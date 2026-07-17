import AVFoundation
import CoreAudio
import OSLog

private let logger = Logger(subsystem: "com.lucasbaggiotto.Transcribe", category: "MicrophoneCapture")

/// Captures the microphone (your voice) by tapping the engine's input node directly.
///
/// ponytail: no AVAudioEngine mixer / player-node graph and nothing is ever routed to an output.
/// the old design tapped `mainMixerNode` while setting its `outputVolume = 0`, which silences the
/// tapped signal too (that was the "transcrição não pega" bug). Tapping the input node gives the raw
/// mic signal with no playback and no feedback risk. System audio is captured separately (see
/// `SystemAudioCapture`) and both streams are fed straight to the transcriber.
final class MicrophoneCapture {
    private let engine = AVAudioEngine()

    /// Starts the mic tap. `deviceID` selects a specific input device (nil = system default).
    func start(deviceID: AudioDeviceID?, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        if let deviceID {
            try setInputDevice(deviceID)
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        logger.debug("mic input format = \(format.description, privacy: .public)")

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            onBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Point the engine's input node at a specific Core Audio device before it starts.
    private func setInputDevice(_ deviceID: AudioDeviceID) throws {
        guard let audioUnit = engine.inputNode.audioUnit else { return }
        var device = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            logger.error("failed to set input device \(deviceID): \(status)")
        }
    }
}
