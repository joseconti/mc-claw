import Foundation
import Logging
import McClawKit

// MARK: - REST API Client (shared helper for REST APIs with Bearer/PAT auth)

/// Generic HTTP client for REST APIs with configurable auth headers and error handling.
struct RESTAPIClient: Sendable {
    private static let logger = Logger(label: "ai.mcclaw.rest-api")

    /// Execute a GET request against a REST API endpoint.
    static func get(
        path: String,
        baseURL: String,
        queryItems: [URLQueryItem] = [],
        credentials: ConnectorCredentials,
        authHeaders: [String: String]
    ) async throws -> (Data, Int) {
        var components = URLComponents(string: baseURL + path)!
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }

        guard let url = components.url else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }

        var request = URLRequest(url: url)
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

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
            throw ConnectorProviderError.apiError(statusCode: 403, message: "Forbidden")
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw ConnectorProviderError.apiError(statusCode: statusCode, message: body)
        }
    }

    /// Execute a POST request with JSON body.
    static func post(
        path: String,
        baseURL: String,
        body: Data,
        credentials: ConnectorCredentials,
        authHeaders: [String: String],
        extraHeaders: [String: String] = [:]
    ) async throws -> (Data, Int) {
        guard let url = URL(string: baseURL + path) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

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
            throw ConnectorProviderError.apiError(statusCode: 403, message: "Forbidden")
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw ConnectorProviderError.apiError(statusCode: statusCode, message: body)
        }
    }

    /// Parse JSON response as dictionary.
    static func parseJSON(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid JSON response")
        }
        return json
    }

    /// Execute a PATCH request with JSON body.
    static func patch(
        path: String,
        baseURL: String,
        body: Data,
        credentials: ConnectorCredentials,
        authHeaders: [String: String]
    ) async throws -> (Data, Int) {
        guard let url = URL(string: baseURL + path) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

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
            throw ConnectorProviderError.apiError(statusCode: 403, message: "Forbidden")
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            let bodyStr = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw ConnectorProviderError.apiError(statusCode: statusCode, message: bodyStr)
        }
    }

    /// Execute a DELETE request.
    static func delete(
        path: String,
        baseURL: String,
        credentials: ConnectorCredentials,
        authHeaders: [String: String]
    ) async throws -> (Data, Int) {
        guard let url = URL(string: baseURL + path) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }

        let statusCode = httpResponse.statusCode
        switch statusCode {
        case 200...204:
            return (data, statusCode)
        case 401:
            throw ConnectorProviderError.authenticationFailed
        case 403:
            throw ConnectorProviderError.apiError(statusCode: 403, message: "Forbidden")
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            let bodyStr = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw ConnectorProviderError.apiError(statusCode: statusCode, message: bodyStr)
        }
    }

    /// Execute a PUT request with JSON body.
    static func put(
        path: String,
        baseURL: String,
        body: Data,
        credentials: ConnectorCredentials,
        authHeaders: [String: String]
    ) async throws -> (Data, Int) {
        guard let url = URL(string: baseURL + path) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

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
            throw ConnectorProviderError.apiError(statusCode: 403, message: "Forbidden")
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ConnectorProviderError.rateLimited(retryAfter: retryAfter)
        default:
            let bodyStr = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw ConnectorProviderError.apiError(statusCode: statusCode, message: bodyStr)
        }
    }

    /// Parse JSON response as array.
    static func parseJSONArray(_ data: Data) throws -> [[String: Any]] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid JSON array response")
        }
        return json
    }
}

// MARK: - Auth Header Helpers

/// Build auth headers for a token that can be either an OAuth access token or a PAT.
private func gitHubAuthHeaders(_ credentials: ConnectorCredentials) -> [String: String] {
    let token = credentials.accessToken ?? credentials.apiKey ?? ""
    return [
        "Authorization": "Bearer \(token)",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    ]
}

private func gitLabAuthHeaders(_ credentials: ConnectorCredentials) -> [String: String] {
    if let pat = credentials.apiKey, !pat.isEmpty {
        return ["PRIVATE-TOKEN": pat]
    }
    let token = credentials.accessToken ?? ""
    return ["Authorization": "Bearer \(token)"]
}

private func linearAuthHeaders(_ credentials: ConnectorCredentials) -> [String: String] {
    let token = credentials.accessToken ?? credentials.apiKey ?? ""
    return [
        "Authorization": "\(token)",
        "Content-Type": "application/json",
    ]
}

