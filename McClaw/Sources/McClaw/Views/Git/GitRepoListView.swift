import SwiftUI

/// Repository list with search, sort, and selection.
struct GitRepoListView: View {
    @Bindable var viewModel: GitPanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search + Sort bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.callout)
                    TextField(
                        String(localized: "Search repositories…", bundle: .appModule),
                        text: $viewModel.searchText
                    )
                    .textFieldStyle(.plain)
                    .font(.callout)

                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Menu {
                    ForEach(GitSortOrder.allCases, id: \.self) { order in
                        Button {
                            viewModel.sortOrder = order
                        } label: {
                            HStack {
                                Text(sortLabel(order))
                                if viewModel.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 14)

            // Repo count
            if !viewModel.isLoadingRepos && viewModel.loadError == nil && !viewModel.filteredRepos.isEmpty {
                HStack {
                    Text(String(localized: "git_repo_count \(viewModel.filteredRepos.count)", bundle: .appModule))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            // Content
            if viewModel.isLoadingRepos {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading repositories…", bundle: .appModule)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.loadError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "Retry", bundle: .appModule)) {
                        Task { await viewModel.loadRepos() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredRepos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(viewModel.searchText.isEmpty
                         ? String(localized: "No repositories found", bundle: .appModule)
                         : String(localized: "No matching repositories", bundle: .appModule))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.filteredRepos) { repo in
                            GitRepoRow(
                                repo: repo,
                                isSelected: viewModel.selectedRepo?.id == repo.id
                            )
                            .onTapGesture(count: 2) {
                                viewModel.showDetail(for: repo)
                            }
                            .onTapGesture {
                                viewModel.selectRepo(repo)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func sortLabel(_ order: GitSortOrder) -> String {
        switch order {
        case .lastUpdated: return String(localized: "Last updated", bundle: .appModule)
        case .name: return String(localized: "Name", bundle: .appModule)
        case .stars: return String(localized: "Stars", bundle: .appModule)
        }
    }
}
