import SwiftUI

/// Sheet shown when a plan file is created in a non-project chat.
/// Lets the user save the artifact to an existing project or create a new one.
struct ArtifactSaveSheet: View {
    let pending: PendingArtifactSave
    let onDismiss: () -> Void

    @Environment(AppState.self) private var appState
    @State private var projectStore = ProjectStore.shared
    @State private var selectedProjectId: String?
    @State private var mode: SaveMode = .existing
    @State private var newProjectName = ""

    private enum SaveMode {
        case existing
        case newProject
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text(String(localized: "Save Plan to Project", bundle: .module))
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            // File info
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.fileName)
                        .font(.callout.weight(.medium))
                    Text(String(localized: "Source: \(pending.sourceCLI.capitalized)", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.3))

            // Mode picker
            Picker("", selection: $mode) {
                Text(String(localized: "Existing Project", bundle: .module))
                    .tag(SaveMode.existing)
                Text(String(localized: "New Project", bundle: .module))
                    .tag(SaveMode.newProject)
            }
            .pickerStyle(.segmented)
            .padding(16)

            // Content
            switch mode {
            case .existing:
                existingProjectPicker
            case .newProject:
                newProjectForm
            }

            Spacer(minLength: 0)

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button(String(localized: "Don't Save", bundle: .module)) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(mode == .existing
                    ? String(localized: "Save", bundle: .module)
                    : String(localized: "Create & Save", bundle: .module)
                ) {
                    saveArtifact()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 400, height: 440)
    }

    // MARK: - Existing Project Picker

    @ViewBuilder
    private var existingProjectPicker: some View {
        if projectStore.projects.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text(String(localized: "No projects yet", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Switch to \"New Project\" to create one.", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(projectStore.projects) { project in
                        Button {
                            selectedProjectId = project.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedProjectId == project.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedProjectId == project.id ? Color.accentColor : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name)
                                        .font(.callout.weight(.medium))
                                    if !project.description.isEmpty {
                                        Text(project.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedProjectId == project.id
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - New Project Form

    @ViewBuilder
    private var newProjectForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Project Name", bundle: .module))
                .font(.callout.weight(.medium))
            TextField(String(localized: "My Project", bundle: .module), text: $newProjectName)
                .mcclawTextField()
                .onSubmit {
                    if canSave { saveArtifact() }
                }
        }
        .padding(16)
    }

    // MARK: - Logic

    private var canSave: Bool {
        switch mode {
        case .existing:
            return selectedProjectId != nil
        case .newProject:
            return !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func saveArtifact() {
        let targetProjectId: String

        switch mode {
        case .existing:
            guard let id = selectedProjectId else { return }
            targetProjectId = id
        case .newProject:
            let name = newProjectName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let project = projectStore.create(name: name)
            targetProjectId = project.id
        }

        // Copy artifact to project
        let sourceURL = URL(fileURLWithPath: pending.filePath)
        ProjectArtifactStore.shared.addArtifact(
            from: sourceURL,
            fileName: pending.fileName,
            type: .plan,
            sourceCLI: pending.sourceCLI,
            sourceSessionId: pending.sessionId,
            toProject: targetProjectId
        )

        // Optionally assign the session to the project
        let sessionStore = SessionStore.shared
        if sessionStore.sessions.first(where: { $0.id == pending.sessionId })?.projectId == nil {
            sessionStore.assignToProject(sessionId: pending.sessionId, projectId: targetProjectId)
            ProjectStore.shared.addSession(pending.sessionId, toProject: targetProjectId)
        }

        onDismiss()
    }
}
