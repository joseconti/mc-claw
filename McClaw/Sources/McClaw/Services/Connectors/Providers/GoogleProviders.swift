import Foundation
import Logging
import McClawKit

// MARK: - Google API Client (shared helper)

/// Common HTTP client for Google APIs with Bearer auth, error handling, and token refresh.
struct GoogleAPIClient: Sendable {
    private static let logger = Logger(label: "ai.mcclaw.google-api")

    /// Execute a GET request against a Google API endpoint.
    static func get(
        path: String,
        baseURL: String = "https://www.googleapis.com",
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

    /// Execute a POST request with JSON body against a Google API endpoint.
    static func post(
        path: String,
        baseURL: String = "https://www.googleapis.com",
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

    /// Execute a PATCH request with JSON body against a Google API endpoint.
    static func patch(
        path: String,
        baseURL: String = "https://www.googleapis.com",
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

    /// Execute a PUT request with JSON body against a Google API endpoint.
    static func put(
        path: String,
        baseURL: String = "https://www.googleapis.com",
        body: Data,
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
        request.httpMethod = "PUT"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }

        return try handleResponse(data: data, httpResponse: httpResponse)
    }

    /// Execute a DELETE request against a Google API endpoint.
    static func delete(
        path: String,
        baseURL: String = "https://www.googleapis.com",
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

    /// Shared response handler for all Google API methods.
    private static func handleResponse(data: Data, httpResponse: HTTPURLResponse) throws -> (Data, Int) {
        let statusCode = httpResponse.statusCode

        switch statusCode {
        case 200...204:
            return (data, statusCode)
        case 401:
            throw ConnectorProviderError.authenticationFailed
        case 403:
            let msg = ConnectorsKit.parseGoogleAPIError(statusCode: statusCode, body: data)
            throw ConnectorProviderError.apiError(statusCode: 403, message: "Forbidden: \(msg)")
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            let msg = ConnectorsKit.parseGoogleAPIError(statusCode: statusCode, body: data)
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

// MARK: - Gmail Provider

struct GmailProvider: ConnectorProvider {
    static let definitionId = "google.gmail"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String
        switch action {
        case "search":
            guard let query = params["q"] else { throw ConnectorProviderError.missingParameter("q") }
            let maxResults = params["maxResults"] ?? "10"
            data = try await searchEmails(query: query, maxResults: maxResults, credentials: credentials)

        case "read":
            guard let messageId = params["messageId"] else { throw ConnectorProviderError.missingParameter("messageId") }
            data = try await readEmail(messageId: messageId, credentials: credentials)

        case "list_unread":
            let maxResults = params["maxResults"] ?? "10"
            data = try await searchEmails(query: "is:unread", maxResults: maxResults, credentials: credentials)

        case "list_labels":
            data = try await listLabels(credentials: credentials)

        // Write actions
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
        let (_, status) = try await GoogleAPIClient.get(
            path: "/gmail/v1/users/me/profile",
            credentials: credentials
        )
        return status == 200
    }

    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        guard credentials.isExpired, let refreshToken = credentials.refreshToken else { return nil }
        let config = ConnectorRegistry.definition(for: Self.definitionId)?.oauthConfig
            ?? googleOAuthConfig(scopes: ["https://www.googleapis.com/auth/gmail.readonly", "https://www.googleapis.com/auth/gmail.compose"])
        return try await OAuthService.shared.refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    // MARK: - API Calls

    private func searchEmails(query: String, maxResults: String, credentials: ConnectorCredentials) async throws -> String {
        // Step 1: Search for message IDs
        let (listData, _) = try await GoogleAPIClient.get(
            path: "/gmail/v1/users/me/messages",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "maxResults", value: maxResults),
            ],
            credentials: credentials
        )

        let listJSON = try GoogleAPIClient.parseJSON(listData)
        guard let messageRefs = listJSON["messages"] as? [[String: Any]] else {
            return "(no messages found)"
        }

        // Step 2: Fetch each message details
        var messages: [[String: Any]] = []
        for ref in messageRefs.prefix(Int(maxResults) ?? 10) {
            guard let id = ref["id"] as? String else { continue }
            let (msgData, _) = try await GoogleAPIClient.get(
                path: "/gmail/v1/users/me/messages/\(id)",
                queryItems: [URLQueryItem(name: "format", value: "metadata"),
                             URLQueryItem(name: "metadataHeaders", value: "Subject"),
                             URLQueryItem(name: "metadataHeaders", value: "From"),
                             URLQueryItem(name: "metadataHeaders", value: "Date")],
                credentials: credentials
            )
            if let msgJSON = try? GoogleAPIClient.parseJSON(msgData) {
                messages.append(msgJSON)
            }
        }

        return ConnectorsKit.formatGmailMessages(messages)
    }

    private func readEmail(messageId: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await GoogleAPIClient.get(
            path: "/gmail/v1/users/me/messages/\(messageId)",
            queryItems: [URLQueryItem(name: "format", value: "full")],
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        return ConnectorsKit.formatGmailMessages([json])
    }

    private func listLabels(credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await GoogleAPIClient.get(
            path: "/gmail/v1/users/me/labels",
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        guard let labels = json["labels"] as? [[String: Any]] else { return "(no labels)" }
        return labels.compactMap { $0["name"] as? String }.joined(separator: "\n")
    }

    // MARK: - Write Actions

    /// Build an RFC 2822 message and base64url-encode it for the Gmail API.
    private func buildRawMessage(to: String, subject: String, body: String, cc: String? = nil, bcc: String? = nil, inReplyTo: String? = nil, references: String? = nil, threadId: String? = nil) -> String {
        var headers = "To: \(to)\r\nSubject: \(subject)\r\nContent-Type: text/plain; charset=utf-8\r\n"
        if let cc = cc, !cc.isEmpty { headers += "Cc: \(cc)\r\n" }
        if let bcc = bcc, !bcc.isEmpty { headers += "Bcc: \(bcc)\r\n" }
        if let inReplyTo = inReplyTo { headers += "In-Reply-To: \(inReplyTo)\r\nReferences: \(references ?? inReplyTo)\r\n" }
        let raw = headers + "\r\n" + body
        return Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func sendEmail(to: String, subject: String, body: String, cc: String?, bcc: String?, credentials: ConnectorCredentials) async throws -> String {
        let raw = buildRawMessage(to: to, subject: subject, body: body, cc: cc, bcc: bcc)
        let payload: [String: Any] = ["raw": raw]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (_, _) = try await GoogleAPIClient.post(
            path: "/gmail/v1/users/me/messages/send",
            body: jsonData,
            credentials: credentials
        )
        return "Email sent successfully to \(to)"
    }

    private func replyToEmail(messageId: String, body: String, credentials: ConnectorCredentials) async throws -> String {
        // Fetch original message to get threadId, Subject, and From
        let (origData, _) = try await GoogleAPIClient.get(
            path: "/gmail/v1/users/me/messages/\(messageId)",
            queryItems: [
                URLQueryItem(name: "format", value: "metadata"),
                URLQueryItem(name: "metadataHeaders", value: "Subject"),
                URLQueryItem(name: "metadataHeaders", value: "From"),
                URLQueryItem(name: "metadataHeaders", value: "Message-ID"),
            ],
            credentials: credentials
        )
        let origJSON = try GoogleAPIClient.parseJSON(origData)
        let threadId = origJSON["threadId"] as? String
        let headers = origJSON["payload"].flatMap { ($0 as? [String: Any])?["headers"] as? [[String: Any]] } ?? []

        let fromHeader = headers.first { ($0["name"] as? String) == "From" }?["value"] as? String ?? ""
        let subjectHeader = headers.first { ($0["name"] as? String) == "Subject" }?["value"] as? String ?? ""
        let messageIdHeader = headers.first { ($0["name"] as? String) == "Message-ID" }?["value"] as? String

        let replySubject = subjectHeader.hasPrefix("Re: ") ? subjectHeader : "Re: \(subjectHeader)"
        let raw = buildRawMessage(
            to: fromHeader,
            subject: replySubject,
            body: body,
            inReplyTo: messageIdHeader,
            references: messageIdHeader
        )

        var payload: [String: Any] = ["raw": raw]
        if let threadId { payload["threadId"] = threadId }
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (_, _) = try await GoogleAPIClient.post(
            path: "/gmail/v1/users/me/messages/send",
            body: jsonData,
            credentials: credentials
        )
        return "Reply sent to \(fromHeader)"
    }

    private func createDraft(to: String, subject: String, body: String, credentials: ConnectorCredentials) async throws -> String {
        let raw = buildRawMessage(to: to, subject: subject, body: body)
        let payload: [String: Any] = ["message": ["raw": raw]]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (_, _) = try await GoogleAPIClient.post(
            path: "/gmail/v1/users/me/drafts",
            body: jsonData,
            credentials: credentials
        )
        return "Draft created: \(subject)"
    }
}

// MARK: - Google Calendar Provider

struct GoogleCalendarProvider: ConnectorProvider {
    static let definitionId = "google.calendar"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String
        switch action {
        case "list_events":
            guard let timeMin = params["timeMin"] else { throw ConnectorProviderError.missingParameter("timeMin") }
            guard let timeMax = params["timeMax"] else { throw ConnectorProviderError.missingParameter("timeMax") }
            let calendarId = params["calendarId"] ?? "primary"
            data = try await listEvents(calendarId: calendarId, timeMin: timeMin, timeMax: timeMax, credentials: credentials)

        case "get_event":
            guard let eventId = params["eventId"] else { throw ConnectorProviderError.missingParameter("eventId") }
            let calendarId = params["calendarId"] ?? "primary"
            data = try await getEvent(calendarId: calendarId, eventId: eventId, credentials: credentials)

        case "list_calendars":
            data = try await listCalendars(credentials: credentials)

        // Write actions
        case "create_event":
            guard let summary = params["summary"] else { throw ConnectorProviderError.missingParameter("summary") }
            guard let startDateTime = params["startDateTime"] else { throw ConnectorProviderError.missingParameter("startDateTime") }
            guard let endDateTime = params["endDateTime"] else { throw ConnectorProviderError.missingParameter("endDateTime") }
            let calendarId = params["calendarId"] ?? "primary"
            data = try await createEvent(calendarId: calendarId, summary: summary, startDateTime: startDateTime, endDateTime: endDateTime, location: params["location"], description: params["description"], credentials: credentials)

        case "update_event":
            guard let eventId = params["eventId"] else { throw ConnectorProviderError.missingParameter("eventId") }
            let calendarId = params["calendarId"] ?? "primary"
            data = try await updateEvent(calendarId: calendarId, eventId: eventId, params: params, credentials: credentials)

        case "delete_event":
            guard let eventId = params["eventId"] else { throw ConnectorProviderError.missingParameter("eventId") }
            let calendarId = params["calendarId"] ?? "primary"
            data = try await deleteEvent(calendarId: calendarId, eventId: eventId, credentials: credentials)

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
        let (_, status) = try await GoogleAPIClient.get(
            path: "/calendar/v3/users/me/calendarList",
            queryItems: [URLQueryItem(name: "maxResults", value: "1")],
            credentials: credentials
        )
        return status == 200
    }

    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        guard credentials.isExpired, let refreshToken = credentials.refreshToken else { return nil }
        let config = ConnectorRegistry.definition(for: Self.definitionId)?.oauthConfig
            ?? googleOAuthConfig(scopes: ["https://www.googleapis.com/auth/calendar.events"])
        return try await OAuthService.shared.refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    private func listEvents(calendarId: String, timeMin: String, timeMax: String, credentials: ConnectorCredentials) async throws -> String {
        let encodedCal = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let (data, _) = try await GoogleAPIClient.get(
            path: "/calendar/v3/calendars/\(encodedCal)/events",
            queryItems: [
                URLQueryItem(name: "timeMin", value: timeMin),
                URLQueryItem(name: "timeMax", value: timeMax),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "50"),
            ],
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        let events = json["items"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatCalendarEvents(events)
    }

    private func getEvent(calendarId: String, eventId: String, credentials: ConnectorCredentials) async throws -> String {
        let encodedCal = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let (data, _) = try await GoogleAPIClient.get(
            path: "/calendar/v3/calendars/\(encodedCal)/events/\(eventId)",
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        return ConnectorsKit.formatCalendarEvents([json])
    }

    // MARK: - Write Actions

    private func createEvent(calendarId: String, summary: String, startDateTime: String, endDateTime: String, location: String?, description: String?, credentials: ConnectorCredentials) async throws -> String {
        let encodedCal = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var event: [String: Any] = [
            "summary": summary,
            "start": ["dateTime": startDateTime],
            "end": ["dateTime": endDateTime],
        ]
        if let location, !location.isEmpty { event["location"] = location }
        if let description, !description.isEmpty { event["description"] = description }
        let jsonData = try JSONSerialization.data(withJSONObject: event)
        let (_, _) = try await GoogleAPIClient.post(
            path: "/calendar/v3/calendars/\(encodedCal)/events",
            body: jsonData,
            credentials: credentials
        )
        return "Event created: \(summary)"
    }

    private func updateEvent(calendarId: String, eventId: String, params: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let encodedCal = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var patch: [String: Any] = [:]
        if let summary = params["summary"] { patch["summary"] = summary }
        if let location = params["location"] { patch["location"] = location }
        if let description = params["description"] { patch["description"] = description }
        if let start = params["startDateTime"] { patch["start"] = ["dateTime": start] }
        if let end = params["endDateTime"] { patch["end"] = ["dateTime": end] }
        guard !patch.isEmpty else { return "No fields to update" }
        let jsonData = try JSONSerialization.data(withJSONObject: patch)
        let (_, _) = try await GoogleAPIClient.patch(
            path: "/calendar/v3/calendars/\(encodedCal)/events/\(eventId)",
            body: jsonData,
            credentials: credentials
        )
        return "Event updated: \(eventId)"
    }

    private func deleteEvent(calendarId: String, eventId: String, credentials: ConnectorCredentials) async throws -> String {
        let encodedCal = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let (_, _) = try await GoogleAPIClient.delete(
            path: "/calendar/v3/calendars/\(encodedCal)/events/\(eventId)",
            credentials: credentials
        )
        return "Event deleted: \(eventId)"
    }

    private func listCalendars(credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await GoogleAPIClient.get(
            path: "/calendar/v3/users/me/calendarList",
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        let calendars = json["items"] as? [[String: Any]] ?? []
        var lines: [String] = []
        for cal in calendars {
            let summary = cal["summary"] as? String ?? "(unnamed)"
            let id = cal["id"] as? String ?? ""
            let primary = cal["primary"] as? Bool ?? false
            lines.append("- \(summary)\(primary ? " (primary)" : "") [ID: \(id)]")
        }
        return lines.isEmpty ? "(no calendars)" : lines.joined(separator: "\n")
    }
}

// MARK: - Google Drive Provider

struct GoogleDriveProvider: ConnectorProvider {
    static let definitionId = "google.drive"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String
        switch action {
        case "search":
            guard let query = params["q"] else { throw ConnectorProviderError.missingParameter("q") }
            data = try await searchFiles(query: query, credentials: credentials)

        case "list_recent":
            let maxResults = params["maxResults"] ?? "10"
            data = try await listRecent(maxResults: maxResults, credentials: credentials)

        case "get_file_metadata":
            guard let fileId = params["fileId"] else { throw ConnectorProviderError.missingParameter("fileId") }
            data = try await getFileMetadata(fileId: fileId, credentials: credentials)

        // Write actions
        case "create_folder":
            guard let name = params["name"] else { throw ConnectorProviderError.missingParameter("name") }
            data = try await createFolder(name: name, parentId: params["parentId"], credentials: credentials)

        case "move_file":
            guard let fileId = params["fileId"] else { throw ConnectorProviderError.missingParameter("fileId") }
            guard let newParentId = params["newParentId"] else { throw ConnectorProviderError.missingParameter("newParentId") }
            data = try await moveFile(fileId: fileId, newParentId: newParentId, credentials: credentials)

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
        let (_, status) = try await GoogleAPIClient.get(
            path: "/drive/v3/about",
            queryItems: [URLQueryItem(name: "fields", value: "user")],
            credentials: credentials
        )
        return status == 200
    }

    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        guard credentials.isExpired, let refreshToken = credentials.refreshToken else { return nil }
        let config = ConnectorRegistry.definition(for: Self.definitionId)?.oauthConfig
            ?? googleOAuthConfig(scopes: ["https://www.googleapis.com/auth/drive.file"])
        return try await OAuthService.shared.refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    // MARK: - Write Actions

    private func createFolder(name: String, parentId: String?, credentials: ConnectorCredentials) async throws -> String {
        var body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
        ]
        if let parentId, !parentId.isEmpty { body["parents"] = [parentId] }
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await GoogleAPIClient.post(
            path: "/drive/v3/files",
            body: jsonData,
            credentials: credentials
        )
        return "Folder created: \(name)"
    }

    private func moveFile(fileId: String, newParentId: String, credentials: ConnectorCredentials) async throws -> String {
        // First get current parents
        let (metaData, _) = try await GoogleAPIClient.get(
            path: "/drive/v3/files/\(fileId)",
            queryItems: [URLQueryItem(name: "fields", value: "parents")],
            credentials: credentials
        )
        let metaJSON = try GoogleAPIClient.parseJSON(metaData)
        let currentParents = (metaJSON["parents"] as? [String])?.joined(separator: ",") ?? ""
        // Move by adding new parent and removing old
        let (_, _) = try await GoogleAPIClient.patch(
            path: "/drive/v3/files/\(fileId)?addParents=\(newParentId)&removeParents=\(currentParents)",
            body: Data("{}".utf8),
            credentials: credentials
        )
        return "File moved to folder \(newParentId)"
    }

    private func searchFiles(query: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await GoogleAPIClient.get(
            path: "/drive/v3/files",
            queryItems: [
                URLQueryItem(name: "q", value: "name contains '\(query)'"),
                URLQueryItem(name: "fields", value: "files(id,name,mimeType,modifiedTime)"),
                URLQueryItem(name: "pageSize", value: "20"),
            ],
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        let files = json["files"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatDriveFiles(files)
    }

    private func listRecent(maxResults: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await GoogleAPIClient.get(
            path: "/drive/v3/files",
            queryItems: [
                URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
                URLQueryItem(name: "fields", value: "files(id,name,mimeType,modifiedTime)"),
                URLQueryItem(name: "pageSize", value: maxResults),
            ],
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        let files = json["files"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatDriveFiles(files)
    }

    private func getFileMetadata(fileId: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await GoogleAPIClient.get(
            path: "/drive/v3/files/\(fileId)",
            queryItems: [URLQueryItem(name: "fields", value: "id,name,mimeType,modifiedTime,size,owners,webViewLink")],
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        var lines: [String] = []
        lines.append("Name: \(json["name"] as? String ?? "(unnamed)")")
        lines.append("Type: \(json["mimeType"] as? String ?? "unknown")")
        lines.append("Modified: \(json["modifiedTime"] as? String ?? "")")
        if let size = json["size"] as? String { lines.append("Size: \(size) bytes") }
        if let link = json["webViewLink"] as? String { lines.append("Link: \(link)") }
        lines.append("ID: \(json["id"] as? String ?? "")")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Google Sheets Provider

struct GoogleSheetsProvider: ConnectorProvider {
    static let definitionId = "google.sheets"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String
        switch action {
        case "read_range":
            guard let spreadsheetId = params["spreadsheetId"] else { throw ConnectorProviderError.missingParameter("spreadsheetId") }
            guard let range = params["range"] else { throw ConnectorProviderError.missingParameter("range") }
            data = try await readRange(spreadsheetId: spreadsheetId, range: range, credentials: credentials)

        case "list_sheets":
            guard let spreadsheetId = params["spreadsheetId"] else { throw ConnectorProviderError.missingParameter("spreadsheetId") }
            data = try await listSheets(spreadsheetId: spreadsheetId, credentials: credentials)

        // Write actions
        case "write_range":
            guard let spreadsheetId = params["spreadsheetId"] else { throw ConnectorProviderError.missingParameter("spreadsheetId") }
            guard let range = params["range"] else { throw ConnectorProviderError.missingParameter("range") }
            guard let values = params["values"] else { throw ConnectorProviderError.missingParameter("values") }
            data = try await writeRange(spreadsheetId: spreadsheetId, range: range, valuesJSON: values, credentials: credentials)

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
        // Sheets doesn't have a simple "me" endpoint; test via Drive about
        let (_, status) = try await GoogleAPIClient.get(
            path: "/drive/v3/about",
            queryItems: [URLQueryItem(name: "fields", value: "user")],
            credentials: credentials
        )
        return status == 200
    }

    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        guard credentials.isExpired, let refreshToken = credentials.refreshToken else { return nil }
        let config = ConnectorRegistry.definition(for: Self.definitionId)?.oauthConfig
            ?? googleOAuthConfig(scopes: ["https://www.googleapis.com/auth/spreadsheets"])
        return try await OAuthService.shared.refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    // MARK: - Write Actions

    private func writeRange(spreadsheetId: String, range: String, valuesJSON: String, credentials: ConnectorCredentials) async throws -> String {
        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        // values should be JSON array of arrays, e.g. [["A","B"],["C","D"]]
        guard let valuesData = valuesJSON.data(using: .utf8),
              let parsedValues = try JSONSerialization.jsonObject(with: valuesData) as? [[Any]] else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid values JSON — expected array of arrays")
        }
        let body: [String: Any] = ["values": parsedValues]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let (_, _) = try await GoogleAPIClient.put(
            path: "/v4/spreadsheets/\(spreadsheetId)/values/\(encodedRange)",
            baseURL: "https://sheets.googleapis.com",
            body: jsonData,
            queryItems: [URLQueryItem(name: "valueInputOption", value: "USER_ENTERED")],
            credentials: credentials
        )
        return "Values written to \(range)"
    }

    private func readRange(spreadsheetId: String, range: String, credentials: ConnectorCredentials) async throws -> String {
        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        let (data, _) = try await GoogleAPIClient.get(
            path: "/v4/spreadsheets/\(spreadsheetId)/values/\(encodedRange)",
            baseURL: "https://sheets.googleapis.com",
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        let values = json["values"] as? [[Any]] ?? []
        return ConnectorsKit.formatSheetsValues(values)
    }

    private func listSheets(spreadsheetId: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await GoogleAPIClient.get(
            path: "/v4/spreadsheets/\(spreadsheetId)",
            baseURL: "https://sheets.googleapis.com",
            queryItems: [URLQueryItem(name: "fields", value: "sheets.properties")],
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        let sheets = json["sheets"] as? [[String: Any]] ?? []
        var lines: [String] = []
        for sheet in sheets {
            let props = sheet["properties"] as? [String: Any] ?? [:]
            let title = props["title"] as? String ?? "(unnamed)"
            let sheetId = props["sheetId"] as? Int ?? 0
            let rowCount = (props["gridProperties"] as? [String: Any])?["rowCount"] as? Int ?? 0
            let colCount = (props["gridProperties"] as? [String: Any])?["columnCount"] as? Int ?? 0
            lines.append("- \(title) (ID: \(sheetId), \(rowCount) rows x \(colCount) cols)")
        }
        return lines.isEmpty ? "(no sheets)" : lines.joined(separator: "\n")
    }
}

// MARK: - Google Contacts Provider

struct GoogleContactsProvider: ConnectorProvider {
    static let definitionId = "google.contacts"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String
        switch action {
        case "search":
            guard let query = params["query"] else { throw ConnectorProviderError.missingParameter("query") }
            data = try await searchContacts(query: query, credentials: credentials)

        case "list_groups":
            data = try await listGroups(credentials: credentials)

        // Write actions
        case "create_contact":
            guard let givenName = params["givenName"] else { throw ConnectorProviderError.missingParameter("givenName") }
            data = try await createContact(givenName: givenName, familyName: params["familyName"], email: params["email"], phone: params["phone"], credentials: credentials)

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
        let (_, status) = try await GoogleAPIClient.get(
            path: "/v1/people/me",
            baseURL: "https://people.googleapis.com",
            queryItems: [URLQueryItem(name: "personFields", value: "names")],
            credentials: credentials
        )
        return status == 200
    }

    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        guard credentials.isExpired, let refreshToken = credentials.refreshToken else { return nil }
        let config = ConnectorRegistry.definition(for: Self.definitionId)?.oauthConfig
            ?? googleOAuthConfig(scopes: ["https://www.googleapis.com/auth/contacts"])
        return try await OAuthService.shared.refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    // MARK: - Write Actions

    private func createContact(givenName: String, familyName: String?, email: String?, phone: String?, credentials: ConnectorCredentials) async throws -> String {
        var person: [String: Any] = [
            "names": [["givenName": givenName, "familyName": familyName ?? ""]],
        ]
        if let email, !email.isEmpty {
            person["emailAddresses"] = [["value": email]]
        }
        if let phone, !phone.isEmpty {
            person["phoneNumbers"] = [["value": phone]]
        }
        let jsonData = try JSONSerialization.data(withJSONObject: person)
        let (_, _) = try await GoogleAPIClient.post(
            path: "/v1/people:createContact",
            baseURL: "https://people.googleapis.com",
            body: jsonData,
            credentials: credentials
        )
        return "Contact created: \(givenName) \(familyName ?? "")"
    }

    private func searchContacts(query: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await GoogleAPIClient.get(
            path: "/v1/people:searchContacts",
            baseURL: "https://people.googleapis.com",
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "readMask", value: "names,emailAddresses,phoneNumbers"),
                URLQueryItem(name: "pageSize", value: "20"),
            ],
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        let results = json["results"] as? [[String: Any]] ?? []
        let people = results.compactMap { $0["person"] as? [String: Any] }
        return ConnectorsKit.formatContacts(people)
    }

    private func listGroups(credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await GoogleAPIClient.get(
            path: "/v1/contactGroups",
            baseURL: "https://people.googleapis.com",
            queryItems: [URLQueryItem(name: "pageSize", value: "50")],
            credentials: credentials
        )
        let json = try GoogleAPIClient.parseJSON(data)
        let groups = json["contactGroups"] as? [[String: Any]] ?? []
        var lines: [String] = []
        for group in groups {
            let name = group["name"] as? String ?? "(unnamed)"
            let memberCount = group["memberCount"] as? Int ?? 0
            let groupType = group["groupType"] as? String ?? ""
            lines.append("- \(name) (\(memberCount) members)\(groupType == "SYSTEM_CONTACT_GROUP" ? " [system]" : "")")
        }
        return lines.isEmpty ? "(no groups)" : lines.joined(separator: "\n")
    }
}

// MARK: - Google OAuth Config Helper

/// Build a Google OAuth config with specific scopes.
func googleOAuthConfig(scopes: [String]) -> OAuthConfig {
    OAuthConfig(
        authUrl: "https://accounts.google.com/o/oauth2/v2/auth",
        tokenUrl: "https://oauth2.googleapis.com/token",
        scopes: scopes,
        redirectScheme: "mcclaw",
        usePKCE: true
    )
}
