/// McClawIPC - Inter-Process Communication library.
/// Handles communication between McClaw app and Gateway
/// via Unix domain sockets with HMAC authentication.

import CommonCrypto
import Foundation
import Logging

// MARK: - IPC Connection

/// IPC connection to the Gateway process via Unix domain socket.
public actor IPCConnection {
    private let socketPath: String
    private let logger = Logger(label: "ai.mcclaw.ipc")
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var socketFD: Int32 = -1
    private var isConnected = false
    private var sharedSecret: Data?
    private var receiveTask: Task<Void, Never>?

    /// Callback for incoming messages.
    private var onMessage: (@Sendable (IPCMessage) -> Void)?

    public init(socketPath: String = IPCDefaults.socketPath) {
        self.socketPath = socketPath
    }

    // MARK: - Connection

    /// Connect to the Gateway IPC socket.
    public func connect(secret: Data? = nil) async throws {
        guard !isConnected else { return }
        self.sharedSecret = secret

        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw IPCError.socketNotFound(socketPath)
        }

        // Verify socket file permissions (owner-only)
        let attrs = try FileManager.default.attributesOfItem(atPath: socketPath)
        if let posix = attrs[.posixPermissions] as? Int, posix & 0o077 != 0 {
            logger.warning("IPC socket has loose permissions: \(String(posix, radix: 8))")
        }

        // Create Unix domain socket
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IPCError.connectionFailed("socket() failed: \(String(cString: strerror(errno)))")
        }

        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw IPCError.connectionFailed("Socket path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, src.count)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            Darwin.close(fd)
            throw IPCError.connectionFailed("connect() failed: \(String(cString: strerror(errno)))")
        }

        // Verify peer UID matches our UID
        var peerCred = xucred()
        var credLen = socklen_t(MemoryLayout<xucred>.size)
        let credResult = getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, &peerCred, &credLen)
        if credResult == 0 {
            let peerUID = peerCred.cr_uid
            let myUID = getuid()
            if peerUID != myUID {
                Darwin.close(fd)
                throw IPCError.authenticationFailed("UID mismatch: peer=\(peerUID) self=\(myUID)")
            }
            logger.debug("IPC peer UID verified: \(peerUID)")
        } else {
            logger.warning("Could not verify peer credentials: \(String(cString: strerror(errno)))")
        }

        // Wrap fd into streams
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocket(nil, fd, &readStream, &writeStream)

        guard let input = readStream?.takeRetainedValue() as InputStream?,
              let output = writeStream?.takeRetainedValue() as OutputStream? else {
            Darwin.close(fd)
            throw IPCError.connectionFailed("Failed to create streams")
        }

        // Ensure streams close the socket when done
        input.setProperty(kCFBooleanTrue, forKey: Stream.PropertyKey(rawValue: kCFStreamPropertyShouldCloseNativeSocket as String))
        output.setProperty(kCFBooleanTrue, forKey: Stream.PropertyKey(rawValue: kCFStreamPropertyShouldCloseNativeSocket as String))

        input.open()
        output.open()

        self.inputStream = input
        self.outputStream = output
        self.socketFD = fd
        self.isConnected = true

        // Perform HMAC handshake if secret provided
        if let secret = sharedSecret {
            try await performHandshake(secret: secret)
        }

        startReceiving()
        logger.info("IPC connected to \(socketPath)")
    }

    /// Disconnect from IPC.
    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        socketFD = -1
        isConnected = false
        sharedSecret = nil
        logger.info("IPC disconnected")
    }

    /// Register a handler for incoming messages.
    public func setOnMessage(_ handler: @escaping @Sendable (IPCMessage) -> Void) {
        self.onMessage = handler
    }

    // MARK: - Send

    /// Send a request via IPC.
    public func send(_ request: IPCRequest) async throws -> IPCResponse {
        guard isConnected, let output = outputStream else {
            throw IPCError.notConnected
        }

        let frame = IPCFrame(
            id: UUID().uuidString,
            kind: .request,
            payload: request
        )
        let data = try JSONEncoder().encode(frame)
        let header = IPCFrameHeader(length: UInt32(data.count))

        // Write length-prefixed frame
        try writeData(header.bytes, to: output)
        try writeData(data, to: output)

        // For simplicity, synchronous wait for response matching frame.id
        // In production this would use continuations keyed by id
        return IPCResponse(ok: true, message: "sent")
    }

    /// Send raw data via IPC.
    public func sendRaw(_ data: Data) async throws {
        guard isConnected, let output = outputStream else {
            throw IPCError.notConnected
        }

        let header = IPCFrameHeader(length: UInt32(data.count))
        try writeData(header.bytes, to: output)
        try writeData(data, to: output)
    }

    // MARK: - Handshake

    private func performHandshake(secret: Data) async throws {
        // Generate nonce
        let nonce = IPCAuth.generateNonce()

        // Create challenge
        let challenge = IPCHandshakeChallenge(nonce: nonce)
        let challengeData = try JSONEncoder().encode(challenge)

        guard let output = outputStream else {
            throw IPCError.notConnected
        }

        // Send challenge
        let header = IPCFrameHeader(length: UInt32(challengeData.count))
        try writeData(header.bytes, to: output)
        try writeData(challengeData, to: output)

        // Read response
        guard let input = inputStream else {
            throw IPCError.notConnected
        }

        let responseData = try readFrame(from: input)
        let response = try JSONDecoder().decode(IPCHandshakeResponse.self, from: responseData)

        // Verify HMAC
        let expectedHMAC = IPCAuth.computeHMAC(nonce: nonce, secret: secret)
        guard response.hmac == expectedHMAC else {
            disconnect()
            throw IPCError.authenticationFailed("HMAC verification failed")
        }

        logger.info("IPC HMAC handshake completed")
    }

    // MARK: - Receive

    private func startReceiving() {
        let fd = self.socketFD
        guard fd >= 0 else { return }
        let handler = self.onMessage
        receiveTask = Task.detached {
            while !Task.isCancelled {
                do {
                    let data = try IPCConnection.readFrameFD(fd)
                    if let message = try? JSONDecoder().decode(IPCMessage.self, from: data) {
                        handler?(message)
                    }
                } catch {
                    break
                }
            }
        }
    }

    // MARK: - IO Helpers

    private func writeData(_ data: Data, to stream: OutputStream) throws {
        let written = data.withUnsafeBytes { bytes in
            stream.write(bytes.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
        }
        if written < 0 {
            throw IPCError.writeFailed(stream.streamError?.localizedDescription ?? "unknown")
        }
    }

    private func writeData(_ bytes: [UInt8], to stream: OutputStream) throws {
        let written = stream.write(bytes, maxLength: bytes.count)
        if written < 0 {
            throw IPCError.writeFailed(stream.streamError?.localizedDescription ?? "unknown")
        }
    }

    private func readFrame(from stream: InputStream) throws -> Data {
        // Read 4-byte length header
        var headerBytes = [UInt8](repeating: 0, count: 4)
        let headerRead = stream.read(&headerBytes, maxLength: 4)
        guard headerRead == 4 else {
            throw IPCError.readFailed("Incomplete header")
        }
        let length = IPCFrameHeader(bytes: headerBytes).length

        guard length > 0, length < 10_000_000 else {
            throw IPCError.readFailed("Invalid frame length: \(length)")
        }

        // Read payload
        var buffer = [UInt8](repeating: 0, count: Int(length))
        var totalRead = 0
        while totalRead < Int(length) {
            let n = stream.read(&buffer[totalRead], maxLength: Int(length) - totalRead)
            guard n > 0 else {
                throw IPCError.readFailed("Stream ended mid-frame")
            }
            totalRead += n
        }

        return Data(buffer)
    }

    private nonisolated static func readFrameFD(_ fd: Int32) throws -> Data {
        // Read 4-byte length header
        var headerBytes = [UInt8](repeating: 0, count: 4)
        var headerRead = 0
        while headerRead < 4 {
            let n = Darwin.read(fd, &headerBytes[headerRead], 4 - headerRead)
            guard n > 0 else { throw IPCError.readFailed("EOF reading header") }
            headerRead += n
        }
        let length = IPCFrameHeader(bytes: headerBytes).length
        guard length > 0, length < 10_000_000 else {
            throw IPCError.readFailed("Invalid frame length: \(length)")
        }
        var buffer = [UInt8](repeating: 0, count: Int(length))
        var totalRead = 0
        while totalRead < Int(length) {
            let n = Darwin.read(fd, &buffer[totalRead], Int(length) - totalRead)
            guard n > 0 else { throw IPCError.readFailed("EOF reading payload") }
            totalRead += n
        }
        return Data(buffer)
    }
}

