import SwiftUI

struct MeetingDetailView: View {
    @Environment(AppState.self) private var appState
    @State var meeting: Meeting
    var onDelete: () -> Void = {}

    @State private var options = SummaryOptions()
    @State private var selectedPresetID: UUID?
    @State private var summarizing = false
    @State private var summaryError: String?
    /// Force the options form to show even when a summary already exists (regenerate).
    @State private var editingOptions = false

    @State private var followUpTone: FollowUpDrafter.Tone = .formal
    @State private var followUp = ""
    @State private var draftingFollowUp = false
    @State private var followUpError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Título", text: $meeting.title)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)

                if !meeting.participants.isEmpty {
                    Label(meeting.participants.joined(separator: ", "), systemImage: "person.2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                summarySection

                if !meeting.actionItems.isEmpty {
                    GroupBox("Ações") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(meeting.actionItems, id: \.self) { item in
                                Label(item, systemImage: "checkmark.circle")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                }

                followUpSection

                GroupBox("Transcrição") {
                    TextEditor(text: $meeting.editableTranscriptText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 300)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Copiar como Markdown") { MeetingExporter.copyToPasteboard(MeetingExporter.markdown(meeting)) }
                    Button("Copiar como texto") { MeetingExporter.copyToPasteboard(MeetingExporter.plainText(meeting)) }
                    Divider()
                    Button("Exportar…") { MeetingExporter.exportToFile(meeting) }
                } label: {
                    Label("Compartilhar", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem {
                Button("Excluir", systemImage: "trash", role: .destructive) {
                    do {
                        try appState.store.delete(meeting)
                        onDelete()
                    } catch {
                        appState.errorMessage = "Não foi possível excluir a reunião: \(error.localizedDescription)"
                    }
                }
            }
            ToolbarItem {
                Button("Salvar", systemImage: "square.and.arrow.down") {
                    try? appState.store.save(meeting)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        if meeting.hasSummary, !editingOptions {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Resumo", systemImage: "sparkles").font(.headline)
                        Spacer()
                        Button("Refazer", systemImage: "arrow.clockwise") { editingOptions = true }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                    if let prose = meeting.summaryProse, !prose.isEmpty {
                        Text(prose).textSelection(.enabled)
                    } else {
                        ForEach(meeting.summaryBullets, id: \.self) { bullet in
                            Label(bullet, systemImage: "circle.fill").imageScale(.small)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        } else {
            summaryOptionsForm
        }
    }

    private var summaryOptionsForm: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Gerar resumo", systemImage: "sparkles").font(.headline)

                Picker("Modelo", selection: $selectedPresetID) {
                    Text("Personalizado").tag(UUID?.none)
                    ForEach(appState.summaryPresets.presets) { preset in
                        Text(preset.name).tag(UUID?.some(preset.id))
                    }
                }
                .onChange(of: selectedPresetID) { _, id in
                    if let preset = appState.summaryPresets.presets.first(where: { $0.id == id }) {
                        options = preset.options
                    }
                }

                Picker("Formato", selection: $options.format) {
                    ForEach(SummaryOptions.Format.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Incluir itens de ação", isOn: $options.includeActionItems)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Instruções adicionais (opcional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("ex.: foque nas decisões e responsáveis", text: $options.customInstructions, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                }

                if let summaryError {
                    Label(summaryError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    if editingOptions, meeting.hasSummary {
                        Button("Cancelar") { editingOptions = false; summaryError = nil }
                    }
                    Spacer()
                    Button {
                        Task { await generate() }
                    } label: {
                        if summarizing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Gerar resumo", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(summarizing || meeting.fullTranscriptText.isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private func generate() async {
        summarizing = true
        summaryError = nil
        defer { summarizing = false }
        do {
            meeting = try await appState.generateSummary(for: meeting, options: options)
            editingOptions = false
        } catch {
            summaryError = error.localizedDescription
        }
    }

    // MARK: - Follow-up

    @ViewBuilder
    private var followUpSection: some View {
        if !meeting.fullTranscriptText.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Rascunho de follow-up", systemImage: "envelope").font(.headline)
                        Spacer()
                        Picker("Tom", selection: $followUpTone) {
                            ForEach(FollowUpDrafter.Tone.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }

                    if !followUp.isEmpty {
                        Text(followUp)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let followUpError {
                        Label(followUpError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        if !followUp.isEmpty {
                            Button("Copiar", systemImage: "doc.on.doc") {
                                MeetingExporter.copyToPasteboard(followUp)
                            }
                        }
                        Spacer()
                        Button {
                            Task { await draftFollowUp() }
                        } label: {
                            if draftingFollowUp {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(followUp.isEmpty ? "Gerar rascunho" : "Gerar de novo", systemImage: "envelope")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftingFollowUp)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
    }

    private func draftFollowUp() async {
        draftingFollowUp = true
        followUpError = nil
        defer { draftingFollowUp = false }
        do {
            followUp = try await appState.generateFollowUp(for: meeting, tone: followUpTone)
        } catch {
            followUpError = error.localizedDescription
        }
    }
}
