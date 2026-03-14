import SwiftUI

/// Expandable file tree sidebar (like GitHub / Finder).
/// Directories expand inline to show their children; files are selectable.
struct GitFileTreeView: View {
    let nodes: [FileTreeNode]
    let selectedFilePath: String?
    let onToggleDir: (FileTreeNode) -> Void
    let onSelectFile: (GitFileEntry) -> Void
    var onSendToChat: ((String) -> Void)?

    var body: some View {
        if nodes.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading…", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedNodes(nodes)) { node in
                        FileTreeNodeRow(
                            node: node,
                            depth: 0,
                            selectedFilePath: selectedFilePath,
                            onToggleDir: onToggleDir,
                            onSelectFile: onSelectFile,
                            onSendToChat: onSendToChat
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func sortedNodes(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
        let dirs = nodes.filter { $0.entry.type == .dir }.sorted { $0.entry.name.localizedCompare($1.entry.name) == .orderedAscending }
        let files = nodes.filter { $0.entry.type != .dir }.sorted { $0.entry.name.localizedCompare($1.entry.name) == .orderedAscending }
        return dirs + files
    }
}

// MARK: - Recursive Node Row

/// A single row in the tree, with recursive children rendered via `ForEach`.
/// Broken out as its own struct to avoid opaque-return-type recursion issues.
private struct FileTreeNodeRow: View {
    @Bindable var node: FileTreeNode
    let depth: Int
    let selectedFilePath: String?
    let onToggleDir: (FileTreeNode) -> Void
    let onSelectFile: (GitFileEntry) -> Void
    var onSendToChat: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            rowButton
            if node.entry.type == .dir, node.isExpanded {
                ForEach(node.sortedChildren) { child in
                    FileTreeNodeRow(
                        node: child,
                        depth: depth + 1,
                        selectedFilePath: selectedFilePath,
                        onToggleDir: onToggleDir,
                        onSelectFile: onSelectFile,
                        onSendToChat: onSendToChat
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var rowButton: some View {
        let isDir = node.entry.type == .dir
        let isSelected = node.entry.path == selectedFilePath

        Button {
            if isDir {
                onToggleDir(node)
            } else {
                onSelectFile(node.entry)
            }
        } label: {
            HStack(spacing: 4) {
                // Indentation
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth) * 16)
                }

                // Disclosure indicator for directories
                if isDir {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                } else {
                    Spacer()
                        .frame(width: 12)
                }

                // Icon
                Image(systemName: FileTreeIcons.iconName(for: node.entry))
                    .font(.system(size: 13))
                    .foregroundStyle(FileTreeIcons.iconColor(for: node.entry))
                    .frame(width: 16)

                // Name
                Text(node.entry.name)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer()

                // Loading indicator for expanding dirs
                if node.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if node.entry.type == .file, let sendToChat = onSendToChat {
                Button {
                    sendToChat(GitPromptTemplates.explainFile(node.entry.path))
                } label: {
                    Label(String(localized: "git_action_explain_file", bundle: .module), systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    sendToChat(GitPromptTemplates.findUsagesFile(node.entry.path))
                } label: {
                    Label(String(localized: "git_action_find_usages", bundle: .module), systemImage: "magnifyingglass")
                }

                Button {
                    sendToChat(GitPromptTemplates.suggestImprovementsFile(node.entry.path))
                } label: {
                    Label(String(localized: "git_action_suggest_improvements_file", bundle: .module), systemImage: "lightbulb")
                }

                Button {
                    sendToChat(GitPromptTemplates.writeTestsFile(node.entry.path))
                } label: {
                    Label(String(localized: "git_action_write_tests", bundle: .module), systemImage: "checkmark.shield")
                }
            }
        }
    }
}

// MARK: - Shared Icons

enum FileTreeIcons {
    static func iconName(for entry: GitFileEntry) -> String {
        switch entry.type {
        case .dir: return "folder.fill"
        case .symlink: return "link"
        case .submodule: return "shippingbox"
        case .file:
            let ext = (entry.name as NSString).pathExtension.lowercased()
            switch ext {
            case "swift": return "swift"
            case "js", "ts", "jsx", "tsx": return "curlybraces"
            case "py": return "chevron.left.forwardslash.chevron.right"
            case "md", "txt", "rst": return "doc.text"
            case "json", "yaml", "yml", "toml", "xml", "plist": return "gearshape"
            case "png", "jpg", "jpeg", "gif", "svg", "ico", "webp": return "photo"
            case "sh", "bash", "zsh": return "terminal"
            case "css", "scss", "less": return "paintbrush"
            case "html", "htm": return "globe"
            case "lock": return "lock"
            case "gitignore", "gitattributes": return "arrow.triangle.branch"
            case "rb": return "diamond"
            case "go": return "chevron.left.forwardslash.chevron.right"
            case "rs": return "gearshape.2"
            case "c", "cpp", "h", "hpp": return "c.square"
            case "java", "kt": return "cup.and.saucer"
            case "php": return "server.rack"
            default: return "doc"
            }
        }
    }

    static func iconColor(for entry: GitFileEntry) -> Color {
        switch entry.type {
        case .dir: return .blue
        case .symlink: return .purple
        case .submodule: return .orange
        case .file:
            let ext = (entry.name as NSString).pathExtension.lowercased()
            switch ext {
            case "swift": return .orange
            case "js", "jsx": return .yellow
            case "ts", "tsx": return .blue
            case "py": return .green
            case "rb": return .red
            case "go": return .cyan
            case "rs": return .orange
            case "php": return .indigo
            case "html", "htm": return .orange
            case "css", "scss", "less": return .purple
            default: return .secondary
            }
        }
    }
}
