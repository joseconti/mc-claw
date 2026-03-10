import Foundation
import Logging
import McClawKit

/// Native Slack channel using Socket Mode (WebSocket).
/// Runs in the background while McClaw is alive.
/// Requires two tokens:
/// - Bot Token (xoxb-) — from the existing Slack ConnectorProvider for sending messages
/// - App-Level Token (xapp-) — for Socket Mode WebSocket connection
actor SlackNativeService: NativeChannel {
    static let shared = SlackNativeService()

    let channelId = "slack"
    private let logger = Logger(label: "ai.mcclaw.native-channel.slack")

    // MARK: - State

    private(set) var state: NativeChannelState = .disconnected
    private(set) var stats = NativeChannelStats()
    private(set) var botDisplayName: String?

    private var config: NativeChannelConfig?
    private var connectionTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var botToken: String?
    private var appToken: String?
    private var botIdentity: SlackKit.BotIdentity?
    private var onMessage: (@Sendable (NativeChannelMessage) async -> String?)?

    /// Maximum consecutive errors before stopping.
    private let maxConsecutiveErrors = 10

    /// Delay before reconnecting after disconnect.
    private let reconnectDelay: UInt64 = 5_000_000_000 // 5 seconds

    private init() {}

    // MARK: - NativeChannel

    func setOnMessage(_ handler: @escaping @Sendable (NativeChannelMessage) async -> String?) {
        self.onMessage = handler
    }

    func start(config: NativeChannelConfig) async {
        guard connectionTask == nil else {
            logger.warning("Slack native channel already running")
            return
        }

        self.config = config
        state = .connecting
        logger.info("Starting Slack native channel")

        // Load bot token from Keychain
        guard let bot = await loadBotToken(instanceId: config.connectorInstanceId) else {
            state = .error
            stats.lastError = "No bot token found. Configure the Slack connector first."
            logger.error("No bot token for instance \(config.connectorInstanceId)")
            await notifyStateChange()
            return
        }
        botToken = bot

        // Get app-level token from config
        guard let app = config.appLevelToken, SlackKit.isValidAppToken(app) else {
            state = .error
            stats.lastError = "App-level token (xapp-) required for Socket Mode. Add it in channel settings."
            logger.error("No valid app-level token in config")
            await notifyStateChange()
            return
        }
        appToken = app

        // Verify bot token with auth.test
        guard let identity = await fetchBotIdentity(token: bot) else {
            state = .error
            stats.lastError = "Invalid bot token or Slack API unreachable."
            logger.error("auth.test failed")
            await notifyStateChange()
            return
        }

        botIdentity = identity
        botDisplayName = identity.displayName
        logger.info("Slack bot verified: \(botDisplayName ?? "unknown") (team: \(identity.team ?? identity.teamId))")

        // Start Socket Mode connection loop
        connectionTask = Task { [weak self] in
            await self?.connectionLoop()
        }
    }

    func stop() async {
        connectionTask?.cancel()
        connectionTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        botIdentity = nil
        botDisplayName = nil
        stats.connectedSince = nil
        logger.info("Slack native channel stopped")
        await notifyStateChange()
    }

    // MARK: - Connection Loop

    private func connectionLoop() async {
        var consecutiveErrors = 0

        while !Task.isCancelled {
            do {
                // Step 1: Get WebSocket URL via apps.connections.open
                guard let wsURL = try await openSocketModeConnection() else {
                    throw SlackNativeError.noWebSocketURL
                }

                // Step 2: Connect WebSocket
                let session = URLSession(configuration: .default)
                let task = session.webSocketTask(with: wsURL)
                self.webSocketTask = task
                task.resume()

                state = .connected
                stats.connectedSince = Date()
                stats.lastError = nil
                consecutiveErrors = 0
                await notifyStateChange()
                logger.info("Slack Socket Mode connected")

                // Step 3: Receive loop
                try await receiveLoop(task: task)

            } catch is CancellationError {
                break
            } catch {
                consecutiveErrors += 1
                stats.lastError = error.localizedDescription
                stats.reconnectCount += 1
                logger.error("Socket Mode error (\(consecutiveErrors)/\(maxConsecutiveErrors)): \(error.localizedDescription)")

                if consecutiveErrors >= maxConsecutiveErrors {
                    state = .error
                    logger.error("Too many consecutive errors, stopping Slack channel")
                    await notifyStateChange()
                    break
                }

                state = .connecting
                await notifyStateChange()

                // Clean up old WebSocket
                webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
                webSocketTask = nil

                // Wait before reconnecting
                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: reconnectDelay)
                }
            }
        }
    }

    // MARK: - Socket Mode Connection

    private func openSocketModeConnection() async throws -> URL? {
        guard let appToken, let url = SlackKit.connectURL() else {
            throw SlackNativeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SlackNativeError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return SlackKit.parseWebSocketURL(data: data)
        case 401:
            throw SlackNativeError.unauthorized
        case 403:
            throw SlackNativeError.forbidden
        default:
            throw SlackNativeError.httpError(http.statusCode)
        }
    }

    // MARK: - WebSocket Receive Loop

    private func receiveLoop(task: URLSessionWebSocketTask) async throws {
        while task.state == .running && !Task.isCancelled {
            let message = try await task.receive()

            switch message {
            case .string(let text):
                guard let data = text.data(using: .utf8) else { continue }
                await handleSocketMessage(data: data, task: task)
            case .data(let data):
                await handleSocketMessage(data: data, task: task)
            @unknown default:
                break
            }
        }
    }

    private func handleSocketMessage(data: Data, task: URLSessionWebSocketTask) async {
        guard let envelope = SlackKit.parseEnvelope(data: data) else {
            logger.warning("Failed to parse Socket Mode envelope")
            return
        }

        // Always acknowledge first (Slack requires ack within 3 seconds)
        if let envelopeId = envelope.envelopeId {
            await acknowledge(envelopeId: envelopeId, task: task)
        }

        switch envelope.type {
        case SlackKit.typeHello:
            logger.info("Slack Socket Mode: hello received")

        case SlackKit.typeDisconnect:
            logger.info("Slack Socket Mode: disconnect requested, will reconnect")
            task.cancel(with: .normalClosure, reason: nil)

        case SlackKit.typeEventsApi:
            if let event = envelope.payload?.event {
                await handleEvent(event)
            }

        default:
            logger.debug("Unhandled envelope type: \(envelope.type)")
        }
    }

    private func acknowledge(envelopeId: String, task: URLSessionWebSocketTask) async {
        guard let body = SlackKit.acknowledgeBody(envelopeId: envelopeId),
              let text = String(data: body, encoding: .utf8) else { return }

        do {
            try await task.send(.string(text))
        } catch {
            logger.error("Failed to acknowledge envelope \(envelopeId): \(error.localizedDescription)")
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: SlackKit.SlackEvent) async {
        guard SlackKit.shouldProcess(event: event) else { return }

        // Extract text, stripping bot mention
        guard let text = SlackKit.extractText(from: event, botUserId: botIdentity?.userId) else { return }
        guard let channel = event.channel else { return }

        // Check DM-only mode
        if config?.dmOnly == true && !event.isDirectMessage && !event.isAppMention {
            return
        }

        // Check allowed channels
        if let allowed = config?.allowedChannelIds, !allowed.isEmpty {
            guard allowed.contains(channel) else {
                logger.info("Channel \(channel) not in allowedChannelIds, ignoring")
                return
            }
        }

        let senderName = event.user ?? "Unknown"
        stats.messagesReceived += 1
        stats.lastMessageAt = Date()

        logger.info("Slack message from \(senderName) in \(channel): \(String(text.prefix(80)))")

        // Build NativeChannelMessage
        let channelMessage = NativeChannelMessage(
            channelId: channelId,
            senderName: senderName,
            text: text,
            date: Date(),
            platformChannelId: channel,
            platformUserId: event.user,
            threadId: event.threadTs ?? event.ts
        )

        // Route to handler
        guard let handler = onMessage else {
            logger.warning("No message handler set, ignoring")
            return
        }

        if let response = await handler(channelMessage) {
            let sent = await postMessage(
                channel: channel,
                text: response,
                threadTs: event.threadTs ?? event.ts
            )
            if sent {
                logger.info("Reply sent to \(channel)")
            }
        }
    }

    // MARK: - Web API Calls

    private func fetchBotIdentity(token: String) async -> SlackKit.BotIdentity? {
        guard let url = SlackKit.webAPIURL(method: "auth.test") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return SlackKit.parseBotIdentity(data: data)
        } catch {
            logger.error("auth.test error: \(error.localizedDescription)")
            return nil
        }
    }

    private func postMessage(channel: String, text: String, threadTs: String?) async -> Bool {
        guard let botToken, let url = SlackKit.webAPIURL(method: "chat.postMessage") else { return false }

        let truncated = SlackKit.truncateForSlack(text)
        guard let body = SlackKit.postMessageBody(
            channel: channel,
            text: truncated,
            threadTs: threadTs
        ) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.error("chat.postMessage HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return false
            }
            // Check Slack ok field
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["ok"] as? Bool == true {
                stats.messagesSent += 1
                return true
            }
            let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            logger.error("chat.postMessage error: \(errorMsg ?? "unknown")")
            return false
        } catch {
            logger.error("chat.postMessage error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Credential Loading

    private func loadBotToken(instanceId: String) async -> String? {
        let credentials = await KeychainService.shared.loadCredentials(instanceId: instanceId)
        let token = credentials?.accessToken ?? credentials?.apiKey
        guard let token, SlackKit.isValidBotToken(token) else { return nil }
        return token
    }

    // MARK: - State Notifications

    private func notifyStateChange() async {
        await MainActor.run {
            NativeChannelsManager.shared.channelStateDidChange()
        }
    }
}

// MARK: - Errors

enum SlackNativeError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noWebSocketURL
    case unauthorized
    case forbidden
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Slack API URL"
        case .invalidResponse: "Invalid response from Slack"
        case .noWebSocketURL: "Failed to get Socket Mode WebSocket URL"
        case .unauthorized: "App-level token is invalid or revoked (401)"
        case .forbidden: "Socket Mode not enabled for this app (403). Enable it in Slack app settings."
        case .httpError(let code): "Slack API error (HTTP \(code))"
        }
    }
}