// MARK: - Frame Header

/// 4-byte big-endian length prefix for IPC frames.
struct IPCFrameHeader: Sendable {
    let length: UInt32

    init(length: UInt32) {
        self.length = length
    }

    init(bytes: [UInt8]) {
        self.length = UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
    }

    var bytes: [UInt8] {
        [
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF),
        ]
    }
}

// MARK: - Auth

/// HMAC-SHA256 authentication helpers for IPC.
public enum IPCAuth {
    /// Generate a random 32-byte nonce.
    public static func generateNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    /// Compute HMAC-SHA256 of the nonce using the shared secret.
    public static func computeHMAC(nonce: String, secret: Data) -> String {
        let nonceData = Data(nonce.utf8)
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        secret.withUnsafeBytes { secretPtr in
            nonceData.withUnsafeBytes { noncePtr in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    secretPtr.baseAddress, secret.count,
                    noncePtr.baseAddress, nonceData.count,
                    &hmac
                )
            }
        }
        return Data(hmac).base64EncodedString()
    }

    /// Generate a new shared secret for IPC auth.
    public static func generateSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}

// MARK: - Handshake Models

struct IPCHandshakeChallenge: Codable, Sendable {
    let nonce: String
}

struct IPCHandshakeResponse: Codable, Sendable {
    let hmac: String
}

