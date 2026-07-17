import Foundation
import FoundationModels

/// Turns a finished transcript into a title, bullet-point summary and action items,
/// entirely on-device via the Foundation Models framework (PRD: no cloud AI in v1).
enum Summarizer {
    enum SummarizerError: LocalizedError {
        case modelUnavailable(SystemLanguageModel.Availability.UnavailableReason)
        case generationFailed(LanguageModelSession.GenerationError)

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
            case .generationFailed(let error):
                switch error {
                case .exceededContextWindowSize:
                    return "Essa reunião é longa demais para o modelo on-device processar de uma vez. Tente novamente em alguns instantes."
                case .guardrailViolation:
                    return "O Apple Intelligence recusou processar esse conteúdo por segurança."
                default:
                    return "Não foi possível gerar isso com o Apple Intelligence: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Wraps `LanguageModelSession.GenerationError` (context window, guardrails, etc.) in our own
    /// PT-BR-friendly error instead of letting the framework's raw error surface in the UI.
    private static func respond<Content: Generable>(
        _ session: LanguageModelSession, to prompt: String, generating type: Content.Type
    ) async throws -> Content {
        do {
            return try await session.respond(to: prompt, generating: type).content
        } catch let error as LanguageModelSession.GenerationError {
            throw SummarizerError.generationFailed(error)
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
            let r = try await respond(session, to: prompt, generating: GeneratedBulletSummary.self)
            return SummaryResult(
                title: r.title,
                bullets: r.bullets,
                prose: nil,
                actionItems: options.includeActionItems ? r.actionItems : []
            )
        case .prose:
            let r = try await respond(session, to: prompt, generating: GeneratedProseSummary.self)
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
    ///
    /// Long meetings (~30min+) can exceed the on-device model's small context window on their own,
    /// before even counting instructions/output — so the transcript is chunked and each piece
    /// analyzed independently. Specs from different chunks may occasionally duplicate the same ask;
    /// that's an accepted trade-off (specs are editable/removable) for not silently failing instead.
    static func generateDevSpecs(transcript: String, calendarContext: String?, customInstructions: String = "") async throws -> [DevSpec] {
        let chunks = chunkedForContext(transcript)
        var specs: [DevSpec] = []
        for (index, chunk) in chunks.enumerated() {
            let session = try makeSession { devSpecInstructions(customInstructions: customInstructions) }
            var prompt = chunks.count > 1
                ? "Transcrição da reunião (trecho \(index + 1) de \(chunks.count)):\n\(chunk)"
                : "Transcrição da reunião:\n\(chunk)"
            if index == 0, let calendarContext, !calendarContext.isEmpty {
                prompt = "Contexto do evento de calendário: \(calendarContext)\n\n\(prompt)"
            }
            let r = try await respond(session, to: prompt, generating: GeneratedDevSpecList.self)
            specs.append(contentsOf: r.specs.map { DevSpec(title: $0.title, description: $0.description) })
        }
        return specs
    }

    /// Splits a transcript into pieces that fit the on-device model's context window
    /// (`SystemLanguageModel.contextSize`, ~4096 tokens). There's no synchronous tokenizer exposed,
    /// so this uses a conservative ~4 chars/token estimate and reserves half the window for
    /// instructions + expected output, splitting only on whole transcript lines.
    private static func chunkedForContext(_ transcript: String) -> [String] {
        let maxChars = max(2000, (SystemLanguageModel.default.contextSize / 2) * 4)
        guard transcript.count > maxChars else { return [transcript] }

        var chunks: [String] = []
        var current = ""
        for line in transcript.split(separator: "\n", omittingEmptySubsequences: false) {
            if !current.isEmpty, current.count + line.count + 1 > maxChars {
                chunks.append(current)
                current = String(line)
            } else {
                current += (current.isEmpty ? "" : "\n") + line
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
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

    private static func devSpecInstructions(customInstructions: String) -> String {
        var lines = [
            "Você analisa transcrições de reuniões de trabalho em português do Brasil e identifica",
            "tarefas de implementação de software distintas mencionadas nela, sem inventar informação",
            "que não está no texto. Se a reunião não mencionar nada acionável para desenvolvimento,",
            "devolva a lista vazia.",
        ]
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            lines.append("Instruções adicionais do usuário: \(custom)")
        }
        return lines.joined(separator: " ")
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
