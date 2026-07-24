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
    enum CaptureError: LocalizedError {
        case inputUnavailable

        var errorDescription: String? {
            switch self {
            case .inputUnavailable:
                String(localized: "O microfone selecionado não está disponível.")
            }
        }
    }

    private let controlQueue = DispatchQueue(label: "com.lucasbaggiotto.Transcribe.microphone-control")
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var recoveryState = MicrophoneRecoveryState()
    private var preferredDeviceID: AudioDeviceID?
    private var bufferHandler: ((AVAudioPCMBuffer) -> Void)?
    private var errorHandler: ((Error) -> Void)?

    /// Starts the mic tap. `deviceID` selects a specific input device (nil = system default).
    func start(
        deviceID: AudioDeviceID?,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        try controlQueue.sync {
            guard !recoveryState.isCapturing else { return }
            preferredDeviceID = deviceID
            bufferHandler = onBuffer
            errorHandler = onError
            recoveryState.start()

            do {
                try rebuildEngine()
            } catch {
                recoveryState.stop()
                tearDownEngine()
                bufferHandler = nil
                errorHandler = nil
                throw error
            }
        }
    }

    func stop() {
        controlQueue.sync {
            recoveryState.stop()
            tearDownEngine()
            preferredDeviceID = nil
            bufferHandler = nil
            errorHandler = nil
        }
    }

    /// An input or output hardware format change stops and uninitializes AVAudioEngine.
    /// Rebuild the engine after the notification callback returns so microphone capture resumes.
    /// Source: https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange
    private func scheduleRecovery() {
        controlQueue.async { [weak self] in
            guard let self, self.recoveryState.requestRestart() else { return }
            logger.notice("audio configuration changed; rebuilding microphone engine")

            do {
                try self.rebuildEngine()
                self.recoveryState.finishRestart()
                logger.notice("microphone engine resumed after audio configuration change")
            } catch {
                self.recoveryState.stop()
                logger.error("failed to resume microphone after audio configuration change: \(String(describing: error), privacy: .public)")
                self.errorHandler?(error)
            }
        }
    }

    private func rebuildEngine() throws {
        tearDownEngine()
        guard let bufferHandler else { throw CaptureError.inputUnavailable }

        if let preferredDeviceID {
            do {
                try startEngine(deviceID: preferredDeviceID, onBuffer: bufferHandler)
                return
            } catch {
                logger.error("selected microphone \(preferredDeviceID) failed; falling back to system default: \(String(describing: error), privacy: .public)")
                tearDownEngine()
            }
        }

        try startEngine(deviceID: nil, onBuffer: bufferHandler)
    }

    private func startEngine(
        deviceID: AudioDeviceID?,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void
    ) throws {
        let engine = AVAudioEngine()
        if let deviceID {
            try setInputDevice(deviceID, on: engine)
        }

        let input = engine.inputNode
        let hardwareFormat = input.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw CaptureError.inputUnavailable
        }

        let tapFormat = input.outputFormat(forBus: 0)
        logger.notice("mic input format = \(tapFormat.description, privacy: .public)")
        input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
            onBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleRecovery()
        }
    }

    private func tearDownEngine() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    /// Point the engine's input node at a specific Core Audio device before it starts.
    private func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) throws {
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
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

/// Small state machine that prevents repeated hardware notifications from racing multiple restarts.
struct MicrophoneRecoveryState {
    private(set) var isCapturing = false
    private var restartPending = false

    mutating func start() {
        isCapturing = true
        restartPending = false
    }

    mutating func stop() {
        isCapturing = false
        restartPending = false
    }

    mutating func requestRestart() -> Bool {
        guard isCapturing, !restartPending else { return false }
        restartPending = true
        return true
    }

    mutating func finishRestart() {
        restartPending = false
    }
}
