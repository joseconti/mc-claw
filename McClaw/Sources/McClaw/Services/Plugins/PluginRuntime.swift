import Foundation
import Logging

/// Manages compatible plugins via the Gateway.
/// Plugins run in the Gateway (Node.js), not in the Swift app.
@MainActor
@Observable
final class PluginRuntime {
    static let shared = PluginRuntime()

    private let logger = Logger(label: "ai.mcclaw.plugins")

    var plugins: [PluginInfo] = []
    var isLoading = false
    var error: String?
    var statusMessage: String?
    private var busyPlugins: Set<String> = []

    private init() {}

    func isBusy(plugin: PluginInfo) -> Bool {
        busyPlugins.contains(plugin.name)
    }

    /// Refresh the list of installed plugins from Gateway.
    func refreshPlugins() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            plugins = try await GatewayConnectionService.shared.pluginsList()
            AppState.shared.loadedPlugins = plugins
        } catch {
            self.error = error.localizedDescription
            logger.error("Plugin refresh failed: \(error)")
        }
        isLoading = false
    }

    /// Install a plugin via npm.
    func install(packageName: String) async {
        await withBusy(packageName) {
            do {
                try await GatewayConnectionService.shared.pluginInstall(packageName: packageName)
                self.statusMessage = "Installed \(packageName)"
                self.logger.info("Plugin installed: \(packageName)")
            } catch {
                self.statusMessage = "Install failed: \(error.localizedDescription)"
            }
            await self.refreshPlugins()
        }
    }

    /// Uninstall a plugin.
    func uninstall(packageName: String) async {
        await withBusy(packageName) {
            do {
                try await GatewayConnectionService.shared.pluginUninstall(packageName: packageName)
                self.statusMessage = "Uninstalled \(packageName)"
                self.logger.info("Plugin uninstalled: \(packageName)")
            } catch {
                self.statusMessage = "Uninstall failed: \(error.localizedDescription)"
            }
            await self.refreshPlugins()
        }
    }

    /// Toggle a plugin's enabled state.
    func toggle(packageName: String, enabled: Bool) async {
        await withBusy(packageName) {
            do {
                try await GatewayConnectionService.shared.pluginToggle(
                    packageName: packageName, enabled: enabled
                )
                self.statusMessage = enabled ? "Plugin enabled" : "Plugin disabled"
            } catch {
                self.statusMessage = "Toggle failed: \(error.localizedDescription)"
            }
            await self.refreshPlugins()
        }
    }

    private func withBusy(_ id: String, _ work: @escaping () async -> Void) async {
        busyPlugins.insert(id)
        defer { busyPlugins.remove(id) }
        await work()
    }
}
