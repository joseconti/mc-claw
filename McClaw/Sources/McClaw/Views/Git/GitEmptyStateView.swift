import SwiftUI

/// Empty state shown when no Git connector is connected.
struct GitEmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "No Git Connector", bundle: .appModule),
                systemImage: "chevron.left.forwardslash.chevron.right"
            )
        } description: {
            Text("Connect a GitHub or GitLab connector in Settings → Connectors to browse your repositories.", bundle: .appModule)
        } actions: {
            Button {
                AppState.shared.pendingSettingsTab = "connectors"
                AppState.shared.pendingNavigationSection = .settings
            } label: {
                Text("Open Connectors", bundle: .appModule)
            }
            .buttonStyle(.bordered)
        }
    }
}
