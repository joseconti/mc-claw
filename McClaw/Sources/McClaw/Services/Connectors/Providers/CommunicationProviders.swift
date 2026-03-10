import Foundation
import Logging
import McClawKit

// MARK: - Auth Header Helpers

private func slackAuthHeaders(_ credentials: ConnectorCredentials) -> [String: String] {
    let token = credentials.accessToken ?? credentials.apiKey ?? ""
    return ["Authorization": "Bearer \(token)"]
}

private func discordAuthHeaders(_ credentials: ConnectorCredentials) -> [String: String] {
    let token = credentials.accessToken ?? credentials.apiKey ?? ""
    return ["Authorization": "Bot \(token)"]
}

// MARK: - Slack Provider

struct SlackProvider: ConnectorProvider {
    static let definitionId = "comm.slack"
    private static let baseURL = "https://slack.com"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let headers = slackAuthHeaders(credentials)
        let data: String

        switch action {
        case "list_channels":
            let types = params["types"] ?? "public_channel,private_channel"
            data = try await listChannels(types: types, headers: headers, credentials: credentials)

        case "read_channel":
            guard let channelId = params["channelId"] else { throw ConnectorProviderError.missingParameter("channelId") }
            let limit = params["limit"] ?? "20"
            data = try await readChannel(channelId: channelId, limit: limit, headers: headers, credentials: credentials)

        case "search_messages":
            guard let query = params["query"] else { throw ConnectorProviderError.missingParameter("query") }
            data = try await searchMessages(query: query, headers: headers, credentials: credentials)

        case "send_message":
            guard let channelId = params["channelId"] else { throw ConnectorProviderError.missingParameter("channelId") }
            guard let text = params["text"] else { throw ConnectorProviderError.missingParameter("text") }
            data = try await sendMessage(channelId: channelId, text: text, headers: headers, credentials: credentials)

        case "reply_to_thread":
            guard let channelId = params["channelId"] else { throw ConnectorProviderError.missingParameter("channelId") }
            guard let threadTs = params["threadTs"] else { throw ConnectorProviderError.missingParameter("threadTs") }
            guard let text = params["text"] else { throw ConnectorProviderError.missingParameter("text") }
            data = try await replyToThread(channelId: channelId, threadTs: threadTs, text: text, headers: headers, credentials: credentials)

        default:
            throw ConnectorProviderError.unknownAction(action)
        }

