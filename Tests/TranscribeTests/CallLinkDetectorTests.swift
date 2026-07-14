import XCTest
@testable import Transcribe

final class CallLinkDetectorTests: XCTestCase {
    func testDetectsEventURLDirectly() {
        let url = URL(string: "https://zoom.us/j/123456789")!
        XCTAssertEqual(CallLinkDetector.detect(url: url, location: nil, notes: nil), url)
    }

    func testDetectsFaceTimeScheme() {
        let url = URL(string: "facetime:someone@example.com")!
        XCTAssertEqual(CallLinkDetector.detect(url: url, location: nil, notes: nil), url)
    }

    func testFindsLinkInNotesWhenEventURLIsAbsent() {
        let notes = "Pauta:\n1. Revisão\n\nEntrar: https://meet.google.com/abc-defg-hij"
        let result = CallLinkDetector.detect(url: nil, location: nil, notes: notes)
        XCTAssertEqual(result?.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testFindsLinkInLocationForTeams() {
        let location = "Microsoft Teams Meeting - https://teams.microsoft.com/l/meetup-join/xyz"
        let result = CallLinkDetector.detect(url: nil, location: location, notes: nil)
        XCTAssertEqual(result?.host, "teams.microsoft.com")
    }

    func testIgnoresUnrelatedURLsAndText() {
        let url = URL(string: "https://example.com/agenda.pdf")!
        let notes = "Ver material em https://example.com/slides"
        XCTAssertNil(CallLinkDetector.detect(url: url, location: nil, notes: notes))
    }

    func testInPersonMeetingWithNoLinkReturnsNil() {
        let result = CallLinkDetector.detect(url: nil, location: "Sala de reunião 3", notes: "Levar o laptop")
        XCTAssertNil(result)
    }
}
