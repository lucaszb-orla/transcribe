import SwiftUI

@main
struct TranscribeApp: App {
    @State private var appState = AppState()

    /// The UI is written in Brazilian Portuguese, so format dates/numbers to match even when the
    /// Mac's system locale is set to English (otherwise dates render as "14 July 2026").
    private let locale = Locale(identifier: "pt_BR")

    var body: some Scene {
        MenuBarExtra(
            "Transcribe",
            systemImage: appState.mode == .meeting ? "quote.bubble.fill" : "quote.bubble"
        ) {
            MenuBarView()
                .environment(appState)
                .environment(\.locale, locale)
        }
        .menuBarExtraStyle(.window)

        Window("Transcribe", id: "meetings") {
            RootView()
                .environment(appState)
                .environment(appState.permissions)
                .environment(\.locale, locale)
        }
        .defaultLaunchBehavior(.presented)

        Settings {
            SettingsView()
                .environment(appState)
                .environment(\.locale, locale)
        }
    }
}
