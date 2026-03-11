import Foundation

// MARK: - Enums

enum CronSessionTarget: String, CaseIterable, Identifiable, Codable, Sendable {
    case main
    case isolated

    var id: String { rawValue }
}

enum CronWakeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case now
    case nextHeartbeat = "next-heartbeat"

    var id: String { rawValue }
}

enum CronDeliveryMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case announce
    case webhook

    var id: String { rawValue }
}

// MARK: - Delivery

struct CronDeliveryTarget: Codable, Equatable, Sendable {
    var mode: CronDeliveryMode
    var channel: String
    var to: String?
    var bestEffort: Bool?
}

struct CronDelivery: Codable, Equatable, Sendable {
    var mode: CronDeliveryMode
    var channel: String?
    var to: String?
    var bestEffort: Bool?
    var targets: [CronDeliveryTarget]?

    /// All effective delivery targets (flattened from single + multi).
    var allTargets: [CronDeliveryTarget] {
        var result: [CronDeliveryTarget] = []
        if let targets, !targets.isEmpty {
            result.append(contentsOf: targets)
        }
        if let channel, !channel.isEmpty {
            result.append(CronDeliveryTarget(mode: mode, channel: channel, to: to, bestEffort: bestEffort))
        }
        return result
    }
}

// MARK: - Schedule

enum CronSchedule: Codable, Equatable, Sendable {
    case at(at: String)
    case every(everyMs: Int, anchorMs: Int?)
    case cron(expr: String, tz: String?)

    enum CodingKeys: String, CodingKey { case kind, at, atMs, everyMs, anchorMs, expr, tz }

    var kind: String {
        switch self {
        case .at: "at"
        case .every: "every"
        case .cron: "cron"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "at":
            if let at = try container.decodeIfPresent(String.self, forKey: .at),
               !at.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                self = .at(at: at)
                return
            }
            if let atMs = try container.decodeIfPresent(Int.self, forKey: .atMs) {
                let date = Date(timeIntervalSince1970: TimeInterval(atMs) / 1000)
                self = .at(at: Self.formatIsoDate(date))
                return
            }
            throw DecodingError.dataCorruptedError(
                forKey: .at, in: container, debugDescription: "Missing schedule.at")
        case "every":
            self = try .every(
                everyMs: container.decode(Int.self, forKey: .everyMs),
                anchorMs: container.decodeIfPresent(Int.self, forKey: .anchorMs))
        case "cron":
            self = try .cron(
                expr: container.decode(String.self, forKey: .expr),
                tz: container.decodeIfPresent(String.self, forKey: .tz))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "Unknown schedule kind: \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case let .at(at):
            try container.encode(at, forKey: .at)
        case let .every(everyMs, anchorMs):
            try container.encode(everyMs, forKey: .everyMs)
            try container.encodeIfPresent(anchorMs, forKey: .anchorMs)
        case let .cron(expr, tz):
            try container.encode(expr, forKey: .expr)
            try container.encodeIfPresent(tz, forKey: .tz)
        }
    }

    static func parseAtDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let date = makeIsoFormatter(withFractional: true).date(from: trimmed) { return date }
        return makeIsoFormatter(withFractional: false).date(from: trimmed)
    }

    static func formatIsoDate(_ date: Date) -> String {
        makeIsoFormatter(withFractional: false).string(from: date)
    }

    private static func makeIsoFormatter(withFractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}

// MARK: - Payload

enum CronPayload: Codable, Equatable, Sendable {
    case systemEvent(text: String)
    case agentTurn(
        message: String,
        thinking: String?,
        timeoutSeconds: Int?,
        deliver: Bool?,
        channel: String?,
        to: String?,
        bestEffortDeliver: Bool?,
        connectorBindings: [ConnectorBinding]?)

    enum CodingKeys: String, CodingKey {
        case kind, text, message, thinking, timeoutSeconds, deliver, channel, provider, to, bestEffortDeliver, connectorBindings
    }

