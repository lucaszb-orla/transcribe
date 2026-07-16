import AppKit
import SwiftUI

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

    @State private var specsExpanded = true
    @State private var generatingSpecs = false
    @State private var specsError: String?
    @State private var openingSpecID: UUID?
    @State private var recentlyOpenedSpecID: UUID?
    @State private var confirmingRun: ConfirmingRun?
    /// One repo for the whole meeting — a meeting is realistically about a single project, so
    /// picking per-spec was busywork. Pre-filled from the last repo used anywhere in the app.
    @State private var repoPath: String?

    /// Running Claude Code autonomously (commit/push/PR) is consequential enough to confirm first —
    /// there's no in-app undo for it, the consequences land in the user's own repo/GitHub.
    private enum ConfirmingRun: Identifiable {
        case all(count: Int)
        case one(DevSpec)

        var id: String {
            switch self {
            case .all: return "all"
            case .one(let spec): return spec.id.uuidString
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                summarySection
                if !meeting.actionItems.isEmpty { actionsSection }
                devSpecsSection
                transcriptSection
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .onAppear {
            if repoPath == nil {
                repoPath = meeting.devSpecsOrEmpty.compactMap(\.repoPath).first ?? appState.settings.lastUsedRepoPath
            }
        }
        .alert(
            confirmingRunTitle,
            isPresented: Binding(get: { confirmingRun != nil }, set: { if !$0 { confirmingRun = nil } }),
            presenting: confirmingRun
        ) { run in
            Button("Rodar") { confirm(run) }
            Button("Cancelar", role: .cancel) {}
        } message: { run in
            Text(confirmMessage(for: run))
        }
        .toolbar {
            ToolbarItem {
                Button("Continuar transcrição", systemImage: "mic.badge.plus") {
                    Task { await appState.continueMeeting(meeting) }
                }
                .disabled(appState.mode == .meeting)
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
        .deleteMeetingConfirmation(isPresented: $confirmDelete, title: meeting.title) {
            do {
                try appState.store.delete(meeting)
                onDelete()
            } catch {
                appState.errorMessage = "Não foi possível excluir a reunião: \(error.localizedDescription)"
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

    // MARK: - Dev specs

    private var devSpecsSection: some View {
        section("Specs de implementação", systemImage: "hammer", isExpanded: $specsExpanded) {
            Button {
                Task { await generateSpecs() }
            } label: {
                if generatingSpecs {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Gerar specs", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .labelStyle(.iconOnly)
            .disabled(generatingSpecs || meeting.fullTranscriptText.isEmpty)
            .help("Gerar specs de implementação a partir da transcrição")
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if let specsError {
                    Label(specsError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                repoRow
                if meeting.devSpecsOrEmpty.isEmpty {
                    Text("Nenhuma spec gerada ainda.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Spacer()
                        Button("Rodar tudo", systemImage: "play.fill") {
                            confirmingRun = .all(count: meeting.devSpecsOrEmpty.count)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(repoPath == nil)
                    }
                    ForEach(meeting.devSpecsOrEmpty) { spec in
                        devSpecCard(spec)
                    }
                }
            }
        }
    }

    /// One repo path shared by every spec in this meeting — pick it once here instead of per card.
    private var repoRow: some View {
        HStack {
            Text(repoPath ?? "Nenhum repositório escolhido")
                .font(.callout)
                .foregroundStyle(repoPath == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Button("Escolher repositório…") { chooseRepo() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func devSpecCard(_ spec: DevSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(spec.title).font(.headline)
            Text(spec.description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if recentlyOpenedSpecID == spec.id {
                    Label("Aberto no Terminal", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Spacer()
                Button("Abrir no Claude Code", systemImage: "terminal") {
                    confirmingRun = .one(spec)
                }
                .buttonStyle(.bordered)
                .disabled(repoPath == nil || openingSpecID == spec.id)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    private func chooseRepo() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Escolher"
        if let current = repoPath ?? appState.settings.lastUsedRepoPath {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        repoPath = url.path
        appState.settings.lastUsedRepoPath = url.path
        for spec in meeting.devSpecsOrEmpty {
            var updated = spec
            updated.repoPath = url.path
            meeting.updateDevSpec(updated)
        }
        save()
    }

    private var confirmingRunTitle: String {
        switch confirmingRun {
        case .all(let count): return count == 1 ? "Rodar automação?" : "Rodar \(count) automações?"
        case .one, .none: return "Rodar automação?"
        }
    }

    private func confirmMessage(for run: ConfirmingRun) -> String {
        let repo = repoPath ?? ""
        let windows: String
        switch run {
        case .all(let count): windows = count == 1 ? "um Terminal" : "\(count) Terminais"
        case .one: windows = "um Terminal"
        }
        return "Isso vai abrir \(windows) e deixar o Claude Code implementar, commitar, dar push e abrir Pull Request sozinho em \u{201c}\(repo)\u{201d}."
    }

    private func confirm(_ run: ConfirmingRun) {
        switch run {
        case .all:
            runAll()
        case .one(let spec):
            Task { await openInTerminal(spec) }
        }
    }

    /// Opens a Terminal window for every spec against the shared repo, one after another.
    private func runAll() {
        Task {
            for spec in meeting.devSpecsOrEmpty {
                await openInTerminal(spec)
            }
        }
    }

    private func openInTerminal(_ spec: DevSpec) async {
        guard let repoPath else { return }
        openingSpecID = spec.id
        specsError = nil
        defer { openingSpecID = nil }
        do {
            try await appState.openDevSpecInTerminal(spec, in: meeting, repoPath: repoPath)
            withAnimation(.smooth) { recentlyOpenedSpecID = spec.id }
            Task {
                try? await Task.sleep(for: .seconds(2))
                if recentlyOpenedSpecID == spec.id {
                    withAnimation(.smooth) { recentlyOpenedSpecID = nil }
                }
            }
        } catch {
            specsError = error.localizedDescription
        }
    }

    private func generateSpecs() async {
        generatingSpecs = true
        specsError = nil
        defer { generatingSpecs = false }
        do {
            var updated = try await appState.generateDevSpecs(for: meeting)
            if let repoPath {
                for spec in updated.devSpecsOrEmpty {
                    var withRepo = spec
                    withRepo.repoPath = repoPath
                    updated.updateDevSpec(withRepo)
                }
            }
            withAnimation(.smooth) { meeting = updated }
            save()
        } catch {
            specsError = error.localizedDescription
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
