import Foundation
import Logging
import McClawKit

/// Native Telegram bot channel using long-polling.
/// Runs in the background while McClaw is alive (even minimized to menu bar).
/// Reuses credentials from the existing Telegram ConnectorProvider (comm.telegram).
actor TelegramNativeService: NativeChannel {
    static let shared = TelegramNativeService()

    let channelId = "telegram"
    private let logger = Logger(label: "ai.mcclaw.native-channel.telegram")

    // MARK: - State

    private(set) var state: NativeChannelState = .disconnected
    private(set) var stats = NativeChannelStats()
    private(set) var botDisplayName: String?

    private var config: NativeChannelConfig?
    private var pollingTask: Task<Void, Never>?
    private var currentOffset: Int?
    private var botInfo: TelegramKit.BotInfo?
    private var onMessage: (@Sendable (NativeChannelMessage) async -> String?)?

    /// Long-polling timeout in seconds (Telegram recommends 30).
    private let pollTimeout: Int = 30

    /// Delay before reconnecting after an error.
    private let reconnectDelay: UInt64 = 5_000_000_000 // 5 seconds

    /// Maximum consecutive errors before stopping.
    private let maxConsecutiveErrors = 10

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
            logger.warning("Cannot send outbound: Telegram channel not connected")
            return false
        }
        guard let instanceId = config?.connectorInstanceId,
              let token = await loadBotToken(instanceId: instanceId) else {
            logger.error("Cannot send outbound: no bot token available")
            return false
        }
        guard let chatId = Int64(recipientId) else {
            logger.error("Cannot send outbound: recipientId '\(recipientId)' is not a valid chat ID (Int64)")
            return false
        }
        return await sendMessage(token: token, chatId: chatId, text: text)
    }

    func start(config: NativeChannelConfig) async {
        guard pollingTask == nil else {
            logger.warning("Telegram native channel already running")
            return
        }

        self.config = config
        state = .connecting
        logger.info("Starting Telegram native channel")

        // Load bot token from Keychain via connector credentials
        guard let token = await loadBotToken(instanceId: config.connectorInstanceId) else {
            state = .error
            stats.lastError = "No bot token found. Configure the Telegram connector first."
            logger.error("No bot token for instance \(config.connectorInstanceId)")
            await notifyStateChange()
            return
        }

        // Verify bot token with getMe
        guard let info = await fetchBotInfo(token: token) else {
            state = .error
            stats.lastError = "Invalid bot token or Telegram API unreachable."
            logger.error("getMe failed — invalid token or network error")
            await notifyStateChange()
            return
        }

        botInfo = info
        botDisplayName = info.username.map { "@\($0)" } ?? info.firstName
        state = .connected
        stats.connectedSince = Date()
        stats.lastError = nil
        logger.info("Telegram bot connected: \(botDisplayName ?? "unknown")")
        await notifyStateChange()

        // Start long-polling loop
        pollingTask = Task { [weak self] in
            await self?.pollingLoop(token: token)
        }
    }

    func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
        state = .disconnected
        botInfo = nil
        botDisplayName = nil
        stats.connectedSince = nil
        currentOffset = nil
        logger.info("Telegram native channel stopped")
        await notifyStateChange()
    }

    // MARK: - Polling Loop

    private func pollingLoop(token: String) async {
        var consecutiveErrors = 0

        while !Task.isCancelled {
            do {
                let updates = try await pollUpdates(token: token)
                consecutiveErrors = 0

                if !updates.isEmpty {
                    // Update offset to acknowledge received updates
                    if let newOffset = TelegramKit.nextOffset(from: updates) {
                        currentOffset = newOffset
                    }

                    // Process text messages (skip bot messages)
                    let textUpdates = TelegramKit.filterTextMessages(updates)
                    for update in textUpdates {
                        await handleUpdate(update, token: token)
                    }
                }
            } catch is CancellationError {
                break
            } catch {
                consecutiveErrors += 1
                stats.lastError = error.localizedDescription
                logger.error("Polling error (\(consecutiveErrors)/\(maxConsecutiveErrors)): \(error.localizedDescription)")

                if consecutiveErrors >= maxConsecutiveErrors {
                    state = .error
                    logger.error("Too many consecutive errors, stopping Telegram channel")
                    await notifyStateChange()
                    break
                }

                // Wait before retrying
                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: reconnectDelay)
                }
            }
        }
    }

    // MARK: - API Calls

    private func pollUpdates(token: String) async throws -> [TelegramKit.Update] {
        guard let url = TelegramKit.getUpdatesURL(
            token: token,
            offset: currentOffset,
            timeout: pollTimeout
        ) else {
            throw TelegramNativeError.invalidURL
        }

        var request = URLRequest(url: url)
        // Total timeout = poll timeout + buffer for network latency
        request.timeoutInterval = TimeInterval(pollTimeout + 10)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TelegramNativeError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            guard let updates = TelegramKit.parseUpdates(data: data) else {
                throw TelegramNativeError.parseFailed
            }
            return updates
        case 401:
            throw TelegramNativeError.unauthorized
        case 409:
            throw TelegramNativeError.conflict
        case 429:
            // Rate limited — parse retry_after
            let retryAfter: UInt64
            if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let params = body["parameters"] as? [String: Any],
               let retry = params["retry_after"] as? Int {
                retryAfter = UInt64(retry)
            } else {
                retryAfter = 10
            }
            logger.warning("Rate limited, waiting \(retryAfter)s")
            try await Task.sleep(nanoseconds: retryAfter * 1_000_000_000)
            return []
        default:
            throw TelegramNativeError.httpError(httpResponse.statusCode)
        }
    }

    private func fetchBotInfo(token: String) async -> TelegramKit.BotInfo? {
        guard let url = TelegramKit.getMeURL(token: token) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return TelegramKit.parseBotInfo(data: data)
        } catch {
            logger.error("getMe error: \(error.localizedDescription)")
            return nil
        }
    }

    private func sendMessage(token: String, chatId: Int64, text: String, replyToMessageId: Int? = nil) async -> Bool {
        guard let url = TelegramKit.sendMessageURL(token: token) else { return false }

        let truncated = TelegramKit.truncateForTelegram(text)
        guard let body = TelegramKit.sendMessageBody(
            chatId: chatId,
            text: truncated,
            parseMode: "Markdown",
            replyToMessageId: replyToMessageId
        ) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }

            if http.statusCode == 200 {
                stats.messagesSent += 1
                return true
            }

            // If Markdown parsing fails, retry without parse_mode
            if http.statusCode == 400 {
                logger.warning("Markdown send failed, retrying as plain text")
                return await sendPlainMessage(token: token, chatId: chatId, text: truncated, replyToMessageId: replyToMessageId)
            }

            logger.error("sendMessage HTTP \(http.statusCode)")
            return false
        } catch {
            logger.error("sendMessage error: \(error.localizedDescription)")
            return false
        }
    }

    private func sendPlainMessage(token: String, chatId: Int64, text: String, replyToMessageId: Int?) async -> Bool {
        guard let url = TelegramKit.sendMessageURL(token: token) else { return false }

        var bodyDict: [String: Any] = ["chat_id": chatId, "text": text]
        if let replyId = replyToMessageId {
            bodyDict["reply_to_message_id"] = replyId
        }
        guard let body = try? JSONSerialization.data(withJSONObject: bodyDict) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            stats.messagesSent += 1
            return true
        } catch {
            return false
        }
    }

    // MARK: - Message Handling

    private func handleUpdate(_ update: TelegramKit.Update, token: String) async {
        guard let msg = update.effectiveMessage,
              let text = msg.text,
              !text.isEmpty else { return }

        let senderName = msg.from?.displayName ?? "Unknown"
        stats.messagesReceived += 1
        stats.lastMessageAt = Date()

        logger.info("Message from \(senderName) in chat \(msg.chat.id): \(String(text.prefix(80)))")

        // Check allowed chat IDs if configured
        if let allowed = config?.allowedChatIds, !allowed.isEmpty {
            guard allowed.contains(msg.chat.id) else {
                logger.info("Chat \(msg.chat.id) not in allowedChatIds, ignoring")
                return
            }
        }

        // Build NativeChannelMessage for the handler
        let channelMessage = NativeChannelMessage(
            channelId: channelId,
            chatId: msg.chat.id,
            senderId: msg.from?.id ?? 0,
            senderName: senderName,
            text: text,
            date: msg.dateValue,
            replyToMessageId: msg.messageId
        )

        // Call the message handler (NativeChannelsManager routes to CLI)
        guard let handler = onMessage else {
            logger.warning("No message handler set, ignoring message")
            return
        }

        if let response = await handler(channelMessage) {
            let sent = await sendMessage(
                token: token,
                chatId: msg.chat.id,
                text: response,
                replyToMessageId: msg.messageId
            )
            if sent {
                logger.info("Reply sent to chat \(msg.chat.id)")
            }
        }
    }

    // MARK: - Credential Loading

    private func loadBotToken(instanceId: String) async -> String? {
        let credentials = await KeychainService.shared.loadCredentials(instanceId: instanceId)
        let token = credentials?.apiKey ?? credentials?.accessToken
        guard let token, TelegramKit.isValidBotToken(token) else { return nil }
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

enum TelegramNativeError: LocalizedError {
    case invalidURL
    case invalidResponse
    case parseFailed
    case unauthorized
    case conflict
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Telegram API URL"
        case .invalidResponse: "Invalid response from Telegram"
        case .parseFailed: "Failed to parse Telegram response"
        case .unauthorized: "Bot token is invalid or revoked (401)"
        case .conflict: "Another bot instance is polling (409). Stop other instances first."
        case .httpError(let code): "Telegram API error (HTTP \(code))"
        }
    }
}
