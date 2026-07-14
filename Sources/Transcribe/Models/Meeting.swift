import Foundation

struct TranscriptSegment: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var start: TimeInterval
    var text: String
}

struct Meeting: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var calendarEventTitle: String?
    var participants: [String]
    var transcript: [TranscriptSegment]
    var summaryBullets: [String]
    var actionItems: [String]
    var audioFileName: String?

    var fullTranscriptText: String {
        transcript.map(\.text).joined(separator: " ")
    }

    /// v1 has no per-speaker/per-segment editing UI — editing rewrites the transcript as a
    /// single blob and loses the original per-segment timestamps. Fine until phase 2 adds
    /// diarization (see PRD "Próximos passos"), at which point this needs segment-aware editing.
    var editableTranscriptText: String {
        get { fullTranscriptText }
        set { transcript = [TranscriptSegment(start: 0, text: newValue)] }
    }
}
