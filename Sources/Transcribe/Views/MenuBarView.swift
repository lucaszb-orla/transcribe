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

            Button("Ver reuniões", systemImage: "list.bullet") {
                openWindow(id: "meetings")
                NSApp.activate(ignoringOtherApps: true)
            }

            SettingsLink {
                Label("Ajustes…", systemImage: "gearshape")
            }
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })

            if let error = appState.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()
            Button("Sair", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var statusHeader: some View {
        Label(statusText, systemImage: statusIcon)
            .font(.headline)
            .foregroundStyle(statusColor)
            .symbolEffect(.pulse, isActive: appState.mode == .meeting && !appState.isPaused)
    }

    private var statusText: String {
        guard appState.mode == .meeting else { return "Em standby" }
        return appState.isPaused ? "Gravação pausada" : "Gravando reunião"
    }

    private var statusIcon: String {
        guard appState.mode == .meeting else { return "moon.zzz" }
        return appState.isPaused ? "pause.circle.fill" : "record.circle.fill"
    }

    private var statusColor: Color {
        guard appState.mode == .meeting else { return .primary }
        return appState.isPaused ? .orange : .red
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
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Ignorar") {
                    appState.calendarMonitor.dismissCurrentSuggestion()
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionButton: some View {
        if appState.mode == .meeting {
            if appState.isPaused {
                Button("Retomar gravação", systemImage: "play.circle") {
                    appState.resumeMeeting()
                }
            } else {
                Button("Pausar gravação", systemImage: "pause.circle") {
                    appState.pauseMeeting()
                }
            }
            Button("Encerrar reunião", systemImage: "stop.circle") {
                Task { await appState.endMeeting() }
            }
            .tint(.red)
        } else {
            Button("Iniciar gravação manual", systemImage: "record.circle") {
                Task { await appState.startMeeting() }
            }
        }
    }
}