        let (formatted, truncated) = ConnectorsKit.formatActionResult(data)
        return ConnectorActionResult(
            connectorId: Self.definitionId,
            actionId: action,
            data: ConnectorsKit.sanitizeConnectorData(formatted),
            truncated: truncated
        )
    }

    func testConnection(credentials: ConnectorCredentials) async throws -> Bool {
        let headers = slackAuthHeaders(credentials)
        let (data, status) = try await RESTAPIClient.get(
            path: "/api/auth.test",
            baseURL: Self.baseURL,
            credentials: credentials,
            authHeaders: headers
        )
        guard status == 200 else { return false }
        let json = try RESTAPIClient.parseJSON(data)
        return json["ok"] as? Bool ?? false
    }

    // MARK: - API Calls

    private func listChannels(types: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/api/conversations.list",
            baseURL: Self.baseURL,
            queryItems: [
                URLQueryItem(name: "types", value: types),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "exclude_archived", value: "true"),
            ],
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        guard json["ok"] as? Bool == true else {
            let error = json["error"] as? String ?? "Unknown Slack error"
            throw ConnectorProviderError.apiError(statusCode: 0, message: error)
        }
        let channels = json["channels"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatSlackChannels(channels)
    }

    private func readChannel(channelId: String, limit: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/api/conversations.history",
            baseURL: Self.baseURL,
            queryItems: [
                URLQueryItem(name: "channel", value: channelId),
                URLQueryItem(name: "limit", value: limit),
            ],
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        guard json["ok"] as? Bool == true else {
            let error = json["error"] as? String ?? "Unknown Slack error"
            throw ConnectorProviderError.apiError(statusCode: 0, message: error)
        }
        let messages = json["messages"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatSlackMessages(messages)
    }

    private func sendMessage(channelId: String, text: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = ["channel": channelId, "text": text]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.post(
            path: "/api/chat.postMessage",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        guard json["ok"] as? Bool == true else {
            let error = json["error"] as? String ?? "Unknown Slack error"
            throw ConnectorProviderError.apiError(statusCode: 0, message: error)
        }
        return "Message sent to channel \(channelId)"
    }

    private func replyToThread(channelId: String, threadTs: String, text: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = ["channel": channelId, "text": text, "thread_ts": threadTs]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.post(
            path: "/api/chat.postMessage",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        guard json["ok"] as? Bool == true else {
            let error = json["error"] as? String ?? "Unknown Slack error"
            throw ConnectorProviderError.apiError(statusCode: 0, message: error)
        }
        return "Reply sent to thread"
    }

    private func searchMessages(query: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/api/search.messages",
            baseURL: Self.baseURL,
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "count", value: "20"),
            ],
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        guard json["ok"] as? Bool == true else {
            let error = json["error"] as? String ?? "Unknown Slack error"
            throw ConnectorProviderError.apiError(statusCode: 0, message: error)
        }
        let messagesObj = json["messages"] as? [String: Any] ?? [:]
        let matches = messagesObj["matches"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatSlackSearchResults(matches)
    }
}

// MARK: - Discord Provider

struct DiscordProvider: ConnectorProvider {
    static let definitionId = "comm.discord"
    private static let baseURL = "https://discord.com"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let headers = discordAuthHeaders(credentials)
        let data: String

        switch action {
        case "list_guilds":
            data = try await listGuilds(headers: headers, credentials: credentials)

        case "list_channels":
            guard let guildId = params["guildId"] else { throw ConnectorProviderError.missingParameter("guildId") }
            data = try await listChannels(guildId: guildId, headers: headers, credentials: credentials)

        case "read_channel":
            guard let channelId = params["channelId"] else { throw ConnectorProviderError.missingParameter("channelId") }
            let limit = params["limit"] ?? "20"
            data = try await readChannel(channelId: channelId, limit: limit, headers: headers, credentials: credentials)

        case "send_message":
            guard let channelId = params["channelId"] else { throw ConnectorProviderError.missingParameter("channelId") }
            guard let content = params["content"] else { throw ConnectorProviderError.missingParameter("content") }
            data = try await sendMessage(channelId: channelId, content: content, headers: headers, credentials: credentials)

        default:
            throw ConnectorProviderError.unknownAction(action)
        }

        let (formatted, truncated) = ConnectorsKit.formatActionResult(data)
        return ConnectorActionResult(
            connectorId: Self.definitionId,
            actionId: action,
            data: ConnectorsKit.sanitizeConnectorData(formatted),
            truncated: truncated
        )
    }

    func testConnection(credentials: ConnectorCredentials) async throws -> Bool {
        let headers = discordAuthHeaders(credentials)
        let (_, status) = try await RESTAPIClient.get(
            path: "/api/v10/users/@me",
            baseURL: Self.baseURL,
            credentials: credentials,
            authHeaders: headers
        )
        return status == 200
    }

    // MARK: - API Calls

    private func listGuilds(headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/api/v10/users/@me/guilds",
            baseURL: Self.baseURL,
            credentials: credentials,
            authHeaders: headers
        )
        let guilds = try RESTAPIClient.parseJSONArray(data)
        return ConnectorsKit.formatDiscordGuilds(guilds)
    }

    private func listChannels(guildId: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/api/v10/guilds/\(guildId)/channels",
            baseURL: Self.baseURL,
            credentials: credentials,
            authHeaders: headers
        )
        let channels = try RESTAPIClient.parseJSONArray(data)
        return ConnectorsKit.formatDiscordChannels(channels)
    }

    private func readChannel(channelId: String, limit: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/api/v10/channels/\(channelId)/messages",
            baseURL: Self.baseURL,
            queryItems: [URLQueryItem(name: "limit", value: limit)],
            credentials: credentials,
            authHeaders: headers
        )
        let messages = try RESTAPIClient.parseJSONArray(data)
        return ConnectorsKit.formatDiscordMessages(messages)
    }

    private func sendMessage(channelId: String, content: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = ["content": content]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (_, _) = try await RESTAPIClient.post(
            path: "/api/v10/channels/\(channelId)/messages",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        return "Message sent to channel \(channelId)"
    }
}

