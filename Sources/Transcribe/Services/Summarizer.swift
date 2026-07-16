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

    static func summarize(transcript: String, calendarContext: String?, options: SummaryOptions) async throws -> SummaryResult {
        let session = try makeSession { instructions(options) }

        var prompt = "Transcrição da reunião:\n\(transcript)"
        if let calendarContext, !calendarContext.isEmpty {
            prompt = "Contexto do evento de calendário: \(calendarContext)\n\n\(prompt)"
        }

        switch options.format {
        case .bullets:
            let r = try await session.respond(to: prompt, generating: GeneratedBulletSummary.self).content
            return SummaryResult(
                title: r.title,
                bullets: r.bullets,
                prose: nil,
                actionItems: options.includeActionItems ? r.actionItems : []
            )
        case .prose:
            let r = try await session.respond(to: prompt, generating: GeneratedProseSummary.self).content
            return SummaryResult(
                title: r.title,
                bullets: [],
                prose: r.prose,
                actionItems: options.includeActionItems ? r.actionItems : []
            )
        }
    }

    /// Splits a meeting transcript into distinct implementation tasks (title + short description).
    /// Deliberately lightweight: the on-device model just separates the meeting into distinct asks,
    /// the actual engineering synthesis happens later when Claude Code reads the full transcript.
    static func generateDevSpecs(transcript: String, calendarContext: String?) async throws -> [DevSpec] {
        let session = try makeSession {
            "Você analisa transcrições de reuniões de trabalho em português do Brasil e identifica " +
            "tarefas de implementação de software distintas mencionadas nela, sem inventar informação " +
            "que não está no texto. Se a reunião não mencionar nada acionável para desenvolvimento, " +
            "devolva a lista vazia."
        }

        var prompt = "Transcrição da reunião:\n\(transcript)"
        if let calendarContext, !calendarContext.isEmpty {
            prompt = "Contexto do evento de calendário: \(calendarContext)\n\n\(prompt)"
        }

        let r = try await session.respond(to: prompt, generating: GeneratedDevSpecList.self).content
        return r.specs.map { DevSpec(title: $0.title, description: $0.description) }
    }

    private static func makeSession(@InstructionsBuilder instructions: () -> Instructions) throws -> LanguageModelSession {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            if case .unavailable(let reason) = model.availability {
                throw SummarizerError.modelUnavailable(reason)
            }
            throw SummarizerError.modelUnavailable(.deviceNotEligible)
        }
        return LanguageModelSession(model: model) { instructions() }
    }

    private static func instructions(_ options: SummaryOptions) -> String {
        var lines = [
            "Você resume transcrições de reuniões de trabalho em português do Brasil, de forma objetiva e sem inventar informação que não está no texto."
        ]
        lines.append(options.format == .bullets
            ? "Escreva o resumo como tópicos curtos."
            : "Escreva o resumo como prosa corrida.")
        if options.includeActionItems {
            lines.append("Extraia também os itens de ação (tarefas combinadas). Se não houver nenhum, devolva a lista vazia.")
        } else {
            lines.append("Não é necessário extrair itens de ação.")
        }
        let custom = options.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            lines.append("Instruções adicionais do usuário: \(custom)")
        }
        return lines.joined(separator: " ")
    }
}
