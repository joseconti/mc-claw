import Foundation
import AuthenticationServices
import Logging
import McClawKit

/// Manages OAuth 2.0 flows for connectors using ASWebAuthenticationSession + PKCE.
@MainActor
final class OAuthService: NSObject {
    static let shared = OAuthService()

    private let logger = Logger(label: "ai.mcclaw.oauth")
    private let redirectURI = "mcclaw://oauth/callback"

    /// Pending OAuth state for CSRF validation and PKCE exchange.
    private var pendingState: String?
    private var pendingCodeVerifier: String?
    private var pendingInstanceId: String?
    private var pendingOAuthConfig: OAuthConfig?
    private var pendingContinuation: CheckedContinuation<ConnectorCredentials, Error>?

    // MARK: - Public API

    /// Start an OAuth 2.0 authorization flow for a connector instance.
    /// Opens the system browser via ASWebAuthenticationSession.
    func startOAuthFlow(
        config: OAuthConfig,
        instanceId: String
    ) async throws -> ConnectorCredentials {
        // Validate client ID is configured
        let resolvedClientId = clientId(for: config)
        guard !resolvedClientId.isEmpty else {
            throw OAuthError.invalidConfiguration("OAuth Client ID is not configured. Enter it in the connector settings before connecting.")
        }

        // Generate PKCE values
        let codeVerifier = ConnectorsKit.generateCodeVerifier()
        let codeChallenge = ConnectorsKit.computeCodeChallenge(from: codeVerifier)

        // Generate state for CSRF protection
        let state = UUID().uuidString

        // Store pending state
        pendingState = state
        pendingCodeVerifier = codeVerifier
        pendingInstanceId = instanceId
        pendingOAuthConfig = config

        // Build authorization URL
        guard let authURL = ConnectorsKit.buildOAuthURL(
            authUrl: config.authUrl,
            clientId: clientId(for: config),
            redirectUri: redirectURI,
            scopes: config.scopes,
            state: state,
            codeChallenge: config.usePKCE ? codeChallenge : nil,
            codeChallengeMethod: config.usePKCE ? "S256" : nil
        ) else {
            throw OAuthError.invalidConfiguration("Failed to build OAuth URL")
        }

        logger.info("Starting OAuth flow for instance \(instanceId)")

        // Use ASWebAuthenticationSession
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation

            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: config.redirectScheme
            ) { [weak self] callbackURL, error in
                // IMPORTANT: This closure runs on an arbitrary XPC queue.
                // Do NOT access @MainActor self here — hop to MainActor first.
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if let error {
                        self.cleanupPendingState()
                        self.pendingContinuation?.resume(throwing: OAuthError.userCancelled(error.localizedDescription))
                        self.pendingContinuation = nil
                        return
                    }

                    guard let callbackURL else {
                        self.cleanupPendingState()
                        self.pendingContinuation?.resume(throwing: OAuthError.noCallbackURL)
                        self.pendingContinuation = nil
                        return
                    }

                    do {
                        let credentials = try await self.handleCallback(url: callbackURL)
                        self.pendingContinuation?.resume(returning: credentials)
                    } catch {
                        self.pendingContinuation?.resume(throwing: error)
                    }
                    self.pendingContinuation = nil
                    self.cleanupPendingState()
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            if !session.start() {
                self.cleanupPendingState()
                continuation.resume(throwing: OAuthError.sessionStartFailed)
                self.pendingContinuation = nil
            }
        }
    }

    /// Exchange a refresh token for new access credentials.
    func refreshAccessToken(
        refreshToken: String,
        config: OAuthConfig
    ) async throws -> ConnectorCredentials {
        var request = URLRequest(url: URL(string: config.tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId(for: config),
        ]

        if let secret = clientSecret(for: config) {
            params["client_secret"] = secret
        }
        request.httpBody = params.urlEncodedData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = ConnectorsKit.parseGoogleAPIError(statusCode: httpResponse.statusCode, body: data)
            throw OAuthError.tokenExchangeFailed(errorMsg)
        }

        return try parseTokenResponse(data, existingRefreshToken: refreshToken)
    }

    // MARK: - Callback Handling

    /// Handle the OAuth callback URL (called from ASWebAuthenticationSession or deep link).
    private func handleCallback(url: URL) async throws -> ConnectorCredentials {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OAuthError.invalidCallbackURL
        }

        let params = components.queryItems?.reduce(into: [String: String]()) {
            $0[$1.name] = $1.value
        } ?? [:]

        // Validate state (CSRF protection)
        guard let returnedState = params["state"], returnedState == pendingState else {
            throw OAuthError.stateMismatch
        }

        // Check for error response
        if let error = params["error"] {
            let description = params["error_description"] ?? error
            throw OAuthError.providerError(description)
        }

        // Extract authorization code
        guard let code = params["code"] else {
            throw OAuthError.noAuthorizationCode
        }

        guard let config = pendingOAuthConfig else {
            throw OAuthError.invalidConfiguration("No pending OAuth config")
        }

        // Exchange code for tokens
        return try await exchangeCodeForTokens(code: code, config: config)
    }

    /// Exchange authorization code for access/refresh tokens.
    private func exchangeCodeForTokens(
        code: String,
        config: OAuthConfig
    ) async throws -> ConnectorCredentials {
        var request = URLRequest(url: URL(string: config.tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientId(for: config),
        ]

        if let secret = clientSecret(for: config) {
            params["client_secret"] = secret
        }

        if config.usePKCE, let verifier = pendingCodeVerifier {
            params["code_verifier"] = verifier
        }

        request.httpBody = params.urlEncodedData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = ConnectorsKit.parseGoogleAPIError(statusCode: httpResponse.statusCode, body: data)
            logger.error("Token exchange failed: \(errorMsg)")
            throw OAuthError.tokenExchangeFailed(errorMsg)
        }

        return try parseTokenResponse(data)
    }

    // MARK: - Token Response Parsing

    private func parseTokenResponse(_ data: Data, existingRefreshToken: String? = nil) throws -> ConnectorCredentials {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.invalidTokenResponse
        }

        guard let accessToken = json["access_token"] as? String else {
            throw OAuthError.invalidTokenResponse
        }

        let refreshToken = json["refresh_token"] as? String ?? existingRefreshToken
        let expiresIn = json["expires_in"] as? Int ?? 3600
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))

        return ConnectorCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            apiKey: nil,
            expiresAt: expiresAt
        )
    }

    // MARK: - Helpers

    /// Get the OAuth client ID: per-config first, then global fallback.
    private func clientId(for config: OAuthConfig) -> String {
        if let id = config.clientId, !id.isEmpty { return id }
        return ConnectorStore.shared.oauthClientId ?? ""
    }

    /// Get the OAuth client secret: per-config first, then global fallback.
    private func clientSecret(for config: OAuthConfig) -> String? {
        if let secret = config.clientSecret, !secret.isEmpty { return secret }
        if let secret = ConnectorStore.shared.oauthClientSecret, !secret.isEmpty { return secret }
        return nil
    }

    private func cleanupPendingState() {
        pendingState = nil
        pendingCodeVerifier = nil
        pendingInstanceId = nil
        pendingOAuthConfig = nil
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.mainWindow ?? ASPresentationAnchor()
    }
}

// MARK: - OAuth Errors

enum OAuthError: LocalizedError {
    case invalidConfiguration(String)
    case userCancelled(String)
    case noCallbackURL
    case invalidCallbackURL
    case sessionStartFailed
    case stateMismatch
    case providerError(String)
    case noAuthorizationCode
    case tokenExchangeFailed(String)
    case invalidResponse
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg): "Invalid OAuth configuration: \(msg)"
        case .userCancelled(let msg): "OAuth flow cancelled: \(msg)"
        case .noCallbackURL: "No callback URL received"
        case .invalidCallbackURL: "Invalid callback URL"
        case .sessionStartFailed: "Failed to start authentication session"
        case .stateMismatch: "OAuth state mismatch — possible CSRF attack"
        case .providerError(let msg): "Provider error: \(msg)"
        case .noAuthorizationCode: "No authorization code in callback"
        case .tokenExchangeFailed(let msg): "Token exchange failed: \(msg)"
        case .invalidResponse: "Invalid response from token endpoint"
        case .invalidTokenResponse: "Invalid token response format"
        }
    }
}

// MARK: - URL Encoding Helper

private extension Dictionary where Key == String, Value == String {
    var urlEncodedData: Data {
        let encoded = map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }
}
