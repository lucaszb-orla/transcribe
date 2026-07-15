import AppKit
import Foundation
import os

/// Renders a `Meeting` as Markdown or plain text for copying/sharing, and drives
/// the "Exportar…" save panel. On-device, no dependencies (PRD).
enum MeetingExporter {
    private static let log = Logger(subsystem: "com.lucasbaggiotto.Transcribe", category: "MeetingExporter")

    static func markdown(_ meeting: Meeting) -> String {
        render(meeting, md: true)
    }

    static func plainText(_ meeting: Meeting) -> String {
        render(meeting, md: false)
    }

    private static func render(_ m: Meeting, md: Bool) -> String {
        var out: [String] = []

        out.append(md ? "# \(m.title)" : m.title)
        out.append(dateLine(m))

        if !m.participants.isEmpty {
            let label = md ? "**Participantes:** " : "Participantes: "
            out.append(label + m.participants.joined(separator: ", "))
        }

        if let prose = m.summaryProse, !prose.isEmpty {
            out.append(section("Resumo", body: prose, md: md))
        } else if !m.summaryBullets.isEmpty {
            let bullets = m.summaryBullets.map { "- \($0)" }.joined(separator: "\n")
            out.append(section("Resumo", body: bullets, md: md))
        }

        if !m.actionItems.isEmpty {
            let items = m.actionItems.map { md ? "- [ ] \($0)" : "- \($0)" }.joined(separator: "\n")
            out.append(section("Itens de ação", body: items, md: md))
        }

        let transcript = m.fullTranscriptText
        if !transcript.isEmpty {
            out.append(section("Transcrição", body: transcript, md: md))
        }

        return out.joined(separator: "\n\n") + "\n"
    }

    private static func section(_ title: String, body: String, md: Bool) -> String {
        (md ? "## \(title)" : "\(title.uppercased())") + "\n\n" + body
    }

    private static func dateLine(_ m: Meeting) -> String {
        var line = m.startedAt.formatted(date: .long, time: .shortened)
        if let end = m.endedAt {
            line += " – " + end.formatted(date: .omitted, time: .shortened)
        }
        return line
    }

    @MainActor static func copyToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    /// Writes the Markdown transcript straight to `folder`, no dialog — used by the opt-in
    /// auto-export setting right after a meeting is saved.
    @MainActor static func autoSave(_ meeting: Meeting, to folder: URL) {
        let url = folder.appendingPathComponent(suggestedFilename(meeting))
        do {
            try markdown(meeting).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            log.error("Falha ao salvar automaticamente: \(error.localizedDescription)")
        }
    }

    @MainActor static func exportToFile(_ meeting: Meeting) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename(meeting)
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try markdown(meeting).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // ponytail: swallow write errors after logging; add a user alert if this proves confusing.
            log.error("Falha ao exportar reunião: \(error.localizedDescription)")
        }
    }

    private static func suggestedFilename(_ m: Meeting) -> String {
        let date = m.startedAt.formatted(.iso8601.year().month().day())
        let safeTitle = m.title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safeTitle.isEmpty ? "Reuniao" : safeTitle
        return "\(base) - \(date).md"
    }
}
