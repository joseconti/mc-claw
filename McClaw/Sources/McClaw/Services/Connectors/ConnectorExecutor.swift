import Foundation
import Logging

/// Dispatches connector action executions: loads credentials, refreshes tokens, calls providers.
actor ConnectorExecutor {
    static let shared = ConnectorExecutor()

    private let logger = Logger(label: "ai.mcclaw.connector-executor")

    /// Registered providers keyed by definition ID.
    private var providers: [String: any ConnectorProvider]

    init() {
        var initial: [String: any ConnectorProvider] = [:]

        // Google providers
        initial[GmailProvider.definitionId] = GmailProvider()
        initial[GoogleCalendarProvider.definitionId] = GoogleCalendarProvider()
        initial[GoogleDriveProvider.definitionId] = GoogleDriveProvider()
        initial[GoogleSheetsProvider.definitionId] = GoogleSheetsProvider()
        initial[GoogleContactsProvider.definitionId] = GoogleContactsProvider()

        // Dev providers
        initial[GitHubProvider.definitionId] = GitHubProvider()
        initial[GitLabProvider.definitionId] = GitLabProvider()
        initial[LinearProvider.definitionId] = LinearProvider()
        initial[JiraProvider.definitionId] = JiraProvider()
        initial[NotionProvider.definitionId] = NotionProvider()

        // Communication providers
        initial[SlackProvider.definitionId] = SlackProvider()
        initial[DiscordProvider.definitionId] = DiscordProvider()
        initial[TelegramProvider.definitionId] = TelegramProvider()

        // Microsoft providers
        initial[OutlookMailProvider.definitionId] = OutlookMailProvider()
        initial[OutlookCalendarProvider.definitionId] = OutlookCalendarProvider()
        initial[OneDriveProvider.definitionId] = OneDriveProvider()
        initial[MicrosoftToDoProvider.definitionId] = MicrosoftToDoProvider()

        // Productivity providers
        initial[TodoistProvider.definitionId] = TodoistProvider()
        initial[TrelloProvider.definitionId] = TrelloProvider()
        initial[AirtableProvider.definitionId] = AirtableProvider()
        initial[DropboxProvider.definitionId] = DropboxProvider()

        // Utility providers
        initial[WeatherProvider.definitionId] = WeatherProvider()
        initial[RSSProvider.definitionId] = RSSProvider()
        initial[WebhookProvider.definitionId] = WebhookProvider()

        // WordPress/WooCommerce — single provider, single connection, all abilities via MCP bridge
        initial[WordPressProvider.definitionId] = WordPressProvider()

        providers = initial
    }

    // MARK: - Provider Registration

    func registerProvider(_ provider: any ConnectorProvider) {
        let id = type(of: provider).definitionId
        providers[id] = provider
        logger.debug("Registered provider: \(id)")
    }

    // MARK: - Execution

    /// Execute a connector action by instance ID.
    /// Handles credential loading, token refresh, and provider dispatch.
    func execute(
        instanceId: String,
        actionId: String,
        params: [String: String] = [:]
    ) async throws -> ConnectorActionResult {
        // Get instance and definition
        let instance = await MainActor.run { ConnectorStore.shared.instance(for: instanceId) }
        guard let instance else {
            throw ConnectorExecutorError.instanceNotFound(instanceId)
        }

        guard let provider = providers[instance.definitionId] else {
            throw ConnectorExecutorError.noProvider(instance.definitionId)
        }

        // Load credentials
        var credentials = await KeychainService.shared.loadCredentials(instanceId: instanceId)
        guard var credentials else {
            throw ConnectorProviderError.noCredentials
        }

        // Refresh token if expired
        if credentials.isExpired {
            logger.info("Token expired for \(instanceId), attempting refresh")
            if let refreshed = try await provider.refreshTokenIfNeeded(credentials: credentials) {
                credentials = refreshed
                try await KeychainService.shared.saveCredentials(instanceId: instanceId, credentials: refreshed)
                logger.info("Token refreshed for \(instanceId)")
            } else {
                throw ConnectorProviderError.tokenExpiredReauthRequired
            }
        }

        // Execute the action
        logger.info("Executing \(instance.definitionId).\(actionId) for instance \(instanceId)")
        let result = try await provider.execute(action: actionId, params: params, credentials: credentials)

        // Update last sync timestamp
        await MainActor.run {
            ConnectorStore.shared.setConnected(id: instanceId, connected: true)
        }

        return result
    }

    /// Test connection for a connector instance.
    func testConnection(instanceId: String) async throws -> Bool {
        let instance = await MainActor.run { ConnectorStore.shared.instance(for: instanceId) }
        guard let instance else {
            throw ConnectorExecutorError.instanceNotFound(instanceId)
        }

        guard let provider = providers[instance.definitionId] else {
            throw ConnectorExecutorError.noProvider(instance.definitionId)
        }

        guard let credentials = await KeychainService.shared.loadCredentials(instanceId: instanceId) else {
            throw ConnectorProviderError.noCredentials
        }

        return try await provider.testConnection(credentials: credentials)
    }

    /// Check if a provider is registered for a definition ID.
    func hasProvider(for definitionId: String) -> Bool {
        providers[definitionId] != nil
    }
}

// MARK: - Executor Errors

enum ConnectorExecutorError: LocalizedError {
    case instanceNotFound(String)
    case noProvider(String)

    var errorDescription: String? {
        switch self {
        case .instanceNotFound(let id): "Connector instance not found: \(id)"
        case .noProvider(let id): "No provider registered for: \(id)"
        }
    }
}
