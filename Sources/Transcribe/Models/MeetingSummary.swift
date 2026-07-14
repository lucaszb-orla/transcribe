import FoundationModels

/// What the user asks for before generating a summary (chosen in the meeting detail view).
struct SummaryOptions: Equatable, Hashable, Codable {
    enum Format: String, CaseIterable, Identifiable, Codable {
        case bullets, prose
        var id: String { rawValue }
        var label: String { self == .bullets ? "Tópicos" : "Prosa" }
    }

    var format: Format = .bullets
    var includeActionItems: Bool = true
    /// Free-text guidance appended to the model instructions (e.g. "foque nas decisões de produto").
    var customInstructions: String = ""
}

/// Normalized summary the app stores/renders, independent of which format was generated.
struct SummaryResult {
    var title: String
    var bullets: [String]
    var prose: String?
    var actionItems: [String]
}

@Generable
struct GeneratedBulletSummary {
    @Guide(description: "Título curto e descritivo para a reunião, baseado no assunto discutido")
    let title: String

    @Guide(description: "Entre 3 e 8 pontos principais discutidos, em frases curtas e diretas")
    let bullets: [String]

    @Guide(description: "Ações concretas combinadas na reunião, com responsável quando mencionado. Lista vazia se não houver nenhuma.")
    let actionItems: [String]
}

@Generable
struct GeneratedProseSummary {
    @Guide(description: "Título curto e descritivo para a reunião, baseado no assunto discutido")
    let title: String

    @Guide(description: "Resumo em 1 a 3 parágrafos de prosa corrida, objetivo e sem inventar informação")
    let prose: String

    @Guide(description: "Ações concretas combinadas na reunião, com responsável quando mencionado. Lista vazia se não houver nenhuma.")
    let actionItems: [String]
}
