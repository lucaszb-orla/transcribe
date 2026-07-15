import XCTest
@testable import Transcribe

final class PermissionPolicyTests: XCTestCase {
    func testCalendarDoesNotParticipateInRequiredPermissions() {
        let permissions = PermissionSnapshot(
            microphone: .granted,
            speechRecognition: .granted,
            screenRecording: .granted,
            calendar: .denied
        )

        XCTAssertTrue(permissions.requiredGranted)
    }

    func testRequiredProgressEndsAtThreeOfThree() {
        let permissions = PermissionSnapshot(
            microphone: .granted,
            speechRecognition: .granted,
            screenRecording: .granted,
            calendar: .notDetermined
        )

        XCTAssertEqual(permissions.grantedRequiredCount, 3)
        XCTAssertEqual(PermissionSnapshot.requiredCount, 3)
    }

    func testAnyMissingRequiredPermissionPreventsRecording() {
        let statuses: [PermissionSnapshot] = [
            PermissionSnapshot(
                microphone: .denied,
                speechRecognition: .granted,
                screenRecording: .granted,
                calendar: .granted
            ),
            PermissionSnapshot(
                microphone: .granted,
                speechRecognition: .notDetermined,
                screenRecording: .granted,
                calendar: .granted
            ),
            PermissionSnapshot(
                microphone: .granted,
                speechRecognition: .granted,
                screenRecording: .denied,
                calendar: .granted
            )
        ]

        XCTAssertTrue(statuses.allSatisfy { !$0.requiredGranted })
    }

    func testFreshInstallWithMissingPermissionsShowsOnboarding() {
        let defaults = makeDefaults()
        let store = OnboardingCompletionStore(defaults: defaults)

        XCTAssertFalse(store.loadOrMigrate(requiredGranted: false))
        XCTAssertNil(defaults.object(forKey: OnboardingCompletionStore.key))
    }

    func testExistingAuthorizedUserIsMigratedWithoutOnboarding() {
        let defaults = makeDefaults()
        let store = OnboardingCompletionStore(defaults: defaults)

        XCTAssertTrue(store.loadOrMigrate(requiredGranted: true))
        XCTAssertTrue(defaults.bool(forKey: OnboardingCompletionStore.key))
    }

    func testCompletedOnboardingPersistsAcrossLaunches() {
        let defaults = makeDefaults()
        OnboardingCompletionStore(defaults: defaults).markCompleted()

        let reloadedStore = OnboardingCompletionStore(defaults: defaults)
        XCTAssertTrue(reloadedStore.loadOrMigrate(requiredGranted: false))
    }

    func testRevokingRequiredPermissionReopensRecovery() {
        let permissions = PermissionSnapshot(
            microphone: .granted,
            speechRecognition: .granted,
            screenRecording: .denied,
            calendar: .granted
        )

        XCTAssertTrue(permissions.needsOnboarding(onboardingCompleted: true))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PermissionPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}
