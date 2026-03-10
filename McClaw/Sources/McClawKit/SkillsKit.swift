import Foundation

// MARK: - Local Skills Kit

/// Pure logic for parsing and managing local SKILL.md-based skills.
/// No I/O — all functions are pure and testable.
public enum SkillsKit {

    // MARK: - Models

    /// Metadata parsed from SKILL.md YAML frontmatter.
    public struct SkillMetadata: Sendable, Equatable {
        public let name: String
        public let description: String
        public let version: String?
        public let compatibility: String?
        public let emoji: String?
        public let author: String?

        public init(
            name: String,
            description: String,
            version: String? = nil,
            compatibility: String? = nil,
            emoji: String? = nil,
            author: String? = nil
        ) {
            self.name = name
            self.description = description
            self.version = version
            self.compatibility = compatibility
            self.emoji = emoji
            self.author = author
        }
    }

    /// A parsed local skill ready for display and prompt injection.
    public struct LocalSkill: Sendable, Equatable, Identifiable {
        public let id: String             // folder name = skill key
        public let metadata: SkillMetadata
        public let folderPath: String
        public let referenceFiles: [String]

        public init(id: String, metadata: SkillMetadata, folderPath: String, referenceFiles: [String]) {
            self.id = id
            self.metadata = metadata
            self.folderPath = folderPath
            self.referenceFiles = referenceFiles
        }
    }

    /// Persisted user preferences for skills.
    public struct SkillsConfig: Codable, Sendable {
        public var disabled: Set<String>

        public init(disabled: Set<String> = []) {
            self.disabled = disabled
        }
    }

    // MARK: - YAML Frontmatter Parsing

    /// Parse SKILL.md content to extract YAML frontmatter metadata and markdown body.
    /// Returns nil if the file has no valid frontmatter.
    public static func parseFrontmatter(_ content: String) -> (metadata: SkillMetadata, body: String)? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return nil }

        // Find closing ---
        let afterFirst = trimmed.dropFirst(3).drop(while: { $0.isNewline })
        guard let closingRange = afterFirst.range(of: "\n---") else { return nil }

        let yamlBlock = String(afterFirst[afterFirst.startIndex..<closingRange.lowerBound])
        let body = String(afterFirst[closingRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse flat YAML key-value pairs
        var fields: [String: String] = [:]
        for line in yamlBlock.split(separator: "\n", omittingEmptySubsequences: false) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            // Remove surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            fields[key] = value
        }

        guard let name = fields["name"], !name.isEmpty else { return nil }
        let description = fields["description"] ?? ""

        let metadata = SkillMetadata(
            name: name,
            description: description,
            version: fields["version"],
            compatibility: fields["compatibility"],
            emoji: fields["emoji"],
            author: fields["author"]
        )

        return (metadata, body)
    }

    // MARK: - Skill Folder Validation

    /// Check if a folder contains a valid skill (has SKILL.md with frontmatter).
    public static func isValidSkillFolder(files: [String]) -> Bool {
        files.contains("SKILL.md")
    }

    // MARK: - System Prompt Building

    /// Build the skills section of the system prompt for AI context injection.
    /// Returns nil if no skills are provided.
    public static func buildSkillsSystemPrompt(skills: [LocalSkill]) -> String? {
        guard !skills.isEmpty else { return nil }

        var lines: [String] = []
        lines.append("# Available Skills")
        lines.append("")
        lines.append("You have specialized skills available as local files. Each skill has a SKILL.md with detailed instructions and may include a references/ folder with additional documentation.")
        lines.append("")
        lines.append("Read the SKILL.md of the relevant skill when the user's request matches its domain. Follow its procedures and consult references/ as needed.")
        lines.append("")

        for skill in skills {
            let emoji = skill.metadata.emoji ?? "⚡"
            lines.append("## \(emoji) \(skill.metadata.name)")
            if !skill.metadata.description.isEmpty {
                lines.append(skill.metadata.description)
            }
            lines.append("Path: \(skill.folderPath)/SKILL.md")
            if !skill.referenceFiles.isEmpty {
                let refs = skill.referenceFiles.map { "\(skill.folderPath)/references/\($0)" }
                lines.append("References: \(refs.joined(separator: ", "))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - ZIP Structure Detection

    /// Detect the skill folder name from a list of ZIP entry paths.
    /// Handles both `skill-name/SKILL.md` and flat `SKILL.md` structures.
    /// Returns the root folder name if nested, or nil if flat (SKILL.md at root).
    public static func detectZipRootFolder(entries: [String]) -> String? {
        // Check if all entries share a common root folder
        let components = entries.compactMap { entry -> String? in
            let parts = entry.split(separator: "/", maxSplits: 1)
            return parts.count >= 2 ? String(parts[0]) : nil
        }
        guard let first = components.first, components.allSatisfy({ $0 == first }) else {
            return nil
        }
        // Verify SKILL.md is inside the root folder
        if entries.contains("\(first)/SKILL.md") {
            return first
        }
        return nil
    }
}
