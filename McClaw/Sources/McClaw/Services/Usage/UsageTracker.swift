import Foundation
import Logging

/// Tracks token usage and estimated cost per CLI provider.
/// Persisted to `~/.mcclaw/usage.json`.
@MainActor
@Observable
final class UsageTracker {
    static let shared = UsageTracker()

    /// Usage stats per provider
    private(set) var stats: [String: ProviderUsage] = [:]

    /// Total tokens across all providers for current session
    var totalInputTokens: Int { stats.values.reduce(0) { $0 + $1.inputTokens } }
    var totalOutputTokens: Int { stats.values.reduce(0) { $0 + $1.outputTokens } }
    var totalEstimatedCost: Double { stats.values.reduce(0) { $0 + $1.estimatedCost } }

    private let logger = Logger(label: "ai.mcclaw.usage")
    private let fileManager = FileManager.default

    private var usageFileURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/usage.json")
    }

    private init() {
        load()
    }

    /// Record token usage for a provider.
    func record(provider: String, inputTokens: Int, outputTokens: Int, pricing: ModelPricing? = nil) {
        var usage = stats[provider] ?? ProviderUsage(providerId: provider)
        usage.inputTokens += inputTokens
        usage.outputTokens += outputTokens
        usage.requestCount += 1
        usage.lastUsed = Date()

        // Estimate cost if pricing available
        if let pricing {
            let inputCost = Double(inputTokens) * (pricing.inputPerMillion ?? 0) / 1_000_000
            let outputCost = Double(outputTokens) * (pricing.outputPerMillion ?? 0) / 1_000_000
            usage.estimatedCost += inputCost + outputCost
        }

        stats[provider] = usage
        save()
    }

    /// Reset all usage stats.
    func reset() {
        stats.removeAll()
        save()
    }

    /// Reset stats for a specific provider.
    func reset(provider: String) {
        stats.removeValue(forKey: provider)
        save()
    }

    /// Formatted summary string for display.
    func summary(for provider: String) -> String {
        guard let usage = stats[provider] else { return "No usage" }
        let total = usage.inputTokens + usage.outputTokens
        if usage.estimatedCost > 0 {
            return "\(formatTokens(total)) tokens (~$\(String(format: "%.4f", usage.estimatedCost)))"
        }
        return "\(formatTokens(total)) tokens"
    }

    /// Formatted total summary.
    var totalSummary: String {
        let total = totalInputTokens + totalOutputTokens
        if total == 0 { return "No usage" }
        if totalEstimatedCost > 0 {
            return "\(formatTokens(total)) tokens (~$\(String(format: "%.2f", totalEstimatedCost)))"
        }
        return "\(formatTokens(total)) tokens"
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(stats) else { return }
        try? data.write(to: usageFileURL, options: .atomic)
    }

    private func load() {
        guard fileManager.fileExists(atPath: usageFileURL.path),
              let data = try? Data(contentsOf: usageFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        stats = (try? decoder.decode([String: ProviderUsage].self, from: data)) ?? [:]
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}

/// Usage data for a single provider.
struct ProviderUsage: Codable, Sendable {
    let providerId: String
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var requestCount: Int = 0
    var estimatedCost: Double = 0
    var lastUsed: Date?
}
