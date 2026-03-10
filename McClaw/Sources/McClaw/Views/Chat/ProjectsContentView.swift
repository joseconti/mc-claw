import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Main content view showing projects grid, project detail, and project editor.
struct ProjectsContentView: View {
    @Binding var currentSection: SidebarSection
    let onSelectSession: (SessionInfo) -> Void
    let onDeleteSession: (String) -> Void
    /// Called when user starts a new chat from within a project.
    /// Returns the new session ID so we can assign it to the project.
    let onNewChatInProject: (String) -> Void

    @Environment(AppState.self) private var appState
    @State private var sessionStore = SessionStore.shared
    @State private var projectStore = ProjectStore.shared
    @State private var projectFileStore = ProjectFileStore.shared
    @State private var showNewProjectSheet = false
    @State private var newProjectName = ""
    @State private var editingProjectId: String?
    @State private var newChatText = ""

    var body: some View {
        Group {
            if let editId = editingProjectId {
                ProjectEditorView(projectId: editId) {
                    editingProjectId = nil
                }
            } else if case .projectDetail(let projectId) = currentSection {
                projectDetailView(projectId: projectId)
            } else {
                projectsGridView
            }
        }
        .sheet(isPresented: $showNewProjectSheet) {
            newProjectSheet
        }
    }

    // MARK: - Projects Grid

    @ViewBuilder
    private var projectsGridView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projects")
                        .font(.title.weight(.bold))
                    Text("\(projectStore.projects.count) project\(projectStore.projects.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    newProjectName = ""
                    showNewProjectSheet = true
                } label: {
                    Label("New Project", systemImage: "plus")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 24)

