import TipKit

/// Contextual first-run tips for the "Specs de implementação" feature, the least discoverable
/// part of the app: turning a transcript into tasks that Claude Code implements, commits, pushes,
/// and opens a PR for autonomously. TipKit persists "already seen" itself (`Tips.configure()` in
/// `TranscribeApp`), so these are just the tip definitions plus where they're anchored.

/// Shown once on the "Specs de implementação" toolbar button in `MeetingDetailView` — most users
/// won't guess a hammer icon turns a meeting into dev tasks.
struct DevSpecsEntryTip: Tip {
    var title: Text { Text("Vire a reunião em tarefas de dev") }
    var message: Text? {
        Text("Gere specs de implementação a partir da transcrição e mande o Claude Code implementar sozinho.")
    }
    var image: Image? { Image(systemName: "hammer") }
}

/// Shown inline in `DevSpecsView`, next to "Abrir no Claude Code" — the single most important
/// thing a first-time user needs to know before clicking: this isn't a preview, it really runs.
struct DevSpecsRunTip: Tip {
    var title: Text { Text("Isso roda de verdade") }
    var message: Text? {
        Text("Abre um Terminal e deixa o Claude Code implementar, commitar, dar push e abrir Pull Request sozinho, sem pedir confirmação a cada passo.")
    }
    var image: Image? { Image(systemName: "terminal") }
}
