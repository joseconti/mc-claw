import Foundation
import Logging
import McClawKit

actor RocketChatNativeService: NativeChannel {
    static let shared = RocketChatNativeService()
    let channelId = "rocketchat"
    private let logger = Logger(label: "ai.mcclaw.native-channel.rocketchat")

    private(set) var state: NativeChannelState = .disconnected
    private(set) var stats = NativeChannelStats()
    private(set) var botDisplayName: String?

    private var config: NativeChannelConfig?
    private var connectionTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var authToken: String?
    private var myUserId: String?
    private var onMessage: (@Sendable (NativeChannelMessage) async -> String?)?

    private let maxConsecutiveErrors = 10
    private let reconnectDelay: UInt64 = 5_000_000_000

    private init() {}

    func setOnMessage(_ handler: @escaping @Sendable (NativeChannelMessage) async -> String?) {
        self.onMessage = handler
    }

    func start(config: NativeChannelConfig) async {
        guard connectionTask == nil else { return }
        self.config = config
        state = .connecting

        guard let serverURL = config.serverURL, RocketChatKit.isValidServerURL(serverURL) else {
            state = .error
            stats.lastError = "Server URL required. Add it in channel settings."
            await notifyStateChange()
            return
        }

        guard let token = await loadToken(instanceId: config.connectorInstanceId) else {
            state = .error
            stats.lastError = "No auth token found. Configure the Rocket.Chat connector first."
            await notifyStateChange()
            return
        }
        authToken = token

        guard let rcUserId = config.userId, !rcUserId.isEmpty else {
            state = .error
            stats.lastError = "User ID required. Add it in channel settings."
            await notifyStateChange()
            return
        }

        // Verify with /api/v1/me
        guard let me = await fetchMe(serverURL: serverURL, userId: rcUserId, token: token) else {
            state = .error
            stats.lastError = "Invalid credentials or Rocket.Chat server unreachable."
            await notifyStateChange()
            return
        }

        myUserId = me.id
        botDisplayName = me.username
        logger.info("Rocket.Chat verified: \(me.username)")

        connectionTask = Task { [weak self] in
            await self?.connectionLoop(serverURL: serverURL, userId: rcUserId, token: token)
        }
    }

    func stop() async {
        connectionTask?.cancel()
        connectionTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        botDisplayName = nil
        myUserId = nil
        stats.connectedSince = nil
        await notifyStateChange()
    }

    private func connectionLoop(serverURL: String, userId: String, token: String) async {
        var consecutiveErrors = 0
        while !Task.isCancelled {
            do {
                guard let wsURL = RocketChatKit.webSocketURL(serverURL: serverURL) else {
                    throw RocketChatNativeError.invalidURL
                }

                let session = URLSession(configuration: .default)
                let task = session.webSocketTask(with: wsURL)
                self.webSocketTask = task
                task.resume()

                // DDP connect
                guard let connectPayload = RocketChatKit.connectPayload(),
                      let connectText = String(data: connectPayload, encoding: .utf8) else {
                    throw RocketChatNativeError.ddpFailed
                }
                try await task.send(.string(connectText))

                // Wait for "connected"
                let connMsg = try await receiveText(task: task)
                guard let connData = connMsg.data(using: .utf8),
                      let ddp = RocketChatKit.parseDDPMessage(data: connData),
                      ddp.msg == RocketChatKit.ddpConnected else {
                    throw RocketChatNativeError.ddpFailed
                }

                // DDP login
                guard let loginPayload = RocketChatKit.loginPayload(token: token, id: "login-1"),
                      let loginText = String(data: loginPayload, encoding: .utf8) else {
                    throw RocketChatNativeError.authFailed
                }
                try await task.send(.string(loginText))

                // Wait for login result
                let loginMsg = try await receiveText(task: task)
                // Accept result or continue (some servers send other messages first)

                // Subscribe to messages
                guard let subPayload = RocketChatKit.subscribeMessagesPayload(subId: "sub-messages"),
                      let subText = String(data: subPayload, encoding: .utf8) else {
                    throw RocketChatNativeError.ddpFailed
                }
                try await task.send(.string(subText))

                state = .connected
                stats.connectedSince = Date()
                stats.lastError = nil
                consecutiveErrors = 0
                await notifyStateChange()
                logger.info("Rocket.Chat DDP connected")

                try await receiveLoop(task: task, serverURL: serverURL, userId: userId, token: token)

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

    private func receiveText(task: URLSessionWebSocketTask) async throws -> String {
        let message = try await task.receive()
        switch message {
        case .string(let t): return t
        case .data(let d): return String(data: d, encoding: .utf8) ?? ""
        @unknown default: return ""
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask, serverURL: String, userId: String, token: String) async throws {
        while task.state == .running && !Task.isCancelled {
            let text = try await receiveText(task: task)
            guard let data = text.data(using: .utf8) else { continue }
            guard let ddp = RocketChatKit.parseDDPMessage(data: data) else { continue }

            switch ddp.msg {
            case RocketChatKit.ddpPing:
                if let pong = RocketChatKit.pongPayload(id: ddp.id),
                   let pongText = String(data: pong, encoding: .utf8) {
                    try? await task.send(.string(pongText))
                }

            case RocketChatKit.ddpChanged:
                if let rcMessage = RocketChatKit.parseMessage(from: data) {
                    guard let myId = myUserId, RocketChatKit.shouldProcess(message: rcMessage, myUserId: myId) else { continue }
                    await handleMessage(rcMessage, serverURL: serverURL, userId: userId, token: token)
                }

            default:
                break
            }
        }
    }

    private func handleMessage(_ msg: RocketChatKit.RCMessage, serverURL: String, userId: String, token: String) async {
        guard let text = RocketChatKit.extractText(from: msg), !text.isEmpty else { return }

        if let allowed = config?.allowedChannelIds, !allowed.isEmpty {
            guard allowed.contains(msg.rid) else { return }
        }

        stats.messagesReceived += 1
        stats.lastMessageAt = Date()

        let channelMessage = NativeChannelMessage(
            channelId: channelId,
            senderName: msg.user.username,
            text: text,
            date: Date(),
            platformChannelId: msg.rid,
            platformUserId: msg.user.id,
            threadId: msg.tmid
        )

        guard let handler = onMessage else { return }
        if let response = await handler(channelMessage) {
            let truncated = RocketChatKit.truncateForRocketChat(response)
            await sendMessage(serverURL: serverURL, userId: userId, token: token, roomId: msg.rid, text: truncated, threadId: msg.tmid ?? msg.id)
        }
    }

    private func sendMessage(serverURL: String, userId: String, token: String, roomId: String, text: String, threadId: String?) async {
        guard let url = RocketChatKit.sendMessageURL(serverURL: serverURL) else { return }
        guard let body = RocketChatKit.sendMessageBody(roomId: roomId, text: text, threadId: threadId) else { return }
        let headers = RocketChatKit.authHeaders(userId: userId, token: token)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                stats.messagesSent += 1
            }
        } catch {
            logger.error("sendMessage error: \(error.localizedDescription)")
        }
    }

    private func fetchMe(serverURL: String, userId: String, token: String) async -> RocketChatKit.MeResponse? {
        guard let url = RocketChatKit.meURL(serverURL: serverURL) else { return nil }
        let headers = RocketChatKit.authHeaders(userId: userId, token: token)
        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return RocketChatKit.parseMe(data: data)
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

enum RocketChatNativeError: LocalizedError {
    case invalidURL, ddpFailed, authFailed, httpError(Int)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Rocket.Chat server URL"
        case .ddpFailed: "DDP connection failed"
        case .authFailed: "Failed to authenticate with Rocket.Chat"
        case .httpError(let c): "Rocket.Chat API error (HTTP \(c))"
        }
    }
}
