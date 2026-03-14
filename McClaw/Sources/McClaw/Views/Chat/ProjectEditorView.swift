import SwiftUI

/// Full project editor shown in the main content area.
/// Allows editing title, description, rules, and generating a cover image.
struct ProjectEditorView: View {
    let projectId: String
    let onDismiss: () -> Void

    @State private var projectStore = ProjectStore.shared
    @State private var sessionStore = SessionStore.shared
    @State private var name = ""
    @State private var description = ""
    @State private var rules = ""
    @State private var directories: [String] = []
    @State private var coverImage: NSImage?
    @State private var isGeneratingImage = false
    @State private var hasChanges = false

    var body: some View {
        VStack(spacing: 0) {
            // Header — outside scroll so buttons always respond
            HStack {
                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                        Text("Back", bundle: .module)
                            .font(.body)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                Spacer()

                if hasChanges {
                    Button("Save") {
                        saveProject()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Cover image
                    coverImageSection
                        .padding(.horizontal, 32)
                    .padding(.bottom, 24)

                // Form fields
                VStack(alignment: .leading, spacing: 24) {
                    // Title
                    formSection(title: "Title") {
                        TextField("Project name", text: $name)
                            .mcclawTextField()
                            .font(.title3)
                            .onChange(of: name) { _, _ in hasChanges = true }
                    }

                    // Description
                    formSection(title: "Description") {
                        TextEditor(text: $description)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.quaternary.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.quaternary, lineWidth: 0.5)
                            )
                            .frame(minHeight: 80, maxHeight: 120)
                            .onChange(of: description) { _, _ in hasChanges = true }
                    }

                    // Rules
                    formSection(title: "Rules") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Instructions that the AI must follow when chatting within this project. These are injected as system prompt on every message.")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)

                            TextEditor(text: $rules)
                                .font(.body.monospaced())
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(.quaternary.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(.quaternary, lineWidth: 0.5)
                                )
                                .frame(minHeight: 140, maxHeight: 280)
                                .onChange(of: rules) { _, _ in hasChanges = true }
                        }
                    }

                    // Directories
                    formSection(title: String(localized: "Directories", bundle: .module)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Filesystem directories associated with this project. The AI will use them as working paths.", bundle: .module)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)

                            if directories.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.badge.questionmark")
                                        .foregroundStyle(.tertiary)
                                    Text("No directories added yet", bundle: .module)
                                        .font(.callout)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 8)
                            } else {
                                VStack(spacing: 4) {
                                    ForEach(directories, id: \.self) { dir in
                                        HStack(spacing: 8) {
                                            Image(systemName: "folder.fill")
                                                .font(.subheadline)
                                                .foregroundStyle(Color.accentColor)
                                            Text(dir)
                                                .font(.callout.monospaced())
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            Button {
                                                directories.removeAll { $0 == dir }
                                                hasChanges = true
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(.quaternary.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }

                            Button {
                                addDirectory()
                            } label: {
                                Label(String(localized: "Add Directory", bundle: .module), systemImage: "folder.badge.plus")
                                    .font(.callout)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.top, 4)
                        }
                    }

                    // Context sharing info
                    contextInfoSection
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
            }
        }
        .onAppear(perform: loadProject)
    }

    // MARK: - Cover Image

    @ViewBuilder
    private var coverImageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = coverImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            generateImage()
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .liquidGlassCapsule(interactive: false)
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .disabled(isGeneratingImage)
                    }
            } else {
                // Placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [.accentColor.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 160)

                    VStack(spacing: 8) {
                        if isGeneratingImage {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Generating cover image…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)

                            Button("Generate Cover Image") {
                                generateImage()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Text("Uses Gemini or ChatGPT to create a cover based on the project description")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 300)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Context Info

    @ViewBuilder
    private var contextInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                Text("Shared Context")
                    .font(.body.weight(.semibold))
            }

            Text("When a chat belongs to this project, the AI automatically receives:")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                contextBullet(icon: "brain", text: "The project memory (description, rules, decisions, and context)")
                contextBullet(icon: "folder", text: "The configured project directories as working paths")
                contextBullet(icon: "doc.text", text: "Project files content uploaded to the project")
                contextBullet(icon: "bubble.left.and.bubble.right", text: "A digest of recent messages from other chats in the project")
            }
            .padding(.leading, 4)
        }
        .padding(16)
        .background(.quaternary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func contextBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text(text)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Form Section

    @ViewBuilder
    private func formSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.semibold))
            content()
        }
    }

    // MARK: - Actions

    private func loadProject() {
        guard let project = projectStore.load(projectId: projectId) else { return }
        name = project.name
        description = project.description
        rules = project.rules
        directories = project.directories
        coverImage = projectStore.loadCoverImage(for: project)
        hasChanges = false
    }

    private func saveProject() {
        projectStore.update(projectId: projectId, name: name, description: description, rules: rules, directories: directories)
        // Sync memory top sections if memory exists
        if ProjectMemoryStore.shared.loadMemory(for: projectId) != nil {
            ProjectMemoryStore.shared.updateProjectSections(
                for: projectId, name: name, description: description,
                rules: rules, directories: directories
            )
        }
        hasChanges = false
    }

    private func addDirectory() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select a project directory", bundle: .module)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                let path = url.path
                if !directories.contains(path) {
                    directories.append(path)
                }
            }
            hasChanges = true
        }
    }

    private func generateImage() {
        isGeneratingImage = true
        // Save current fields first so the AI has the latest description
        projectStore.update(projectId: projectId, name: name, description: description, rules: rules)

        Task {
            await projectStore.generateCoverImage(projectId: projectId)
            // Reload the image
            if let project = projectStore.load(projectId: projectId) {
                coverImage = projectStore.loadCoverImage(for: project)
            }
            isGeneratingImage = false
        }
    }
}
