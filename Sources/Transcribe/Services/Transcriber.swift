import AVFoundation
import CoreMedia
import Observation
import OSLog
import Speech

private let logger = Logger(subsystem: "com.lucasbaggiotto.Transcribe", category: "Transcriber")

/// Wraps the on-device `SpeechAnalyzer` / `SpeechTranscriber` (offline preset) to turn a live
/// mixed audio stream into timestamped text. No custom vocabulary support here — see PRD risks
/// on proper-noun/acronym accuracy, and WhisperKit as the fallback if this isn't good enough.
@Observable
final class Transcriber {
    enum TranscriberError: Error {
        case localeNotSupported
        case noCompatibleAudioFormat
    }

    private(set) var segments: [TranscriptSegment] = []

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var resultsTask: Task<Void, Never>?

    func start(locale: Locale = .current) async throws {
        logger.debug("device locale = \(locale.identifier(.bcp47), privacy: .public)")
        guard let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            logger.error("no supported SpeechTranscriber locale equivalent to \(locale.identifier(.bcp47), privacy: .public)")
            throw TranscriberError.localeNotSupported
        }
        logger.debug("resolved locale = \(resolvedLocale.identifier(.bcp47), privacy: .public)")

        let transcriber = SpeechTranscriber(locale: resolvedLocale, preset: .transcription)
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
        self.converter = nil
        self.segments = []

        resultsTask = Task { [weak self] in
            guard let self else { return }
            guard let stream = self.transcriber?.results else { return }
            do {
                for try await result in stream where result.isFinal {
                    await self.appendSegment(start: result.range.start.seconds, text: String(result.text.characters))
                }
            } catch {
                // The recognizer stream ended (e.g. finalize was called); nothing to recover here.
            }
        }

        logger.debug("starting analyzer…")
        try await analyzer.start(inputSequence: inputSequence)
        logger.debug("analyzer started")
    }

    /// Feed a live audio buffer (already mixed mic + system audio, see `AudioMixer`) to the recognizer.
    func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let analyzerFormat, let inputBuilder, let converted = convert(buffer, to: analyzerFormat) else {
            return
        }
        inputBuilder.yield(AnalyzerInput(buffer: converted))
    }

    /// Stops feeding audio, waits for the recognizer to flush, and returns the final transcript.
    func finish() async -> [TranscriptSegment] {
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        return segments
    }

    @MainActor
    private func appendSegment(start: TimeInterval, text: String) {
        guard !text.isEmpty else { return }
        segments.append(TranscriptSegment(start: start, text: text))
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return nil }

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