// MARK: - Telegram Provider

struct TelegramProvider: ConnectorProvider {
    static let definitionId = "comm.telegram"
    private static let baseURL = "https://api.telegram.org"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let token = credentials.accessToken ?? credentials.apiKey ?? ""
        guard !token.isEmpty else { throw ConnectorProviderError.noCredentials }
        let data: String

        switch action {
        case "get_updates":
            let limit = params["limit"] ?? "20"
            let offset = params["offset"]
            data = try await getUpdates(token: token, limit: limit, offset: offset, credentials: credentials)

        case "get_me":
            data = try await getMe(token: token, credentials: credentials)

        case "send_message":
            guard let chatId = params["chatId"] else { throw ConnectorProviderError.missingParameter("chatId") }
            guard let text = params["text"] else { throw ConnectorProviderError.missingParameter("text") }
            data = try await sendMessage(token: token, chatId: chatId, text: text, credentials: credentials)

        default:
            throw ConnectorProviderError.unknownAction(action)
        }

        let (formatted, truncated) = ConnectorsKit.formatActionResult(data)
        return ConnectorActionResult(
            connectorId: Self.definitionId,
            actionId: action,
            data: ConnectorsKit.sanitizeConnectorData(formatted),
            truncated: truncated
        )
    }

    func testConnection(credentials: ConnectorCredentials) async throws -> Bool {
        let token = credentials.accessToken ?? credentials.apiKey ?? ""
        guard !token.isEmpty else { return false }
        let (data, status) = try await RESTAPIClient.get(
            path: "/bot\(token)/getMe",
            baseURL: Self.baseURL,
            credentials: credentials,
            authHeaders: [:]
        )
        guard status == 200 else { return false }
        let json = try RESTAPIClient.parseJSON(data)
        return json["ok"] as? Bool ?? false
    }

    // MARK: - API Calls

    private func getUpdates(token: String, limit: String, offset: String?, credentials: ConnectorCredentials) async throws -> String {
        var queryItems = [URLQueryItem(name: "limit", value: limit)]
        if let offset { queryItems.append(URLQueryItem(name: "offset", value: offset)) }

        let (data, _) = try await RESTAPIClient.get(
            path: "/bot\(token)/getUpdates",
            baseURL: Self.baseURL,
            queryItems: queryItems,
            credentials: credentials,
            authHeaders: [:]
        )
        let json = try RESTAPIClient.parseJSON(data)
        guard json["ok"] as? Bool == true else {
            let description = json["description"] as? String ?? "Unknown Telegram error"
            throw ConnectorProviderError.apiError(statusCode: 0, message: description)
        }
        let updates = json["result"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatTelegramUpdates(updates)
    }

    private func sendMessage(token: String, chatId: String, text: String, credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = ["chat_id": chatId, "text": text]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.post(
            path: "/bot\(token)/sendMessage",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: [:]
        )
        let json = try RESTAPIClient.parseJSON(data)
        guard json["ok"] as? Bool == true else {
            let description = json["description"] as? String ?? "Unknown Telegram error"
            throw ConnectorProviderError.apiError(statusCode: 0, message: description)
        }
        return "Message sent to chat \(chatId)"
    }

    private func getMe(token: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/bot\(token)/getMe",
            baseURL: Self.baseURL,
            credentials: credentials,
            authHeaders: [:]
        )
        let json = try RESTAPIClient.parseJSON(data)
        guard json["ok"] as? Bool == true else {
            let description = json["description"] as? String ?? "Unknown Telegram error"
            throw ConnectorProviderError.apiError(statusCode: 0, message: description)
        }
        let result = json["result"] as? [String: Any] ?? [:]
        return ConnectorsKit.formatTelegramBotInfo(result)
    }
}
