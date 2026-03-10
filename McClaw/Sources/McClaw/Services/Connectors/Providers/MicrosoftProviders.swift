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

        return try handleResponse(data: data, httpResponse: httpResponse)
    }

    /// Execute a POST request with JSON body against Microsoft Graph API.
    static func post(
        path: String,
        body: Data,
        credentials: ConnectorCredentials
    ) async throws -> (Data, Int) {
        guard let token = credentials.accessToken, !token.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }

        guard let url = URL(string: baseURL + path) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }

        return try handleResponse(data: data, httpResponse: httpResponse)
    }

    /// Execute a PATCH request with JSON body against Microsoft Graph API.
    static func patch(
        path: String,
        body: Data,
        credentials: ConnectorCredentials
    ) async throws -> (Data, Int) {
        guard let token = credentials.accessToken, !token.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }

        guard let url = URL(string: baseURL + path) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }

        return try handleResponse(data: data, httpResponse: httpResponse)
    }

    /// Execute a DELETE request against Microsoft Graph API.
    static func delete(
        path: String,
        credentials: ConnectorCredentials
    ) async throws -> (Data, Int) {
        guard let token = credentials.accessToken, !token.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }

        guard let url = URL(string: baseURL + path) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }

        return try handleResponse(data: data, httpResponse: httpResponse)
    }

    /// Shared response handler for all Microsoft Graph API methods.
    private static func handleResponse(data: Data, httpResponse: HTTPURLResponse) throws -> (Data, Int) {
        let statusCode = httpResponse.statusCode

        switch statusCode {
        case 200...204:
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

        case "send_email":
            guard let to = params["to"] else { throw ConnectorProviderError.missingParameter("to") }
            guard let subject = params["subject"] else { throw ConnectorProviderError.missingParameter("subject") }
            guard let body = params["body"] else { throw ConnectorProviderError.missingParameter("body") }
            data = try await sendEmail(to: to, subject: subject, body: body, cc: params["cc"], bcc: params["bcc"], credentials: credentials)

        case "reply_to_email":
            guard let messageId = params["messageId"] else { throw ConnectorProviderError.missingParameter("messageId") }
            guard let body = params["body"] else { throw ConnectorProviderError.missingParameter("body") }
            data = try await replyToEmail(messageId: messageId, body: body, credentials: credentials)

        case "create_draft":
            guard let to = params["to"] else { throw ConnectorProviderError.missingParameter("to") }
            guard let subject = params["subject"] else { throw ConnectorProviderError.missingParameter("subject") }
            guard let body = params["body"] else { throw ConnectorProviderError.missingParameter("body") }
            data = try await createDraft(to: to, subject: subject, body: body, credentials: credentials)

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
            ?? microsoftOAuthConfig(scopes: ["Mail.Read", "Mail.Send"])
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

    private func sendEmail(to: String, subject: String, body: String, cc: String?, bcc: String?, credentials: ConnectorCredentials) async throws -> String {
        var message: [String: Any] = [
            "subject": subject,
            "body": ["contentType": "Text", "content": body],
            "toRecipients": [["emailAddress": ["address": to]]],
        ]
        if let cc = cc, !cc.isEmpty {
            message["ccRecipients"] = [["emailAddress": ["address": cc]]]
        }
        if let bcc = bcc, !bcc.isEmpty {
            message["bccRecipients"] = [["emailAddress": ["address": bcc]]]
        }
        let payload: [String: Any] = ["message": message]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (_, _) = try await MicrosoftGraphClient.post(
            path: "/me/sendMail",
            body: jsonData,
            credentials: credentials
        )
        return "Email sent successfully to \(to)"
    }

    private func replyToEmail(messageId: String, body: String, credentials: ConnectorCredentials) async throws -> String {
        let payload: [String: Any] = ["comment": body]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (_, _) = try await MicrosoftGraphClient.post(
            path: "/me/messages/\(messageId)/reply",
            body: jsonData,
            credentials: credentials
        )
        return "Reply sent successfully"
    }

    private func createDraft(to: String, subject: String, body: String, credentials: ConnectorCredentials) async throws -> String {
        let payload: [String: Any] = [
            "subject": subject,
            "body": ["contentType": "Text", "content": body],
            "toRecipients": [["emailAddress": ["address": to]]],
            "isDraft": true,
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (_, _) = try await MicrosoftGraphClient.post(
            path: "/me/messages",
            body: jsonData,
            credentials: credentials
        )
        return "Draft created: \(subject)"
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

        case "create_event":
            guard let subject = params["subject"] else { throw ConnectorProviderError.missingParameter("subject") }
            guard let start = params["start"] else { throw ConnectorProviderError.missingParameter("start") }
            guard let end = params["end"] else { throw ConnectorProviderError.missingParameter("end") }
            data = try await createEvent(subject: subject, start: start, end: end, location: params["location"], body: params["body"], credentials: credentials)

        case "update_event":
            guard let eventId = params["eventId"] else { throw ConnectorProviderError.missingParameter("eventId") }
            data = try await updateEvent(eventId: eventId, params: params, credentials: credentials)

        case "delete_event":
            guard let eventId = params["eventId"] else { throw ConnectorProviderError.missingParameter("eventId") }
            data = try await deleteEvent(eventId: eventId, credentials: credentials)

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
            ?? microsoftOAuthConfig(scopes: ["Calendars.ReadWrite"])
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

    private func createEvent(subject: String, start: String, end: String, location: String?, body: String?, credentials: ConnectorCredentials) async throws -> String {
        var payload: [String: Any] = [
            "subject": subject,
            "start": ["dateTime": start, "timeZone": "UTC"],
            "end": ["dateTime": end, "timeZone": "UTC"],
        ]
        if let body = body, !body.isEmpty {
            payload["body"] = ["contentType": "Text", "content": body]
        }
        if let location = location, !location.isEmpty {
            payload["location"] = ["displayName": location]
        }
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (_, _) = try await MicrosoftGraphClient.post(
            path: "/me/events",
            body: jsonData,
            credentials: credentials
        )
        return "Event created: \(subject)"
    }

    private func updateEvent(eventId: String, params: [String: String], credentials: ConnectorCredentials) async throws -> String {
        var payload: [String: Any] = [:]
        if let subject = params["subject"] {
            payload["subject"] = subject
        }
        if let start = params["start"] {
            payload["start"] = ["dateTime": start, "timeZone": "UTC"]
        }
        if let end = params["end"] {
            payload["end"] = ["dateTime": end, "timeZone": "UTC"]
        }
        if let location = params["location"] {
            payload["location"] = ["displayName": location]
        }
        if let body = params["body"] {
            payload["body"] = ["contentType": "Text", "content": body]
        }
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (_, _) = try await MicrosoftGraphClient.patch(
            path: "/me/events/\(eventId)",
            body: jsonData,
            credentials: credentials
        )
        return "Event updated"
    }

    private func deleteEvent(eventId: String, credentials: ConnectorCredentials) async throws -> String {
        let (_, _) = try await MicrosoftGraphClient.delete(
            path: "/me/events/\(eventId)",
            credentials: credentials
        )
        return "Event deleted"
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

        case "create_folder":
            guard let name = params["name"] else { throw ConnectorProviderError.missingParameter("name") }
            data = try await createFolder(name: name, parentPath: params["parentPath"], credentials: credentials)

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
            ?? microsoftOAuthConfig(scopes: ["Files.ReadWrite"])
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

    private func createFolder(name: String, parentPath: String?, credentials: ConnectorCredentials) async throws -> String {
        let path: String
        if let parentPath = parentPath, !parentPath.isEmpty, parentPath != "root" {
            path = "/me/drive/root:/\(parentPath):/children"
        } else {
            path = "/me/drive/root/children"
        }
        let payload: [String: Any] = [
            "name": name,
            "folder": [:] as [String: Any],
            "@microsoft.graph.conflictBehavior": "rename",
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (_, _) = try await MicrosoftGraphClient.post(
            path: path,
            body: jsonData,
            credentials: credentials
        )
        return "Folder created: \(name)"
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

        case "create_task":
            guard let listId = params["listId"] else { throw ConnectorProviderError.missingParameter("listId") }
            guard let title = params["title"] else { throw ConnectorProviderError.missingParameter("title") }
            data = try await createTask(listId: listId, title: title, body: params["body"], dueDateTime: params["dueDateTime"], credentials: credentials)

        case "complete_task":
            guard let listId = params["listId"] else { throw ConnectorProviderError.missingParameter("listId") }
            guard let taskId = params["taskId"] else { throw ConnectorProviderError.missingParameter("taskId") }
            data = try await completeTask(listId: listId, taskId: taskId, credentials: credentials)

        case "delete_task":
            guard let listId = params["listId"] else { throw ConnectorProviderError.missingParameter("listId") }
            guard let taskId = params["taskId"] else { throw ConnectorProviderError.missingParameter("taskId") }
            data = try await deleteTask(listId: listId, taskId: taskId, credentials: credentials)

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
            ?? microsoftOAuthConfig(scopes: ["Tasks.ReadWrite"])
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

    private func createTask(listId: String, title: String, body: String?, dueDateTime: String?, credentials: ConnectorCredentials) async throws -> String {
        var payload: [String: Any] = ["title": title]
        if let body = body, !body.isEmpty {
            payload["body"] = ["content": body, "contentType": "text"]
        }
        if let dueDateTime = dueDateTime, !dueDateTime.isEmpty {
            payload["dueDateTime"] = ["dateTime": dueDateTime, "timeZone": "UTC"]
        }
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (_, _) = try await MicrosoftGraphClient.post(
            path: "/me/todo/lists/\(listId)/tasks",
            body: jsonData,
            credentials: credentials
        )
        return "Task created: \(title)"
    }

    private func completeTask(listId: String, taskId: String, credentials: ConnectorCredentials) async throws -> String {
        let payload: [String: Any] = ["status": "completed"]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (_, _) = try await MicrosoftGraphClient.patch(
            path: "/me/todo/lists/\(listId)/tasks/\(taskId)",
            body: jsonData,
            credentials: credentials
        )
        return "Task completed"
    }

    private func deleteTask(listId: String, taskId: String, credentials: ConnectorCredentials) async throws -> String {
        let (_, _) = try await MicrosoftGraphClient.delete(
            path: "/me/todo/lists/\(listId)/tasks/\(taskId)",
            credentials: credentials
        )
        return "Task deleted"
    }
}
