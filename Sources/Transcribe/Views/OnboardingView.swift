import AppKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(PermissionsManager.self) private var permissions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var privacyPercentage = 0
    @State private var showCompletion = false

    var onFinished: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.026, blue: 0.03)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                privacyColumn
                    .frame(minWidth: 300, idealWidth: 336, maxWidth: 380)

                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 38)

                OnboardingPermissionPanel(
                    stage: stage,
                    status: activeStatus,
                    grantedRequiredCount: permissions.grantedRequiredCount,
                    reduceMotion: reduceMotion,
                    primaryTitle: primaryTitle,
                    secondaryTitle: secondaryTitle,
                    primaryAction: performPrimaryAction,
                    secondaryAction: performSecondaryAction
                )
                .frame(minWidth: 410, maxWidth: .infinity)
                .padding(.horizontal, 42)
                .padding(.vertical, 38)
            }

            ChromeBorderView(
                progress: Double(permissions.grantedRequiredCount) / Double(PermissionSnapshot.requiredCount)
            )
            .padding(12)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: permissions.grantedRequiredCount)
        }
        .frame(minWidth: 820, idealWidth: 820, minHeight: 560, idealHeight: 560)
        .preferredColorScheme(.dark)
        .onAppear {
            permissions.refresh()
            if reduceMotion {
                privacyPercentage = 100
            } else {
                withAnimation(.easeOut(duration: 0.8)) { privacyPercentage = 100 }
            }
        }
        .onChange(of: reduceMotion) {
            if reduceMotion { privacyPercentage = 100 }
        }
    }

    private var privacyColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TRANSCRIBE")
                .font(.caption2.weight(.semibold))
                .tracking(2.4)
                .foregroundStyle(.white.opacity(0.58))

            Spacer(minLength: 12)

            Image("OnboardingHero")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 250, maxHeight: 250)
                .accessibilityHidden(true)

            Spacer(minLength: 12)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(privacyPercentage)")
                    .font(.system(size: 62, weight: .semibold, design: .rounded))
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(privacyPercentage)))
                Text("%")
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(privacyPercentage) por cento no seu Mac")

            Text("no seu Mac")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text("Seu áudio não vai para a nuvem. A transcrição e o resumo acontecem aqui.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.leading, 44)
        .padding(.trailing, 36)
        .padding(.vertical, 38)
    }

    private var stage: OnboardingStage {
        OnboardingFlow.stage(
            for: permissions.snapshot,
            showCompletion: showCompletion
        )
    }

    private var activeStatus: PermissionStatus {
        switch stage {
        case .microphone: permissions.microphone
        case .speechRecognition: permissions.speechRecognition
        case .screenRecording: permissions.screenRecording
        case .calendar: permissions.calendar
        case .complete: .granted
        }
    }

    private var primaryTitle: String {
        switch stage {
        case .microphone, .speechRecognition, .screenRecording:
            activeStatus == .denied ? "Abrir Ajustes" : "Permitir"
        case .calendar:
            switch activeStatus {
            case .granted: "Continuar"
            case .denied: "Abrir Ajustes"
            case .notDetermined: "Conectar Calendário"
            }
        case .complete: "Ver minhas reuniões"
        }
    }

    private var secondaryTitle: String? {
        switch stage {
        case .screenRecording where activeStatus == .denied: "Reiniciar o Transcribe"
        case .calendar: "Agora não"
        default: nil
        }
    }

    private func performPrimaryAction() {
        switch stage {
        case .microphone:
            if activeStatus == .denied { openPrivacySettings(for: stage) }
            else { Task { await permissions.requestMicrophone() } }
        case .speechRecognition:
            if activeStatus == .denied { openPrivacySettings(for: stage) }
            else { Task { await permissions.requestSpeechRecognition() } }
        case .screenRecording:
            if activeStatus == .denied { openPrivacySettings(for: stage) }
            else { permissions.requestScreenRecording() }
        case .calendar:
            if activeStatus == .denied {
                openPrivacySettings(for: stage)
            } else if activeStatus == .granted {
                showReady()
            } else {
                Task {
                    await appState.requestCalendarIntegration()
                    showReady()
                }
            }
        case .complete:
            permissions.completeOnboarding()
            onFinished()
        }
    }

    private func performSecondaryAction() {
        switch stage {
        case .screenRecording: relaunchApp()
        case .calendar: showReady()
        default: break
        }
    }

    private func showReady() {
        if reduceMotion { showCompletion = true }
        else { withAnimation(.easeOut(duration: 0.45)) { showCompletion = true } }
    }

    private func openPrivacySettings(for stage: OnboardingStage) {
        guard let anchor = stage.privacySettingsAnchor,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
