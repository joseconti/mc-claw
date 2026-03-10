import Foundation
import Logging
import McClawKit

// MARK: - Microsoft Graph Client (shared helper)

/// Common HTTP client for Microsoft Graph API v1.0 with Bearer auth and error handling.
struct MicrosoftGraphClient: Sendable {
    private static let logger = Logger(label: "ai.mcclaw.microsoft-graph")
    private static let baseURL = "https://graph.microsoft.com/v1.0"

    /// Execute a GET request against Microsoft Graph API.
    static func get(
        path: String,
        queryItems: [URLQueryItem] = [],
        credentials: ConnectorCredentials
    ) async throws -> (Data, Int) {
        guard let token = credentials.accessToken, !token.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }

        var components = URLComponents(string: baseURL + path)!
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }

        guard let url = components.url else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }

        let statusCode = httpResponse.statusCode

        switch statusCode {
        case 200...299:
            return (data, statusCode)
        case 401:
            throw ConnectorProviderError.authenticationFailed
        case 403:
            let msg = ConnectorsKit.parseMicrosoftGraphError(statusCode: statusCode, body: data)
            throw ConnectorProviderError.apiError(statusCode: 403, message: "Forbidden: \(msg)")
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            let msg = ConnectorsKit.parseMicrosoftGraphError(statusCode: statusCode, body: data)
            throw ConnectorProviderError.apiError(statusCode: statusCode, message: msg)
        }
    }

    /// Parse JSON response as dictionary.
    static func parseJSON(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid JSON response")
        }
        return json
    }
}

// MARK: - Microsoft OAuth Config Helper

/// Build a Microsoft OAuth config with specific scopes.
func microsoftOAuthConfig(scopes: [String]) -> OAuthConfig {
    OAuthConfig(
        authUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
        tokenUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
        scopes: scopes + ["offline_access"],
        redirectScheme: "mcclaw",
        usePKCE: true
    )
}

// MARK: - Outlook Mail Provider

struct OutlookMailProvider: ConnectorProvider {
    static let definitionId = "microsoft.outlook"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String

        switch action {
        case "list_messages":
            let folder = params["folder"] ?? "inbox"
            let top = params["top"] ?? "10"
            data = try await listMessages(folder: folder, top: top, credentials: credentials)

        case "read_message":
            guard let messageId = params["messageId"] else { throw ConnectorProviderError.missingParameter("messageId") }
            data = try await readMessage(messageId: messageId, credentials: credentials)

        case "search":
            guard let query = params["query"] else { throw ConnectorProviderError.missingParameter("query") }
            data = try await searchMessages(query: query, credentials: credentials)

        case "list_folders":
            data = try await listFolders(credentials: credentials)

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
        let (_, status) = try await MicrosoftGraphClient.get(
            path: "/me",
            credentials: credentials
        )
        return status == 200
    }

    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        guard credentials.isExpired, let refreshToken = credentials.refreshToken else { return nil }
        let config = ConnectorRegistry.definition(for: Self.definitionId)?.oauthConfig
            ?? microsoftOAuthConfig(scopes: ["Mail.Read"])
        return try await OAuthService.shared.refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    // MARK: - API Calls

