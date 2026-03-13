import Foundation
import Logging

/// State management for the Git section panel.
@MainActor
@Observable
final class GitPanelViewModel {
    // MARK: - Platform & Repos

    var selectedPlatform: GitPlatform = .github
    var availablePlatforms: [GitPlatform] = []
    var repos: [GitRepoInfo] = []
    var searchText: String = ""
    var sortOrder: GitSortOrder = .lastUpdated
    var isLoadingRepos: Bool = false
    var loadError: String?

    // MARK: - Selection

    var selectedRepo: GitRepoInfo?
    var selectedBranch: GitBranch?
    var gitContext: GitContext?

    // MARK: - Detail

    var isShowingDetail: Bool = false
    var branches: [GitBranch] = []
    var pullRequests: [GitPRInfo] = []
    var issues: [GitIssueInfo] = []
    var recentCommits: [GitCommitInfo] = []

    // MARK: - File Tree (expandable)

    var treeNodes: [FileTreeNode] = []
    /// Cache of loaded children keyed by directory path.
    private var childrenCache: [String: [GitFileEntry]] = [:]

    // MARK: - File Viewer

    var viewingFile: GitFileEntry?
    var fileContent: String?
    var isLoadingFile: Bool = false

    // MARK: - Dependencies

    private let connectorStore = ConnectorStore.shared
    private let gitService = GitService.shared
    private let logger = Logger(label: "ai.mcclaw.git-panel")

    // MARK: - Computed

    var filteredRepos: [GitRepoInfo] {
        var result = repos

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        switch sortOrder {
        case .lastUpdated:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .name:
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .stars:
            result.sort { $0.starCount > $1.starCount }
        }

        return result
    }

    // MARK: - Actions

    /// Detect which Git platforms have connected connectors.
    func detectAvailablePlatforms() {
        availablePlatforms = GitPlatform.allCases.filter { platform in
            connectorStore.connectedInstances.contains { $0.definitionId == platform.connectorId }
        }

        // Auto-select first available if current is not available
        if !availablePlatforms.contains(selectedPlatform), let first = availablePlatforms.first {
            selectedPlatform = first
        }
    }

    /// Load repositories from the selected platform connector.
    func loadRepos() async {
        guard !isLoadingRepos else { return }
        isLoadingRepos = true
        loadError = nil

        defer { isLoadingRepos = false }

        let connectorId = selectedPlatform.connectorId
        guard let instance = connectorStore.connectedInstances.first(where: { $0.definitionId == connectorId }) else {
            loadError = String(localized: "No connected connector for \(selectedPlatform.displayName)", bundle: .module)
            return
        }

        do {
            let executor = ConnectorExecutor.shared
            let result = try await executor.execute(
                instanceId: instance.id,
                actionId: selectedPlatform == .github ? "list_repos" : "list_projects",
                params: ["sort": "updated", "format": "json"]
            )
            repos = parseRepos(from: result.data, platform: selectedPlatform)
            await matchLocalPaths()
        } catch {
            loadError = error.localizedDescription
            logger.error("Failed to load repos: \(error)")
        }
    }

    /// Select a repository: set context and open detail view.
    func selectRepo(_ repo: GitRepoInfo) {
        selectedRepo = repo
        selectedBranch = nil
        isShowingDetail = true
        treeNodes = []
        childrenCache = [:]
        viewingFile = nil
        fileContent = nil

        gitContext = GitContext(
            platform: selectedPlatform,
            repoFullName: repo.fullName,
            repoURL: repo.htmlURL,
            branch: repo.defaultBranch,
            localPath: repo.localPath
        )
    }

    /// Select a branch within the current repo.
    func selectBranch(_ branch: GitBranch) {
        selectedBranch = branch
        if var ctx = gitContext {
            ctx.branch = branch.name
            gitContext = ctx
        }
        // Reload file tree for the new branch
        treeNodes = []
        childrenCache = [:]
        viewingFile = nil
        fileContent = nil
        if let repo = selectedRepo {
            Task { await loadRootTree(repo: repo) }
        }
    }

