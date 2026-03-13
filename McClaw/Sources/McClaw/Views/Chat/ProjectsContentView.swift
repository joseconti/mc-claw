import AppKit
import McClawKit
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
    @State private var showMemorySheet = false
    @State private var memoryStore = ProjectMemoryStore.shared
    @State private var artifactStore = ProjectArtifactStore.shared
    @Namespace private var cliSelectorNamespace

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
                            .liquidGlassCapsule()
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
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    showMemorySheet = true
                } label: {
                    Label(String(localized: "Memory", bundle: .module), systemImage: "brain")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .sheet(isPresented: $showMemorySheet) {
                    ProjectMemorySheet(projectId: projectId)
                        .environment(appState)
                }

                Button {
                    editingProjectId = projectId
                } label: {
                    Label(String(localized: "Edit", bundle: .module), systemImage: "pencil")
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
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    Text(String(localized: "Project rules active (\(rules.count) chars)", bundle: .module))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            }

            // Memory badge
            if memoryStore.memorySize(for: projectId) > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    Text(String(localized: "Project memory active (\(memoryStore.formattedMemorySize(for: projectId)))", bundle: .module))
                        .font(.subheadline)
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

            // Two-column layout: conversations on left, artifacts on right
            HStack(alignment: .top, spacing: 0) {
                // Left column: files + conversations
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
                .frame(maxWidth: .infinity)

                Divider()

                // Right column: artifacts
                ScrollView {
                    projectArtifactsSection(projectId: projectId)
                }
                .frame(width: 280)
                .background(.quaternary.opacity(0.15))
            }
        }
        .onAppear {
            artifactStore.refresh(for: projectId)
        }
    }

    // MARK: - Project Artifacts Section

    @ViewBuilder
    private func projectArtifactsSection(projectId: String) -> some View {
        let artifacts = artifactStore.currentProjectId == projectId
            ? artifactStore.currentArtifacts
            : []

        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack {
                Text(String(localized: "Artifacts", bundle: .module))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)

                if !artifacts.isEmpty {
                    Text("\(artifacts.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.7))
                        .clipShape(Capsule())
                }

                Spacer()

                // Upload artifact button
                Button {
                    importArtifactToProject(projectId: projectId)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if artifacts.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "No artifacts yet", bundle: .module))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Plans and documents created by AI will appear here. You can also upload files manually.", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    Button {
                        importArtifactToProject(projectId: projectId)
                    } label: {
                        Label(String(localized: "Upload Artifact", bundle: .module), systemImage: "arrow.up.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
            } else {
                // Artifacts list
                VStack(spacing: 2) {
                    ForEach(artifacts) { artifact in
                        Button {
                            let fileURL = artifactStore.artifactFileURL(artifact, projectId: projectId)
                            withAnimation(.snappy(duration: 0.25)) {
                                appState.openPlanFilePath = fileURL.path
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: artifact.iconName)
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                                    .frame(width: 26, height: 26)
                                    .background(.orange.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(artifact.fileName.replacingOccurrences(of: ".md", with: ""))
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        if let cli = artifact.sourceCLI {
                                            Text(cli.capitalized)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(artifact.createdAt, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                let url = artifactStore.artifactFileURL(artifact, projectId: projectId)
                                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                            } label: {
                                Label(String(localized: "Show in Finder", bundle: .module), systemImage: "folder")
                            }

                            Button {
                                if let content = artifactStore.loadContent(artifact, projectId: projectId) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(content, forType: .string)
                                }
                            } label: {
                                Label(String(localized: "Copy Content", bundle: .module), systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button(role: .destructive) {
                                artifactStore.removeArtifact(id: artifact.id, fromProject: projectId)
                            } label: {
                                Label(String(localized: "Remove from Project", bundle: .module), systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func importArtifactToProject(projectId: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .json, .yaml, .xml, .html, .sourceCode]
        panel.message = String(localized: "Select files to add as project artifacts", bundle: .module)

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            artifactStore.addArtifact(
                from: url,
                fileName: url.lastPathComponent,
                type: .document,
                toProject: projectId
            )
        }
    }

    // MARK: - Project Chat Input Bar

    @ViewBuilder
    private func projectChatInputBar(projectId: String) -> some View {
        ChatInputBar(
            onSend: { text, attachments in
                startNewChatInProject(projectId: projectId, text: text)
            },
            onAbort: { },
            isWorking: false,
            onImageGenerate: { prompt in
                appState.pendingImagePrompt = prompt
                startNewChatInProject(projectId: projectId)
            },
            onInstallPrompt: { prompt in
                appState.pendingInstallPrompt = prompt
                startNewChatInProject(projectId: projectId)
            }
        )
        .environment(appState)
    }

    // MARK: - CLI Selector

    @ViewBuilder
    private var projectCLISelector: some View {
        let installedCLIs = appState.installedAIProviders
        if installedCLIs.count > 1 {
            HStack(spacing: 0) {
                ForEach(installedCLIs) { cli in
                    let isSelected = cli.id == appState.currentCLIIdentifier
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            appState.currentCLIIdentifier = cli.id
                        }
                        Task { await ConfigStore.shared.saveFromState() }
                        // Auto-start BitNet server when selected (on-demand mode)
                        if cli.id == "bitnet", !appState.bitnetAlwaysOn {
                            Task {
                                let server = BitNetServerManager.shared
                                if await !server.isRunning {
                                    let model = appState.bitnetDefaultModel ?? BitNetKit.defaultModel?.modelId ?? "BitNet-b1.58-2B-4T"
                                    let serverConfig = BitNetKit.ServerConfig(
                                        port: appState.bitnetServerPort,
                                        threads: appState.bitnetThreads,
                                        contextSize: appState.bitnetContextSize,
                                        maxTokens: appState.bitnetMaxTokens,
                                        temperature: appState.bitnetTemperature
                                    )
                                    try? await server.start(model: model, config: serverConfig, trackIdle: true)
                                } else {
                                    await server.touch()
                                }
                            }
                        }
                    } label: {
                        Text(cli.displayName)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.35))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                                        )
                                        .matchedGeometryEffect(id: "cliPill", in: cliSelectorNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.quaternary.opacity(0.5))
            .clipShape(Capsule())
            .liquidGlassCapsule()
        } else if let cli = appState.currentCLI {
            Text(cli.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func startNewChatInProject(projectId: String, text: String? = nil) {
        let message = text ?? ""

        // Create new session and assign to project
        let newSessionId = UUID().uuidString

        // Assign to project first
        projectStore.addSession(newSessionId, toProject: projectId)

        // Store the message text — DO NOT set currentSessionId here,
        // let onNewChatInProject handle it to avoid double-VM creation.
        if !message.isEmpty {
            appState.pendingMessage = message
        }

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
                            .font(.subheadline.weight(.medium))
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
                .mcclawTextField()
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
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.subheadline)
                            Text("\(sessionCount)")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)

                        if !project.rules.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "brain.head.profile")
                                    .font(.subheadline)
                                Text("Rules")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(Color.accentColor.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                            .liquidGlassCapsule(interactive: false)
                        }

                        Spacer()

                        Text(project.updatedAt, style: .relative)
                            .font(.subheadline)
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
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(file.formattedSize)
                .font(.subheadline)
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
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.quaternary)
                                .clipShape(Capsule())
                                .liquidGlassCapsule(interactive: false)
                        }

                        Text("\(session.messageCount) message\(session.messageCount == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)

                        Text(session.lastMessageAt, style: .relative)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
