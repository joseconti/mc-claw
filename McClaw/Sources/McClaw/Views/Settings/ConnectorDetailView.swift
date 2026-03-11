import McClawKit
import SwiftUI

/// Detail view for configuring and managing a single connector instance.
struct ConnectorDetailView: View {
    let definition: ConnectorDefinition
    @Binding var instance: ConnectorInstance?
    @State private var store = ConnectorStore.shared
    @State private var isConnecting = false
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var apiKeyInput = ""
    @State private var domainInput = ""
    @State private var serverURLInput = ""
    @State private var botEmailInput = ""
    @State private var userIdInput = ""
    @State private var clientIdInput = ""
    @State private var oauthClientIdInput = ""
    @State private var oauthClientSecretInput = ""
    @State private var errorMessage: String?
    @State private var authMode: AuthMode = .token

    /// Whether this connector supports dual auth (OAuth + PAT).
    private var supportsDualAuth: Bool {
        definition.id == "dev.github" || definition.id == "dev.gitlab"
    }

    /// Whether this connector needs a domain field (Jira).
    private var needsDomain: Bool {
        definition.id == "dev.jira"
    }

    /// Connectors that need a server URL (self-hosted platforms).
    private static let needsServerURL: Set<String> = [
        "comm.matrix", "comm.mattermost", "comm.mastodon",
        "comm.zulip", "comm.rocketchat",
    ]