    /// Clear the current selection.
    func clearSelection() {
        selectedRepo = nil
        selectedBranch = nil
        gitContext = nil
        isShowingDetail = false
        treeNodes = []
        childrenCache = [:]
        viewingFile = nil
        fileContent = nil
    }

    /// Open the detail view for a repo (called on single click).
    func showDetail(for repo: GitRepoInfo) {
        selectRepo(repo)
    }

    /// Go back from detail to repo list.
    func hideDetail() {
        isShowingDetail = false
        treeNodes = []
        childrenCache = [:]
        viewingFile = nil
        fileContent = nil
    }

    /// Toggle expand/collapse for a directory node; load children on first expand.
    func toggleDirectory(_ node: FileTreeNode) {
        if node.isExpanded {
            node.isExpanded = false
        } else {
            node.isExpanded = true
            if node.children == nil {
                node.isLoading = true
                Task { await loadDirectoryChildren(node) }
            }
        }
    }

    /// Select a file node to view its content.
    func selectFile(_ entry: GitFileEntry) {
        viewingFile = entry
        fileContent = nil
        isLoadingFile = true
        Task { await loadFileContent(entry) }
    }

    /// Close the file viewer.
    func closeFileViewer() {
        viewingFile = nil
        fileContent = nil
        isLoadingFile = false
    }

    /// Load detailed info for a repo (branches, PRs, issues, commits, files).
    func loadRepoDetail(_ repo: GitRepoInfo) async {
        // Reset
        branches = []
        pullRequests = []
        issues = []
        recentCommits = []
        treeNodes = []
        childrenCache = [:]

        let connectorId = selectedPlatform.connectorId
        guard let instance = connectorStore.connectedInstances.first(where: { $0.definitionId == connectorId }) else { return }
        let executor = ConnectorExecutor.shared

        let repoParam = selectedPlatform == .github ? "repo" : "projectId"
        let repoValue = selectedPlatform == .github ? repo.fullName : repo.id

        // Load all in parallel
        async let branchTask: Void = loadBranches(executor: executor, instanceId: instance.id, repoParam: repoParam, repoValue: repoValue, defaultBranch: repo.defaultBranch)
        async let fileTask: Void = loadRootTree(repo: repo)
        async let issueTask: Void = loadIssues(executor: executor, instanceId: instance.id, repoParam: repoParam, repoValue: repoValue)
        async let prTask: Void = loadPullRequests(executor: executor, instanceId: instance.id, repoParam: repoParam, repoValue: repoValue)
        async let commitTask: Void = loadCommits(executor: executor, instanceId: instance.id, repoParam: repoParam, repoValue: repoValue)

        _ = await (branchTask, fileTask, issueTask, prTask, commitTask)
    }

    /// Refresh everything.
    func refreshAll() async {
        detectAvailablePlatforms()
        await loadRepos()
    }

    // MARK: - Private Loaders

    private func loadBranches(executor: ConnectorExecutor, instanceId: String, repoParam: String, repoValue: String, defaultBranch: String) async {
        do {
            let result = try await executor.execute(
                instanceId: instanceId,
                actionId: "list_branches",
                params: [repoParam: repoValue, "format": "json"]
            )
            branches = parseBranches(from: result.data, defaultBranch: defaultBranch)
        } catch {
            logger.warning("Failed to load branches: \(error)")
        }
    }

    /// Load the root-level file tree for a repo.
    func loadRootTree(repo: GitRepoInfo) async {
        let entries = await fetchDirectoryEntries(repoFullName: repo.fullName, path: "")
        treeNodes = entries.map { FileTreeNode(entry: $0) }
        childrenCache[""] = entries
    }

