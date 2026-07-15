import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            if appState.mode == .standby, let suggestion = appState.suggestion {
                Divider()
                suggestionBanner(suggestion)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
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
        .animation(.smooth, value: appState.suggestion)
        .animation(.smooth, value: appState.mode)
        .animation(.smooth, value: appState.isPaused)
        .endMeetingConfirmation(isPresented: $confirmEnd) {
            Task { await appState.endMeeting() }
        }
    }

    private var statusHeader: some View {
        Label(statusText, systemImage: statusIcon)
            .font(.headline)
            .foregroundStyle(statusColor)
            .symbolEffect(.pulse, isActive: appState.mode == .meeting && !appState.isPaused && !reduceMotion)
    }

    private var statusText: String {
        guard appState.mode == .meeting else { return "Em espera" }
        return appState.isPaused ? "Pausado" : "Gravando"
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
                Button("Iniciar transcrição") {
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
                Button("Retomar transcrição", systemImage: "play.circle") {
                    appState.resumeMeeting()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Pausar transcrição", systemImage: "pause.circle") {
                    appState.pauseMeeting()
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Encerrar transcrição", systemImage: "stop.circle") {
                confirmEnd = true
            }
            .tint(.red)
        } else if appState.suggestion == nil {
            // Primary action in standby — the calendar suggestion banner already carries a prominent
            // CTA, so only emphasize here when there's no banner (avoids two competing blue buttons).
            Button("Nova transcrição", systemImage: "record.circle") {
                Task { await appState.startMeeting() }
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button("Nova transcrição", systemImage: "record.circle") {
                Task { await appState.startMeeting() }
            }
        }
    }
}
