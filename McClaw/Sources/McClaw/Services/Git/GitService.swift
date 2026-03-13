import Foundation
import Logging

/// Result of a local git CLI command execution.
struct GitProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
    var output: String { succeeded ? stdout : stderr }
}

/// Manages local git CLI operations via Foundation.Process.
actor GitService {
    static let shared = GitService()

    private let logger = Logger(label: "ai.mcclaw.git")
    private let gitPath = "/usr/bin/git"

    /// Maximum output length forwarded to the AI (characters).
    private let maxOutputLength = 8000

    // MARK: - Discovery

    /// Check whether `git` is available on the system.
    func isGitInstalled() async -> Bool {
        let result = await execute(args: ["--version"])
        return result.succeeded
    }

    /// Scan common directories for locally cloned repos.
    func findLocalRepos(searchPaths: [String]? = nil) async -> [LocalRepoInfo] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = searchPaths ?? [
            "\(home)/Developer",
            "\(home)/Documents/GitHub",
            "\(home)/Projects",
            "\(home)/repos",
        ]

        var repos: [LocalRepoInfo] = []
        let fm = FileManager.default

        for searchPath in paths {
            guard let entries = try? fm.contentsOfDirectory(atPath: searchPath) else { continue }
            for entry in entries {
                let fullPath = "\(searchPath)/\(entry)"
                let gitDir = "\(fullPath)/.git"
                guard fm.fileExists(atPath: gitDir) else { continue }

                let remote = await getRemoteURL(repoPath: fullPath)
                let branch = await getCurrentBranch(repoPath: fullPath)
                repos.append(LocalRepoInfo(path: fullPath, remoteURL: remote, currentBranch: branch))
            }
        }

        return repos
    }

    /// Find local path matching a remote URL.
    func getRepoPath(for remoteURL: String, searchPaths: [String]? = nil) async -> String? {
        let repos = await findLocalRepos(searchPaths: searchPaths)
        let normalized = normalizeRemoteURL(remoteURL)
        return repos.first { normalizeRemoteURL($0.remoteURL ?? "") == normalized }?.path
    }

    // MARK: - Read Operations

    func log(repoPath: String, branch: String? = nil, since: String? = nil, limit: Int = 20, format: String? = nil) async throws -> String {
        var args = ["-C", repoPath, "log"]
        if let fmt = format {
            args.append("--pretty=format:\(fmt)")
        } else {
            args.append("--pretty=format:%h %an %s (%ar)")
        }
        args.append("-\(limit)")
        if let since { args.append(contentsOf: ["--since", since]) }
        if let branch { args.append(branch) }
        return try await run(args: args)
    }

    func diff(repoPath: String, target: String? = nil) async throws -> String {
        var args = ["-C", repoPath, "diff"]
        if let target { args.append(target) }
        return try await run(args: args)
    }

    func status(repoPath: String) async throws -> String {
        try await run(args: ["-C", repoPath, "status", "--short"])
    }

    func blame(repoPath: String, file: String) async throws -> String {
        try await run(args: ["-C", repoPath, "blame", file])
    }

    func show(repoPath: String, ref: String) async throws -> String {
        try await run(args: ["-C", repoPath, "show", ref, "--stat"])
    }

    func branches(repoPath: String) async throws -> [GitBranch] {
        let output = try await run(args: ["-C", repoPath, "branch", "-a", "--format=%(refname:short) %(HEAD) %(upstream:track)"])
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2)
            guard let name = parts.first.map(String.init) else { return nil }
            let isDefault = parts.count > 1 && parts[1] == "*"
            return GitBranch(name: name, isDefault: isDefault, isProtected: false, aheadBehind: nil)
        }
    }

    // MARK: - Write Operations

    func clone(url: String, destination: String) async throws -> String {
        try await run(args: ["clone", url, destination])
    }

    func checkout(repoPath: String, branch: String, create: Bool = false) async throws -> String {
        var args = ["-C", repoPath, "checkout"]
        if create { args.append("-b") }
        args.append(branch)
        return try await run(args: args)
    }

    func pull(repoPath: String) async throws -> String {
        try await run(args: ["-C", repoPath, "pull"])
    }

    func add(repoPath: String, files: [String]) async throws -> String {
        try await run(args: ["-C", repoPath, "add"] + files)
    }

    func commit(repoPath: String, message: String) async throws -> String {
        try await run(args: ["-C", repoPath, "commit", "-m", message])
    }

    func push(repoPath: String, remote: String = "origin", branch: String? = nil) async throws -> String {
        var args = ["-C", repoPath, "push", remote]
        if let branch { args.append(branch) }
        return try await run(args: args)
    }

    func tag(repoPath: String, name: String, message: String? = nil) async throws -> String {
        var args = ["-C", repoPath, "tag"]
        if let message {
            args.append(contentsOf: ["-a", name, "-m", message])
        } else {
            args.append(name)
        }
        return try await run(args: args)
    }

    func stash(repoPath: String, action: StashAction) async throws -> String {
        try await run(args: ["-C", repoPath, "stash", action.rawValue])
    }

    func createBranch(repoPath: String, name: String, from: String? = nil) async throws -> String {
        var args = ["-C", repoPath, "checkout", "-b", name]
        if let from { args.append(from) }
        return try await run(args: args)
    }

    // MARK: - Raw Execution (for @git intercept)

    /// Execute an arbitrary git command string (used by @git() intercept).
    /// Only allows safe git sub-commands.
    func executeRaw(command: String, repoPath: String) async throws -> String {
        let parts = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let subcommand = parts.first else {
            throw GitServiceError.emptyCommand
        }

        // Validate sub-command against allowlist
        guard Self.allowedSubcommands.contains(subcommand) else {
            throw GitServiceError.disallowedCommand(subcommand)
        }

        let args = ["-C", repoPath] + parts
        return try await run(args: args)
    }

    /// Sub-commands allowed via @git() intercept.
    private static let allowedSubcommands: Set<String> = [
        // Read
        "log", "diff", "status", "blame", "show", "branch", "shortlog",
        "rev-parse", "ls-files", "ls-tree", "cat-file", "describe", "tag",
        // Write (requires confirmation at UI layer)
        "clone", "checkout", "pull", "add", "commit", "push", "stash",
        "fetch", "merge", "rebase", "reset", "cherry-pick",
    ]

    // MARK: - Internal

    private func run(args: [String]) async throws -> String {
        let result = await execute(args: args)
        guard result.succeeded else {
            throw GitServiceError.commandFailed(result.stderr)
        }
        return truncate(result.stdout)
    }

    private func execute(args: [String], workingDirectory: String? = nil) async -> GitProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: gitPath)
            process.arguments = args
            process.standardInput = FileHandle.nullDevice

            if let wd = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: wd)
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: GitProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                return
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            continuation.resume(returning: GitProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr))
        }
    }

    private func truncate(_ text: String) -> String {
        if text.count > maxOutputLength {
            return String(text.prefix(maxOutputLength)) + "\n... (truncated)"
        }
        return text
    }

    private func getRemoteURL(repoPath: String) async -> String? {
        let result = await execute(args: ["-C", repoPath, "remote", "get-url", "origin"])
        return result.succeeded ? result.stdout : nil
    }

    private func getCurrentBranch(repoPath: String) async -> String? {
        let result = await execute(args: ["-C", repoPath, "rev-parse", "--abbrev-ref", "HEAD"])
        return result.succeeded ? result.stdout : nil
    }

    /// Normalize remote URLs for comparison (strip .git suffix, protocol differences).
    private func normalizeRemoteURL(_ url: String) -> String {
        var normalized = url.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove trailing .git
        if normalized.hasSuffix(".git") {
            normalized = String(normalized.dropLast(4))
        }
        // Normalize SSH to HTTPS-like path
        if normalized.hasPrefix("git@") {
            normalized = normalized
                .replacingOccurrences(of: "git@", with: "")
                .replacingOccurrences(of: ":", with: "/")
        }
        // Remove protocol prefix
        normalized = normalized
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return normalized
    }
}

// MARK: - Errors

enum GitServiceError: LocalizedError {
    case emptyCommand
    case disallowedCommand(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            return "Empty git command"
        case .disallowedCommand(let cmd):
            return "Git sub-command '\(cmd)' is not allowed"
        case .commandFailed(let msg):
            return "Git command failed: \(msg)"
        }
    }
}
