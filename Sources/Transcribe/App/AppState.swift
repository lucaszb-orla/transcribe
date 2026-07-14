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

    private var recordingSession: RecordingSession?
    private var pendingSuggestion: MeetingSuggestion?

    var suggestion: MeetingSuggestion? { calendarMonitor.suggestion }
    var liveTranscript: [TranscriptSegment] { recordingSession?.liveSegments ?? [] }

    init() {
        Task { await self.start() }
    }

    func start() async {
        await calendarMonitor.start()
    }

    func startMeeting(from suggestion: MeetingSuggestion? = nil) async {
        guard mode == .standby else { return }
        guard permissions.allGranted else {
            errorMessage = "Conceda acesso ao microfone, reconhecimento de fala e calendário antes de gravar."
            return
        }
        pendingSuggestion = suggestion
        calendarMonitor.dismissCurrentSuggestion()

        let session = RecordingSession()
        recordingSession = session
        do {
            try await session.start()
            mode = .meeting
        } catch {
            logger.error("startMeeting failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível iniciar a gravação: \(error.localizedDescription)"
            recordingSession = nil
        }
    }

    func endMeeting() async {
        guard mode == .meeting, let session = recordingSession else { return }
        mode = .standby
        recordingSession = nil

        let (segments, startedAt, endedAt) = await session.stop()
        let transcriptText = segments.map(\.text).joined(separator: " ")

        var title = pendingSuggestion?.title ?? "Reunião de \(startedAt.formatted(date: .abbreviated, time: .shortened))"
        var summaryBullets: [String] = []
        var actionItems: [String] = []

        if !transcriptText.isEmpty {
            do {
                let calendarContext = pendingSuggestion.map {
                    "Título: \($0.title), participantes: \($0.participants.joined(separator: ", "))"
                }
                let summary = try await Summarizer.summarize(transcript: transcriptText, calendarContext: calendarContext)
                title = summary.title
                summaryBullets = summary.bullets
                actionItems = summary.actionItems
            } catch {
                logger.error("summarize failed: \(String(describing: error), privacy: .public)")
                errorMessage = "Transcrição salva, mas o resumo automático falhou: \(error.localizedDescription)"
            }
        }

        let meeting = Meeting(
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            calendarEventTitle: pendingSuggestion?.title,
            participants: pendingSuggestion?.participants ?? [],
            transcript: segments,
            summaryBullets: summaryBullets,
            actionItems: actionItems,
            audioFileName: nil
        )

        try? store.save(meeting)
        pendingSuggestion = nil
    }
}
