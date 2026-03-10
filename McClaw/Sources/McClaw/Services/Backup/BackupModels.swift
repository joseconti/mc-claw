import Foundation

/// Top-level encrypted wrapper written to .mcb files.
struct EncryptedBackup: Codable {
    /// Format version for forward compatibility.
    let version: Int
    /// Random salt for PBKDF2 key derivation (16 bytes).
    let salt: Data
    /// AES-GCM nonce + ciphertext + tag combined.
    let sealedData: Data
}

/// Plaintext container with all exportable app data.
/// Contains the entire ~/.mcclaw/ directory (except logs) plus decrypted credentials.
struct BackupContainer: Codable {
    let version: Int
    let createdAt: Date
    let appVersion: String

    /// Connector credentials (decrypted for portability across machines).
    var credentials: [BackupCredentialEntry]

    /// All files from ~/.mcclaw/ stored with their relative paths.
    var directoryFiles: [BackupFileEntry]
}

struct BackupCredentialEntry: Codable {
    let instanceId: String
    let credentialData: Data
}

struct BackupFileEntry: Codable {
    /// Path relative to ~/.mcclaw/ (e.g. "sessions/abc123.json", "skills/my-skill/SKILL.md").
    let relativePath: String
    let data: Data
}

struct BackupImportResult: Sendable {
    let credentialsRestored: Int
    let filesRestored: Int
    let warnings: [String]
}
