import Foundation

// MARK: - Categories & Auth Types

enum ConnectorCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case google
    case microsoft
    case dev
    case communication
    case productivity
    case utilities
    case wordpress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: String(localized: "Google", bundle: .module)
        case .microsoft: String(localized: "Microsoft", bundle: .module)
        case .dev: String(localized: "Development", bundle: .module)
        case .communication: String(localized: "Communication", bundle: .module)
        case .productivity: String(localized: "Productivity", bundle: .module)
        case .utilities: String(localized: "Utilities", bundle: .module)
        case .wordpress: String(localized: "WordPress", bundle: .module)
        }
    }

    var icon: String {
        switch self {
        case .google: "globe"
        case .microsoft: "rectangle.grid.2x2"
        case .dev: "chevron.left.forwardslash.chevron.right"
        case .communication: "bubble.left.and.bubble.right"
        case .productivity: "checkmark.circle"
        case .utilities: "wrench.and.screwdriver"
        case .wordpress: "w.circle"
        }
    }

    var sortOrder: Int {
        switch self {
        case .google: 0
        case .microsoft: 1
        case .dev: 2
        case .communication: 3
        case .productivity: 4
        case .utilities: 5
        case .wordpress: 6
        }
    }
}

enum ConnectorAuthType: String, Codable, Sendable {
    case oauth2
    case apiKey
    case botToken
    case pat
    case mcpBridge
    case none
}

// MARK: - OAuth Config

struct OAuthConfig: Codable, Equatable, Sendable {
    let authUrl: String
    let tokenUrl: String
    let scopes: [String]
    let redirectScheme: String
    let usePKCE: Bool
    /// Per-connector client ID. Falls back to global ConnectorStore.oauthClientId if nil.
    var clientId: String?
    /// Per-connector client secret. Required by Google/Microsoft for token exchange.
    var clientSecret: String?

    init(
        authUrl: String,
        tokenUrl: String,
        scopes: [String],
        redirectScheme: String = "mcclaw",
        usePKCE: Bool = true,
        clientId: String? = nil,
        clientSecret: String? = nil
    ) {
        self.authUrl = authUrl
        self.tokenUrl = tokenUrl
        self.scopes = scopes
        self.redirectScheme = redirectScheme
        self.usePKCE = usePKCE
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}

// MARK: - Action Definition

struct ConnectorActionDef: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let description: String
    let parameters: [ConnectorActionParam]
    /// Whether this action modifies external data (send email, create event, etc.).
    let isWriteAction: Bool

    init(id: String, name: String, description: String, parameters: [ConnectorActionParam] = [], isWriteAction: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.parameters = parameters
        self.isWriteAction = isWriteAction
    }
}

struct ConnectorActionParam: Codable, Equatable, Sendable {
    let name: String
    let type: String
    let description: String
    let required: Bool
    let defaultValue: String?
    let enumValues: [String]?

    init(
        name: String,
        description: String,
        type: String = "string",
        required: Bool = false,
        defaultValue: String? = nil,
        enumValues: [String]? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.defaultValue = defaultValue
        self.enumValues = enumValues
    }
}

// MARK: - Connector Definition (Static Registry)

struct ConnectorDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let category: ConnectorCategory
    let name: String
    let description: String
    let icon: String
    let authType: ConnectorAuthType
    let oauthConfig: OAuthConfig?
    let actions: [ConnectorActionDef]
    let requiredScopes: [String]

    init(
        id: String,
        category: ConnectorCategory,
        name: String,
        description: String,
        icon: String,
        authType: ConnectorAuthType,
        oauthConfig: OAuthConfig? = nil,
        actions: [ConnectorActionDef] = [],
        requiredScopes: [String] = []
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.description = description
        self.icon = icon
        self.authType = authType
        self.oauthConfig = oauthConfig
        self.actions = actions
        self.requiredScopes = requiredScopes
    }
}

// MARK: - Connector Instance (User-configured)

struct ConnectorInstance: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let definitionId: String
    var name: String
    var isConnected: Bool
    var lastSyncAt: Date?
    var lastError: String?
    var config: [String: String]

    init(
        id: String = UUID().uuidString,
        definitionId: String,
        name: String,
        isConnected: Bool = false,
        lastSyncAt: Date? = nil,
        lastError: String? = nil,
        config: [String: String] = [:]
    ) {
        self.id = id
        self.definitionId = definitionId
        self.name = name
        self.isConnected = isConnected
        self.lastSyncAt = lastSyncAt
        self.lastError = lastError
        self.config = config
    }
}

// MARK: - Credentials (stored in Keychain, NOT in config)

struct ConnectorCredentials: Codable, Sendable {
    var accessToken: String?
    var refreshToken: String?
    var apiKey: String?
    var expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    var hasValidToken: Bool {
        if let accessToken, !accessToken.isEmpty, !isExpired { return true }
        if let apiKey, !apiKey.isEmpty { return true }
        return false
    }
}

// MARK: - Action Result

struct ConnectorActionResult: Sendable {
    let connectorId: String
    let actionId: String
    let data: String
    let timestamp: Date
    let truncated: Bool

    init(connectorId: String, actionId: String, data: String, timestamp: Date = Date(), truncated: Bool = false) {
        self.connectorId = connectorId
        self.actionId = actionId
        self.data = data
        self.timestamp = timestamp
        self.truncated = truncated
    }
}

// MARK: - Connector Binding (for Cron Jobs)

struct ConnectorBinding: Codable, Equatable, Sendable {
    let connectorInstanceId: String
    let actionId: String
    var params: [String: String]
    var maxResultLength: Int

    init(
        connectorInstanceId: String,
        actionId: String,
        params: [String: String] = [:],
        maxResultLength: Int = 4000
    ) {
        self.connectorInstanceId = connectorInstanceId
        self.actionId = actionId
        self.params = params
        self.maxResultLength = maxResultLength
    }
}

// MARK: - Connector Status

enum ConnectorStatus: Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .error(let msg): "Error: \(msg)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
