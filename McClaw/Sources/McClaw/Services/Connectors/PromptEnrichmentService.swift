import Foundation
import Logging
import McClawKit

/// Coordinates prompt enrichment: injects connectors header, executes @fetch commands,
/// and enriches cron job payloads with real data from connected services.
@MainActor
@Observable
final class PromptEnrichmentService {
    static let shared = PromptEnrichmentService()

    /// True while the service is executing @fetch commands.
    var isFetching = false
    /// Human-readable status of the current fetch operation.
    var fetchStatusMessage: String?

    private let logger = Logger(label: "ai.mcclaw.prompt-enrichment")

    private init() {}

    // MARK: - Connectors Header

    /// Build the header to prepend to the first message in a conversation turn.
    /// Returns nil if no connectors are active.
    func buildConnectorsHeader() -> String? {
        ConnectorStore.shared.buildConnectorsHeader()
    }

    // MARK: - Chat @fetch Processing

    /// Parse and execute all @fetch commands found in an AI response.
    /// Returns the clean response (without @fetch tokens) and the fetched results formatted for re-injection.
    /// - Parameters:
    ///   - response: The raw AI response text.
    ///   - round: Current fetch round (1-based). Stops at `maxFetchRoundsPerTurn`.
    /// - Returns: Tuple of (cleanResponse, fetchResults). fetchResults is nil if no @fetch found.
    func parseAndExecuteFetch(
        response: String,
        round: Int = 1
    ) async -> (cleanResponse: String, fetchResults: String?) {
        let commands = ConnectorsKit.detectFetchInResponse(response)
        guard !commands.isEmpty else {
            return (response, nil)
        }

        guard round <= ConnectorsKit.maxFetchRoundsPerTurn else {
            logger.warning("Max fetch rounds (\(ConnectorsKit.maxFetchRoundsPerTurn)) reached, skipping")
            let cleaned = ConnectorsKit.removeFetchCommands(response)
            return (cleaned, nil)
        }

        isFetching = true
        defer { isFetching = false; fetchStatusMessage = nil }

        var results: [(connector: String, action: String, data: String)] = []

        for cmd in commands {
            fetchStatusMessage = "Fetching data from \(cmd.connector).\(cmd.action)…"
            logger.info("Executing @fetch: \(cmd.connector).\(cmd.action) params=\(cmd.params)")

            let result = await executeFetchCommand(cmd)
            results.append(result)
        }

        let cleaned = ConnectorsKit.removeFetchCommands(response)
        let enriched = ConnectorsKit.buildEnrichedPrompt(original: cleaned, results: results)

        return (cleaned, enriched)
    }

    // MARK: - Manual /fetch

    /// Execute a single /fetch command from user input.
    /// Returns a formatted result message for display in chat.
    func executeSlashFetch(_ input: String) async -> String {
        guard let cmd = ConnectorsKit.parseSlashFetch(input) else {
            return "Invalid format. Usage: `/fetch connector.action param=value`"
        }

        isFetching = true
        fetchStatusMessage = "Fetching data from \(cmd.connector).\(cmd.action)…"
        defer { isFetching = false; fetchStatusMessage = nil }

        let result = await executeFetchCommand(cmd)
        let (formatted, truncated) = ConnectorsKit.formatActionResult(
            result.data,
            maxLength: ConnectorsKit.defaultMaxResultLength
        )

        return ConnectorsKit.buildFetchResultMessage(
            connector: result.connector,
            action: result.action,
            data: formatted,
            truncated: truncated
        )
    }

    // MARK: - Cron Enrichment

