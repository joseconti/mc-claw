import Foundation
import Logging
import McClawKit

// MARK: - Todoist Provider

struct TodoistProvider: ConnectorProvider {
    static let definitionId = "prod.todoist"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String

        switch action {
        case "list_tasks":
            let projectId = params["projectId"]
            let filter = params["filter"]
            data = try await listTasks(projectId: projectId, filter: filter, credentials: credentials)

        case "list_projects":
            data = try await listProjects(credentials: credentials)

        case "get_task":
            guard let taskId = params["taskId"] else { throw ConnectorProviderError.missingParameter("taskId") }
            data = try await getTask(taskId: taskId, credentials: credentials)

        case "create_task":
            guard let content = params["content"] else { throw ConnectorProviderError.missingParameter("content") }
            data = try await createTask(content: content, projectId: params["projectId"], dueString: params["dueString"], priority: params["priority"], credentials: credentials)

        case "complete_task":
            guard let taskId = params["taskId"] else { throw ConnectorProviderError.missingParameter("taskId") }
            data = try await completeTask(taskId: taskId, credentials: credentials)

        case "delete_task":
            guard let taskId = params["taskId"] else { throw ConnectorProviderError.missingParameter("taskId") }
            data = try await deleteTask(taskId: taskId, credentials: credentials)

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
        let (_, status) = try await todoistGet(path: "/rest/v2/projects", queryItems: [URLQueryItem(name: "limit", value: "1")], credentials: credentials)
        return status == 200
    }

    // MARK: - API Calls

    private func listTasks(projectId: String?, filter: String?, credentials: ConnectorCredentials) async throws -> String {
        var queryItems: [URLQueryItem] = []
        if let projectId, !projectId.isEmpty {
            queryItems.append(URLQueryItem(name: "project_id", value: projectId))
        }
        if let filter, !filter.isEmpty {
            queryItems.append(URLQueryItem(name: "filter", value: filter))
        }
        let (data, _) = try await todoistGet(path: "/rest/v2/tasks", queryItems: queryItems, credentials: credentials)
        let tasks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return ConnectorsKit.formatTodoistTasks(tasks)
    }

    private func listProjects(credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await todoistGet(path: "/rest/v2/projects", credentials: credentials)
        let projects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return ConnectorsKit.formatTodoistProjects(projects)
    }

    private func getTask(taskId: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await todoistGet(path: "/rest/v2/tasks/\(taskId)", credentials: credentials)
        guard let task = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(task not found)"
        }
        return ConnectorsKit.formatTodoistTaskDetail(task)
    }

    private func createTask(content: String, projectId: String?, dueString: String?, priority: String?, credentials: ConnectorCredentials) async throws -> String {
        var body: [String: Any] = ["content": content]
        if let projectId, !projectId.isEmpty { body["project_id"] = projectId }
        if let dueString, !dueString.isEmpty { body["due_string"] = dueString }
        if let priority, let p = Int(priority) { body["priority"] = p }
        let _ = try await todoistPost(path: "/rest/v2/tasks", body: body, credentials: credentials)
        return "Task created: \(content)"
    }

    private func completeTask(taskId: String, credentials: ConnectorCredentials) async throws -> String {
        let _ = try await todoistPost(path: "/rest/v2/tasks/\(taskId)/close", body: nil, credentials: credentials)
        return "Task completed"
    }

    private func deleteTask(taskId: String, credentials: ConnectorCredentials) async throws -> String {
        let _ = try await todoistRequest(method: "DELETE", path: "/rest/v2/tasks/\(taskId)", body: nil, credentials: credentials)
        return "Task deleted"
    }

    private func todoistPost(path: String, body: [String: Any]?, credentials: ConnectorCredentials) async throws -> (Data, Int) {
        return try await todoistRequest(method: "POST", path: path, body: body, credentials: credentials)
    }

    private func todoistRequest(method: String, path: String, body: [String: Any]?, credentials: ConnectorCredentials) async throws -> (Data, Int) {
        guard let token = credentials.apiKey ?? credentials.accessToken, !token.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }
        guard let url = URL(string: "https://api.todoist.com" + path) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299: return (data, http.statusCode)
        case 401, 403: throw ConnectorProviderError.authenticationFailed
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            throw ConnectorProviderError.apiError(statusCode: http.statusCode, message: "Todoist API error")
        }
    }

    private func todoistGet(path: String, queryItems: [URLQueryItem] = [], credentials: ConnectorCredentials) async throws -> (Data, Int) {
        guard let token = credentials.apiKey ?? credentials.accessToken, !token.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }
        var components = URLComponents(string: "https://api.todoist.com" + path)!
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        guard let url = components.url else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299: return (data, http.statusCode)
        case 401, 403: throw ConnectorProviderError.authenticationFailed
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            throw ConnectorProviderError.apiError(statusCode: http.statusCode, message: "Todoist API error")
        }
    }
}

