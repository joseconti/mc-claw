import Foundation
import Logging

/// Manages connector instances: CRUD, persistence, and header generation.
@MainActor
@Observable
final class ConnectorStore {
    static let shared = ConnectorStore()

    private let logger = Logger(label: "ai.mcclaw.connectors")

    var instances: [ConnectorInstance] = []
    var selectedInstanceId: String?
    var lastError: String?

    /// OAuth client ID for Google/Microsoft (set by user in Settings > Connectors).
    var oauthClientId: String? {
        get { UserDefaults.standard.string(forKey: "mcclaw.oauth.clientId") }
        set { UserDefaults.standard.set(newValue, forKey: "mcclaw.oauth.clientId") }
    }

    /// OAuth client secret for Google/Microsoft (set by user in Settings > Connectors).
    var oauthClientSecret: String? {
        get { UserDefaults.standard.string(forKey: "mcclaw.oauth.clientSecret") }
        set { UserDefaults.standard.set(newValue, forKey: "mcclaw.oauth.clientSecret") }
    }

    private var configFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw")
            .appendingPathComponent("connectors.json")
    }

    // MARK: - Lifecycle

    func start() {
        loadFromDisk()
        logger.info("ConnectorStore started with \(instances.count) instance(s)")
    }

    // MARK: - CRUD

    @discardableResult
    func addInstance(definitionId: String) -> ConnectorInstance? {
        guard let definition = ConnectorRegistry.definition(for: definitionId) else {
            lastError = "Unknown connector: \(definitionId)"
            return nil
        }

        let instance = ConnectorInstance(
            definitionId: definitionId,
            name: definition.name
        )
        instances.append(instance)
        saveToDisk()
        logger.info("Added connector instance: \(definition.name) (\(instance.id))")
        return instance
    }

    func removeInstance(id: String) {
        instances.removeAll { $0.id == id }
        if selectedInstanceId == id { selectedInstanceId = nil }

        // Clean up credentials
        Task {
            await KeychainService.shared.deleteCredentials(instanceId: id)
        }

        saveToDisk()
        logger.info("Removed connector instance: \(id)")
    }

    func updateInstance(_ updated: ConnectorInstance) {
        guard let idx = instances.firstIndex(where: { $0.id == updated.id }) else { return }
        instances[idx] = updated
        saveToDisk()
    }

    func setConnected(id: String, connected: Bool, error: String? = nil) {
        guard let idx = instances.firstIndex(where: { $0.id == id }) else { return }
        instances[idx].isConnected = connected
        instances[idx].lastError = error
        if connected {
            instances[idx].lastSyncAt = Date()
        }
        saveToDisk()
    }

    func updateConfig(id: String, config: [String: String]) {
        guard let idx = instances.firstIndex(where: { $0.id == id }) else { return }
        instances[idx].config = config
        saveToDisk()
    }

    // MARK: - Queries

    var connectedInstances: [ConnectorInstance] {
        instances.filter(\.isConnected)
    }

    var connectedCount: Int {
        connectedInstances.count
    }

    func instance(for id: String) -> ConnectorInstance? {
        instances.first { $0.id == id }
    }

    func instances(for definitionId: String) -> [ConnectorInstance] {
        instances.filter { $0.definitionId == definitionId }
    }

    func definition(for instance: ConnectorInstance) -> ConnectorDefinition? {
        ConnectorRegistry.definition(for: instance.definitionId)
    }

    // MARK: - Connectors Header for Prompt Injection

    /// Build the header that gets injected into every prompt sent to CLIs.
    /// Returns nil if no connectors are active.
    func buildConnectorsHeader() -> String? {
        let active = connectedInstances
        guard !active.isEmpty else { return nil }

        var lines: [String] = ["[McClaw Connectors] Available data sources:"]

        for instance in active {
            guard let def = ConnectorRegistry.definition(for: instance.definitionId) else { continue }
            let actionNames = def.actions.map(\.id).joined(separator: ", ")
            lines.append("- \(instance.name.lowercased()): \(actionNames)")
        }

        lines.append("")
        lines.append("To request data, reply with: @fetch(connector.action, param=value)")
        lines.append("The user can also use: /fetch connector.action")

        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: configFileURL) else { return }
        do {
            instances = try JSONDecoder().decode([ConnectorInstance].self, from: data)
        } catch {
            logger.error("Failed to load connectors config: \(error)")
        }
    }

    private func saveToDisk() {
        do {
            let dir = configFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(instances)
            try data.write(to: configFileURL)
        } catch {
            logger.error("Failed to save connectors config: \(error)")
        }
    }
}
