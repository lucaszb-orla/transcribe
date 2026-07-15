import SwiftUI

enum OnboardingStage: Int, Hashable {
    case microphone
    case speechRecognition
    case screenRecording
    case calendar
    case complete

    var eyebrow: String {
        switch self {
        case .microphone, .speechRecognition, .screenRecording: "ACESSOS ESSENCIAIS"
        case .calendar: "1 EXTRA, SE VOCÊ QUISER"
        case .complete: "TUDO PRONTO"
        }
    }

    var title: String {
        switch self {
        case .microphone: "Primeiro, seu microfone"
        case .speechRecognition: "Agora, reconhecer sua fala"
        case .screenRecording: "E o áudio dos participantes"
        case .calendar: "Quer conectar o Calendário?"
        case .complete: "Tudo pronto."
        }
    }

    var detail: String {
        switch self {
        case .microphone: "Captura o que você diz durante a reunião. O áudio é processado no próprio Mac."
        case .speechRecognition: "Transforma as falas em texto ao vivo usando o reconhecimento on-device da Apple."
        case .screenRecording: "O macOS exige Gravação de Tela para capturar somente o áudio do sistema. Nenhum vídeo é salvo."
        case .calendar: "O Transcribe pode avisar quando uma reunião com link estiver começando. Você também pode ativar isso depois."
        case .complete: "As permissões essenciais estão ativas. Você já pode começar sua primeira transcrição."
        }
    }

    var icon: String {
        switch self {
        case .microphone: "mic.fill"
        case .speechRecognition: "waveform"
        case .screenRecording: "rectangle.on.rectangle"
        case .calendar: "calendar.badge.plus"
        case .complete: "checkmark.seal.fill"
        }
    }

    var privacySettingsAnchor: String? {
        switch self {
        case .microphone: "Privacy_Microphone"
        case .speechRecognition: "Privacy_SpeechRecognition"
        case .screenRecording: "Privacy_ScreenCapture"
        case .calendar: "Privacy_Calendars"
        case .complete: nil
        }
    }
}

enum OnboardingFlow {
    static func stage(
        for permissions: PermissionSnapshot,
        showCompletion: Bool = false
    ) -> OnboardingStage {
        if showCompletion {
            return .complete
        }

        if permissions.microphone != .granted {
            return .microphone
        }

        if permissions.speechRecognition != .granted {
            return .speechRecognition
        }

        if permissions.screenRecording != .granted {
            return .screenRecording
        }

        return .calendar
    }
}

struct OnboardingReplay {
    private(set) var stage: OnboardingStage = .microphone

    var grantedRequiredCount: Int {
        switch stage {
        case .microphone: 0
        case .speechRecognition: 1
        case .screenRecording: 2
        case .calendar, .complete: PermissionSnapshot.requiredCount
        }
    }

    mutating func advance() {
        switch stage {
        case .microphone: stage = .speechRecognition
        case .speechRecognition: stage = .screenRecording
        case .screenRecording: stage = .calendar
        case .calendar: stage = .complete
        case .complete: break
        }
    }
}

struct OnboardingPermissionPanel: View {
    var stage: OnboardingStage
    var status: PermissionStatus
    var grantedRequiredCount: Int
    var reduceMotion: Bool
    var primaryTitle: String
    var secondaryTitle: String?
    var primaryAction: () -> Void
    var secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(stage.eyebrow)
                    .font(.caption2.weight(.semibold))
                    .tracking(1.7)
                    .foregroundStyle(.white.opacity(0.52))
                    .contentTransition(.opacity)

                Spacer()

                Text("\(grantedRequiredCount)/\(PermissionSnapshot.requiredCount)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(grantedRequiredCount)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(grantedRequiredCount) de 3 permissões essenciais")
            }

            Spacer(minLength: 38)

            Image(systemName: stage.icon)
                .font(.system(size: 43, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(stage == .complete ? .green : .white)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .accessibilityHidden(true)

            Text(stage.title)
                .font(.system(size: 32, weight: .semibold))
                .tracking(-0.7)
                .foregroundStyle(.white.opacity(0.96))
                .contentTransition(.opacity)
                .padding(.top, 24)

            Text(stage.detail)
                .font(.body)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .padding(.top, 12)

            if status == .denied, stage != .complete {
                Label("Acesso negado. Você pode alterá-lo nos Ajustes do Sistema.", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                    .transition(.opacity)
            }

            Spacer(minLength: 28)

            HStack(spacing: 14) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                if let secondaryTitle {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.borderless)
                        .controlSize(.large)
                }
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.18) : .easeOut(duration: 0.45),
            value: stage
        )
        .animation(.easeOut(duration: 0.18), value: status)
    }
}
