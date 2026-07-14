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
                    ContentUnavailableView(
                        query.isEmpty ? "Nenhuma reunião ainda" : "Nenhum resultado",
                        systemImage: query.isEmpty ? "waveform" : "magnifyingglass",
                        description: Text(query.isEmpty
                            ? "Inicie uma gravação para ver a transcrição aqui."
                            : "Tente buscar por outro título ou trecho da transcrição.")
                    )
                }
            }
        } detail: {
            if let selection {
                MeetingDetailView(meeting: selection)
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
    }
}
