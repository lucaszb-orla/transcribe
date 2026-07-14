import SwiftUI

@main
struct TranscribeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra(
            "Transcribe",
            systemImage: appState.mode == .meeting ? "waveform.circle.fill" : "waveform.circle"
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