            // Grid of projects
            ScrollView {
                if projectStore.projects.isEmpty {
                    emptyProjectsView
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(projectStore.projects) { project in
                            ProjectCard(
                                project: project,
                                sessionCount: sessionStore.sessions(forProject: project.id).count,
                                coverImage: projectStore.loadCoverImage(for: project)
                            ) {
                                currentSection = .projectDetail(project.id)
                            }
                            .contextMenu {
                                Button {
                                    editingProjectId = project.id
                                } label: {
                                    Label("Edit Project", systemImage: "pencil")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    projectStore.delete(projectId: project.id)
                                    sessionStore.refreshIndex()
                                } label: {
                                    Label("Delete Project", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyProjectsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No projects yet")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Create a project to organize your conversations into groups.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button {
                newProjectName = ""
                showNewProjectSheet = true
            } label: {
                Label("Create Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Project Detail

    @ViewBuilder
    private func projectDetailView(projectId: String) -> some View {
        let project = projectStore.projects.first { $0.id == projectId }
        let projectSessions = sessionStore.sessions(forProject: projectId)

        VStack(spacing: 0) {
            // Cover image header
            if let project, let img = projectStore.loadCoverImage(for: project) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        Button {
                            currentSection = .projects
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.medium))
                                Text("Projects")
                                    .font(.body)
                            }
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                    }
            } else {
                // No cover image — simple header
                HStack {
                    Button {
                        currentSection = .projects
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.medium))
                            Text("Projects")
                                .font(.body)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project?.name ?? "Project")
                        .font(.title.weight(.bold))

                    if let desc = project?.description, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text("\(projectSessions.count) conversation\(projectSessions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    editingProjectId = projectId
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)

            // Rules badge
            if let rules = project?.rules, !rules.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text("Project rules active (\(rules.count) chars)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            }

            // CLI selector
            projectCLISelector
                .padding(.horizontal, 32)
                .padding(.bottom, 4)

            // New chat input bar
            projectChatInputBar(projectId: projectId)

            Divider()
                .padding(.horizontal, 24)

            // Scrollable content: files + conversations
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Project files section
                    projectFilesSection(projectId: projectId)

                    // Conversations section
                    if projectSessions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            Text("No conversations yet")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Text("Type a message above to start a new conversation in this project.")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 340)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        // Section header
                        HStack {
                            Text("Conversations")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(projectSessions) { session in
                                SessionListRow(session: session) {
                                    currentSection = .chats
                                    onSelectSession(session)
                                }
                                .contextMenu {
                                    Button {
                                        projectStore.removeSession(session.id, fromProject: projectId)
                                        sessionStore.refreshIndex()
                                    } label: {
                                        Label("Remove from Project", systemImage: "folder.badge.minus")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        if let pid = session.projectId {
                                            projectStore.removeSession(session.id, fromProject: pid)
                                        }
                                        sessionStore.delete(sessionId: session.id)
                                        onDeleteSession(session.id)
                                    } label: {
                                        Label("Move to Trash", systemImage: "trash")
                                    }
                                }

                                if session.id != projectSessions.last?.id {
                                    Divider()
                                        .padding(.horizontal, 32)
                                }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
        }
    }

    // MARK: - Project Chat Input Bar

    @ViewBuilder
    private func projectChatInputBar(projectId: String) -> some View {
        VStack(spacing: 0) {
            // Text input area — uses MultiLineTextInput (Enter sends, Shift+Enter newline)
            MultiLineTextInput(
                text: $newChatText,
                placeholder: "Start a new conversation...",
                font: .systemFont(ofSize: 16),
                minHeight: 80,
                maxHeight: 200,
                onSubmit: { startNewChatInProject(projectId: projectId) }
            )
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 16)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            // Bottom row: attach on left, send on right
            HStack(spacing: 8) {
                // Attach file button
                Button {
                    addFilesToProject(projectId: projectId)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Add files to project")

                Spacer()

                // Send button
                Button {
                    startNewChatInProject(projectId: projectId)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            newChatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.gray.opacity(0.2)
                                : Color.accentColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(newChatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: NSColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0)))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color(nsColor: NSColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1.0)), lineWidth: 1)
                }
        }
        .frame(maxWidth: 780)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - CLI Selector

    @ViewBuilder
    private var projectCLISelector: some View {
        let installedCLIs = appState.availableCLIs.filter(\.isInstalled)
        if installedCLIs.count > 1 {
            HStack(spacing: 0) {
                ForEach(installedCLIs) { cli in
                    let isSelected = cli.id == appState.currentCLIIdentifier
                    Button {
                        appState.currentCLIIdentifier = cli.id
                        Task { await ConfigStore.shared.saveFromState() }
                    } label: {
                        Text(cli.displayName)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                isSelected
                                    ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                                    : AnyShapeStyle(Color.clear)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.quaternary.opacity(0.5))
            .clipShape(Capsule())
        } else if let cli = appState.currentCLI {
            Text(cli.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func startNewChatInProject(projectId: String) {
        let text = newChatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Create new session and assign to project
        let newSessionId = UUID().uuidString

        // Assign to project first
        projectStore.addSession(newSessionId, toProject: projectId)

        // Store the message text — DO NOT set currentSessionId here,
        // let onNewChatInProject handle it to avoid double-VM creation.
        appState.pendingMessage = text

        newChatText = ""

        // Navigate to chats and trigger the new chat creation
        currentSection = .chats
        onNewChatInProject(newSessionId)
    }

    // MARK: - Project Files Section

    @ViewBuilder
    private func projectFilesSection(projectId: String) -> some View {
        let files = projectFileStore.listFiles(for: projectId)

        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Files")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        addFilesToProject(projectId: projectId)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)

                // Files grid
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(files) { file in
                        ProjectFileCard(file: file)
                            .contextMenu {
                                Button {
                                    NSWorkspace.shared.selectFile(
                                        file.path,
                                        inFileViewerRootedAtPath: ""
                                    )
                                } label: {
                                    Label("Show in Finder", systemImage: "folder")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    projectFileStore.removeFile(name: file.name, fromProject: projectId)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 32)

                Divider()
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
        }
    }

    private func addFilesToProject(projectId: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.item]
        panel.message = "Select files to add to the project. ZIP files will be extracted automatically."

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            projectFileStore.addFile(from: url, toProject: projectId)
        }
    }

    // MARK: - New Project Sheet

    @ViewBuilder
    private var newProjectSheet: some View {
        VStack(spacing: 16) {
            Text("New Project")
                .font(.headline)

            TextField("Project name", text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit {
                    commitNewProject()
                }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showNewProjectSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    commitNewProject()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }

    private func commitNewProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let project = projectStore.create(name: name)
        showNewProjectSheet = false
        // Open the editor immediately for the new project
        editingProjectId = project.id
    }
}

// MARK: - Project Card

private struct ProjectCard: View {
    let project: ProjectInfo
    let sessionCount: Int
    let coverImage: NSImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Cover image or gradient
                if let img = coverImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 100)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 80)
                        .overlay {
                            Image(systemName: "folder.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !project.description.isEmpty {
                        Text(project.description)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.caption2)
                            Text("\(sessionCount)")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)

                        if !project.rules.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "brain.head.profile")
                                    .font(.caption2)
                                Text("Rules")
                                    .font(.caption2)
                            }
                            .foregroundStyle(Color.accentColor.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        Text(project.updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
            }
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Generate stable gradient colors based on the project ID.
    private var gradientColors: [Color] {
        let hash = project.id.hashValue
        let hue1 = Double(abs(hash) % 360) / 360.0
        let hue2 = (hue1 + 0.15).truncatingRemainder(dividingBy: 1.0)
        return [
            Color(hue: hue1, saturation: 0.5, brightness: 0.7),
            Color(hue: hue2, saturation: 0.6, brightness: 0.6)
        ]
    }
}

// MARK: - Session List Row (shared with Trash)

// MARK: - Project File Card

private struct ProjectFileCard: View {
    let file: ProjectFile

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: file.iconName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(height: 28)

            Text(file.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(file.formattedSize)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(.quaternary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }
}

// MARK: - Session List Row (shared with Trash)

struct SessionListRow: View {
    let session: SessionInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.body)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let provider = session.cliProvider {
                            Text(provider.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }

                        Text("\(session.messageCount) message\(session.messageCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Text(session.lastMessageAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
