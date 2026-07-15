import Speech
import SwiftUI

/// Preferences window (⌘,): which microphone to record and which language to transcribe.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var devices: [AudioInputDevice] = []
    @State private var locales: [Locale] = []
    @State private var pendingPresetDelete: SummaryPreset?

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section {
                Picker("Entrada de áudio", selection: $settings.selectedInputUID) {
                    Text("Padrão do sistema").tag(String?.none)
                    ForEach(devices) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Microfone")
            } footer: {
                Text("O áudio do sistema (outros participantes) é capturado à parte via gravação de tela.")
            }

            Section {
                Picker("Idioma", selection: $settings.transcriptionLocaleID) {
                    ForEach(localeOptions, id: \.id) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Idioma da transcrição")
            } footer: {
                Text("A transcrição on-device espera este idioma. Fale nele para melhores resultados.")
            }

            Section {
                Toggle("Iniciar e encerrar gravação automaticamente", isOn: $settings.autoRecordFromCalendar)
            } header: {
                Text("Calendário")
            } footer: {
                Text("Grava sozinho quando uma reunião do calendário com link de chamada começa e para no fim do evento — sem precisar clicar.")
            }

            Section("Presets de resumo") {
                if appState.summaryPresets.presets.isEmpty {
                    Text("Nenhum preset. Salve um a partir da tela de uma reunião.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(appState.summaryPresets.presets) { preset in
                    HStack {
                        TextField("Nome", text: nameBinding(for: preset))
                            .textFieldStyle(.plain)
                        Spacer()
                        Text(preset.options.format.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            pendingPresetDelete = preset
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Apagar preset")
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Resizable within sensible bounds — a fixed frame made the Settings window non-resizable.
        .frame(
            minWidth: 460, idealWidth: 520, maxWidth: 720,
            minHeight: 420, idealHeight: 520, maxHeight: 820
        )
        .task {
            devices = AudioDevices.inputDevices()
            locales = (try? await SpeechTranscriber.supportedLocales) ?? []
        }
        .alert("Apagar preset?", isPresented: Binding(
            get: { pendingPresetDelete != nil },
            set: { if !$0 { pendingPresetDelete = nil } }
        ), presenting: pendingPresetDelete) { preset in
            Button("Apagar", role: .destructive) { appState.summaryPresets.delete(preset) }
            Button("Cancelar", role: .cancel) {}
        } message: { preset in
            Text("“\(preset.name)” será apagado permanentemente.")
        }
    }

    /// Two-way binding that renames a preset in place (persists via the store's didSet).
    private func nameBinding(for preset: SummaryPreset) -> Binding<String> {
        Binding(
            get: { appState.summaryPresets.presets.first(where: { $0.id == preset.id })?.name ?? preset.name },
            set: { newName in
                var updated = preset
                updated.name = newName
                appState.summaryPresets.update(updated)
            }
        )
    }

    /// The recognizer's supported locales, always including the current selection so it stays visible
    /// even before the async list loads (or if it's not reported).
    private var localeOptions: [(id: String, name: String)] {
        var ids = locales.map { $0.identifier(.bcp47) }
        let selected = appState.settings.transcriptionLocaleID
        if !ids.contains(selected) { ids.insert(selected, at: 0) }
        let display = Locale(identifier: "pt_BR")
        return ids
            .sorted()
            .map { id in
                (id: id, name: display.localizedString(forIdentifier: id) ?? id)
            }
    }
}
