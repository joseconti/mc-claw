import Foundation
import Logging

/// Manages channel status, configuration, and lifecycle via Gateway RPC.
@MainActor
@Observable
final class ChannelsStore {
    static let shared = ChannelsStore()

    private let logger = Logger(label: "ai.mcclaw.channels")

    // MARK: - State

    var snapshot: ChannelsStatusSnapshot?
    var lastError: String?
    var lastSuccess: Date?
    var isRefreshing = false

    // WhatsApp login state
    var whatsappLoginMessage: String?
    var whatsappLoginQrDataUrl: String?
    var whatsappLoginConnected: Bool?
    var whatsappBusy = false
    var telegramBusy = false

    // Config state
    var configStatus: String?
    var isSavingConfig = false
    var configSchemaLoading = false
    var configSchema: ConfigSchemaNode?
    var configUiHints: [String: ConfigUiHint] = [:]
    var configDraft: [String: Any] = [:]
    var configDirty = false
    var configRoot: [String: Any] = [:]
    var configLoaded = false

    private let pollInterval: TimeInterval = 45
    private var pollTask: Task<Void, Never>?

    private init() {}

    // MARK: - Channel metadata helpers

    func channelMetaEntry(_ id: String) -> ChannelsStatusSnapshot.ChannelUiMetaEntry? {
        snapshot?.channelMeta?.first(where: { $0.id == id })
    }

    func resolveChannelLabel(_ id: String) -> String {
        if let meta = channelMetaEntry(id), !meta.label.isEmpty {
            return meta.label
        }
        if let label = snapshot?.channelLabels[id], !label.isEmpty {
            return label
        }
        return id.capitalized
    }

    func resolveChannelDetailLabel(_ id: String) -> String {
        if let meta = channelMetaEntry(id), !meta.detailLabel.isEmpty {
            return meta.detailLabel
        }
        if let detail = snapshot?.channelDetailLabels?[id], !detail.isEmpty {
            return detail
        }
        return resolveChannelLabel(id)
    }

    func resolveChannelSystemImage(_ id: String) -> String {
        if let meta = channelMetaEntry(id), let symbol = meta.systemImage, !symbol.isEmpty {
            return symbol
        }
        if let symbol = snapshot?.channelSystemImages?[id], !symbol.isEmpty {
            return symbol
        }
        switch id {
        case "whatsapp": return "message.fill"
        case "telegram": return "paperplane.fill"
        case "discord": return "bubble.left.and.bubble.right.fill"
        case "slack": return "number"
        case "signal": return "lock.fill"
        case "imessage": return "message.badge.filled.fill"
        case "gchat": return "bubble.left.fill"
        default: return "message"
        }
    }

    func orderedChannelIds() -> [String] {
        if let meta = snapshot?.channelMeta, !meta.isEmpty {
            return meta.map(\.id)
        }
        return snapshot?.channelOrder ?? []
    }

    // MARK: - Config value access

    func configValue(at path: ConfigPath) -> Any? {
        var current: Any = configDraft
        for segment in path {
            switch segment {
            case .key(let key):
                guard let dict = current as? [String: Any] else { return nil }
                guard let next = dict[key] else { return nil }
                current = next
            case .index(let idx):
                guard let arr = current as? [Any], idx < arr.count else { return nil }
                current = arr[idx]
            }
        }
        return current
    }

    func updateConfigValue(path: ConfigPath, value: Any?) {
        guard !path.isEmpty else { return }
        configDraft = setNestedValue(in: configDraft, path: path, value: value)
        configDirty = true
    }

    func channelConfigSchema(for channelId: String) -> ConfigSchemaNode? {
        guard let schema = configSchema else { return nil }
        return schema.node(at: [.key("channels"), .key(channelId)])
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.refresh(probe: true)
            await self.loadConfigSchema()
            await self.loadConfig()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                await self.refresh(probe: false)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Refresh

    func refresh(probe: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snap = try await GatewayConnectionService.shared.channelsStatus(probe: probe)
            snapshot = snap
            lastSuccess = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Config schema loading

    func loadConfigSchema() async {
        configSchemaLoading = true
        defer { configSchemaLoading = false }

        do {
            let response = try await GatewayConnectionService.shared.call(method: "config.schema")
            if response.ok, let result = response.result {
                let data = try JSONEncoder().encode(result)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let schemaRaw = json["schema"] ?? json
                    configSchema = ConfigSchemaNode(raw: schemaRaw)
                    if let hintsRaw = json["uiHints"] as? [String: Any] {
                        configUiHints = decodeUiHints(hintsRaw)
                    }
                }
            }
        } catch {
            logger.error("Failed to load config schema: \(error)")
        }
    }

    func loadConfig() async {
        do {
            let response = try await GatewayConnectionService.shared.call(method: "config.get")
            if response.ok, let result = response.result {
                let data = try JSONEncoder().encode(result)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let config = json["config"] as? [String: Any] ?? json
                    configRoot = config
                    configDraft = config
                    configLoaded = true
                    configDirty = false
                }
            }
        } catch {
            logger.error("Failed to load config: \(error)")
        }
    }

