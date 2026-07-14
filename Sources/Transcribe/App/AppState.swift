import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.lucasbaggiotto.Transcribe", category: "AppState")

enum AppMode {
    case standby
    case meeting
}

/// The app's top-level state machine: Standby (watching the calendar) ↔ Meeting (recording).
@MainActor
@Observable
final class AppState {
    private(set) var mode: AppMode = .standby
    var errorMessage: String?

    let calendarMonitor = CalendarMonitor()
    let store = MeetingStore()
    let permissions = PermissionsManager()
    let settings = AppSettings()
    let summaryPresets = SummaryPresetStore()

    private var recordingSession: RecordingSession?
    private var pendingSuggestion: MeetingSuggestion?

    var suggestion: MeetingSuggestion? { calendarMonitor.suggestion }
    var liveTranscript: [TranscriptSegment] { recordingSession?.liveSegments ?? [] }
    var liveText: String { recordingSession?.liveText ?? "" }
    var isPaused: Bool { recordingSession?.state == .paused }
    var micLevel: Float { recordingSession?.micLevel ?? 0 }
    var recordingStartedAt: Date?
    /// Set when a recording just ended, so the list can jump to it for summary review.
    var pendingReviewMeetingID: UUID?

    init() {
        Task { await self.start() }
    }

    func start() async {
        await calendarMonitor.start()
    }

    func startMeeting(from suggestion: MeetingSuggestion? = nil) async {
        guard mode == .standby else { return }
        permissions.refresh()
        guard permissions.allGranted else {
            errorMessage = "Conceda acesso ao microfone, reconhecimento de fala, calendário e gravação de tela antes de gravar."
            return
        }
        pendingSuggestion = suggestion
        calendarMonitor.dismissCurrentSuggestion()

        let session = RecordingSession()
        recordingSession = session
        do {
            try await session.start(inputDeviceID: settings.resolvedInputDeviceID, locale: settings.transcriptionLocale)
            recordingStartedAt = Date()
            mode = .meeting
        } catch {
            logger.error("startMeeting failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível iniciar a gravação: \(error.localizedDescription)"
            recordingSession = nil
        }
    }

    func pauseMeeting() {
        recordingSession?.pause()
    }

    func resumeMeeting() {
        recordingSession?.resume()
    }

    func endMeeting() async {
        guard mode == .meeting, let session = recordingSession else { return }
        mode = .standby
        recordingSession = nil
        recordingStartedAt = nil

        let (segments, startedAt, endedAt) = await session.stop()

        // Save the transcript immediately; summarization is now on-demand (the detail view asks the
        // user which format/options they want) so nothing is lost even if they never summarize.
        let title = pendingSuggestion?.title ?? "Reunião de \(startedAt.formatted(date: .abbreviated, time: .shortened))"
        let meeting = Meeting(
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            calendarEventTitle: pendingSuggestion?.title,
            participants: pendingSuggestion?.participants ?? [],
            transcript: segments,
            summaryBullets: [],
            actionItems: [],
            audioFileName: nil
        )

        try? store.save(meeting)
        pendingReviewMeetingID = meeting.id
        pendingSuggestion = nil
    }

    /// Generate (or regenerate) a summary for a saved meeting with the user's chosen options.
    /// Returns the updated, saved meeting.
    func generateSummary(for meeting: Meeting, options: SummaryOptions) async throws -> Meeting {
        let result = try await Summarizer.summarize(
            transcript: meeting.fullTranscriptText,
            calendarContext: Self.calendarContext(for: meeting),
            options: options
        )

        var updated = meeting
        if !result.title.isEmpty { updated.title = result.title }
        updated.summaryBullets = result.bullets
        updated.summaryProse = result.prose
        updated.actionItems = result.actionItems
        try store.save(updated)
        return updated
    }

    /// Generate a follow-up recap message (e-mail/Slack) for a saved meeting. Returns plain text.
    func generateFollowUp(for meeting: Meeting, tone: FollowUpDrafter.Tone) async throws -> String {
        try await FollowUpDrafter.draft(
            transcript: meeting.fullTranscriptText,
            calendarContext: Self.calendarContext(for: meeting),
            tone: tone
        )
    }

    private static func calendarContext(for meeting: Meeting) -> String? {
        let parts = meeting.participants
        let eventTitle = meeting.calendarEventTitle
        if eventTitle == nil, parts.isEmpty { return nil }
        var ctx = "Título: \(eventTitle ?? meeting.title)"
        if !parts.isEmpty { ctx += ", participantes: \(parts.joined(separator: ", "))" }
        return ctx
    }
}
