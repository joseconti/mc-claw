import Foundation
import Logging

/// Monitors local application health via periodic polling.
@MainActor
@Observable
final class HealthStore {
    static let shared = HealthStore()

    var isHealthy: Bool = true
    var lastError: String?
    var cliCount: Int = 0
    var memoryUsageMB: Int = 0

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

    /// Collect local health metrics.
    private func fetchHealth() async {
        let info = ProcessInfo.processInfo
        let memBytes = info.physicalMemory
        memoryUsageMB = Int(memBytes / (1024 * 1024))
        cliCount = AppState.shared.availableCLIs.filter(\.isInstalled).count
        isHealthy = cliCount > 0
        lastError = nil
    }

    private init() {}
}
