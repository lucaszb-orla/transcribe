import AVFoundation
import CoreGraphics
import EventKit
import Observation
import Speech

enum PermissionStatus {
    case notDetermined
    case granted
    case denied
}

struct PermissionSnapshot {
    static let requiredCount = 3

    let microphone: PermissionStatus
    let speechRecognition: PermissionStatus
    let screenRecording: PermissionStatus
    let calendar: PermissionStatus

    var grantedRequiredCount: Int {
        [microphone, speechRecognition, screenRecording].count { $0 == .granted }
    }

    var requiredGranted: Bool {
        grantedRequiredCount == Self.requiredCount
    }

    func needsOnboarding(onboardingCompleted: Bool) -> Bool {
        !requiredGranted || !onboardingCompleted
    }
}

struct OnboardingCompletionStore {
    static let key = "onboardingCompleted"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Existing installs predate the completion key. If their required permissions are already
    /// granted at launch, migrate them silently instead of presenting onboarding again.
    func loadOrMigrate(requiredGranted: Bool) -> Bool {
        if defaults.object(forKey: Self.key) != nil {
            return defaults.bool(forKey: Self.key)
        }
        guard requiredGranted else { return false }
        defaults.set(true, forKey: Self.key)
        return true
    }

    func markCompleted() {
        defaults.set(true, forKey: Self.key)
    }
}

/// Explicitly requests and tracks the OS permissions Transcribe uses, separating the three
/// recording requirements from the optional Calendar integration.
@MainActor
@Observable
final class PermissionsManager {
    private(set) var microphone: PermissionStatus = .notDetermined
    private(set) var calendar: PermissionStatus = .notDetermined
    private(set) var speechRecognition: PermissionStatus = .notDetermined
    private(set) var screenRecording: PermissionStatus = .notDetermined
    private(set) var onboardingCompleted = false

    private let onboardingStore: OnboardingCompletionStore

    var snapshot: PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphone,
            speechRecognition: speechRecognition,
            screenRecording: screenRecording,
            calendar: calendar
        )
    }

    var grantedRequiredCount: Int { snapshot.grantedRequiredCount }
    var requiredGranted: Bool { snapshot.requiredGranted }
    var needsOnboarding: Bool {
        snapshot.needsOnboarding(onboardingCompleted: onboardingCompleted)
    }

    init(defaults: UserDefaults = .standard) {
        onboardingStore = OnboardingCompletionStore(defaults: defaults)
        refresh()
        onboardingCompleted = onboardingStore.loadOrMigrate(requiredGranted: requiredGranted)
    }

    func refresh() {
        microphone = Self.status(for: AVCaptureDevice.authorizationStatus(for: .audio))
        calendar = Self.status(for: EKEventStore.authorizationStatus(for: .event))
        speechRecognition = Self.status(for: SFSpeechRecognizer.authorizationStatus())
        if CGPreflightScreenCaptureAccess() {
            screenRecording = .granted
        } else if screenRecording != .denied {
            screenRecording = .notDetermined
        }
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = granted ? .granted : .denied
    }

    func requestCalendar() async {
        do {
            let granted = try await EKEventStore().requestFullAccessToEvents()
            calendar = granted ? .granted : .denied
        } catch {
            calendar = .denied
        }
    }

    func requestSpeechRecognition() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        speechRecognition = Self.status(for: status)
    }

    /// Screen Recording has no async request API: `CGRequestScreenCaptureAccess` shows the system
    /// prompt only the first time; once denied, granting it requires the user to flip it in System
    /// Settings and relaunch Transcribe (ScreenCaptureKit doesn't pick up a same-run change).
    func requestScreenRecording() {
        screenRecording = CGRequestScreenCaptureAccess() ? .granted : .denied
    }

    func completeOnboarding() {
        guard requiredGranted else { return }
        onboardingStore.markCompleted()
        onboardingCompleted = true
    }

    private static func status(for status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private static func status(for status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: .granted
        case .denied, .restricted, .writeOnly: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private static func status(for status: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}