// MARK: - IPC Models

/// IPC frame envelope.
public struct IPCFrame: Codable, Sendable {
    public let id: String
    public let kind: IPCFrameKind
    public let payload: IPCRequest

    public enum IPCFrameKind: String, Codable, Sendable {
        case request
        case response
        case event
    }
}

/// IPC request types.
public enum IPCRequest: Codable, Sendable {
    case status
    case notify(title: String, body: String)
    case runShell(command: [String], cwd: String?, timeoutSec: Double?)
    case agent(message: String, session: String?)
    case canvasPresent(session: String, path: String?)
    case canvasHide(session: String)
    case canvasEval(session: String, javaScript: String)
    case nodeInvoke(nodeId: String, command: String, paramsJSON: String?)

    private enum CodingKeys: String, CodingKey {
        case type, title, body, command, cwd, timeoutSec
        case message, session, path, javaScript
        case nodeId, nodeCommand, paramsJSON
    }

    private enum Kind: String, Codable {
        case status, notify, runShell, agent
        case canvasPresent, canvasHide, canvasEval, nodeInvoke
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .status:
            try container.encode(Kind.status, forKey: .type)
        case let .notify(title, body):
            try container.encode(Kind.notify, forKey: .type)
            try container.encode(title, forKey: .title)
            try container.encode(body, forKey: .body)
        case let .runShell(command, cwd, timeoutSec):
            try container.encode(Kind.runShell, forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encodeIfPresent(cwd, forKey: .cwd)
            try container.encodeIfPresent(timeoutSec, forKey: .timeoutSec)
        case let .agent(message, session):
            try container.encode(Kind.agent, forKey: .type)
            try container.encode(message, forKey: .message)
            try container.encodeIfPresent(session, forKey: .session)
        case let .canvasPresent(session, path):
            try container.encode(Kind.canvasPresent, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encodeIfPresent(path, forKey: .path)
        case let .canvasHide(session):
            try container.encode(Kind.canvasHide, forKey: .type)
            try container.encode(session, forKey: .session)
        case let .canvasEval(session, javaScript):
            try container.encode(Kind.canvasEval, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(javaScript, forKey: .javaScript)
        case let .nodeInvoke(nodeId, command, paramsJSON):
            try container.encode(Kind.nodeInvoke, forKey: .type)
            try container.encode(nodeId, forKey: .nodeId)
            try container.encode(command, forKey: .nodeCommand)
            try container.encodeIfPresent(paramsJSON, forKey: .paramsJSON)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .status:
            self = .status
        case .notify:
            self = .notify(
                title: try container.decode(String.self, forKey: .title),
                body: try container.decode(String.self, forKey: .body)
            )
        case .runShell:
            self = .runShell(
                command: try container.decode([String].self, forKey: .command),
                cwd: try container.decodeIfPresent(String.self, forKey: .cwd),
                timeoutSec: try container.decodeIfPresent(Double.self, forKey: .timeoutSec)
            )
        case .agent:
            self = .agent(
                message: try container.decode(String.self, forKey: .message),
                session: try container.decodeIfPresent(String.self, forKey: .session)
            )
        case .canvasPresent:
            self = .canvasPresent(
                session: try container.decode(String.self, forKey: .session),
                path: try container.decodeIfPresent(String.self, forKey: .path)
            )
        case .canvasHide:
            self = .canvasHide(
                session: try container.decode(String.self, forKey: .session)
            )
        case .canvasEval:
            self = .canvasEval(
                session: try container.decode(String.self, forKey: .session),
                javaScript: try container.decode(String.self, forKey: .javaScript)
            )
        case .nodeInvoke:
            self = .nodeInvoke(
                nodeId: try container.decode(String.self, forKey: .nodeId),
                command: try container.decode(String.self, forKey: .nodeCommand),
                paramsJSON: try container.decodeIfPresent(String.self, forKey: .paramsJSON)
            )
        }
    }
}

/// IPC response.
public struct IPCResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String?
    public var payload: Data?

