import Foundation
import Logging

/// Persists chat sessions to disk at `~/.mcclaw/sessions/`.
/// Each session is stored as a JSON file named `{sessionId}.json`.
@MainActor
@Observable
final class SessionStore {
    static let shared = SessionStore()

    /// All known session summaries, sorted by last message date (newest first).
    private(set) var sessions: [SessionInfo] = []

    private let logger = Logger(label: "ai.mcclaw.sessions")
    private let fileManager = FileManager.default

    private var sessionsDir: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/sessions", isDirectory: true)
    }

    private var trashDir: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/sessions/trash", isDirectory: true)
    }

    /// Sessions currently in the trash, sorted by most recent first.
    private(set) var trashedSessions: [SessionInfo] = []

    private init() {}

    // MARK: - Directory

    func ensureDirectory() {
        try? fileManager.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: trashDir, withIntermediateDirectories: true)
    }

    // MARK: - Save

    /// Save messages for a session. Creates or overwrites the session file.
    func save(sessionId: String, messages: [ChatMessage], provider: String? = nil) {
        ensureDirectory()

        let record = SessionRecord(
            sessionId: sessionId,
            messages: messages,
            cliProvider: provider,
            savedAt: Date()
        )

        let url = sessionsDir.appendingPathComponent("\(sanitize(sessionId)).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(record)
            try data.write(to: url, options: .atomic)
            logger.info("Session saved: \(sessionId) (\(messages.count) messages)")
            refreshIndex()
        } catch {
            logger.error("Failed to save session \(sessionId): \(error)")
        }
    }

    // MARK: - Load

    /// Load messages for a session from disk. Returns nil if not found.
    func load(sessionId: String) -> [ChatMessage]? {
        let url = sessionsDir.appendingPathComponent("\(sanitize(sessionId)).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: url)
            let record = try decoder.decode(SessionRecord.self, from: data)
            logger.info("Session loaded: \(sessionId) (\(record.messages.count) messages)")
            return record.messages
        } catch {
            logger.error("Failed to load session \(sessionId): \(error)")
            return nil
        }
    }

    // MARK: - Delete / Trash

    /// Move a session to the trash instead of permanently deleting it.
    func delete(sessionId: String) {
        moveToTrash(sessionId: sessionId)
    }

    /// Move a session file to the trash directory.
    func moveToTrash(sessionId: String) {
        ensureDirectory()
        let filename = "\(sanitize(sessionId)).json"
        let source = sessionsDir.appendingPathComponent(filename)
        let destination = trashDir.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: source.path) else { return }

        do {
            // Remove existing trash file with same name if any
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
            logger.info("Session moved to trash: \(sessionId)")
        } catch {
            logger.error("Failed to move session to trash: \(error)")
        }
        refreshIndex()
    }

    /// Restore a session from the trash back to the sessions directory.
    func restoreFromTrash(sessionId: String) {
        ensureDirectory()
        let filename = "\(sanitize(sessionId)).json"
        let source = trashDir.appendingPathComponent(filename)
        let destination = sessionsDir.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: source.path) else { return }

        do {
            try fileManager.moveItem(at: source, to: destination)
            logger.info("Session restored from trash: \(sessionId)")
        } catch {
            logger.error("Failed to restore session from trash: \(error)")
        }
        refreshIndex()
    }

    /// Permanently delete a session from the trash.
    func deletePermanently(sessionId: String) {
        let url = trashDir.appendingPathComponent("\(sanitize(sessionId)).json")
        try? fileManager.removeItem(at: url)
        logger.info("Session permanently deleted: \(sessionId)")
        refreshIndex()
    }

    /// Empty the entire trash, permanently deleting all trashed sessions.
    func emptyTrash() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: trashDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for url in urls where url.pathExtension == "json" {
            try? fileManager.removeItem(at: url)
        }
        logger.info("Trash emptied")
        refreshIndex()
    }

    // MARK: - Project Assignment

    /// Mark a session as belonging to a project. Rewrites the session record with projectId metadata.
    func assignToProject(sessionId: String, projectId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].projectId = projectId
        // Persist the projectId in a lightweight metadata sidecar
        saveProjectAssignment(sessionId: sessionId, projectId: projectId)
    }

    /// Remove project assignment from a session.
    func unassignFromProject(sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].projectId = nil
        removeProjectAssignment(sessionId: sessionId)
    }

    /// Sessions not assigned to any project and not Git sessions (shown in main sidebar).
    var unassignedSessions: [SessionInfo] {
        sessions.filter { $0.projectId == nil && $0.gitRepoFullName == nil }
    }

    /// Sessions belonging to a specific project.
    func sessions(forProject projectId: String) -> [SessionInfo] {
        sessions.filter { $0.projectId == projectId }
    }

    // MARK: - Project Assignment Persistence

    private var assignmentsFile: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/sessions/project_assignments.json")
    }

    private func loadAssignments() -> [String: String] {
        guard let data = try? Data(contentsOf: assignmentsFile),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func saveAssignments(_ assignments: [String: String]) {
        ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(assignments) else { return }
        try? data.write(to: assignmentsFile, options: .atomic)
    }

    private func saveProjectAssignment(sessionId: String, projectId: String) {
        var assignments = loadAssignments()
        assignments[sessionId] = projectId
        saveAssignments(assignments)
    }

    private func removeProjectAssignment(sessionId: String) {
        var assignments = loadAssignments()
        assignments.removeValue(forKey: sessionId)
        saveAssignments(assignments)
    }

    // MARK: - Git Repo Assignment

    /// Mark a session as belonging to a Git repository.
    func assignToGitRepo(sessionId: String, repoFullName: String) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].gitRepoFullName = repoFullName
        }
        var assignments = loadGitRepoAssignments()
        assignments[sessionId] = repoFullName
        saveGitRepoAssignments(assignments)
    }

    /// Remove Git repo assignment from a session.
    func unassignFromGitRepo(sessionId: String) {
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].gitRepoFullName = nil
        }
        var assignments = loadGitRepoAssignments()
        assignments.removeValue(forKey: sessionId)
        saveGitRepoAssignments(assignments)
    }

    /// Sessions belonging to a specific Git repository, sorted by most recent first.
    func sessions(forGitRepo repoFullName: String) -> [SessionInfo] {
        sessions
            .filter { $0.gitRepoFullName == repoFullName }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    // MARK: - Git Repo Assignment Persistence

    private var gitRepoAssignmentsFile: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/sessions/git_repo_assignments.json")
    }

    private func loadGitRepoAssignments() -> [String: String] {
        guard let data = try? Data(contentsOf: gitRepoAssignmentsFile),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func saveGitRepoAssignments(_ assignments: [String: String]) {
        ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(assignments) else { return }
        try? data.write(to: gitRepoAssignmentsFile, options: .atomic)
    }

    // MARK: - Index

    /// Refresh the session index by scanning the sessions directory.
    func refreshIndex() {
        ensureDirectory()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var infos: [SessionInfo] = []

        guard let urls = try? fileManager.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            sessions = []
            return
        }

        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(SessionRecord.self, from: data) else {
                continue
            }

            let lastMsg = record.messages.last
            let info = SessionInfo(
                id: record.sessionId,
                title: sessionTitle(from: record),
                createdAt: record.messages.first?.timestamp ?? record.savedAt,
                lastMessageAt: lastMsg?.timestamp ?? record.savedAt,
                sessionType: SessionKey.parse(record.sessionId).type,
                messageCount: record.messages.count,
                cliProvider: record.cliProvider
            )
            infos.append(info)
        }

        // Apply project assignments
        let assignments = loadAssignments()
        for i in infos.indices {
            infos[i].projectId = assignments[infos[i].id]
        }

        // Apply git repo assignments
        let gitAssignments = loadGitRepoAssignments()
        for i in infos.indices {
            infos[i].gitRepoFullName = gitAssignments[infos[i].id]
        }

        sessions = infos.sorted { $0.lastMessageAt > $1.lastMessageAt }

        // Scan trash directory
        refreshTrashIndex(decoder: decoder)
    }

    /// Refresh the trashed sessions index.
    private func refreshTrashIndex(decoder: JSONDecoder) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: trashDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            trashedSessions = []
            return
        }

        var trashed: [SessionInfo] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(SessionRecord.self, from: data) else {
                continue
            }

            let lastMsg = record.messages.last
            let info = SessionInfo(
                id: record.sessionId,
                title: sessionTitle(from: record),
                createdAt: record.messages.first?.timestamp ?? record.savedAt,
                lastMessageAt: lastMsg?.timestamp ?? record.savedAt,
                sessionType: SessionKey.parse(record.sessionId).type,
                messageCount: record.messages.count,
                cliProvider: record.cliProvider
            )
            trashed.append(info)
        }
        trashedSessions = trashed.sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    // MARK: - Helpers

    /// Derive a short title from the first user message or fallback to session ID.
    private func sessionTitle(from record: SessionRecord) -> String {
        if let firstUser = record.messages.first(where: { $0.role == .user }) {
            let text = firstUser.content.prefix(60)
            return text.count < firstUser.content.count ? "\(text)…" : String(text)
        }
        return String(record.sessionId.prefix(8))
    }

    /// Sanitize session ID for use as filename.
    private func sanitize(_ sessionId: String) -> String {
        sessionId.replacingOccurrences(
            of: "[^a-zA-Z0-9_\\-]",
            with: "_",
            options: .regularExpression
        )
    }
}

// MARK: - Persistence Model

/// On-disk format for a saved session.
struct SessionRecord: Codable, Sendable {
    let sessionId: String
    let messages: [ChatMessage]
    let cliProvider: String?
    let savedAt: Date
}
