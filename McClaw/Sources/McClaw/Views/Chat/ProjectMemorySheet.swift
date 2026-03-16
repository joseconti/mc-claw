import SwiftUI
import UniformTypeIdentifiers

/// Sheet that displays and allows editing the project memory file (memory.md).
struct ProjectMemorySheet: View {
    let projectId: String

    @State private var memoryStore = ProjectMemoryStore.shared
    @State private var memoryContent: String = ""
    @State private var isEditing = false
    @State private var editText = ""
    @State private var isUpdating = false
    @State private var showExporter = false
    @State private var showImporter = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // Content
            if memoryContent.isEmpty && !isEditing {
                emptyState
            } else if isEditing {
                editMode
            } else {
                viewMode
            }
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 600)
        .onAppear(perform: loadMemory)
        .fileExporter(
            isPresented: $showExporter,
            document: MemoryDocument(content: memoryContent),
            contentType: .plainText,
            defaultFilename: "memory.md"
        ) { _ in }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = memoryStore.importMemory(from: url, for: projectId)
                loadMemory()
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Project Memory", bundle: .appModule)
                    .font(.headline)

                let size = memoryStore.formattedMemorySize(for: projectId)
                if memoryStore.memorySize(for: projectId) > 0 {
                    Text(size)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Toolbar buttons
            HStack(spacing: 8) {
                if isEditing {
                    Button(String(localized: "Cancel", bundle: .appModule)) {
                        isEditing = false
                        editText = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(String(localized: "Save", bundle: .appModule)) {
                        memoryStore.saveMemory(editText, for: projectId)
                        memoryContent = editText
                        isEditing = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button {
                        editText = memoryContent
                        isEditing = true
                    } label: {
                        Label(String(localized: "Edit", bundle: .appModule), systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        refreshMemory()
                    } label: {
                        if isUpdating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(String(localized: "Refresh", bundle: .appModule), systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isUpdating || appState.memoryProviderId == nil)
                    .help(appState.memoryProviderId == nil
                        ? String(localized: "Set a memory provider in Settings → General to enable AI updates", bundle: .appModule)
                        : String(localized: "Update memory using AI", bundle: .appModule))

                    Menu {
                        Button {
                            showExporter = true
                        } label: {
                            Label(String(localized: "Export", bundle: .appModule), systemImage: "square.and.arrow.up")
                        }

                        Button {
                            showImporter = true
                        } label: {
                            Label(String(localized: "Import", bundle: .appModule), systemImage: "square.and.arrow.down")
                        }

                        Divider()

                        Button(role: .destructive) {
                            memoryStore.deleteMemory(for: projectId)
                            memoryContent = ""
                        } label: {
                            Label(String(localized: "Delete Memory", bundle: .appModule), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No memory yet", bundle: .appModule)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Project memory will be created automatically after your first conversation, or you can create it manually.", bundle: .appModule)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 12) {
                Button {
                    createInitialMemory()
                } label: {
                    Label(String(localized: "Create Memory", bundle: .appModule), systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    showImporter = true
                } label: {
                    Label(String(localized: "Import", bundle: .appModule), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - View Mode (Markdown Rendered)

    @ViewBuilder
    private var viewMode: some View {
        ScrollView {
            MarkdownContentView(content: memoryContent)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Edit Mode

    @ViewBuilder
    private var editMode: some View {
        TextEditor(text: $editText)
            .font(.body.monospaced())
            .scrollContentBackground(.hidden)
            .padding(16)
    }

    // MARK: - Actions

    private func loadMemory() {
        memoryContent = memoryStore.loadMemory(for: projectId) ?? ""
    }

    private func createInitialMemory() {
        guard let project = ProjectStore.shared.load(projectId: projectId) else { return }
        let initial = memoryStore.buildInitialMemory(for: project)
        memoryStore.saveMemory(initial, for: projectId)
        memoryContent = initial
    }

    private func refreshMemory() {
        isUpdating = true
        Task {
            // If no memory exists, create initial first
            if memoryContent.isEmpty {
                createInitialMemory()
            }
            // Gather messages from ALL project sessions for a comprehensive update
            let allMessages = gatherAllProjectMessages()
            await memoryStore.updateMemoryAsync(for: projectId, chatMessages: allMessages)
            loadMemory()
            isUpdating = false
        }
    }

    /// Collect messages from all sessions belonging to this project.
    private func gatherAllProjectMessages() -> [ChatMessage] {
        guard let project = ProjectStore.shared.load(projectId: projectId) else { return [] }
        let sessionStore = SessionStore.shared
        var allMessages: [ChatMessage] = []
        for sessionId in project.sessionIds {
            if let messages = sessionStore.load(sessionId: sessionId) {
                allMessages.append(contentsOf: messages)
            }
        }
        // Sort by timestamp so the AI sees them in order
        return allMessages.sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - File Document for Export

struct MemoryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}
