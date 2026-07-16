import Foundation

/// What the user picks before generating/running dev specs (mirrors `SummaryOptions`).
struct DevSpecOptions: Equatable, Hashable, Codable {
    var customInstructions: String = ""
    var model: ClaudeModel = .sonnet
    var effort: ClaudeEffort = .medium
}

/// Aliases accepted by the `claude` CLI's `--model` flag.
enum ClaudeModel: String, CaseIterable, Identifiable, Codable {
    case sonnet, opus, fable, haiku
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Values accepted by the `claude` CLI's `--effort` flag.
enum ClaudeEffort: String, CaseIterable, Identifiable, Codable {
    case low, medium, high, xhigh, max
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: "Baixo"
        case .medium: "Médio"
        case .high: "Alto"
        case .xhigh: "Muito alto"
        case .max: "Máximo"
        }
    }
}
