import Foundation
import FoundationModels

/// Turns a finished transcript into a title, bullet-point summary and action items,
/// entirely on-device via the Foundation Models framework (PRD: no cloud AI in v1).
enum Summarizer {
    enum SummarizerError: LocalizedError {
        case modelUnavailable(SystemLanguageModel.Availability.UnavailableReason)

        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return "O Apple Intelligence não está ativado. Ative em Ajustes do Sistema › Apple Intelligence e Siri para gerar resumos automáticos."
                case .deviceNotEligible:
                    return "Este Mac não é compatível com o Apple Intelligence, então o resumo automático fica indisponível."
                case .modelNotReady:
                    return "O modelo do Apple Intelligence ainda está sendo baixado. Tente novamente em alguns minutos."
                @unknown default:
                    return "O resumo automático (Apple Intelligence) está indisponível no momento."
                }
            }
        }
    }

    static func summarize(transcript: String, calendarContext: String?) async throws -> MeetingSummary {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            if case .unavailable(let reason) = model.availability {
                throw SummarizerError.modelUnavailable(reason)
            }
            throw SummarizerError.modelUnavailable(.deviceNotEligible)
        }

        let session = LanguageModelSession(model: model) {
            "Você resume transcrições de reuniões de trabalho em português do Brasil, de forma objetiva e sem inventar informação que não está no texto."
        }

        var prompt = "Transcrição da reunião:\n\(transcript)"
        if let calendarContext, !calendarContext.isEmpty {
            prompt = "Contexto do evento de calendário: \(calendarContext)\n\n\(prompt)"
        }

        let response = try await session.respond(to: prompt, generating: MeetingSummary.self)
        return response.content
    }
}