    func saveConfigDraft() async {
        isSavingConfig = true
        defer { isSavingConfig = false }
        configStatus = nil

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: configDraft)
            let value = try JSONDecoder().decode(AnyCodableValue.self, from: jsonData)
            let response = try await GatewayConnectionService.shared.call(
                method: "config.set",
                params: ["config": value]
            )
            if response.ok {
                configRoot = configDraft
                configDirty = false
                configStatus = "Configuration saved."
            } else {
                configStatus = "Save failed: \(response.error?.message ?? "unknown")"
            }
        } catch {
            configStatus = "Save error: \(error.localizedDescription)"
        }
    }

    func reloadConfigDraft() async {
        configDraft = configRoot
        configDirty = false
        configStatus = "Reverted to last saved configuration."
        await loadConfig()
    }

    // MARK: - WhatsApp

    func startWhatsAppLogin(force: Bool) async {
        guard !whatsappBusy else { return }
        whatsappBusy = true
        defer { whatsappBusy = false }
        var shouldAutoWait = false
        do {
            let result = try await GatewayConnectionService.shared.whatsAppLoginStart(force: force)
            whatsappLoginMessage = result.message
            whatsappLoginQrDataUrl = result.qrDataUrl
            whatsappLoginConnected = nil
            shouldAutoWait = result.qrDataUrl != nil
        } catch {
            whatsappLoginMessage = error.localizedDescription
            whatsappLoginQrDataUrl = nil
            whatsappLoginConnected = nil
        }
        await refresh(probe: true)
        if shouldAutoWait {
            Task { await waitWhatsAppLogin() }
        }
    }

    func waitWhatsAppLogin(timeoutMs: Int = 120_000) async {
        guard !whatsappBusy else { return }
        whatsappBusy = true
        defer { whatsappBusy = false }
        do {
            let result = try await GatewayConnectionService.shared.whatsAppLoginWait(timeoutMs: timeoutMs)
            whatsappLoginMessage = result.message
            whatsappLoginConnected = result.connected
            if result.connected {
                whatsappLoginQrDataUrl = nil
            }
        } catch {
            whatsappLoginMessage = error.localizedDescription
        }
        await refresh(probe: true)
    }

    func logoutWhatsApp() async {
        guard !whatsappBusy else { return }
        whatsappBusy = true
        defer { whatsappBusy = false }
        do {
            let result = try await GatewayConnectionService.shared.channelLogout(channel: "whatsapp")
            whatsappLoginMessage = result.cleared
                ? "Logged out and cleared credentials."
                : "No WhatsApp session found."
            whatsappLoginQrDataUrl = nil
        } catch {
            whatsappLoginMessage = error.localizedDescription
        }
        await refresh(probe: true)
    }

    // MARK: - Telegram

    func logoutTelegram() async {
        guard !telegramBusy else { return }
        telegramBusy = true
        defer { telegramBusy = false }
        do {
            let result = try await GatewayConnectionService.shared.channelLogout(channel: "telegram")
            if result.envToken == true {
                configStatus = "Telegram token still set via env; config cleared."
            } else {
                configStatus = result.cleared
                    ? "Telegram token cleared."
                    : "No Telegram token configured."
            }
            await loadConfig()
        } catch {
            configStatus = error.localizedDescription
        }
        await refresh(probe: true)
    }

    // MARK: - Helpers

    private func setNestedValue(in dict: [String: Any], path: ConfigPath, value: Any?) -> [String: Any] {
        guard let first = path.first else { return dict }
        var result = dict
        let rest = Array(path.dropFirst())

        switch first {
        case .key(let key):
            if rest.isEmpty {
                if let value {
                    result[key] = value
                } else {
                    result.removeValue(forKey: key)
                }
            } else {
                let sub = (result[key] as? [String: Any]) ?? [:]
                result[key] = setNestedValue(in: sub, path: rest, value: value)
            }
        case .index:
            break // Array index updates not needed at top level
        }
        return result
    }
}
