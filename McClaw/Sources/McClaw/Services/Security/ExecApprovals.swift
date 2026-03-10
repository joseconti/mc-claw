import Foundation
import Logging

/// Manages execution approval rules for system commands.
/// Implements deny/allowlist/ask security model with glob pattern matching,
/// shell wrapper parsing, and persistent storage.
@MainActor
@Observable
final class ExecApprovals {
    static let shared = ExecApprovals()

    var securityMode: ExecSecurityMode = .ask
    var allowList: [ExecAllowlistEntry] = []
    var denyList: [ExecApprovalRule] = []

    /// Pending approval request shown in the UI dialog
    var pendingApproval: ExecApprovalRequest?

    private let logger = Logger(label: "ai.mcclaw.exec")

    private static var configFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw")
            .appendingPathComponent("exec-approvals.json")
    }

    // MARK: - Approval Check

    /// Check if a command is approved for execution.
    func checkApproval(command: String, arguments: [String]) -> ExecApprovalResult {
        let fullCommand = ([command] + arguments).joined(separator: " ")

        // Resolve the executable path
        let resolution = resolveCommand(command: command, arguments: arguments)

        // Check deny list first (deny always wins)
        for rule in denyList {
            if matchesRule(rule: rule, command: fullCommand, resolvedPath: resolution.resolvedPath) {
                return .denied(reason: rule.reason ?? "Command denied by policy")
            }
        }

        // Check allowlist
        for entry in allowList {
            if matchesAllowlistEntry(entry: entry, resolvedPath: resolution.resolvedPath, command: fullCommand) {
                // Record usage
                recordAllowlistUse(entryId: entry.id, command: fullCommand, resolvedPath: resolution.resolvedPath)
                return .approved
            }
        }

        // Shell wrapper parsing: if the command is a shell invocation,
        // resolve the inner commands too
        let shellResolutions = parseShellWrapper(command: command, arguments: arguments)
        if !shellResolutions.isEmpty {
            // Check if all inner commands are allowlisted
            let allAllowed = shellResolutions.allSatisfy { innerRes in
                allowList.contains { entry in
                    matchesAllowlistEntry(entry: entry, resolvedPath: innerRes.resolvedPath, command: innerRes.rawExecutable)
                }
            }
            if allAllowed {
                return .approved
            }
        }

        // Default based on security mode
        switch securityMode {
        case .deny:
            return .denied(reason: "All commands denied")
        case .allow:
            return .approved
        case .ask:
            return .needsApproval(
                command: fullCommand,
                resolution: resolution
            )
        }
    }

    // MARK: - Glob Pattern Matching

    /// Match a glob pattern against a path (case-insensitive).
    /// Supports * (single path component), ** (cross directory), ? (single char).
    static func globToRegex(_ pattern: String) -> NSRegularExpression? {
        var expanded = pattern
        // Expand tilde
        if expanded.hasPrefix("~") {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path
                + expanded.dropFirst()
        }

        // Normalize separators
        expanded = expanded.replacingOccurrences(of: "\\", with: "/")

        // Build regex
        var regex = "^"
        var i = expanded.startIndex
        while i < expanded.endIndex {
            let c = expanded[i]
            if c == "*" {
                let next = expanded.index(after: i)
                if next < expanded.endIndex && expanded[next] == "*" {
                    regex += ".*"
                    i = expanded.index(after: next)
                    continue
                } else {
                    regex += "[^/]*"
                }
            } else if c == "?" {
                regex += "."
            } else if "\\^$.|+()[]{}".contains(c) {
                regex += "\\\(c)"
            } else {
                regex += String(c)
            }
            i = expanded.index(after: i)
        }
        regex += "$"

        return try? NSRegularExpression(pattern: regex, options: .caseInsensitive)
    }

    // MARK: - Allowlist Validation

    /// Validate that a pattern is a valid path-based pattern.
    static func validateAllowlistPattern(_ pattern: String) -> ExecAllowlistValidation {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid(reason: "Pattern cannot be empty")
        }
        // Must contain path separator or tilde
        guard trimmed.contains("/") || trimmed.contains("~") || trimmed.contains("\\") else {
            return .invalid(reason: "Pattern must be a path (contain /, ~, or \\)")
        }
        // Try to compile as glob
        guard globToRegex(trimmed) != nil else {
            return .invalid(reason: "Invalid glob pattern syntax")
        }
        return .valid(trimmed)
    }

    // MARK: - Allowlist Management

    func addAllowlistEntry(pattern: String, command: String? = nil) {
        guard case .valid(let validated) = Self.validateAllowlistPattern(pattern) else { return }
        let entry = ExecAllowlistEntry(
            pattern: validated,
            lastUsedCommand: command
        )
        allowList.append(entry)
        saveToFile()
    }

    func removeAllowlistEntry(id: UUID) {
        allowList.removeAll { $0.id == id }
        saveToFile()
    }

    func addDenyRule(command: String? = nil, pattern: String? = nil, reason: String? = nil) {
        let rule = ExecApprovalRule(command: command, pattern: pattern, reason: reason)
        denyList.append(rule)
        saveToFile()
    }

    func removeDenyRule(id: UUID) {
        denyList.removeAll { $0.id == id }
        saveToFile()
    }

    // MARK: - Persistence

    func loadFromFile() {
        guard let data = try? Data(contentsOf: Self.configFileURL) else {
            logger.info("No exec-approvals config found, using defaults")
            return
        }
        do {
            let file = try JSONDecoder().decode(ExecApprovalsFile.self, from: data)
            securityMode = file.defaults.securityMode
            allowList = file.allowList
            denyList = file.denyList
            logger.info("Loaded exec-approvals: \(allowList.count) allow, \(denyList.count) deny")
        } catch {
            logger.error("Failed to parse exec-approvals: \(error)")
        }
    }

    func saveToFile() {
        let file = ExecApprovalsFile(
            version: 1,
            defaults: ExecApprovalsDefaults(securityMode: securityMode),
            allowList: allowList,
            denyList: denyList
        )
        do {
            let dir = Self.configFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let data = try JSONEncoder().encode(file)
            try data.write(to: Self.configFileURL, options: .atomic)

            // Set restrictive permissions (owner read/write only)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: Self.configFileURL.path
            )
            logger.info("Saved exec-approvals config")
        } catch {
            logger.error("Failed to save exec-approvals: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func matchesRule(rule: ExecApprovalRule, command: String, resolvedPath: String?) -> Bool {
        if let pattern = rule.pattern {
            return command.range(of: pattern, options: .regularExpression) != nil
        }
        if let prefix = rule.command {
            return command.hasPrefix(prefix)
        }
        return false
    }

    private func matchesAllowlistEntry(entry: ExecAllowlistEntry, resolvedPath: String?, command: String) -> Bool {
        guard let regex = Self.globToRegex(entry.pattern) else { return false }

        // Match against resolved path first
        if let resolved = resolvedPath {
            let normalized = resolved.replacingOccurrences(of: "\\", with: "/").lowercased()
            let range = NSRange(normalized.startIndex..., in: normalized)
            if regex.firstMatch(in: normalized, range: range) != nil {
                return true
            }
        }

        // Also try matching the raw command executable
        let firstToken = command.split(separator: " ").first.map(String.init) ?? command
        let normalized = firstToken.replacingOccurrences(of: "\\", with: "/").lowercased()
        let range = NSRange(normalized.startIndex..., in: normalized)
        return regex.firstMatch(in: normalized, range: range) != nil
    }

    private func recordAllowlistUse(entryId: UUID, command: String, resolvedPath: String?) {
        guard let idx = allowList.firstIndex(where: { $0.id == entryId }) else { return }
        allowList[idx].lastUsedAt = Date()
        allowList[idx].lastUsedCommand = command
        if let resolved = resolvedPath {
            allowList[idx].lastResolvedPath = resolved
        }
        // Don't save on every use - debounce or save periodically
    }

    // MARK: - Command Resolution

    /// Resolve a command to its executable path.
    func resolveCommand(command: String, arguments: [String]) -> ExecCommandResolution {
        let executable: String
        if command.contains("/") || command.contains("~") {
            // Already a path
            var expanded = command
            if expanded.hasPrefix("~") {
                expanded = FileManager.default.homeDirectoryForCurrentUser.path
                    + expanded.dropFirst()
            }
            executable = command
            let resolvedPath = FileManager.default.fileExists(atPath: expanded) ? expanded : nil
            return ExecCommandResolution(
                rawExecutable: command,
                resolvedPath: resolvedPath,
                executableName: URL(fileURLWithPath: command).lastPathComponent
            )
        } else {
            executable = command
            // Search PATH
            let resolvedPath = findInPath(executable)
            return ExecCommandResolution(
                rawExecutable: executable,
                resolvedPath: resolvedPath,
                executableName: executable
            )
        }
    }

    private func findInPath(_ name: String) -> String? {
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)

        let searchDirs = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        ] + pathDirs

        for dir in searchDirs {
            let full = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: full) {
                return full
            }
        }
        return nil
    }

    // MARK: - Shell Wrapper Parsing

    private static let knownShells: Set<String> = [
        "bash", "sh", "zsh", "dash", "ksh", "fish", "ash",
    ]

    /// Parse shell wrapper commands (e.g., `bash -c "cmd1 | cmd2"`).
    /// Returns resolved commands from inside the wrapper, or empty if not a shell wrapper
    /// or if the payload contains unsafe constructs.
    func parseShellWrapper(command: String, arguments: [String]) -> [ExecCommandResolution] {
        let basename = URL(fileURLWithPath: command).lastPathComponent
        guard Self.knownShells.contains(basename) else { return [] }

        // Look for -c or -lc flag
        guard let cIndex = arguments.firstIndex(where: { $0 == "-c" || $0 == "-lc" }),
              cIndex + 1 < arguments.count else {
            return []
        }

        let payload = arguments[cIndex + 1]

        // Fail-closed: reject payloads with subshells or command substitution
        if payload.contains("$(") || payload.contains("`") {
            logger.warning("Shell wrapper contains substitution, rejecting: \(payload.prefix(80))")
            return []
        }

        // Split by pipes and resolve each command
        let pipedCommands = payload.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        return pipedCommands.compactMap { cmd in
            let parts = cmd.split(separator: " ").map(String.init)
            guard let first = parts.first else { return nil }
            return resolveCommand(command: first, arguments: Array(parts.dropFirst()))
        }
    }

    private init() {}
}

