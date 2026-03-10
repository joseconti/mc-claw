import SwiftUI

/// Sheet for browsing MCP presets and installing them with configurable options.
struct MCPPresetBrowser: View {
    let provider: String
    let installedServerNames: Set<String>
    let onCancel: () -> Void
    let onInstall: (MCPServerFormData) async throws -> Void

    @State private var selectedPreset: MCPPreset?
    @State private var isInstalling = false
    @State private var errorMessage: String?

    private var categories: [(MCPPreset.Category, [MCPPreset])] {
        MCPPresetRegistry.byCategory
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(String(localized: "preset.browser.title", bundle: .module))
                    .font(.headline)
                Spacer()
                Text(provider.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary)
                    .clipShape(Capsule())
                    .liquidGlassCapsule(interactive: false)
            }
            .padding()

            Divider()

            if let preset = selectedPreset {
                presetDetail(preset)
            } else {
                presetCatalog
            }

            Divider()

            // Footer
            HStack {
                if selectedPreset != nil {
                    Button(String(localized: "preset.browser.back", bundle: .module)) {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedPreset = nil
                            errorMessage = nil
                        }
                    }
                }
                Button(String(localized: "Cancel", bundle: .module), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if let preset = selectedPreset {
                    let alreadyInstalled = installedServerNames.contains(preset.id)
                    Button(alreadyInstalled
                           ? String(localized: "preset.browser.reinstall", bundle: .module)
                           : String(localized: "preset.browser.install", bundle: .module)
                    ) {
                        install(preset)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isInstalling)
                }
            }
            .padding()
        }
        .frame(width: 520, height: 540)
    }

    // MARK: - Catalog

    private var presetCatalog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(categories, id: \.0) { category, presets in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(presets) { preset in
                            presetCard(preset)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func presetCard(_ preset: MCPPreset) -> some View {
        let alreadyInstalled = installedServerNames.contains(preset.id)

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                selectedPreset = preset
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preset.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(preset.name)
                            .font(.body.weight(.medium))
                        if alreadyInstalled {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    private func presetDetail(_ preset: MCPPreset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: preset.icon)
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                            .font(.title3.weight(.semibold))
                        Text(preset.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Requirements
                if preset.requiresNode || preset.requiresChrome {
                    requirementsBadges(preset)
                }

                Divider()

                // Command preview
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "preset.detail.command", bundle: .module))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(commandPreview(preset))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Options
                if !preset.options.isEmpty {
                    Divider()

                    Text(String(localized: "preset.detail.options", bundle: .module))
                        .font(.subheadline.weight(.medium))

                    ForEach(optionBindings(for: preset)) { option in
                        optionRow(option)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding()
        }
    }

    private func requirementsBadges(_ preset: MCPPreset) -> some View {
        HStack(spacing: 8) {
            if preset.requiresNode {
                Label("Node.js", systemImage: "shippingbox")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
            if preset.requiresChrome {
                Label("Chrome", systemImage: "globe")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private func optionRow(_ option: MCPPresetOption) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch option.kind {
            case .toggle:
                Toggle(option.label, isOn: toggleBinding(for: option.id))
                    .toggleStyle(.switch)
            case .text:
                TextField(option.label, text: textBinding(for: option.id))
            case .picker(let choices):
                Picker(option.label, selection: textBinding(for: option.id)) {
                    Text(String(localized: "preset.option.default", bundle: .module))
                        .tag("")
                    ForEach(choices, id: \.self) { choice in
                        Text(choice).tag(choice)
                    }
                }
            }
            Text(option.help)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Bindings

    /// We need to mutate selectedPreset.options — these helpers bridge SwiftUI bindings.
    private func optionBindings(for preset: MCPPreset) -> [MCPPresetOption] {
        selectedPreset?.options ?? preset.options
    }

    private func toggleBinding(for optionId: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedPreset?.options.first(where: { $0.id == optionId })?.value == "true"
            },
            set: { newValue in
                if let idx = selectedPreset?.options.firstIndex(where: { $0.id == optionId }) {
                    selectedPreset?.options[idx].value = newValue ? "true" : "false"
                }
            }
        )
    }

    private func textBinding(for optionId: String) -> Binding<String> {
        Binding(
            get: {
                selectedPreset?.options.first(where: { $0.id == optionId })?.value ?? ""
            },
            set: { newValue in
                if let idx = selectedPreset?.options.firstIndex(where: { $0.id == optionId }) {
                    selectedPreset?.options[idx].value = newValue
                }
            }
        )
    }

    // MARK: - Helpers

    private func commandPreview(_ preset: MCPPreset) -> String {
        let resolved = preset.resolvedArgs
        return "\(preset.command) \(resolved.joined(separator: " "))"
    }

    private func install(_ preset: MCPPreset) {
        isInstalling = true
        errorMessage = nil

        Task {
            do {
                let form = preset.toFormData()
                try await onInstall(form)
            } catch {
                errorMessage = error.localizedDescription
            }
            isInstalling = false
        }
    }
}
