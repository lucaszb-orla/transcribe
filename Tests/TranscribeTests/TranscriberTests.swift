import XCTest
@testable import Transcribe

final class TranscriberTests: XCTestCase {
    func testWithTimeoutReturnsTrueWhenOperationFinishesFirst() async {
        let finishedInTime = await Transcriber.withTimeout(seconds: 5) {
            // Fast operation: should win the race easily.
        }
        XCTAssertTrue(finishedInTime)
    }

    func testWithTimeoutReturnsFalseWhenOperationHangs() async {
        let start = Date()
        let finishedInTime = await Transcriber.withTimeout(seconds: 0.2) {
            // Simulates a stuck `finalizeAndFinishThroughEndOfInput()`: never returns on its own.
            try? await Task.sleep(for: .seconds(60))
        }
        XCTAssertFalse(finishedInTime)
        // The call itself must return promptly, not after the stuck operation's own delay.
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
