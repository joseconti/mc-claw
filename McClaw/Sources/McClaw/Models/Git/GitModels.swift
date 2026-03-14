import Foundation

// MARK: - Platform

/// Supported Git hosting platforms.
enum GitPlatform: String, Codable, CaseIterable, Sendable, Identifiable {
    case github
    case gitlab

    var id: String { rawValue }

    var connectorId: String {
        switch self {
        case .github: return "dev.github"
        case .gitlab: return "dev.gitlab"
        }
    }

    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        }
    }

    var icon: String {
        switch self {
        case .github: return "arrow.triangle.branch"
        case .gitlab: return "arrow.triangle.branch"
        }
    }
}

// MARK: - Context

/// Active Git context for chat enrichment.
struct GitContext: Equatable, Sendable {
    let platform: GitPlatform
    let repoFullName: String
    let repoURL: String
    var branch: String
    var localPath: String?
    /// Additional repos for cross-repo intelligence (comparing dependent repos).
    var additionalRepos: [AdditionalRepoContext]?
}

/// Lightweight reference to an additional repo for cross-repo prompts.
struct AdditionalRepoContext: Equatable, Sendable {
    let fullName: String
    let platform: GitPlatform
    let localPath: String?
}

// MARK: - Repository

/// Repository info fetched from a Git platform.
struct GitRepoInfo: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let fullName: String
    let description: String?
    let language: String?
    let isPrivate: Bool
    let isFork: Bool
    let starCount: Int
    let openIssueCount: Int
    let openPRCount: Int
    let defaultBranch: String
    let updatedAt: Date
    let cloneURL: String
    let htmlURL: String
    var localPath: String?
}

// MARK: - Branch

/// A Git branch.
struct GitBranch: Identifiable, Codable, Sendable {
    var id: String { name }
    let name: String
    let isDefault: Bool
    let isProtected: Bool
    let aheadBehind: AheadBehind?
}

/// Ahead/behind counts relative to the default branch.
struct AheadBehind: Codable, Sendable {
    let ahead: Int
    let behind: Int
}

// MARK: - Pull Request

/// Pull request / merge request info.
struct GitPRInfo: Identifiable, Codable, Sendable {
    let id: String
    let number: Int
    let title: String
    let author: String
    let state: String
    let sourceBranch: String
    let targetBranch: String
    let reviewState: String?
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Issue

/// Issue info from a Git platform.
struct GitIssueInfo: Identifiable, Codable, Sendable {
    let id: String
    let number: Int
    let title: String
    let author: String
    let state: String
    let labels: [String]
    let assignees: [String]
    let createdAt: Date
}

// MARK: - Commit

/// Commit info.
struct GitCommitInfo: Identifiable, Codable, Sendable {
    let id: String
    let shortSha: String
    let message: String
    let author: String
    let date: Date
}

// MARK: - Local Repo

/// A locally cloned repository discovered on disk.
struct LocalRepoInfo: Codable, Sendable {
    let path: String
    let remoteURL: String?
    let currentBranch: String?
}

// MARK: - File Entry

/// A file or directory entry from the repository contents API.
struct GitFileEntry: Identifiable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    let type: FileType
    let size: Int
    let sha: String

    enum FileType: String, Sendable {
        case file
        case dir
        case symlink
        case submodule
    }
}

// MARK: - File Tree Node

/// An observable node in the expandable file tree.
/// Directories can be expanded to reveal children loaded lazily from the API.
@MainActor
@Observable
final class FileTreeNode: Identifiable {
    let entry: GitFileEntry
    var children: [FileTreeNode]?
    var isExpanded: Bool = false
    var isLoading: Bool = false

    nonisolated var id: String { entry.path }

    init(entry: GitFileEntry, children: [FileTreeNode]? = nil) {
        self.entry = entry
        self.children = children
    }

    /// Sorted children: directories first, then files, both alphabetical.
    var sortedChildren: [FileTreeNode] {
        guard let children else { return [] }
        let dirs = children.filter { $0.entry.type == .dir }.sorted { $0.entry.name.localizedCompare($1.entry.name) == .orderedAscending }
        let files = children.filter { $0.entry.type != .dir }.sorted { $0.entry.name.localizedCompare($1.entry.name) == .orderedAscending }
        return dirs + files
    }
}

// MARK: - Sort

/// Sort order for the repository list.
enum GitSortOrder: String, CaseIterable, Sendable {
    case lastUpdated
    case name
    case stars
}

// MARK: - Stash Action

/// Stash sub-commands.
enum StashAction: String, Sendable {
    case save
    case pop
    case list
    case drop
    case apply
}
