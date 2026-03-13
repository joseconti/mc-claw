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

    /// Build a context header for the active Git repository.
    func buildGitContextHeader(_ context: GitContext) -> String {
        var lines: [String] = []
        lines.append("[McClaw Git Context]")
        lines.append("Platform: \(context.platform.displayName)")
        lines.append("Repository: \(context.repoFullName) (\(context.repoURL))")
        lines.append("Branch: \(context.branch)")
        if let path = context.localPath {
            lines.append("Local path: \(path)")
        }
        lines.append("Available actions:")
        lines.append("  Platform (\(context.platform.displayName) API): list_issues, list_prs, get_pr_diff, create_issue, create_pr, create_comment, search_code, list_releases, list_branches, list_commits")
        lines.append("  Local (git CLI): log, diff, status, blame, show, clone, checkout, branch, add, commit, push, pull, tag, stash")
        lines.append("To execute an action, use: @fetch(\(context.platform == .github ? "github" : "gitlab").list_prs, repo=\(context.repoFullName), state=open) or @git(log --since=\"1 week ago\" --oneline)")
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
