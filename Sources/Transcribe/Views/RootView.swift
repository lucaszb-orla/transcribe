import SwiftUI

/// Gates the app behind onboarding until permissions are granted, then shows the live recording
/// screen while a meeting is in progress or the meeting list otherwise.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(PermissionsManager.self) private var permissions

    var body: some View {
        if !permissions.allGranted {
            OnboardingView { permissions.refresh() }
        } else if appState.mode == .meeting {
            RecordingView()
                .frame(minWidth: 480, minHeight: 420)
        } else {
            MeetingListView()
        }
    }
}