    var kind: String {
        switch self {
        case .systemEvent: "systemEvent"
        case .agentTurn: "agentTurn"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "systemEvent":
            self = try .systemEvent(text: container.decode(String.self, forKey: .text))
        case "agentTurn":
            self = try .agentTurn(
                message: container.decode(String.self, forKey: .message),
                thinking: container.decodeIfPresent(String.self, forKey: .thinking),
                timeoutSeconds: container.decodeIfPresent(Int.self, forKey: .timeoutSeconds),
                deliver: container.decodeIfPresent(Bool.self, forKey: .deliver),
                channel: container.decodeIfPresent(String.self, forKey: .channel)
                    ?? container.decodeIfPresent(String.self, forKey: .provider),
                to: container.decodeIfPresent(String.self, forKey: .to),
                bestEffortDeliver: container.decodeIfPresent(Bool.self, forKey: .bestEffortDeliver),
                connectorBindings: container.decodeIfPresent([ConnectorBinding].self, forKey: .connectorBindings))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "Unknown payload kind: \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case let .systemEvent(text):
            try container.encode(text, forKey: .text)
        case let .agentTurn(message, thinking, timeoutSeconds, deliver, channel, to, bestEffortDeliver, connectorBindings):
            try container.encode(message, forKey: .message)
            try container.encodeIfPresent(thinking, forKey: .thinking)
            try container.encodeIfPresent(timeoutSeconds, forKey: .timeoutSeconds)
            try container.encodeIfPresent(deliver, forKey: .deliver)
            try container.encodeIfPresent(channel, forKey: .channel)
            try container.encodeIfPresent(to, forKey: .to)
            try container.encodeIfPresent(bestEffortDeliver, forKey: .bestEffortDeliver)
            try container.encodeIfPresent(connectorBindings, forKey: .connectorBindings)
        }
    }
}

// MARK: - Job State

struct CronJobState: Codable, Equatable, Sendable {
    var nextRunAtMs: Int?
    var runningAtMs: Int?
    var lastRunAtMs: Int?
    var lastStatus: String?
    var lastError: String?
    var lastDurationMs: Int?
}

// MARK: - Job

struct CronJob: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let agentId: String?
    var name: String
    var description: String?
    var enabled: Bool
    var deleteAfterRun: Bool?
    let createdAtMs: Int
    let updatedAtMs: Int
    let schedule: CronSchedule
    let sessionTarget: CronSessionTarget
    let wakeMode: CronWakeMode
    let payload: CronPayload
    let delivery: CronDelivery?
    let state: CronJobState

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled job" : trimmed
    }

    var nextRunDate: Date? {
        guard let ms = state.nextRunAtMs else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    var lastRunDate: Date? {
        guard let ms = state.lastRunAtMs else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
}

// MARK: - Events & Logs

struct CronEvent: Codable, Sendable {
    let jobId: String
    let action: String
    let runAtMs: Int?
    let durationMs: Int?
    let status: String?
    let error: String?
    let summary: String?
    let nextRunAtMs: Int?
}

struct CronRunLogEntry: Codable, Identifiable, Sendable {
    var id: String { "\(jobId)-\(ts)" }

    let ts: Int
    let jobId: String
    let action: String
    let status: String?
    let error: String?
    let summary: String?
    let runAtMs: Int?
    let durationMs: Int?
    let nextRunAtMs: Int?

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
    }

    var runDate: Date? {
        guard let runAtMs else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(runAtMs) / 1000)
    }
}

// MARK: - API Responses

struct CronListResponse: Codable, Sendable {
    let jobs: [CronJob]
}

struct CronRunsResponse: Codable, Sendable {
    let entries: [CronRunLogEntry]
}

struct CronStatusResponse: Codable, Sendable {
    let enabled: Bool?
    let storePath: String?
    let nextWakeAtMs: Int?
}

// MARK: - Duration Formatting

enum DurationFormatting {
    static func concise(ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let seconds = ms / 1000
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }

    static func parseDurationMs(_ input: String) -> Int? {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }

        let pattern = "^(\\d+(?:\\.\\d+)?)(ms|s|m|h|d)$"
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = rx.firstMatch(in: raw, range: NSRange(location: 0, length: raw.utf16.count))
        else { return nil }

        func group(_ idx: Int) -> String {
            let range = match.range(at: idx)
            guard let r = Range(range, in: raw) else { return "" }
            return String(raw[r])
        }
        let n = Double(group(1)) ?? 0
        if !n.isFinite || n <= 0 { return nil }
        let unit = group(2).lowercased()
        let factor: Double = switch unit {
        case "ms": 1
        case "s": 1000
        case "m": 60_000
        case "h": 3_600_000
        default: 86_400_000
        }
        return Int(floor(n * factor))
    }
}
