import Foundation

/// Named, reusable `SummaryOptions` presets so the user picks a meeting type
/// ("Daily / Standup", "Call de vendas") instead of reconfiguring options each time.
/// `SummaryOptions` conforms to Codable at its declaration (see MeetingSummary.swift).

struct SummaryPreset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var options: SummaryOptions
}

/// Persists `[SummaryPreset]` to UserDefaults as JSON; seeds pt-BR defaults on first run.
@MainActor
@Observable
final class SummaryPresetStore {
    var presets: [SummaryPreset] {
        didSet { save() }
    }

    private static let key = "summaryPresets"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([SummaryPreset].self, from: data) {
            presets = stored
        } else {
            presets = Self.defaults
        }
    }

    func add(name: String, options: SummaryOptions) {
        presets.append(SummaryPreset(name: name, options: options))
    }

    func delete(_ preset: SummaryPreset) {
        presets.removeAll { $0.id == preset.id }
    }

    func update(_ preset: SummaryPreset) {
        guard let i = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[i] = preset
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private static let defaults: [SummaryPreset] = [
        SummaryPreset(name: "Reunião geral",
                      options: SummaryOptions(format: .bullets, includeActionItems: true)),
        SummaryPreset(name: "Daily / Standup",
                      options: SummaryOptions(format: .bullets, includeActionItems: true,
                                              customInstructions: "Foque nos bloqueios de cada pessoa e nos próximos passos combinados.")),
        SummaryPreset(name: "Call de vendas",
                      options: SummaryOptions(format: .prose, includeActionItems: true,
                                              customInstructions: "Destaque as necessidades e objeções do cliente e os próximos passos comerciais.")),
        SummaryPreset(name: "1:1",
                      options: SummaryOptions(format: .prose, includeActionItems: true)),
    ]
}
