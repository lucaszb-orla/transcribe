import SwiftUI

/// Chat-style transcript: "Você" bubbles on the right, "Participantes" on the left — much faster to
/// scan who said what than a flat paragraph. Segments with no speaker tag (older meetings, or a
/// manually edited transcript, which collapses to one untagged blob) render as plain text instead of
/// guessing a side. Shared by the live recording view and the saved-meeting detail view.
struct TranscriptBubbleList: View {
    let segments: [TranscriptSegment]
    /// In-progress (not yet finalized) text for each source, shown as a lighter "still speaking" bubble.
    var pendingMe: String = ""
    var pendingOthers: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Self.grouped(segments)) { group in
                TranscriptBubble(speaker: group.speaker, text: group.text, start: group.start)
            }
            if !pendingMe.isEmpty {
                TranscriptBubble(speaker: .me, text: pendingMe, start: nil, isPending: true)
            }
            if !pendingOthers.isEmpty {
                TranscriptBubble(speaker: .others, text: pendingOthers, start: nil, isPending: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Group: Identifiable {
        let id: UUID
        let speaker: Speaker?
        let start: TimeInterval
        let text: String
    }

    /// Merges consecutive same-speaker segments into one "message" — otherwise a speaker mid-sentence
    /// (the recognizer commits several short final segments back to back) turns into a wall of tiny bubbles.
    private static func grouped(_ segments: [TranscriptSegment]) -> [Group] {
        var groups: [Group] = []
        for segment in segments {
            if let last = groups.last, last.speaker == segment.speaker {
                groups[groups.count - 1] = Group(
                    id: last.id, speaker: last.speaker, start: last.start,
                    text: last.text + " " + segment.text
                )
            } else {
                groups.append(Group(id: segment.id, speaker: segment.speaker, start: segment.start, text: segment.text))
            }
        }
        return groups
    }
}

private struct TranscriptBubble: View {
    let speaker: Speaker?
    let text: String
    let start: TimeInterval?
    var isPending: Bool = false

    var body: some View {
        switch speaker {
        case .me:
            HStack {
                Spacer(minLength: 48)
                bubble(tint: Color.accentColor, foreground: .white)
            }
        case .others:
            HStack {
                bubble(tint: nil, foreground: .primary)
                Spacer(minLength: 48)
            }
        case nil:
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bubble(tint: Color?, foreground: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text).textSelection(.enabled)
            if let start {
                Text(Self.mmss(start)).font(.caption2).opacity(0.7)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.quaternary), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isPending ? 0.6 : 1)
    }

    private static func mmss(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
