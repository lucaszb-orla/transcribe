import Foundation

/// A single implementation task extracted from a meeting, to be handed to the Claude Code CLI.
struct DevSpec: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var description: String
    var repoPath: String? = nil
    var result: DevSpecResult? = nil
}

struct DevSpecResult: Codable, Hashable {
    enum Status: String, Codable {
        case success, failure
    }

    var status: Status
    var prURL: String? = nil
    /// pt-BR summary (success) or error message (failure).
    var message: String
    var finishedAt: Date
}
