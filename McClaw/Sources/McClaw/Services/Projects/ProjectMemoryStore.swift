import Foundation
import Logging

/// Manages project memory files (`memory.md`) that serve as the single source of truth
/// for AI context in each project. Memory includes project description, rules, directories,
/// and accumulated decisions/context from conversations.
///
/// Storage: `~/.mcclaw/projects/{projectId}/memory.md`
@MainActor
@Observable
final class ProjectMemoryStore {
    static let shared = ProjectMemoryStore()

    private let logger = Logger(label: "ai.mcclaw.project-memory")
    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Paths

    /// Directory for a project's data.
    private func projectDir(for projectId: String) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/projects/\(projectId)", isDirectory: true)
    }

    /// Path to the memory file for a project.
    func memoryFileURL(for projectId: String) -> URL {
        projectDir(for: projectId).appendingPathComponent("memory.md")
    }

    // MARK: - Read

    /// Load the memory.md content for a project. Returns nil if file doesn't exist.
    func loadMemory(for projectId: String) -> String? {
        let url = memoryFileURL(for: projectId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Memory file size in bytes. Returns 0 if file doesn't exist.
    func memorySize(for projectId: String) -> Int64 {
        let url = memoryFileURL(for: projectId)
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// Formatted memory size string (e.g., "2.4 KB").
    func formattedMemorySize(for projectId: String) -> String {
        let bytes = memorySize(for: projectId)
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }

    // MARK: - Write

    /// Save memory content to disk (atomic write).
    func saveMemory(_ content: String, for projectId: String) {
        let dir = projectDir(for: projectId)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = memoryFileURL(for: projectId)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            logger.info("Memory saved for project \(projectId) (\(content.count) chars)")
        } catch {
            logger.error("Failed to save memory for project \(projectId): \(error)")
        }
    }

    /// Delete the memory file for a project.
    func deleteMemory(for projectId: String) {
        let url = memoryFileURL(for: projectId)
        try? fileManager.removeItem(at: url)
        logger.info("Memory deleted for project \(projectId)")
    }

    // MARK: - Initial Memory

    /// Build the initial memory content from project fields.
    func buildInitialMemory(for project: ProjectInfo) -> String {
        var lines: [String] = []

        lines.append("# \(project.name)")
        lines.append("")

        lines.append("## Description")
        lines.append(project.description.isEmpty ? "_No description provided._" : project.description)
        lines.append("")

        lines.append("## Rules")
        lines.append(project.rules.isEmpty ? "_No rules defined._" : project.rules)
        lines.append("")

        lines.append("## Directories")
        if project.directories.isEmpty {
            lines.append("_No directories configured._")
        } else {
            for dir in project.directories {
                lines.append("- \(dir)")
            }
        }
        lines.append("")

        lines.append("## Decisions & Context")
        lines.append("_No decisions recorded yet. This section will be updated automatically after conversations._")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Update Project Sections

    /// Update the fixed top sections (Description, Rules, Directories) of an existing memory file
    /// without using the AI. Does a direct text replacement of those sections.
    func updateProjectSections(
        for projectId: String,
        name: String,
        description: String,
        rules: String,
        directories: [String]
    ) {
        guard let existing = loadMemory(for: projectId) else { return }

        // Find the "## Decisions & Context" marker — everything from there onward is preserved
        let decisionsMarker = "## Decisions & Context"
        let decisionsSection: String

        if let range = existing.range(of: decisionsMarker) {
            decisionsSection = String(existing[range.lowerBound...])
        } else {
            // No decisions section yet — preserve everything after "## Directories" section
            decisionsSection = """
            ## Decisions & Context
            _No decisions recorded yet. This section will be updated automatically after conversations._

            """
        }

        // Rebuild top sections
        var lines: [String] = []
        lines.append("# \(name)")
        lines.append("")
        lines.append("## Description")
        lines.append(description.isEmpty ? "_No description provided._" : description)
        lines.append("")
        lines.append("## Rules")
        lines.append(rules.isEmpty ? "_No rules defined._" : rules)
        lines.append("")
        lines.append("## Directories")
        if directories.isEmpty {
            lines.append("_No directories configured._")
        } else {
            for dir in directories {
                lines.append("- \(dir)")
            }
        }
        lines.append("")

        // Append the preserved decisions section
        lines.append(decisionsSection)

        saveMemory(lines.joined(separator: "\n"), for: projectId)
        logger.info("Memory project sections updated for \(projectId)")
    }

    // MARK: - AI-Powered Memory Update

    /// Asynchronously update the memory by sending the current memory + chat summary to the AI.
    /// This runs in the background and does not block the UI.
    nonisolated func updateMemoryAsync(
        for projectId: String,
        chatMessages: [ChatMessage]
    ) async {
        let appState = await MainActor.run { AppState.shared }
        let memoryProviderId = await MainActor.run { appState.memoryProviderId }

        guard let providerId = memoryProviderId else {
            return
        }

        let provider = await MainActor.run {
            appState.availableCLIs.first(where: { $0.id == providerId && $0.isInstalled })
        }
        guard let provider else {
            return
        }

        // Load existing memory or build initial
        let existingMemory: String = await MainActor.run {
            if let memory = self.loadMemory(for: projectId) {
                return memory
            }
            // Build initial memory from project info
            let projectStore = ProjectStore.shared
            guard let project = projectStore.load(projectId: projectId) else {
                return ""
            }
            let initial = self.buildInitialMemory(for: project)
            self.saveMemory(initial, for: projectId)
            return initial
        }

        guard !existingMemory.isEmpty else { return }

        // Build chat summary — user + assistant only, sorted oldest→newest.
        // Use more messages when many chats are provided (Refresh), fewer for single-chat updates.
        let relevantMessages = chatMessages
            .filter { $0.role == .user || $0.role == .assistant }
            .sorted { $0.timestamp < $1.timestamp }

        // Adaptive limit: up to 60 messages for multi-chat refresh, 20 for single-chat idle update
        let messageLimit = relevantMessages.count > 40 ? 60 : 20
        let selectedMessages = Array(relevantMessages.suffix(messageLimit))

        var chatSummary = ""
        for msg in selectedMessages {
            let role = msg.role == .user ? "User" : "Assistant"
            let content = String(msg.content.prefix(500))
            chatSummary += "**\(role)**: \(content)\n\n"
        }

        guard !chatSummary.isEmpty else { return }

        // Build the prompt for the AI
        let prompt = """
        You are a memory manager for a software project. Below is the current project memory and recent conversations.

        IMPORTANT: The conversations are sorted from OLDEST to NEWEST (chronological order). \
        When there is a conflict between an earlier and a later message about the same topic, \
        the LATEST message always wins. For example, if an early message says "use PostgreSQL" \
        but a later message says "switch to SQLite", the memory must say "SQLite".

        Your job is to MERGE the conversation insights into the memory, producing an updated memory.md:
        1. Read the current memory carefully — it is the source of truth until contradicted by newer conversations.
        2. Read the conversations from top to bottom — later messages supersede earlier ones on the same topic.
        3. If a conversation CONTRADICTS something in memory, UPDATE memory to reflect the latest decision.
        4. Add new decisions, definitions, patterns, or important context to "Decisions & Context".
        5. Remove information from "Decisions & Context" that is now outdated or superseded by newer decisions.
        6. Keep Description, Rules, and Directories sections updated if conversations changed them.
        7. Be concise — memory is a summary of what matters, not a transcript. No filler, no chat history.
        8. Reply with ONLY the updated memory.md content. No preamble, no explanation, no code fences.

        ## Current Memory
        \(existingMemory)

        ## Recent Conversations (oldest → newest)
        \(chatSummary)
        """

        // Send to the AI via CLIBridge
        let stream = await CLIBridge.shared.send(message: prompt, provider: provider)
        var response = ""
        for await event in stream {
            if case .text(let chunk) = event {
                response += chunk
            }
        }

        // Clean up response — remove potential code fences wrapping
        let cleaned = cleanAIResponse(response)

        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                self.logger.warning("Empty response from AI for memory update of project \(projectId)")
            }
            return
        }

        await MainActor.run {
            self.saveMemory(cleaned, for: projectId)
            self.logger.info("Memory updated via AI for project \(projectId)")
        }
    }

    // MARK: - Helpers

    /// Strip potential code fences or preamble from AI response.
    private nonisolated func cleanAIResponse(_ response: String) -> String {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading ```markdown or ``` fence
        if text.hasPrefix("```markdown") {
            text = String(text.dropFirst("```markdown".count))
        } else if text.hasPrefix("```md") {
            text = String(text.dropFirst("```md".count))
        } else if text.hasPrefix("```") {
            text = String(text.dropFirst("```".count))
        }

        // Remove trailing ``` fence
        if text.hasSuffix("```") {
            text = String(text.dropLast("```".count))
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Export / Import

    /// Export memory to a file URL.
    func exportMemory(for projectId: String, to url: URL) -> Bool {
        guard let content = loadMemory(for: projectId) else { return false }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            logger.error("Failed to export memory: \(error)")
            return false
        }
    }

    /// Import memory from a file URL.
    func importMemory(from url: URL, for projectId: String) -> Bool {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            saveMemory(content, for: projectId)
            return true
        } catch {
            logger.error("Failed to import memory: \(error)")
            return false
        }
    }
}
