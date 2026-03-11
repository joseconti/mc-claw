import SwiftUI

/// Dynamic form rendered from a JSON Schema for channel configuration.
struct ConfigSchemaForm: View {
    let store: ChannelsStore
    let schema: ConfigSchemaNode
    let path: ConfigPath

    var body: some View {
        renderNode(schema, path: path)
    }

    private func renderNode(_ schema: ConfigSchemaNode, path: ConfigPath) -> AnyView {
        let storedValue = store.configValue(at: path)
        let value = storedValue ?? schema.explicitDefault
        let label = hintForPath(path, hints: store.configUiHints)?.label ?? schema.title
        let help = hintForPath(path, hints: store.configUiHints)?.help ?? schema.description
        let variants = schema.anyOf.isEmpty ? schema.oneOf : schema.anyOf

        if !variants.isEmpty {
            let nonNull = variants.filter { !$0.isNullSchema }
            if nonNull.count == 1, let only = nonNull.first {
                return renderNode(only, path: path)
            }
            let literals = nonNull.compactMap(\.literalValue)
            if !literals.isEmpty, literals.count == nonNull.count {
                return AnyView(renderEnumPicker(label: label, help: help, path: path, options: literals, schema: schema))
            }
        }

        switch schema.schemaType {
        case "object":
            return AnyView(renderObjectNode(schema, path: path, label: label, help: help))
        case "array":
            return AnyView(renderArray(schema, path: path, value: value, label: label, help: help))
        case "boolean":
            return AnyView(
                Toggle(isOn: boolBinding(path, defaultValue: schema.explicitDefault as? Bool)) {
                    if let label { Text(label) } else { Text("Enabled") }
                }
                .help(help ?? "")
            )
        case "number", "integer":
            return AnyView(renderNumberField(schema, path: path, label: label, help: help))
        case "string":
            return AnyView(renderStringField(schema, path: path, label: label, help: help))
        default:
            return AnyView(
                VStack(alignment: .leading, spacing: 6) {
                    if let label { Text(label).font(.callout.weight(.semibold)) }
                    Text("Unsupported field type.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            )
        }
    }

    @ViewBuilder
    private func renderEnumPicker(
        label: String?,
        help: String?,
        path: ConfigPath,
        options: [Any],
        schema: ConfigSchemaNode
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label { Text(label).font(.callout.weight(.semibold)) }
            if let help {
                Text(help)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Picker("", selection: enumBinding(path, options: options, defaultValue: schema.explicitDefault)) {
                Text("Select...").tag(-1)
                ForEach(options.indices, id: \.self) { index in
                    Text(String(describing: options[index])).tag(index)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private func renderObjectNode(
        _ schema: ConfigSchemaNode,
        path: ConfigPath,
        label: String?,
        help: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let label {
                Text(label)
                    .font(.callout.weight(.semibold))
            }
            if let help {
                Text(help)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            let properties = schema.properties
            let sortedKeys = properties.keys.sorted { lhs, rhs in
                let orderA = hintForPath(path + [.key(lhs)], hints: store.configUiHints)?.order ?? 0
                let orderB = hintForPath(path + [.key(rhs)], hints: store.configUiHints)?.order ?? 0
                if orderA != orderB { return orderA < orderB }
                return lhs < rhs
            }
            ForEach(sortedKeys, id: \.self) { key in
                if let child = properties[key] {
                    self.renderNode(child, path: path + [.key(key)])
                }
            }
        }
    }

    @ViewBuilder
    private func renderStringField(
        _ schema: ConfigSchemaNode,
        path: ConfigPath,
        label: String?,
        help: String?
    ) -> some View {
        let hint = hintForPath(path, hints: store.configUiHints)
        let placeholder = hint?.placeholder ?? ""
        let sensitive = hint?.sensitive ?? isSensitivePath(path)
        let defaultValue = schema.explicitDefault as? String

        VStack(alignment: .leading, spacing: 6) {
            if let label { Text(label).font(.callout.weight(.semibold)) }
            if let help {
                Text(help)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let options = schema.enumValues {
                Picker("", selection: enumBinding(path, options: options, defaultValue: schema.explicitDefault)) {
                    Text("Select...").tag(-1)
                    ForEach(options.indices, id: \.self) { index in
                        Text(String(describing: options[index])).tag(index)
                    }
                }
                .pickerStyle(.menu)
            } else if sensitive {
                SecureField(placeholder, text: stringBinding(path, defaultValue: defaultValue))
                    .mcclawTextField()
            } else {
                TextField(placeholder, text: stringBinding(path, defaultValue: defaultValue))
                    .mcclawTextField()
            }
        }
    }

    @ViewBuilder
    private func renderNumberField(
        _ schema: ConfigSchemaNode,
        path: ConfigPath,
        label: String?,
        help: String?
    ) -> some View {
        let defaultValue = (schema.explicitDefault as? Double)
            ?? (schema.explicitDefault as? Int).map(Double.init)
        VStack(alignment: .leading, spacing: 6) {
            if let label { Text(label).font(.callout.weight(.semibold)) }
            if let help {
                Text(help)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            TextField(
                "",
                text: numberBinding(
                    path,
                    isInteger: schema.schemaType == "integer",
                    defaultValue: defaultValue))
                .mcclawTextField()
        }
    }

    @ViewBuilder
    private func renderArray(
        _ schema: ConfigSchemaNode,
        path: ConfigPath,
        value: Any?,
        label: String?,
        help: String?
    ) -> some View {
        let items = value as? [Any] ?? []
        let itemSchema = schema.items
        VStack(alignment: .leading, spacing: 10) {
            if let label { Text(label).font(.callout.weight(.semibold)) }
            if let help {
                Text(help)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    if let itemSchema {
                        renderNode(itemSchema, path: path + [.index(index)])
                    } else {
                        Text(String(describing: items[index]))
                    }
                    Button("Remove") {
                        var next = items
                        next.remove(at: index)
                        store.updateConfigValue(path: path, value: next)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Button("Add") {
                var next = items
                if let itemSchema {
                    next.append(itemSchema.defaultValue)
                } else {
                    next.append("")
                }
                store.updateConfigValue(path: path, value: next)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Bindings

    private func stringBinding(_ path: ConfigPath, defaultValue: String?) -> Binding<String> {
        Binding(
            get: {
                if let value = store.configValue(at: path) as? String { return value }
                return defaultValue ?? ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                store.updateConfigValue(path: path, value: trimmed.isEmpty ? nil : trimmed)
            })
    }

    private func boolBinding(_ path: ConfigPath, defaultValue: Bool?) -> Binding<Bool> {
        Binding(
            get: {
                if let value = store.configValue(at: path) as? Bool { return value }
                return defaultValue ?? false
            },
            set: { newValue in
                store.updateConfigValue(path: path, value: newValue)
            })
    }

    private func numberBinding(
        _ path: ConfigPath,
        isInteger: Bool,
        defaultValue: Double?
    ) -> Binding<String> {
        Binding(
            get: {
                if let value = store.configValue(at: path) { return String(describing: value) }
                guard let defaultValue else { return "" }
                return isInteger ? String(Int(defaultValue)) : String(defaultValue)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    store.updateConfigValue(path: path, value: nil)
                } else if let value = Double(trimmed) {
                    store.updateConfigValue(path: path, value: isInteger ? Int(value) : value)
                }
            })
    }

    private func enumBinding(
        _ path: ConfigPath,
        options: [Any],
        defaultValue: Any?
    ) -> Binding<Int> {
        Binding(
            get: {
                let value = store.configValue(at: path) ?? defaultValue
                guard let value else { return -1 }
                return options.firstIndex { option in
                    String(describing: option) == String(describing: value)
                } ?? -1
            },
            set: { index in
                guard index >= 0, index < options.count else {
                    store.updateConfigValue(path: path, value: nil)
                    return
                }
                store.updateConfigValue(path: path, value: options[index])
            })
    }
}

/// Convenience view that renders config for a specific channel ID.
struct ChannelConfigFormView: View {
    let store: ChannelsStore
    let channelId: String

    var body: some View {
        if store.configSchemaLoading {
            ProgressView().controlSize(.small)
        } else if let schema = store.channelConfigSchema(for: channelId) {
            ConfigSchemaForm(
                store: store,
                schema: schema,
                path: [.key("channels"), .key(channelId)]
            )
        } else {
            Text("Schema unavailable for this channel.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
