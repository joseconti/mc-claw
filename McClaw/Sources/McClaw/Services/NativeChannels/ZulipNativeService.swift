import Foundation
import Logging
import McClawKit

actor ZulipNativeService: NativeChannel {
    static let shared = ZulipNativeService()
    let channelId = "zulip"
    private let logger = Logger(label: "ai.mcclaw.native-channel.zulip")

    private(set) var state: NativeChannelState = .disconnected
    private(set) var stats = NativeChannelStats()
    private(set) var botDisplayName: String?

    private var config: NativeChannelConfig?
    private var pollingTask: Task<Void, Never>?
    private var queueId: String?
    private var lastEventId: Int = -1
    private var myUserId: Int?
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
            logger.warning("Cannot send outbound: Zulip channel not connected")
            return false
        }
        guard let serverURL = config?.serverURL,
              let botEmail = config?.botEmail,
              let apiKey = await loadToken(instanceId: config?.connectorInstanceId ?? "") else {
            logger.error("Cannot send outbound: no credentials available")
            return false
        }
        let authHeader = ZulipKit.basicAuthHeader(email: botEmail, apiKey: apiKey)
        let truncated = ZulipKit.truncateForZulip(text)

        // recipientId format: "stream:topic" for stream messages, or an email for direct messages
        if recipientId.contains(":") {
            let parts = recipientId.split(separator: ":", maxSplits: 1)
            let stream = String(parts[0])
            let topic = parts.count > 1 ? String(parts[1]) : "general"
            await sendStreamReply(serverURL: serverURL, authHeader: authHeader, stream: stream, topic: topic, content: truncated)
        } else {
            await sendDirectReply(serverURL: serverURL, authHeader: authHeader, to: recipientId, content: truncated)
        }
        return true
    }

    func start(config: NativeChannelConfig) async {
        guard pollingTask == nil else { return }
        self.config = config
        state = .connecting

        guard let serverURL = config.serverURL, ZulipKit.isValidServerURL(serverURL) else {
            state = .error
            stats.lastError = "Server URL required. Add it in channel settings."
            await notifyStateChange()
            return
        }

        guard let botEmail = config.botEmail, ZulipKit.isValidEmail(botEmail) else {
            state = .error
            stats.lastError = "Bot email required. Add it in channel settings."
            await notifyStateChange()
            return
        }

        guard let apiKey = await loadToken(instanceId: config.connectorInstanceId),
              ZulipKit.isValidAPIKey(apiKey) else {
            state = .error
            stats.lastError = "No API key found. Configure the Zulip connector first."
            await notifyStateChange()
            return
        }

        let authHeader = ZulipKit.basicAuthHeader(email: botEmail, apiKey: apiKey)

        // Verify with /users/me
        guard let profile = await fetchProfile(serverURL: serverURL, authHeader: authHeader) else {
            state = .error
            stats.lastError = "Invalid credentials or Zulip server unreachable."
            await notifyStateChange()
            return
        }

        myUserId = profile.userId
        botDisplayName = profile.fullName
        logger.info("Zulip verified: \(profile.fullName) (\(profile.email))")

        pollingTask = Task { [weak self] in
            await self?.pollingLoop(serverURL: serverURL, authHeader: authHeader)
        }
    }

    func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
        state = .disconnected
        botDisplayName = nil
        myUserId = nil
        queueId = nil
        lastEventId = -1
        stats.connectedSince = nil
        await notifyStateChange()
    }

    private func pollingLoop(serverURL: String, authHeader: String) async {
        var consecutiveErrors = 0

        while !Task.isCancelled {
            // Register queue if needed
            if queueId == nil {
                guard let reg = await registerQueue(serverURL: serverURL, authHeader: authHeader) else {
                    consecutiveErrors += 1
                    if consecutiveErrors >= maxConsecutiveErrors { state = .error; await notifyStateChange(); break }
                    try? await Task.sleep(nanoseconds: reconnectDelay)
                    continue
                }
                queueId = reg.queueId
                lastEventId = reg.lastEventId
                state = .connected
                stats.connectedSince = Date()
                stats.lastError = nil
                consecutiveErrors = 0
                await notifyStateChange()
                logger.info("Zulip event queue registered: \(reg.queueId)")
            }

            do {
                guard let qid = queueId,
                      let url = ZulipKit.eventsURL(serverURL: serverURL, queueId: qid, lastEventId: lastEventId) else {
                    throw ZulipNativeError.invalidURL
                }

                var request = URLRequest(url: url)
                request.setValue(authHeader, forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 90

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }

                if http.statusCode == 400 || http.statusCode == 404 {
                    // Queue expired, re-register
                    queueId = nil
                    continue
                }

                guard http.statusCode == 200 else {
                    throw ZulipNativeError.httpError(http.statusCode)
                }

                consecutiveErrors = 0

                guard let events = ZulipKit.parseEvents(data: data) else { continue }
                for event in events {
                    if event.id > lastEventId { lastEventId = event.id }
                    guard let myId = myUserId, ZulipKit.shouldProcess(event: event, myUserId: myId) else { continue }
                    if let msg = event.message {
                        await handleMessage(msg, serverURL: serverURL, authHeader: authHeader)
                    }
                }
            } catch is CancellationError { break }
            catch {
                consecutiveErrors += 1
                stats.lastError = error.localizedDescription
                if consecutiveErrors >= maxConsecutiveErrors {
                    state = .error
                    await notifyStateChange()
                    break
                }
                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: reconnectDelay)
                }
            }
        }
    }

    private func handleMessage(_ msg: ZulipKit.ZulipMessage, serverURL: String, authHeader: String) async {
        guard let text = ZulipKit.extractText(from: msg), !text.isEmpty else { return }

        // Check allowed rooms/streams
        if let allowed = config?.allowedRoomIds, !allowed.isEmpty {
            let topic = ZulipKit.topicFromMessage(msg) ?? ""
            guard allowed.contains(String(msg.id)) || allowed.contains(topic) else { return }
        }

        stats.messagesReceived += 1
        stats.lastMessageAt = Date()

        let channelMessage = NativeChannelMessage(
            channelId: channelId,
            senderName: msg.senderFullName,
            text: text,
            date: Date(timeIntervalSince1970: TimeInterval(msg.timestamp)),
            platformChannelId: "\(msg.id)",
            platformUserId: "\(msg.senderId)"
        )

        guard let handler = onMessage else { return }
        if let response = await handler(channelMessage) {
            let truncated = ZulipKit.truncateForZulip(response)
            if ZulipKit.isStreamMessage(msg) {
                let streamName: String
                if case .stream(let name) = msg.displayRecipient { streamName = name } else { streamName = "" }
                await sendStreamReply(serverURL: serverURL, authHeader: authHeader, stream: streamName, topic: msg.subject ?? "", content: truncated)
            } else {
                await sendDirectReply(serverURL: serverURL, authHeader: authHeader, to: msg.senderEmail, content: truncated)
            }
        }
    }

    private func registerQueue(serverURL: String, authHeader: String) async -> ZulipKit.RegisterResponse? {
        guard let url = ZulipKit.registerURL(serverURL: serverURL) else { return nil }
        guard let body = ZulipKit.registerBody(eventTypes: ["message"]) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return ZulipKit.parseRegisterResponse(data: data)
        } catch { return nil }
    }

    private func sendStreamReply(serverURL: String, authHeader: String, stream: String, topic: String, content: String) async {
        guard let url = ZulipKit.messagesURL(serverURL: serverURL) else { return }
        guard let body = ZulipKit.sendStreamMessageBody(stream: stream, topic: topic, content: content) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
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

    private func sendDirectReply(serverURL: String, authHeader: String, to: String, content: String) async {
        guard let url = ZulipKit.messagesURL(serverURL: serverURL) else { return }
        guard let body = ZulipKit.sendDirectMessageBody(to: to, content: content) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                stats.messagesSent += 1
            }
        } catch {
            logger.error("sendDirectMessage error: \(error.localizedDescription)")
        }
    }

    private func fetchProfile(serverURL: String, authHeader: String) async -> ZulipKit.UserProfile? {
        guard let url = ZulipKit.usersURL(serverURL: serverURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return ZulipKit.parseUserProfile(data: data)
        } catch { return nil }
    }

    private func loadToken(instanceId: String) async -> String? {
        let creds = await KeychainService.shared.loadCredentials(instanceId: instanceId)
        return creds?.apiKey ?? creds?.accessToken
    }

    private func notifyStateChange() async {
        await MainActor.run { NativeChannelsManager.shared.channelStateDidChange() }
    }
}

enum ZulipNativeError: LocalizedError {
    case invalidURL, httpError(Int)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Zulip server URL"
        case .httpError(let c): "Zulip API error (HTTP \(c))"
        }
    }
}
