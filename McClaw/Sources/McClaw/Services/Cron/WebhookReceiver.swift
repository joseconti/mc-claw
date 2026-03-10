import Foundation
import Logging

/// Receives webhook events from Gateway (`webhook.*` RPC methods).
/// Webhooks are registered/managed via GatewayConnectionService and
/// delivered as push events over the existing WebSocket connection.
@MainActor
@Observable
final class WebhookReceiver {
    static let shared = WebhookReceiver()

    var registeredWebhooks: [WebhookEntry] = []
    var lastError: String?
    var isLoading = false

    private let logger = Logger(label: "ai.mcclaw.webhook")

    private init() {}

    // MARK: - CRUD

    func refreshList() async {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let result = try await GatewayConnectionService.shared.webhookList()
            if let result {
                let data = try JSONEncoder().encode(result)
                let response = try JSONDecoder().decode(WebhookListResponse.self, from: data)
                registeredWebhooks = response.webhooks
            } else {
                registeredWebhooks = []
            }
        } catch {
            logger.error("webhook.list failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func register(id: String, url: String, secret: String? = nil) async {
        lastError = nil
        do {
            try await GatewayConnectionService.shared.webhookRegister(id: id, url: url, secret: secret)
            await refreshList()
        } catch {
            logger.error("webhook.register failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func remove(id: String) async {
        lastError = nil
        do {
            try await GatewayConnectionService.shared.webhookRemove(id: id)
            await refreshList()
        } catch {
            logger.error("webhook.remove failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }
}

// MARK: - Models

struct WebhookEntry: Identifiable, Codable, Sendable {
    let id: String
    let url: String
    let createdAtMs: Int?
    let lastTriggeredAtMs: Int?

    var createdDate: Date? {
        guard let ms = createdAtMs else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    var lastTriggeredDate: Date? {
        guard let ms = lastTriggeredAtMs else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
}

struct WebhookListResponse: Codable, Sendable {
    let webhooks: [WebhookEntry]
}