// MARK: - Security Mode

enum ExecSecurityMode: String, Codable, Sendable, CaseIterable {
    case deny    // Deny all commands
    case allow   // Allow all commands
    case ask     // Ask user for approval
}

// MARK: - Approval Result

enum ExecApprovalResult: Sendable {
    case approved
    case denied(reason: String)
    case needsApproval(command: String, resolution: ExecCommandResolution? = nil)
}

// MARK: - Allowlist Entry

struct ExecAllowlistEntry: Codable, Sendable, Identifiable {
    let id: UUID
    let pattern: String
    var lastUsedAt: Date?
    var lastUsedCommand: String?
    var lastResolvedPath: String?

    init(
        id: UUID = UUID(),
        pattern: String,
        lastUsedAt: Date? = nil,
        lastUsedCommand: String? = nil,
        lastResolvedPath: String? = nil
    ) {
        self.id = id
        self.pattern = pattern
        self.lastUsedAt = lastUsedAt
        self.lastUsedCommand = lastUsedCommand
        self.lastResolvedPath = lastResolvedPath
    }
}

// MARK: - Deny Rule

struct ExecApprovalRule: Codable, Sendable, Identifiable {
    let id: UUID
    let command: String?
    let pattern: String?     // Regex pattern
    let reason: String?

