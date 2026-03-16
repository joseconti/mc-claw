import SwiftUI
import McClawKit

/// Settings tab for managing paired mobile devices.
/// All operations are local — McClaw IS the server.
struct DevicesSettingsTab: View {
    @State private var pairingService = DevicePairingService.shared
    @State private var qrPayload: PairingQRPayload?
    @State private var errorMessage: String?
    @State private var selectedDeviceId: String?
    @State private var showRevokeConfirm = false
    @State private var deviceToRevoke: PairedDevice?
    @State private var connectedDeviceIds: Set<String> = []
    @State private var serverRunning = false
    @State private var relayConnected = false
    @State private var relayMode: RelayConfig.RelayMode = .disabled
    @State private var relayURL: String = ""
    @State private var relayToken: String = ""
    @State private var relayLicenseKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            serverStatusSection
            remoteAccessSection
            pairingSection
            if pairingService.pendingRequest != nil { pendingRequestSection }
            pairedDevicesSection
            if let selectedDevice = pairingService.devices.first(where: { $0.id == selectedDeviceId }) {
                deviceDetailSection(selectedDevice)
            }
        }
        .task { await startServer() }
        .onReceive(NotificationCenter.default.publisher(for: .relayStateChanged)) { notification in
            if let state = notification.object as? RelayState {
                relayConnected = state.isConnected
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceConnectionChanged)) { notification in
            if let event = notification.object as? DeviceConnectionEvent {
                if event.connected {
                    connectedDeviceIds.insert(event.deviceId)
                } else {
                    connectedDeviceIds.remove(event.deviceId)
                }
            }
        }
        .alert(
            String(localized: "revoke_device", bundle: .appModule),
            isPresented: $showRevokeConfirm,
            presenting: deviceToRevoke
        ) { device in
            Button(String(localized: "revoke_device", bundle: .appModule), role: .destructive) {
                revoke(deviceId: device.deviceId)
            }
            Button(String(localized: "cancel", bundle: .appModule), role: .cancel) {}
        } message: { device in
            Text(String(localized: "revoke_device_confirm \(device.name)", bundle: .appModule))
        }
    }

    // MARK: - Server Status

    private var serverStatusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(serverRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            if serverRunning {
                let ip = DevicePairingService.localIPAddress() ?? "127.0.0.1"
                Text(String(localized: "devices_server_running \(ip)", bundle: .appModule))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "devices_server_stopped", bundle: .appModule))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button(String(localized: "devices_server_start", bundle: .appModule)) {
                    Task { await startServer() }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if !pairingService.devices.isEmpty {
                let count = connectedDeviceIds.count
                Text(String(localized: "devices_connected_count \(count) \(pairingService.devices.count)", bundle: .appModule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Remote Access

    private var remoteAccessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "devices_remote_access", bundle: .appModule),
                systemImage: "globe"
            )
            .font(.headline)

            Text(String(localized: "devices_remote_access_desc", bundle: .appModule))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(String(localized: "devices_relay_mode", bundle: .appModule), selection: $relayMode) {
                Text(String(localized: "devices_relay_disabled", bundle: .appModule)).tag(RelayConfig.RelayMode.disabled)
                Text(String(localized: "devices_relay_self_hosted", bundle: .appModule)).tag(RelayConfig.RelayMode.selfHosted)
                Text(String(localized: "devices_relay_cloud", bundle: .appModule)).tag(RelayConfig.RelayMode.mcclawCloud)
            }
            .pickerStyle(.segmented)
            .onChange(of: relayMode) {
                handleRelayModeChange()
            }

            if relayMode == .selfHosted {
                TextField(
                    String(localized: "devices_relay_url_placeholder", bundle: .appModule),
                    text: $relayURL
                )
                .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "devices_relay_self_hosted_info", bundle: .appModule))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link(
                        "github.com/joseconti/mc-claw-relay-server",
                        destination: URL(string: "https://github.com/joseconti/mc-claw-relay-server")!
                    )
                    .font(.caption)
                }
            }

            if relayMode == .mcclawCloud {
                HStack(spacing: 8) {
                    Image(systemName: "cloud.fill")
                        .foregroundStyle(.blue)
                    Text(String(localized: "devices_relay_cloud_url", bundle: .appModule))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text(String(localized: "devices_relay_cloud_cost", bundle: .appModule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if relayMode != .disabled {
                HStack(spacing: 8) {
                    Circle()
                        .fill(relayConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(relayConnected
                         ? String(localized: "devices_relay_connected", bundle: .appModule)
                         : String(localized: "devices_relay_disconnected", bundle: .appModule))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !relayConnected {
                        Button(String(localized: "devices_relay_connect", bundle: .appModule)) {
                            Task { await connectRelay() }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(String(localized: "devices_relay_disconnect", bundle: .appModule)) {
                            Task { await disconnectRelay() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Pairing Section

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "pair_device_header", bundle: .appModule),
                systemImage: "qrcode"
            )
            .font(.headline)

            if let qrPayload {
                HStack {
                    Spacer()
                    QRCodeView(payload: qrPayload)
                        .frame(width: 200, height: 200)
                    Spacer()
                }

                Text(String(localized: "pair_device_scan_hint", bundle: .appModule))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(String(localized: "pair_device_dismiss_qr", bundle: .appModule)) {
                    self.qrPayload = nil
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    generateQR()
                } label: {
                    Label(
                        String(localized: "pair_new_device", bundle: .appModule),
                        systemImage: "iphone.badge.plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!serverRunning)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Pending Request

    private var pendingRequestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                String(localized: "pending_request_header", bundle: .appModule),
                systemImage: "bell.badge"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            if let request = pairingService.pendingRequest {
                HStack(spacing: 12) {
                    Image(systemName: request.devicePlatform == .ios ? "iphone" : "phone.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.deviceName)
                            .font(.body.weight(.medium))
                        Text(DeviceKit.platformDisplayName(
                            request.devicePlatform == .ios ? .ios : .android
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(String(localized: "approve", bundle: .appModule)) {
                        approve(code: request.code)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(String(localized: "reject", bundle: .appModule)) {
                        reject(code: request.code)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.1)))
    }

    // MARK: - Paired Devices List

    private var pairedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "paired_devices_header", bundle: .appModule),
                systemImage: "ipad.and.iphone"
            )
            .font(.headline)

            if pairingService.devices.isEmpty {
                Text(String(localized: "no_devices_paired", bundle: .appModule))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(pairingService.devices) { device in
                    deviceRow(device)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private func deviceRow(_ device: PairedDevice) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(connectedDeviceIds.contains(device.deviceId) ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)

            Image(systemName: device.platform == .ios ? "iphone" : "phone.fill")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    Text(DeviceKit.platformDisplayName(
                        device.platform == .ios ? .ios : .android
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(DeviceKit.lastSeenText(from: device.lastSeen))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                selectedDeviceId = selectedDeviceId == device.id ? nil : device.id
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)

            Button {
                deviceToRevoke = device
                showRevokeConfirm = true
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Device Detail (Permissions)

    private func deviceDetailSection(_ device: PairedDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "device_permissions_header \(device.name)", bundle: .appModule),
                systemImage: "lock.shield"
            )
            .font(.headline)

            let keys = DeviceKit.permissionKeys()
            ForEach(keys, id: \.self) { key in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(DeviceKit.permissionLabel(for: key))
                            .font(.body)
                        Text(DeviceKit.permissionDescription(for: key))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: permissionValue(device: device, key: key) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(permissionValue(device: device, key: key) ? .green : .secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private func permissionValue(device: PairedDevice, key: String) -> Bool {
        switch key {
        case "chat": device.permissions.chat
        case "cron.read": device.permissions.cronRead
        case "cron.write": device.permissions.cronWrite
        case "channels.read": device.permissions.channelsRead
        case "channels.write": device.permissions.channelsWrite
        case "plugins.read": device.permissions.pluginsRead
        case "plugins.write": device.permissions.pluginsWrite
        case "exec.approve": device.permissions.execApprove
        case "config.read": device.permissions.configRead
        case "config.write": device.permissions.configWrite
        case "node.invoke": device.permissions.nodeInvoke
        default: false
        }
    }

    // MARK: - Actions

    private func startServer() async {
        do {
            try await MobileServer.shared.start()
            serverRunning = await MobileServer.shared.isRunning
        } catch {
            errorMessage = error.localizedDescription
            serverRunning = false
        }
    }

    private func generateQR() {
        errorMessage = nil
        Task {
            let port = await MobileServer.shared.port
            qrPayload = pairingService.generatePairingCode(serverPort: port)
        }
    }

    private func approve(code: String) {
        if let _ = pairingService.approvePairing(code: code) {
            qrPayload = nil
        }
    }

    private func reject(code: String) {
        pairingService.rejectPairing(code: code)
    }

    private func revoke(deviceId: String) {
        pairingService.revokeDevice(deviceId: deviceId)
        if selectedDeviceId == deviceId { selectedDeviceId = nil }
    }

    // MARK: - Relay Actions

    private func handleRelayModeChange() {
        if relayMode == .disabled {
            Task { await disconnectRelay() }
        } else if relayMode == .mcclawCloud {
            relayURL = "wss://relay.joseconti.com"
        }
    }

    private func connectRelay() async {
        let url = relayMode == .mcclawCloud ? "wss://relay.joseconti.com" : relayURL
        guard !url.isEmpty else {
            errorMessage = "Relay URL is required"
            return
        }

        // Generate relay token if empty (persistent per Mac)
        if relayToken.isEmpty {
            relayToken = UUID().uuidString
        }

        let config = RelayConfig(
            url: url,
            relayToken: relayToken,
            licenseKey: relayMode == .mcclawCloud ? relayLicenseKey : nil,
            mode: relayMode
        )

        await RelayClient.shared.connect(config: config)
        let state = await RelayClient.shared.state
        relayConnected = state.isConnected
    }

    private func disconnectRelay() async {
        await RelayClient.shared.disconnect()
        relayConnected = false
    }
}
