import SwiftUI

/// Gates the app behind onboarding until permissions are granted, then shows the live recording
/// screen while a meeting is in progress or the meeting list otherwise.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(PermissionsManager.self) private var permissions
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .animation(.smooth(duration: 0.35), value: appState.mode)
            .animation(.smooth(duration: 0.35), value: permissions.needsOnboarding)
            .onChange(of: scenePhase) {
                if scenePhase == .active { appState.syncCalendarIntegration() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if permissions.needsOnboarding {
            OnboardingView { permissions.refresh() }
                .transition(.opacity)
        } else if appState.mode == .meeting {
            RecordingView()
                .frame(minWidth: 480, minHeight: 420)
                .transition(.opacity)
        } else {
            MeetingListView()
                .transition(.opacity)
        }
    }
}
