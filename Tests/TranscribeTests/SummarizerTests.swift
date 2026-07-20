import XCTest
@testable import Transcribe

final class SummarizerTests: XCTestCase {
    func testShortTranscriptStaysAsOneChunk() {
        let transcript = "Você: oi\nParticipantes: tudo bem?"
        XCTAssertEqual(Summarizer.chunkedForContext(transcript), [transcript])
    }

    /// This is exactly the case that used to fail: a transcript long enough to exceed the
    /// on-device model's context window in one shot must split into more than one chunk so
    /// `summarize` can take the chunk-then-merge path instead of throwing `exceededContextWindowSize`.
    func testLongTranscriptSplitsIntoMultipleChunks() {
        let line = "Participantes: " + String(repeating: "um ponto de discussão qualquer ", count: 20)
        let longTranscript = Array(repeating: line, count: 400).joined(separator: "\n")

        let chunks = Summarizer.chunkedForContext(longTranscript)

        XCTAssertGreaterThan(chunks.count, 1)
        // No content lost or reordered by the split.
        XCTAssertEqual(chunks.joined(separator: "\n"), longTranscript)
    }
}
