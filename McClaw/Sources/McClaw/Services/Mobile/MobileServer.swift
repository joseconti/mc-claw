import Foundation
import Logging
import Network

/// Embedded WebSocket server for mobile device connections.
/// Runs inside McClaw — mobile apps connect directly to this server.
actor MobileServer {
    static let shared = MobileServer()

    private let logger = Logger(label: "ai.mcclaw.mobile.server")
    private var listener: NWListener?
    private var connections: [String: MobileConnection] = [:]  // deviceId -> connection
    private(set) var isRunning = false
    private(set) var port: UInt16 = 3578

    /// Callback when a mobile device sends a message.
    private var onMessage: (@MainActor @Sendable (String, MobileIncomingMessage) -> Void)?

    func setOnMessage(_ handler: @escaping @MainActor @Sendable (String, MobileIncomingMessage) -> Void) {
        self.onMessage = handler
    }

    // MARK: - Start / Stop

    /// Start the WebSocket server on the given port.
    func start(port: UInt16 = 3578) throws {
        guard !isRunning else { return }
        self.port = port

        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let nwListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = nwListener

        nwListener.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleListenerState(state) }
        }

        nwListener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleNewConnection(connection) }
        }

        nwListener.start(queue: .global(qos: .userInitiated))
        isRunning = true
        logger.info("Mobile server starting on port \(port)")
    }

    /// Stop the server and disconnect all devices.
    func stop() {
        listener?.cancel()
        listener = nil
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        isRunning = false
        logger.info("Mobile server stopped")
    }

    // MARK: - Connection Management

    /// Get IDs of currently connected devices.
    var connectedDeviceIds: Set<String> {
        Set(connections.keys)
    }

    /// Send a message to a specific device.
    func send(to deviceId: String, message: MobileOutgoingMessage) {
        guard let conn = connections[deviceId] else {
            logger.warning("Cannot send to \(deviceId): not connected")
            return
        }
        conn.send(message)
    }

    /// Send a message to all connected devices.
    func broadcast(_ message: MobileOutgoingMessage) {
        for (_, conn) in connections {
            conn.send(message)
        }
    }

    /// Disconnect a specific device.
    func disconnect(deviceId: String) {
        connections[deviceId]?.cancel()
        connections.removeValue(forKey: deviceId)
        logger.info("Device \(deviceId) disconnected")
        notifyConnectionChange(deviceId: deviceId, connected: false)
    }

    // MARK: - Private

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let actualPort = listener?.port?.rawValue {
                self.port = actualPort
                logger.info("Mobile server ready on port \(actualPort)")
            }
            isRunning = true
        case .failed(let error):
            logger.error("Mobile server failed: \(error)")
            isRunning = false
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let conn = MobileConnection(connection: nwConnection)
        logger.info("New mobile connection from \(nwConnection.endpoint)")

        conn.start { [weak self] deviceId, message in
            Task { await self?.handleMessage(deviceId: deviceId, message: message) }
        } onAuthenticated: { [weak self] deviceId in
            Task { await self?.registerDevice(deviceId: deviceId, connection: conn) }
        } onDisconnected: { [weak self] deviceId in
            Task { await self?.handleDisconnect(deviceId: deviceId) }
        }
    }

    private func registerDevice(deviceId: String, connection: MobileConnection) {
        connections[deviceId] = connection
        logger.info("Device \(deviceId) authenticated and registered")
        notifyConnectionChange(deviceId: deviceId, connected: true)
    }

    private func handleMessage(deviceId: String, message: MobileIncomingMessage) {
        let handler = self.onMessage
        Task { @MainActor in
            handler?(deviceId, message)
        }
    }

    private func handleDisconnect(deviceId: String) {
        connections.removeValue(forKey: deviceId)
        logger.info("Device \(deviceId) disconnected")
        notifyConnectionChange(deviceId: deviceId, connected: false)
    }

    private func notifyConnectionChange(deviceId: String, connected: Bool) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .deviceConnectionChanged,
                object: DeviceConnectionEvent(deviceId: deviceId, connected: connected, timestamp: Date())
            )
        }
    }
}

// MARK: - Mobile Connection

/// Wraps a single NWConnection for a mobile device.
final class MobileConnection: Sendable {
    private let connection: NWConnection
    private let logger = Logger(label: "ai.mcclaw.mobile.conn")

    private let _deviceId = LockedValue<String?>(nil)
    var deviceId: String? { _deviceId.value }

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(
        onMessage: @escaping @Sendable (String, MobileIncomingMessage) -> Void,
        onAuthenticated: @escaping @Sendable (String) -> Void,
        onDisconnected: @escaping @Sendable (String) -> Void
    ) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.receiveLoop(onMessage: onMessage, onAuthenticated: onAuthenticated, onDisconnected: onDisconnected)
            case .failed, .cancelled:
                if let id = self.deviceId {
                    onDisconnected(id)
                }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    func send(_ message: MobileOutgoingMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])

        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.error("Send error: \(error)")
            }
        })
    }

    func cancel() {
        connection.cancel()
    }

    private func receiveLoop(
        onMessage: @escaping @Sendable (String, MobileIncomingMessage) -> Void,
        onAuthenticated: @escaping @Sendable (String) -> Void,
        onDisconnected: @escaping @Sendable (String) -> Void
    ) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self else { return }

            if let error {
                self.logger.error("Receive error: \(error)")
                if let id = self.deviceId { onDisconnected(id) }
                return
            }

            guard let data = content else {
                self.receiveLoop(onMessage: onMessage, onAuthenticated: onAuthenticated, onDisconnected: onDisconnected)
                return
            }

            // Check if it's a WebSocket text message
            let isText = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                .map { $0 as? NWProtocolWebSocket.Metadata }
                .flatMap { $0?.opcode == .text ? true : nil } ?? true

            if isText, let msg = try? JSONDecoder().decode(MobileIncomingMessage.self, from: data) {
                if msg.type == "auth", let devId = msg.deviceId {
                    self._deviceId.value = devId
                    // Validate token via DevicePairingService
                    Task {
                        let valid = await DevicePairingService.shared.validateToken(msg.token ?? "", deviceId: devId)
                        if valid {
                            onAuthenticated(devId)
                            self.send(MobileOutgoingMessage(type: "auth.ok"))
                        } else {
                            self.send(MobileOutgoingMessage(type: "auth.error", error: "Invalid token"))
                            self.connection.cancel()
                        }
                    }
                } else if let devId = self.deviceId {
                    onMessage(devId, msg)
                }
            }

            // Continue receiving
            self.receiveLoop(onMessage: onMessage, onAuthenticated: onAuthenticated, onDisconnected: onDisconnected)
        }
    }
}

// MARK: - Thread-safe Value

/// Simple thread-safe wrapper for a mutable value.
final class LockedValue<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) { _value = value }

    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// MARK: - Mobile Messages

/// Message received from a mobile device.
struct MobileIncomingMessage: Codable, Sendable {
    let type: String
    let deviceId: String?
    let token: String?
    let text: String?
    let sessionKey: String?
    let data: [String: String]?
}

/// Message sent to a mobile device.
struct MobileOutgoingMessage: Codable, Sendable {
    let type: String
    var text: String?
    var error: String?
    var data: [String: String]?
}
