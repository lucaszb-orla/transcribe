import Speech
import SwiftUI

/// Preferences window (⌘,): which microphone to record and which language to transcribe.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var devices: [AudioInputDevice] = []
    @State private var locales: [Locale] = []

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section("Microfone") {
                Picker("Entrada de áudio", selection: $settings.selectedInputUID) {
                    Text("Padrão do sistema").tag(String?.none)
                    ForEach(devices) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                }
                .pickerStyle(.menu)

                Text("O áudio do sistema (outros participantes) é capturado à parte via gravação de tela.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Idioma da transcrição") {
                Picker("Idioma", selection: $settings.transcriptionLocaleID) {
                    ForEach(localeOptions, id: \.id) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                Text("A transcrição on-device espera este idioma. Fale nele para melhores resultados.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 300)
        .task {
            devices = AudioDevices.inputDevices()
            locales = (try? await SpeechTranscriber.supportedLocales) ?? []
        }
    }

    /// The recognizer's supported locales, always including the current selection so it stays visible
    /// even before the async list loads (or if it's not reported).
    private var localeOptions: [(id: String, name: String)] {
        var ids = locales.map { $0.identifier(.bcp47) }
        let selected = appState.settings.transcriptionLocaleID
        if !ids.contains(selected) { ids.insert(selected, at: 0) }
        let display = Locale.current
        return ids
            .sorted()
            .map { id in
                (id: id, name: display.localizedString(forIdentifier: id).map { "\($0) (\(id))" } ?? id)
            }
    }
}
