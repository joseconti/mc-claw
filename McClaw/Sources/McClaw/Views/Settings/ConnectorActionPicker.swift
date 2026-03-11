import SwiftUI

/// Reusable picker for selecting a connector instance and action, with parameter fields.
/// Used in CronJobEditor (Data Sources) and potentially other places.
struct ConnectorActionPicker: View {
    @Binding var binding: ConnectorBinding?

    private let connectorStore = ConnectorStore.shared

    @State private var selectedInstanceId: String = ""
    @State private var selectedActionId: String = ""
    @State private var params: [String: String] = [:]
    @State private var maxResultLength: String = "4000"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Connector instance picker
            HStack {
                Text("Connector")
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: $selectedInstanceId) {
                    Text("Select…").tag("")
                    ForEach(connectorStore.connectedInstances) { instance in
                        Text(instance.name).tag(instance.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            // Action picker (shown when connector is selected)
            if let actions = availableActions, !actions.isEmpty {
                HStack {
                    Text("Action")
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: $selectedActionId) {
                        Text("Select…").tag("")
                        ForEach(actions) { action in
                            Text(action.name).tag(action.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }

            // Parameter fields (shown when action is selected)
            if let actionDef = selectedAction, !actionDef.parameters.isEmpty {
                ForEach(actionDef.parameters, id: \.name) { param in
                    HStack {
                        Text(param.name)
                            .foregroundStyle(param.required ? .primary : .secondary)
                            .frame(width: 100, alignment: .leading)
                        if let enumValues = param.enumValues, !enumValues.isEmpty {
                            Picker("", selection: paramBinding(for: param.name, default: param.defaultValue ?? "")) {
                                Text("—").tag("")
                                ForEach(enumValues, id: \.self) { value in
                                    Text(value).tag(value)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        } else {
                            TextField(
                                param.required ? "\(param.description) (required)" : param.description,
                                text: paramBinding(for: param.name, default: param.defaultValue ?? "")
                            )
                            .mcclawTextField()
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                HStack {
                    Text("Max length")
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    TextField("4000", text: $maxResultLength)
                        .mcclawTextField()
                        .frame(width: 80)
                    Text("chars")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // Preview of the @fetch syntax
            if !selectedInstanceId.isEmpty && !selectedActionId.isEmpty {
                let preview = buildPreview()
                Text(preview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .onChange(of: selectedInstanceId) { _, _ in
            selectedActionId = ""
            params = [:]
            syncToBinding()
        }
        .onChange(of: selectedActionId) { _, _ in
            params = [:]
            // Pre-fill default values
            if let actionDef = selectedAction {
                for param in actionDef.parameters {
                    if let defaultValue = param.defaultValue {
                        params[param.name] = defaultValue
                    }
                }
            }
            syncToBinding()
        }
        .onAppear { hydrateFromBinding() }
    }

    // MARK: - Computed

    private var availableActions: [ConnectorActionDef]? {
        guard !selectedInstanceId.isEmpty,
              let instance = connectorStore.instance(for: selectedInstanceId),
              let definition = ConnectorRegistry.definition(for: instance.definitionId) else {
            return nil
        }
        return definition.actions
    }

    private var selectedAction: ConnectorActionDef? {
        availableActions?.first { $0.id == selectedActionId }
    }

    // MARK: - Helpers

    private func paramBinding(for name: String, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { params[name] ?? defaultValue },
            set: { newValue in
                params[name] = newValue
                syncToBinding()
            }
        )
    }

    private func syncToBinding() {
        guard !selectedInstanceId.isEmpty, !selectedActionId.isEmpty else {
            binding = nil
            return
        }

        let nonEmptyParams = params.filter { !$0.value.isEmpty }
        let maxLen = Int(maxResultLength) ?? 4000

        binding = ConnectorBinding(
            connectorInstanceId: selectedInstanceId,
            actionId: selectedActionId,
            params: nonEmptyParams,
            maxResultLength: maxLen
        )
    }

    private func hydrateFromBinding() {
        guard let binding else { return }
        selectedInstanceId = binding.connectorInstanceId
        selectedActionId = binding.actionId
        params = binding.params
        maxResultLength = String(binding.maxResultLength)
    }

    private func buildPreview() -> String {
        let connectorName: String
        if let instance = connectorStore.instance(for: selectedInstanceId) {
            connectorName = instance.name.lowercased()
        } else {
            connectorName = "connector"
        }

        let nonEmpty = params.filter { !$0.value.isEmpty }
        if nonEmpty.isEmpty {
            return "@fetch(\(connectorName).\(selectedActionId))"
        }
        let paramStr = nonEmpty.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        return "@fetch(\(connectorName).\(selectedActionId), \(paramStr))"
    }
}

/// A row in the CronJobEditor's Data Sources section.
struct ConnectorBindingRow: View {
    let index: Int
    @Binding var binding: ConnectorBinding?
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            ConnectorActionPicker(binding: $binding)
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
    }
}