    /// Enrich a cron job message with data from pre-configured connector bindings.
    /// Each binding is executed and results are prepended to the original message.
    func enrichForCronJob(
        message: String,
        bindings: [ConnectorBinding]
    ) async -> String {
        guard !bindings.isEmpty else { return message }

        isFetching = true
        defer { isFetching = false; fetchStatusMessage = nil }

        var results: [(connector: String, action: String, data: String)] = []

        for binding in bindings {
            fetchStatusMessage = "Fetching data for cron: \(binding.actionId)…"

            do {
                let actionResult = try await ConnectorExecutor.shared.execute(
                    instanceId: binding.connectorInstanceId,
                    actionId: binding.actionId,
                    params: binding.params
                )

                let (formatted, _) = ConnectorsKit.formatActionResult(
                    actionResult.data,
                    maxLength: binding.maxResultLength
                )

                // Resolve connector name from instance
                let connectorName = resolveConnectorName(instanceId: binding.connectorInstanceId)
                results.append((connector: connectorName, action: binding.actionId, data: formatted))

            } catch {
                // Include error as text, don't fail the whole job
                let connectorName = resolveConnectorName(instanceId: binding.connectorInstanceId)
                let errorText = "[Error fetching \(connectorName).\(binding.actionId): \(error.localizedDescription)]"
                results.append((connector: connectorName, action: binding.actionId, data: errorText))
                logger.error("Cron fetch failed: \(connectorName).\(binding.actionId): \(error)")
            }
        }

        return ConnectorsKit.buildEnrichedPrompt(original: message, results: results)
    }

    // MARK: - Git Context Header

