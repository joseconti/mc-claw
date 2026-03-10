import Foundation
import Logging

/// Bridge for inter-process communication with the Gateway.
/// Uses Unix domain sockets with HMAC authentication and UID verification.
actor IPCBridge {
    static let shared = IPCBridge()

    private let logger = Logger(label: "ai.mcclaw.ipc-bridge")

    /// Send a command via IPC to the Gateway.
    func send(command: String, payload: Data? = nil) async throws -> Data {
        // TODO: Implement Unix socket communication
        logger.info("IPC send: \(command)")
        return Data()
    }
}
