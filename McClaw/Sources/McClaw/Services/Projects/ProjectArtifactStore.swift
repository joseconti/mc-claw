import Foundation
import Logging

/// Manages project artifacts (plans, documents, diagnostics) stored centrally in McClaw.
///
/// Storage: `~/.mcclaw/projects/{projectId}/artifacts/`
/// Index:   `~/.mcclaw/projects/{projectId}/artifacts/index.json`
@MainActor
@Observable
final class ProjectArtifactStore {
    static let shared = ProjectArtifactStore()

    private let logger = Logger(label: "ai.mcclaw.project-artifacts")
    private let fileManager = FileManager.default

    /// Artifacts for the currently viewed project (refreshed on demand).
    private(set) var currentArtifacts: [ProjectArtifact] = []
    /// The project ID currently loaded.
    private(set) var currentProjectId: String?

    private init() {}

    // MARK: - Paths

    private func artifactsDir(for projectId: String) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/projects/\(projectId)/artifacts", isDirectory: true)
    }

    private func indexFile(for projectId: String) -> URL {
        artifactsDir(for: projectId).appendingPathComponent("index.json")
    }

    /// Full path to an artifact's file on disk.
    func artifactFileURL(_ artifact: ProjectArtifact, projectId: String) -> URL {
        artifactsDir(for: projectId).appendingPathComponent(artifact.storedFileName)
    }

    // MARK: - Ensure Directory

    private func ensureDirectory(for projectId: String) {
        let dir = artifactsDir(for: projectId)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Index Persistence

    private func loadIndex(for projectId: String) -> [ProjectArtifact] {
        let url = indexFile(for: projectId)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ProjectArtifact].self, from: data)) ?? []
    }

    private func saveIndex(_ artifacts: [ProjectArtifact], for projectId: String) {
        ensureDirectory(for: projectId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(artifacts) else { return }
        try? data.write(to: indexFile(for: projectId), options: .atomic)
    }

    // MARK: - Refresh

    /// Load artifacts for a project into `currentArtifacts`.
    func refresh(for projectId: String) {
        currentProjectId = projectId
        currentArtifacts = loadIndex(for: projectId).sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Add Artifact

    /// Copy a file into the project's artifacts directory and update the index.
    @discardableResult
    func addArtifact(
        from sourceURL: URL,
        fileName: String,
        type: ArtifactType = .plan,
        sourceCLI: String? = nil,
        sourceSessionId: String? = nil,
        toProject projectId: String
    ) -> ProjectArtifact {
        ensureDirectory(for: projectId)

        let artifact = ProjectArtifact(
            fileName: fileName,
            type: type,
            sourceCLI: sourceCLI,
            sourceSessionId: sourceSessionId,
            originalPath: sourceURL.path
        )

        let destURL = artifactFileURL(artifact, projectId: projectId)

        do {
            try fileManager.copyItem(at: sourceURL, to: destURL)
        } catch {
            logger.error("Failed to copy artifact \(fileName) to project \(projectId): \(error)")
        }

        var index = loadIndex(for: projectId)
        index.append(artifact)
        saveIndex(index, for: projectId)

        // Update observable state if viewing this project
        if currentProjectId == projectId {
            currentArtifacts = index.sorted { $0.createdAt > $1.createdAt }
        }

        logger.info("Artifact added: \(fileName) (\(type.rawValue)) to project \(projectId)")
        return artifact
    }

    // MARK: - Remove Artifact

    /// Remove an artifact from the project (deletes file and index entry).
    func removeArtifact(id: String, fromProject projectId: String) {
        var index = loadIndex(for: projectId)
        guard let artifact = index.first(where: { $0.id == id }) else { return }

        // Delete file
        let fileURL = artifactFileURL(artifact, projectId: projectId)
        try? fileManager.removeItem(at: fileURL)

        // Update index
        index.removeAll { $0.id == id }
        saveIndex(index, for: projectId)

        // Update observable state
        if currentProjectId == projectId {
            currentArtifacts = index.sorted { $0.createdAt > $1.createdAt }
        }

        logger.info("Artifact removed: \(artifact.fileName) from project \(projectId)")
    }

    // MARK: - Read Content

    /// Load the text content of an artifact. Returns nil for binary files or on error.
    func loadContent(_ artifact: ProjectArtifact, projectId: String) -> String? {
        let url = artifactFileURL(artifact, projectId: projectId)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Count

    /// Number of artifacts in a project (lightweight, reads index only).
    func artifactCount(for projectId: String) -> Int {
        loadIndex(for: projectId).count
    }
}