// MARK: - Trello Provider

struct TrelloProvider: ConnectorProvider {
    static let definitionId = "prod.trello"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String

        switch action {
        case "list_boards":
            data = try await listBoards(credentials: credentials)

        case "list_cards":
            guard let listId = params["listId"] else { throw ConnectorProviderError.missingParameter("listId") }
            data = try await listCards(listId: listId, credentials: credentials)

        case "list_lists":
            guard let boardId = params["boardId"] else { throw ConnectorProviderError.missingParameter("boardId") }
            data = try await listLists(boardId: boardId, credentials: credentials)

        case "create_card":
            guard let listId = params["listId"] else { throw ConnectorProviderError.missingParameter("listId") }
            guard let name = params["name"] else { throw ConnectorProviderError.missingParameter("name") }
            data = try await createCard(listId: listId, name: name, desc: params["desc"], credentials: credentials)

        case "move_card":
            guard let cardId = params["cardId"] else { throw ConnectorProviderError.missingParameter("cardId") }
            guard let listId = params["listId"] else { throw ConnectorProviderError.missingParameter("listId") }
            data = try await moveCard(cardId: cardId, listId: listId, credentials: credentials)

        case "archive_card":
            guard let cardId = params["cardId"] else { throw ConnectorProviderError.missingParameter("cardId") }
            data = try await archiveCard(cardId: cardId, credentials: credentials)

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
        let (_, status) = try await trelloGet(path: "/1/members/me", credentials: credentials)
        return status == 200
    }

    // MARK: - API Calls

    private func createCard(listId: String, name: String, desc: String?, credentials: ConnectorCredentials) async throws -> String {
        var queryItems = [
            URLQueryItem(name: "idList", value: listId),
            URLQueryItem(name: "name", value: name),
        ]
        if let desc, !desc.isEmpty {
            queryItems.append(URLQueryItem(name: "desc", value: desc))
        }
        let _ = try await trelloRequest(method: "POST", path: "/1/cards", queryItems: queryItems, credentials: credentials)
        return "Card created: \(name)"
    }

    private func moveCard(cardId: String, listId: String, credentials: ConnectorCredentials) async throws -> String {
        let queryItems = [URLQueryItem(name: "idList", value: listId)]
        let _ = try await trelloRequest(method: "PUT", path: "/1/cards/\(cardId)", queryItems: queryItems, credentials: credentials)
        return "Card moved"
    }

    private func archiveCard(cardId: String, credentials: ConnectorCredentials) async throws -> String {
        let queryItems = [URLQueryItem(name: "closed", value: "true")]
        let _ = try await trelloRequest(method: "PUT", path: "/1/cards/\(cardId)", queryItems: queryItems, credentials: credentials)
        return "Card archived"
    }

    private func listBoards(credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await trelloGet(path: "/1/members/me/boards", queryItems: [
            URLQueryItem(name: "fields", value: "id,name,desc,closed,url"),
        ], credentials: credentials)
        let boards = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return ConnectorsKit.formatTrelloBoards(boards)
    }

    private func listCards(listId: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await trelloGet(path: "/1/lists/\(listId)/cards", queryItems: [
            URLQueryItem(name: "fields", value: "id,name,desc,due,labels,closed,url"),
        ], credentials: credentials)
        let cards = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return ConnectorsKit.formatTrelloCards(cards)
    }

    private func listLists(boardId: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await trelloGet(path: "/1/boards/\(boardId)/lists", queryItems: [
            URLQueryItem(name: "fields", value: "id,name,closed"),
        ], credentials: credentials)
        let lists = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return ConnectorsKit.formatTrelloLists(lists)
    }

    /// Trello uses API Key + Token as query params (not headers).
    private func trelloGet(path: String, queryItems: [URLQueryItem] = [], credentials: ConnectorCredentials) async throws -> (Data, Int) {
        // Trello stores API key in apiKey, token in accessToken
        guard let apiKey = credentials.apiKey, !apiKey.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }
        guard let token = credentials.accessToken, !token.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }
        var components = URLComponents(string: "https://api.trello.com" + path)!
        var allItems = queryItems
        allItems.append(URLQueryItem(name: "key", value: apiKey))
        allItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = (components.queryItems ?? []) + allItems
        guard let url = components.url else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299: return (data, http.statusCode)
        case 401: throw ConnectorProviderError.authenticationFailed
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            throw ConnectorProviderError.apiError(statusCode: http.statusCode, message: "Trello API error")
        }
    }

    /// Trello write requests (POST/PUT/DELETE) using API Key + Token as query params.
    private func trelloRequest(method: String, path: String, queryItems: [URLQueryItem] = [], credentials: ConnectorCredentials) async throws -> (Data, Int) {
        guard let apiKey = credentials.apiKey, !apiKey.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }
        guard let token = credentials.accessToken, !token.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }
        var components = URLComponents(string: "https://api.trello.com" + path)!
        var allItems = queryItems
        allItems.append(URLQueryItem(name: "key", value: apiKey))
        allItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = (components.queryItems ?? []) + allItems
        guard let url = components.url else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299: return (data, http.statusCode)
        case 401: throw ConnectorProviderError.authenticationFailed
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            throw ConnectorProviderError.apiError(statusCode: http.statusCode, message: "Trello API error")
        }
    }
}

