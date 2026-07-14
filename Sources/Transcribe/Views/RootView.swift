import SwiftUI

/// Gates the app behind onboarding until mic/speech/calendar access are all granted.
struct RootView: View {
    @Environment(PermissionsManager.self) private var permissions

    var body: some View {
        if permissions.allGranted {
            MeetingListView()
        } else {
            OnboardingView { permissions.refresh() }
        }
    }
}
