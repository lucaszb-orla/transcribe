import FoundationModels

@Generable
struct MeetingSummary: Equatable {
    @Guide(description: "Título curto e descritivo para a reunião, baseado no assunto discutido")
    let title: String

    @Guide(description: "Entre 3 e 8 pontos principais discutidos, em frases curtas e diretas")
    let bullets: [String]

    @Guide(description: "Ações concretas combinadas na reunião, com responsável quando mencionado")
    let actionItems: [String]
}
