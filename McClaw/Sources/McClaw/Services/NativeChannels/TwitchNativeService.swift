import Foundation
import Logging
import McClawKit

actor TwitchNativeService: NativeChannel {
    static let shared = TwitchNativeService()
    let channelId = "twitch"
    private let logger = Logger(label: "ai.mcclaw.native-channel.twitch")

    private(set) var state: NativeChannelState = .disconnected
    private(set) var stats = NativeChannelStats()
    private(set) var botDisplayName: String?

    private var config: NativeChannelConfig?
    private var connectionTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var accessToken: String?
    private var twitchClientId: String?
    private var botUserId: String?
    private var onMessage: (@Sendable (NativeChannelMessage) async -> String?)?

    private let maxConsecutiveErrors = 10
    private let reconnectDelay: UInt64 = 5_000_000_000

    private init() {}

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
            logger.warning("Cannot send outbound: Twitch channel not connected")
            return false
        }
        guard let token = accessToken,
              let clientId = twitchClientId,
              let userId = botUserId else {
            logger.error("Cannot send outbound: no credentials available")
            return false
        }
        let truncated = TwitchKit.truncateForTwitch(text)
        // recipientId is the broadcaster user ID
        await sendChatMessage(token: token, clientId: clientId, broadcasterId: recipientId, senderId: userId, message: truncated)
        return true
    }

    func start(config: NativeChannelConfig) async {
        guard connectionTask == nil else { return }
        self.config = config
        state = .connecting

        guard let clientId = config.clientId, TwitchKit.isValidClientId(clientId) else {
            state = .error
            stats.lastError = "Client ID required. Add it in channel settings."
            await notifyStateChange()
            return
        }
        twitchClientId = clientId

        guard let token = await loadToken(instanceId: config.connectorInstanceId),
              TwitchKit.isValidToken(token) else {
            state = .error
            stats.lastError = "No access token found. Configure the Twitch connector first."
            await notifyStateChange()
            return
        }
        accessToken = token

        // Validate token
        guard let validation = await validateToken(token: token) else {
            state = .error
            stats.lastError = "Invalid token or Twitch unreachable."
            await notifyStateChange()
            return
        }

        botUserId = validation.userId
        botDisplayName = validation.login
        logger.info("Twitch verified: \(validation.login) (userId: \(validation.userId))")

        connectionTask = Task { [weak self] in
            await self?.connectionLoop(token: token, clientId: clientId)
        }
    }

    func stop() async {
        connectionTask?.cancel()
        connectionTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        botDisplayName = nil
        botUserId = nil
        stats.connectedSince = nil
        await notifyStateChange()
    }

    private func connectionLoop(token: String, clientId: String) async {
        var consecutiveErrors = 0
        while !Task.isCancelled {
            do {
                let wsURL = TwitchKit.eventSubWSURL()
                let session = URLSession(configuration: .default)
                let task = session.webSocketTask(with: wsURL)
                self.webSocketTask = task
                task.resume()

                // Receive session_welcome
                let welcomeData = try await receiveData(task: task)
                guard let welcomeMsg = TwitchKit.parseWebSocketMessage(data: welcomeData),
                      let sessionId = TwitchKit.parseSessionId(from: welcomeMsg) else {
                    throw TwitchNativeError.noWelcome
                }

                logger.info("Twitch EventSub welcome, session: \(sessionId)")

                // Subscribe to channel.chat.message for all allowed channels
                guard let userId = botUserId else { throw TwitchNativeError.noUserId }

                // Subscribe to own channel by default
                let broadcasterIds = config?.allowedChannelIds ?? [userId]
                for broadcasterId in broadcasterIds {
                    await subscribeToChatMessages(token: token, clientId: clientId, broadcasterId: broadcasterId, userId: userId, sessionId: sessionId)
                }

                state = .connected
                stats.connectedSince = Date()
                stats.lastError = nil
                consecutiveErrors = 0
                await notifyStateChange()
                logger.info("Twitch EventSub connected")

                try await receiveLoop(task: task, token: token, clientId: clientId)

            } catch is CancellationError { break }
            catch {
                consecutiveErrors += 1
                stats.lastError = error.localizedDescription
                stats.reconnectCount += 1
                if consecutiveErrors >= maxConsecutiveErrors {
                    state = .error
                    await notifyStateChange()
                    break
                }
                state = .connecting
                await notifyStateChange()
                webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
                webSocketTask = nil
                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: reconnectDelay)
                }
            }
        }
    }

    private func receiveData(task: URLSessionWebSocketTask) async throws -> Data {
        let message = try await task.receive()
        switch message {
        case .string(let text): return text.data(using: .utf8) ?? Data()
        case .data(let data): return data
        @unknown default: return Data()
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask, token: String, clientId: String) async throws {
        while task.state == .running && !Task.isCancelled {
            let data = try await receiveData(task: task)
            guard let msg = TwitchKit.parseWebSocketMessage(data: data) else { continue }

            switch msg.metadata.messageType {
            case TwitchKit.sessionKeepalive:
                break // Do nothing, just keep alive

            case TwitchKit.notification:
                if let event = TwitchKit.parseChatEvent(from: msg),
                   let userId = botUserId,
                   TwitchKit.shouldProcess(event: event, botUserId: userId) {
                    await handleChatEvent(event, token: token, clientId: clientId)
                }

            case TwitchKit.sessionReconnect:
                logger.info("Twitch EventSub reconnect requested")
                task.cancel(with: .normalClosure, reason: nil)
                return

            case TwitchKit.revocation:
                logger.warning("Twitch EventSub subscription revoked")

            default:
                break
            }
        }
    }

    private func handleChatEvent(_ event: TwitchKit.ChatEvent, token: String, clientId: String) async {
        guard let text = TwitchKit.extractText(from: event), !text.isEmpty else { return }

        stats.messagesReceived += 1
        stats.lastMessageAt = Date()

        let senderName = event.chatterUserName
        let channelMessage = NativeChannelMessage(
            channelId: channelId,
            senderName: senderName,
            text: text,
            date: Date(),
            platformChannelId: event.broadcasterUserId,
            platformUserId: event.chatterUserId
        )

        guard let handler = onMessage else { return }
        if let response = await handler(channelMessage),
           let userId = botUserId {
            let truncated = TwitchKit.truncateForTwitch(response)
            await sendChatMessage(token: token, clientId: clientId, broadcasterId: event.broadcasterUserId, senderId: userId, message: truncated)
        }
    }

    private func subscribeToChatMessages(token: String, clientId: String, broadcasterId: String, userId: String, sessionId: String) async {
        guard let url = TwitchKit.subscriptionsURL() else { return }
        guard let body = TwitchKit.chatMessageSubscribeBody(broadcasterUserId: broadcasterId, userId: userId, sessionId: sessionId) else { return }
        let headers = TwitchKit.authHeaders(token: token, clientId: clientId)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 202 {
                logger.info("Subscribed to chat messages for broadcaster \(broadcasterId)")
            } else {
                logger.error("Failed to subscribe: HTTP \(code)")
            }
        } catch {
            logger.error("Subscribe error: \(error.localizedDescription)")
        }
    }

    private func sendChatMessage(token: String, clientId: String, broadcasterId: String, senderId: String, message: String) async {
        guard let url = TwitchKit.chatMessagesURL() else { return }
        guard let body = TwitchKit.sendChatBody(broadcasterId: broadcasterId, senderId: senderId, message: message) else { return }
        let headers = TwitchKit.authHeaders(token: token, clientId: clientId)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                stats.messagesSent += 1
            }
        } catch {
            logger.error("sendChat error: \(error.localizedDescription)")
        }
    }

    private func validateToken(token: String) async -> TwitchKit.TokenValidation? {
        guard let url = TwitchKit.validateTokenURL() else { return nil }
        var request = URLRequest(url: url)
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return TwitchKit.parseTokenValidation(data: data)
        } catch { return nil }
    }

    private func loadToken(instanceId: String) async -> String? {
        let creds = await KeychainService.shared.loadCredentials(instanceId: instanceId)
        return creds?.accessToken ?? creds?.apiKey
    }

    private func notifyStateChange() async {
        await MainActor.run { NativeChannelsManager.shared.channelStateDidChange() }
    }
}

enum TwitchNativeError: LocalizedError {
    case noWelcome, noUserId, httpError(Int)
    var errorDescription: String? {
        switch self {
        case .noWelcome: "Did not receive welcome from Twitch EventSub"
        case .noUserId: "No user ID available"
        case .httpError(let c): "Twitch API error (HTTP \(c))"
        }
    }
}
