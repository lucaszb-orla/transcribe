import FoundationModels

/// Turns a finished transcript into a title, bullet-point summary and action items,
/// entirely on-device via the Foundation Models framework (PRD: no cloud AI in v1).
enum Summarizer {
    enum SummarizerError: Error {
        case modelUnavailable(SystemLanguageModel.Availability.UnavailableReason)
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
