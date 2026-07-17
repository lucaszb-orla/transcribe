import AppKit
import SwiftUI
import TipKit

struct MeetingDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var meeting: Meeting
    var onDelete: () -> Void = {}

    @State private var options = SummaryOptions()
    @State private var selectedPresetID: UUID?
    @State private var summarizing = false
    @State private var summaryError: String?
    /// Force the options form to show even when a summary already exists (regenerate).
    @State private var editingOptions = false

    @State private var showSavePreset = false
    @State private var newPresetName = ""
    @State private var confirmDelete = false

    @State private var summaryExpanded = true
    @State private var actionsExpanded = true
    @State private var transcriptExpanded = false
    @State private var editingTranscript = false

    @State private var showingSpecs = false
    private let specsTip = DevSpecsEntryTip()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    summarySection
                    if !meeting.actionItems.isEmpty { actionsSection }
                    transcriptSection
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.background)
            .navigationDestination(isPresented: $showingSpecs) {
                DevSpecsView(meeting: meeting)
            }
            .toolbar { toolbarContent }
            .deleteMeetingConfirmation(isPresented: $confirmDelete, title: meeting.title) {
                do {
                    try appState.store.delete(meeting)
                    onDelete()
                } catch {
                    appState.errorMessage = "Não foi possível excluir a reunião: \(error.localizedDescription)"
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button("Continuar transcrição", systemImage: "mic.badge.plus") {
                Task { await appState.continueMeeting(meeting) }
            }
            .disabled(appState.mode == .meeting)
        }
        ToolbarItem {
            Button("Specs de implementação", systemImage: "hammer") {
                showingSpecs = true
            }
            .popoverTip(specsTip)
        }
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
            Button("Salvar", systemImage: "checkmark") {
                save()
            }
            .keyboardShortcut("s", modifiers: .command)
        }
        ToolbarItem {
            Button("Excluir", systemImage: "trash", role: .destructive) {
                confirmDelete = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Título", text: $meeting.title)
                .font(.largeTitle.bold())
                .textFieldStyle(.plain)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { metadata }
                VStack(alignment: .leading, spacing: 4) { metadata }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        Label(meeting.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
        if let duration = durationText {
            Label(duration, systemImage: "clock")
        }
        if !meeting.participants.isEmpty {
            Label(meeting.participants.joined(separator: ", "), systemImage: "person.2")
                .lineLimit(1)
                .help(meeting.participants.joined(separator: ", "))
        }
    }

    private var durationText: String? {
        guard let end = meeting.endedAt else { return nil }
        let seconds = Int(end.timeIntervalSince(meeting.startedAt))
        guard seconds > 0 else { return nil }
        let m = seconds / 60, s = seconds % 60
        return m > 0 ? "\(m) min" : "\(s)s"
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        if meeting.hasSummary, !editingOptions {
            section("Resumo", systemImage: "sparkles", isExpanded: $summaryExpanded) {
                Button("Refazer", systemImage: "arrow.clockwise") {
                    withAnimation(.smooth) { editingOptions = true }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .labelStyle(.iconOnly)
                .help("Refazer resumo")
            } content: {
                if let prose = meeting.summaryProse, !prose.isEmpty {
                    Text(prose)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(meeting.summaryBullets, id: \.self) { bullet in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(.tertiary)
                                Text(bullet).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        } else {
            summaryOptionsForm
                .transition(.opacity)
        }
    }

    private var summaryOptionsForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Resumo", systemImage: "sparkles").font(.headline)

            Group {
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
                .labelsHidden()

                Toggle("Incluir itens de ação", isOn: $options.includeActionItems)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Instruções adicionais")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("ex.: foque nas decisões e responsáveis", text: $options.customInstructions, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                }

                if let summaryError {
                    Label(summaryError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    if editingOptions, meeting.hasSummary {
                        Button("Cancelar") {
                            summaryError = nil
                            withAnimation(.smooth) { editingOptions = false }
                        }
                    }
                    Button("Salvar como preset…", systemImage: "bookmark") {
                        newPresetName = ""
                        showSavePreset = true
                    }
                    Spacer()
                    Button {
                        Task { await generate() }
                    } label: {
                        if summarizing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Gerar", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(summarizing || meeting.fullTranscriptText.isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Salvar preset", isPresented: $showSavePreset) {
            TextField("Nome do preset", text: $newPresetName)
            Button("Cancelar", role: .cancel) {}
            Button("Salvar") {
                let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                appState.summaryPresets.add(name: name, options: options)
            }
        } message: {
            Text("As opções atuais serão salvas como um preset reutilizável.")
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        section("Ações", systemImage: "checklist", isExpanded: $actionsExpanded) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(meeting.actionItems, id: \.self) { item in
                    let done = meeting.isActionDone(item)
                    Button {
                        withAnimation(.snappy) { meeting.toggleActionDone(item) }
                        save()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done ? Color.accentColor : .secondary)
                                .contentTransition(.symbolEffect(.replace))
                            Text(item)
                                .strikethrough(done)
                                .foregroundStyle(done ? .secondary : .primary)
                            Spacer()
                        }
                        .contentShape(.rect)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        section("Transcrição", systemImage: "text.quote", isExpanded: $transcriptExpanded) {
            Button(editingTranscript ? "Concluir" : "Editar", systemImage: editingTranscript ? "checkmark" : "pencil") {
                withAnimation(.smooth) { editingTranscript.toggle() }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .labelStyle(.iconOnly)
            .help(editingTranscript ? "Concluir edição" : "Editar transcrição")
        } content: {
            if editingTranscript {
                TextEditor(text: $meeting.editableTranscriptText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 260)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            } else if meeting.transcript.isEmpty {
                Text("Transcrição vazia.")
                    .foregroundStyle(.secondary)
            } else {
                TranscriptBubbleList(segments: meeting.transcript)
            }
        }
    }

    // MARK: - Section helper

    /// A collapsible titled section with an optional trailing control. Uses a native
    /// `DisclosureGroup` so long content (resumo, transcrição) can be tucked away.
    private func section<Trailing: View, Content: View>(
        _ title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let body = content()
        let control = trailing()
        return DisclosureGroup(isExpanded: isExpanded.animation(.smooth)) {
            body
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                control
            }
            .contentShape(.rect)
        }
        .tint(.secondary)
    }

    private func save() {
        do {
            try appState.store.save(meeting)
        } catch {
            appState.errorMessage = "Não foi possível salvar a reunião: \(error.localizedDescription)"
        }
    }

    private func generate() async {
        summarizing = true
        summaryError = nil
        defer { summarizing = false }
        do {
            let updated = try await appState.generateSummary(for: meeting, options: options)
            withAnimation(.smooth) {
                meeting = updated
                editingOptions = false
            }
        } catch {
            summaryError = error.localizedDescription
        }
    }
}
