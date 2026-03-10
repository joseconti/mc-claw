import Foundation

/// A Git or platform action proposed by the AI that requires user confirmation before execution.
///
/// Used in the `@git-confirm()` and `@fetch-confirm()` intercept pipeline.
/// The confirmation card is shown inline in the chat message stream.
struct PendingGitAction: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let type: GitActionType
    let command: String
    let title: String
    let details: [String: String]
    var status: GitActionStatus

    init(
        id: UUID = UUID(),
        type: GitActionType,
        command: String,
        title: String,
        details: [String: String] = [:],
        status: GitActionStatus = .pendingConfirmation
    ) {
        self.id = id
        self.type = type
        self.command = command
        self.title = title
        self.details = details
        self.status = status
    }

    // MARK: - Action Type

    enum GitActionType: String, Codable, Sendable, Equatable {
        /// Execute via GitService.executeRaw (local git CLI).
        case localGit
        /// Execute via ConnectorExecutor (platform API: GitHub/GitLab).
        case platformAPI
    }

    // MARK: - Status

    enum GitActionStatus: Codable, Sendable, Equatable {
        case pendingConfirmation
        case executing
        case completed(output: String)
        case failed(error: String)
        case cancelled
    }

    // MARK: - Helpers

    /// Whether this action involves a destructive git operation (reset, rebase, --force).
    var isDestructive: Bool {
        details["warning"] == "destructive"
    }

    /// Details as sorted tuples for display in the confirmation card.
    var sortedDetails: [(label: String, value: String)] {
        details
            .filter { $0.key != "warning" }
            .sorted { $0.key < $1.key }
            .map { (label: $0.key, value: $0.value) }
    }
}