    init(id: UUID = UUID(), command: String? = nil, pattern: String? = nil, reason: String? = nil) {
        self.id = id
        self.command = command
        self.pattern = pattern
        self.reason = reason
    }
}

// MARK: - Command Resolution

struct ExecCommandResolution: Codable, Sendable {
    let rawExecutable: String
    let resolvedPath: String?
    let executableName: String
}

// MARK: - Allowlist Validation

enum ExecAllowlistValidation: Sendable {
    case valid(String)
    case invalid(reason: String)
}

// MARK: - Approval Request (for UI dialog)

struct ExecApprovalRequest: Identifiable, Sendable {
    let id: UUID
    let command: String
    let arguments: [String]
    let fullCommand: String
    let resolution: ExecCommandResolution?
    let timestamp: Date

    init(command: String, arguments: [String], resolution: ExecCommandResolution? = nil) {
        self.id = UUID()
        self.command = command
        self.arguments = arguments
        self.fullCommand = ([command] + arguments).joined(separator: " ")
        self.resolution = resolution
        self.timestamp = Date()
    }
}

/// User's decision on an approval request.
enum ExecApprovalDecision: Sendable {
    case allowOnce
    case allowAlways   // Add to allowlist
    case deny
}

// MARK: - Persistence File

struct ExecApprovalsFile: Codable, Sendable {
    let version: Int
    let defaults: ExecApprovalsDefaults
    let allowList: [ExecAllowlistEntry]
    let denyList: [ExecApprovalRule]
}

struct ExecApprovalsDefaults: Codable, Sendable {
    let securityMode: ExecSecurityMode
}
