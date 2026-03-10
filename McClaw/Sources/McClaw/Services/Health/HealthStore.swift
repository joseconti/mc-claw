import Foundation
import Logging
import McClawProtocol

/// Monitors Gateway and channel health via periodic polling.
@MainActor
@Observable
final class HealthStore {
    static let shared = HealthStore()

    var latestSnapshot: HealthSnapshot?
    var isHealthy: Bool { latestSnapshot != nil }
    var lastError: String?

    private let logger = Logger(label: "ai.mcclaw.health")
    private var pollingTask: Task<Void, Never>?

    /// Start periodic health polling (every 60 seconds).
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchHealth()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Stop health polling.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Fetch health once (manual refresh).
    func refresh() async {
        await fetchHealth()
    }

    /// Fetch health snapshot from Gateway.
    private func fetchHealth() async {
        do {
            let response = try await GatewayConnectionService.shared.call(method: "health.snapshot")
            if response.ok, let result = response.result {
                let snapshot = try parseSnapshot(from: result)
                latestSnapshot = snapshot
                lastError = nil

                // Sync channel statuses to AppState
                AppState.shared.activeChannels = snapshot.channelStatuses
                logger.debug("Health snapshot updated: \(snapshot.activeConnections) connections")
            }
        } catch {
            lastError = error.localizedDescription
            logger.error("Health fetch failed: \(error)")
        }
    }

    /// Parse AnyCodableValue into HealthSnapshot.
    private func parseSnapshot(from value: AnyCodableValue) throws -> HealthSnapshot {
        let data = try JSONEncoder().encode(value)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HealthSnapshot.self, from: data)
    }

    private init() {}
}
