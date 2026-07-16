import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.lucasbaggiotto.Transcribe", category: "AppState")

enum AppMode {
    case standby
    case meeting
}

/// Live state for one in-flight "enviar pro Claude Code" run. Ephemeral — only lives while the app
/// is open; the final `DevSpecResult` is what gets persisted onto the `Meeting`.
@MainActor
@Observable
final class DevSpecRunState {
    var log: String = ""
    var isRunning = true
    var result: DevSpecResult?
    var errorMessage: String?
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
    private var autoStopTask: Task<Void, Never>?
    /// When set, the current recording is a continuation and its segments append to this meeting.
    private var continuationBase: Meeting?

    var isContinuing: Bool { continuationBase != nil }

    var suggestion: MeetingSuggestion? { calendarMonitor.suggestion }
    var liveTranscript: [TranscriptSegment] { recordingSession?.liveSegments ?? [] }
    var liveText: String { recordingSession?.liveText ?? "" }
    var livePendingMe: String { recordingSession?.micVolatileText ?? "" }
    var livePendingOthers: String { recordingSession?.systemVolatileText ?? "" }
    var isPaused: Bool { recordingSession?.state == .paused }
    var micLevel: Float { recordingSession?.micLevel ?? 0 }
    var recordingStartedAt: Date?
    /// Set when a recording just ended, so the list can jump to it for summary review.
    var pendingReviewMeetingID: UUID?

    /// In-flight "enviar pro Claude Code" runs, keyed by `DevSpec.id`.
    var devSpecRuns: [UUID: DevSpecRunState] = [:]

    init() {
        Task { await self.start() }
    }

    func start() async {
        calendarMonitor.onNewCandidate = { [weak self] suggestion in
            Task { @MainActor in
                guard let self, self.settings.autoRecordFromCalendar, self.mode == .standby else { return }
                await self.startMeeting(from: suggestion)
            }
        }
        await calendarMonitor.start()
    }

    func startMeeting(from suggestion: MeetingSuggestion? = nil) async {
        guard mode == .standby, ensurePermissions() else { return }
        continuationBase = nil
        pendingSuggestion = suggestion
        calendarMonitor.dismissCurrentSuggestion()

        guard await beginSession() else { return }
        // Auto-stop at the event's end when auto-recording is on and this came from the calendar.
        if settings.autoRecordFromCalendar, let end = suggestion?.end {
            scheduleAutoStop(at: end)
        }
    }

    /// Resume transcribing into an existing meeting — new speech appends to its transcript.
    func continueMeeting(_ base: Meeting) async {
        guard mode == .standby, ensurePermissions() else { return }
        pendingSuggestion = nil
        continuationBase = base
        if !(await beginSession()) { continuationBase = nil }
    }

    private func ensurePermissions() -> Bool {
        permissions.refresh()
        guard permissions.allGranted else {
            errorMessage = "Conceda acesso ao microfone, reconhecimento de fala, calendário e gravação de tela antes de gravar."
            return false
        }
        return true
    }

    private func beginSession() async -> Bool {
        // Flip to .meeting *before* the first await: this method only ever runs on the MainActor,
        // and actors are only reentrant at suspension points, so setting this synchronously closes
        // the window where a concurrent startMeeting/continueMeeting call (e.g. a calendar
        // auto-start racing a manual start) could pass the `mode == .standby` guard twice and orphan
        // the first RecordingSession (mic/screen capture left running with nothing referencing it).
        mode = .meeting
        let session = RecordingSession()
        // SCStream's delegate callback can land on an arbitrary queue — hop to the MainActor before
        // touching AppState.
        session.onSystemAudioError = { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = "O áudio do sistema parou de ser capturado: \(error.localizedDescription)"
            }
        }
        recordingSession = session
        do {
            try await session.start(inputDeviceID: settings.resolvedInputDeviceID, locale: settings.transcriptionLocale)
            recordingStartedAt = Date()
            return true
        } catch {
            logger.error("beginSession failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível iniciar a gravação: \(error.localizedDescription)"
            recordingSession = nil
            mode = .standby
            return false
        }
    }

    func pauseMeeting() {
        recordingSession?.pause()
    }

    func resumeMeeting() {
        recordingSession?.resume()
    }

