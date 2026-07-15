import AVFoundation
import CoreAudio
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.lucasbaggiotto.Transcribe", category: "RecordingSession")

/// Owns "Modo Reunião": mic capture + system-audio capture, both fed live to the transcriber.
/// No audio is written to disk (see PRD "Fora do escopo"). Summarization happens after `stop()`.
@Observable
final class RecordingSession {
    enum SessionState {
        case idle
        case recording
        case paused
    }

    private(set) var state: SessionState = .idle
    /// Live microphone level, 0…1, for the on-screen meter.
    private(set) var micLevel: Float = 0

    private let mic = MicrophoneCapture()
    private let systemAudio = SystemAudioCapture()
    private let transcriber = Transcriber()
    private var startedAt: Date?

    /// Called if system-audio capture stops unexpectedly mid-meeting (e.g. Screen Recording
    /// permission revoked, display disconnected) — mic audio keeps being transcribed either way,
    /// but the caller should surface this since the other participants' audio is now missing.
    var onSystemAudioError: ((Error) -> Void)?

    /// Skips feeding audio to the recognizer while paused (both capturers keep running).
    private var paused = false

    var liveText: String { transcriber.liveText }
    var liveSegments: [TranscriptSegment] { transcriber.segments }

    func start(inputDeviceID: AudioDeviceID?, locale: Locale) async throws {
        guard state == .idle else { return }
        startedAt = Date()

        logger.debug("starting transcriber…")
        try await transcriber.start(locale: locale)

        logger.debug("starting mic capture…")
        do {
            try mic.start(deviceID: inputDeviceID) { [weak self] buffer in
                guard let self, !self.paused else { return }
                let level = buffer.meterLevel
                DispatchQueue.main.async { self.micLevel = level }
                self.transcriber.ingest(buffer)
            }
        } catch {
            _ = await transcriber.finish()
            throw error
        }

        logger.debug("starting system audio capture…")
        do {
            try await systemAudio.start(onBuffer: { [weak self] buffer in
                guard let self, !self.paused else { return }
                self.transcriber.ingest(buffer)
            }, onError: { [weak self] error in
                self?.onSystemAudioError?(error)
            })
        } catch {
            mic.stop()
            _ = await transcriber.finish()
            throw error
        }
        logger.debug("recording started")

        state = .recording
    }

    func pause() {
        guard state == .recording else { return }
        paused = true
        micLevel = 0
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        paused = false
        state = .recording
    }

    func stop() async -> (transcript: [TranscriptSegment], startedAt: Date, endedAt: Date) {
        await systemAudio.stop()
        mic.stop()
        micLevel = 0
        let segments = await transcriber.finish()
        state = .idle
        return (segments, startedAt ?? Date(), Date())
    }
}

private extension AVAudioPCMBuffer {
    /// RMS of the first channel mapped to a perceptual 0…1 meter (roughly -50 dB … 0 dB).
    var meterLevel: Float {
        guard let channel = floatChannelData?[0], frameLength > 0 else { return 0 }
        let n = Int(frameLength)
        var sum: Float = 0
        for i in 0..<n {
            let s = channel[i]
            sum += s * s
        }
        let rms = (sum / Float(n)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        return min(1, max(0, (db + 50) / 50))
    }
}
