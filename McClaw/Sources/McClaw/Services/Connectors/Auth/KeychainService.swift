import Foundation
import Security
import Logging

/// Manages credential storage for connectors.
/// Primary storage is FileCredentialStore (survives app rebuilds).
/// Keychain is kept as a migration fallback for existing credentials.
actor KeychainService {
    static let shared = KeychainService()

    private let logger = Logger(label: "ai.mcclaw.keychain")
    private let servicePrefix = "ai.mcclaw.connector"

    // MARK: - Low-level Keychain CRUD (legacy, used for migration)

    private func keychainSave(service: String, account: String, data: Data) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func keychainLoad(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func keychainDelete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - High-level Credentials API (delegates to FileCredentialStore)

    func saveCredentials(instanceId: String, credentials: ConnectorCredentials) throws {
        // Save to file-based store (survives rebuilds)
        try FileCredentialStore.shared.save(instanceId: instanceId, credentials: credentials)

        // Also save to Keychain as secondary copy (best-effort)
        let service = "\(servicePrefix).\(instanceId)"
        if let data = try? JSONEncoder().encode(credentials) {
            try? keychainSave(service: service, account: "credentials", data: data)
        }

        logger.info("Credentials saved for connector \(instanceId)")
    }

    func loadCredentials(instanceId: String) -> ConnectorCredentials? {
        // 1. Try file-based store first (primary)
        if let creds = FileCredentialStore.shared.load(instanceId: instanceId) {
            return creds
        }

        // 2. Fallback: try Keychain (migration from pre-file-store versions)
        let service = "\(servicePrefix).\(instanceId)"
        if let data = keychainLoad(service: service, account: "credentials"),
           let creds = try? JSONDecoder().decode(ConnectorCredentials.self, from: data) {
            logger.info("Migrating credentials from Keychain to file store for \(instanceId)")
            // Migrate to file store
            try? FileCredentialStore.shared.save(instanceId: instanceId, credentials: creds)
            return creds
        }

        return nil
    }

    func deleteCredentials(instanceId: String) {
        // Delete from both stores
        FileCredentialStore.shared.delete(instanceId: instanceId)

        let service = "\(servicePrefix).\(instanceId)"
        keychainDelete(service: service, account: "credentials")

        logger.info("Credentials deleted for connector \(instanceId)")
    }

    func hasCredentials(instanceId: String) -> Bool {
        FileCredentialStore.shared.hasCredentials(instanceId: instanceId)
            || loadCredentials(instanceId: instanceId) != nil
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case notFound
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Failed to save to Keychain (status: \(status))"
        case .notFound:
            "Credential not found in Keychain"
        case .decodingFailed:
            "Failed to decode credential data"
        }
    }
}
