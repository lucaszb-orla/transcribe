import Foundation

/// A single implementation task extracted from a meeting, to be handed to the Claude Code CLI.
struct DevSpec: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var description: String
    var repoPath: String? = nil
}
