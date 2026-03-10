import Foundation
import Security
import Logging

/// Manages credential storage in macOS Keychain for connectors.
actor KeychainService {
    static let shared = KeychainService()

    private let logger = Logger(label: "ai.mcclaw.keychain")
    private let servicePrefix = "ai.mcclaw.connector"

    // MARK: - Low-level CRUD

    func save(service: String, account: String, data: Data) throws {
        // Delete existing item first (if any)
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

    func load(service: String, account: String) -> Data? {
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

    func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - High-level Credentials API

    func saveCredentials(instanceId: String, credentials: ConnectorCredentials) throws {
        let service = "\(servicePrefix).\(instanceId)"
        let data = try JSONEncoder().encode(credentials)
        try save(service: service, account: "credentials", data: data)
        logger.info("Credentials saved for connector \(instanceId)")
    }

    func loadCredentials(instanceId: String) -> ConnectorCredentials? {
        let service = "\(servicePrefix).\(instanceId)"
        guard let data = load(service: service, account: "credentials") else { return nil }
        return try? JSONDecoder().decode(ConnectorCredentials.self, from: data)
    }

    func deleteCredentials(instanceId: String) {
        let service = "\(servicePrefix).\(instanceId)"
        delete(service: service, account: "credentials")
        logger.info("Credentials deleted for connector \(instanceId)")
    }

    func hasCredentials(instanceId: String) -> Bool {
        loadCredentials(instanceId: instanceId) != nil
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
