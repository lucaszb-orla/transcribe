import SwiftUI

struct MeetingListView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var selection: Meeting?

    var body: some View {
        NavigationSplitView {
            List(appState.store.search(query), selection: $selection) { meeting in
                VStack(alignment: .leading) {
                    Text(meeting.title).font(.headline)
                    Text(meeting.startedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        } detail: {
            if let selection {
                MeetingDetailView(meeting: selection)
                    .id(selection.id)
            } else {
                Text("Selecione uma reunião")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .alert("Não foi possível concluir a ação", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }
}
