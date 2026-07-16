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
    /// Separate recognizer per source (instead of one mixed stream) so segments can be tagged
    /// "Você" vs. "Participantes" — the app already captures these two streams independently.
    private let micTranscriber = Transcriber(speaker: .me)
    private let systemTranscriber = Transcriber(speaker: .others)
    private var startedAt: Date?

    /// Called if system-audio capture stops unexpectedly mid-meeting (e.g. Screen Recording
    /// permission revoked, display disconnected) — mic audio keeps being transcribed either way,
    /// but the caller should surface this since the other participants' audio is now missing.
    var onSystemAudioError: ((Error) -> Void)?

    /// Skips feeding audio to the recognizer while paused (both capturers keep running).
    private var paused = false

    var liveText: String {
        var lines = liveSegments.map { "\($0.speaker?.label ?? Speaker.others.label): \($0.text)" }
        if !micTranscriber.volatileText.isEmpty {
            lines.append("\(Speaker.me.label): \(micTranscriber.volatileText)")
        }
        if !systemTranscriber.volatileText.isEmpty {
            lines.append("\(Speaker.others.label): \(systemTranscriber.volatileText)")
        }
        return lines.joined(separator: "\n")
    }

    var liveSegments: [TranscriptSegment] {
        deduped(mic: micTranscriber.segments, systemAudio: systemTranscriber.segments)
    }

    /// The in-progress phrase for each source, not yet finalized — used to show a "still speaking" bubble.
    var micVolatileText: String { micTranscriber.volatileText }
    var systemVolatileText: String { systemTranscriber.volatileText }

    func start(inputDeviceID: AudioDeviceID?, locale: Locale) async throws {
        guard state == .idle else { return }
        startedAt = Date()

        logger.debug("starting transcribers…")
        try await micTranscriber.start(locale: locale)
        try await systemTranscriber.start(locale: locale)

        logger.debug("starting mic capture…")
        do {
            try mic.start(deviceID: inputDeviceID) { [weak self] buffer in
                guard let self, !self.paused else { return }
                let level = buffer.meterLevel
                DispatchQueue.main.async { self.micLevel = level }
                self.micTranscriber.ingest(buffer)
            }
        } catch {
            _ = await micTranscriber.finish()
            _ = await systemTranscriber.finish()
            throw error
        }

        logger.debug("starting system audio capture…")
        do {
            try await systemAudio.start(onBuffer: { [weak self] buffer in
                guard let self, !self.paused else { return }
                self.systemTranscriber.ingest(buffer)
            }, onError: { [weak self] error in
                self?.onSystemAudioError?(error)
            })
        } catch {
            mic.stop()
            _ = await micTranscriber.finish()
            _ = await systemTranscriber.finish()
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
        async let micSegments = micTranscriber.finish()
        async let systemSegments = systemTranscriber.finish()
        let segments = await deduped(mic: micSegments, systemAudio: systemSegments)
        state = .idle
        return (segments, startedAt ?? Date(), Date())
    }

    /// Without headphones, the mic often picks up the Mac's own speaker output (the other
    /// participants' audio), so the same utterance gets transcribed twice: correctly under
    /// "Participantes" (system audio) and again, muffled, mistagged "Você" (mic). System audio
    /// is the ground truth for what others said, so any mic segment that's a near-duplicate —
    /// close in time and similar in text — of a system-audio segment gets dropped.
    // ponytail: naive O(n*m) scan + word-overlap heuristic, good enough for a meeting-length
    // transcript; revisit with better matching if leakage still slips through in practice.
    private func deduped(mic: [TranscriptSegment], systemAudio: [TranscriptSegment]) -> [TranscriptSegment] {
        let timeWindow: TimeInterval = 3
        let similarityThreshold = 0.5
        let keptMic = mic.filter { micSegment in
            !systemAudio.contains { systemSegment in
                abs(systemSegment.start - micSegment.start) <= timeWindow
                    && micSegment.text.echoSimilarity(to: systemSegment.text) >= similarityThreshold
            }
        }
        return (keptMic + systemAudio).sorted { $0.start < $1.start }
    }
}

private extension String {
    /// Jaccard similarity (0…1) of normalized word sets — a cheap stand-in for "are these
    /// the same utterance", tolerant of the mic's leaked copy being a bit noisier/lower-quality.
    func echoSimilarity(to other: String) -> Double {
        let a = normalizedWordSet
        let b = other.normalizedWordSet
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        guard intersection > 0 else { return 0 }
        return Double(intersection) / Double(a.union(b).count)
    }

    private var normalizedWordSet: Set<String> {
        Set(lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
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
