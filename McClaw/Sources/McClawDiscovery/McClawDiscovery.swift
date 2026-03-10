/// McClawDiscovery - Gateway discovery library.
/// Finds and connects to Gateway instances (local or remote).

import Foundation

/// Discovers Gateway instances on the network or local machine.
public actor GatewayDiscovery {
    public init() {}

    /// Discover local Gateway instance.
    public func discoverLocal(port: Int = 3577) async -> GatewayEndpoint? {
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return GatewayEndpoint(
                    host: "127.0.0.1",
                    port: port,
                    isLocal: true,
                    protocolVersion: 3
                )
            }
        } catch {
            // Gateway not running locally
        }

        return nil
    }

    /// Discover remote Gateway via SSH tunnel.
    public func discoverRemote(host: String, port: Int = 3577, identity: String?) async -> GatewayEndpoint? {
        // TODO: Implement SSH tunnel discovery
        return GatewayEndpoint(
            host: host,
            port: port,
            isLocal: false,
            protocolVersion: 3
        )
    }
}

/// A discovered Gateway endpoint.
public struct GatewayEndpoint: Sendable {
    public let host: String
    public let port: Int
    public let isLocal: Bool
    public let protocolVersion: Int
}
