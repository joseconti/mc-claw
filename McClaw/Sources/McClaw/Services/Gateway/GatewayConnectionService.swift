import Foundation
import Logging
import McClawKit

/// WebSocket client for communicating with the Gateway.
/// Protocol version 3 compatible.
actor GatewayConnectionService {
    static let shared = GatewayConnectionService()

    private let logger = Logger(label: "ai.mcclaw.gateway")
    private var webSocketTask: URLSessionWebSocketTask?
    private var sequence: Int = 0
    private var pendingRequests: [Int: CheckedContinuation<WSResponse, Error>] = [:]

    /// Callback for incoming chat messages from Gateway.
    /// Called on MainActor with (text, sessionId).
    private var onChatMessage: (@MainActor @Sendable (String, String) -> Void)?

    /// Register a handler for chat.message events from Gateway.
    func setOnChatMessage(_ handler: @escaping @MainActor @Sendable (String, String) -> Void) {
        self.onChatMessage = handler
    }

    /// Gateway WebSocket URL (configurable for remote mode)
    private var _gatewayURL: URL = URL(string: "ws://127.0.0.1:3577/ws")!

    var gatewayURL: URL { _gatewayURL }

    /// Update the gateway URL (used by ConnectionModeCoordinator).
    func setGatewayURL(_ url: URL) {
        _gatewayURL = url
        logger.info("Gateway URL set to \(url)")
    }

    // MARK: - Connection

    /// Connect to the Gateway WebSocket.
    func connect() async {
        logger.info("Connecting to Gateway at \(_gatewayURL)")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: _gatewayURL)
        self.webSocketTask = task
        task.resume()

        await updateStatus(.connecting)
        startReceiving()

        // Send hello handshake
        do {
            let response = try await call(method: "hello", params: [
                "client": .string("mcclaw"),
                "protocolVersion": .int(3),
            ])
            if response.ok {
                await updateStatus(.connected)
                logger.info("Gateway connected (protocol v3)")
            } else {
                await updateStatus(.error)
                logger.error("Gateway handshake failed: \(response.error?.message ?? "unknown")")
            }
        } catch {
            await updateStatus(.error)
            logger.error("Gateway connection error: \(error)")
        }
    }

    /// Disconnect from the Gateway.
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        Task { await updateStatus(.disconnected) }
        logger.info("Gateway disconnected")
    }

    // MARK: - RPC

    /// Make an RPC call to the Gateway.
    func call(method: String, params: [String: AnyCodableValue]? = nil) async throws -> WSResponse {
        sequence += 1
        let seq = sequence

        let request = WSRequest(seq: seq, method: method, params: params)
        let data = try JSONEncoder().encode(request)

        guard let text = String(data: data, encoding: .utf8) else {
            throw GatewayError.encodingFailed
        }

        let message = URLSessionWebSocketTask.Message.string(text)
        try await webSocketTask?.send(message)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[seq] = continuation
        }
    }

    // MARK: - Events

    /// Start receiving messages from the WebSocket.
    private func startReceiving() {
        Task {
            guard let task = webSocketTask else { return }

            do {
                while task.state == .running {
                    let message = try await task.receive()

                    switch message {
                    case .string(let text):
                        handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                logger.error("WebSocket receive error: \(error)")
                await updateStatus(.disconnected)
            }
        }
    }

    /// Handle an incoming WebSocket message.
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        // Try to decode as response (has seq)
        if let response = try? JSONDecoder().decode(WSResponse.self, from: data) {
            if let continuation = pendingRequests.removeValue(forKey: response.seq) {
                continuation.resume(returning: response)
            }
            return
        }

        // Try to decode as event (has event name)
        if let event = try? JSONDecoder().decode(WSEvent.self, from: data) {
            handleEvent(event)
            return
        }

        logger.warning("Unknown WebSocket message: \(text.prefix(100))")
    }

    // MARK: - Cron RPC

    /// List cron jobs from Gateway.
    func cronList(includeDisabled: Bool = true) async throws -> [CronJob] {
        let response = try await call(method: "cron.list", params: [
            "includeDisabled": .bool(includeDisabled),
        ])
        guard response.ok, let result = response.result else {
            throw GatewayError.serverError(response.error?.message ?? "cron.list failed")
        }
        let data = try JSONEncoder().encode(result)
        let listResponse = try JSONDecoder().decode(CronListResponse.self, from: data)
        return listResponse.jobs
    }

    /// Get cron scheduler status.
    func cronStatus() async throws -> CronStatusResponse {
        let response = try await call(method: "cron.status")
        guard response.ok, let result = response.result else {
            throw GatewayError.serverError(response.error?.message ?? "cron.status failed")
        }
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(CronStatusResponse.self, from: data)
    }

    /// Get run log entries for a cron job.
    func cronRuns(jobId: String, limit: Int = 200) async throws -> [CronRunLogEntry] {
        let response = try await call(method: "cron.runs", params: [
            "jobId": .string(jobId),
            "limit": .int(limit),
        ])
        guard response.ok, let result = response.result else {
            throw GatewayError.serverError(response.error?.message ?? "cron.runs failed")
        }
        let data = try JSONEncoder().encode(result)
        let runsResponse = try JSONDecoder().decode(CronRunsResponse.self, from: data)
        return runsResponse.entries
    }

    /// Add a new cron job.
    func cronAdd(payload: [String: AnyCodableValue]) async throws {
        let response = try await call(method: "cron.add", params: payload)
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "cron.add failed")
        }
    }

    /// Update an existing cron job.
    func cronUpdate(jobId: String, patch: [String: AnyCodableValue]) async throws {
        var params = patch
        params["jobId"] = .string(jobId)
        let response = try await call(method: "cron.update", params: params)
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "cron.update failed")
        }
    }

    /// Remove a cron job.
    func cronRemove(jobId: String) async throws {
        let response = try await call(method: "cron.remove", params: [
            "jobId": .string(jobId),
        ])
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "cron.remove failed")
        }
    }

    /// Force-run a cron job immediately.
    func cronRun(jobId: String, force: Bool = true, messageOverride: String? = nil) async throws {
        var params: [String: AnyCodableValue] = [
            "jobId": .string(jobId),
            "force": .bool(force),
        ]
        if let messageOverride {
            params["messageOverride"] = .string(messageOverride)
        }
        let response = try await call(method: "cron.run", params: params)
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "cron.run failed")
        }
    }

    // MARK: - Webhook RPC

    /// Register a webhook endpoint via Gateway.
    func webhookRegister(id: String, url: String, secret: String?) async throws {
        var params: [String: AnyCodableValue] = [
            "id": .string(id),
            "url": .string(url),
        ]
        if let secret { params["secret"] = .string(secret) }
        let response = try await call(method: "webhook.register", params: params)
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "webhook.register failed")
        }
    }

    /// Remove a webhook endpoint.
    func webhookRemove(id: String) async throws {
        let response = try await call(method: "webhook.remove", params: [
            "id": .string(id),
        ])
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "webhook.remove failed")
        }
    }

    /// List registered webhooks.
    func webhookList() async throws -> AnyCodableValue? {
        let response = try await call(method: "webhook.list")
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "webhook.list failed")
        }
        return response.result
    }

    // MARK: - Exec Approval RPC

    /// Respond to an exec approval request from the Gateway.
    func execApprovalResolve(requestId: String, decision: String) async throws {
        let response = try await call(method: "exec.approval.resolve", params: [
            "requestId": .string(requestId),
            "decision": .string(decision),
        ])
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "exec.approval.resolve failed")
        }
    }

    // MARK: - Channels RPC

    /// Get channels status snapshot from Gateway.
    func channelsStatus(probe: Bool = false) async throws -> ChannelsStatusSnapshot {
        var params: [String: AnyCodableValue] = [
            "probe": .bool(probe),
        ]
        if probe {
            params["timeoutMs"] = .int(8000)
        }
        let response = try await call(method: "channels.status", params: params)
        guard response.ok, let result = response.result else {
            throw GatewayError.serverError(response.error?.message ?? "channels.status failed")
        }
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(ChannelsStatusSnapshot.self, from: data)
    }

    /// Logout from a channel.
    func channelLogout(channel: String) async throws -> ChannelLogoutResult {
        let response = try await call(method: "channels.logout", params: [
            "channel": .string(channel),
        ])
        guard response.ok, let result = response.result else {
            throw GatewayError.serverError(response.error?.message ?? "channels.logout failed")
        }
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(ChannelLogoutResult.self, from: data)
    }

    /// Start WhatsApp login flow (returns QR code).
    func whatsAppLoginStart(force: Bool) async throws -> WhatsAppLoginStartResult {
        let response = try await call(method: "web.login.start", params: [
            "force": .bool(force),
            "timeoutMs": .int(30000),
        ])
        guard response.ok, let result = response.result else {
            throw GatewayError.serverError(response.error?.message ?? "web.login.start failed")
        }
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(WhatsAppLoginStartResult.self, from: data)
    }

    /// Wait for WhatsApp login to complete.
    func whatsAppLoginWait(timeoutMs: Int = 120_000) async throws -> WhatsAppLoginWaitResult {
        let response = try await call(method: "web.login.wait", params: [
            "timeoutMs": .int(timeoutMs),
        ])
        guard response.ok, let result = response.result else {
            throw GatewayError.serverError(response.error?.message ?? "web.login.wait failed")
        }
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(WhatsAppLoginWaitResult.self, from: data)
    }

    // MARK: - Plugins RPC

    /// List installed plugins from Gateway.
    func pluginsList() async throws -> [PluginInfo] {
        let response = try await call(method: "plugins.list")
        guard response.ok, let result = response.result else {
            throw GatewayError.serverError(response.error?.message ?? "plugins.list failed")
        }
        let data = try JSONEncoder().encode(result)
        if let wrapper = try? JSONDecoder().decode(PluginsListResponse.self, from: data) {
            return wrapper.plugins
        }
        return try JSONDecoder().decode([PluginInfo].self, from: data)
    }

    /// Install a plugin package.
    func pluginInstall(packageName: String) async throws {
        let response = try await call(method: "plugins.install", params: [
            "package": .string(packageName),
        ])
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "plugins.install failed")
        }
    }

    /// Uninstall a plugin package.
    func pluginUninstall(packageName: String) async throws {
        let response = try await call(method: "plugins.uninstall", params: [
            "package": .string(packageName),
        ])
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "plugins.uninstall failed")
        }
    }

    /// Toggle a plugin's enabled state.
    func pluginToggle(packageName: String, enabled: Bool) async throws {
        let response = try await call(method: "plugins.toggle", params: [
            "package": .string(packageName),
            "enabled": .bool(enabled),
        ])
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "plugins.toggle failed")
        }
    }

    /// Update a plugin's configuration.
    func pluginUpdateConfig(packageName: String, config: [String: AnyCodableValue]) async throws {
        var params: [String: AnyCodableValue] = [
            "package": .string(packageName),
        ]
        params["config"] = .dictionary(config)
        let response = try await call(method: "plugins.config", params: params)
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "plugins.config failed")
        }
    }

    // MARK: - Skills RPC (Gateway legacy — kept for future Gateway integration)

    /// Get skills status from Gateway.
    func skillsStatus() async throws -> GatewaySkillsStatusReport {
        let response = try await call(method: "skills.status")
        guard response.ok, let result = response.result else {
            throw GatewayError.serverError(response.error?.message ?? "skills.status failed")
        }
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(GatewaySkillsStatusReport.self, from: data)
    }

    /// Install a skill's dependency.
    func skillsInstall(name: String, installId: String) async throws -> GatewaySkillInstallResult {
        let response = try await call(method: "skills.install", params: [
            "name": .string(name),
            "installId": .string(installId),
        ])
        guard response.ok, let result = response.result else {
            throw GatewayError.serverError(response.error?.message ?? "skills.install failed")
        }
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(GatewaySkillInstallResult.self, from: data)
    }

    /// Update a skill's config (enabled, apiKey, env).
    func skillsUpdate(
        skillKey: String,
        enabled: Bool? = nil,
        apiKey: String? = nil,
        env: [String: AnyCodableValue]? = nil
    ) async throws -> GatewaySkillUpdateResult {
        var params: [String: AnyCodableValue] = [
            "skillKey": .string(skillKey),
        ]
        if let enabled { params["enabled"] = .bool(enabled) }
        if let apiKey { params["apiKey"] = .string(apiKey) }
        if let env { params["env"] = .dictionary(env) }
        let response = try await call(method: "skills.update", params: params)
        guard response.ok, let result = response.result else {
            throw GatewayError.serverError(response.error?.message ?? "skills.update failed")
        }
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(GatewaySkillUpdateResult.self, from: data)
    }

    // MARK: - Canvas / Node RPC

    /// Send a canvas A2UI action message to the Gateway agent.
    func sendCanvasA2UIAction(message: String) async throws {
        let response = try await call(method: "agent.send", params: [
            "message": .string(message),
            "thinking": .string("low"),
            "deliver": .bool(false),
        ])
        guard response.ok else {
            throw GatewayError.serverError(response.error?.message ?? "agent.send failed")
        }
    }

    /// Send a node bridge invoke response back to the Gateway.
    func sendNodeInvokeResponse(_ response: BridgeInvokeResponse) async throws {
        let data = try JSONEncoder().encode(response)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GatewayError.encodingFailed
        }
        let message = URLSessionWebSocketTask.Message.string(text)
        try await webSocketTask?.send(message)
    }

    /// Send a node event to the Gateway.
    func sendNodeEvent(_ event: BridgeEventFrame) async throws {
        let data = try JSONEncoder().encode(event)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GatewayError.encodingFailed
        }
        let message = URLSessionWebSocketTask.Message.string(text)
        try await webSocketTask?.send(message)
    }

    /// Send the node hello frame to the Gateway.
    func sendNodeHello(_ hello: BridgeHello) async throws {
        let data = try JSONEncoder().encode(hello)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GatewayError.encodingFailed
        }
        let message = URLSessionWebSocketTask.Message.string(text)
        try await webSocketTask?.send(message)
    }

    // MARK: - Event Callbacks

    /// Callback for incoming node invoke requests from Gateway.
    private var onNodeInvoke: (@MainActor @Sendable (BridgeInvokeRequest) -> Void)?

    /// Register a handler for node invoke requests.
    func setOnNodeInvoke(_ handler: @escaping @MainActor @Sendable (BridgeInvokeRequest) -> Void) {
        self.onNodeInvoke = handler
    }

    /// Callback for incoming cron events from Gateway.
    private var onCronEvent: (@MainActor @Sendable (CronEvent) -> Void)?

    /// Register a handler for cron events from Gateway.
    func setOnCronEvent(_ handler: @escaping @MainActor @Sendable (CronEvent) -> Void) {
        self.onCronEvent = handler
    }

    /// Callback for channel status updates.
    private var onChannelEvent: (@MainActor @Sendable () -> Void)?

    /// Register a handler for channel events.
    func setOnChannelEvent(_ handler: @escaping @MainActor @Sendable () -> Void) {
        self.onChannelEvent = handler
    }

    /// Callback for plugin changes.
    private var onPluginEvent: (@MainActor @Sendable () -> Void)?

    /// Register a handler for plugin events.
    func setOnPluginEvent(_ handler: @escaping @MainActor @Sendable () -> Void) {
        self.onPluginEvent = handler
    }

    /// Handle a push event from the Gateway.
    private func handleEvent(_ event: WSEvent) {
        logger.debug("Gateway event: \(event.event)")

        let chatHandler = self.onChatMessage
        let cronHandler = self.onCronEvent
        let channelHandler = self.onChannelEvent
        let pluginHandler = self.onPluginEvent
        let nodeHandler = self.onNodeInvoke

        Task { @MainActor in
            switch event.event {
            case "agent.working":
                AppState.shared.isWorking = true
            case "agent.idle":
                AppState.shared.isWorking = false
            case "health.update":
                break
            case "chat.message":
                if let data = event.data,
                   case .string(let text) = data["text"],
                   case .string(let sessionId) = data["sessionId"] {
                    chatHandler?(text, sessionId)
                }
            case "exec.approval.requested":
                if let data = event.data,
                   case .string(let command) = data["command"] {
                    let args: [String]
                    if case .string(let argsStr) = data["arguments"] {
                        args = argsStr.split(separator: " ").map(String.init)
                    } else {
                        args = []
                    }
                    let request = ExecApprovalRequest(command: command, arguments: args)
                    ExecApprovals.shared.pendingApproval = request
                }
            case "cron":
                if let data = event.data {
                    let jsonData = try? JSONEncoder().encode(data)
                    if let jsonData,
                       let cronEvt = try? JSONDecoder().decode(CronEvent.self, from: jsonData) {
                        cronHandler?(cronEvt)
                    }
                }
            case "channels", "channels.status":
                channelHandler?()
            case "plugins", "plugins.changed":
                pluginHandler?()
            case "node.invoke":
                if let data = event.data {
                    let jsonData = try? JSONEncoder().encode(data)
                    if let jsonData,
                       let invokeReq = try? JSONDecoder().decode(BridgeInvokeRequest.self, from: jsonData) {
                        nodeHandler?(invokeReq)
                    }
                }
            default:
                break
            }
        }
    }

    /// Update the Gateway status on main actor.
    private func updateStatus(_ status: GatewayStatus) async {
        await MainActor.run {
            AppState.shared.gatewayStatus = status
        }
    }
}