    /// Load children of a directory node lazily.
    private func loadDirectoryChildren(_ node: FileTreeNode) async {
        guard let repo = selectedRepo else { node.isLoading = false; return }
        let path = node.entry.path
        let entries = await fetchDirectoryEntries(repoFullName: repo.fullName, path: path)
        childrenCache[path] = entries
        node.children = entries.map { FileTreeNode(entry: $0) }
        node.isLoading = false
    }

    /// Fetch directory entries from the API for a given path.
    private func fetchDirectoryEntries(repoFullName: String, path: String) async -> [GitFileEntry] {
        let connectorId = selectedPlatform.connectorId
        guard let instance = connectorStore.connectedInstances.first(where: { $0.definitionId == connectorId }) else { return [] }

        do {
            var params: [String: String] = ["repo": repoFullName, "path": path, "format": "json"]
            if let branch = selectedBranch {
                params["ref"] = branch.name
            }
            let result = try await ConnectorExecutor.shared.execute(
                instanceId: instance.id,
                actionId: "get_contents",
                params: params
            )
            return parseFileEntries(from: result.data)
        } catch {
            logger.warning("Failed to load directory \(path): \(error)")
            return []
        }
    }

    private func loadFileContent(_ entry: GitFileEntry) async {
        guard let repo = selectedRepo else { return }
        let connectorId = selectedPlatform.connectorId
        guard let instance = connectorStore.connectedInstances.first(where: { $0.definitionId == connectorId }) else {
            isLoadingFile = false
            return
        }

        do {
            var params: [String: String] = ["repo": repo.fullName, "path": entry.path, "format": "json"]
            if let branch = selectedBranch {
                params["ref"] = branch.name
            }
            let result = try await ConnectorExecutor.shared.execute(
                instanceId: instance.id,
                actionId: "get_contents",
                params: params
            )
            // GitHub returns a single object with "content" (base64) for files
            if let jsonData = result.data.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let base64Content = dict["content"] as? String {
                let cleaned = base64Content.replacingOccurrences(of: "\n", with: "")
                if let decoded = Data(base64Encoded: cleaned),
                   let text = String(data: decoded, encoding: .utf8) {
                    fileContent = text
                } else {
                    fileContent = String(localized: "Unable to decode file content", bundle: .module)
                }
            } else {
                fileContent = String(localized: "Unable to load file content", bundle: .module)
            }
        } catch {
            logger.warning("Failed to load file content: \(error)")
            fileContent = String(localized: "Error loading file", bundle: .module)
        }

        isLoadingFile = false
    }

    private func loadIssues(executor: ConnectorExecutor, instanceId: String, repoParam: String, repoValue: String) async {
        do {
            let result = try await executor.execute(
                instanceId: instanceId,
                actionId: selectedPlatform == .github ? "list_issues" : "list_issues",
                params: [repoParam: repoValue, "state": "open", "format": "json"]
            )
            issues = parseIssues(from: result.data)
        } catch {
            logger.warning("Failed to load issues: \(error)")
        }
    }

    private func loadPullRequests(executor: ConnectorExecutor, instanceId: String, repoParam: String, repoValue: String) async {
        do {
            let result = try await executor.execute(
                instanceId: instanceId,
                actionId: selectedPlatform == .github ? "list_prs" : "list_mrs",
                params: [repoParam: repoValue, "state": "open", "format": "json"]
            )
            pullRequests = parsePullRequests(from: result.data)
        } catch {
            logger.warning("Failed to load PRs: \(error)")
        }
    }

