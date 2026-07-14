import Foundation
import FoundationModels

/// Turns a finished transcript into a follow-up recap message (e-mail/Slack),
/// entirely on-device via the Foundation Models framework (PRD: no cloud AI in v1).
enum FollowUpDrafter {
    enum Tone: String, CaseIterable, Identifiable {
        case formal, casual
        var id: String { rawValue }
        var label: String {
            switch self {
            case .formal: return "Formal"
            case .casual: return "Descontraído"
            }
        }
    }

    enum FollowUpError: LocalizedError {
        case modelUnavailable(SystemLanguageModel.Availability.UnavailableReason)

        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return "O Apple Intelligence não está ativado. Ative em Ajustes do Sistema › Apple Intelligence e Siri para gerar mensagens de follow-up."
                case .deviceNotEligible:
                    return "Este Mac não é compatível com o Apple Intelligence, então o rascunho de follow-up fica indisponível."
                case .modelNotReady:
                    return "O modelo do Apple Intelligence ainda está sendo baixado. Tente novamente em alguns minutos."
                @unknown default:
                    return "O rascunho de follow-up (Apple Intelligence) está indisponível no momento."
                }
            }
        }
    }

    static func draft(transcript: String, calendarContext: String?, tone: Tone) async throws -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            if case .unavailable(let reason) = model.availability {
                throw FollowUpError.modelUnavailable(reason)
            }
            throw FollowUpError.modelUnavailable(.deviceNotEligible)
        }

        let session = LanguageModelSession(model: model) {
            instructions(tone)
        }

        var prompt = "Transcrição da reunião:\n\(transcript)"
        if let calendarContext, !calendarContext.isEmpty {
            prompt = "Contexto do evento de calendário: \(calendarContext)\n\n\(prompt)"
        }

        return try await session.respond(to: prompt).content
    }

    private static func instructions(_ tone: Tone) -> String {
        let toneLine = tone == .formal
            ? "Use um tom formal e profissional."
            : "Use um tom descontraído e próximo, mas ainda profissional."
        return [
            "Você escreve mensagens de follow-up de reuniões de trabalho em português do Brasil (para e-mail ou Slack), sem inventar informação que não está na transcrição.",
            "Escreva uma mensagem concisa com: saudação, principais pontos discutidos, próximos passos combinados com seus responsáveis, e um encerramento.",
            toneLine,
            "Devolva apenas o texto da mensagem, pronto para copiar e enviar."
        ].joined(separator: " ")
    }
}