private func jiraAuthHeaders(_ credentials: ConnectorCredentials, domain: String) -> [String: String] {
    // Jira Cloud uses Basic auth: email:apiToken (base64 encoded)
    // The apiKey stores "email:token" already encoded, or we use accessToken for OAuth
    if let accessToken = credentials.accessToken, !accessToken.isEmpty {
        return [
            "Authorization": "Bearer \(accessToken)",
            "Accept": "application/json",
        ]
    }
    if let apiKey = credentials.apiKey, !apiKey.isEmpty {
        let encoded = Data(apiKey.utf8).base64EncodedString()
        return [
            "Authorization": "Basic \(encoded)",
            "Accept": "application/json",
        ]
    }
    return ["Accept": "application/json"]
}

private func notionAuthHeaders(_ credentials: ConnectorCredentials) -> [String: String] {
    let token = credentials.accessToken ?? credentials.apiKey ?? ""
    return [
        "Authorization": "Bearer \(token)",
        "Notion-Version": "2022-06-28",
        "Content-Type": "application/json",
    ]
}

// MARK: - GitHub Provider

struct GitHubProvider: ConnectorProvider {
    static let definitionId = "dev.github"
    private static let baseURL = "https://api.github.com"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let headers = gitHubAuthHeaders(credentials)
        let data: String

        switch action {
        case "list_issues":
            guard let repo = params["repo"] else { throw ConnectorProviderError.missingParameter("repo") }
            let state = params["state"] ?? "open"
            data = try await listIssues(repo: repo, state: state, headers: headers, credentials: credentials)

        case "list_prs":
            guard let repo = params["repo"] else { throw ConnectorProviderError.missingParameter("repo") }
            let state = params["state"] ?? "open"
            data = try await listPRs(repo: repo, state: state, headers: headers, credentials: credentials)

        case "list_repos":
            let sort = params["sort"] ?? "updated"
            data = try await listRepos(sort: sort, headers: headers, credentials: credentials)

        case "search_code":
            guard let query = params["query"] else { throw ConnectorProviderError.missingParameter("query") }
            data = try await searchCode(query: query, headers: headers, credentials: credentials)

        case "get_notifications":
            data = try await getNotifications(headers: headers, credentials: credentials)

        case "create_issue":
            guard let repo = params["repo"] else { throw ConnectorProviderError.missingParameter("repo") }
            guard let title = params["title"] else { throw ConnectorProviderError.missingParameter("title") }
            data = try await createIssue(repo: repo, title: title, body: params["body"], labels: params["labels"], headers: headers, credentials: credentials)

        case "create_comment":
            guard let repo = params["repo"] else { throw ConnectorProviderError.missingParameter("repo") }
            guard let issueNumber = params["issueNumber"] else { throw ConnectorProviderError.missingParameter("issueNumber") }
            guard let body = params["body"] else { throw ConnectorProviderError.missingParameter("body") }
            data = try await createComment(repo: repo, issueNumber: issueNumber, body: body, headers: headers, credentials: credentials)

        case "create_pr":
            guard let repo = params["repo"] else { throw ConnectorProviderError.missingParameter("repo") }
            guard let title = params["title"] else { throw ConnectorProviderError.missingParameter("title") }
            guard let head = params["head"] else { throw ConnectorProviderError.missingParameter("head") }
            guard let base = params["base"] else { throw ConnectorProviderError.missingParameter("base") }
            data = try await createPR(repo: repo, title: title, head: head, base: base, body: params["body"], draft: params["draft"], headers: headers, credentials: credentials)

        case "merge_pr":
            guard let repo = params["repo"] else { throw ConnectorProviderError.missingParameter("repo") }
            guard let pullNumber = params["pullNumber"] else { throw ConnectorProviderError.missingParameter("pullNumber") }
            let mergeMethod = params["mergeMethod"] ?? "merge"
            data = try await mergePR(repo: repo, pullNumber: pullNumber, mergeMethod: mergeMethod, headers: headers, credentials: credentials)

        case "close_issue":
            guard let repo = params["repo"] else { throw ConnectorProviderError.missingParameter("repo") }
            guard let issueNumber = params["issueNumber"] else { throw ConnectorProviderError.missingParameter("issueNumber") }
            data = try await closeIssue(repo: repo, issueNumber: issueNumber, headers: headers, credentials: credentials)

        case "add_labels":
            guard let repo = params["repo"] else { throw ConnectorProviderError.missingParameter("repo") }
            guard let issueNumber = params["issueNumber"] else { throw ConnectorProviderError.missingParameter("issueNumber") }
            guard let labels = params["labels"] else { throw ConnectorProviderError.missingParameter("labels") }
            data = try await addLabels(repo: repo, issueNumber: issueNumber, labels: labels, headers: headers, credentials: credentials)

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
        let headers = gitHubAuthHeaders(credentials)
        let (_, status) = try await RESTAPIClient.get(
            path: "/user",
            baseURL: Self.baseURL,
            credentials: credentials,
            authHeaders: headers
        )
        return status == 200
    }

