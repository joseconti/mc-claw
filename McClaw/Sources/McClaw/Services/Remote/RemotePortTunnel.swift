import Foundation
import Logging
import Network

/// Port forwarding tunnel for remote mode.
/// Uses `ssh -N -L` to forward the remote gateway port to localhost.
final class RemotePortTunnel: Sendable {
    private static let logger = Logger(label: "ai.mcclaw.remote.tunnel")

    let process: Process
    let localPort: UInt16?
    private let stderrHandle: FileHandle?

    private init(process: Process, localPort: UInt16?, stderrHandle: FileHandle?) {
        self.process = process
        self.localPort = localPort
        self.stderrHandle = stderrHandle
    }

    deinit {
        Self.cleanupStderr(stderrHandle)
        process.terminate()
    }

    func terminate() {
        Self.cleanupStderr(stderrHandle)
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    /// Create an SSH tunnel forwarding remotePort to a local port.
    static func create(
        target: SSHTarget,
        identity: String?,
        remotePort: Int,
        preferredLocalPort: UInt16? = nil,
        allowRandomLocalPort: Bool = true
    ) async throws -> RemotePortTunnel {
        let localPort = try await findPort(
            preferred: preferredLocalPort,
            allowRandom: allowRandomLocalPort
        )

        var options: [String] = [
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

        if let identity = identity?.trimmingCharacters(in: .whitespacesAndNewlines),
           !identity.isEmpty {
            let expandedPath = (identity as NSString).expandingTildeInPath
            options += ["-i", expandedPath]
        }

        if let port = target.port {
            options += ["-p", String(port)]
        }

        let sshTarget: String
        if let user = target.user {
            sshTarget = "\(user)@\(target.host)"
        } else {
            sshTarget = target.host
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = options + [sshTarget]

        let pipe = Pipe()
        process.standardError = pipe
        let stderrHandle = pipe.fileHandleForReading

        // Drain stderr to prevent ssh from blocking
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                Self.cleanupStderr(handle)
                return
            }
            if let line = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty {
                Self.logger.error("ssh tunnel stderr: \(line)")
            }
        }
        process.terminationHandler = { _ in
            Self.cleanupStderr(stderrHandle)
        }

        try process.run()

        // Give ssh 150ms to fail immediately (e.g. port in use)
        try? await Task.sleep(nanoseconds: 150_000_000)
        if !process.isRunning {
            let stderr = Self.drainStderr(stderrHandle)
            let msg = stderr.isEmpty ? "ssh tunnel exited immediately" : "ssh tunnel failed: \(stderr)"
            throw RemoteTunnelError.sshFailed(msg)
        }

        Self.logger.info("SSH tunnel started: localPort=\(localPort) → remote=\(remotePort)")
        return RemotePortTunnel(process: process, localPort: localPort, stderrHandle: stderrHandle)
    }

    // MARK: - Port Finding

    private static func findPort(preferred: UInt16?, allowRandom: Bool) async throws -> UInt16 {
        if let preferred, portIsFree(preferred) { return preferred }
        if let preferred, !allowRandom {
            throw RemoteTunnelError.portUnavailable(Int(preferred))
        }

        return try await withCheckedThrowingContinuation { cont in
            let queue = DispatchQueue(label: "ai.mcclaw.remote.tunnel.port", qos: .utility)
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                listener.newConnectionHandler = { connection in connection.cancel() }
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if let port = listener.port?.rawValue {
                            listener.stateUpdateHandler = nil
                            listener.cancel()
                            cont.resume(returning: port)
                        }
                    case let .failed(error):
                        listener.stateUpdateHandler = nil
                        listener.cancel()
                        cont.resume(throwing: error)
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    static func portIsFree(_ port: UInt16) -> Bool {
        canBindIPv4(port) && canBindIPv6(port)
    }

    private static func canBindIPv4(_ port: UInt16) -> Bool {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout.size(ofValue: one)))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private static func canBindIPv6(_ port: UInt16) -> Bool {
        let fd = Darwin.socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout.size(ofValue: one)))

        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian
        var loopback = in6_addr()
        _ = withUnsafeMutablePointer(to: &loopback) { ptr in
            inet_pton(AF_INET6, "::1", ptr)
        }
        addr.sin6_addr = loopback

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        return result == 0
    }

    // MARK: - Stderr Helpers

    private static func cleanupStderr(_ handle: FileHandle?) {
        guard let handle else { return }
        handle.readabilityHandler = nil
        try? handle.close()
    }

    private static func drainStderr(_ handle: FileHandle) -> String {
        handle.readabilityHandler = nil
        defer { try? handle.close() }
        do {
            let data = try handle.readToEnd() ?? Data()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}

// MARK: - SSH Target

/// Parsed SSH target (user@host:port).
struct SSHTarget: Sendable {
    let user: String?
    let host: String
    let port: Int?

    /// Parse "user@host:port" or "user@host" or "host:port" or "host".
    static func parse(_ target: String) -> SSHTarget? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var user: String?
        var remainder = trimmed

        if let atIndex = remainder.firstIndex(of: "@") {
            user = String(remainder[..<atIndex])
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
        return SSHTarget(user: user, host: host, port: port)
    }
}

// MARK: - Errors

enum RemoteTunnelError: Error, LocalizedError {
    case notConfigured
    case sshFailed(String)
    case portUnavailable(Int)
    case tunnelNotRunning

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Remote mode is not configured"
        case .sshFailed(let msg): "SSH tunnel failed: \(msg)"
        case .portUnavailable(let port): "Local port \(port) is unavailable"
        case .tunnelNotRunning: "SSH tunnel is not running"
        }
    }
}
