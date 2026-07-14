import SwiftUI

struct MeetingListView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var selection: Meeting?

    var body: some View {
        NavigationSplitView {
            List(appState.store.search(query), selection: $selection) { meeting in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title).font(.headline)
                        Text(meeting.startedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(meeting)
                .contextMenu {
                    Button("Excluir", systemImage: "trash", role: .destructive) {
                        delete(meeting)
                    }
                }
            }
            .onDeleteCommand {
                if let selection { delete(selection) }
            }
            .searchable(text: $query, prompt: "Buscar por título ou transcrição")
            .navigationTitle("Reuniões")
            .toolbar {
                ToolbarItem {
                    Button("Nova transcrição", systemImage: "record.circle") {
                        Task { await appState.startMeeting() }
                    }
                }
            }
            .overlay {
                if appState.store.search(query).isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView {
                            Label("Nenhuma reunião ainda", systemImage: "waveform")
                        } description: {
                            Text("Inicie uma gravação para ver a transcrição e o resumo aqui.")
                        } actions: {
                            Button("Nova transcrição", systemImage: "record.circle") {
                                Task { await appState.startMeeting() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
        } detail: {
            if let selection {
                MeetingDetailView(meeting: selection, onDelete: { self.selection = nil })
                    .id(selection.id)
            } else {
                ContentUnavailableView(
                    "Selecione uma reunião",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Escolha uma reunião na lista para ver a transcrição e o resumo.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .alert("Não foi possível concluir a ação", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("Fechar") {}
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .onAppear { selectPendingReview() }
        .onChange(of: appState.pendingReviewMeetingID) { selectPendingReview() }
    }

    /// After a recording ends, jump straight to the new meeting so the user can choose summary options.
    private func selectPendingReview() {
        guard let id = appState.pendingReviewMeetingID,
              let meeting = appState.store.meetings.first(where: { $0.id == id }) else { return }
        selection = meeting
        appState.pendingReviewMeetingID = nil
    }

    private func delete(_ meeting: Meeting) {
        if selection?.id == meeting.id { selection = nil }
        do {
            try appState.store.delete(meeting)
        } catch {
            appState.errorMessage = "Não foi possível excluir a reunião: \(error.localizedDescription)"
        }
    }
}
