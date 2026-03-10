import Foundation
import Logging
import McClawKit

/// Native Mattermost channel using WebSocket API.
actor MattermostNativeService: NativeChannel {
    static let shared = MattermostNativeService()
    let channelId = "mattermost"
    private let logger = Logger(label: "ai.mcclaw.native-channel.mattermost")

    private(set) var state: NativeChannelState = .disconnected
    private(set) var stats = NativeChannelStats()
    private(set) var botDisplayName: String?

    private var config: NativeChannelConfig?
    private var connectionTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var accessToken: String?
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

        guard let serverURL = config.serverURL, MattermostKit.isValidServerURL(serverURL) else {
            state = .error
            stats.lastError = "Server URL required. Add it in channel settings."
            await notifyStateChange()
            return
        }

        guard let token = await loadToken(instanceId: config.connectorInstanceId) else {
            state = .error
            stats.lastError = "No access token found. Configure the Mattermost connector first."
            await notifyStateChange()
            return
        }
        accessToken = token

        // Verify with /users/me
        guard let user = await fetchMe(serverURL: serverURL, token: token) else {
            state = .error
            stats.lastError = "Invalid token or Mattermost server unreachable."
            await notifyStateChange()
            return
        }

        myUserId = user.id
        botDisplayName = user.username
        logger.info("Mattermost verified: \(user.username)")

        connectionTask = Task { [weak self] in
            await self?.connectionLoop(serverURL: serverURL, token: token)
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

    private func connectionLoop(serverURL: String, token: String) async {
        var consecutiveErrors = 0
        while !Task.isCancelled {
            do {
                guard let wsURL = MattermostKit.webSocketURL(serverURL: serverURL) else {
                    throw MattermostNativeError.invalidURL
                }

                let session = URLSession(configuration: .default)
                let task = session.webSocketTask(with: wsURL)
                self.webSocketTask = task
                task.resume()

                // Send auth challenge
                guard let authBody = MattermostKit.authChallengeBody(token: token),
                      let authText = String(data: authBody, encoding: .utf8) else {
                    throw MattermostNativeError.authFailed
                }
                try await task.send(.string(authText))

                state = .connected
                stats.connectedSince = Date()
                stats.lastError = nil
                consecutiveErrors = 0
                await notifyStateChange()
                logger.info("Mattermost WebSocket connected")

                try await receiveLoop(task: task, serverURL: serverURL, token: token)

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

    private func receiveLoop(task: URLSessionWebSocketTask, serverURL: String, token: String) async throws {
        while task.state == .running && !Task.isCancelled {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .string(let text): data = text.data(using: .utf8) ?? Data()
            case .data(let d): data = d
            @unknown default: continue
            }

            guard let event = MattermostKit.parseWebSocketEvent(data: data) else { continue }

            if event.event == MattermostKit.eventPosted {
                guard let myId = myUserId, MattermostKit.shouldProcess(event: event, myUserId: myId) else { continue }
                if let post = MattermostKit.extractPost(from: event) {
                    await handlePost(post, serverURL: serverURL, token: token)
                }
            }
        }
    }

    private func handlePost(_ post: MattermostKit.Post, serverURL: String, token: String) async {
        guard !post.message.isEmpty else { return }

        if let allowed = config?.allowedChannelIds, !allowed.isEmpty {
            guard allowed.contains(post.channelId) else { return }
        }

        stats.messagesReceived += 1
        stats.lastMessageAt = Date()

        let channelMessage = NativeChannelMessage(
            channelId: channelId,
            senderName: post.userId,
            text: post.message,
            date: Date(timeIntervalSince1970: TimeInterval(post.createAt) / 1000.0),
            platformChannelId: post.channelId,
            platformUserId: post.userId,
            threadId: (post.rootId?.isEmpty ?? true) ? nil : post.rootId
        )

        guard let handler = onMessage else { return }
        if let response = await handler(channelMessage) {
            await sendPost(serverURL: serverURL, token: token, channelId: post.channelId, text: response, rootId: (post.rootId?.isEmpty ?? true) ? post.id : post.rootId)
        }
    }

    private func sendPost(serverURL: String, token: String, channelId: String, text: String, rootId: String?) async {
        guard let url = MattermostKit.postsURL(serverURL: serverURL) else { return }
        let truncated = MattermostKit.truncateForMattermost(text)
        guard let body = MattermostKit.createPostBody(channelId: channelId, message: truncated, rootId: rootId) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 201 {
                stats.messagesSent += 1
            }
        } catch {
            logger.error("sendPost error: \(error.localizedDescription)")
        }
    }

    private func fetchMe(serverURL: String, token: String) async -> MattermostKit.User? {
        guard let url = MattermostKit.usersURL(serverURL: serverURL, path: "/api/v4/users/me") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return MattermostKit.parseUser(data: data)
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

enum MattermostNativeError: LocalizedError {
    case invalidURL, authFailed, httpError(Int)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Mattermost server URL"
        case .authFailed: "Failed to authenticate with Mattermost WebSocket"
        case .httpError(let c): "Mattermost API error (HTTP \(c))"
        }
    }
}
