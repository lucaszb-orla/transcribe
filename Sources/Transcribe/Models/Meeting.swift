import Foundation

/// Which capture source produced a segment. Not identity-based diarization — just the two
/// streams the app already records separately (your mic vs. everyone else, mixed together
/// via ScreenCaptureKit).
enum Speaker: String, Codable {
    case me, others

    var label: String {
        switch self {
        case .me: "Você"
        case .others: "Participantes"
        }
    }
}

struct TranscriptSegment: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var start: TimeInterval
    var text: String
    /// Optional so older saved meetings (recorded before speaker splitting existed) still decode.
    var speaker: Speaker? = nil
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
    var summaryProse: String? = nil
    var actionItems: [String]
    /// Texts of the action items the user has ticked off. Optional so older saved meetings decode.
    /// ponytail: keyed by text (action items aren't editable), so duplicate texts toggle together.
    var doneActionItems: [String]? = nil
    /// Implementation tasks extracted from this meeting, each optionally sent to Claude Code.
    /// Optional so older saved meetings decode.
    var devSpecs: [DevSpec]? = nil

    /// True once a summary has been generated (either format).
    var hasSummary: Bool {
        !summaryBullets.isEmpty || !(summaryProse ?? "").isEmpty
    }

    func isActionDone(_ item: String) -> Bool {
        doneActionItems?.contains(item) ?? false
    }

    mutating func toggleActionDone(_ item: String) {
        var done = doneActionItems ?? []
        if let i = done.firstIndex(of: item) { done.remove(at: i) } else { done.append(item) }
        doneActionItems = done
    }

    var devSpecsOrEmpty: [DevSpec] {
        devSpecs ?? []
    }

    mutating func updateDevSpec(_ spec: DevSpec) {
        var specs = devSpecsOrEmpty
        if let i = specs.firstIndex(where: { $0.id == spec.id }) {
            specs[i] = spec
        } else {
            specs.append(spec)
        }
        devSpecs = specs
    }

    mutating func removeDevSpec(_ id: UUID) {
        devSpecs?.removeAll { $0.id == id }
    }

    var fullTranscriptText: String {
        transcript.map { segment in
            guard let speaker = segment.speaker else { return segment.text }
            return "\(speaker.label): \(segment.text)"
        }.joined(separator: "\n")
    }

    /// v1 has no per-speaker/per-segment editing UI — editing rewrites the transcript as a
    /// single blob and loses the original per-segment timestamps/speaker tags. Fine until phase 2
    /// adds real diarization, at which point this needs segment-aware editing.
    var editableTranscriptText: String {
        get { fullTranscriptText }
        set { transcript = [TranscriptSegment(start: 0, text: newValue)] }
    }
}
