import Foundation
import Logging

/// Manages the SSH tunnel lifecycle for remote Gateway connections.
/// Handles start, stop, restart with backoff, and tunnel reuse.
actor RemoteTunnelManager {
    static let shared = RemoteTunnelManager()

    private let logger = Logger(label: "ai.mcclaw.remote-tunnel")
    private var controlTunnel: RemotePortTunnel?
    private var restartInFlight = false
    private var lastRestartAt: Date?
    private let restartBackoffSeconds: TimeInterval = 2.0

    /// The local port of the running tunnel, if any.
    var tunnelPort: UInt16? {
        guard let tunnel = controlTunnel,
              tunnel.process.isRunning else { return nil }
        return tunnel.localPort
    }

    /// Check if a tunnel is currently running and healthy.
    var isRunning: Bool {
        controlTunnel?.process.isRunning ?? false
    }

    /// Ensure an SSH tunnel is running for the gateway port.
    /// Returns the local forwarded port.
    func ensureControlTunnel(
        target: SSHTarget,
        identity: String?,
        remotePort: Int = 3577
    ) async throws -> UInt16 {
        // Reuse existing tunnel if healthy
        if let existingPort = await controlTunnelPortIfRunning() {
            return existingPort
        }

        await waitForRestartBackoffIfNeeded()

        let desiredPort = UInt16(remotePort)
        let tunnel = try await RemotePortTunnel.create(
            target: target,
            identity: identity,
            remotePort: remotePort,
            preferredLocalPort: desiredPort,
            allowRandomLocalPort: true
        )

        self.controlTunnel = tunnel
        self.endRestart()
        let resolvedPort = tunnel.localPort ?? desiredPort
        logger.info("SSH tunnel ready, localPort=\(resolvedPort)")
        return resolvedPort
    }

    /// Stop all tunnels.
    func stopAll() {
        controlTunnel?.terminate()
        controlTunnel = nil
        logger.info("All tunnels stopped")
    }

    // MARK: - Reuse / Health

    private func controlTunnelPortIfRunning() async -> UInt16? {
        guard !restartInFlight else {
            logger.info("Control tunnel restart in flight; skipping reuse")
            return nil
        }

        if let tunnel = controlTunnel,
           tunnel.process.isRunning,
           let local = tunnel.localPort {
            logger.info("Reusing active SSH tunnel on localPort=\(local)")
            return local
        }

        // Tunnel not running or dead
        if controlTunnel != nil {
            logger.warning("SSH tunnel process died; clearing")
            await beginRestart()
            controlTunnel?.terminate()
            controlTunnel = nil
        }

        return nil
    }

    // MARK: - Restart Backoff

    private func beginRestart() async {
        guard !restartInFlight else { return }
        restartInFlight = true
        lastRestartAt = Date()
        logger.info("Control tunnel restart started")
    }

    private func endRestart() {
        if restartInFlight {
            restartInFlight = false
            logger.info("Control tunnel restart finished")
        }
    }

    private func waitForRestartBackoffIfNeeded() async {
        guard let last = lastRestartAt else { return }
        let elapsed = Date().timeIntervalSince(last)
        let remaining = restartBackoffSeconds - elapsed
        guard remaining > 0 else { return }
        logger.info("Restart backoff: waiting \(remaining)s")
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }
}
