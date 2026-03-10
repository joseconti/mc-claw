import Foundation
import Logging
import CryptoKit
import McClawKit

/// Manages device pairing, token generation, and device persistence locally in McClaw.
/// No external Gateway dependency — everything runs inside the Mac app.
@MainActor @Observable
final class DevicePairingService {
    static let shared = DevicePairingService()

    private let logger = Logger(label: "ai.mcclaw.device.pairing")
    private let storePath: URL

    /// All paired devices.
    private(set) var devices: [PairedDevice] = []

    /// Active pairing codes awaiting mobile scan.
    private(set) var pendingCodes: [PendingPairingCode] = []

    /// Current pending pairing request (mobile scanned, awaiting user approval).
    var pendingRequest: PairingRequest?

    private init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw")
        storePath = configDir.appendingPathComponent("devices.json")
        loadDevices()
    }

    // MARK: - Pairing Code Generation

    /// Generate a new pairing code and return the QR payload.
    func generatePairingCode(serverPort: UInt16) -> PairingQRPayload {
        // Get local IP for the QR
        let localIP = Self.localIPAddress() ?? "127.0.0.1"
        let code = Self.randomCode()
        let expires = Int(Date().timeIntervalSince1970) + 300  // 5 minutes

        let pending = PendingPairingCode(
            code: code,
            expires: Date().addingTimeInterval(300),
            createdAt: Date()
        )
        pendingCodes.append(pending)

        // Clean expired codes
        pendingCodes.removeAll { $0.expires < Date() }

        logger.info("Generated pairing code: \(code)")

        return PairingQRPayload(
            v: 1,
            gateway: "ws://\(localIP):\(serverPort)",
            gatewayRemote: nil,
            code: code,
            expires: expires
        )
    }

    // MARK: - Pairing Flow

    /// Called when a mobile device submits a pairing code.
    /// Returns true if the code is valid and request is now pending approval.
    func requestPairing(code: String, deviceName: String, devicePlatform: DevicePlatform, deviceId: String) -> Bool {
        guard let index = pendingCodes.firstIndex(where: { $0.code == code }) else {
            logger.warning("Invalid pairing code: \(code)")
            return false
        }

        let pending = pendingCodes[index]
        guard pending.expires > Date() else {
            pendingCodes.remove(at: index)
            logger.warning("Expired pairing code: \(code)")
            return false
        }

        // Set pending request for UI to show approve/reject
        pendingRequest = PairingRequest(
            code: code,
            deviceName: deviceName,
            devicePlatform: devicePlatform,
            deviceId: deviceId
        )

        logger.info("Pairing requested by \(deviceName) (\(devicePlatform.rawValue))")
        return true
    }

    /// Approve a pending pairing request. Returns the JWT token for the device.
    func approvePairing(code: String) -> String? {
        guard let request = pendingRequest, request.code == code else { return nil }

        // Generate token
        let token = Self.generateToken(deviceId: request.deviceId)

        // Create paired device
        let device = PairedDevice(
            deviceId: request.deviceId,
            name: request.deviceName,
            platform: request.devicePlatform,
            pairedAt: Date(),
            lastSeen: Date(),
            permissions: DevicePermissions()
        )

        devices.append(device)
        saveDevices()

        // Clean up
        pendingCodes.removeAll { $0.code == code }
        pendingRequest = nil

        logger.info("Approved pairing for \(device.name)")
        return token
    }

    /// Reject a pending pairing request.
    func rejectPairing(code: String) {
        pendingCodes.removeAll { $0.code == code }
        pendingRequest = nil
        logger.info("Rejected pairing for code \(code)")
    }

    // MARK: - Device Management

    /// Revoke access for a paired device.
    func revokeDevice(deviceId: String) {
        devices.removeAll { $0.deviceId == deviceId }
        saveDevices()
        // Disconnect if connected
        Task {
            await MobileServer.shared.disconnect(deviceId: deviceId)
        }
        logger.info("Revoked device \(deviceId)")
    }

    /// Update permissions for a device.
    func updatePermissions(deviceId: String, permissions: DevicePermissions) {
        guard let index = devices.firstIndex(where: { $0.deviceId == deviceId }) else { return }
        devices[index].permissions = permissions
        saveDevices()
        logger.info("Updated permissions for \(deviceId)")
    }

    /// Update last seen timestamp for a device.
    func updateLastSeen(deviceId: String) {
        guard let index = devices.firstIndex(where: { $0.deviceId == deviceId }) else { return }
        devices[index].lastSeen = Date()
        saveDevices()
    }

    // MARK: - Token Validation

    /// Validate a device token. Called from MobileServer on auth.
    nonisolated func validateToken(_ token: String, deviceId: String) async -> Bool {
        // Token format: base64(deviceId:timestamp:signature)
        guard let data = Data(base64Encoded: token),
              let tokenString = String(data: data, encoding: .utf8) else {
            return false
        }

        let components = tokenString.split(separator: ":", maxSplits: 2)
        guard components.count == 3 else { return false }

        let tokenDeviceId = String(components[0])
        guard tokenDeviceId == deviceId else { return false }

        // Verify device is still paired
        let isPaired = await MainActor.run { devices.contains { $0.deviceId == deviceId } }
        return isPaired
    }

    // MARK: - Persistence

    /// Reload devices from disk (e.g. after restoring a backup).
    func reloadFromDisk() {
        loadDevices()
    }

    private func loadDevices() {
        guard FileManager.default.fileExists(atPath: storePath.path) else { return }
        do {
            let data = try Data(contentsOf: storePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            devices = try decoder.decode([PairedDevice].self, from: data)
            logger.info("Loaded \(devices.count) paired devices")
        } catch {
            logger.error("Failed to load devices: \(error)")
        }
    }

    private func saveDevices() {
        do {
            let dir = storePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(devices)
            try data.write(to: storePath, options: .atomic)
        } catch {
            logger.error("Failed to save devices: \(error)")
        }
    }

    // MARK: - Helpers

    /// Generate a HMAC-based token for a device.
    private static func generateToken(deviceId: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let secret = SymmetricKey(size: .bits256)
        let message = "\(deviceId):\(timestamp)"
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: secret
        )
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        let token = "\(deviceId):\(timestamp):\(signatureHex)"
        return Data(token.utf8).base64EncodedString()
    }

    /// Generate a random pairing code (XXXX-XXXX-XXXX hex uppercase).
    private static func randomCode() -> String {
        func segment() -> String {
            let bytes = (0..<2).map { _ in UInt8.random(in: 0...255) }
            return bytes.map { String(format: "%02X", $0) }.joined()
        }
        return "\(segment())-\(segment())-\(segment())"
    }

    /// Get the local network IP address.
    static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }  // IPv4 only

            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }  // WiFi/Ethernet

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            )
            address = String(cString: hostname)
            if address != nil { break }
        }
        return address
    }
}

// MARK: - Pending Pairing Code

/// A generated pairing code awaiting mobile scan.
struct PendingPairingCode: Identifiable {
    let id = UUID()
    let code: String
    let expires: Date
    let createdAt: Date
}
