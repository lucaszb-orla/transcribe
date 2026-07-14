import AVFoundation

/// Combines the microphone (you) and the system audio (everyone else) into one signal.
///
/// ponytail: real-time sample mixing via AVAudioEngine's mixer node, not a proper gain-staged
/// audio pipeline. v1 has no speaker diarization (see PRD "Fora do escopo"), so a single mixed
/// stream is all the transcriber needs. If diarization lands later, transcribe mic and system
/// audio as two separate streams instead and merge by timestamp.
final class AudioMixer {
    private let engine = AVAudioEngine()
    private let systemPlayer = AVAudioPlayerNode()

    /// Starts the mic → mixer path and returns the format buffers will arrive in.
    @discardableResult
    func start(onMixedBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws -> AVAudioFormat {
        let mixer = engine.mainMixerNode
        engine.attach(systemPlayer)
        engine.connect(systemPlayer, to: mixer, format: nil)
        engine.connect(engine.inputNode, to: mixer, format: engine.inputNode.outputFormat(forBus: 0))

        // Silence playback: we only want the tap, not to hear our own mic played back live.
        mixer.outputVolume = 0

        let mixFormat = mixer.outputFormat(forBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 4096, format: mixFormat) { buffer, _ in
            onMixedBuffer(buffer)
        }

        try engine.start()
        systemPlayer.play()
        return mixFormat
    }

    /// Feeds a system-audio buffer (from `SystemAudioCapture`) into the mix.
    func scheduleSystemAudio(_ buffer: AVAudioPCMBuffer) {
        systemPlayer.scheduleBuffer(buffer)
    }

    func stop() {
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
    }
}