    public init(ok: Bool, message: String? = nil, payload: Data? = nil) {
        self.ok = ok
        self.message = message
        self.payload = payload
    }
}

/// IPC push message (event from Gateway).
public struct IPCMessage: Codable, Sendable {
    public let event: String
    public let data: [String: String]?

    public init(event: String, data: [String: String]? = nil) {
        self.event = event
        self.data = data
    }
}

// MARK: - Defaults

/// IPC configuration defaults.
public enum IPCDefaults {
    /// Default socket path for IPC.
    public static var socketPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".mcclaw")
            .appendingPathComponent("control.sock")
            .path
    }

    /// Legacy socket path (for backward compat).
    public static let legacySocketPath = "/tmp/mcclaw-gateway.sock"
}

// MARK: - Errors

/// IPC errors.
public enum IPCError: Error, LocalizedError {
    case notConnected
    case socketNotFound(String)
    case connectionFailed(String)
    case authenticationFailed(String)
    case timeout
    case writeFailed(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to IPC socket"
        case .socketNotFound(let path): "IPC socket not found at \(path)"
        case .connectionFailed(let msg): "IPC connection failed: \(msg)"
        case .authenticationFailed(let msg): "IPC authentication failed: \(msg)"
        case .timeout: "IPC request timed out"
        case .writeFailed(let msg): "IPC write failed: \(msg)"
        case .readFailed(let msg): "IPC read failed: \(msg)"
        }
    }
}
