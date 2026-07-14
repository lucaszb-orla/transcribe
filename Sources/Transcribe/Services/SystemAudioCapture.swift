import AVFoundation
import ScreenCaptureKit

/// Captures the audio coming out of the speakers (the other participants), via ScreenCaptureKit.
/// This is the officially sanctioned way to grab system audio without a virtual driver — it just
/// happens to require the "Screen Recording" permission even though we never touch video (PRD risk).
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    enum CaptureError: Error {
        case noDisplay
    }

    private var stream: SCStream?
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        self.onBuffer = onBuffer

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // We only care about audio, but SCStreamConfiguration still wants a (minimal) video config.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "system-audio-capture"))
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        onBuffer = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let pcmBuffer = sampleBuffer.asPCMBuffer else { return }
        onBuffer?(pcmBuffer)
    }
}