    private func loadCommits(executor: ConnectorExecutor, instanceId: String, repoParam: String, repoValue: String) async {
        do {
            let result = try await executor.execute(
                instanceId: instanceId,
                actionId: "list_commits",
                params: [repoParam: repoValue, "format": "json"]
            )
            recentCommits = parseCommits(from: result.data)
        } catch {
            logger.warning("Failed to load commits: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func matchLocalPaths() async {
        let localRepos = await gitService.findLocalRepos()
        for i in repos.indices {
            let cloneURL = repos[i].cloneURL.lowercased()
            if let local = localRepos.first(where: {
                guard let remote = $0.remoteURL else { return false }
                return cloneURL.contains(remote.lowercased().replacingOccurrences(of: ".git", with: ""))
                    || remote.lowercased().contains(repos[i].fullName.lowercased())
            }) {
                repos[i].localPath = local.path
            }
        }
    }

    // MARK: - Parsers

    private func parseRepos(from data: String, platform: GitPlatform) -> [GitRepoInfo] {
        guard let jsonData = data.data(using: .utf8) else { return [] }
        guard let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            logger.warning("Could not parse repos response as JSON array")
            return []
        }

        let decoder = ISO8601DateFormatter()
        decoder.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let decoderBasic = ISO8601DateFormatter()

        func parseDate(_ str: String?) -> Date {
            guard let str else { return Date.distantPast }
            return decoder.date(from: str) ?? decoderBasic.date(from: str) ?? Date.distantPast
        }

        return array.compactMap { dict -> GitRepoInfo? in
            if platform == .github {
                guard let id = dict["id"] as? Int,
                      let name = dict["name"] as? String,
                      let fullName = dict["full_name"] as? String else { return nil }
                return GitRepoInfo(
                    id: String(id),
                    name: name,
                    fullName: fullName,
                    description: dict["description"] as? String,
                    language: dict["language"] as? String,
                    isPrivate: dict["private"] as? Bool ?? false,
                    isFork: dict["fork"] as? Bool ?? false,
                    starCount: dict["stargazers_count"] as? Int ?? 0,
                    openIssueCount: dict["open_issues_count"] as? Int ?? 0,
                    openPRCount: 0,
                    defaultBranch: dict["default_branch"] as? String ?? "main",
                    updatedAt: parseDate(dict["updated_at"] as? String),
                    cloneURL: dict["clone_url"] as? String ?? "",
                    htmlURL: dict["html_url"] as? String ?? ""
                )
            } else {
                guard let id = dict["id"] as? Int,
                      let name = dict["name"] as? String else { return nil }
                let namespace = dict["path_with_namespace"] as? String ?? name
                return GitRepoInfo(
                    id: String(id),
                    name: name,
                    fullName: namespace,
                    description: dict["description"] as? String,
                    language: nil,
                    isPrivate: (dict["visibility"] as? String) == "private",
                    isFork: dict["forked_from_project"] != nil,
                    starCount: dict["star_count"] as? Int ?? 0,
                    openIssueCount: dict["open_issues_count"] as? Int ?? 0,
                    openPRCount: 0,
                    defaultBranch: dict["default_branch"] as? String ?? "main",
                    updatedAt: parseDate(dict["last_activity_at"] as? String),
                    cloneURL: dict["http_url_to_repo"] as? String ?? "",
                    htmlURL: dict["web_url"] as? String ?? ""
                )
            }
        }
    }

    private func parseBranches(from data: String, defaultBranch: String) -> [GitBranch] {
        guard let jsonData = data.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else { return [] }

        return array.compactMap { dict -> GitBranch? in
            guard let name = dict["name"] as? String else { return nil }
            let isProtected = dict["protected"] as? Bool ?? false
            return GitBranch(
                name: name,
                isDefault: name == defaultBranch,
                isProtected: isProtected,
                aheadBehind: nil
            )
        }
    }

    private func parseFileEntries(from data: String) -> [GitFileEntry] {
        guard let jsonData = data.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else { return [] }

        return array.compactMap { dict -> GitFileEntry? in
            guard let name = dict["name"] as? String,
                  let path = dict["path"] as? String,
                  let typeStr = dict["type"] as? String else { return nil }

            let type: GitFileEntry.FileType
            switch typeStr {
            case "dir": type = .dir
            case "file": type = .file
            case "symlink": type = .symlink
            case "submodule": type = .submodule
            default: type = .file
            }

            return GitFileEntry(
                name: name,
                path: path,
                type: type,
                size: dict["size"] as? Int ?? 0,
                sha: dict["sha"] as? String ?? ""
            )
        }
    }

    private func parseIssues(from data: String) -> [GitIssueInfo] {
        guard let jsonData = data.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else { return [] }

        let decoder = ISO8601DateFormatter()
        decoder.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let decoderBasic = ISO8601DateFormatter()

        func parseDate(_ str: String?) -> Date {
            guard let str else { return Date.distantPast }
            return decoder.date(from: str) ?? decoderBasic.date(from: str) ?? Date.distantPast
        }

        return array.compactMap { dict -> GitIssueInfo? in
            // Skip pull requests (GitHub returns PRs in issues endpoint)
            if dict["pull_request"] != nil { return nil }

            guard let number = dict["number"] as? Int,
                  let title = dict["title"] as? String else { return nil }

            let user = dict["user"] as? [String: Any]
            let author = user?["login"] as? String ?? ""
            let state = dict["state"] as? String ?? "open"
            let labelArray = dict["labels"] as? [[String: Any]] ?? []
            let labels = labelArray.compactMap { $0["name"] as? String }
            let assigneeArray = dict["assignees"] as? [[String: Any]] ?? []
            let assignees = assigneeArray.compactMap { $0["login"] as? String }

            return GitIssueInfo(
                id: String(number),
                number: number,
                title: title,
                author: author,
                state: state,
                labels: labels,
                assignees: assignees,
                createdAt: parseDate(dict["created_at"] as? String)
            )
        }
    }

    private func parsePullRequests(from data: String) -> [GitPRInfo] {
        guard let jsonData = data.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else { return [] }

        let decoder = ISO8601DateFormatter()
        decoder.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let decoderBasic = ISO8601DateFormatter()

        func parseDate(_ str: String?) -> Date {
            guard let str else { return Date.distantPast }
            return decoder.date(from: str) ?? decoderBasic.date(from: str) ?? Date.distantPast
        }

        return array.compactMap { dict -> GitPRInfo? in
            guard let number = dict["number"] as? Int,
                  let title = dict["title"] as? String else { return nil }

            let user = dict["user"] as? [String: Any]
            let author = user?["login"] as? String ?? ""
            let state = dict["state"] as? String ?? "open"
            let head = dict["head"] as? [String: Any]
            let base = dict["base"] as? [String: Any]
            let sourceBranch = head?["ref"] as? String ?? ""
            let targetBranch = base?["ref"] as? String ?? ""

            return GitPRInfo(
                id: String(number),
                number: number,
                title: title,
                author: author,
                state: state,
                sourceBranch: sourceBranch,
                targetBranch: targetBranch,
                reviewState: nil,
                createdAt: parseDate(dict["created_at"] as? String),
                updatedAt: parseDate(dict["updated_at"] as? String)
            )
        }
    }

    private func parseCommits(from data: String) -> [GitCommitInfo] {
        guard let jsonData = data.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else { return [] }

        let decoder = ISO8601DateFormatter()
        decoder.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let decoderBasic = ISO8601DateFormatter()

        func parseDate(_ str: String?) -> Date {
            guard let str else { return Date.distantPast }
            return decoder.date(from: str) ?? decoderBasic.date(from: str) ?? Date.distantPast
        }

        return array.compactMap { dict -> GitCommitInfo? in
            guard let sha = dict["sha"] as? String else { return nil }
            let commit = dict["commit"] as? [String: Any] ?? [:]
            let message = commit["message"] as? String ?? ""
            let authorObj = commit["author"] as? [String: Any] ?? [:]
            let author = authorObj["name"] as? String ?? ""
            let dateStr = authorObj["date"] as? String

            return GitCommitInfo(
                id: sha,
                shortSha: String(sha.prefix(7)),
                message: message.components(separatedBy: "\n").first ?? message,
                author: author,
                date: parseDate(dateStr)
            )
        }
    }
}
