/// RemoteKit - Pure logic for remote connection handling.
/// Testable without actors or UI dependencies.

import Foundation

// MARK: - SSH Target Parsing

/// Parsed SSH connection target.
public struct RemoteSSHTarget: Codable, Sendable, Equatable {
    public let user: String?
    public let host: String
    public let port: Int?

    public init(user: String? = nil, host: String, port: Int? = nil) {
        self.user = user
        self.host = host
        self.port = port
    }

    /// Parse "user@host:port", "user@host", "host:port", or "host".
    public static func parse(_ target: String) -> RemoteSSHTarget? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var user: String?
        var remainder = trimmed

        if let atIndex = remainder.firstIndex(of: "@") {
            let u = String(remainder[..<atIndex])
            guard !u.isEmpty else { return nil }
            user = u
            remainder = String(remainder[remainder.index(after: atIndex)...])
        }

        var host: String
        var port: Int?

        if let colonIndex = remainder.lastIndex(of: ":") {
            let portStr = String(remainder[remainder.index(after: colonIndex)...])
            if let p = Int(portStr), p > 0, p <= 65535 {
                host = String(remainder[..<colonIndex])
                port = p
            } else {
                host = remainder
            }
        } else {
            host = remainder
        }

        guard !host.isEmpty else { return nil }
        return RemoteSSHTarget(user: user, host: host, port: port)
    }

    /// Format back to string representation.
    public var formatted: String {
        var result = ""
        if let user { result += "\(user)@" }
        result += host
        if let port { result += ":\(port)" }
        return result
    }
}

// MARK: - Gateway URL Validation

/// Validates and normalizes gateway WebSocket URLs.
public enum RemoteURLValidator {
    /// Normalize and validate a gateway URL string.
    /// Returns nil if invalid. Rules:
    /// - ws:// only allowed for loopback hosts
    /// - wss:// allowed for any host
    public static func normalize(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }

        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "ws" || scheme == "wss" else { return nil }

        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !host.isEmpty else { return nil }

        // Plain ws:// only on loopback
        if scheme == "ws", !isLoopback(host) {
            return nil
        }

        // Add default port if missing
        if url.port == nil {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url
            }
            components.port = defaultPort(scheme: scheme)
            return components.url
        }

        return url
    }

    /// Build a local WebSocket URL.
    public static func localURL(port: Int) -> URL {
        URL(string: "ws://127.0.0.1:\(port)/ws")!
    }

    /// Check if a host is loopback.
    public static func isLoopback(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "127.0.0.1" || lower == "localhost" || lower == "::1"
    }

    /// Default port for scheme.
    public static func defaultPort(scheme: String) -> Int {
        switch scheme.lowercased() {
        case "wss": 443
        case "ws": 3577
        default: 3577
        }
    }

    /// Convert a gateway WebSocket URL to an HTTP dashboard URL.
    public static func dashboardURL(from wsURL: URL) -> URL? {
        guard var components = URLComponents(url: wsURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.scheme {
        case "ws": components.scheme = "http"
        case "wss": components.scheme = "https"
        default: return nil
        }
        components.path = "/"
        return components.url
    }
}

// MARK: - Connection Mode Resolution

/// Determines the effective connection mode.
public enum ConnectionModeResolver {
    /// Resolve connection mode from config values with priority cascade.
    /// 1. Explicit mode if set
    /// 2. Presence of remote URL → remote
    /// 3. Default to local
    public static func resolve(
        explicitMode: String?,
        remoteUrl: String?,
        remoteTarget: String?,
        hasCompletedOnboarding: Bool
    ) -> String {
        // If explicit mode is set, use it
        if let mode = explicitMode,
           ["local", "remote", "unconfigured"].contains(mode) {
            return mode
        }

        // If remote URL or target is present, assume remote
        if let url = remoteUrl, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "remote"
        }
        if let target = remoteTarget, !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "remote"
        }

        // Default
        return hasCompletedOnboarding ? "local" : "unconfigured"
    }
}

// MARK: - SSH Arguments Builder

/// Builds SSH command arguments for tunnel creation.
public enum SSHArgumentsBuilder {
    /// Build SSH arguments for port forwarding.
    public static func buildTunnelArgs(
        target: RemoteSSHTarget,
        identity: String?,
        localPort: Int,
        remotePort: Int,
        extraOptions: [String] = []
    ) -> [String] {
        var args: [String] = []

        // Standard tunnel options
        args += [
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UpdateHostKeys=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "TCPKeepAlive=yes",
            "-N",
            "-L", "\(localPort):127.0.0.1:\(remotePort)",
        ]

        // Identity file
        if let identity = identity?.trimmingCharacters(in: .whitespacesAndNewlines),
           !identity.isEmpty {
            let expanded = identity.hasPrefix("~")
                ? (identity as NSString).expandingTildeInPath
                : identity
            args += ["-i", expanded]
        }

        // Port
        if let port = target.port {
            args += ["-p", String(port)]
        }

        // Extra options
        args += extraOptions

        // Target
        let sshTarget: String
        if let user = target.user {
            sshTarget = "\(user)@\(target.host)"
        } else {
            sshTarget = target.host
        }
        args.append(sshTarget)

        return args
    }

    /// Build SSH arguments for a test connection.
    public static func buildTestArgs(
        target: RemoteSSHTarget,
        identity: String?,
        timeoutSeconds: Int = 5
    ) -> [String] {
        var args: [String] = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(timeoutSeconds)",
            "-o", "StrictHostKeyChecking=accept-new",
        ]

        if let identity = identity?.trimmingCharacters(in: .whitespacesAndNewlines),
           !identity.isEmpty {
            let expanded = identity.hasPrefix("~")
                ? (identity as NSString).expandingTildeInPath
                : identity
            args += ["-i", expanded]
        }

        if let port = target.port {
            args += ["-p", String(port)]
        }

        let sshTarget: String
        if let user = target.user {
            sshTarget = "\(user)@\(target.host)"
        } else {
            sshTarget = target.host
        }
        args += [sshTarget, "echo", "mcclaw-test-ok"]

        return args
    }
}

// MARK: - IPC Frame Header

/// 4-byte big-endian length prefix for IPC frames.
public struct IPCFrameHeaderKit: Sendable {
    public let length: UInt32

    public init(length: UInt32) {
        self.length = length
    }

    public init(bytes: [UInt8]) {
        precondition(bytes.count >= 4)
        self.length = UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
    }

    public var bytes: [UInt8] {
        [
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF),
        ]
    }
}
