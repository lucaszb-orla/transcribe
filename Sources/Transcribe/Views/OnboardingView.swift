import AppKit
import SwiftUI

/// Shown until mic, calendar, and speech-recognition access are all granted. Each permission is
/// requested explicitly (see `PermissionsManager`) instead of hoping AVAudioEngine/SpeechAnalyzer's
/// implicit first-use prompt fires reliably.
struct OnboardingView: View {
    @Environment(PermissionsManager.self) private var permissions
    var onFinished: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bem-vindo ao Transcribe").font(.title2).bold()
                Text("Antes de começar, precisamos de quatro permissões do macOS.")
                    .foregroundStyle(.secondary)
            }

            List {
                row(
                    icon: "mic.fill",
                    title: "Microfone",
                    detail: "Grava sua fala durante as reuniões.",
                    status: permissions.microphone
                ) { Task { await permissions.requestMicrophone() } }

                row(
                    icon: "waveform",
                    title: "Reconhecimento de fala",
                    detail: "Transcreve o áudio no dispositivo.",
                    status: permissions.speechRecognition
                ) { Task { await permissions.requestSpeechRecognition() } }

                row(
                    icon: "calendar",
                    title: "Calendário",
                    detail: "Sugere gravação quando uma reunião com link está prestes a começar.",
                    status: permissions.calendar
                ) { Task { await permissions.requestCalendar() } }

                screenRecordingRow
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 250)

            HStack {
                if [permissions.microphone, permissions.speechRecognition, permissions.calendar, permissions.screenRecording].contains(.denied) {
                    Button("Abrir Ajustes do Sistema") { openPrivacySettings() }
                }
                Spacer()
                Button("Continuar") { onFinished() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!permissions.allGranted)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 460)
        .onAppear { permissions.refresh() }
    }

    private func row(icon: String, title: String, detail: String, status: PermissionStatus, request: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusControl(status, request: request)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusControl(_ status: PermissionStatus, request: @escaping () -> Void) -> some View {
        switch status {
        case .granted:
            Label("Permitido", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.iconOnly)
        case .denied:
            HStack(spacing: 6) {
                Text("Negado").font(.caption).foregroundStyle(.red)
                Button("Abrir Ajustes", action: openPrivacySettings)
                    .controlSize(.small)
            }
        case .notDetermined:
            Button("Permitir", action: request)
                .controlSize(.small)
        }
    }

    /// Screen Recording is special: macOS only re-checks this permission for a process at launch,
    /// so if you grant it in System Settings while Transcribe is already running, `CGPreflightScreenCaptureAccess`
    /// keeps reporting the old (denied) state until the app is relaunched — it's not a bug in our check.
    private var screenRecordingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gravação de tela").font(.headline)
                    Text("Necessária para capturar o áudio do sistema (os outros participantes), mesmo sem gravar vídeo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if permissions.screenRecording == .granted {
                    Label("Permitido", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.iconOnly)
                } else {
                    Button("Permitir") { permissions.requestScreenRecording() }
                        .controlSize(.small)
                }
            }
            if permissions.screenRecording != .granted {
                HStack(spacing: 6) {
                    Text("Já ativou em Ajustes do Sistema e continua marcado como pendente aqui?")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Reiniciar o Transcribe") { relaunchApp() }
                        .font(.caption2)
                }
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Screen Recording grants only take effect for a *new* process, so this is the only way to make
    /// the app pick up a permission the user just flipped on in System Settings.
    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
