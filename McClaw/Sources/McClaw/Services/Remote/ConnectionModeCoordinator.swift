import Foundation
import Logging

/// Orchestrates connection mode switching between local and remote Gateway.
/// Handles cleanup of previous mode and setup of new mode.
@MainActor
final class ConnectionModeCoordinator {
    static let shared = ConnectionModeCoordinator()

    private let logger = Logger(label: "ai.mcclaw.connection")
    private var lastMode: ConnectionMode?

    /// Apply the requested connection mode.
    /// Stops services from the previous mode and starts the appropriate ones.
    func apply(mode: ConnectionMode) async {
        if let lastMode, lastMode != mode {
            logger.info("Switching connection mode: \(lastMode.rawValue) → \(mode.rawValue)")
        }
        self.lastMode = mode

        switch mode {
        case .unconfigured:
            await applyUnconfigured()

        case .local:
            await applyLocal()

        case .remote:
            await applyRemote()
        }
    }

    // MARK: - Mode Handlers

    private func applyUnconfigured() async {
        await RemoteTunnelManager.shared.stopAll()
        await GatewayConnectionService.shared.disconnect()
        AppState.shared.gatewayStatus = .disconnected
        logger.info("Connection mode: unconfigured")
    }

    private func applyLocal() async {
        // Stop any remote tunnels
        await RemoteTunnelManager.shared.stopAll()

        // Configure for local Gateway
        let port = AppState.shared.gatewayPort
        let url = URL(string: "ws://127.0.0.1:\(port)/ws")!
        await GatewayConnectionService.shared.setGatewayURL(url)
        await GatewayConnectionService.shared.connect()
        logger.info("Connection mode: local (port \(port))")
    }

    private func applyRemote() async {
        let state = AppState.shared

        switch state.remoteTransport {
        case .ssh:
            await applyRemoteSSH()
        case .direct:
            await applyRemoteDirect()
        }
    }

    private func applyRemoteSSH() async {
        let state = AppState.shared

        guard let targetStr = state.remoteTarget,
              let target = SSHTarget.parse(targetStr) else {
            logger.error("Remote SSH target not configured")
            state.gatewayStatus = .error
            return
        }

        do {
            let localPort = try await RemoteTunnelManager.shared.ensureControlTunnel(
                target: target,
                identity: state.remoteIdentity,
                remotePort: state.gatewayPort
            )

            let url = URL(string: "ws://127.0.0.1:\(localPort)/ws")!
            await GatewayConnectionService.shared.setGatewayURL(url)
            await GatewayConnectionService.shared.connect()
            logger.info("Connection mode: remote SSH via port \(localPort)")
        } catch {
            logger.error("Remote SSH tunnel failed: \(error)")
            state.gatewayStatus = .error
        }
    }

    private func applyRemoteDirect() async {
        let state = AppState.shared

        guard let urlStr = state.remoteUrl,
              let url = GatewayRemoteConfig.normalizeGatewayUrl(urlStr) else {
            logger.error("Remote direct URL not configured or invalid")
            state.gatewayStatus = .error
            return
        }

        await GatewayConnectionService.shared.setGatewayURL(url)
        await GatewayConnectionService.shared.connect()
        logger.info("Connection mode: remote direct at \(url)")
    }
}

// MARK: - Remote Config Helpers

enum GatewayRemoteConfig {
    /// Normalize and validate a gateway URL string.
    /// Only allows ws:// on loopback or wss:// on any host.
    static func normalizeGatewayUrl(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }

        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "ws" || scheme == "wss" else { return nil }

        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !host.isEmpty else { return nil }

        // Plain ws:// only allowed on loopback
        if scheme == "ws", !isLoopbackHost(host) {
            return nil
        }

        // Add default port if missing
        if url.port == nil {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url
            }
            components.port = scheme == "wss" ? 443 : 3577
            return components.url
        }

        return url
    }

    /// Check if a host string is loopback.
    static func isLoopbackHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "127.0.0.1" || lower == "localhost" || lower == "::1"
    }

    /// Default port for a gateway URL scheme.
    static func defaultPort(for url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "wss": return 443
        case "ws": return 3577
        default: return nil
        }
    }
}