    /// Connectors that need additional identity fields.
    private static let needsBotEmail: Set<String> = ["comm.zulip"]
    private static let needsUserId: Set<String> = ["comm.rocketchat"]
    private static let needsClientId: Set<String> = ["comm.twitch"]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Close button bar
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.top, 8)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    Divider()
                    connectionSection
                    if instance?.isConnected == true {
                        Divider()
                        actionsSection
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .frame(minWidth: 300)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: definition.icon)
                .font(.title)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .liquidGlass(cornerRadius: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(definition.name)
                    .font(.title2.bold())

                Text(definition.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusIndicator
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        guard let inst = instance else { return .gray }
        if inst.isConnected { return .green }
        if inst.lastError != nil { return .red }
        return .gray
    }

    private var statusText: String {
        guard let inst = instance else { return "Not added" }
        if inst.isConnected { return "Connected" }
        if let error = inst.lastError { return "Error: \(error)" }
        return "Disconnected"
    }

    // MARK: - Connection Section

    @ViewBuilder
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection")
                .font(.headline)

            if supportsDualAuth {
                dualAuthConnectionView
            } else {
                switch definition.authType {
                case .oauth2:
                    oauthConnectionView
                case .apiKey, .pat:
                    if needsDomain {
                        domainApiKeyConnectionView
                    } else {
                        apiKeyConnectionView
                    }
                case .botToken:
                    botTokenConnectionView
                case .mcpBridge:
                    mcpBridgeView
                case .none:
                    noAuthView
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let inst = instance, let lastSync = inst.lastSyncAt {
                Text("Last sync: \(lastSync, style: .relative) ago")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Dual Auth (OAuth + PAT) for GitHub/GitLab

    private var dualAuthConnectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if instance?.isConnected == true {
                connectedActions
            } else {
                Picker("Auth Method", selection: $authMode) {
                    Text("Personal Access Token").tag(AuthMode.token)
                    Text("OAuth").tag(AuthMode.oauth)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                if authMode == .oauth {
                    Button {
                        Task { await connectOAuth() }
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.key")
                            Text("Sign in with \(definition.name)")
                        }
                    }
                    .disabled(isConnecting)
                } else {
                    SecureField("Personal Access Token", text: $apiKeyInput)
                        .mcclawTextField()
                        .frame(maxWidth: 400)

                    tokenFormatHint

                    HStack {
                        Button("Save & Connect") {
                            Task { await connectWithKey() }
                        }
                        .disabled(apiKeyInput.isEmpty || isConnecting)

                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                if isConnecting && authMode == .oauth {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    /// Hint text showing expected token format for the current connector.
    @ViewBuilder
    private var tokenFormatHint: some View {
        if definition.id == "dev.github" {
            Text("Format: ghp_... (classic) or github_pat_... (fine-grained)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        } else if definition.id == "dev.gitlab" {
            Text("Format: glpat-... (GitLab PAT)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - OAuth Connection

    private var oauthConnectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if instance?.isConnected == true {
                connectedActions
            } else {
                TextField("OAuth Client ID", text: $oauthClientIdInput)
                    .mcclawTextField()
                    .frame(maxWidth: 400)

                SecureField("OAuth Client Secret", text: $oauthClientSecretInput)
                    .mcclawTextField()
                    .frame(maxWidth: 400)

                Text("From your \(definition.category == .google ? "Google Cloud Console" : definition.category == .microsoft ? "Azure App Registration" : "developer console") OAuth credentials.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                Link("How to get these credentials →",
                     destination: URL(string: "https://mcclaw.app/docs/#connectors")!)
                    .font(.subheadline)

                Button {
                    Task { await connectOAuth() }
                } label: {
                    HStack {
                        Image(systemName: "person.badge.key")
                        Text("Sign in with \(definition.category == .google ? "Google" : definition.name)")
                    }
                }
                .disabled(isConnecting || oauthClientIdInput.isEmpty || oauthClientSecretInput.isEmpty)

                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .onAppear {
            oauthClientIdInput = store.oauthClientId ?? ""
            oauthClientSecretInput = store.oauthClientSecret ?? ""
        }
    }

    // MARK: - API Key / PAT Connection

    private var apiKeyConnectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if instance?.isConnected == true {
                connectedActions
            } else {
                // Server URL for self-hosted platforms
                if Self.needsServerURL.contains(definition.id) {
                    TextField(serverURLPlaceholder, text: $serverURLInput)
                        .mcclawTextField()
                        .frame(maxWidth: 400)
                    Text(serverURLHint)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                SecureField(tokenLabel, text: $apiKeyInput)
                    .mcclawTextField()
                    .frame(maxWidth: 400)

                tokenHint

                // Extra identity fields
                if Self.needsBotEmail.contains(definition.id) {
                    TextField("Bot email (e.g. mybot-bot@org.zulipchat.com)", text: $botEmailInput)
                        .mcclawTextField()
                        .frame(maxWidth: 400)
                }

                if Self.needsUserId.contains(definition.id) {
                    TextField("User ID", text: $userIdInput)
                        .mcclawTextField()
                        .frame(maxWidth: 400)
                    Text("Found in Administration > Users or your profile.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                if Self.needsClientId.contains(definition.id) {
                    TextField("Client ID", text: $clientIdInput)
                        .mcclawTextField()
                        .frame(maxWidth: 400)
                    Text("From your Twitch Developer Console application.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                HStack {
                    Button("Save & Connect") {
                        Task { await connectWithKey() }
                    }
                    .disabled(apiKeyInput.isEmpty || isConnecting || !extraFieldsValid)

                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    /// Validate that required extra fields are filled.
    private var extraFieldsValid: Bool {
        if Self.needsServerURL.contains(definition.id) && serverURLInput.isEmpty { return false }
        if Self.needsBotEmail.contains(definition.id) && botEmailInput.isEmpty { return false }
        if Self.needsUserId.contains(definition.id) && userIdInput.isEmpty { return false }
        if Self.needsClientId.contains(definition.id) && clientIdInput.isEmpty { return false }
        return true
    }

    private var tokenLabel: String {
        switch definition.id {
        case "comm.matrix": return "Access Token"
        case "comm.mattermost": return "Personal Access Token"
        case "comm.mastodon": return "Access Token"
        case "comm.zulip": return "API Key"
        case "comm.rocketchat": return "Auth Token"
        case "comm.twitch": return "OAuth Token"
        default: return definition.authType == .pat ? "Personal Access Token" : "API Key"
        }
    }

    @ViewBuilder
    private var tokenHint: some View {
        switch definition.id {
        case "comm.matrix":
            Text("Matrix access token. Generate via Element or the Matrix API.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        case "comm.mattermost":
            Text("Create in Account Settings > Security > Personal Access Tokens.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        case "comm.mastodon":
            Text("From your instance's Preferences > Development > New Application.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        case "comm.zulip":
            Text("Found in Settings > Your Bots on your Zulip server.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        case "comm.rocketchat":
            Text("Personal Access Token from My Account > Security.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        case "comm.twitch":
            Text("OAuth token with chat scopes from Twitch Developer Console.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        default:
            EmptyView()
        }
    }

    private var serverURLPlaceholder: String {
        switch definition.id {
        case "comm.matrix": return "https://matrix.org"
        case "comm.mattermost": return "https://your-server.mattermost.com"
        case "comm.mastodon": return "https://mastodon.social"
        case "comm.zulip": return "https://your-org.zulipchat.com"
        case "comm.rocketchat": return "https://your-server.rocket.chat"
        default: return "https://..."
        }
    }

    private var serverURLHint: String {
        switch definition.id {
        case "comm.matrix": return "Your Matrix homeserver URL."
        case "comm.mattermost": return "Your Mattermost server URL (self-hosted or cloud)."
        case "comm.mastodon": return "Your Mastodon instance URL."
        case "comm.zulip": return "Your Zulip server URL."
        case "comm.rocketchat": return "Your Rocket.Chat server URL."
        default: return "Server URL."
        }
    }

    // MARK: - Domain + API Key Connection (Jira)

    private var domainApiKeyConnectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if instance?.isConnected == true {
                connectedActions
            } else {
                TextField("Jira domain (e.g. mycompany)", text: $domainInput)
                    .mcclawTextField()
                    .frame(maxWidth: 400)

                Text("Your Jira URL: https://\(domainInput.isEmpty ? "domain" : domainInput).atlassian.net")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                SecureField("API Token (email:token format)", text: $apiKeyInput)
                    .mcclawTextField()
                    .frame(maxWidth: 400)

                Text("Format: your-email@example.com:your-api-token")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                HStack {
                    Button("Save & Connect") {
                        Task { await connectWithDomainKey() }
                    }
                    .disabled(apiKeyInput.isEmpty || domainInput.isEmpty || isConnecting)

                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Bot Token Connection

    private var botTokenConnectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if instance?.isConnected == true {
                connectedActions
            } else {
                SecureField("Bot Token", text: $apiKeyInput)
                    .mcclawTextField()
                    .frame(maxWidth: 400)

                botTokenFormatHint

                HStack {
                    Button("Validate & Connect") {
                        Task { await connectWithKey() }
                    }
                    .disabled(apiKeyInput.isEmpty || isConnecting)

                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    /// Hint text showing expected bot token format for communication connectors.
    @ViewBuilder
    private var botTokenFormatHint: some View {
        switch definition.id {
        case "comm.slack":
            Text("Format: xoxb-... (Bot User OAuth Token from Slack App settings)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        case "comm.discord":
            Text("Format: Bot token from Discord Developer Portal > Bot section")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        case "comm.telegram":
            Text("Format: 123456789:ABCdefGHIjklMNOpqrSTUvwxYZ (from @BotFather)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        default:
            EmptyView()
        }
    }

    // MARK: - MCP Bridge

    @State private var detectedSites: [MCPWordPressSite] = []

    private var mcpBridgeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if instance?.isConnected == true {
                connectedActions
            } else if !detectedSites.isEmpty {
                // MCP servers found — show detected sites and connect button
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Detected WordPress Sites", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)

                        ForEach(detectedSites) { site in
                            HStack(spacing: 6) {
                                Image(systemName: "globe")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(site.serverName)
                                        .font(.subheadline)
                                    Text(site.siteUrl)
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(site.transport.rawValue)
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .liquidGlass(cornerRadius: 3)
                            }
                        }
                    }
                    .padding(4)
                }

                Button("Connect via MCP") {
                    connectMCPBridge()
                }
            } else {
                // No MCP servers found — show setup instructions
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Setup Required", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)

                        Text("To connect WordPress, you need:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Label("Install MCP Content Manager plugin on your WordPress site", systemImage: "1.circle")
                                .font(.subheadline)
                            Label("Configure the MCP server in McClaw Settings → MCP", systemImage: "2.circle")
                                .font(.subheadline)
                            Label("Come back here and click Connect", systemImage: "3.circle")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.tertiary)

                        Link("Get MCP Content Manager",
                             destination: URL(string: "https://plugins.joseconti.com/en/product/mcp-content-manager-for-wordpress/")!)
                            .font(.subheadline)
                    }
                    .padding(4)
                }
            }

            Divider()

            // Always show available modules
            mcpBridgeModulesPreview
        }
        .onAppear {
            detectedSites = WordPressProvider.detectInstallations()
        }
    }

    /// Preview of all WordPress modules available through MCP Content Manager.
    private var mcpBridgeModulesPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Included Modules (\(MCMAbilitiesCatalog.totalAbilities) abilities)")
                .font(.subheadline.bold())

            ForEach(MCMAbilitiesCatalog.subConnectors, id: \.id) { sub in
                HStack(spacing: 8) {
                    Image(systemName: sub.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    Text(sub.name)
                        .font(.subheadline)

                    Text("(\(sub.abilities.count))")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Text(sub.description)
                        .font(.subheadline)
                        .foregroundStyle(.quaternary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func connectMCPBridge() {
        guard let site = detectedSites.first else { return }
        let inst = instance ?? store.addInstance(definitionId: definition.id)
        guard let inst else { return }
        instance = inst

        // Store site URL as the "apiKey" credential for MCP bridge resolution
        let credentials = ConnectorCredentials(
            accessToken: nil,
            refreshToken: nil,
            apiKey: site.siteUrl,
            expiresAt: nil
        )
        Task {
            try? await KeychainService.shared.saveCredentials(instanceId: inst.id, credentials: credentials)
            store.setConnected(id: inst.id, connected: true)
            self.instance = store.instance(for: inst.id)
        }
    }

    // MARK: - No Auth

    private var noAuthView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This connector does not require authentication.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if instance == nil {
                Button("Add Connector") {
                    let inst = store.addInstance(definitionId: definition.id)
                    if let inst {
                        instance = inst
                        store.setConnected(id: inst.id, connected: true)
                    }
                }
            }
        }
    }

    // MARK: - Connected Actions

    private var connectedActions: some View {
        HStack(spacing: 12) {
            Button("Test Connection") {
                Task { await testConnectionAction() }
            }
            .disabled(isTesting)

            Button("Disconnect") {
                disconnect()
            }
            .foregroundStyle(.red)

            if isTesting {
                ProgressView()
                    .controlSize(.small)
            }

            if let result = testResult {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.success ? .green : .red)
                Text(result.message)
                    .font(.subheadline)
                    .foregroundStyle(result.success ? .green : .red)
            }
        }
    }

    // MARK: - Actions List

    @ViewBuilder
    private var actionsSection: some View {
        if definition.authType == .mcpBridge {
            wpModulesSection
        } else {
            flatActionsSection
        }
    }

    /// Flat list of actions for non-WordPress connectors.
    private var flatActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available Actions")
                .font(.headline)

            ForEach(definition.actions) { action in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "play.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.name)
                            .font(.body)
                        Text(action.description)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        if !action.parameters.isEmpty {
                            Text("Params: \(action.parameters.map(\.name).joined(separator: ", "))")
                                .font(.subheadline)
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// WordPress modules grouped by sub-connector.
    private var wpModulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Available Modules (\(MCMAbilitiesCatalog.totalAbilities) abilities)")
                .font(.headline)

            ForEach(MCMAbilitiesCatalog.subConnectors, id: \.id) { sub in
                HStack(spacing: 8) {
                    Image(systemName: sub.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(sub.name)
                            .font(.body)
                        Text("\(sub.abilities.count) abilities — \(sub.description)")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Actions

    private func connectOAuth() async {
        guard let inst = instance ?? store.addInstance(definitionId: definition.id) else { return }
        instance = inst
        isConnecting = true
        errorMessage = nil

        // Save OAuth credentials globally
        if !oauthClientIdInput.isEmpty {
            store.oauthClientId = oauthClientIdInput
        }
        if !oauthClientSecretInput.isEmpty {
            store.oauthClientSecret = oauthClientSecretInput
        }

        let config = oauthConfig(for: definition)

        do {
            let credentials = try await OAuthService.shared.startOAuthFlow(
                config: config,
                instanceId: inst.id
            )
            try await KeychainService.shared.saveCredentials(instanceId: inst.id, credentials: credentials)
            store.setConnected(id: inst.id, connected: true)
            instance = store.instance(for: inst.id)
        } catch {
            errorMessage = error.localizedDescription
            store.setConnected(id: inst.id, connected: false, error: error.localizedDescription)
            instance = store.instance(for: inst.id)
        }
        isConnecting = false
    }

    private func connectWithKey() async {
        guard let inst = instance ?? store.addInstance(definitionId: definition.id) else { return }
        instance = inst
        isConnecting = true
        errorMessage = nil

        let credentials = ConnectorCredentials(
            accessToken: definition.authType == .botToken ? apiKeyInput : nil,
            refreshToken: nil,
            apiKey: definition.authType != .botToken ? apiKeyInput : nil,
            expiresAt: nil
        )

        // Store extra fields in the connector instance config
        var config = inst.config
        if !serverURLInput.isEmpty {
            config["serverURL"] = serverURLInput
        }
        if !botEmailInput.isEmpty {
            config["botEmail"] = botEmailInput
        }
        if !userIdInput.isEmpty {
            config["userId"] = userIdInput
        }
        if !clientIdInput.isEmpty {
            config["clientId"] = clientIdInput
        }
        if config != inst.config {
            store.updateConfig(id: inst.id, config: config)
        }

        do {
            try await KeychainService.shared.saveCredentials(instanceId: inst.id, credentials: credentials)

            // Test connection
            let success = try await ConnectorExecutor.shared.testConnection(instanceId: inst.id)
            if success {
                store.setConnected(id: inst.id, connected: true)
                apiKeyInput = ""
            } else {
                store.setConnected(id: inst.id, connected: false, error: "Connection test failed")
            }
            instance = store.instance(for: inst.id)
        } catch {
            errorMessage = error.localizedDescription
            store.setConnected(id: inst.id, connected: false, error: error.localizedDescription)
            instance = store.instance(for: inst.id)
        }
        isConnecting = false
    }

    /// Connect with domain + API key (for Jira).
    private func connectWithDomainKey() async {
        guard let inst = instance ?? store.addInstance(definitionId: definition.id) else { return }
        instance = inst
        isConnecting = true
        errorMessage = nil

        // Store domain in the apiKey as "email:token@domain"
        let compositeKey = "\(apiKeyInput)@\(domainInput)"
        let credentials = ConnectorCredentials(
            accessToken: nil,
            refreshToken: nil,
            apiKey: compositeKey,
            expiresAt: nil
        )

        do {
            try await KeychainService.shared.saveCredentials(instanceId: inst.id, credentials: credentials)

            let success = try await ConnectorExecutor.shared.testConnection(instanceId: inst.id)
            if success {
                store.setConnected(id: inst.id, connected: true)
                apiKeyInput = ""
                domainInput = ""
            } else {
                store.setConnected(id: inst.id, connected: false, error: "Connection test failed")
            }
            instance = store.instance(for: inst.id)
        } catch {
            errorMessage = error.localizedDescription
            store.setConnected(id: inst.id, connected: false, error: error.localizedDescription)
            instance = store.instance(for: inst.id)
        }
        isConnecting = false
    }

    private func testConnectionAction() async {
        guard let inst = instance else { return }
        isTesting = true
        testResult = nil

        do {
            let success = try await ConnectorExecutor.shared.testConnection(instanceId: inst.id)
            testResult = TestResult(success: success, message: success ? "Connection OK" : "Test failed")
        } catch {
            testResult = TestResult(success: false, message: error.localizedDescription)
        }
        isTesting = false
    }

    private func disconnect() {
        guard let inst = instance else { return }
        store.setConnected(id: inst.id, connected: false)
        Task {
            await KeychainService.shared.deleteCredentials(instanceId: inst.id)
        }
        testResult = nil
        errorMessage = nil
        instance = store.instance(for: inst.id)
    }

    /// Build OAuth config for the connector's provider.
    private func oauthConfig(for def: ConnectorDefinition) -> OAuthConfig {
        // Use definition's oauthConfig if available
        if let config = def.oauthConfig { return config }

        // Provider-specific OAuth configs
        switch def.id {
        case "dev.github":
            return OAuthConfig(
                authUrl: "https://github.com/login/oauth/authorize",
                tokenUrl: "https://github.com/login/oauth/access_token",
                scopes: ["repo", "read:user", "notifications"],
                usePKCE: false  // GitHub doesn't support PKCE for OAuth Apps
            )
        case "dev.gitlab":
            return OAuthConfig(
                authUrl: "https://gitlab.com/oauth/authorize",
                tokenUrl: "https://gitlab.com/oauth/token",
                scopes: ["read_user", "read_api"]
            )
        case "dev.linear":
            return OAuthConfig(
                authUrl: "https://linear.app/oauth/authorize",
                tokenUrl: "https://api.linear.app/oauth/token",
                scopes: ["read"]
            )
        default:
            // Fallback to Google-style config
            let scopes = def.requiredScopes.isEmpty ? ["openid", "email"] : def.requiredScopes
            return googleOAuthConfig(scopes: scopes)
        }
    }
}

// MARK: - Auth Mode

private enum AuthMode {
    case token
    case oauth
}

// MARK: - Test Result

private struct TestResult {
    let success: Bool
    let message: String
}