    private func scheduleAutoStop(at end: Date) {
        autoStopTask?.cancel()
        let seconds = max(0, end.timeIntervalSinceNow)
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.mode == .meeting else { return }
            await self.endMeeting()
        }
    }

    func endMeeting() async {
        guard mode == .meeting, let session = recordingSession else { return }
        autoStopTask?.cancel()
        autoStopTask = nil
        mode = .standby
        recordingSession = nil
        recordingStartedAt = nil

        let (segments, startedAt, endedAt) = await session.stop()

        // Continuation: append the new segments (offset past the existing recording) to the base meeting.
        if let base = continuationBase {
            continuationBase = nil
            pendingSuggestion = nil
            var updated = base
            let offset = max(0, (base.endedAt ?? base.startedAt).timeIntervalSince(base.startedAt))
            updated.transcript.append(contentsOf: segments.map {
                TranscriptSegment(start: $0.start + offset, text: $0.text, speaker: $0.speaker)
            })
            updated.endedAt = endedAt
            // The old summary/action items only cover the meeting up to the previous stop point —
            // clear them so the detail view doesn't show a stale summary as if it were current.
            updated.summaryBullets = []
            updated.summaryProse = nil
            updated.actionItems = []
            updated.doneActionItems = nil
            do {
                try store.save(updated)
                maybeAutoExport(updated)
            } catch {
                logger.error("failed to save continued meeting: \(String(describing: error), privacy: .public)")
                errorMessage = "Não foi possível salvar a reunião continuada: \(error.localizedDescription)"
            }
            pendingReviewMeetingID = updated.id
            return
        }

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
            actionItems: []
        )

        do {
            try store.save(meeting)
            maybeAutoExport(meeting)
        } catch {
            logger.error("failed to save meeting: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível salvar a reunião: \(error.localizedDescription)"
        }
        pendingReviewMeetingID = meeting.id
        pendingSuggestion = nil
    }

    /// Opt-in (Ajustes > Salvamento automático): mirrors the just-saved transcript as a Markdown
    /// file in the user's chosen folder. Best-effort — a failure here doesn't affect the meeting,
    /// which is already safely stored in the app's own JSON store.
    private func maybeAutoExport(_ meeting: Meeting) {
        guard settings.autoExportEnabled, let folder = settings.autoExportFolderURL else { return }
        do {
            try MeetingExporter.autoSave(meeting, to: folder)
        } catch {
            errorMessage = "A reunião foi salva, mas não deu pra copiar em Markdown para a pasta escolhida: \(error.localizedDescription)"
        }
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

    /// Splits a saved meeting into candidate dev specs and persists them. Returns the updated meeting.
    func generateDevSpecs(for meeting: Meeting) async throws -> Meeting {
        let specs = try await Summarizer.generateDevSpecs(
            transcript: meeting.fullTranscriptText,
            calendarContext: Self.calendarContext(for: meeting)
        )
        var updated = meeting
        updated.devSpecs = specs
        try store.save(updated)
        return updated
    }

    /// Kicks off the Claude Code automation for one spec inside `repoPath`, streaming progress into
    /// `devSpecRuns[spec.id]` and persisting the final `DevSpecResult` onto the meeting.
    func runDevSpec(_ spec: DevSpec, in meeting: Meeting, repoPath: String) {
        let state = DevSpecRunState()
        devSpecRuns[spec.id] = state
        settings.lastUsedRepoPath = repoPath

        var spec = spec
        spec.repoPath = repoPath
        let meetingMarkdown = MeetingExporter.markdown(meeting)

        Task {
            do {
                let result = try await ClaudeCodeRunner.run(
                    spec: spec,
                    meetingMarkdown: meetingMarkdown,
                    repoPath: repoPath
                ) { [weak state] line in
                    state?.log += (state?.log.isEmpty == false ? "\n" : "") + line
                }
                state.result = result
                state.isRunning = false
                persist(spec: spec, result: result, in: meeting.id)
            } catch {
                state.errorMessage = error.localizedDescription
                state.isRunning = false
            }
        }
    }

    private func persist(spec: DevSpec, result: DevSpecResult, in meetingID: UUID) {
        guard var meeting = store.meetings.first(where: { $0.id == meetingID }) else { return }
        var updatedSpec = spec
        updatedSpec.result = result
        meeting.updateDevSpec(updatedSpec)
        do {
            try store.save(meeting)
        } catch {
            logger.error("failed to persist dev spec result: \(String(describing: error), privacy: .public)")
        }
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