    // MARK: - API Calls

    private func listIssues(repo: String, state: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/repos/\(repo)/issues",
            baseURL: Self.baseURL,
            queryItems: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "per_page", value: "20"),
            ],
            credentials: credentials,
            authHeaders: headers
        )
        let items = try RESTAPIClient.parseJSONArray(data)
        return ConnectorsKit.formatGitHubIssues(items)
    }

    private func listPRs(repo: String, state: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/repos/\(repo)/pulls",
            baseURL: Self.baseURL,
            queryItems: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "per_page", value: "20"),
            ],
            credentials: credentials,
            authHeaders: headers
        )
        let items = try RESTAPIClient.parseJSONArray(data)
        return ConnectorsKit.formatGitHubPRs(items)
    }

    private func listRepos(sort: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/user/repos",
            baseURL: Self.baseURL,
            queryItems: [
                URLQueryItem(name: "sort", value: sort),
                URLQueryItem(name: "per_page", value: "20"),
            ],
            credentials: credentials,
            authHeaders: headers
        )
        let items = try RESTAPIClient.parseJSONArray(data)
        return ConnectorsKit.formatGitHubRepos(items)
    }

    private func searchCode(query: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/search/code",
            baseURL: Self.baseURL,
            queryItems: [URLQueryItem(name: "q", value: query)],
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let items = json["items"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatGitHubCodeSearch(items)
    }

    private func createIssue(repo: String, title: String, body: String?, labels: String?, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        var bodyDict: [String: Any] = ["title": title]
        if let body { bodyDict["body"] = body }
        if let labels {
            bodyDict["labels"] = labels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.post(
            path: "/repos/\(repo)/issues",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let number = json["number"] as? Int ?? 0
        let issueTitle = json["title"] as? String ?? title
        return "Issue created: #\(number) \(issueTitle)"
    }

    private func createComment(repo: String, issueNumber: String, body: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = ["body": body]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (_, _) = try await RESTAPIClient.post(
            path: "/repos/\(repo)/issues/\(issueNumber)/comments",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        return "Comment added to #\(issueNumber)"
    }

    private func getNotifications(headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/notifications",
            baseURL: Self.baseURL,
            queryItems: [URLQueryItem(name: "per_page", value: "20")],
            credentials: credentials,
            authHeaders: headers
        )
        let items = try RESTAPIClient.parseJSONArray(data)
        return ConnectorsKit.formatGitHubNotifications(items)
    }

    private func createPR(repo: String, title: String, head: String, base: String, body: String?, draft: String?, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        var bodyDict: [String: Any] = ["title": title, "head": head, "base": base]
        if let body { bodyDict["body"] = body }
        if let draft, draft.lowercased() == "true" { bodyDict["draft"] = true }
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.post(
            path: "/repos/\(repo)/pulls",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let number = json["number"] as? Int ?? 0
        let htmlUrl = json["html_url"] as? String ?? ""
        return "PR created: #\(number) \(title)\n\(htmlUrl)"
    }

    private func mergePR(repo: String, pullNumber: String, mergeMethod: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = ["merge_method": mergeMethod]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.put(
            path: "/repos/\(repo)/pulls/\(pullNumber)/merge",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let merged = json["merged"] as? Bool ?? false
        return merged ? "PR #\(pullNumber) merged successfully" : "Failed to merge PR #\(pullNumber)"
    }

    private func closeIssue(repo: String, issueNumber: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = ["state": "closed"]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (_, _) = try await RESTAPIClient.patch(
            path: "/repos/\(repo)/issues/\(issueNumber)",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        return "Issue #\(issueNumber) closed"
    }

    private func addLabels(repo: String, issueNumber: String, labels: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let labelArray = labels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let bodyDict: [String: Any] = ["labels": labelArray]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (_, _) = try await RESTAPIClient.post(
            path: "/repos/\(repo)/issues/\(issueNumber)/labels",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        return "Labels added to #\(issueNumber): \(labels)"
    }
}

// MARK: - GitLab Provider

struct GitLabProvider: ConnectorProvider {
    static let definitionId = "dev.gitlab"
    private static let defaultBaseURL = "https://gitlab.com/api/v4"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let headers = gitLabAuthHeaders(credentials)
        let data: String

        switch action {
        case "list_issues":
            guard let projectId = params["projectId"] else { throw ConnectorProviderError.missingParameter("projectId") }
            let state = params["state"] ?? "opened"
            data = try await listIssues(projectId: projectId, state: state, headers: headers, credentials: credentials)

        case "list_mrs":
            guard let projectId = params["projectId"] else { throw ConnectorProviderError.missingParameter("projectId") }
            let state = params["state"] ?? "opened"
            data = try await listMRs(projectId: projectId, state: state, headers: headers, credentials: credentials)

        case "list_projects":
            data = try await listProjects(headers: headers, credentials: credentials)

        case "create_issue":
            guard let projectId = params["projectId"] else { throw ConnectorProviderError.missingParameter("projectId") }
            guard let title = params["title"] else { throw ConnectorProviderError.missingParameter("title") }
            data = try await createIssue(projectId: projectId, title: title, description: params["description"], headers: headers, credentials: credentials)

        case "create_comment":
            guard let projectId = params["projectId"] else { throw ConnectorProviderError.missingParameter("projectId") }
            guard let issueIid = params["issueIid"] else { throw ConnectorProviderError.missingParameter("issueIid") }
            guard let body = params["body"] else { throw ConnectorProviderError.missingParameter("body") }
            data = try await createComment(projectId: projectId, issueIid: issueIid, body: body, headers: headers, credentials: credentials)

        case "create_mr":
            guard let projectId = params["projectId"] else { throw ConnectorProviderError.missingParameter("projectId") }
            guard let title = params["title"] else { throw ConnectorProviderError.missingParameter("title") }
            guard let sourceBranch = params["sourceBranch"] else { throw ConnectorProviderError.missingParameter("sourceBranch") }
            guard let targetBranch = params["targetBranch"] else { throw ConnectorProviderError.missingParameter("targetBranch") }
            data = try await createMR(projectId: projectId, title: title, sourceBranch: sourceBranch, targetBranch: targetBranch, description: params["description"], headers: headers, credentials: credentials)

        case "merge_mr":
            guard let projectId = params["projectId"] else { throw ConnectorProviderError.missingParameter("projectId") }
            guard let mrIid = params["mrIid"] else { throw ConnectorProviderError.missingParameter("mrIid") }
            data = try await mergeMR(projectId: projectId, mrIid: mrIid, headers: headers, credentials: credentials)

        case "close_issue":
            guard let projectId = params["projectId"] else { throw ConnectorProviderError.missingParameter("projectId") }
            guard let issueIid = params["issueIid"] else { throw ConnectorProviderError.missingParameter("issueIid") }
            data = try await closeIssue(projectId: projectId, issueIid: issueIid, headers: headers, credentials: credentials)

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
        let headers = gitLabAuthHeaders(credentials)
        let (_, status) = try await RESTAPIClient.get(
            path: "/user",
            baseURL: Self.defaultBaseURL,
            credentials: credentials,
            authHeaders: headers
        )
        return status == 200
    }

    private func listIssues(projectId: String, state: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let encoded = projectId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectId
        let (data, _) = try await RESTAPIClient.get(
            path: "/projects/\(encoded)/issues",
            baseURL: Self.defaultBaseURL,
            queryItems: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "per_page", value: "20"),
            ],
            credentials: credentials,
            authHeaders: headers
        )
        let items = try RESTAPIClient.parseJSONArray(data)
        return ConnectorsKit.formatGitLabIssues(items)
    }

    private func listMRs(projectId: String, state: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let encoded = projectId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectId
        let (data, _) = try await RESTAPIClient.get(
            path: "/projects/\(encoded)/merge_requests",
            baseURL: Self.defaultBaseURL,
            queryItems: [
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "per_page", value: "20"),
            ],
            credentials: credentials,
            authHeaders: headers
        )
        let items = try RESTAPIClient.parseJSONArray(data)
        return ConnectorsKit.formatGitLabMRs(items)
    }

    private func createIssue(projectId: String, title: String, description: String?, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let encoded = projectId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectId
        var bodyDict: [String: Any] = ["title": title]
        if let description { bodyDict["description"] = description }
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.post(
            path: "/projects/\(encoded)/issues",
            baseURL: Self.defaultBaseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let iid = json["iid"] as? Int ?? 0
        let issueTitle = json["title"] as? String ?? title
        return "Issue created: #\(iid) \(issueTitle)"
    }

    private func createComment(projectId: String, issueIid: String, body: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let encoded = projectId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectId
        let bodyDict: [String: Any] = ["body": body]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (_, _) = try await RESTAPIClient.post(
            path: "/projects/\(encoded)/issues/\(issueIid)/notes",
            baseURL: Self.defaultBaseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        return "Comment added to #\(issueIid)"
    }

    private func listProjects(headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/projects",
            baseURL: Self.defaultBaseURL,
            queryItems: [
                URLQueryItem(name: "membership", value: "true"),
                URLQueryItem(name: "per_page", value: "20"),
                URLQueryItem(name: "order_by", value: "last_activity_at"),
            ],
            credentials: credentials,
            authHeaders: headers
        )
        let items = try RESTAPIClient.parseJSONArray(data)
        return ConnectorsKit.formatGitLabProjects(items)
    }

    private func createMR(projectId: String, title: String, sourceBranch: String, targetBranch: String, description: String?, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let encoded = projectId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectId
        var bodyDict: [String: Any] = [
            "title": title,
            "source_branch": sourceBranch,
            "target_branch": targetBranch,
        ]
        if let description { bodyDict["description"] = description }
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.post(
            path: "/projects/\(encoded)/merge_requests",
            baseURL: Self.defaultBaseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let iid = json["iid"] as? Int ?? 0
        let webUrl = json["web_url"] as? String ?? ""
        return "MR created: !\(iid) \(title)\n\(webUrl)"
    }

    private func mergeMR(projectId: String, mrIid: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let encoded = projectId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectId
        let (data, _) = try await RESTAPIClient.put(
            path: "/projects/\(encoded)/merge_requests/\(mrIid)/merge",
            baseURL: Self.defaultBaseURL,
            body: Data("{}".utf8),
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let state = json["state"] as? String ?? ""
        return state == "merged" ? "MR !\(mrIid) merged successfully" : "MR !\(mrIid) state: \(state)"
    }

    private func closeIssue(projectId: String, issueIid: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let encoded = projectId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectId
        let bodyDict: [String: Any] = ["state_event": "close"]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (_, _) = try await RESTAPIClient.put(
            path: "/projects/\(encoded)/issues/\(issueIid)",
            baseURL: Self.defaultBaseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        return "Issue #\(issueIid) closed"
    }
}

// MARK: - Linear Provider

struct LinearProvider: ConnectorProvider {
    static let definitionId = "dev.linear"
    private static let baseURL = "https://api.linear.app"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let headers = linearAuthHeaders(credentials)
        let data: String

        switch action {
        case "list_issues":
            let teamId = params["teamId"]
            let state = params["state"]
            data = try await listIssues(teamId: teamId, state: state, headers: headers, credentials: credentials)

        case "list_projects":
            data = try await listProjects(headers: headers, credentials: credentials)

        case "my_assigned":
            data = try await myAssigned(headers: headers, credentials: credentials)

        case "create_issue":
            guard let teamId = params["teamId"] else { throw ConnectorProviderError.missingParameter("teamId") }
            guard let title = params["title"] else { throw ConnectorProviderError.missingParameter("title") }
            data = try await createIssue(teamId: teamId, title: title, description: params["description"], priority: params["priority"], headers: headers, credentials: credentials)

        case "update_issue":
            guard let issueId = params["issueId"] else { throw ConnectorProviderError.missingParameter("issueId") }
            data = try await updateIssue(issueId: issueId, title: params["title"], description: params["description"], stateId: params["stateId"], priority: params["priority"], headers: headers, credentials: credentials)

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
        let headers = linearAuthHeaders(credentials)
        let query = """
        { "query": "{ viewer { id name } }" }
        """
        let (responseData, status) = try await RESTAPIClient.post(
            path: "/graphql",
            baseURL: Self.baseURL,
            body: Data(query.utf8),
            credentials: credentials,
            authHeaders: headers
        )
        guard status == 200 else { return false }
        // GraphQL returns 200 even for auth errors — check for errors array
        if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            return false
        }
        return true
    }

    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        guard credentials.isExpired, let refreshToken = credentials.refreshToken else { return nil }
        let config = ConnectorRegistry.definition(for: Self.definitionId)?.oauthConfig
            ?? OAuthConfig(
                authUrl: "https://linear.app/oauth/authorize",
                tokenUrl: "https://api.linear.app/oauth/token",
                scopes: ["read"]
            )
        return try await OAuthService.shared.refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    // MARK: - GraphQL Queries

    private func listIssues(teamId: String?, state: String?, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        var filter = ""
        var filterParts: [String] = []
        if let teamId { filterParts.append("team: { id: { eq: \"\(teamId)\" } }") }
        if let state { filterParts.append("state: { name: { eqIgnoreCase: \"\(state)\" } }") }
        if !filterParts.isEmpty { filter = "(filter: { \(filterParts.joined(separator: ", ")) })" }

        let query = """
        { "query": "{ issues\(filter) { nodes { id identifier title state { name } priority assignee { name } createdAt } } }" }
        """
        let (data, _) = try await RESTAPIClient.post(
            path: "/graphql",
            baseURL: Self.baseURL,
            body: Data(query.utf8),
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let dataObj = json["data"] as? [String: Any] ?? [:]
        let issues = dataObj["issues"] as? [String: Any] ?? [:]
        let nodes = issues["nodes"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatLinearIssues(nodes)
    }

    private func listProjects(headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let query = """
        { "query": "{ projects { nodes { id name state startDate targetDate lead { name } } } }" }
        """
        let (data, _) = try await RESTAPIClient.post(
            path: "/graphql",
            baseURL: Self.baseURL,
            body: Data(query.utf8),
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let dataObj = json["data"] as? [String: Any] ?? [:]
        let projects = dataObj["projects"] as? [String: Any] ?? [:]
        let nodes = projects["nodes"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatLinearProjects(nodes)
    }

    private func createIssue(teamId: String, title: String, description: String?, priority: String?, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        var inputParts = ["teamId: \"\(teamId)\"", "title: \"\(title)\""]
        if let description { inputParts.append("description: \"\(description)\"") }
        if let priority, let priorityInt = Int(priority) { inputParts.append("priority: \(priorityInt)") }
        let input = inputParts.joined(separator: ", ")
        let query = """
        { "query": "mutation { issueCreate(input: { \(input) }) { success issue { id identifier title } } }" }
        """
        let (data, _) = try await RESTAPIClient.post(
            path: "/graphql",
            baseURL: Self.baseURL,
            body: Data(query.utf8),
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let dataObj = json["data"] as? [String: Any] ?? [:]
        let issueCreate = dataObj["issueCreate"] as? [String: Any] ?? [:]
        let issue = issueCreate["issue"] as? [String: Any] ?? [:]
        let identifier = issue["identifier"] as? String ?? ""
        let issueTitle = issue["title"] as? String ?? title
        return "Issue created: \(identifier) \(issueTitle)"
    }

    private func updateIssue(issueId: String, title: String?, description: String?, stateId: String?, priority: String?, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        var inputParts: [String] = []
        if let title { inputParts.append("title: \"\(title)\"") }
        if let description { inputParts.append("description: \"\(description)\"") }
        if let stateId { inputParts.append("stateId: \"\(stateId)\"") }
        if let priority, let priorityInt = Int(priority) { inputParts.append("priority: \(priorityInt)") }
        let input = inputParts.joined(separator: ", ")
        let query = """
        { "query": "mutation { issueUpdate(id: \\"\(issueId)\\", input: { \(input) }) { success issue { id identifier title } } }" }
        """
        let (data, _) = try await RESTAPIClient.post(
            path: "/graphql",
            baseURL: Self.baseURL,
            body: Data(query.utf8),
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let dataObj = json["data"] as? [String: Any] ?? [:]
        let issueUpdate = dataObj["issueUpdate"] as? [String: Any] ?? [:]
        let issue = issueUpdate["issue"] as? [String: Any] ?? [:]
        let identifier = issue["identifier"] as? String ?? ""
        return "Issue updated: \(identifier)"
    }

    private func myAssigned(headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let query = """
        { "query": "{ viewer { assignedIssues { nodes { id identifier title state { name } priority createdAt } } } }" }
        """
        let (data, _) = try await RESTAPIClient.post(
            path: "/graphql",
            baseURL: Self.baseURL,
            body: Data(query.utf8),
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let dataObj = json["data"] as? [String: Any] ?? [:]
        let viewer = dataObj["viewer"] as? [String: Any] ?? [:]
        let assigned = viewer["assignedIssues"] as? [String: Any] ?? [:]
        let nodes = assigned["nodes"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatLinearIssues(nodes)
    }
}

// MARK: - Jira Provider

struct JiraProvider: ConnectorProvider {
    static let definitionId = "dev.jira"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let domain = params["domain"] ?? credentials.domain ?? ""
        guard !domain.isEmpty else {
            throw ConnectorProviderError.missingParameter("domain (set in connector config)")
        }
        let baseURL = "https://\(domain).atlassian.net/rest/api/3"
        let headers = jiraAuthHeaders(credentials, domain: domain)
        let data: String

        switch action {
        case "list_issues":
            guard let projectKey = params["projectKey"] else { throw ConnectorProviderError.missingParameter("projectKey") }
            data = try await searchJQL(jql: "project=\(projectKey) ORDER BY updated DESC", baseURL: baseURL, headers: headers, credentials: credentials)

        case "search_jql":
            guard let jql = params["jql"] else { throw ConnectorProviderError.missingParameter("jql") }
            data = try await searchJQL(jql: jql, baseURL: baseURL, headers: headers, credentials: credentials)

        case "my_assigned":
            data = try await searchJQL(jql: "assignee=currentUser() ORDER BY updated DESC", baseURL: baseURL, headers: headers, credentials: credentials)

        case "create_issue":
            guard let projectKey = params["projectKey"] else { throw ConnectorProviderError.missingParameter("projectKey") }
            guard let summary = params["summary"] else { throw ConnectorProviderError.missingParameter("summary") }
            let issueType = params["issueType"] ?? "Task"
            data = try await createIssue(projectKey: projectKey, summary: summary, issueType: issueType, description: params["description"], baseURL: baseURL, headers: headers, credentials: credentials)

        case "add_comment":
            guard let issueKey = params["issueKey"] else { throw ConnectorProviderError.missingParameter("issueKey") }
            guard let body = params["body"] else { throw ConnectorProviderError.missingParameter("body") }
            data = try await addComment(issueKey: issueKey, body: body, baseURL: baseURL, headers: headers, credentials: credentials)

        case "transition_issue":
            guard let issueKey = params["issueKey"] else { throw ConnectorProviderError.missingParameter("issueKey") }
            guard let transitionId = params["transitionId"] else { throw ConnectorProviderError.missingParameter("transitionId") }
            data = try await transitionIssue(issueKey: issueKey, transitionId: transitionId, baseURL: baseURL, headers: headers, credentials: credentials)

        case "assign_issue":
            guard let issueKey = params["issueKey"] else { throw ConnectorProviderError.missingParameter("issueKey") }
            guard let accountId = params["accountId"] else { throw ConnectorProviderError.missingParameter("accountId") }
            data = try await assignIssue(issueKey: issueKey, accountId: accountId, baseURL: baseURL, headers: headers, credentials: credentials)

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
        let domain = credentials.domain ?? ""
        guard !domain.isEmpty else { return false }
        let baseURL = "https://\(domain).atlassian.net/rest/api/3"
        let headers = jiraAuthHeaders(credentials, domain: domain)
        let (_, status) = try await RESTAPIClient.get(
            path: "/myself",
            baseURL: baseURL,
            credentials: credentials,
            authHeaders: headers
        )
        return status == 200
    }

    private func createIssue(projectKey: String, summary: String, issueType: String, description: String?, baseURL: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        var descriptionContent: [[String: Any]] = []
        if let description {
            descriptionContent = [["type": "paragraph", "content": [["type": "text", "text": description]]]]
        }
        var fields: [String: Any] = [
            "project": ["key": projectKey],
            "summary": summary,
            "issuetype": ["name": issueType],
        ]
        if !descriptionContent.isEmpty {
            fields["description"] = ["type": "doc", "version": 1, "content": descriptionContent]
        }
        let bodyDict: [String: Any] = ["fields": fields]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.post(
            path: "/issue",
            baseURL: baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let key = json["key"] as? String ?? ""
        return "Issue created: \(key)"
    }

    private func addComment(issueKey: String, body: String, baseURL: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = [
            "body": [
                "type": "doc",
                "version": 1,
                "content": [["type": "paragraph", "content": [["type": "text", "text": body]]]],
            ],
        ]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (_, _) = try await RESTAPIClient.post(
            path: "/issue/\(issueKey)/comment",
            baseURL: baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        return "Comment added to \(issueKey)"
    }

    private func transitionIssue(issueKey: String, transitionId: String, baseURL: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = ["transition": ["id": transitionId]]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (_, _) = try await RESTAPIClient.post(
            path: "/issue/\(issueKey)/transitions",
            baseURL: baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        return "Issue \(issueKey) transitioned (transition ID: \(transitionId))"
    }

    private func assignIssue(issueKey: String, accountId: String, baseURL: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = ["accountId": accountId]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (_, _) = try await RESTAPIClient.put(
            path: "/issue/\(issueKey)/assignee",
            baseURL: baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        return "Issue \(issueKey) assigned"
    }

    private func searchJQL(jql: String, baseURL: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await RESTAPIClient.get(
            path: "/search",
            baseURL: baseURL,
            queryItems: [
                URLQueryItem(name: "jql", value: jql),
                URLQueryItem(name: "maxResults", value: "20"),
                URLQueryItem(name: "fields", value: "summary,status,assignee,priority,issuetype,updated"),
            ],
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let issues = json["issues"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatJiraIssues(issues)
    }
}

// MARK: - Notion Provider

struct NotionProvider: ConnectorProvider {
    static let definitionId = "dev.notion"
    private static let baseURL = "https://api.notion.com"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let headers = notionAuthHeaders(credentials)
        let data: String

        switch action {
        case "search":
            guard let query = params["query"] else { throw ConnectorProviderError.missingParameter("query") }
            data = try await search(query: query, headers: headers, credentials: credentials)

        case "list_databases":
            data = try await listDatabases(headers: headers, credentials: credentials)

        case "query_database":
            guard let databaseId = params["databaseId"] else { throw ConnectorProviderError.missingParameter("databaseId") }
            data = try await queryDatabase(databaseId: databaseId, headers: headers, credentials: credentials)

        case "create_page":
            guard let parentId = params["parentId"] else { throw ConnectorProviderError.missingParameter("parentId") }
            guard let title = params["title"] else { throw ConnectorProviderError.missingParameter("title") }
            data = try await createPage(parentId: parentId, title: title, content: params["content"], headers: headers, credentials: credentials)

        case "append_block":
            guard let blockId = params["blockId"] else { throw ConnectorProviderError.missingParameter("blockId") }
            guard let content = params["content"] else { throw ConnectorProviderError.missingParameter("content") }
            data = try await appendBlock(blockId: blockId, content: content, headers: headers, credentials: credentials)

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
        let headers = notionAuthHeaders(credentials)
        let body = Data("{}".utf8)
        let (_, status) = try await RESTAPIClient.post(
            path: "/v1/search",
            baseURL: Self.baseURL,
            body: body,
            credentials: credentials,
            authHeaders: headers
        )
        return status == 200
    }

    private func search(query: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = ["query": query, "page_size": 20]
        let body = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.post(
            path: "/v1/search",
            baseURL: Self.baseURL,
            body: body,
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let results = json["results"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatNotionResults(results)
    }

    private func listDatabases(headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = [
            "filter": ["value": "database", "property": "object"],
            "page_size": 20,
        ]
        let body = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.post(
            path: "/v1/search",
            baseURL: Self.baseURL,
            body: body,
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let results = json["results"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatNotionDatabases(results)
    }

    private func createPage(parentId: String, title: String, content: String?, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        var bodyDict: [String: Any] = [
            "parent": ["page_id": parentId],
            "properties": ["title": [["text": ["content": title]]]],
        ]
        if let content {
            bodyDict["children"] = [
                [
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": ["rich_text": [["type": "text", "text": ["content": content]]]],
                ],
            ]
        }
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (_, _) = try await RESTAPIClient.post(
            path: "/v1/pages",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        return "Page created: \(title)"
    }

    private func appendBlock(blockId: String, content: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = [
            "children": [
                [
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": ["rich_text": [["type": "text", "text": ["content": content]]]],
                ],
            ],
        ]
        let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (_, _) = try await RESTAPIClient.patch(
            path: "/v1/blocks/\(blockId)/children",
            baseURL: Self.baseURL,
            body: jsonBody,
            credentials: credentials,
            authHeaders: headers
        )
        return "Block appended to \(blockId)"
    }

    private func queryDatabase(databaseId: String, headers: [String: String], credentials: ConnectorCredentials) async throws -> String {
        let bodyDict: [String: Any] = ["page_size": 20]
        let body = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, _) = try await RESTAPIClient.post(
            path: "/v1/databases/\(databaseId)/query",
            baseURL: Self.baseURL,
            body: body,
            credentials: credentials,
            authHeaders: headers
        )
        let json = try RESTAPIClient.parseJSON(data)
        let results = json["results"] as? [[String: Any]] ?? []
        return ConnectorsKit.formatNotionDatabaseRows(results)
    }
}

// MARK: - ConnectorCredentials Extension for Jira Domain

private extension ConnectorCredentials {
    /// Jira domain is stored in the apiKey field as "email:token@domain" or extracted from config.
    /// We use a convention: if apiKey contains "@", the part after @ is the domain.
    var domain: String? {
        guard let key = apiKey else { return nil }
        let parts = key.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return String(parts[1])
    }

    /// The actual auth credential (email:token) without the domain suffix.
    var jiraAuthPart: String? {
        guard let key = apiKey else { return nil }
        let parts = key.split(separator: "@", maxSplits: 1)
        return String(parts[0])
    }
}
