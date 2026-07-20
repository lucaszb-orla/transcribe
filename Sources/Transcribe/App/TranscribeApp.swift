import SwiftUI
import TipKit

@main
struct TranscribeApp: App {
    @State private var appState = AppState()

    init() {
        // One-time setup so the contextual tips (see DevSpecsTips.swift) can track "already seen"
        // themselves. Must run before any `.popoverTip`/`TipView` renders.
        try? Tips.configure()
    }

    var body: some Scene {
        MenuBarExtra(
            "Transcribe",
            systemImage: appState.mode == .meeting ? "quote.bubble.fill" : "quote.bubble"
        ) {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Window("Transcribe", id: "meetings") {
            RootView()
                .environment(appState)
                .environment(appState.permissions)
        }
        .defaultLaunchBehavior(.presented)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
