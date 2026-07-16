import AppKit
import SwiftUI

/// A dedicated screen for turning a meeting into implementation tasks and handing them off to
/// Claude Code — split out from `MeetingDetailView` so summarizing a meeting never implies also
/// generating dev specs for it; the two are unrelated asks the user makes independently.
struct DevSpecsView: View {
    @Environment(AppState.self) private var appState
    @State var meeting: Meeting

    @State private var options = DevSpecOptions()
    @State private var generatingSpecs = false
    @State private var specsError: String?

    @State private var repoPath: String?
    @State private var openingSpecID: UUID?
    @State private var recentlyOpenedSpecID: UUID?
    @State private var confirmingRun: ConfirmingRun?
    @State private var statuses: [UUID: ClaudeCodeRunner.DevSpecStatus] = [:]

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
            VStack(alignment: .leading, spacing: 20) {
                optionsForm
                if !meeting.devSpecsOrEmpty.isEmpty {
                    repoRow
                    runAllRow
                    ForEach(meeting.devSpecsOrEmpty) { spec in
                        devSpecCard(spec)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .navigationTitle("Specs de implementação")
        .onAppear {
            if repoPath == nil {
                repoPath = meeting.devSpecsOrEmpty.compactMap(\.repoPath).first ?? appState.settings.lastUsedRepoPath
            }
        }
        .task { await refreshStatuses() }
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
    }

    // MARK: - Options / generate

    private var optionsForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Specs de implementação", systemImage: "hammer").font(.headline)

            Group {
                Picker("Modelo", selection: $options.model) {
                    ForEach(ClaudeModel.allCases) { Text($0.label).tag($0) }
                }
                Picker("Esforço", selection: $options.effort) {
                    ForEach(ClaudeEffort.allCases) { Text($0.label).tag($0) }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Instruções adicionais")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("ex.: focar só no backend, ignorar testes", text: $options.customInstructions, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                }

                if let specsError {
                    Label(specsError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button {
                        Task { await generateSpecs() }
                    } label: {
                        if generatingSpecs {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(
                                meeting.devSpecsOrEmpty.isEmpty ? "Gerar specs" : "Regerar specs",
                                systemImage: "play.fill"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(generatingSpecs || meeting.fullTranscriptText.isEmpty)
                    .help(meeting.devSpecsOrEmpty.isEmpty ? "" : "Substitui as specs atuais (edições incluídas) por uma nova lista")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Specs list

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

    private var runAllRow: some View {
        HStack {
            Spacer()
            Button("Atualizar status", systemImage: "arrow.clockwise") {
                Task { await refreshStatuses() }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            Button("Rodar tudo", systemImage: "play.fill") {
                confirmingRun = .all(count: meeting.devSpecsOrEmpty.count)
            }
            .buttonStyle(.borderedProminent)
            .disabled(repoPath == nil)
        }
    }

    private func devSpecCard(_ spec: DevSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Título", text: titleBinding(spec.id))
                .textFieldStyle(.plain)
                .font(.headline)
            TextField("Descrição", text: descriptionBinding(spec.id), axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(.secondary)
                .lineLimit(1...6)

            statusRow(for: spec)

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

    @ViewBuilder
    private func statusRow(for spec: DevSpec) -> some View {
        switch statuses[spec.id] ?? .notStarted {
        case .notStarted:
            EmptyView()
        case .dispatched:
            Label("Enviado, PR ainda não encontrada", systemImage: "clock")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .prOpen(let url):
            statusLink("PR aberta", url: url, systemImage: "arrow.triangle.pull")
        case .prMerged(let url):
            statusLink("PR mesclada", url: url, systemImage: "checkmark.circle.fill")
        case .prClosed(let url):
            statusLink("PR fechada sem merge", url: url, systemImage: "xmark.circle")
        }
    }

    private func statusLink(_ title: String, url: String, systemImage: String) -> some View {
        Button {
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.link)
        .font(.callout)
    }

    // MARK: - Bindings

    private func titleBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { meeting.devSpecsOrEmpty.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                guard var spec = meeting.devSpecsOrEmpty.first(where: { $0.id == id }) else { return }
                spec.title = newValue
                meeting.updateDevSpec(spec)
            }
        )
    }

    private func descriptionBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { meeting.devSpecsOrEmpty.first(where: { $0.id == id })?.description ?? "" },
            set: { newValue in
                guard var spec = meeting.devSpecsOrEmpty.first(where: { $0.id == id }) else { return }
                spec.description = newValue
                meeting.updateDevSpec(spec)
            }
        )
    }

    // MARK: - Actions

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
        Task { await refreshStatuses() }
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
            let updated = try await appState.openDevSpecInTerminal(spec, in: meeting, repoPath: repoPath, options: options)
            meeting = updated
            withAnimation(.smooth) { recentlyOpenedSpecID = spec.id }
            statuses[spec.id] = .dispatched
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

    private func refreshStatuses() async {
        guard let repoPath else { return }
        for spec in meeting.devSpecsOrEmpty {
            statuses[spec.id] = await ClaudeCodeRunner.checkStatus(spec: spec, repoPath: repoPath)
        }
    }

    private func generateSpecs() async {
        generatingSpecs = true
        specsError = nil
        defer { generatingSpecs = false }
        do {
            var updated = try await appState.generateDevSpecs(for: meeting, options: options)
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

    private func save() {
        do {
            try appState.store.save(meeting)
        } catch {
            appState.errorMessage = "Não foi possível salvar a reunião: \(error.localizedDescription)"
        }
    }
}
