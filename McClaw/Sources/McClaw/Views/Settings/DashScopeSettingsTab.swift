import SwiftUI
import McClawKit

/// Settings tab for DashScope (Alibaba Cloud) provider: API key, region, model selection, connection test.
struct DashScopeSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var apiKeyInput = ""
    @State private var isKeyVisible = false
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var hasExistingKey = false

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        @Bindable var state = appState
        VStack(alignment: .leading, spacing: 0) {
            // Description
            Text(String(localized: "dashscope_description", bundle: .module))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            // Section 1: API Key
            apiKeySection

            sectionDivider()

            // Section 2: Region
            regionSection

            sectionDivider()

            // Section 3: Models
            modelsSection

            sectionDivider()

            // Section 4: Connection Test
            connectionSection
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "dashscope_api_key_header", bundle: .module))

            HStack {
                if isKeyVisible {
                    TextField(
                        String(localized: "dashscope_api_key_placeholder", bundle: .module),
                        text: $apiKeyInput
                    )
                    .mcclawTextField()
                } else {
                    SecureField(
                        String(localized: "dashscope_api_key_placeholder", bundle: .module),
                        text: $apiKeyInput
                    )
                    .mcclawTextField()
                }

                Button {
                    isKeyVisible.toggle()
                } label: {
                    Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "dashscope_toggle_visibility", bundle: .module))
            }

            HStack(spacing: 8) {
                Button(String(localized: "dashscope_save_key", bundle: .module)) {
                    saveAPIKey()
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if hasExistingKey {
                    Button(String(localized: "dashscope_remove_key", bundle: .module), role: .destructive) {
                        removeAPIKey()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if hasExistingKey {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(String(localized: "dashscope_key_stored", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(String(localized: "dashscope_key_hint", bundle: .module))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .onAppear {
            loadExistingKey()
        }
    }

    // MARK: - Region Section

    private var regionSection: some View {
        @Bindable var state = appState
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "dashscope_region_header", bundle: .module))

            Picker("", selection: $state.dashscopeRegion) {
                ForEach(DashScopeKit.Region.allCases, id: \.rawValue) { region in
                    Text(region.displayName).tag(region.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            Text(String(localized: "dashscope_region_hint", bundle: .module))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .onChange(of: appState.dashscopeRegion) { Task { await ConfigStore.shared.saveFromState() } }
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(String(localized: "dashscope_models_header", bundle: .module))

            ForEach(DashScopeKit.modelCatalog) { model in
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 4) {
                            Text(model.displayName)
                                .font(.callout.weight(.medium))
                            Text(model.originalProvider)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        if let ctx = model.contextWindow {
                            Text("\(ctx / 1024)K context")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    if appState.defaultModels["dashscope"] == model.modelId {
                        Text(String(localized: "dashscope_default_badge", bundle: .module))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.2))
                            .clipShape(Capsule())
                    } else {
                        Button(String(localized: "dashscope_set_default", bundle: .module)) {
                            appState.defaultModels["dashscope"] = model.modelId
                            Task { await ConfigStore.shared.saveFromState() }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "dashscope_connection_header", bundle: .module))

            HStack {
                Button {
                    testConnection()
                } label: {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label(
                            String(localized: "dashscope_test_connection", bundle: .module),
                            systemImage: "network"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTesting || !hasExistingKey)

                if let result = testResult {
                    switch result {
                    case .success:
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(String(localized: "dashscope_connected", bundle: .module))
                                .font(.callout)
                        }
                    case .failure(let msg):
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(msg)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if !hasExistingKey {
                Text(String(localized: "dashscope_not_configured", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func loadExistingKey() {
        if let key = DashScopeKeychainHelper.loadAPIKey(), !key.isEmpty {
            hasExistingKey = true
            // Show masked version
            apiKeyInput = String(repeating: "•", count: min(key.count, 20)) + key.suffix(4)
        }
    }

    private func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        if DashScopeKeychainHelper.saveAPIKey(key) {
            hasExistingKey = true
            appState.dashscopeAPIKeyStored = true
            appState.hiddenProviders.remove("dashscope")
            Task { await ConfigStore.shared.saveFromState() }
            // Mask the displayed key
            apiKeyInput = String(repeating: "•", count: min(key.count, 20)) + key.suffix(4)
            testResult = nil
        }
    }

    private func removeAPIKey() {
        _ = DashScopeKeychainHelper.deleteAPIKey()
        hasExistingKey = false
        appState.dashscopeAPIKeyStored = false
        apiKeyInput = ""
        testResult = nil
        Task { await ConfigStore.shared.saveFromState() }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        let regionStr = appState.dashscopeRegion
        let region = DashScopeKit.Region(rawValue: regionStr) ?? .international

        Task {
            guard let apiKey = DashScopeKeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
                await MainActor.run {
                    testResult = .failure("No API key found")
                    isTesting = false
                }
                return
            }

            guard let url = DashScopeKit.modelsURL(for: region) else {
                await MainActor.run {
                    testResult = .failure("Invalid URL")
                    isTesting = false
                }
                return
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    await MainActor.run {
                        if httpResponse.statusCode == 200 {
                            testResult = .success
                        } else {
                            testResult = .failure("HTTP \(httpResponse.statusCode)")
                        }
                        isTesting = false
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}

// MARK: - Section Helpers (matching SettingsWindow style)

private func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.headline)
        .padding(.top, 16)
        .padding(.bottom, 4)
}

private func sectionDivider() -> some View {
    Divider()
        .padding(.vertical, 8)
}
