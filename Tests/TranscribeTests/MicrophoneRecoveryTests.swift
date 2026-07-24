import XCTest
@testable import Transcribe

final class MicrophoneRecoveryTests: XCTestCase {
    func testConfigurationChangesAreCoalescedWhileRestartIsPending() {
        var state = MicrophoneRecoveryState()
        state.start()

        XCTAssertTrue(state.requestRestart())
        XCTAssertFalse(state.requestRestart())

        state.finishRestart()
        XCTAssertTrue(state.requestRestart())
    }

    func testConfigurationChangesAreIgnoredAfterCaptureStops() {
        var state = MicrophoneRecoveryState()
        state.start()
        state.stop()

        XCTAssertFalse(state.requestRestart())
    }
}
