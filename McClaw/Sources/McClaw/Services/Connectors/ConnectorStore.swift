import Foundation
import Logging
import McClawKit

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
        get { oauthConfig.clientId }
        set {
            var cfg = oauthConfig
            cfg.clientId = newValue
            saveOAuthConfig(cfg)
        }
    }

    /// OAuth client secret for Google/Microsoft (set by user in Settings > Connectors).
    var oauthClientSecret: String? {
        get { oauthConfig.clientSecret }
        set {
            var cfg = oauthConfig
            cfg.clientSecret = newValue
            saveOAuthConfig(cfg)
        }
    }

    // MARK: - OAuth Config File Persistence

    private struct OAuthConfig: Codable {
        var clientId: String?
        var clientSecret: String?
    }

    private var oauthConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw")
            .appendingPathComponent("oauth-config.json")
    }

    private var oauthConfig: OAuthConfig {
        // Try file first
        if let data = try? Data(contentsOf: oauthConfigURL),
           let config = try? JSONDecoder().decode(OAuthConfig.self, from: data) {
            return config
        }
        // Migrate from UserDefaults if present
        let legacy = OAuthConfig(
            clientId: UserDefaults.standard.string(forKey: "mcclaw.oauth.clientId"),
            clientSecret: UserDefaults.standard.string(forKey: "mcclaw.oauth.clientSecret")
        )
        if legacy.clientId != nil || legacy.clientSecret != nil {
            saveOAuthConfig(legacy)
            UserDefaults.standard.removeObject(forKey: "mcclaw.oauth.clientId")
            UserDefaults.standard.removeObject(forKey: "mcclaw.oauth.clientSecret")
        }
        return legacy
    }

    private func saveOAuthConfig(_ config: OAuthConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: oauthConfigURL, options: .atomic)
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

        var tuples: [(name: String, readActions: [String], writeActions: [String])] = []

        for instance in active {
            guard let def = ConnectorRegistry.definition(for: instance.definitionId) else { continue }
            let readActions = def.actions.filter { !$0.isWriteAction }.map(\.id)
            let writeActions = def.actions.filter { $0.isWriteAction }.map(\.id)
            tuples.append((name: instance.name.lowercased(), readActions: readActions, writeActions: writeActions))
        }

        return ConnectorsKit.buildConnectorsHeader(connectors: tuples)
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
            try data.write(to: configFileURL, options: .atomic)
        } catch {
            logger.error("Failed to save connectors config: \(error)")
        }
    }
}