// MARK: - Airtable Provider

struct AirtableProvider: ConnectorProvider {
    static let definitionId = "prod.airtable"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String

        switch action {
        case "list_records":
            guard let baseId = params["baseId"] else { throw ConnectorProviderError.missingParameter("baseId") }
            guard let tableId = params["tableId"] else { throw ConnectorProviderError.missingParameter("tableId") }
            data = try await listRecords(baseId: baseId, tableId: tableId, credentials: credentials)

        case "list_bases":
            data = try await listBases(credentials: credentials)

        case "get_record":
            guard let baseId = params["baseId"] else { throw ConnectorProviderError.missingParameter("baseId") }
            guard let tableId = params["tableId"] else { throw ConnectorProviderError.missingParameter("tableId") }
            guard let recordId = params["recordId"] else { throw ConnectorProviderError.missingParameter("recordId") }
            data = try await getRecord(baseId: baseId, tableId: tableId, recordId: recordId, credentials: credentials)

        case "create_record":
            guard let baseId = params["baseId"] else { throw ConnectorProviderError.missingParameter("baseId") }
            guard let tableId = params["tableId"] else { throw ConnectorProviderError.missingParameter("tableId") }
            guard let fields = params["fields"] else { throw ConnectorProviderError.missingParameter("fields") }
            data = try await createRecord(baseId: baseId, tableId: tableId, fieldsJSON: fields, credentials: credentials)

        case "update_record":
            guard let baseId = params["baseId"] else { throw ConnectorProviderError.missingParameter("baseId") }
            guard let tableId = params["tableId"] else { throw ConnectorProviderError.missingParameter("tableId") }
            guard let recordId = params["recordId"] else { throw ConnectorProviderError.missingParameter("recordId") }
            guard let fields = params["fields"] else { throw ConnectorProviderError.missingParameter("fields") }
            data = try await updateRecord(baseId: baseId, tableId: tableId, recordId: recordId, fieldsJSON: fields, credentials: credentials)

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
        let (_, status) = try await airtableGet(path: "/v0/meta/bases", credentials: credentials)
        return status == 200
    }

    // MARK: - API Calls

    private func listRecords(baseId: String, tableId: String, credentials: ConnectorCredentials) async throws -> String {
        let encodedTable = tableId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tableId
        let (data, _) = try await airtableGet(path: "/v0/\(baseId)/\(encodedTable)", credentials: credentials)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(invalid response)"
        }
        let records = json["records"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatAirtableRecords(records)
    }

    private func listBases(credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await airtableGet(path: "/v0/meta/bases", credentials: credentials)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(invalid response)"
        }
        let bases = json["bases"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatAirtableBases(bases)
    }

    private func getRecord(baseId: String, tableId: String, recordId: String, credentials: ConnectorCredentials) async throws -> String {
        let encodedTable = tableId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tableId
        let (data, _) = try await airtableGet(path: "/v0/\(baseId)/\(encodedTable)/\(recordId)", credentials: credentials)
        guard let record = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(record not found)"
        }
        return ConnectorsKit.formatAirtableRecordDetail(record)
    }

    private func createRecord(baseId: String, tableId: String, fieldsJSON: String, credentials: ConnectorCredentials) async throws -> String {
        guard let fieldsData = fieldsJSON.data(using: .utf8),
              let fields = try JSONSerialization.jsonObject(with: fieldsData) as? [String: Any] else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid fields JSON")
        }
        let encodedTable = tableId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tableId
        let body: [String: Any] = ["fields": fields]
        let _ = try await airtableRequest(method: "POST", path: "/v0/\(baseId)/\(encodedTable)", body: body, credentials: credentials)
        return "Record created in \(tableId)"
    }

    private func updateRecord(baseId: String, tableId: String, recordId: String, fieldsJSON: String, credentials: ConnectorCredentials) async throws -> String {
        guard let fieldsData = fieldsJSON.data(using: .utf8),
              let fields = try JSONSerialization.jsonObject(with: fieldsData) as? [String: Any] else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid fields JSON")
        }
        let encodedTable = tableId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tableId
        let body: [String: Any] = ["fields": fields]
        let _ = try await airtableRequest(method: "PATCH", path: "/v0/\(baseId)/\(encodedTable)/\(recordId)", body: body, credentials: credentials)
        return "Record updated: \(recordId)"
    }

    private func airtableRequest(method: String, path: String, body: [String: Any], credentials: ConnectorCredentials) async throws -> (Data, Int) {
        guard let token = credentials.apiKey ?? credentials.accessToken, !token.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }
        guard let url = URL(string: "https://api.airtable.com" + path) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299: return (data, http.statusCode)
        case 401, 403: throw ConnectorProviderError.authenticationFailed
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            throw ConnectorProviderError.apiError(statusCode: http.statusCode, message: "Airtable API error")
        }
    }

    private func airtableGet(path: String, credentials: ConnectorCredentials) async throws -> (Data, Int) {
        guard let token = credentials.apiKey ?? credentials.accessToken, !token.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }
        guard let url = URL(string: "https://api.airtable.com" + path) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299: return (data, http.statusCode)
        case 401, 403: throw ConnectorProviderError.authenticationFailed
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            throw ConnectorProviderError.apiError(statusCode: http.statusCode, message: "Airtable API error")
        }
    }
}

