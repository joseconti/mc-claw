import Foundation

/// Protocol that each connector provider must implement.
/// Providers handle the actual API calls to external services.
protocol ConnectorProvider: Sendable {
    /// The definition ID this provider handles (e.g. "google.gmail").
    static var definitionId: String { get }

    /// Execute a specific action with given parameters.
    func execute(
        action: String,
        params: [String: String],
        credentials: ConnectorCredentials
    ) async throws -> ConnectorActionResult

    /// Test if the credentials are valid and the service is reachable.
    func testConnection(credentials: ConnectorCredentials) async throws -> Bool

    /// Refresh the access token if needed. Returns new credentials or nil if no refresh needed.
    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials?
}

/// Default implementation for providers that don't support token refresh.
extension ConnectorProvider {
    func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials? {
        nil
    }
}

// MARK: - Provider Errors

enum ConnectorProviderError: LocalizedError {
    case unknownAction(String)
    case missingParameter(String)
    case authenticationFailed
    case rateLimited(retryAfter: Int?)
    case apiError(statusCode: Int, message: String)
    case networkError(Error)
    case noCredentials

    var errorDescription: String? {
        switch self {
        case .unknownAction(let action):
            "Unknown action: \(action)"
        case .missingParameter(let param):
            "Missing required parameter: \(param)"
        case .authenticationFailed:
            "Authentication failed. Please reconnect this connector."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                "Rate limited. Retry in \(seconds) seconds."
            } else {
                "Rate limited. Please wait before retrying."
            }
        case .apiError(let code, let message):
            "API error (\(code)): \(message)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        case .noCredentials:
            "No credentials configured. Please connect this connector first."
        }
    }
}
