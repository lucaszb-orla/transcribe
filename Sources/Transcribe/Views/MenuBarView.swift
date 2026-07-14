import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            if appState.mode == .standby, let suggestion = appState.suggestion {
                Divider()
                suggestionBanner(suggestion)
            }

            Divider()
            actionButton

            Button("Ver reuniões") {
                openWindow(id: "meetings")
                NSApp.activate(ignoringOtherApps: true)
            }

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()
            Button("Sair") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var statusHeader: some View {
        Label(
            statusText,
            systemImage: appState.mode == .meeting ? "record.circle" : "moon.zzz"
        )
        .font(.headline)
    }

    private var statusText: String {
        guard appState.mode == .meeting else { return "Em standby" }
        return appState.isPaused ? "Gravação pausada" : "Gravando reunião"
    }

    private func suggestionBanner(_ suggestion: MeetingSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(suggestion.title).font(.subheadline).bold()
            Text(suggestion.start, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Iniciar gravação") {
                    Task { await appState.startMeeting(from: suggestion) }
                }
                Button("Ignorar") {
                    appState.calendarMonitor.dismissCurrentSuggestion()
                }
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if appState.mode == .meeting {
            if appState.isPaused {
                Button("Retomar gravação") { appState.resumeMeeting() }
            } else {
                Button("Pausar gravação") { appState.pauseMeeting() }
            }
            Button("Encerrar reunião") {
                Task { await appState.endMeeting() }
            }
        } else {
            Button("Iniciar gravação manual") {
                Task { await appState.startMeeting() }
            }
        }
    }
}
