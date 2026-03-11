import Foundation
import Logging
import McClawKit

/// Native Discord bot channel using Gateway WebSocket (v10).
/// Runs in the background while McClaw is alive.
/// Reuses credentials from the existing Discord ConnectorProvider (comm.discord).
actor DiscordNativeService: NativeChannel {
    static let shared = DiscordNativeService()

    let channelId = "discord"
    private let logger = Logger(label: "ai.mcclaw.native-channel.discord")

    // MARK: - State

    private(set) var state: NativeChannelState = .disconnected
    private(set) var stats = NativeChannelStats()
    private(set) var botDisplayName: String?

    private var config: NativeChannelConfig?
    private var connectionTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var botToken: String?
    private var botUserId: String?
    private var sessionId: String?
    private var lastSequence: Int?
    private var onMessage: (@Sendable (NativeChannelMessage) async -> String?)?

    /// Maximum consecutive errors before stopping.
    private let maxConsecutiveErrors = 10

    /// Delay before reconnecting after disconnect.
    private let reconnectDelay: UInt64 = 5_000_000_000 // 5 seconds

    private init() {}

    // MARK: - NativeChannel

    func clearStats() {
        stats = NativeChannelStats()
        state = .disconnected
        botDisplayName = nil
    }

    func setOnMessage(_ handler: @escaping @Sendable (NativeChannelMessage) async -> String?) {
        self.onMessage = handler
    }

    func sendOutbound(text: String, recipientId: String) async -> Bool {
        guard state == .connected else {
            logger.warning("Cannot send outbound: Discord channel not connected")
            return false
        }
        guard let token = botToken else {
            logger.error("Cannot send outbound: no bot token available")
            return false
        }
        return await sendMessage(token: token, channelId: recipientId, text: text)
    }

    func start(config: NativeChannelConfig) async {
        guard connectionTask == nil else {
            logger.warning("Discord native channel already running")
            return
        }

        self.config = config
        state = .connecting
        logger.info("Starting Discord native channel")

        // Load bot token from Keychain
        guard let token = await loadBotToken(instanceId: config.connectorInstanceId) else {
            state = .error
            stats.lastError = "No bot token found. Configure the Discord connector first."
            logger.error("No bot token for instance \(config.connectorInstanceId)")
            await notifyStateChange()
            return
        }
        botToken = token

        // Start connection loop
        connectionTask = Task { [weak self] in
            await self?.connectionLoop(token: token)
        }
    }

    func stop() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        connectionTask?.cancel()
        connectionTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        botUserId = nil
        botDisplayName = nil
        sessionId = nil
        lastSequence = nil
        stats.connectedSince = nil
        logger.info("Discord native channel stopped")
        await notifyStateChange()
    }

    // MARK: - Connection Loop

    private func connectionLoop(token: String) async {
        var consecutiveErrors = 0

        while !Task.isCancelled {
            do {
                // Connect to Discord Gateway
                guard let gatewayURL = DiscordKit.gatewayURL() else {
                    throw DiscordNativeError.invalidURL
                }

                let session = URLSession(configuration: .default)
                let task = session.webSocketTask(with: gatewayURL)
                self.webSocketTask = task
                task.resume()

                // Receive Hello (op 10)
                let helloData = try await receivePayload(task: task)
                guard let hello = DiscordKit.parseGatewayPayload(data: helloData),
                      hello.op == DiscordKit.opcodeHello,
                      let helloInfo = DiscordKit.parseHello(payload: hello) else {
                    throw DiscordNativeError.noHello
                }

                let heartbeatInterval = helloInfo.heartbeatInterval
                logger.info("Discord Gateway hello received, heartbeat interval: \(heartbeatInterval)ms")

                // Send Identify (op 2)
                guard let identifyData = DiscordKit.identifyPayload(token: token, intents: DiscordKit.defaultIntents) else {
                    throw DiscordNativeError.identifyFailed
                }
                try await task.send(.string(String(data: identifyData, encoding: .utf8)!))

                // Receive Ready (op 0, t: READY)
                let readyData = try await receivePayload(task: task)
                guard let readyPayload = DiscordKit.parseGatewayPayload(data: readyData),
                      let ready = DiscordKit.parseReady(payload: readyPayload) else {
                    throw DiscordNativeError.readyFailed
                }

                botUserId = ready.user.id
                sessionId = ready.sessionId
                lastSequence = readyPayload.s
                botDisplayName = ready.user.username
                state = .connected
                stats.connectedSince = Date()
                stats.lastError = nil
                consecutiveErrors = 0
                await notifyStateChange()
                logger.info("Discord bot connected: \(botDisplayName ?? "unknown") (guilds: \(ready.guilds.count))")

                // Start heartbeat loop
                heartbeatTask = Task { [weak self] in
                    await self?.heartbeatLoop(task: task, interval: heartbeatInterval)
                }

                // Receive loop
                try await receiveLoop(task: task, token: token)

            } catch is CancellationError {
                break
            } catch {
                consecutiveErrors += 1
                stats.lastError = error.localizedDescription
                stats.reconnectCount += 1
                logger.error("Discord Gateway error (\(consecutiveErrors)/\(maxConsecutiveErrors)): \(error.localizedDescription)")

                if consecutiveErrors >= maxConsecutiveErrors {
                    state = .error
                    logger.error("Too many consecutive errors, stopping Discord channel")
                    await notifyStateChange()
                    break
                }

                state = .connecting
                await notifyStateChange()

                // Clean up
                heartbeatTask?.cancel()
                heartbeatTask = nil
                webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
                webSocketTask = nil

                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: reconnectDelay)
                }
            }
        }
    }

    // MARK: - WebSocket

    private func receivePayload(task: URLSessionWebSocketTask) async throws -> Data {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return text.data(using: .utf8) ?? Data()
        case .data(let data):
            return data
        @unknown default:
            return Data()
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask, token: String) async throws {
        while task.state == .running && !Task.isCancelled {
            let data = try await receivePayload(task: task)
            guard let payload = DiscordKit.parseGatewayPayload(data: data) else { continue }

            // Update sequence number
            if let s = payload.s {
                lastSequence = s
            }

            switch payload.op {
            case DiscordKit.opcodeDispatch:
                if payload.t == DiscordKit.eventMessageCreate {
                    if let message = DiscordKit.parseMessageCreate(payload: payload) {
                        await handleMessage(message, token: token)
                    }
                }

            case DiscordKit.opcodeHeartbeat:
                // Server requests immediate heartbeat
                if let hb = DiscordKit.heartbeatPayload(sequence: lastSequence),
                   let text = String(data: hb, encoding: .utf8) {
                    try? await task.send(.string(text))
                }

            case DiscordKit.opcodeReconnect:
                logger.info("Discord Gateway requested reconnect")
                task.cancel(with: .normalClosure, reason: nil)
                return

            case DiscordKit.opcodeInvalidSession:
                logger.warning("Discord Gateway invalid session, reconnecting")
                sessionId = nil
                task.cancel(with: .normalClosure, reason: nil)
                return

            default:
                break
            }
        }
    }

    private func heartbeatLoop(task: URLSessionWebSocketTask, interval: Int) async {
        let intervalNs = UInt64(interval) * 1_000_000
        // Initial jitter
        let jitter = UInt64.random(in: 0..<UInt64(interval)) * 1_000_000
        try? await Task.sleep(nanoseconds: jitter)

        while !Task.isCancelled && task.state == .running {
            if let hb = DiscordKit.heartbeatPayload(sequence: lastSequence),
               let text = String(data: hb, encoding: .utf8) {
                try? await task.send(.string(text))
            }
            try? await Task.sleep(nanoseconds: intervalNs)
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: DiscordKit.Message, token: String) async {
        // Skip bot messages
        guard DiscordKit.shouldProcess(message: message, botUserId: botUserId) else { return }

        // Extract text, stripping bot mention
        guard let text = DiscordKit.extractText(from: message, botUserId: botUserId),
              !text.isEmpty else { return }

        let channelIdStr = message.channelId

        // Check DM-only mode
        let isDM = message.guildId == nil
        if config?.dmOnly == true && !isDM {
            // In guild channels, only respond if mentioned
            let isMentioned = botUserId.map { message.content.contains("<@\($0)>") } ?? false
            if !isMentioned { return }
        }

        // Check allowed channels
        if let allowed = config?.allowedChannelIds, !allowed.isEmpty {
            guard allowed.contains(channelIdStr) else {
                logger.info("Channel \(channelIdStr) not in allowedChannelIds, ignoring")
                return
            }
        }

        let senderName = message.author.globalName ?? message.author.username
        stats.messagesReceived += 1
        stats.lastMessageAt = Date()

        logger.info("Discord message from \(senderName) in \(channelIdStr): \(String(text.prefix(80)))")

        // Build NativeChannelMessage
        let channelMessage = NativeChannelMessage(
            channelId: channelId,
            senderName: senderName,
            text: text,
            date: Date(),
            platformChannelId: channelIdStr,
            platformUserId: message.author.id
        )

        // Route to handler
        guard let handler = onMessage else {
            logger.warning("No message handler set, ignoring")
            return
        }

        if let response = await handler(channelMessage) {
            let sent = await sendMessage(
                token: token,
                channelId: channelIdStr,
                text: response
            )
            if sent {
                logger.info("Reply sent to \(channelIdStr)")
            }
        }
    }

    // MARK: - REST API

    private func sendMessage(token: String, channelId: String, text: String) async -> Bool {
        guard let url = DiscordKit.channelMessagesURL(channelId: channelId) else { return false }

        let truncated = DiscordKit.truncateForDiscord(text)
        guard let body = DiscordKit.sendMessageBody(content: truncated) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }

            if http.statusCode == 200 || http.statusCode == 201 {
                stats.messagesSent += 1
                return true
            }

            logger.error("sendMessage HTTP \(http.statusCode)")
            return false
        } catch {
            logger.error("sendMessage error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Credential Loading

    private func loadBotToken(instanceId: String) async -> String? {
        let credentials = await KeychainService.shared.loadCredentials(instanceId: instanceId)
        return credentials?.apiKey ?? credentials?.accessToken
    }

    // MARK: - State Notifications

    private func notifyStateChange() async {
        await MainActor.run {
            NativeChannelsManager.shared.channelStateDidChange()
        }
    }
}

// MARK: - Errors

enum DiscordNativeError: LocalizedError {
    case invalidURL
    case noHello
    case identifyFailed
    case readyFailed
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Discord Gateway URL"
        case .noHello: "Did not receive Hello from Discord Gateway"
        case .identifyFailed: "Failed to send Identify to Discord Gateway"
        case .readyFailed: "Did not receive Ready from Discord Gateway"
        case .invalidResponse: "Invalid response from Discord"
        case .httpError(let code): "Discord API error (HTTP \(code))"
        }
    }
}