    /// Build a context header for the active Git repository with READ/WRITE separation
    /// and confirmation format instructions.
    func buildGitContextHeader(_ context: GitContext) -> String {
        let platformId = context.platform == .github ? "github" : "gitlab"
        let clonedLocally = context.localPath != nil ? "yes" : "no"

        var lines: [String] = []
        lines.append("[McClaw Git Context]")
        lines.append("Platform: \(context.platform.displayName)")
        lines.append("Repository: \(context.repoFullName) (\(context.repoURL))")
        lines.append("Branch: \(context.branch)")
        if let path = context.localPath {
            lines.append("Local path: \(path)")
        }
        lines.append("Cloned locally: \(clonedLocally)")
        lines.append("")
        lines.append("Available platform actions (via @fetch):")
        lines.append("  READ: list_repos, list_branches, list_issues, list_prs, get_pr_diff, list_commits, list_releases, search_code, get_contents")
        lines.append("  WRITE: create_issue, close_issue, create_comment, create_pr, merge_pr, create_release")
        lines.append("")
        if context.localPath != nil {
            lines.append("Available local git actions (via @git):")
            lines.append("  READ: log, diff, status, blame, show, branch, shortlog, ls-files, ls-tree, describe, tag --list")
            lines.append("  WRITE: clone, checkout, pull, add, commit, push, tag, stash, fetch, merge, rebase, cherry-pick, reset")
            lines.append("")
        }
        lines.append("Rules:")
        lines.append("  - For READ actions, execute directly: @git(log -10 --oneline) or @fetch(\(platformId).list_prs, repo=\(context.repoFullName), state=open)")
        lines.append("  - For WRITE actions, ALWAYS use the confirmation format:")
        lines.append("    @git-confirm(command, title=Title, details=key1=value1|key2=value2)")
        lines.append("    @fetch-confirm(connector.action, param1=value1, param2=value2)")
        lines.append("  - Maximum 5 @git rounds per message")
        lines.append("  - Maximum 3 @fetch rounds per message")
        lines.append("  - Output truncation: 8000 chars for @git, 4000 chars for @fetch")

        // Cross-repo context
        if let additionalRepos = context.additionalRepos, !additionalRepos.isEmpty {
            lines.append("")
            lines.append("Additional repositories in context (cross-repo intelligence):")
            for repo in additionalRepos {
                let localInfo = repo.localPath != nil ? ", local: \(repo.localPath!)" : ""
                lines.append("  - \(repo.fullName) (\(repo.platform.displayName)\(localInfo))")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - @git() Processing

    /// Maximum characters of git output forwarded to the AI.
    private static let maxGitOutputLength = 8000

    /// Parse and execute all @git() commands found in an AI response.
    func parseAndExecuteGit(
        response: String,
        repoPath: String?,
        round: Int = 1
    ) async -> (cleanResponse: String, gitResults: String?) {
        let commands = detectGitCommands(in: response)
        guard !commands.isEmpty else {
            return (response, nil)
        }

        guard round <= ConnectorsKit.maxFetchRoundsPerTurn else {
            logger.warning("Max git rounds reached, skipping")
            let cleaned = removeGitCommands(from: response)
            return (cleaned, nil)
        }

        guard let path = repoPath else {
            let cleaned = removeGitCommands(from: response)
            return (cleaned, "[Git Error: No local repository path. Clone the repo first.]")
        }

        isFetching = true
        defer { isFetching = false; fetchStatusMessage = nil }

        var results: [String] = []

        for cmd in commands {
            fetchStatusMessage = "Running git \(cmd.prefix(30))…"
            logger.info("Executing @git: \(cmd) in \(path)")

            do {
                let output = try await GitService.shared.executeRaw(command: cmd, repoPath: path)
                let truncated = output.count > Self.maxGitOutputLength
                    ? String(output.prefix(Self.maxGitOutputLength)) + "\n... (truncated)"
                    : output
                results.append("[git \(cmd)]\n\(truncated)")
            } catch {
                results.append("[git \(cmd)]\nError: \(error.localizedDescription)")
                logger.error("@git failed: \(cmd): \(error)")
            }
        }

        let cleaned = removeGitCommands(from: response)
        let combined = results.joined(separator: "\n\n")
        let enriched = """
        \(cleaned)

        [McClaw Git Results]
        \(combined)

        Based on the git output above, provide a helpful summary to the user.
        """

        return (cleaned, enriched)
    }

    /// Detect @git(...) commands in text.
    private func detectGitCommands(in text: String) -> [String] {
        var commands: [String] = []
        let pattern = #"@git\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            if match.numberOfRanges > 1 {
                let cmdRange = match.range(at: 1)
                let cmd = nsText.substring(with: cmdRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                commands.append(cmd)
            }
        }
        return commands
    }

    /// Remove @git(...) tokens from text.
    private func removeGitCommands(from text: String) -> String {
        let pattern = #"@git\([^)]+\)\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: nsText.length), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - @git-confirm() / @fetch-confirm() Processing

    /// Detect @git-confirm(...) commands in AI response.
    /// Format: @git-confirm(command, title=Title, details=key1=value1|key2=value2)
    func detectGitConfirmations(in text: String) -> [PendingGitAction] {
        var actions: [PendingGitAction] = []
        // Match @git-confirm(command, title=..., details=...)
        let pattern = #"@git-confirm\(([^,]+),\s*title=([^,]+),\s*details=([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard match.numberOfRanges > 3 else { continue }
            let command = nsText.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = nsText.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detailsRaw = nsText.substring(with: match.range(at: 3))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var details = parseKeyValuePairs(detailsRaw)

            // Mark destructive operations
            let destructivePatterns = ["reset", "rebase", "--force", "push --force", "push -f"]
            if destructivePatterns.contains(where: { command.lowercased().contains($0) }) {
                details["warning"] = "destructive"
            }

            actions.append(PendingGitAction(
                type: .localGit,
                command: command,
                title: title,
                details: details
            ))
        }
        return actions
    }

    /// Detect @fetch-confirm(...) commands in AI response.
    /// Format: @fetch-confirm(connector.action, param1=value1, param2=value2, ...)
    func detectFetchConfirmations(in text: String) -> [PendingGitAction] {
        var actions: [PendingGitAction] = []
        // Match @fetch-confirm(connector.action, rest...)
        let pattern = #"@fetch-confirm\(([a-zA-Z_]+\.[a-zA-Z_]+),\s*(.+?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard match.numberOfRanges > 2 else { continue }
            let connectorAction = nsText.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let paramsRaw = nsText.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Parse params as key=value pairs separated by commas
            var details: [String: String] = [:]
            let parts = paramsRaw.components(separatedBy: ", ")
            for part in parts {
                let kv = part.components(separatedBy: "=")
                if kv.count >= 2 {
                    let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = kv.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
                    details[key] = value
                }
            }

            // Derive title from action name
            let actionParts = connectorAction.split(separator: ".")
            let actionName = actionParts.count > 1 ? String(actionParts[1]) : connectorAction
            let title = actionName
                .replacingOccurrences(of: "_", with: " ")
                .capitalized

            actions.append(PendingGitAction(
                type: .platformAPI,
                command: connectorAction,
                title: title,
                details: details
            ))
        }
        return actions
    }

    /// Remove @git-confirm(...) and @fetch-confirm(...) tokens from text.
    func removeConfirmationCommands(from text: String) -> String {
        var result = text
        // Remove @git-confirm(...)
        if let regex = try? NSRegularExpression(pattern: #"@git-confirm\([^)]+\)\s*"#) {
            let nsText = result as NSString
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: nsText.length), withTemplate: "")
        }
        // Remove @fetch-confirm(...)
        if let regex = try? NSRegularExpression(pattern: #"@fetch-confirm\(.+?\)\s*"#, options: .dotMatchesLineSeparators) {
            let nsText = result as NSString
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: nsText.length), withTemplate: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse "key1=value1|key2=value2" into a dictionary.
    private func parseKeyValuePairs(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = raw.components(separatedBy: "|")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=")
            if kv.count >= 2 {
                let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = kv.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    result[key] = value
                }
            }
        }
        return result
    }

    // MARK: - Private Helpers

    /// Execute a single FetchCommand, resolving the connector instance by name.
    private func executeFetchCommand(_ cmd: ConnectorsKit.FetchCommand) async -> (connector: String, action: String, data: String) {
        // Find the connected instance matching the connector name
        guard let instance = resolveInstance(for: cmd.connector) else {
            let error = "[Error: No connected connector matching '\(cmd.connector)'. Check Settings → Connectors.]"
            return (connector: cmd.connector, action: cmd.action, data: error)
        }

        do {
            let result = try await ConnectorExecutor.shared.execute(
                instanceId: instance.id,
                actionId: cmd.action,
                params: cmd.params
            )

            let (formatted, _) = ConnectorsKit.formatActionResult(
                result.data,
                maxLength: ConnectorsKit.defaultMaxResultLength
            )

            return (connector: cmd.connector, action: cmd.action, data: formatted)

        } catch {
            let errorText = "[Error: \(error.localizedDescription)]"
            logger.error("Fetch failed: \(cmd.connector).\(cmd.action): \(error)")
            return (connector: cmd.connector, action: cmd.action, data: errorText)
        }
    }

    /// Resolve a connector instance by name or definition ID.
    /// Tries: exact instance name (case-insensitive), definition ID, definition name.
    private func resolveInstance(for name: String) -> ConnectorInstance? {
        let connected = ConnectorStore.shared.connectedInstances
        let lower = name.lowercased()

        // 1. Match by instance name (case-insensitive)
        if let match = connected.first(where: { $0.name.lowercased() == lower }) {
            return match
        }

        // 2. Match by definition ID (e.g. "google.gmail", "github")
        if let match = connected.first(where: { $0.definitionId.lowercased() == lower }) {
            return match
        }

        // 3. Match by definition ID suffix (e.g. "gmail" matches "google.gmail")
        if let match = connected.first(where: {
            $0.definitionId.lowercased().hasSuffix(".\(lower)") ||
            $0.definitionId.lowercased() == "google.\(lower)" ||
            $0.definitionId.lowercased() == "microsoft.\(lower)"
        }) {
            return match
        }

        return nil
    }

    /// Get a human-readable connector name from an instance ID.
    private func resolveConnectorName(instanceId: String) -> String {
        guard let instance = ConnectorStore.shared.instance(for: instanceId) else {
            return instanceId
        }
        return instance.name.lowercased()
    }
}