// MARK: - Dropbox Provider

struct DropboxProvider: ConnectorProvider {
    static let definitionId = "prod.dropbox"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String

        switch action {
        case "list_files":
            let path = params["path"] ?? ""
            data = try await listFiles(path: path, credentials: credentials)

        case "search":
            guard let query = params["query"] else { throw ConnectorProviderError.missingParameter("query") }
            data = try await searchFiles(query: query, credentials: credentials)

        case "get_metadata":
            guard let path = params["path"] else { throw ConnectorProviderError.missingParameter("path") }
            data = try await getMetadata(path: path, credentials: credentials)

        case "create_folder":
            guard let path = params["path"] else { throw ConnectorProviderError.missingParameter("path") }
            data = try await createFolder(path: path, credentials: credentials)

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
        guard let token = credentials.accessToken, !token.isEmpty else { return false }
        let url = URL(string: "https://api.dropboxapi.com/2/users/get_current_account")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Dropbox requires empty body for this endpoint
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        guard credentials.isExpired, let refreshToken = credentials.refreshToken else { return nil }
        let config = ConnectorRegistry.definition(for: Self.definitionId)?.oauthConfig
            ?? dropboxOAuthConfig()
        return try await OAuthService.shared.refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    // MARK: - API Calls

    private func createFolder(path: String, credentials: ConnectorCredentials) async throws -> String {
        let body: [String: Any] = [
            "path": path,
            "autorename": true,
        ]
        let _ = try await dropboxPost(path: "/2/files/create_folder_v2", body: body, credentials: credentials)
        return "Folder created: \(path)"
    }

    private func listFiles(path: String, credentials: ConnectorCredentials) async throws -> String {
        let body: [String: Any] = [
            "path": path.isEmpty ? "" : path,
            "limit": 50,
            "include_non_downloadable_files": false,
        ]
        let (data, _) = try await dropboxPost(path: "/2/files/list_folder", body: body, credentials: credentials)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(invalid response)"
        }
        let entries = json["entries"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatDropboxEntries(entries)
    }

    private func searchFiles(query: String, credentials: ConnectorCredentials) async throws -> String {
        let body: [String: Any] = [
            "query": query,
            "options": ["max_results": 20],
        ]
        let (data, _) = try await dropboxPost(path: "/2/files/search_v2", body: body, credentials: credentials)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(invalid response)"
        }
        let matches = json["matches"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatDropboxSearchResults(matches)
    }

    private func getMetadata(path: String, credentials: ConnectorCredentials) async throws -> String {
        let body: [String: Any] = [
            "path": path,
            "include_media_info": true,
        ]
        let (data, _) = try await dropboxPost(path: "/2/files/get_metadata", body: body, credentials: credentials)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(not found)"
        }
        return ConnectorsKit.formatDropboxEntryDetail(json)
    }

    /// Dropbox API uses POST for most endpoints with JSON bodies.
    private func dropboxPost(path: String, body: [String: Any], credentials: ConnectorCredentials) async throws -> (Data, Int) {
        guard let token = credentials.accessToken, !token.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }
        guard let url = URL(string: "https://api.dropboxapi.com" + path) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299: return (data, http.statusCode)
        case 401: throw ConnectorProviderError.authenticationFailed
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            throw ConnectorProviderError.apiError(statusCode: http.statusCode, message: "Dropbox API error")
        }
    }
}

// MARK: - Dropbox OAuth Config

func dropboxOAuthConfig() -> OAuthConfig {
    OAuthConfig(
        authUrl: "https://www.dropbox.com/oauth2/authorize",
        tokenUrl: "https://api.dropboxapi.com/oauth2/token",
        scopes: ["files.metadata.read", "files.content.read"],
        redirectScheme: "mcclaw",
        usePKCE: true
    )
}
