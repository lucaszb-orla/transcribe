import Foundation
import Observation

/// Local-only persistence: one JSON file per meeting under Application Support.
/// No sync and no backend. See PRD "Armazenamento".
@Observable
final class MeetingStore {
    private(set) var meetings: [Meeting] = []

    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Transcribe/Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var dir = directory
        try? dir.setResourceValues(excluded)
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        meetings = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                (try? Data(contentsOf: url)).flatMap { try? decoder.decode(Meeting.self, from: $0) }
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func save(_ meeting: Meeting) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(meeting)
        try data.write(to: fileURL(for: meeting), options: .atomic)
        reload()
    }

    /// Moves the meeting's file to the Trash rather than deleting it outright, so a mis-click
    /// is recoverable. This matches the HIG preference for undo-able actions over confirmation alerts.
    func delete(_ meeting: Meeting) throws {
        try FileManager.default.trashItem(at: fileURL(for: meeting), resultingItemURL: nil)
        reload()
    }

    func search(_ query: String) -> [Meeting] {
        guard !query.isEmpty else { return meetings }
        let lowered = query.lowercased()
        return meetings.filter {
            $0.title.lowercased().contains(lowered) || $0.fullTranscriptText.lowercased().contains(lowered)
        }
    }

    private func fileURL(for meeting: Meeting) -> URL {
        directory.appendingPathComponent("\(meeting.id.uuidString).json")
    }
}
