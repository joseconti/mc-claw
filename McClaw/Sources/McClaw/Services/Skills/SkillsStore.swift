import AppKit
import Foundation
import Logging
import McClawKit

/// Manages local skills stored in ~/.mcclaw/skills/.
/// Scans skill folders, parses SKILL.md frontmatter, handles ZIP import and removal.
@MainActor
@Observable
final class LocalSkillsStore {
    static let shared = LocalSkillsStore()

    private let logger = Logger(label: "ai.mcclaw.skills")

    var skills: [LocalSkillInfo] = []
    var isLoading = false
    var error: String?
    var statusMessage: String?

    /// Base configuration directory (~/.mcclaw/).
    private var baseDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mcclaw")
    }

    /// Base directory for skills.
    var skillsDir: URL {
        baseDir.appendingPathComponent("skills")
    }

    /// Config file for user preferences (disabled skills).
    private var configURL: URL {
        baseDir.appendingPathComponent("skills-config.json")
    }

    private init() {}

    // MARK: - Bundled Skills Installation

    /// Install bundled skills from the app bundle on first launch.
    /// Only copies skills that don't already exist in ~/.mcclaw/skills/.
    func installBundledSkillsIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)

        // Find BundledSkills in the app bundle
        guard let bundledPath = Bundle.main.resourcePath.map({ URL(fileURLWithPath: $0).appendingPathComponent("BundledSkills") }),
              fm.fileExists(atPath: bundledPath.path) else {
            logger.debug("No BundledSkills found in app bundle")
            return
        }

        guard let entries = try? fm.contentsOfDirectory(at: bundledPath, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return
        }

        var installed = 0
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            let skillName = entry.lastPathComponent
            let destDir = skillsDir.appendingPathComponent(skillName)

            // Only copy if not already present (user may have customized it)
            if !fm.fileExists(atPath: destDir.path) {
                do {
                    try fm.copyItem(at: entry, to: destDir)
                    installed += 1
                } catch {
                    logger.warning("Failed to install bundled skill \(skillName): \(error)")
                }
            }
        }

        if installed > 0 {
            logger.info("Installed \(installed) bundled skills")
        }
    }

    // MARK: - Refresh

    /// Scan ~/.mcclaw/skills/ and parse all valid skill folders.
    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        let fm = FileManager.default
        let config = loadConfig()

        // Ensure directory exists
        try? fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)

        var loaded: [LocalSkillInfo] = []

        guard let entries = try? fm.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            isLoading = false
            return
        }

        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            let skillMd = entry.appendingPathComponent("SKILL.md")
            guard let content = try? String(contentsOf: skillMd, encoding: .utf8),
                  let parsed = SkillsKit.parseFrontmatter(content) else { continue }

            // Scan references/
            let refsDir = entry.appendingPathComponent("references")
            let refFiles: [String]
            if let refs = try? fm.contentsOfDirectory(atPath: refsDir.path) {
                refFiles = refs.filter { $0.hasSuffix(".md") }.sorted()
            } else {
                refFiles = []
            }

            let skillId = entry.lastPathComponent
            loaded.append(LocalSkillInfo(
                id: skillId,
                metadata: parsed.metadata,
                folderPath: entry.path,
                referenceFiles: refFiles,
                isEnabled: !config.disabled.contains(skillId)
            ))
        }

        skills = loaded.sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }
        isLoading = false
        logger.info("Loaded \(skills.count) local skills")
    }

    // MARK: - Enable / Disable

    func setEnabled(skillId: String, enabled: Bool) {
        guard let idx = skills.firstIndex(where: { $0.id == skillId }) else { return }
        skills[idx].isEnabled = enabled

        var config = loadConfig()
        if enabled {
            config.disabled.remove(skillId)
        } else {
            config.disabled.insert(skillId)
        }
        saveConfig(config)
        statusMessage = enabled ? "Skill enabled" : "Skill disabled"
    }

    // MARK: - Import ZIP

    /// Import a skill from a ZIP file. Unzips to ~/.mcclaw/skills/.
    func importZIP(from url: URL) async {
        isLoading = true
        error = nil
        statusMessage = nil

        do {
            let fm = FileManager.default
            try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)

            // Create temp directory for extraction
            let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tempDir) }

            // Unzip using ditto (macOS built-in)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", url.path, tempDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw SkillImportError.unzipFailed
            }

            // Find the skill folder (may be nested in a root folder, or contain __MACOSX)
            let extracted = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey])
            let candidates = extracted.filter {
                $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store"
            }

            // Determine source: is SKILL.md at root of temp, or inside a subfolder?
            var sourceDir: URL
            var skillName: String

            if fm.fileExists(atPath: tempDir.appendingPathComponent("SKILL.md").path) {
                // Flat ZIP: SKILL.md at root → use ZIP filename as folder name
                skillName = url.deletingPathExtension().lastPathComponent
                sourceDir = tempDir
            } else if let folder = candidates.first(where: { dir in
                fm.fileExists(atPath: dir.appendingPathComponent("SKILL.md").path)
            }) {
                // Nested ZIP: skill-name/SKILL.md
                skillName = folder.lastPathComponent
                sourceDir = folder
            } else {
                throw SkillImportError.noSkillMd
            }

            // Validate SKILL.md has valid frontmatter
            let content = try String(contentsOf: sourceDir.appendingPathComponent("SKILL.md"), encoding: .utf8)
            guard SkillsKit.parseFrontmatter(content) != nil else {
                throw SkillImportError.invalidFrontmatter
            }

            // Copy to skills directory
            let destDir = skillsDir.appendingPathComponent(skillName)
            if fm.fileExists(atPath: destDir.path) {
                try fm.removeItem(at: destDir)
            }
            try fm.copyItem(at: sourceDir, to: destDir)

            // Clean up __MACOSX and .DS_Store from destination
            let cleanup = ["__MACOSX", ".DS_Store"]
            for name in cleanup {
                let item = destDir.appendingPathComponent(name)
                try? fm.removeItem(at: item)
            }

            statusMessage = "Imported skill: \(skillName)"
            logger.info("Imported skill from ZIP: \(skillName)")
        } catch let error as SkillImportError {
            self.error = error.localizedDescription
        } catch {
            self.error = "Import failed: \(error.localizedDescription)"
        }

        isLoading = false
        refresh()
    }

    // MARK: - Remove

    func remove(skillId: String) {
        let folder = skillsDir.appendingPathComponent(skillId)
        try? FileManager.default.removeItem(at: folder)

        // Clean up config
        var config = loadConfig()
        config.disabled.remove(skillId)
        saveConfig(config)

        skills.removeAll { $0.id == skillId }
        statusMessage = "Removed skill: \(skillId)"
        logger.info("Removed skill: \(skillId)")
    }

    // MARK: - Open Folder

    func openSkillsFolder() {
        try? FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(skillsDir)
    }

    // MARK: - Active Skills for Prompt Injection

    /// Returns enabled skills as pure-logic types for system prompt building.
    func activeSkills() -> [SkillsKit.LocalSkill] {
        skills.filter(\.isEnabled).map(\.asLocalSkill)
    }

    // MARK: - Config Persistence

    private func loadConfig() -> SkillsKit.SkillsConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(SkillsKit.SkillsConfig.self, from: data) else {
            return SkillsKit.SkillsConfig()
        }
        return config
    }

    private func saveConfig(_ config: SkillsKit.SkillsConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}

// MARK: - Import Errors

enum SkillImportError: LocalizedError {
    case unzipFailed
    case noSkillMd
    case invalidFrontmatter

    var errorDescription: String? {
        switch self {
        case .unzipFailed: "Failed to unzip the file."
        case .noSkillMd: "No SKILL.md found in the ZIP. Skills must contain a SKILL.md file."
        case .invalidFrontmatter: "SKILL.md has no valid YAML frontmatter (name is required)."
        }
    }
}
