import CryptoKit
import Foundation
import Logging

/// Exports and imports encrypted backups of all McClaw configuration.
actor BackupService {
    static let shared = BackupService()

    private let logger = Logger(label: "ai.mcclaw.backup")

    private let backupVersion = 1

    private var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw")
    }

    // MARK: - Export

    func exportBackup(password: String) async throws -> Data {
        logger.info("Starting backup export")

        // Collect ALL files from ~/.mcclaw/ except regenerable/downloadable directories
        let excludedDirs: Set<String> = ["logs", "bitnet", "tools"]
        let directoryFiles = Self.collectAllFiles(in: configDir, excluding: excludedDirs)

        logger.info("Collected \(directoryFiles.count) files from ~/.mcclaw/")

        // Also collect credentials via FileCredentialStore (decrypted, for portability)
        let credEntries = FileCredentialStore.shared.listAll()
        let credentials = credEntries.map { entry in
            BackupCredentialEntry(
                instanceId: entry.instanceId,
                credentialData: (try? JSONEncoder().encode(entry.credentials)) ?? Data()
            )
        }

        // Build container
        let container = BackupContainer(
            version: backupVersion,
            createdAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            credentials: credentials,
            directoryFiles: directoryFiles
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(container)

        logger.info("Backup container encoded: \(plaintext.count) bytes")

        // Derive key from password using HKDF (safe, no raw pointers)
        let salt = Self.generateRandom(count: 16)
        let key = Self.deriveKey(password: password, salt: salt)

        // Encrypt with AES-256-GCM
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let sealedData = sealed.combined else {
            throw BackupError.encryptionFailed
        }

        // Wrap in EncryptedBackup
        let encrypted = EncryptedBackup(
            version: backupVersion,
            salt: salt,
            sealedData: sealedData
        )

        let result = try JSONEncoder().encode(encrypted)
        logger.info("Backup exported: \(credentials.count) credentials, \(directoryFiles.count) files, \(result.count) bytes total")
        return result
    }

    // MARK: - Import

    func importBackup(data: Data, password: String) async throws -> BackupImportResult {
        logger.info("Starting backup import (\(data.count) bytes)")

        // 1. Decode encrypted wrapper
        let encrypted = try JSONDecoder().decode(EncryptedBackup.self, from: data)
        guard encrypted.version <= backupVersion else {
            throw BackupError.unsupportedVersion(encrypted.version)
        }

        // 2. Decrypt
        let key = Self.deriveKey(password: password, salt: encrypted.salt)
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: encrypted.sealedData)
        } catch {
            throw BackupError.wrongPassword
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw BackupError.wrongPassword
        }

        // 3. Decode container
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let container = try decoder.decode(BackupContainer.self, from: plaintext)

        var warnings: [String] = []
        var credCount = 0
        var fileCount = 0

        let fm = FileManager.default

        // 4. Ensure config directory exists
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)

        // 5. Restore all files to ~/.mcclaw/
        for entry in container.directoryFiles {
            let url = configDir.appendingPathComponent(entry.relativePath)
            let dir = url.deletingLastPathComponent()
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try entry.data.write(to: url, options: .atomic)
                fileCount += 1
            } catch {
                warnings.append("Failed to restore \(entry.relativePath): \(error.localizedDescription)")
            }
        }

        // 6. Restore credentials via FileCredentialStore
        // (credentials are stored decrypted in the backup for portability across machines;
        //  FileCredentialStore re-encrypts them with this machine's hardware UUID)
        for entry in container.credentials {
            do {
                let creds = try JSONDecoder().decode(ConnectorCredentials.self, from: entry.credentialData)
                try FileCredentialStore.shared.save(instanceId: entry.instanceId, credentials: creds)
                credCount += 1
            } catch {
                warnings.append("Failed to restore credentials for \(entry.instanceId): \(error.localizedDescription)")
            }
        }

        let result = BackupImportResult(
            credentialsRestored: credCount,
            filesRestored: fileCount,
            warnings: warnings
        )
        logger.info("Backup imported: \(credCount) credentials, \(fileCount) files, \(warnings.count) warnings")
        return result
    }

    // MARK: - Crypto

    /// Derives an AES-256 key from a password + salt using HKDF-SHA256.
    /// Uses CryptoKit only (no CommonCrypto, no unsafe pointers).
    private nonisolated static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        // Create input key material from password bytes
        let passwordData = Data(password.utf8)
        let inputKey = SymmetricKey(data: passwordData)

        // Use HKDF to derive a 256-bit key
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("ai.mcclaw.backup.v1".utf8),
            outputByteCount: 32
        )
    }

    private nonisolated static func generateRandom(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    // MARK: - File Collection

    /// Collects all files from a directory recursively.
    /// Runs as a nonisolated static to avoid NSDirectoryEnumerator async context issues.
    private nonisolated static func collectAllFiles(
        in baseDir: URL,
        excluding excludedDirs: Set<String>
    ) -> [BackupFileEntry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: baseDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [BackupFileEntry] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else { continue }

            let fullPath = fileURL.path
            let basePath = baseDir.path
            guard fullPath.count > basePath.count + 1 else { continue }
            let relativePath = String(fullPath.dropFirst(basePath.count + 1))

            // Skip excluded directories
            let topDir = relativePath.split(separator: "/").first.map(String.init) ?? ""
            if excludedDirs.contains(topDir) { continue }

            guard let data = try? Data(contentsOf: fileURL) else { continue }
            entries.append(BackupFileEntry(relativePath: relativePath, data: data))
        }
        return entries
    }
}

// MARK: - Errors

enum BackupError: LocalizedError {
    case encryptionFailed
    case wrongPassword
    case unsupportedVersion(Int)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            String(localized: "Failed to encrypt backup", bundle: .module)
        case .wrongPassword:
            String(localized: "Wrong password or corrupted backup", bundle: .module)
        case .unsupportedVersion(let v):
            String(localized: "Unsupported backup version: \(v)", bundle: .module)
        case .importFailed(let reason):
            String(localized: "Import failed: \(reason)", bundle: .module)
        }
    }
}
