import Foundation
import CryptoKit

/// Pure logic for the Connectors system. Testable without UI or Keychain dependencies.
public enum ConnectorsKit {

    // MARK: - @fetch Command Parsing

    /// A parsed @fetch command from an AI response.
    public struct FetchCommand: Equatable, Sendable {
        public let connector: String
        public let action: String
        public let params: [String: String]

        public init(connector: String, action: String, params: [String: String] = [:]) {
            self.connector = connector
            self.action = action
            self.params = params
        }
    }

    /// Parse a @fetch command string.
    /// Format: `@fetch(connector.action, param1=value1, param2=value2)`
    public static func parseFetchCommand(_ text: String) -> FetchCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Match @fetch(...)
        guard trimmed.hasPrefix("@fetch("), trimmed.hasSuffix(")") else { return nil }

        let inner = String(trimmed.dropFirst(7).dropLast(1))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !inner.isEmpty else { return nil }

        // Split by comma, first part is connector.action
        let parts = inner.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let connectorAction = parts[0]

        // Split connector.action
        let caParts = connectorAction.split(separator: ".", maxSplits: 1)
        guard caParts.count == 2 else { return nil }

        let connector = String(caParts[0])
        let action = String(caParts[1])

        // Parse params if present
        var params: [String: String] = [:]
        if parts.count > 1 {
            let paramString = parts[1]
            let paramPairs = paramString.split(separator: ",")
            for pair in paramPairs {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    params[key] = value
                }
            }
        }

        return FetchCommand(connector: connector, action: action, params: params)
    }

    /// Check if a text contains any @fetch commands.
    public static func containsFetchCommand(_ text: String) -> Bool {
        text.contains("@fetch(")
    }

    /// Extract all @fetch commands from a text.
    public static func extractFetchCommands(_ text: String) -> [FetchCommand] {
        var commands: [FetchCommand] = []
        let pattern = "@fetch\\([^)]+\\)"

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let matchText = String(text[range])
            if let cmd = parseFetchCommand(matchText) {
                commands.append(cmd)
            }
        }

        return commands
    }

    /// Remove @fetch commands from text, returning the clean response.
    public static func removeFetchCommands(_ text: String) -> String {
        let pattern = "@fetch\\([^)]+\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let cleaned = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Connectors Header

    /// Build the connectors header for prompt injection.
    /// - Parameter connectors: List of (name, [actions]) tuples for active connectors.
    /// - Returns: Formatted header string.
    public static func buildConnectorsHeader(
        connectors: [(name: String, actions: [String])]
    ) -> String? {
        guard !connectors.isEmpty else { return nil }

        var lines: [String] = ["[McClaw Connectors] Available data sources:"]

        for (name, actions) in connectors {
            let actionList = actions.joined(separator: ", ")
            lines.append("- \(name): \(actionList)")
        }

        lines.append("")
        lines.append("To request data, reply with: @fetch(connector.action, param=value)")
        lines.append("The user can also use: /fetch connector.action")

        return lines.joined(separator: "\n")
    }

    // MARK: - Result Formatting

    /// Truncate a result string to a maximum length with indicator.
    public static func formatActionResult(_ result: String, maxLength: Int = 4000) -> (text: String, truncated: Bool) {
        guard result.count > maxLength else {
            return (result, false)
        }

        let truncated = String(result.prefix(maxLength))
        return (truncated + "\n... [truncated, \(result.count - maxLength) chars omitted]", true)
    }

    /// Build an enriched prompt by combining original message with fetched data.
    public static func buildEnrichedPrompt(
        original: String,
        results: [(connector: String, action: String, data: String)]
    ) -> String {
        guard !results.isEmpty else { return original }

        var sections: [String] = []

        for result in results {
            sections.append("--- Data from \(result.connector).\(result.action) ---")
            sections.append(result.data)
        }

        sections.append("--- End of fetched data ---")
        sections.append("")
        sections.append(original)

        return sections.joined(separator: "\n")
    }

    // MARK: - AI Response @fetch Detection

    /// Detect all @fetch commands in an AI response.
    /// This is the main entry point for PromptEnrichmentService to find fetch requests in CLI output.
    public static func detectFetchInResponse(_ text: String) -> [FetchCommand] {
        extractFetchCommands(text)
    }

    /// Parse a /fetch command from user input.
    /// Format: `/fetch connector.action param1=value1 param2=value2`
    public static func parseSlashFetch(_ text: String) -> FetchCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/fetch ") else { return nil }

        let afterPrefix = String(trimmed.dropFirst(7))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !afterPrefix.isEmpty else { return nil }

        // Split by whitespace: first token is connector.action, rest are params
        let tokens = afterPrefix.split(separator: " ")
        guard !tokens.isEmpty else { return nil }

        let connectorAction = String(tokens[0])
        let caParts = connectorAction.split(separator: ".", maxSplits: 1)
        guard caParts.count == 2 else { return nil }

        let connector = String(caParts[0])
        let action = String(caParts[1])

        var params: [String: String] = [:]
        for token in tokens.dropFirst() {
            let kv = token.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[String(kv[0])] = String(kv[1])
            }
        }

        return FetchCommand(connector: connector, action: action, params: params)
    }

    /// Build a formatted message showing fetch results for display in chat.
    public static func buildFetchResultMessage(
        connector: String,
        action: String,
        data: String,
        truncated: Bool = false
    ) -> String {
        var lines: [String] = []
        lines.append("**Result from \(connector).\(action)**")
        lines.append("")
        lines.append(data)
        if truncated {
            lines.append("")
            lines.append("_(Result was truncated to fit context limits)_")
        }
        return lines.joined(separator: "\n")
    }

    /// Maximum number of @fetch rounds allowed per conversation turn (anti-loop).
    public static let maxFetchRoundsPerTurn = 3

    /// Default maximum result length per action.
    public static let defaultMaxResultLength = 4000

    // MARK: - Token Validation

    /// Check if a token expiry date is still valid (with 5 minute buffer).
    public static func isTokenValid(expiresAt: Date, now: Date = Date()) -> Bool {
        let buffer: TimeInterval = 5 * 60  // 5 minutes
        return now.addingTimeInterval(buffer) < expiresAt
    }

    // MARK: - OAuth URL Building

    /// Build an OAuth authorization URL.
    public static func buildOAuthURL(
        authUrl: String,
        clientId: String,
        redirectUri: String,
        scopes: [String],
        state: String,
        codeChallenge: String? = nil,
        codeChallengeMethod: String? = nil
    ) -> URL? {
        guard var components = URLComponents(string: authUrl) else { return nil }

        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        if let challenge = codeChallenge, let method = codeChallengeMethod {
            items.append(URLQueryItem(name: "code_challenge", value: challenge))
            items.append(URLQueryItem(name: "code_challenge_method", value: method))
        }

        components.queryItems = items
        return components.url
    }

    // MARK: - Sanitization

    /// Sanitize connector data to prevent prompt injection.
    /// Escapes any @fetch() patterns that might exist in external data.
    public static func sanitizeConnectorData(_ data: String) -> String {
        data.replacingOccurrences(of: "@fetch(", with: "@fetch\\(")
    }

    // MARK: - PKCE (Proof Key for Code Exchange)

    /// Generate a cryptographically random code verifier for PKCE (43-128 chars, RFC 7636).
    public static func generateCodeVerifier(length: Int = 64) -> String {
        let allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        let clampedLength = min(max(length, 43), 128)
        var bytes = [UInt8](repeating: 0, count: clampedLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, clampedLength, &bytes)
        return String(bytes.map { allowed[allowed.index(allowed.startIndex, offsetBy: Int($0) % allowed.count)] })
    }

    /// Compute the S256 code challenge from a code verifier (SHA256 + base64url, RFC 7636).
    public static func computeCodeChallenge(from verifier: String) -> String {
        import_sha256(Data(verifier.utf8))
    }

    /// SHA256 + base64url encoding (no padding). Internal helper.
    private static func import_sha256(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        let hashData = Data(hash)
        return hashData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Google API Response Parsing

    /// Parse a Google API error response to extract a user-friendly message.
    public static func parseGoogleAPIError(statusCode: Int, body: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return "HTTP \(statusCode)"
    }

    /// Format Gmail messages into a readable text summary.
    public static func formatGmailMessages(_ messages: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, msg) in messages.enumerated() {
            let headers = (msg["payload"] as? [String: Any])?["headers"] as? [[String: Any]] ?? []
            let subject = headers.first { ($0["name"] as? String) == "Subject" }?["value"] as? String ?? "(no subject)"
            let from = headers.first { ($0["name"] as? String) == "From" }?["value"] as? String ?? "unknown"
            let date = headers.first { ($0["name"] as? String) == "Date" }?["value"] as? String ?? ""
            let snippet = msg["snippet"] as? String ?? ""
            let id = msg["id"] as? String ?? ""
            lines.append("\(i + 1). From: \(from)")
            lines.append("   Subject: \(subject)")
            lines.append("   Date: \(date)")
            lines.append("   ID: \(id)")
            if !snippet.isEmpty {
                lines.append("   Preview: \(snippet)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Format Google Calendar events into a readable text summary.
    public static func formatCalendarEvents(_ events: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, event) in events.enumerated() {
            let summary = event["summary"] as? String ?? "(no title)"
            let startObj = event["start"] as? [String: Any]
            let start = startObj?["dateTime"] as? String ?? startObj?["date"] as? String ?? "unknown"
            let endObj = event["end"] as? [String: Any]
            let end = endObj?["dateTime"] as? String ?? endObj?["date"] as? String ?? ""
            let location = event["location"] as? String
            let id = event["id"] as? String ?? ""

            lines.append("\(i + 1). \(summary)")
            lines.append("   When: \(start)\(end.isEmpty ? "" : " → \(end)")")
            if let loc = location, !loc.isEmpty {
                lines.append("   Where: \(loc)")
            }
            lines.append("   ID: \(id)")
            lines.append("")
        }
        return lines.isEmpty ? "(no events)" : lines.joined(separator: "\n")
    }

    /// Format Google Drive files into a readable text summary.
    public static func formatDriveFiles(_ files: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, file) in files.enumerated() {
            let name = file["name"] as? String ?? "(unnamed)"
            let mimeType = file["mimeType"] as? String ?? ""
            let modifiedTime = file["modifiedTime"] as? String ?? ""
            let id = file["id"] as? String ?? ""
            lines.append("\(i + 1). \(name) [\(mimeType)]")
            lines.append("   Modified: \(modifiedTime)")
            lines.append("   ID: \(id)")
            lines.append("")
        }
        return lines.isEmpty ? "(no files)" : lines.joined(separator: "\n")
    }

    /// Format Google Sheets values (2D array) into a readable table.
    public static func formatSheetsValues(_ values: [[Any]]) -> String {
        guard !values.isEmpty else { return "(empty range)" }
        var lines: [String] = []
        for row in values {
            let cells = row.map { "\($0)" }
            lines.append(cells.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    /// Format Google Contacts (People API) into readable text.
    public static func formatContacts(_ connections: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, person) in connections.enumerated() {
            let names = person["names"] as? [[String: Any]] ?? []
            let displayName = names.first?["displayName"] as? String ?? "(unknown)"
            let emails = person["emailAddresses"] as? [[String: Any]] ?? []
            let email = emails.first?["value"] as? String ?? ""
            let phones = person["phoneNumbers"] as? [[String: Any]] ?? []
            let phone = phones.first?["value"] as? String ?? ""
            lines.append("\(i + 1). \(displayName)")
            if !email.isEmpty { lines.append("   Email: \(email)") }
            if !phone.isEmpty { lines.append("   Phone: \(phone)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no contacts)" : lines.joined(separator: "\n")
    }

    // MARK: - GitHub Response Formatting

    /// Format GitHub issues into readable text.
    public static func formatGitHubIssues(_ issues: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, issue) in issues.enumerated() {
            let number = issue["number"] as? Int ?? 0
            let title = issue["title"] as? String ?? "(no title)"
            let state = issue["state"] as? String ?? ""
            let user = (issue["user"] as? [String: Any])?["login"] as? String ?? ""
            let labels = (issue["labels"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ") ?? ""
            let updatedAt = issue["updated_at"] as? String ?? ""

            lines.append("\(i + 1). #\(number) \(title)")
            lines.append("   State: \(state) | Author: \(user)")
            if !labels.isEmpty { lines.append("   Labels: \(labels)") }
            if !updatedAt.isEmpty { lines.append("   Updated: \(updatedAt)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no issues)" : lines.joined(separator: "\n")
    }

    /// Format GitHub pull requests into readable text.
    public static func formatGitHubPRs(_ prs: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, pr) in prs.enumerated() {
            let number = pr["number"] as? Int ?? 0
            let title = pr["title"] as? String ?? "(no title)"
            let state = pr["state"] as? String ?? ""
            let user = (pr["user"] as? [String: Any])?["login"] as? String ?? ""
            let head = (pr["head"] as? [String: Any])?["ref"] as? String ?? ""
            let base = (pr["base"] as? [String: Any])?["ref"] as? String ?? ""
            let draft = pr["draft"] as? Bool ?? false

            lines.append("\(i + 1). #\(number) \(title)\(draft ? " [DRAFT]" : "")")
            lines.append("   State: \(state) | Author: \(user)")
            lines.append("   Branch: \(head) -> \(base)")
            lines.append("")
        }
        return lines.isEmpty ? "(no pull requests)" : lines.joined(separator: "\n")
    }

    /// Format GitHub repositories into readable text.
    public static func formatGitHubRepos(_ repos: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, repo) in repos.enumerated() {
            let fullName = repo["full_name"] as? String ?? "(unnamed)"
            let description = repo["description"] as? String ?? ""
            let language = repo["language"] as? String ?? ""
            let stars = repo["stargazers_count"] as? Int ?? 0
            let isPrivate = repo["private"] as? Bool ?? false
            let updatedAt = repo["updated_at"] as? String ?? ""

            lines.append("\(i + 1). \(fullName)\(isPrivate ? " [private]" : "")")
            if !description.isEmpty { lines.append("   \(description)") }
            var meta: [String] = []
            if !language.isEmpty { meta.append(language) }
            if stars > 0 { meta.append("\(stars) stars") }
            if !meta.isEmpty { lines.append("   \(meta.joined(separator: " | "))") }
            if !updatedAt.isEmpty { lines.append("   Updated: \(updatedAt)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no repositories)" : lines.joined(separator: "\n")
    }

    /// Format GitHub code search results into readable text.
    public static func formatGitHubCodeSearch(_ items: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, item) in items.enumerated() {
            let name = item["name"] as? String ?? "(unnamed)"
            let path = item["path"] as? String ?? ""
            let repo = (item["repository"] as? [String: Any])?["full_name"] as? String ?? ""

            lines.append("\(i + 1). \(name)")
            lines.append("   Path: \(repo)/\(path)")
            lines.append("")
        }
        return lines.isEmpty ? "(no results)" : lines.joined(separator: "\n")
    }

    /// Format GitHub notifications into readable text.
    public static func formatGitHubNotifications(_ notifications: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, notif) in notifications.enumerated() {
            let subject = notif["subject"] as? [String: Any] ?? [:]
            let title = subject["title"] as? String ?? "(no title)"
            let type = subject["type"] as? String ?? ""
            let repo = (notif["repository"] as? [String: Any])?["full_name"] as? String ?? ""
            let reason = notif["reason"] as? String ?? ""
            let unread = notif["unread"] as? Bool ?? false

            lines.append("\(i + 1). \(title)\(unread ? " [unread]" : "")")
            lines.append("   Type: \(type) | Repo: \(repo)")
            lines.append("   Reason: \(reason)")
            lines.append("")
        }
        return lines.isEmpty ? "(no notifications)" : lines.joined(separator: "\n")
    }

    // MARK: - GitLab Response Formatting

    /// Format GitLab issues into readable text.
    public static func formatGitLabIssues(_ issues: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, issue) in issues.enumerated() {
            let iid = issue["iid"] as? Int ?? 0
            let title = issue["title"] as? String ?? "(no title)"
            let state = issue["state"] as? String ?? ""
            let author = (issue["author"] as? [String: Any])?["username"] as? String ?? ""
            let labels = (issue["labels"] as? [String])?.joined(separator: ", ") ?? ""
            let updatedAt = issue["updated_at"] as? String ?? ""

            lines.append("\(i + 1). #\(iid) \(title)")
            lines.append("   State: \(state) | Author: \(author)")
            if !labels.isEmpty { lines.append("   Labels: \(labels)") }
            if !updatedAt.isEmpty { lines.append("   Updated: \(updatedAt)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no issues)" : lines.joined(separator: "\n")
    }

    /// Format GitLab merge requests into readable text.
    public static func formatGitLabMRs(_ mrs: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, mr) in mrs.enumerated() {
            let iid = mr["iid"] as? Int ?? 0
            let title = mr["title"] as? String ?? "(no title)"
            let state = mr["state"] as? String ?? ""
            let author = (mr["author"] as? [String: Any])?["username"] as? String ?? ""
            let sourceBranch = mr["source_branch"] as? String ?? ""
            let targetBranch = mr["target_branch"] as? String ?? ""
            let draft = mr["draft"] as? Bool ?? false

            lines.append("\(i + 1). !\(iid) \(title)\(draft ? " [DRAFT]" : "")")
            lines.append("   State: \(state) | Author: \(author)")
            lines.append("   Branch: \(sourceBranch) -> \(targetBranch)")
            lines.append("")
        }
        return lines.isEmpty ? "(no merge requests)" : lines.joined(separator: "\n")
    }

    /// Format GitLab projects into readable text.
    public static func formatGitLabProjects(_ projects: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, project) in projects.enumerated() {
            let name = project["path_with_namespace"] as? String ?? "(unnamed)"
            let description = project["description"] as? String ?? ""
            let stars = project["star_count"] as? Int ?? 0
            let visibility = project["visibility"] as? String ?? ""
            let lastActivity = project["last_activity_at"] as? String ?? ""

            lines.append("\(i + 1). \(name) [\(visibility)]")
            if !description.isEmpty { lines.append("   \(description)") }
            if stars > 0 { lines.append("   Stars: \(stars)") }
            if !lastActivity.isEmpty { lines.append("   Last activity: \(lastActivity)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no projects)" : lines.joined(separator: "\n")
    }

    // MARK: - Linear Response Formatting

    /// Format Linear issues (GraphQL nodes) into readable text.
    public static func formatLinearIssues(_ nodes: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, issue) in nodes.enumerated() {
            let identifier = issue["identifier"] as? String ?? ""
            let title = issue["title"] as? String ?? "(no title)"
            let stateName = (issue["state"] as? [String: Any])?["name"] as? String ?? ""
            let priority = issue["priority"] as? Int ?? 0
            let assignee = (issue["assignee"] as? [String: Any])?["name"] as? String ?? ""
            let createdAt = issue["createdAt"] as? String ?? ""

            let priorityLabel = linearPriorityLabel(priority)
            lines.append("\(i + 1). \(identifier) \(title)")
            lines.append("   State: \(stateName) | Priority: \(priorityLabel)")
            if !assignee.isEmpty { lines.append("   Assignee: \(assignee)") }
            if !createdAt.isEmpty { lines.append("   Created: \(createdAt)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no issues)" : lines.joined(separator: "\n")
    }

    /// Format Linear projects (GraphQL nodes) into readable text.
    public static func formatLinearProjects(_ nodes: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, project) in nodes.enumerated() {
            let name = project["name"] as? String ?? "(unnamed)"
            let state = project["state"] as? String ?? ""
            let startDate = project["startDate"] as? String ?? ""
            let targetDate = project["targetDate"] as? String ?? ""
            let lead = (project["lead"] as? [String: Any])?["name"] as? String ?? ""

            lines.append("\(i + 1). \(name)")
            if !state.isEmpty { lines.append("   State: \(state)") }
            if !startDate.isEmpty || !targetDate.isEmpty {
                lines.append("   Dates: \(startDate) -> \(targetDate)")
            }
            if !lead.isEmpty { lines.append("   Lead: \(lead)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no projects)" : lines.joined(separator: "\n")
    }

    /// Convert Linear priority number to label.
    private static func linearPriorityLabel(_ priority: Int) -> String {
        switch priority {
        case 0: "No priority"
        case 1: "Urgent"
        case 2: "High"
        case 3: "Medium"
        case 4: "Low"
        default: "P\(priority)"
        }
    }

    // MARK: - Jira Response Formatting

    /// Format Jira issues (search results) into readable text.
    public static func formatJiraIssues(_ issues: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, issue) in issues.enumerated() {
            let key = issue["key"] as? String ?? ""
            let fields = issue["fields"] as? [String: Any] ?? [:]
            let summary = fields["summary"] as? String ?? "(no summary)"
            let status = (fields["status"] as? [String: Any])?["name"] as? String ?? ""
            let priority = (fields["priority"] as? [String: Any])?["name"] as? String ?? ""
            let issueType = (fields["issuetype"] as? [String: Any])?["name"] as? String ?? ""
            let assignee = (fields["assignee"] as? [String: Any])?["displayName"] as? String ?? "Unassigned"
            let updatedAt = fields["updated"] as? String ?? ""

            lines.append("\(i + 1). \(key) \(summary)")
            lines.append("   Type: \(issueType) | Status: \(status) | Priority: \(priority)")
            lines.append("   Assignee: \(assignee)")
            if !updatedAt.isEmpty { lines.append("   Updated: \(updatedAt)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no issues)" : lines.joined(separator: "\n")
    }

    // MARK: - Notion Response Formatting

    /// Format Notion search results into readable text.
    public static func formatNotionResults(_ results: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, result) in results.enumerated() {
            let objectType = result["object"] as? String ?? ""
            let id = result["id"] as? String ?? ""
            let title = extractNotionTitle(from: result)
            let lastEdited = result["last_edited_time"] as? String ?? ""

            lines.append("\(i + 1). \(title) [\(objectType)]")
            lines.append("   ID: \(id)")
            if !lastEdited.isEmpty { lines.append("   Last edited: \(lastEdited)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no results)" : lines.joined(separator: "\n")
    }

    /// Format Notion databases from search results.
    public static func formatNotionDatabases(_ results: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, db) in results.enumerated() {
            let id = db["id"] as? String ?? ""
            let title = extractNotionTitle(from: db)
            let lastEdited = db["last_edited_time"] as? String ?? ""

            lines.append("\(i + 1). \(title)")
            lines.append("   ID: \(id)")
            if !lastEdited.isEmpty { lines.append("   Last edited: \(lastEdited)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no databases)" : lines.joined(separator: "\n")
    }

    /// Format Notion database query rows.
    public static func formatNotionDatabaseRows(_ results: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, row) in results.enumerated() {
            let id = row["id"] as? String ?? ""
            let title = extractNotionTitle(from: row)
            let properties = row["properties"] as? [String: Any] ?? [:]
            let lastEdited = row["last_edited_time"] as? String ?? ""

            lines.append("\(i + 1). \(title)")
            lines.append("   ID: \(id)")

            // Extract a few property values for context
            for (key, value) in properties.prefix(5) {
                if let propDict = value as? [String: Any],
                   let propType = propDict["type"] as? String {
                    let displayValue = extractNotionPropertyValue(propDict, type: propType)
                    if !displayValue.isEmpty {
                        lines.append("   \(key): \(displayValue)")
                    }
                }
            }

            if !lastEdited.isEmpty { lines.append("   Last edited: \(lastEdited)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no rows)" : lines.joined(separator: "\n")
    }

    /// Extract the title from a Notion object (page or database).
    private static func extractNotionTitle(from obj: [String: Any]) -> String {
        // Database title
        if let titleArray = obj["title"] as? [[String: Any]] {
            let parts = titleArray.compactMap { $0["plain_text"] as? String }
            if !parts.isEmpty { return parts.joined() }
        }

        // Page title from properties
        if let properties = obj["properties"] as? [String: Any] {
            for (_, value) in properties {
                if let propDict = value as? [String: Any],
                   propDict["type"] as? String == "title",
                   let titleArr = propDict["title"] as? [[String: Any]] {
                    let parts = titleArr.compactMap { $0["plain_text"] as? String }
                    if !parts.isEmpty { return parts.joined() }
                }
            }
        }

        return "(untitled)"
    }

    /// Extract a displayable value from a Notion property.
    private static func extractNotionPropertyValue(_ prop: [String: Any], type: String) -> String {
        switch type {
        case "title", "rich_text":
            let arr = prop[type] as? [[String: Any]] ?? []
            return arr.compactMap { $0["plain_text"] as? String }.joined()
        case "number":
            if let num = prop["number"] as? Double { return "\(num)" }
        case "select":
            return (prop["select"] as? [String: Any])?["name"] as? String ?? ""
        case "multi_select":
            let items = prop["multi_select"] as? [[String: Any]] ?? []
            return items.compactMap { $0["name"] as? String }.joined(separator: ", ")
        case "status":
            return (prop["status"] as? [String: Any])?["name"] as? String ?? ""
        case "checkbox":
            if let val = prop["checkbox"] as? Bool { return val ? "Yes" : "No" }
        case "date":
            if let dateObj = prop["date"] as? [String: Any] {
                return dateObj["start"] as? String ?? ""
            }
        default:
            break
        }
        return ""
    }

    // MARK: - Slack Response Formatting

    /// Format Slack channels into readable text.
    public static func formatSlackChannels(_ channels: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, channel) in channels.enumerated() {
            let name = channel["name"] as? String ?? "(unnamed)"
            let id = channel["id"] as? String ?? ""
            let isPrivate = channel["is_private"] as? Bool ?? false
            let memberCount = channel["num_members"] as? Int ?? 0
            let topic = (channel["topic"] as? [String: Any])?["value"] as? String ?? ""
            let purpose = (channel["purpose"] as? [String: Any])?["value"] as? String ?? ""

            lines.append("\(i + 1). #\(name)\(isPrivate ? " [private]" : "") (ID: \(id))")
            lines.append("   Members: \(memberCount)")
            if !topic.isEmpty { lines.append("   Topic: \(topic)") }
            if !purpose.isEmpty && purpose != topic { lines.append("   Purpose: \(purpose)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no channels)" : lines.joined(separator: "\n")
    }

    /// Format Slack messages into readable text.
    public static func formatSlackMessages(_ messages: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, msg) in messages.enumerated() {
            let text = msg["text"] as? String ?? ""
            let user = msg["user"] as? String ?? "unknown"
            let ts = msg["ts"] as? String ?? ""
            let subtype = msg["subtype"] as? String

            if let subtype {
                lines.append("\(i + 1). [\(subtype)] \(text)")
            } else {
                lines.append("\(i + 1). <\(user)> \(text)")
            }
            if !ts.isEmpty { lines.append("   Timestamp: \(ts)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no messages)" : lines.joined(separator: "\n")
    }

    /// Format Slack search results into readable text.
    public static func formatSlackSearchResults(_ matches: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, match) in matches.enumerated() {
            let text = match["text"] as? String ?? ""
            let user = match["username"] as? String ?? "unknown"
            let channel = (match["channel"] as? [String: Any])?["name"] as? String ?? ""
            let ts = match["ts"] as? String ?? ""
            let permalink = match["permalink"] as? String ?? ""

            lines.append("\(i + 1). <\(user)> in #\(channel): \(text)")
            if !ts.isEmpty { lines.append("   Timestamp: \(ts)") }
            if !permalink.isEmpty { lines.append("   Link: \(permalink)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no results)" : lines.joined(separator: "\n")
    }

    // MARK: - Discord Response Formatting

    /// Format Discord guilds (servers) into readable text.
    public static func formatDiscordGuilds(_ guilds: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, guild) in guilds.enumerated() {
            let name = guild["name"] as? String ?? "(unnamed)"
            let id = guild["id"] as? String ?? ""
            let owner = guild["owner"] as? Bool ?? false

            lines.append("\(i + 1). \(name)\(owner ? " [owner]" : "") (ID: \(id))")
            lines.append("")
        }
        return lines.isEmpty ? "(no servers)" : lines.joined(separator: "\n")
    }

    /// Format Discord channels into readable text.
    public static func formatDiscordChannels(_ channels: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, channel) in channels.enumerated() {
            let name = channel["name"] as? String ?? "(unnamed)"
            let id = channel["id"] as? String ?? ""
            let type = channel["type"] as? Int ?? 0
            let topic = channel["topic"] as? String ?? ""

            let typeName = discordChannelTypeName(type)
            lines.append("\(i + 1). \(typeName)\(name) (ID: \(id))")
            if !topic.isEmpty { lines.append("   Topic: \(topic)") }
            lines.append("")
        }
        return lines.isEmpty ? "(no channels)" : lines.joined(separator: "\n")
    }

    /// Format Discord messages into readable text.
    public static func formatDiscordMessages(_ messages: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, msg) in messages.enumerated() {
            let content = msg["content"] as? String ?? ""
            let author = (msg["author"] as? [String: Any])?["username"] as? String ?? "unknown"
            let timestamp = msg["timestamp"] as? String ?? ""
            let id = msg["id"] as? String ?? ""

            lines.append("\(i + 1). <\(author)> \(content)")
            if !timestamp.isEmpty { lines.append("   Time: \(timestamp)") }
            lines.append("   ID: \(id)")
            lines.append("")
        }
        return lines.isEmpty ? "(no messages)" : lines.joined(separator: "\n")
    }

    /// Map Discord channel type int to human-readable prefix.
    private static func discordChannelTypeName(_ type: Int) -> String {
        switch type {
        case 0: "#"      // GUILD_TEXT
        case 2: "voice:" // GUILD_VOICE
        case 4: ""       // GUILD_CATEGORY
        case 5: "news:"  // GUILD_ANNOUNCEMENT
        case 13: "stage:" // GUILD_STAGE_VOICE
        case 15: "forum:" // GUILD_FORUM
        default: ""
        }
    }

    // MARK: - Telegram Response Formatting

    /// Format Telegram updates into readable text.
    public static func formatTelegramUpdates(_ updates: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, update) in updates.enumerated() {
            let updateId = update["update_id"] as? Int ?? 0

            if let message = update["message"] as? [String: Any] {
                let text = message["text"] as? String ?? "(non-text message)"
                let from = (message["from"] as? [String: Any])?["first_name"] as? String ?? "unknown"
                let chatTitle = (message["chat"] as? [String: Any])?["title"] as? String
                    ?? (message["chat"] as? [String: Any])?["first_name"] as? String ?? ""
                let date = message["date"] as? Int ?? 0

                lines.append("\(i + 1). [update \(updateId)] <\(from)>\(chatTitle.isEmpty ? "" : " in \(chatTitle)"): \(text)")
                if date > 0 { lines.append("   Date: \(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(date))))") }
            } else if let callbackQuery = update["callback_query"] as? [String: Any] {
                let data = callbackQuery["data"] as? String ?? ""
                let from = (callbackQuery["from"] as? [String: Any])?["first_name"] as? String ?? "unknown"
                lines.append("\(i + 1). [update \(updateId)] Callback from \(from): \(data)")
            } else {
                lines.append("\(i + 1). [update \(updateId)] (other update type)")
            }
            lines.append("")
        }
        return lines.isEmpty ? "(no updates)" : lines.joined(separator: "\n")
    }

    /// Format Telegram bot info into readable text.
    public static func formatTelegramBotInfo(_ bot: [String: Any]) -> String {
        let id = bot["id"] as? Int ?? 0
        let firstName = bot["first_name"] as? String ?? ""
        let username = bot["username"] as? String ?? ""
        let canJoinGroups = bot["can_join_groups"] as? Bool ?? false
        let canReadAll = bot["can_read_all_group_messages"] as? Bool ?? false
        let supportsInline = bot["supports_inline_queries"] as? Bool ?? false

        var lines: [String] = []
        lines.append("Bot: \(firstName) (@\(username))")
        lines.append("ID: \(id)")
        lines.append("Can join groups: \(canJoinGroups ? "Yes" : "No")")
        lines.append("Can read all messages: \(canReadAll ? "Yes" : "No")")
        lines.append("Supports inline queries: \(supportsInline ? "Yes" : "No")")
        return lines.joined(separator: "\n")
    }

    // MARK: - Microsoft Graph Error Parsing

    /// Parse a Microsoft Graph API error response to extract a user-friendly message.
    public static func parseMicrosoftGraphError(statusCode: Int, body: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return "HTTP \(statusCode)"
    }

    // MARK: - Outlook Mail Response Formatting

    /// Format Outlook messages into readable text.
    public static func formatOutlookMessages(_ messages: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, msg) in messages.enumerated() {
            let subject = msg["subject"] as? String ?? "(no subject)"
            let fromObj = msg["from"] as? [String: Any]
            let emailAddress = fromObj?["emailAddress"] as? [String: Any]
            let fromName = emailAddress?["name"] as? String ?? ""
            let fromEmail = emailAddress?["address"] as? String ?? ""
            let from = fromName.isEmpty ? fromEmail : "\(fromName) <\(fromEmail)>"
            let receivedAt = msg["receivedDateTime"] as? String ?? ""
            let preview = msg["bodyPreview"] as? String ?? ""
            let isRead = msg["isRead"] as? Bool ?? true
            let id = msg["id"] as? String ?? ""

            lines.append("\(i + 1). \(subject)\(isRead ? "" : " [unread]")")
            lines.append("   From: \(from)")
            if !receivedAt.isEmpty { lines.append("   Date: \(receivedAt)") }
            if !preview.isEmpty {
                let trimmedPreview = preview.prefix(200)
                lines.append("   Preview: \(trimmedPreview)")
            }
            lines.append("   ID: \(id)")
            lines.append("")
        }
        return lines.isEmpty ? "(no messages)" : lines.joined(separator: "\n")
    }

    /// Format Outlook mail folders into readable text.
    public static func formatOutlookFolders(_ folders: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, folder) in folders.enumerated() {
            let name = folder["displayName"] as? String ?? "(unnamed)"
            let id = folder["id"] as? String ?? ""
            let total = folder["totalItemCount"] as? Int ?? 0
            let unread = folder["unreadItemCount"] as? Int ?? 0

            lines.append("\(i + 1). \(name) (\(total) items, \(unread) unread)")
            lines.append("   ID: \(id)")
            lines.append("")
        }
        return lines.isEmpty ? "(no folders)" : lines.joined(separator: "\n")
    }

    // MARK: - Outlook Calendar Response Formatting

    /// Format Outlook calendar events into readable text.
    public static func formatOutlookEvents(_ events: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, event) in events.enumerated() {
            let subject = event["subject"] as? String ?? "(no title)"
            let isAllDay = event["isAllDay"] as? Bool ?? false
            let startObj = event["start"] as? [String: Any]
            let start = startObj?["dateTime"] as? String ?? ""
            let endObj = event["end"] as? [String: Any]
            let end = endObj?["dateTime"] as? String ?? ""
            let locationObj = event["location"] as? [String: Any]
            let location = locationObj?["displayName"] as? String ?? ""
            let organizerObj = (event["organizer"] as? [String: Any])?["emailAddress"] as? [String: Any]
            let organizer = organizerObj?["name"] as? String ?? ""
            let id = event["id"] as? String ?? ""

            lines.append("\(i + 1). \(subject)\(isAllDay ? " [all day]" : "")")
            lines.append("   When: \(start)\(end.isEmpty ? "" : " → \(end)")")
            if !location.isEmpty { lines.append("   Where: \(location)") }
            if !organizer.isEmpty { lines.append("   Organizer: \(organizer)") }
            lines.append("   ID: \(id)")
            lines.append("")
        }
        return lines.isEmpty ? "(no events)" : lines.joined(separator: "\n")
    }

    /// Format Outlook calendars into readable text.
    public static func formatOutlookCalendars(_ calendars: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, cal) in calendars.enumerated() {
            let name = cal["name"] as? String ?? "(unnamed)"
            let id = cal["id"] as? String ?? ""
            let isDefault = cal["isDefaultCalendar"] as? Bool ?? false
            let color = cal["color"] as? String ?? ""

            lines.append("\(i + 1). \(name)\(isDefault ? " (default)" : "")")
            if !color.isEmpty { lines.append("   Color: \(color)") }
            lines.append("   ID: \(id)")
            lines.append("")
        }
        return lines.isEmpty ? "(no calendars)" : lines.joined(separator: "\n")
    }

    // MARK: - OneDrive Response Formatting

    /// Format OneDrive items (files/folders) into readable text.
    public static func formatOneDriveItems(_ items: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, item) in items.enumerated() {
            let name = item["name"] as? String ?? "(unnamed)"
            let id = item["id"] as? String ?? ""
            let size = item["size"] as? Int
            let lastModified = item["lastModifiedDateTime"] as? String ?? ""
            let isFolder = item["folder"] != nil
            let mimeType = (item["file"] as? [String: Any])?["mimeType"] as? String ?? ""

            let typeLabel = isFolder ? "[folder]" : (mimeType.isEmpty ? "" : "[\(mimeType)]")
            lines.append("\(i + 1). \(name) \(typeLabel)")
            if let size, !isFolder { lines.append("   Size: \(formatFileSize(size))") }
            if !lastModified.isEmpty { lines.append("   Modified: \(lastModified)") }
            lines.append("   ID: \(id)")
            lines.append("")
        }
        return lines.isEmpty ? "(no files)" : lines.joined(separator: "\n")
    }

    /// Format a single OneDrive item detail into readable text.
    public static func formatOneDriveItemDetail(_ item: [String: Any]) -> String {
        let name = item["name"] as? String ?? "(unnamed)"
        let id = item["id"] as? String ?? ""
        let size = item["size"] as? Int
        let lastModified = item["lastModifiedDateTime"] as? String ?? ""
        let createdAt = item["createdDateTime"] as? String ?? ""
        let isFolder = item["folder"] != nil
        let mimeType = (item["file"] as? [String: Any])?["mimeType"] as? String ?? ""
        let webUrl = item["webUrl"] as? String ?? ""
        let createdBy = (item["createdBy"] as? [String: Any])?["user"] as? [String: Any]
        let createdByName = createdBy?["displayName"] as? String ?? ""

        var lines: [String] = []
        lines.append("Name: \(name)")
        lines.append("Type: \(isFolder ? "Folder" : mimeType)")
        if let size, !isFolder { lines.append("Size: \(formatFileSize(size))") }
        if !createdAt.isEmpty { lines.append("Created: \(createdAt)") }
        if !lastModified.isEmpty { lines.append("Modified: \(lastModified)") }
        if !createdByName.isEmpty { lines.append("Created by: \(createdByName)") }
        if !webUrl.isEmpty { lines.append("Link: \(webUrl)") }
        lines.append("ID: \(id)")
        return lines.joined(separator: "\n")
    }

    /// Format byte size into human-readable string.
    private static func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024.0
        return String(format: "%.1f GB", gb)
    }

    // MARK: - Microsoft To Do Response Formatting

    /// Format To Do task lists into readable text.
    public static func formatToDoLists(_ lists: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, list) in lists.enumerated() {
            let name = list["displayName"] as? String ?? "(unnamed)"
            let id = list["id"] as? String ?? ""
            let isOwner = list["isOwner"] as? Bool ?? false
            let wellknown = list["wellknownListName"] as? String ?? ""

            let suffix = wellknown == "defaultList" ? " (default)" : ""
            lines.append("\(i + 1). \(name)\(suffix)\(isOwner ? "" : " [shared]")")
            lines.append("   ID: \(id)")
            lines.append("")
        }
        return lines.isEmpty ? "(no lists)" : lines.joined(separator: "\n")
    }

    /// Format To Do tasks into readable text.
    public static func formatToDoTasks(_ tasks: [[String: Any]]) -> String {
        var lines: [String] = []
        for (i, task) in tasks.enumerated() {
            let title = task["title"] as? String ?? "(untitled)"
            let status = task["status"] as? String ?? ""
            let importance = task["importance"] as? String ?? "normal"
            let dueObj = task["dueDateTime"] as? [String: Any]
            let dueDate = dueObj?["dateTime"] as? String ?? ""
            let id = task["id"] as? String ?? ""
            let isCompleted = status == "completed"

            let statusIcon = isCompleted ? "[done]" : "[pending]"
            let importanceLabel = importance == "high" ? " [!]" : ""
            lines.append("\(i + 1). \(statusIcon) \(title)\(importanceLabel)")
            if !dueDate.isEmpty { lines.append("   Due: \(dueDate)") }
            lines.append("   ID: \(id)")
            lines.append("")
        }
        return lines.isEmpty ? "(no tasks)" : lines.joined(separator: "\n")
    }

    /// Format a single To Do task detail into readable text.
    public static func formatToDoTaskDetail(_ task: [String: Any]) -> String {
        let title = task["title"] as? String ?? "(untitled)"
        let status = task["status"] as? String ?? ""
        let importance = task["importance"] as? String ?? "normal"
        let dueObj = task["dueDateTime"] as? [String: Any]
        let dueDate = dueObj?["dateTime"] as? String ?? ""
        let completedObj = task["completedDateTime"] as? [String: Any]
        let completedDate = completedObj?["dateTime"] as? String ?? ""
        let createdAt = task["createdDateTime"] as? String ?? ""
        let bodyObj = task["body"] as? [String: Any]
        let bodyContent = bodyObj?["content"] as? String ?? ""
        let id = task["id"] as? String ?? ""

        var lines: [String] = []
        lines.append("Title: \(title)")
        lines.append("Status: \(status)")
        lines.append("Importance: \(importance)")
        if !dueDate.isEmpty { lines.append("Due: \(dueDate)") }
        if !completedDate.isEmpty { lines.append("Completed: \(completedDate)") }
        if !createdAt.isEmpty { lines.append("Created: \(createdAt)") }
        if !bodyContent.isEmpty { lines.append("Notes: \(bodyContent)") }
        lines.append("ID: \(id)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Todoist Formatting

    /// Format Todoist tasks list.
    public static func formatTodoistTasks(_ tasks: [[String: Any]]) -> String {
        if tasks.isEmpty { return "(no tasks)" }
        return tasks.map { task in
            let content = task["content"] as? String ?? "(untitled)"
            let description = task["description"] as? String ?? ""
            let priority = task["priority"] as? Int ?? 1
            let due = (task["due"] as? [String: Any])?["date"] as? String ?? ""
            let isCompleted = task["is_completed"] as? Bool ?? false
            let labels = task["labels"] as? [String] ?? []
            let id = task["id"] as? String ?? ""

            var line = isCompleted ? "[done] " : "- "
            line += content
            if priority > 1 { line += " [p\(priority)]" }
            if !due.isEmpty { line += " (due: \(due))" }
            if !labels.isEmpty { line += " [\(labels.joined(separator: ", "))]" }
            if !description.isEmpty { line += "\n  \(description)" }
            if !id.isEmpty { line += "\n  ID: \(id)" }
            return line
        }.joined(separator: "\n")
    }

    /// Format Todoist projects list.
    public static func formatTodoistProjects(_ projects: [[String: Any]]) -> String {
        if projects.isEmpty { return "(no projects)" }
        return projects.map { project in
            let name = project["name"] as? String ?? "(untitled)"
            let id = project["id"] as? String ?? ""
            let color = project["color"] as? String ?? ""
            let isFavorite = project["is_favorite"] as? Bool ?? false
            var line = "- \(name)"
            if isFavorite { line += " ★" }
            if !color.isEmpty { line += " (\(color))" }
            if !id.isEmpty { line += " [ID: \(id)]" }
            return line
        }.joined(separator: "\n")
    }

    /// Format a single Todoist task detail.
    public static func formatTodoistTaskDetail(_ task: [String: Any]) -> String {
        let content = task["content"] as? String ?? "(untitled)"
        let description = task["description"] as? String ?? ""
        let priority = task["priority"] as? Int ?? 1
        let due = (task["due"] as? [String: Any])?["date"] as? String ?? ""
        let isCompleted = task["is_completed"] as? Bool ?? false
        let labels = task["labels"] as? [String] ?? []
        let id = task["id"] as? String ?? ""
        let projectId = task["project_id"] as? String ?? ""
        let createdAt = task["created_at"] as? String ?? ""

        var lines: [String] = []
        lines.append(content)
        lines.append("Status: \(isCompleted ? "completed" : "active")")
        lines.append("Priority: p\(priority)")
        if !due.isEmpty { lines.append("Due: \(due)") }
        if !labels.isEmpty { lines.append("Labels: \(labels.joined(separator: ", "))") }
        if !description.isEmpty { lines.append("Description: \(description)") }
        if !projectId.isEmpty { lines.append("Project ID: \(projectId)") }
        if !createdAt.isEmpty { lines.append("Created: \(createdAt)") }
        if !id.isEmpty { lines.append("ID: \(id)") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Trello Formatting

    /// Format Trello boards list.
    public static func formatTrelloBoards(_ boards: [[String: Any]]) -> String {
        if boards.isEmpty { return "(no boards)" }
        return boards.map { board in
            let name = board["name"] as? String ?? "(untitled)"
            let id = board["id"] as? String ?? ""
            let desc = board["desc"] as? String ?? ""
            let closed = board["closed"] as? Bool ?? false
            let url = board["url"] as? String ?? ""
            var line = closed ? "[closed] " : "- "
            line += name
            if !desc.isEmpty { line += " — \(desc)" }
            if !url.isEmpty { line += "\n  URL: \(url)" }
            if !id.isEmpty { line += "\n  ID: \(id)" }
            return line
        }.joined(separator: "\n")
    }

    /// Format Trello cards list.
    public static func formatTrelloCards(_ cards: [[String: Any]]) -> String {
        if cards.isEmpty { return "(no cards)" }
        return cards.map { card in
            let name = card["name"] as? String ?? "(untitled)"
            let id = card["id"] as? String ?? ""
            let desc = card["desc"] as? String ?? ""
            let due = card["due"] as? String ?? ""
            let closed = card["closed"] as? Bool ?? false
            let labels = (card["labels"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            var line = closed ? "[done] " : "- "
            line += name
            if !labels.isEmpty { line += " [\(labels.joined(separator: ", "))]" }
            if !due.isEmpty { line += " (due: \(due))" }
            if !desc.isEmpty {
                let shortDesc = desc.count > 80 ? String(desc.prefix(80)) + "..." : desc
                line += "\n  \(shortDesc)"
            }
            if !id.isEmpty { line += "\n  ID: \(id)" }
            return line
        }.joined(separator: "\n")
    }

    /// Format Trello lists.
    public static func formatTrelloLists(_ lists: [[String: Any]]) -> String {
        if lists.isEmpty { return "(no lists)" }
        return lists.map { list in
            let name = list["name"] as? String ?? "(untitled)"
            let id = list["id"] as? String ?? ""
            let closed = list["closed"] as? Bool ?? false
            var line = closed ? "[archived] " : "- "
            line += name
            if !id.isEmpty { line += " [ID: \(id)]" }
            return line
        }.joined(separator: "\n")
    }

    // MARK: - Airtable Formatting

    /// Format Airtable records list.
    public static func formatAirtableRecords(_ records: [[String: Any]]) -> String {
        if records.isEmpty { return "(no records)" }
        return records.map { record in
            let id = record["id"] as? String ?? ""
            let fields = record["fields"] as? [String: Any] ?? [:]
            var lines: [String] = ["Record: \(id)"]
            for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
                let valueStr: String
                if let str = value as? String { valueStr = str }
                else if let num = value as? NSNumber { valueStr = "\(num)" }
                else if let arr = value as? [Any] { valueStr = "[\(arr.count) items]" }
                else { valueStr = "\(value)" }
                lines.append("  \(key): \(valueStr)")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n---\n")
    }

    /// Format Airtable bases list.
    public static func formatAirtableBases(_ bases: [[String: Any]]) -> String {
        if bases.isEmpty { return "(no bases)" }
        return bases.map { base in
            let name = base["name"] as? String ?? "(untitled)"
            let id = base["id"] as? String ?? ""
            var line = "- \(name)"
            if !id.isEmpty { line += " [ID: \(id)]" }
            return line
        }.joined(separator: "\n")
    }

    /// Format a single Airtable record detail.
    public static func formatAirtableRecordDetail(_ record: [String: Any]) -> String {
        let id = record["id"] as? String ?? ""
        let fields = record["fields"] as? [String: Any] ?? [:]
        let createdTime = record["createdTime"] as? String ?? ""
        var lines: [String] = ["Record: \(id)"]
        if !createdTime.isEmpty { lines.append("Created: \(createdTime)") }
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            let valueStr: String
            if let str = value as? String { valueStr = str }
            else if let num = value as? NSNumber { valueStr = "\(num)" }
            else if let arr = value as? [Any] { valueStr = "[\(arr.count) items]" }
            else { valueStr = "\(value)" }
            lines.append("  \(key): \(valueStr)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Dropbox Formatting

    /// Format Dropbox file/folder entries.
    public static func formatDropboxEntries(_ entries: [[String: Any]]) -> String {
        if entries.isEmpty { return "(no files)" }
        return entries.map { entry in
            let name = entry["name"] as? String ?? "(unknown)"
            let tag = entry[".tag"] as? String ?? ""
            let pathDisplay = entry["path_display"] as? String ?? ""
            let size = entry["size"] as? Int
            let modified = entry["server_modified"] as? String ?? ""
            var line = tag == "folder" ? "📁 " : "📄 "
            line += name
            if let size { line += " (\(ConnectorsKit.formatFileSize(size)))" }
            if !modified.isEmpty { line += " [modified: \(modified)]" }
            if !pathDisplay.isEmpty { line += "\n  Path: \(pathDisplay)" }
            return line
        }.joined(separator: "\n")
    }

    /// Format Dropbox search results.
    public static func formatDropboxSearchResults(_ matches: [[String: Any]]) -> String {
        if matches.isEmpty { return "(no results)" }
        let entries = matches.compactMap { match -> [String: Any]? in
            match["metadata"] as? [String: Any] ?? (match["metadata"] as? [String: Any])?["metadata"] as? [String: Any]
        }
        if entries.isEmpty { return "(no results)" }
        return formatDropboxEntries(entries)
    }

    /// Format a single Dropbox entry detail.
    public static func formatDropboxEntryDetail(_ entry: [String: Any]) -> String {
        let name = entry["name"] as? String ?? "(unknown)"
        let tag = entry[".tag"] as? String ?? ""
        let pathDisplay = entry["path_display"] as? String ?? ""
        let size = entry["size"] as? Int
        let modified = entry["server_modified"] as? String ?? ""
        let id = entry["id"] as? String ?? ""

        var lines: [String] = ["\(tag == "folder" ? "📁" : "📄") \(name)"]
        if !pathDisplay.isEmpty { lines.append("Path: \(pathDisplay)") }
        if let size { lines.append("Size: \(ConnectorsKit.formatFileSize(size))") }
        if !modified.isEmpty { lines.append("Modified: \(modified)") }
        if !id.isEmpty { lines.append("ID: \(id)") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Weather Formatting

    /// Format current weather response from OpenWeatherMap.
    public static func formatCurrentWeather(_ json: [String: Any]) -> String {
        let name = json["name"] as? String ?? ""
        let main = json["main"] as? [String: Any] ?? [:]
        let weather = (json["weather"] as? [[String: Any]])?.first ?? [:]
        let wind = json["wind"] as? [String: Any] ?? [:]

        let temp = main["temp"] as? Double ?? 0
        let feelsLike = main["feels_like"] as? Double ?? 0
        let humidity = main["humidity"] as? Int ?? 0
        let description = weather["description"] as? String ?? ""
        let windSpeed = wind["speed"] as? Double ?? 0

        var lines: [String] = []
        if !name.isEmpty { lines.append("📍 \(name)") }
        lines.append("🌡 \(String(format: "%.1f", temp))°C (feels like \(String(format: "%.1f", feelsLike))°C)")
        if !description.isEmpty { lines.append("☁️ \(description.capitalized)") }
        lines.append("💧 Humidity: \(humidity)%")
        lines.append("💨 Wind: \(String(format: "%.1f", windSpeed)) m/s")
        return lines.joined(separator: "\n")
    }

    /// Format weather forecast from OpenWeatherMap.
    public static func formatWeatherForecast(_ json: [String: Any]) -> String {
        let city = (json["city"] as? [String: Any])?["name"] as? String ?? ""
        let list = json["list"] as? [[String: Any]] ?? []

        if list.isEmpty { return "(no forecast data)" }

        var lines: [String] = []
        if !city.isEmpty { lines.append("📍 Forecast for \(city)") }

        // Show next 8 entries (24h at 3h intervals)
        for entry in list.prefix(8) {
            let dt = entry["dt_txt"] as? String ?? ""
            let main = entry["main"] as? [String: Any] ?? [:]
            let weather = (entry["weather"] as? [[String: Any]])?.first ?? [:]
            let temp = main["temp"] as? Double ?? 0
            let description = weather["description"] as? String ?? ""
            lines.append("  \(dt): \(String(format: "%.1f", temp))°C — \(description)")
        }
        return lines.joined(separator: "\n")
    }

    /// Format weather alerts from OpenWeatherMap One Call API.
    public static func formatWeatherAlerts(_ json: [String: Any]) -> String {
        let alerts = json["alerts"] as? [[String: Any]] ?? []
        if alerts.isEmpty { return "(no active weather alerts)" }

        return alerts.map { alert in
            let event = alert["event"] as? String ?? "(unknown)"
            let sender = alert["sender_name"] as? String ?? ""
            let description = alert["description"] as? String ?? ""
            let start = alert["start"] as? Int
            let end = alert["end"] as? Int
            var lines: [String] = ["⚠️ \(event)"]
            if !sender.isEmpty { lines.append("Source: \(sender)") }
            if let start { lines.append("Start: \(formatUnixTimestamp(start))") }
            if let end { lines.append("End: \(formatUnixTimestamp(end))") }
            if !description.isEmpty {
                let short = description.count > 200 ? String(description.prefix(200)) + "..." : description
                lines.append(short)
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n---\n")
    }

    /// Format a Unix timestamp to ISO string.
    public static func formatUnixTimestamp(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime]
        return formatter.string(from: date)
    }

    // MARK: - RSS Formatting

    /// Format RSS/Atom feed entries.
    public static func formatRSSEntries(_ entries: [[String: String]]) -> String {
        if entries.isEmpty { return "(no entries)" }
        return entries.enumerated().map { index, entry in
            let title = entry["title"] ?? "(untitled)"
            let link = entry["link"] ?? ""
            let description = entry["description"] ?? ""
            let pubDate = entry["pubDate"] ?? ""
            let author = entry["author"] ?? ""
            var lines: [String] = ["\(index + 1). \(title)"]
            if !pubDate.isEmpty { lines.append("   Date: \(pubDate)") }
            if !author.isEmpty { lines.append("   Author: \(author)") }
            if !link.isEmpty { lines.append("   Link: \(link)") }
            if !description.isEmpty {
                let clean = description
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let short = clean.count > 150 ? String(clean.prefix(150)) + "..." : clean
                if !short.isEmpty { lines.append("   \(short)") }
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    // MARK: - Webhook Formatting

    /// Format webhook response.
    public static func formatWebhookResponse(statusCode: Int, body: String) -> String {
        var lines: [String] = ["HTTP \(statusCode)"]
        if !body.isEmpty {
            let truncated = body.count > 2000 ? String(body.prefix(2000)) + "... (truncated)" : body
            lines.append(truncated)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Bot Token Validation

    /// Validate a Slack Bot Token format (xoxb- prefix).
    public static func isValidSlackBotToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("xoxb-") && trimmed.count >= 30
    }

    /// Validate a Discord Bot Token format (contains two dots separating three base64 segments).
    public static func isValidDiscordBotToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".")
        return parts.count == 3 && trimmed.count >= 50
    }

    /// Validate a Telegram Bot Token format (digits:alphanumeric-with-dashes).
    public static func isValidTelegramBotToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return false }
        let botId = parts[0]
        let hash = parts[1]
        return botId.allSatisfy(\.isNumber) && !botId.isEmpty && hash.count >= 30
    }

    // MARK: - PAT Validation

    /// Validate a GitHub Personal Access Token format.
    public static func isValidGitHubPAT(_ token: String) -> Bool {
        // Classic PATs: ghp_ prefix, 36+ chars
        // Fine-grained PATs: github_pat_ prefix
        // OAuth tokens: gho_ prefix
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ghp_") && trimmed.count >= 40 { return true }
        if trimmed.hasPrefix("github_pat_") && trimmed.count >= 40 { return true }
        if trimmed.hasPrefix("gho_") && trimmed.count >= 40 { return true }
        return false
    }

    /// Validate a GitLab Personal Access Token format.
    public static func isValidGitLabPAT(_ token: String) -> Bool {
        // GitLab PATs: glpat- prefix, 20+ chars
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("glpat-") && trimmed.count >= 20 { return true }
        // Legacy tokens without prefix (alphanumeric, 20 chars)
        if trimmed.count == 20 && trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) { return true }
        return false
    }
}
