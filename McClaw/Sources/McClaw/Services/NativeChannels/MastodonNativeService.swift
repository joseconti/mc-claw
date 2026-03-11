import Foundation
import Logging
import McClawKit

/// Native Mastodon/Fediverse channel using WebSocket streaming.
actor MastodonNativeService: NativeChannel {
    static let shared = MastodonNativeService()
    let channelId = "mastodon"
    private let logger = Logger(label: "ai.mcclaw.native-channel.mastodon")

    private(set) var state: NativeChannelState = .disconnected
    private(set) var stats = NativeChannelStats()
    private(set) var botDisplayName: String?

    private var config: NativeChannelConfig?
    private var connectionTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var accessToken: String?
    private var myAccountId: String?
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
            logger.warning("Cannot send outbound: Mastodon channel not connected")
            return false
        }
        guard let instanceURL = config?.serverURL,
              let token = accessToken else {
            logger.error("Cannot send outbound: no credentials available")
            return false
        }
        guard let url = MastodonKit.postStatusURL(instanceURL: instanceURL) else { return false }
        let truncated = MastodonKit.truncateForMastodon(text)
        let visibility = MastodonKit.Visibility(rawValue: config?.replyVisibility ?? "unlisted") ?? .unlisted
        // recipientId is used as inReplyToId; empty means a new public status
        let inReplyToId: String? = recipientId.isEmpty ? nil : recipientId
        guard let body = MastodonKit.postStatusBody(text: truncated, inReplyToId: inReplyToId, visibility: visibility) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                stats.messagesSent += 1
                return true
            }
            return false
        } catch {
            logger.error("sendOutbound error: \(error.localizedDescription)")
            return false
        }
    }

    func start(config: NativeChannelConfig) async {
        guard connectionTask == nil else { return }
        self.config = config
        state = .connecting

        guard let instanceURL = config.serverURL, MastodonKit.isValidInstanceURL(instanceURL) else {
            state = .error
            stats.lastError = "Instance URL required (e.g. https://mastodon.social). Add it in channel settings."
            await notifyStateChange()
            return
        }

        guard let token = await loadToken(instanceId: config.connectorInstanceId) else {
            state = .error
            stats.lastError = "No access token found. Configure the Mastodon connector first."
            await notifyStateChange()
            return
        }
        accessToken = token

        guard let account = await verifyCredentials(instanceURL: instanceURL, token: token) else {
            state = .error
            stats.lastError = "Invalid access token or instance unreachable."
            await notifyStateChange()
            return
        }

        myAccountId = account.id
        botDisplayName = "@\(account.acct)"
        logger.info("Mastodon verified: @\(account.acct)")

        connectionTask = Task { [weak self] in
            await self?.connectionLoop(instanceURL: instanceURL, token: token)
        }
    }

    func stop() async {
        connectionTask?.cancel()
        connectionTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        botDisplayName = nil
        myAccountId = nil
        stats.connectedSince = nil
        await notifyStateChange()
    }

    private func connectionLoop(instanceURL: String, token: String) async {
        var consecutiveErrors = 0
        while !Task.isCancelled {
            do {
                guard let wsURL = MastodonKit.streamingURL(instanceURL: instanceURL, token: token, stream: "user:notification") else {
                    throw MastodonNativeError.invalidURL
                }

                let session = URLSession(configuration: .default)
                let task = session.webSocketTask(with: wsURL)
                self.webSocketTask = task
                task.resume()

                state = .connected
                stats.connectedSince = Date()
                stats.lastError = nil
                consecutiveErrors = 0
                await notifyStateChange()
                logger.info("Mastodon streaming connected")

                try await receiveLoop(task: task, instanceURL: instanceURL, token: token)

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

    private func receiveLoop(task: URLSessionWebSocketTask, instanceURL: String, token: String) async throws {
        while task.state == .running && !Task.isCancelled {
            let message = try await task.receive()
            let text: String
            switch message {
            case .string(let t): text = t
            case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
            @unknown default: continue
            }

            // Mastodon streaming sends JSON with event and payload fields
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let eventType = json["event"] as? String,
                  let payloadStr = json["payload"] as? String else { continue }

            if eventType == "notification" {
                if let payloadData = payloadStr.data(using: .utf8),
                   let notif = try? JSONDecoder().decode(MastodonKit.Notification.self, from: payloadData) {
                    if MastodonKit.isMention(notif) {
                        await handleMention(notif, instanceURL: instanceURL, token: token)
                    }
                }
            }
        }
    }

    private func handleMention(_ notification: MastodonKit.Notification, instanceURL: String, token: String) async {
        guard let status = notification.status else { return }
        guard let myId = myAccountId, MastodonKit.shouldProcess(notification: notification, myAccountId: myId) else { return }

        let text = MastodonKit.extractText(from: status)
        guard !text.isEmpty else { return }

        stats.messagesReceived += 1
        stats.lastMessageAt = Date()

        let senderName = "@\(notification.account.acct)"
        let channelMessage = NativeChannelMessage(
            channelId: channelId,
            senderName: senderName,
            text: text,
            date: Date(),
            platformChannelId: status.id,
            platformUserId: notification.account.id
        )

        guard let handler = onMessage else { return }
        if let response = await handler(channelMessage) {
            let visibility = config?.replyVisibility ?? status.visibility.rawValue
            await postReply(instanceURL: instanceURL, token: token, inReplyToId: status.id, text: "@\(notification.account.acct) \(response)", visibility: visibility)
        }
    }

    private func postReply(instanceURL: String, token: String, inReplyToId: String, text: String, visibility: String) async {
        guard let url = MastodonKit.postStatusURL(instanceURL: instanceURL) else { return }
        let truncated = MastodonKit.truncateForMastodon(text)
        guard let body = MastodonKit.postStatusBody(text: truncated, inReplyToId: inReplyToId, visibility: MastodonKit.Visibility(rawValue: visibility) ?? .unlisted) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                stats.messagesSent += 1
            }
        } catch {
            logger.error("postStatus error: \(error.localizedDescription)")
        }
    }

    private func verifyCredentials(instanceURL: String, token: String) async -> MastodonKit.Account? {
        guard let url = MastodonKit.verifyCredentialsURL(instanceURL: instanceURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return MastodonKit.parseAccount(data: data)
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

enum MastodonNativeError: LocalizedError {
    case invalidURL, httpError(Int)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Mastodon instance URL"
        case .httpError(let c): "Mastodon API error (HTTP \(c))"
        }
    }
}
