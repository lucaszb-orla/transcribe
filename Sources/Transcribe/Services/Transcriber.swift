import AVFoundation
import CoreMedia
import Observation
import OSLog
import Speech

private let logger = Logger(subsystem: "com.lucasbaggiotto.Transcribe", category: "Transcriber")

/// Wraps the on-device `SpeechAnalyzer` / `SpeechTranscriber` to turn a live audio stream into
/// timestamped text, streaming partial ("volatile") results for live feedback. No custom vocabulary
/// (see PRD risks on proper-noun/acronym accuracy, WhisperKit as fallback).
///
/// One instance handles a single audio source (mic or system audio) so its segments can be
/// tagged with `speaker`. `RecordingSession` runs two of these to split "Você" vs.
/// "Participantes" without needing real diarization.
@Observable
final class Transcriber {
    enum TranscriberError: Error {
        case localeNotSupported
        case noCompatibleAudioFormat
    }

    let speaker: Speaker

    init(speaker: Speaker) {
        self.speaker = speaker
    }

    /// Finalized segments (stable, used for the saved transcript).
    private(set) var segments: [TranscriptSegment] = []
    /// The in-progress phrase the recognizer hasn't finalized yet. It is shown live, then replaced.
    private(set) var volatileText: String = ""

    /// What the recording UI displays: everything finalized so far plus the current partial phrase.
    var liveText: String {
        (segments.map(\.text) + [volatileText])
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?

    private let ingestQueue = DispatchQueue(label: "com.lucasbaggiotto.Transcribe.ingest")
    private var converters: [String: AVAudioConverter] = [:]

    func start(locale: Locale = .current) async throws {
        logger.debug("device locale = \(locale.identifier(.bcp47), privacy: .public)")
        guard let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            logger.error("no supported SpeechTranscriber locale equivalent to \(locale.identifier(.bcp47), privacy: .public)")
            throw TranscriberError.localeNotSupported
        }
        logger.debug("resolved locale = \(resolvedLocale.identifier(.bcp47), privacy: .public)")

        let transcriber = SpeechTranscriber(
            locale: resolvedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        logger.debug("ensuring assets installed…")
        try await Self.ensureAssetsInstalled(for: transcriber)
        logger.debug("assets ready")

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            logger.error("no compatible audio format")
            throw TranscriberError.noCompatibleAudioFormat
        }
        logger.debug("analyzer format = \(format.description, privacy: .public)")

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.analyzerFormat = format
        self.inputBuilder = inputBuilder
        self.segments = []
        self.volatileText = ""

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        await self?.appendFinal(start: result.range.start.seconds, text: text)
                    } else {
                        await self?.setVolatile(text)
                    }
                }
            } catch {
                // Stream ended because finalize was called. Nothing to recover.
            }
        }

        logger.debug("starting analyzer…")
        try await analyzer.start(inputSequence: inputSequence)
        logger.debug("analyzer started")
    }

    /// Feed a live audio buffer (mic or system audio) to the recognizer. Thread-safe.
    func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let analyzerFormat, let inputBuilder else { return }
        // Copy immediately: the tap/SCK buffer is reused by the caller after this returns.
        guard let copy = buffer.deepCopy() else { return }
        ingestQueue.async { [weak self] in
            guard let self, let converted = self.convert(copy, to: analyzerFormat) else { return }
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        }
    }

    /// Stops feeding audio, waits for the recognizer to flush, and returns the final transcript.
    ///
    /// `finalizeAndFinishThroughEndOfInput()` has no documented time bound, and on a long (~1h+)
    /// meeting a stuck finalize used to freeze the whole app on "Encerrar" forever — with nothing
    /// to show for it, even though everything said up to that point was already sitting in
    /// `segments`. Race it against a timeout instead: if it doesn't wrap up promptly, give up on
    /// waiting and return what's already been transcribed rather than hang indefinitely. The slow
    /// call keeps running in the background and is simply ignored once we've moved on.
    func finish() async -> [TranscriptSegment] {
        inputBuilder?.finish()
        let finishedInTime = await Self.withTimeout(seconds: 15) { [weak self] in
            try? await self?.analyzer?.finalizeAndFinishThroughEndOfInput()
            // Wait for the results loop to drain rather than cancelling it, so the last finalized
            // segment (still hopping onto @MainActor when finalize completes) isn't dropped.
            await self?.resultsTask?.value
        }
        if !finishedInTime {
            logger.error("\(self.speaker.label, privacy: .public) transcriber finalize timed out after 15s; returning \(self.segments.count, privacy: .public) segments captured so far")
        }
        return segments
    }

    /// Runs `operation` unstructured (not as a task-group child) so a timeout can truly abandon it
    /// instead of blocking on it anyway — Swift's structured concurrency always awaits every child
    /// task before returning, timeout or not, which would defeat the whole point here.
    // internal (not private) so `TranscriberTests` can exercise the race directly via `@testable import`.
    static func withTimeout(seconds: TimeInterval, operation: @escaping @Sendable () async -> Void) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let box = ResumeOnce(continuation)
            Task {
                await operation()
                box.resume(with: true)
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                box.resume(with: false)
            }
        }
    }

    /// Guards a `CheckedContinuation` so only the first of the two racing tasks above resumes it.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func resume(with value: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: value)
        }
    }

    @MainActor
    private func appendFinal(start: TimeInterval, text: String) {
        volatileText = ""
        guard !text.isEmpty else { return }
        segments.append(TranscriptSegment(start: start, text: text, speaker: speaker))
    }

    @MainActor
    private func setVolatile(_ text: String) {
        volatileText = text
    }

    // Called only on `ingestQueue`.
    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }

        let key = "\(buffer.format.sampleRate)-\(buffer.format.channelCount)-\(buffer.format.commonFormat.rawValue)-\(buffer.format.isInterleaved)"
        let converter = converters[key] ?? AVAudioConverter(from: buffer.format, to: format)
        guard let converter else { return nil }
        converters[key] = converter

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 8
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }

    private static func ensureAssetsInstalled(for module: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }
}

private extension AVAudioPCMBuffer {
    /// A tap/ScreenCaptureKit buffer is only valid during the callback; copy before handing it off.
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        copy.frameLength = frameLength
        let channels = Int(format.channelCount)
        let frames = Int(frameLength)
        if let src = floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channels { dst[ch].update(from: src[ch], count: frames) }
        } else if let src = int16ChannelData, let dst = copy.int16ChannelData {
            for ch in 0..<channels { dst[ch].update(from: src[ch], count: frames) }
        } else if let src = int32ChannelData, let dst = copy.int32ChannelData {
            for ch in 0..<channels { dst[ch].update(from: src[ch], count: frames) }
        } else {
            return nil
        }
        return copy
    }
}