/// Gateway-related errors.
enum GatewayError: Error, LocalizedError {
    case encodingFailed
    case notConnected
    case timeout
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: "Failed to encode message"
        case .notConnected: "Not connected to Gateway"
        case .timeout: "Request timed out"
        case .serverError(let msg): "Gateway error: \(msg)"
        }
    }
}

/// Helper for decoding plugins.list responses.
private struct PluginsListResponse: Codable {
    let plugins: [PluginInfo]
}

// MARK: - Gateway Skills Types (legacy — for future Gateway integration)

struct GatewaySkillsStatusReport: Codable, Sendable {
    let workspaceDir: String?
    let managedSkillsDir: String?
    let skills: [GatewaySkillStatus]
}

struct GatewaySkillStatus: Codable, Sendable {
    let name: String
    let description: String
    let source: String
    let filePath: String
    let baseDir: String
    let skillKey: String
    let primaryEnv: String?
    let emoji: String?
    let homepage: String?
    let always: Bool
    let disabled: Bool
    let eligible: Bool
}

struct GatewaySkillInstallResult: Codable, Sendable {
    let ok: Bool
    let message: String
    let stdout: String?
    let stderr: String?
    let code: Int?
}

struct GatewaySkillUpdateResult: Codable, Sendable {
    let ok: Bool
    let skillKey: String
}
