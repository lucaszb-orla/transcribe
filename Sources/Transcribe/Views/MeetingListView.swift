import AppKit
import SwiftUI

struct MeetingListView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var selection: Meeting?
    @State private var pendingDelete: Meeting?

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
                        pendingDelete = meeting
                    }
                }
            }
            .onDeleteCommand {
                if let selection { pendingDelete = selection }
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Buscar por título ou transcrição")
            .navigationTitle("Reuniões")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
            .safeAreaInset(edge: .top, spacing: 0) {
                if appState.permissions.snapshot.needsCalendarIntegration {
                    calendarIntegrationBanner
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Nova transcrição", systemImage: "record.circle") {
                    Task { await appState.startMeeting() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(8)
            }
            .toolbar {
                ToolbarItem {
                    SettingsLink {
                        Label("Ajustes", systemImage: "gearshape")
                    }
                }
            }
            .overlay {
                if appState.store.search(query).isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView {
                            Label("Nenhuma reunião ainda", systemImage: "waveform")
                        } description: {
                            Text("Toque em “Nova transcrição” para gravar sua primeira reunião.")
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Nenhum resultado", systemImage: "magnifyingglass")
                        } description: {
                            Text("Nenhuma reunião encontrada para “\(query)”.")
                        }
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
        .deleteMeetingConfirmation(
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            title: pendingDelete?.title ?? ""
        ) {
            if let pendingDelete { delete(pendingDelete) }
        }
        .onAppear { selectPendingReview() }
        .onChange(of: appState.pendingReviewMeetingID) { selectPendingReview() }
    }

    private var calendarIntegrationBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Conecte seu Calendário", systemImage: "calendar.badge.plus")
                .font(.headline)
            Text("Receba sugestões quando uma reunião com link estiver prestes a começar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if appState.permissions.calendar == .denied {
                Button("Abrir Ajustes") { openCalendarPrivacySettings() }
                    .controlSize(.small)
            } else {
                Button("Conectar Calendário") {
                    Task { await appState.requestCalendarIntegration() }
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .contain)
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

    private func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
