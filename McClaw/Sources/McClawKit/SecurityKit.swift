import Foundation

/// Pure security logic extracted for testability.
/// Used by ExecApprovals and HostEnvSanitizer in the main app target.
public enum SecurityKit {

    // MARK: - Glob Pattern Matching

    /// Convert a glob pattern to a compiled regex (case-insensitive).
    /// Supports: * (single path component), ** (cross directory), ? (single char), ~ (home dir).
    public static func globToRegex(_ pattern: String) -> NSRegularExpression? {
        var expanded = pattern
        // Expand tilde
        if expanded.hasPrefix("~") {
            expanded = NSHomeDirectory() + String(expanded.dropFirst())
        }
        // Normalize separators
        expanded = expanded.replacingOccurrences(of: "\\", with: "/")

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

    /// Check if a path matches a glob pattern.
    public static func globMatches(pattern: String, path: String) -> Bool {
        guard let regex = globToRegex(pattern) else { return false }
        let normalized = path.replacingOccurrences(of: "\\", with: "/").lowercased()
        let range = NSRange(normalized.startIndex..., in: normalized)
        return regex.firstMatch(in: normalized, range: range) != nil
    }

    // MARK: - Pattern Validation

    /// Validate that a pattern is a valid path-based allowlist pattern.
    public static func validateAllowlistPattern(_ pattern: String) -> AllowlistValidation {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid(reason: "Pattern cannot be empty")
        }
        guard trimmed.contains("/") || trimmed.contains("~") || trimmed.contains("\\") else {
            return .invalid(reason: "Pattern must be a path (contain /, ~, or \\)")
        }
        guard globToRegex(trimmed) != nil else {
            return .invalid(reason: "Invalid glob pattern syntax")
        }
        return .valid(trimmed)
    }

    public enum AllowlistValidation: Equatable, Sendable {
        case valid(String)
        case invalid(reason: String)
    }

    // MARK: - Shell Wrapper Detection

    /// Known shell names that might wrap other commands.
    public static let knownShells: Set<String> = [
        "bash", "sh", "zsh", "dash", "ksh", "fish", "ash",
    ]

    /// Parse a shell wrapper command (`bash -c "cmd1 | cmd2"`) into individual commands.
    /// Returns empty array if not a shell wrapper or contains unsafe constructs.
    public static func parseShellPayload(shell: String, arguments: [String]) -> [String] {
        let basename = URL(fileURLWithPath: shell).lastPathComponent
        guard knownShells.contains(basename) else { return [] }

        // Look for -c or -lc flag
        guard let cIndex = arguments.firstIndex(where: { $0 == "-c" || $0 == "-lc" }),
              cIndex + 1 < arguments.count else {
            return []
        }

        let payload = arguments[cIndex + 1]

        // Fail-closed: reject payloads with subshells or command substitution
        if payload.contains("$(") || payload.contains("`") {
            return []
        }

        return payload.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Environment Sanitization

    /// Sanitize environment variables, removing dangerous ones.
    public static func sanitizeEnvironment(
        env: [String: String],
        overrides: [String: String]? = nil,
        isShellWrapper: Bool = false
    ) -> [String: String] {
        var result: [String: String] = [:]

        if isShellWrapper {
            for key in shellWrapperAllowlist {
                if let value = env[key] {
                    result[key] = value
                }
            }
            if let path = env["PATH"] { result["PATH"] = path }
            result["MCCLAW_CLIENT"] = "1"
            return result
        }

        for (key, value) in env {
            if blockedExact.contains(key) { continue }
            if blockedPrefixes.contains(where: { key.hasPrefix($0) }) { continue }
            result[key] = value
        }

        if let overrides {
            for (key, value) in overrides {
                if key == "PATH" { continue }
                if overrideBlockedExact.contains(key) { continue }
                if overrideBlockedPrefixes.contains(where: { key.hasPrefix($0) }) { continue }
                result[key] = value
            }
        }

        result["MCCLAW_CLIENT"] = "1"
        result["NO_COLOR"] = "1"
        return result
    }

    // MARK: - Blocklists

    public static let blockedExact: Set<String> = [
        "NODE_OPTIONS", "NODE_PATH",
        "PYTHONHOME", "PYTHONPATH",
        "PERL5LIB", "PERL5OPT",
        "RUBYLIB", "RUBYOPT",
        "BASH_ENV", "ENV", "SHELLOPTS", "PS4",
        "GIT_EXTERNAL_DIFF",
        "GCONV_PATH", "IFS",
        "SSLKEYLOGFILE",
        "SHELL",
        "CLAUDECODE",
    ]

    public static let blockedPrefixes: [String] = [
        "DYLD_", "LD_", "BASH_FUNC_",
    ]

    public static let overrideBlockedExact: Set<String> = [
        "HOME", "ZDOTDIR",
        "GIT_SSH_COMMAND", "GIT_SSH", "GIT_PROXY_COMMAND",
        "GIT_ASKPASS", "SSH_ASKPASS",
        "LESSOPEN", "LESSCLOSE", "PAGER", "MANPAGER", "GIT_PAGER",
        "EDITOR", "VISUAL", "FCEDIT", "SUDO_EDITOR",
        "PROMPT_COMMAND", "HISTFILE",
        "PERL5DB", "PERL5DBCMD",
        "OPENSSL_CONF", "OPENSSL_ENGINES",
        "PYTHONSTARTUP", "WGETRC", "CURL_HOME",
    ]

    public static let overrideBlockedPrefixes: [String] = [
        "GIT_CONFIG_", "NPM_CONFIG_",
    ]

    public static let shellWrapperAllowlist: Set<String> = [
        "TERM", "LANG", "LC_ALL", "LC_CTYPE", "LC_MESSAGES",
        "COLORTERM", "NO_COLOR", "FORCE_COLOR",
    ]
}
