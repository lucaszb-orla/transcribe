import CoreAudio
import Foundation

/// A selectable audio input device. `uid` is stable across reboots/reconnects (unlike the numeric
/// `AudioDeviceID`), so that's what we persist; `id` is resolved fresh at recording time.
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioDevices {
    /// All Core Audio devices that have at least one input channel.
    static func inputDevices() -> [AudioInputDevice] {
        deviceIDs().compactMap { id in
            guard inputChannelCount(id) > 0,
                  let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, kAudioObjectPropertyName) else {
                return nil
            }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    /// Resolve a persisted UID back to the current device ID (nil if it's unplugged).
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        inputDevices().first { $0.uid == uid }?.id
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }
        return ids
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return 0
        }
        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, bufferList) == noErr else {
            return 0
        }
        let list = UnsafeMutableAudioBufferListPointer(bufferList.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, &value) == noErr else {
            return nil
        }
        return value as String
    }
}

/// User-adjustable settings, persisted in `UserDefaults`: input mic + transcription language.
@MainActor
@Observable
final class AppSettings {
    /// Persisted device UID; nil means "system default".
    var selectedInputUID: String? {
        didSet { UserDefaults.standard.set(selectedInputUID, forKey: Self.inputKey) }
    }

    /// BCP-47 identifier of the language the recognizer should expect (e.g. "pt-BR").
    var transcriptionLocaleID: String {
        didSet { UserDefaults.standard.set(transcriptionLocaleID, forKey: Self.localeKey) }
    }

    /// Opt-in: auto-start recording when a calendar meeting begins and auto-stop at its end.
    var autoRecordFromCalendar: Bool {
        didSet { UserDefaults.standard.set(autoRecordFromCalendar, forKey: Self.autoRecordKey) }
    }

    /// Opt-in: mirror every saved transcript as a Markdown file in `autoExportFolderPath`. Off by
    /// default. This is a local convenience export, not a replacement for the app's own storage.
    var autoExportEnabled: Bool {
        didSet { UserDefaults.standard.set(autoExportEnabled, forKey: Self.autoExportEnabledKey) }
    }

    /// Folder the user picked for auto-export (via NSOpenPanel); nil until they choose one.
    var autoExportFolderPath: String? {
        didSet { UserDefaults.standard.set(autoExportFolderPath, forKey: Self.autoExportFolderKey) }
    }

    /// Last git repo path picked for the "enviar pro Claude Code" automation; nil until first use.
    var lastUsedRepoPath: String? {
        didSet { UserDefaults.standard.set(lastUsedRepoPath, forKey: Self.lastUsedRepoPathKey) }
    }

    private static let inputKey = "selectedInputUID"
    private static let localeKey = "transcriptionLocaleID"
    private static let autoRecordKey = "autoRecordFromCalendar"
    private static let autoExportEnabledKey = "autoExportEnabled"
    private static let autoExportFolderKey = "autoExportFolderPath"
    private static let lastUsedRepoPathKey = "lastUsedRepoPath"

    init() {
        selectedInputUID = UserDefaults.standard.string(forKey: Self.inputKey)
        // Default to Brazilian Portuguese; the system locale ("en-US" here) was transcribing English.
        transcriptionLocaleID = UserDefaults.standard.string(forKey: Self.localeKey) ?? "pt-BR"
        autoRecordFromCalendar = UserDefaults.standard.bool(forKey: Self.autoRecordKey)
        autoExportEnabled = UserDefaults.standard.bool(forKey: Self.autoExportEnabledKey)
        autoExportFolderPath = UserDefaults.standard.string(forKey: Self.autoExportFolderKey)
        lastUsedRepoPath = UserDefaults.standard.string(forKey: Self.lastUsedRepoPathKey)
    }

    var autoExportFolderURL: URL? {
        autoExportFolderPath.map { URL(fileURLWithPath: $0) }
    }

    /// Resolve the current setting to a device ID for the recording engine.
    var resolvedInputDeviceID: AudioDeviceID? {
        selectedInputUID.flatMap { AudioDevices.deviceID(forUID: $0) }
    }

    var transcriptionLocale: Locale {
        Locale(identifier: transcriptionLocaleID)
    }
}
