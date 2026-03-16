import Foundation
import Logging

/// Plugin management placeholder.
/// Plugins previously ran in an external Gateway (Node.js).
/// This stub preserves the API surface so existing UI compiles.
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

    func refreshPlugins() async {
        // No-op: plugins require an external runtime
    }

    func install(packageName: String) async {
        statusMessage = String(localized: "Plugin installation is not available in standalone mode.", bundle: .appModule)
    }

    func uninstall(packageName: String) async {
        statusMessage = String(localized: "Plugin removal is not available in standalone mode.", bundle: .appModule)
    }

    func toggle(packageName: String, enabled: Bool) async {
        statusMessage = String(localized: "Plugin toggle is not available in standalone mode.", bundle: .appModule)
    }
}
