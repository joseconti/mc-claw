import Foundation
import Logging

/// Connects McClaw to a relay server for remote mobile access.
/// McClaw acts as "host" — the relay forwards frames between mobile devices and this Mac.
actor RelayClient {
    static let shared = RelayClient()

    private let logger = Logger(label: "ai.mcclaw.relay")
    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private(set) var state: RelayState = .disconnected
    private var config: RelayConfig?

    /// Callback when a message arrives from a remote device via the relay.
    private var onMessage: (@Sendable (String, Data) -> Void)?

    func setOnMessage(_ handler: @escaping @Sendable (String, Data) -> Void) {
        self.onMessage = handler
    }

    // MARK: - Connect / Disconnect

    /// Connect to the relay server.
    /// For McClaw Cloud mode, automatically obtains/refreshes JWT before connecting.
    func connect(config: RelayConfig) async {
        self.config = config
        guard state != .connected else { return }

        state = .connecting
        await notifyStateChange()

        // For McClaw Cloud: obtain JWT if needed
        var activeConfig = config
        if config.mode == .mcclawCloud {
            if !config.isJWTValid {
                if let refreshed = await refreshJWT(config: config) {
                    activeConfig = refreshed
                    self.config = refreshed
                } else {
                    state = .error("Failed to authenticate with McClaw Cloud")
                    await notifyStateChange()
                    return
                }
            }
        }

        guard var urlComponents = URLComponents(string: activeConfig.url) else {
            logger.error("Invalid relay URL: \(activeConfig.url)")
            state = .error("Invalid relay URL")
            await notifyStateChange()
            return
        }

        // Ensure path ends with /relay
        if !urlComponents.path.hasSuffix("/v1/relay") {
            urlComponents.path = urlComponents.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/relay"
        }

        guard let url = urlComponents.url else {
            state = .error("Cannot build relay URL")
            await notifyStateChange()
            return
        }

        var request = URLRequest(url: url)
        request.setValue(activeConfig.relayToken, forHTTPHeaderField: "X-Relay-Token")
        request.setValue("host", forHTTPHeaderField: "X-Client-Type")

        // JWT auth for McClaw Cloud
        if let jwt = activeConfig.jwt, !jwt.isEmpty {
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        startReceiving()
        startPing()

        state = .connected
        await notifyStateChange()
        logger.info("Connected to relay at \(url)")
    }

    // MARK: - JWT Auth

    /// Auth endpoint URL for McClaw Cloud.
    private static let authURL = URL(string: "https://api.joseconti.com/v1/mcclaw/relay-auth/")!

    /// Obtain a new JWT from api.joseconti.com using the license key.
    private func refreshJWT(config: RelayConfig) async -> RelayConfig? {
        guard let licenseKey = config.licenseKey, !licenseKey.isEmpty else {
            logger.error("No license key configured for McClaw Cloud relay")
            return nil
        }

        var request = URLRequest(url: Self.authURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: String] = ["license_key": licenseKey]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            if http.statusCode == 200 {
                let result = try JSONDecoder().decode(RelayAuthResponse.self, from: data)
                var updated = config
                updated.jwt = result.token
                updated.jwtExpiresAt = ISO8601DateFormatter().date(from: result.expiresAt)
                logger.info("Relay JWT obtained, expires at \(result.expiresAt)")
                return updated
            } else {
                let errorBody = String(data: data, encoding: .utf8) ?? ""
                logger.error("Relay auth failed (HTTP \(http.statusCode)): \(errorBody)")
                return nil
            }
        } catch {
            logger.error("Relay auth request failed: \(error)")
            return nil
        }
    }

    /// Disconnect from the relay.
    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        Task { await notifyStateChange() }
        logger.info("Disconnected from relay")
    }

    // MARK: - Send

    /// Send a message to a specific device via the relay.
    func send(to deviceId: String, message: MobileOutgoingMessage) async {
        guard let data = try? JSONEncoder().encode(message) else { return }
        guard var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        dict["targetDeviceId"] = deviceId

        guard let payload = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: payload, encoding: .utf8) else { return }

        do {
            try await webSocketTask?.send(.string(text))
        } catch {
            logger.error("Relay send error: \(error)")
        }
    }

    /// Broadcast a message to all connected devices via the relay.
    func broadcast(_ message: MobileOutgoingMessage) async {
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }
        do {
            try await webSocketTask?.send(.string(text))
        } catch {
            logger.error("Relay broadcast error: \(error)")
        }
    }

    // MARK: - Receive

    private func startReceiving() {
        guard let wsTask = webSocketTask else { return }
        Task { [weak self, wsTask] in
            do {
                while wsTask.state == .running {
                    let message = try await wsTask.receive()
                    switch message {
                    case .string(let text):
                        await self?.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self?.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                await self?.handleDisconnect(error: error)
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        // Check if it's a relay control message
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String, type.hasPrefix("relay.") {
            handleRelayMessage(type: type, json: json)
            return
        }

        // Forward to MobileServer for processing
        // Extract deviceId from the message if present
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let deviceId = json["deviceId"] as? String {
            onMessage?(deviceId, data)
        }
    }

    private func handleRelayMessage(type: String, json: [String: Any]) {
        switch type {
        case "relay.connected":
            let devices = json["connectedDevices"] as? Int ?? 0
            logger.info("Relay connected as host. \(devices) device(s) online.")
        case "relay.device.connected":
            if let deviceId = json["deviceId"] as? String {
                logger.info("Device \(deviceId) connected via relay")
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .deviceConnectionChanged,
                        object: DeviceConnectionEvent(deviceId: deviceId, connected: true, timestamp: Date())
                    )
                }
            }
        case "relay.device.disconnected":
            if let deviceId = json["deviceId"] as? String {
                logger.info("Device \(deviceId) disconnected from relay")
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .deviceConnectionChanged,
                        object: DeviceConnectionEvent(deviceId: deviceId, connected: false, timestamp: Date())
                    )
                }
            }
        default:
            break
        }
    }

    private func handleDisconnect(error: Error) {
        logger.error("Relay disconnected: \(error)")
        state = .disconnected
        Task { await notifyStateChange() }

        // Auto-reconnect if we have config
        if let config = self.config {
            reconnectTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                logger.info("Attempting relay reconnect...")
                await connect(config: config)
            }
        }
    }

    // MARK: - Ping

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { break }
                await sendPingFrame()
            }
        }
    }

    private func sendPingFrame() {
        webSocketTask?.sendPing { [weak self] error in
            if let error {
                Task { await self?.handleDisconnect(error: error) }
            }
        }
    }

    // MARK: - State

    private func notifyStateChange() async {
        let currentState = state
        await MainActor.run {
            NotificationCenter.default.post(
                name: .relayStateChanged,
                object: currentState
            )
        }
    }
}

// MARK: - Relay State

enum RelayState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Relay Config

struct RelayConfig: Codable, Sendable {
    /// Relay server URL (e.g. "wss://relay.joseconti.com")
    var url: String
    /// Unique token identifying this McClaw instance on the relay
    var relayToken: String
    /// McClaw license key (used to obtain JWT for McClaw Cloud)
    var licenseKey: String?
    /// Cached JWT for McClaw Cloud relay auth
    var jwt: String?
    /// JWT expiration date
    var jwtExpiresAt: Date?
    /// Connection mode
    var mode: RelayMode = .disabled

    enum RelayMode: String, Codable, Sendable {
        case disabled
        case selfHosted
        case mcclawCloud
    }

    /// Whether the cached JWT is still valid (with 1h margin).
    var isJWTValid: Bool {
        guard let jwt, !jwt.isEmpty, let exp = jwtExpiresAt else { return false }
        return exp.timeIntervalSinceNow > 3600 // Refresh 1h before expiry
    }
}

// MARK: - Notifications

// MARK: - Auth Response

private struct RelayAuthResponse: Codable, Sendable {
    let token: String
    let expiresAt: String
    let ttl: Int

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case ttl
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let relayStateChanged = Notification.Name("relayStateChanged")
}
