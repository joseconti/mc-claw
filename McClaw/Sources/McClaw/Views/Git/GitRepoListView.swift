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
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    TextField(
                        String(localized: "Search repositories…", bundle: .module),
                        text: $viewModel.searchText
                    )
                    .textFieldStyle(.plain)
                    .font(.callout)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 12)

            // Repo list
            if viewModel.isLoadingRepos {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading repositories…", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "Retry", bundle: .module)) {
                        Task { await viewModel.loadRepos() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredRepos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(viewModel.searchText.isEmpty
                         ? String(localized: "No repositories found", bundle: .module)
                         : String(localized: "No matching repositories", bundle: .module))
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
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func sortLabel(_ order: GitSortOrder) -> String {
        switch order {
        case .lastUpdated: return String(localized: "Last updated", bundle: .module)
        case .name: return String(localized: "Name", bundle: .module)
        case .stars: return String(localized: "Stars", bundle: .module)
        }
    }
}
