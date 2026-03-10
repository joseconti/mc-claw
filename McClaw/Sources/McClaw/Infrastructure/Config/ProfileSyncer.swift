import Foundation

/// Syncs user profile information to CLI-specific config files.
/// Each CLI has its own way of storing user context:
/// - Claude: ~/.claude/CLAUDE.md (markdown with user info section)
/// - Gemini: ~/.gemini/settings.json (JSON with user context)
enum ProfileSyncer {
    /// Sync user profile to all supported CLI config files.
    static func syncToCLIs(name: String?, email: String?, description: String?) async {
        guard name != nil || email != nil || description != nil else { return }

        await syncToClaudeMD(name: name, email: email, description: description)
        await syncToGeminiSettings(name: name, email: email, description: description)
    }

    // MARK: - Claude CLI (~/.claude/CLAUDE.md)

    private static func syncToClaudeMD(name: String?, email: String?, description: String?) async {
        let home = NSHomeDirectory()
        let claudeDir = "\(home)/.claude"
        let claudeMDPath = "\(claudeDir)/CLAUDE.md"

        // Build the McClaw profile section
        let profileSection = buildProfileMarkdown(name: name, email: email, description: description)
        let marker = "<!-- McClaw User Profile -->"
        let endMarker = "<!-- /McClaw User Profile -->"
        let fullSection = "\(marker)\n\(profileSection)\n\(endMarker)"

        // Ensure ~/.claude/ exists
        try? FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: claudeMDPath),
           var content = try? String(contentsOfFile: claudeMDPath, encoding: .utf8) {
            // Replace existing McClaw section or append
            if let startRange = content.range(of: marker),
               let endRange = content.range(of: endMarker) {
                let fullRange = startRange.lowerBound..<endRange.upperBound
                content.replaceSubrange(fullRange, with: fullSection)
            } else {
                content += "\n\n\(fullSection)\n"
            }
            try? content.write(toFile: claudeMDPath, atomically: true, encoding: .utf8)
        } else {
            // Create new file
            let content = "# User Context\n\n\(fullSection)\n"
            try? content.write(toFile: claudeMDPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Gemini CLI (~/.gemini/settings.json)

    private static func syncToGeminiSettings(name: String?, email: String?, description: String?) async {
        let home = NSHomeDirectory()
        let geminiDir = "\(home)/.gemini"
        let settingsPath = "\(geminiDir)/settings.json"

        // Ensure ~/.gemini/ exists
        try? FileManager.default.createDirectory(atPath: geminiDir, withIntermediateDirectories: true)

        // Read existing settings or start fresh
        var settings: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Update user profile in settings
        var profile: [String: String] = [:]
        if let name = name { profile["name"] = name }
        if let email = email { profile["email"] = email }
        if let description = description { profile["description"] = description }
        settings["userProfile"] = profile

        // Write back
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }
    }

    // MARK: - Helpers

    private static func buildProfileMarkdown(name: String?, email: String?, description: String?) -> String {
        var lines: [String] = ["## About the User"]
        if let name = name, !name.isEmpty {
            lines.append("- **Name**: \(name)")
        }
        if let email = email, !email.isEmpty {
            lines.append("- **Email**: \(email)")
        }
        if let description = description, !description.isEmpty {
            lines.append("")
            lines.append(description)
        }
        return lines.joined(separator: "\n")
    }
}
