import CryptoKit
import Foundation
import IOKit
import Logging

/// Persists connector credentials as AES-256-GCM encrypted files in ~/.mcclaw/credentials/.
/// Uses the machine's hardware UUID as key material so credentials survive app rebuilds
/// and code-signing changes (unlike Keychain, which binds items to the code signature).
final class FileCredentialStore: @unchecked Sendable {
    static let shared = FileCredentialStore()

    private let logger = Logger(label: "ai.mcclaw.file-credentials")

    private var credentialsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw")
            .appendingPathComponent("credentials")
    }

    // MARK: - Public API

    func save(instanceId: String, credentials: ConnectorCredentials) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: credentialsDir.path) {
            try fm.createDirectory(at: credentialsDir, withIntermediateDirectories: true)
        }

        let plaintext = try JSONEncoder().encode(credentials)
        let key = deriveEncryptionKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)

        guard let combined = sealed.combined else {
            throw FileCredentialError.encryptionFailed
        }

        let fileURL = credentialsDir.appendingPathComponent("\(instanceId).enc")
        try combined.write(to: fileURL, options: .atomic)
        logger.info("Credentials saved to file for connector \(instanceId)")
    }

    func load(instanceId: String) -> ConnectorCredentials? {
        let fileURL = credentialsDir.appendingPathComponent("\(instanceId).enc")
        guard let combined = try? Data(contentsOf: fileURL) else { return nil }

        do {
            let key = deriveEncryptionKey()
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            return try JSONDecoder().decode(ConnectorCredentials.self, from: plaintext)
        } catch {
            logger.error("Failed to decrypt credentials for \(instanceId): \(error)")
            return nil
        }
    }

    func delete(instanceId: String) {
        let fileURL = credentialsDir.appendingPathComponent("\(instanceId).enc")
        try? FileManager.default.removeItem(at: fileURL)
        logger.info("Credentials file deleted for connector \(instanceId)")
    }

    func hasCredentials(instanceId: String) -> Bool {
        let fileURL = credentialsDir.appendingPathComponent("\(instanceId).enc")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// List all stored credentials (for backup export).
    func listAll() -> [(instanceId: String, credentials: ConnectorCredentials)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: credentialsDir, includingPropertiesForKeys: nil) else {
            return []
        }

        var result: [(instanceId: String, credentials: ConnectorCredentials)] = []
        for file in files where file.pathExtension == "enc" {
            let instanceId = file.deletingPathExtension().lastPathComponent
            if let creds = load(instanceId: instanceId) {
                result.append((instanceId: instanceId, credentials: creds))
            }
        }
        return result
    }

    // MARK: - Encryption Key

    /// Derives an AES-256 key from the machine's hardware UUID using HKDF.
    /// The hardware UUID (IOPlatformUUID) is stable across app rebuilds, reinstalls,
    /// and code-signing changes — it only changes if the hardware changes.
    private func deriveEncryptionKey() -> SymmetricKey {
        let uuid = Self.machineUUID()
        let inputKey = SymmetricKey(data: Data(uuid.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: Data("ai.mcclaw.credentials.v1".utf8),
            info: Data("file-credential-store".utf8),
            outputByteCount: 32
        )
    }

    /// Returns the IOPlatformUUID (hardware UUID) of this Mac.
    private static func machineUUID() -> String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMasterPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(platformExpert) }

        guard platformExpert != 0,
              let uuidCF = IORegistryEntryCreateCFProperty(
                  platformExpert,
                  "IOPlatformUUID" as CFString,
                  kCFAllocatorDefault,
                  0
              )?.takeRetainedValue() as? String
        else {
            // Fallback to a stable but less unique identifier
            return ProcessInfo.processInfo.hostName
        }
        return uuidCF
    }
}

// MARK: - Errors

enum FileCredentialError: LocalizedError {
    case encryptionFailed
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: "Failed to encrypt credentials"
        case .decryptionFailed: "Failed to decrypt credentials"
        }
    }
}
