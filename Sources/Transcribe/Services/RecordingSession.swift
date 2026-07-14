import AVFoundation
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.lucasbaggiotto.Transcribe", category: "RecordingSession")

/// Owns the three moving parts of "Modo Reunião": mixed audio capture and live transcription.
/// Summarization happens after `stop()`, once the caller has the calendar context to pass along.
@Observable
final class RecordingSession {
    enum SessionState {
        case idle
        case recording
    }

    private(set) var state: SessionState = .idle

    private let mixer = AudioMixer()
    private let systemAudio = SystemAudioCapture()
    private let transcriber = Transcriber()
    private var startedAt: Date?

    var liveSegments: [TranscriptSegment] { transcriber.segments }

    func start() async throws {
        guard state == .idle else { return }
        startedAt = Date()

        logger.debug("starting transcriber…")
        try await transcriber.start()
        logger.debug("transcriber started, starting mixer…")
        try mixer.start { [weak self] buffer in
            self?.transcriber.ingest(buffer)
        }
        logger.debug("mixer started, starting system audio capture…")
        try await systemAudio.start { [weak self] buffer in
            self?.mixer.scheduleSystemAudio(buffer)
        }
        logger.debug("system audio capture started")

        state = .recording
    }

    func stop() async -> (transcript: [TranscriptSegment], startedAt: Date, endedAt: Date) {
        await systemAudio.stop()
        mixer.stop()
        let segments = await transcriber.finish()
        state = .idle
        return (segments, startedAt ?? Date(), Date())
    }
}
