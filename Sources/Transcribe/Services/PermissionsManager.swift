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

/// Explicitly requests and tracks the three OS permissions Transcribe needs, so onboarding can
/// show real status instead of relying on AVAudioEngine/SpeechAnalyzer's implicit (and flaky)
/// first-use prompts.
@MainActor
@Observable
final class PermissionsManager {
    private(set) var microphone: PermissionStatus = .notDetermined
    private(set) var calendar: PermissionStatus = .notDetermined
    private(set) var speechRecognition: PermissionStatus = .notDetermined
    private(set) var screenRecording: PermissionStatus = .notDetermined

    var allGranted: Bool {
        microphone == .granted && calendar == .granted && speechRecognition == .granted && screenRecording == .granted
    }

    init() {
        refresh()
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
