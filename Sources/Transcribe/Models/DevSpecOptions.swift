import Foundation

/// What the user picks before generating/running dev specs (mirrors `SummaryOptions`).
struct DevSpecOptions: Equatable, Hashable, Codable {
    var customInstructions: String = ""
    var provider: SpecProvider = .claude
    var model: ClaudeModel = .sonnet
    var effort: ClaudeEffort = .medium
}

/// Which model generates the spec list from the transcript. Apple Intelligence stays fully
/// on-device but is small and less accurate; Claude reads the whole transcript (no context-window
/// juggling needed) using the same CLI already used to run the specs.
enum SpecProvider: String, CaseIterable, Identifiable, Codable {
    case appleIntelligence, claude
    var id: String { rawValue }
    var label: String {
        switch self {
        case .appleIntelligence: String(localized: "Apple Intelligence (on-device)")
        case .claude: String(localized: "Claude (nuvem)")
        }
    }
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
        case .low: String(localized: "Baixo")
        case .medium: String(localized: "Médio")
        case .high: String(localized: "Alto")
        case .xhigh: String(localized: "Muito alto")
        case .max: String(localized: "Máximo")
        }
    }
}
