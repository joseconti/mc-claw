import Foundation
import Logging
import McClawKit

/// Native Matrix channel using Client-Server API long-polling (/sync).
/// Connects to any Matrix homeserver directly from McClaw.
actor MatrixNativeService: NativeChannel {
    static let shared = MatrixNativeService()
    let channelId = "matrix"
    private let logger = Logger(label: "ai.mcclaw.native-channel.matrix")

    // State
    private(set) var state: NativeChannelState = .disconnected
    private(set) var stats = NativeChannelStats()
    private(set) var botDisplayName: String?

    private var config: NativeChannelConfig?
    private var pollingTask: Task<Void, Never>?
    private var sinceToken: String?
    private var myUserId: String?
    private var onMessage: (@Sendable (NativeChannelMessage) async -> String?)?

    private let syncTimeout: Int = 30000
    private let reconnectDelay: UInt64 = 5_000_000_000
    private let maxConsecutiveErrors = 10

    private init() {}

    // NativeChannel conformance
    func setOnMessage(_ handler: @escaping @Sendable (NativeChannelMessage) async -> String?) {
        self.onMessage = handler
    }

    func start(config: NativeChannelConfig) async {
        guard pollingTask == nil else { return }
        self.config = config
        state = .connecting

        // Need homeserver URL from config
        guard let serverURL = config.serverURL, MatrixKit.isValidHomeserverURL(serverURL) else {
            state = .error
            stats.lastError = "Homeserver URL required. Add it in channel settings."
            await notifyStateChange()
            return
        }

        // Load access token
        guard let token = await loadToken(instanceId: config.connectorInstanceId) else {
            state = .error
            stats.lastError = "No access token found. Configure the Matrix connector first."
            await notifyStateChange()
            return
        }

        // Verify with whoami
        guard let whoami = await fetchWhoAmI(serverURL: serverURL, token: token) else {
            state = .error
            stats.lastError = "Invalid access token or homeserver unreachable."
            await notifyStateChange()
            return
        }

        myUserId = whoami.userId
        botDisplayName = whoami.userId
        state = .connected
        stats.connectedSince = Date()
        stats.lastError = nil
        await notifyStateChange()
        logger.info("Matrix connected: \(whoami.userId)")

        pollingTask = Task { [weak self] in
            await self?.syncLoop(serverURL: serverURL, token: token)
        }
    }

    func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
        state = .disconnected
        botDisplayName = nil
        myUserId = nil
        sinceToken = nil
        stats.connectedSince = nil
        await notifyStateChange()
    }

    // Sync loop
    private func syncLoop(serverURL: String, token: String) async {
        var consecutiveErrors = 0
        // Do initial sync without timeout to get since token
        if sinceToken == nil {
            if let initialToken = await doSync(serverURL: serverURL, token: token, since: nil, timeout: 0) {
                sinceToken = initialToken
            }
        }

        while !Task.isCancelled {
            do {
                guard let url = MatrixKit.syncURL(homeserver: serverURL, sinceToken: sinceToken, timeout: syncTimeout) else {
                    throw MatrixNativeError.invalidURL
                }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = TimeInterval(syncTimeout / 1000 + 10)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if code == 401 { throw MatrixNativeError.unauthorized }
                    throw MatrixNativeError.httpError(code)
                }

                consecutiveErrors = 0

                guard let syncResponse = MatrixKit.parseSyncResponse(data: data) else { continue }
                sinceToken = syncResponse.nextBatch

                // Extract and handle messages
                guard let myId = myUserId else { continue }
                let messages = MatrixKit.extractMessages(from: syncResponse, myUserId: myId)
                for (roomId, event) in messages {
                    await handleRoomMessage(roomId: roomId, event: event, serverURL: serverURL, token: token)
                }
            } catch is CancellationError {
                break
            } catch {
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

    private func doSync(serverURL: String, token: String, since: String?, timeout: Int) async -> String? {
        guard let url = MatrixKit.syncURL(homeserver: serverURL, sinceToken: since, timeout: timeout) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = TimeInterval(timeout / 1000 + 10)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let sync = MatrixKit.parseSyncResponse(data: data)
            return sync?.nextBatch
        } catch {
            return nil
        }
    }

    private func handleRoomMessage(roomId: String, event: MatrixKit.RoomEvent, serverURL: String, token: String) async {
        guard let text = MatrixKit.extractText(from: event), !text.isEmpty else { return }

        // Check allowed rooms
        if let allowed = config?.allowedRoomIds, !allowed.isEmpty {
            guard allowed.contains(roomId) else { return }
        }

        stats.messagesReceived += 1
        stats.lastMessageAt = Date()

        let senderName = event.sender
        let channelMessage = NativeChannelMessage(
            channelId: channelId,
            senderName: senderName,
            text: text,
            date: Date(timeIntervalSince1970: TimeInterval(event.originServerTs) / 1000.0),
            platformChannelId: roomId,
            platformUserId: event.sender
        )

        guard let handler = onMessage else { return }
        if let response = await handler(channelMessage) {
            await sendRoomMessage(serverURL: serverURL, token: token, roomId: roomId, text: response)
        }
    }

    private func sendRoomMessage(serverURL: String, token: String, roomId: String, text: String) async {
        let txnId = MatrixKit.generateTxnId()
        guard let url = MatrixKit.sendMessageURL(homeserver: serverURL, roomId: roomId, txnId: txnId) else { return }
        let truncated = MatrixKit.truncateForMatrix(text)
        guard let body = MatrixKit.noticeMessageBody(text: truncated) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
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
            logger.error("sendMessage error: \(error.localizedDescription)")
        }
    }

    private func fetchWhoAmI(serverURL: String, token: String) async -> MatrixKit.WhoAmIResponse? {
        guard let url = MatrixKit.whoAmIURL(homeserver: serverURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return MatrixKit.parseWhoAmI(data: data)
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

enum MatrixNativeError: LocalizedError {
    case invalidURL, unauthorized, httpError(Int)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Matrix homeserver URL"
        case .unauthorized: "Access token is invalid or revoked (401)"
        case .httpError(let c): "Matrix API error (HTTP \(c))"
        }
    }
}
