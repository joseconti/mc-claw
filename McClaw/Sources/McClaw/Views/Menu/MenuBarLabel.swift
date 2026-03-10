import SwiftUI

/// Menu bar icon with animated state indicator.
struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Image(systemName: iconName)
            .symbolEffect(.pulse, isActive: appState.isWorking)
    }

    private var iconName: String {
        if appState.isPaused {
            return "pause.circle"
        } else if appState.isWorking {
            return "brain.head.profile"
        } else if appState.talkModeEnabled {
            return "waveform.circle"
        } else {
            return "brain"
        }
    }
}