    private func listMessages(folder: String, top: String, credentials: ConnectorCredentials) async throws -> String {
        let path = folder == "inbox" ? "/me/messages" : "/me/mailFolders/\(folder)/messages"
        let (data, _) = try await MicrosoftGraphClient.get(
            path: path,
            queryItems: [
                URLQueryItem(name: "$top", value: top),
                URLQueryItem(name: "$orderby", value: "receivedDateTime desc"),
                URLQueryItem(name: "$select", value: "id,subject,from,receivedDateTime,bodyPreview,isRead"),
            ],
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        let messages = json["value"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatOutlookMessages(messages)
    }

    private func readMessage(messageId: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/messages/\(messageId)",
            queryItems: [
                URLQueryItem(name: "$select", value: "id,subject,from,receivedDateTime,body,isRead,toRecipients,ccRecipients"),
            ],
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        return ConnectorsKit.formatOutlookMessages([json])
    }

    private func searchMessages(query: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/messages",
            queryItems: [
                URLQueryItem(name: "$search", value: "\"\(query)\""),
                URLQueryItem(name: "$top", value: "20"),
                URLQueryItem(name: "$select", value: "id,subject,from,receivedDateTime,bodyPreview,isRead"),
            ],
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        let messages = json["value"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatOutlookMessages(messages)
    }

    private func listFolders(credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/mailFolders",
            queryItems: [
                URLQueryItem(name: "$select", value: "id,displayName,totalItemCount,unreadItemCount"),
            ],
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        let folders = json["value"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatOutlookFolders(folders)
    }
}

// MARK: - Outlook Calendar Provider

struct OutlookCalendarProvider: ConnectorProvider {
    static let definitionId = "microsoft.calendar"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String

        switch action {
        case "list_events":
            guard let startDateTime = params["startDateTime"] else { throw ConnectorProviderError.missingParameter("startDateTime") }
            guard let endDateTime = params["endDateTime"] else { throw ConnectorProviderError.missingParameter("endDateTime") }
            data = try await listEvents(startDateTime: startDateTime, endDateTime: endDateTime, credentials: credentials)

        case "get_event":
            guard let eventId = params["eventId"] else { throw ConnectorProviderError.missingParameter("eventId") }
            data = try await getEvent(eventId: eventId, credentials: credentials)

        case "list_calendars":
            data = try await listCalendars(credentials: credentials)

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
        let (_, status) = try await MicrosoftGraphClient.get(
            path: "/me/calendars",
            queryItems: [URLQueryItem(name: "$top", value: "1")],
            credentials: credentials
        )
        return status == 200
    }

    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        guard credentials.isExpired, let refreshToken = credentials.refreshToken else { return nil }
        let config = ConnectorRegistry.definition(for: Self.definitionId)?.oauthConfig
            ?? microsoftOAuthConfig(scopes: ["Calendars.Read"])
        return try await OAuthService.shared.refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    // MARK: - API Calls

    private func listEvents(startDateTime: String, endDateTime: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/calendarview",
            queryItems: [
                URLQueryItem(name: "startDateTime", value: startDateTime),
                URLQueryItem(name: "endDateTime", value: endDateTime),
                URLQueryItem(name: "$orderby", value: "start/dateTime"),
                URLQueryItem(name: "$top", value: "50"),
                URLQueryItem(name: "$select", value: "id,subject,start,end,location,organizer,isAllDay"),
            ],
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        let events = json["value"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatOutlookEvents(events)
    }

    private func getEvent(eventId: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/events/\(eventId)",
            queryItems: [
                URLQueryItem(name: "$select", value: "id,subject,start,end,location,organizer,isAllDay,body,attendees"),
            ],
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        return ConnectorsKit.formatOutlookEvents([json])
    }

    private func listCalendars(credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/calendars",
            queryItems: [
                URLQueryItem(name: "$select", value: "id,name,color,isDefaultCalendar"),
            ],
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        let calendars = json["value"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatOutlookCalendars(calendars)
    }
}

// MARK: - OneDrive Provider

struct OneDriveProvider: ConnectorProvider {
    static let definitionId = "microsoft.onedrive"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String

        switch action {
        case "list_recent":
            data = try await listRecent(credentials: credentials)

        case "search":
            guard let query = params["query"] else { throw ConnectorProviderError.missingParameter("query") }
            data = try await searchFiles(query: query, credentials: credentials)

        case "get_item":
            guard let itemId = params["itemId"] else { throw ConnectorProviderError.missingParameter("itemId") }
            data = try await getItem(itemId: itemId, credentials: credentials)

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
        let (_, status) = try await MicrosoftGraphClient.get(
            path: "/me/drive",
            credentials: credentials
        )
        return status == 200
    }

    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        guard credentials.isExpired, let refreshToken = credentials.refreshToken else { return nil }
        let config = ConnectorRegistry.definition(for: Self.definitionId)?.oauthConfig
            ?? microsoftOAuthConfig(scopes: ["Files.Read"])
        return try await OAuthService.shared.refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    // MARK: - API Calls

    private func listRecent(credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/drive/recent",
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        let items = json["value"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatOneDriveItems(items)
    }

    private func searchFiles(query: String, credentials: ConnectorCredentials) async throws -> String {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/drive/root/search(q='\(encodedQuery)')",
            queryItems: [URLQueryItem(name: "$top", value: "20")],
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        let items = json["value"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatOneDriveItems(items)
    }

    private func getItem(itemId: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/drive/items/\(itemId)",
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        return ConnectorsKit.formatOneDriveItemDetail(json)
    }
}

// MARK: - Microsoft To Do Provider

struct MicrosoftToDoProvider: ConnectorProvider {
    static let definitionId = "microsoft.todo"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String

        switch action {
        case "list_tasks":
            guard let listId = params["listId"] else { throw ConnectorProviderError.missingParameter("listId") }
            data = try await listTasks(listId: listId, credentials: credentials)

        case "list_lists":
            data = try await listLists(credentials: credentials)

        case "get_task":
            guard let listId = params["listId"] else { throw ConnectorProviderError.missingParameter("listId") }
            guard let taskId = params["taskId"] else { throw ConnectorProviderError.missingParameter("taskId") }
            data = try await getTask(listId: listId, taskId: taskId, credentials: credentials)

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
        let (_, status) = try await MicrosoftGraphClient.get(
            path: "/me/todo/lists",
            queryItems: [URLQueryItem(name: "$top", value: "1")],
            credentials: credentials
        )
        return status == 200
    }

    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        guard credentials.isExpired, let refreshToken = credentials.refreshToken else { return nil }
        let config = ConnectorRegistry.definition(for: Self.definitionId)?.oauthConfig
            ?? microsoftOAuthConfig(scopes: ["Tasks.Read"])
        return try await OAuthService.shared.refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    // MARK: - API Calls

    private func listTasks(listId: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/todo/lists/\(listId)/tasks",
            queryItems: [
                URLQueryItem(name: "$top", value: "50"),
                URLQueryItem(name: "$select", value: "id,title,status,importance,dueDateTime,completedDateTime,createdDateTime"),
            ],
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        let tasks = json["value"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatToDoTasks(tasks)
    }

    private func listLists(credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/todo/lists",
            queryItems: [
                URLQueryItem(name: "$select", value: "id,displayName,isOwner,wellknownListName"),
            ],
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        let lists = json["value"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatToDoLists(lists)
    }

    private func getTask(listId: String, taskId: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await MicrosoftGraphClient.get(
            path: "/me/todo/lists/\(listId)/tasks/\(taskId)",
            credentials: credentials
        )
        let json = try MicrosoftGraphClient.parseJSON(data)
        return ConnectorsKit.formatToDoTaskDetail(json)
    }
}
