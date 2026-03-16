import SwiftUI

/// Sheet that lets users pick a repo from their connected Git platforms (GitHub, GitLab)
/// to associate with a project.
struct GitRepoPickerSheet: View {
    let onSelect: (GitRepoInfo) -> Void
    let onBrowseLocal: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var connectorStore = ConnectorStore.shared
    @State private var selectedPlatform: GitPlatform = .github
    @State private var availablePlatforms: [GitPlatform] = []
    @State private var repos: [GitRepoInfo] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(String(localized: "project_select_repo_title", bundle: .appModule))
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if availablePlatforms.isEmpty {
                // No connected platforms
                noPlatformsView
            } else {
                // Platform picker + repo list
                VStack(spacing: 0) {
                    // Platform selector
                    if availablePlatforms.count > 1 {
                        Picker("", selection: $selectedPlatform) {
                            ForEach(availablePlatforms) { platform in
                                Text(platform.displayName).tag(platform)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .onChange(of: selectedPlatform) {
                            Task { await loadRepos() }
                        }
                    }

                    // Search bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.tertiary)
                        TextField(String(localized: "project_repo_search_placeholder", bundle: .appModule), text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                    .padding(.vertical, 6)

                    Divider()

                    // Content
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .controlSize(.regular)
                        Spacer()
                    } else if let error = loadError {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        Spacer()
                    } else if filteredRepos.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text(String(localized: "project_repo_no_results", bundle: .appModule))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    } else {
                        repoListView
                    }
                }
            }

            Divider()

            // Footer — browse local option
            HStack {
                Button {
                    dismiss()
                    // Small delay so sheet dismisses before panel opens
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onBrowseLocal()
                    }
                } label: {
                    Label(String(localized: "project_browse_local_repo", bundle: .appModule), systemImage: "folder")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button(String(localized: "Cancel", bundle: .appModule)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 500, height: 480)
        .onAppear {
            detectPlatforms()
            if !availablePlatforms.isEmpty {
                Task { await loadRepos() }
            }
        }
    }

    // MARK: - Repo List

    private var repoListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredRepos) { repo in
                    repoPickerRow(repo)
                    if repo.id != filteredRepos.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func repoPickerRow(_ repo: GitRepoInfo) -> some View {
        Button {
            onSelect(repo)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(repo.isPrivate ? .orange : .blue)
                    .frame(width: 28, height: 28)
                    .background(repo.isPrivate ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(repo.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)

                        if repo.isFork {
                            Image(systemName: "tuningfork")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(repo.fullName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        if let lang = repo.language {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(languageColor(lang))
                                    .frame(width: 6, height: 6)
                                Text(lang)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                if repo.localPath != nil {
                    Image(systemName: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .help(String(localized: "Cloned locally", bundle: .appModule))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - No Platforms

    private var noPlatformsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(String(localized: "project_no_git_platforms", bundle: .appModule))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(String(localized: "project_no_git_platforms_hint", bundle: .appModule))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Logic

    private var filteredRepos: [GitRepoInfo] {
        if searchText.isEmpty { return repos }
        return repos.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.fullName.localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private func detectPlatforms() {
        availablePlatforms = GitPlatform.allCases.filter { platform in
            connectorStore.connectedInstances.contains { $0.definitionId == platform.connectorId }
        }
        if let first = availablePlatforms.first {
            selectedPlatform = first
        }
    }

    private func loadRepos() async {
        isLoading = true
        loadError = nil
        repos = []

        let connectorId = selectedPlatform.connectorId
        guard let instance = connectorStore.connectedInstances.first(where: { $0.definitionId == connectorId }) else {
            loadError = String(localized: "No connected connector for \(selectedPlatform.displayName)", bundle: .appModule)
            isLoading = false
            return
        }

        do {
            let result = try await ConnectorExecutor.shared.execute(
                instanceId: instance.id,
                actionId: selectedPlatform == .github ? "list_repos" : "list_projects",
                params: ["sort": "updated", "format": "json"]
            )
            repos = parseRepos(from: result.data, platform: selectedPlatform)
            await matchLocalPaths()
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    private func matchLocalPaths() async {
        let localRepos = await GitService.shared.findLocalRepos()
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

    // MARK: - Parsers (same logic as GitPanelViewModel)

    private func parseRepos(from data: String, platform: GitPlatform) -> [GitRepoInfo] {
        guard let jsonData = data.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else { return [] }

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
                    id: String(id), name: name, fullName: fullName,
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
                    id: String(id), name: name, fullName: namespace,
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

    private func languageColor(_ language: String) -> Color {
        switch language.lowercased() {
        case "swift": return .orange
        case "python": return .blue
        case "javascript", "typescript": return .yellow
        case "rust": return .brown
        case "go": return .cyan
        case "ruby": return .red
        case "java", "kotlin": return .purple
        case "c", "c++", "c#": return .gray
        case "php": return .indigo
        case "html", "css": return .pink
        default: return .secondary
        }
    }
}
