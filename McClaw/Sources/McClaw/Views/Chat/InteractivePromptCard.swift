import SwiftUI
import McClawKit

/// Inline card displayed in assistant messages for interactive prompts.
/// Renders different styles: single/multi choice, confirmation, free text.
/// Active cards accept user input; answered cards show a compact summary.
struct InteractivePromptCard: View {
    let prompt: InteractivePromptKit.InteractivePrompt
    let isActive: Bool
    let currentIndex: Int
    let totalCount: Int
    let existingResponse: InteractivePromptKit.PromptResponse?

    @State private var focusedIndex: Int = 0
    @State private var selectedKeys: Set<String> = []
    @State private var freeText: String = ""
    @State private var isHoveredOption: String?

    private let promptService = InteractivePromptService.shared

    var body: some View {
        if isActive {
            activeCard
        } else if let response = existingResponse {
            answeredCard(response)
        } else {
            // Inactive, not yet answered — show collapsed pending state
            pendingCard
        }
    }

    // MARK: - Active Card

    @ViewBuilder
    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header (includes title + description + navigation)
            headerRow

            // Content by style
            switch prompt.style {
            case .singleChoice:
                singleChoiceContent
            case .multiChoice:
                multiChoiceContent
            case .confirmation:
                confirmationContent
            case .freeText:
                freeTextContent
            }

            // Keyboard hints
            keyboardHints
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.border, lineWidth: 0.5)
                }
        }
        .onKeyPress(.upArrow) {
            moveFocus(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveFocus(1)
            return .handled
        }
        .onKeyPress(.return) {
            submitFocused()
            return .handled
        }
        .onKeyPress(.escape) {
            promptService.skipCurrent()
            return .handled
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack(spacing: 8) {
                Text(prompt.title)
                    .font(.body.weight(.medium))

                Spacer()

                // Navigation controls for wizard flow (like Claude: < 2 de 4 > X)
                if totalCount > 1 {
                    HStack(spacing: 8) {
                        // Back chevron
                        Button {
                            promptService.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(currentIndex > 0 ? .secondary : .quaternary)
                        }
                        .buttonStyle(.plain)
                        .disabled(currentIndex == 0)

                        // Page indicator
                        Text(String(localized: "\(currentIndex + 1) of \(totalCount)", bundle: .module))
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        // Forward chevron (skip current to advance)
                        Button {
                            promptService.skipCurrent()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(currentIndex < totalCount - 1 ? .secondary : .quaternary)
                        }
                        .buttonStyle(.plain)
                        .disabled(currentIndex >= totalCount - 1)
                    }
                }

                // Close button (skip all)
                Button {
                    promptService.skipAll()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Skip all", bundle: .module))
            }

            // Description
            if let desc = prompt.description, !desc.isEmpty {
                Text(desc)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Single Choice

    @ViewBuilder
    private var singleChoiceContent: some View {
        if let options = prompt.options {
            VStack(spacing: 1) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    optionRow(option: option, index: index, isFocused: focusedIndex == index) {
                        submitSingleChoice(option)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // "Something else..." free text option
            if options.contains(where: { $0.isFreeText == true }) == false {
                freeTextOptionRow
            }
        }
    }

    // MARK: - Multi Choice

    @ViewBuilder
    private var multiChoiceContent: some View {
        if let options = prompt.options {
            VStack(spacing: 1) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    multiChoiceRow(option: option, index: index, isFocused: focusedIndex == index)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Footer: selection count + Skip + confirm arrow
            HStack(spacing: 12) {
                if !selectedKeys.isEmpty {
                    Text(String(localized: "\(selectedKeys.count) selected", bundle: .module))
                        .font(.callout)
                        .foregroundStyle(Theme.accent)
                }

                Spacer()

                // Skip button
                Button {
                    promptService.skipCurrent()
                } label: {
                    Text(String(localized: "Skip", bundle: .module))
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)

                // Confirm arrow button
                Button {
                    submitMultiChoice()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(selectedKeys.isEmpty ? Color.gray.opacity(0.3) : Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(selectedKeys.isEmpty)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Confirmation

    @ViewBuilder
    private var confirmationContent: some View {
        HStack(spacing: 12) {
            Spacer()

            Button {
                let response = InteractivePromptKit.PromptResponse(
                    promptId: prompt.id,
                    selectedKeys: ["cancel"]
                )
                promptService.resolveCurrentPrompt(response)
            } label: {
                Text(String(localized: "Cancel", bundle: .module))
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 80)
            }
            .buttonStyle(.bordered)

            Button {
                let response = InteractivePromptKit.PromptResponse(
                    promptId: prompt.id,
                    selectedKeys: ["accept"]
                )
                promptService.resolveCurrentPrompt(response)
            } label: {
                Text(String(localized: "Accept", bundle: .module))
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 80)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(.top, 4)
    }

    // MARK: - Free Text

    @ViewBuilder
    private var freeTextContent: some View {
        HStack(spacing: 8) {
            TextField(
                String(localized: "Type your answer...", bundle: .module),
                text: $freeText
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                submitFreeText()
            }

            Button {
                submitFreeText()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundColor(freeText.isEmpty ? Color.gray : Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Option Rows

    @ViewBuilder
    private func optionRow(option: InteractivePromptKit.PromptOption, index: Int, isFocused: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Number badge
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isFocused ? .white : .secondary)
                    .frame(width: 24, height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isFocused ? Theme.accent : Theme.border)
                    }

                // Icon if provided
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Label
                Text(option.label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                // Arrow indicator on hover/focus
                if isFocused || isHoveredOption == option.key {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isFocused || isHoveredOption == option.key ? Theme.hoverBackground : Theme.cardBackground)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHoveredOption = hovering ? option.key : nil
            if hovering { focusedIndex = index }
        }
    }

    @ViewBuilder
    private func multiChoiceRow(option: InteractivePromptKit.PromptOption, index: Int, isFocused: Bool) -> some View {
        Button {
            toggleSelection(option.key)
        } label: {
            HStack(spacing: 10) {
                // Checkbox
                Image(systemName: selectedKeys.contains(option.key) ? "checkmark.square.fill" : "square")
                    .font(.subheadline)
                    .foregroundStyle(selectedKeys.contains(option.key) ? Theme.accent : .secondary)

                // Icon if provided
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(option.label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isFocused || isHoveredOption == option.key ? Theme.hoverBackground : Theme.cardBackground)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHoveredOption = hovering ? option.key : nil
            if hovering { focusedIndex = index }
        }
    }

    @ViewBuilder
    private var freeTextOptionRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(
                String(localized: "Something else...", bundle: .module),
                text: $freeText
            )
            .textFieldStyle(.plain)
            .font(.subheadline)
            .onSubmit {
                if !freeText.trimmingCharacters(in: .whitespaces).isEmpty {
                    let response = InteractivePromptKit.PromptResponse(
                        promptId: prompt.id,
                        freeText: freeText
                    )
                    promptService.resolveCurrentPrompt(response)
                }
            }

            // Skip button
            Button {
                promptService.skipCurrent()
            } label: {
                Text(String(localized: "Skip", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Keyboard Hints

    @ViewBuilder
    private var keyboardHints: some View {
        Text(String(localized: "↑↓ navigate · Enter select · Esc skip", bundle: .module))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Answered Card (compact)

    @ViewBuilder
    private func answeredCard(_ response: InteractivePromptKit.PromptResponse) -> some View {
        HStack(spacing: 8) {
            Image(systemName: response.skipped ? "arrow.uturn.forward" : "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(response.skipped ? Color.secondary : Color.green)

            Text(prompt.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(answerSummary(response))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.cardBackground.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.border.opacity(0.3), lineWidth: 0.5)
                }
        }
    }

    // MARK: - Pending Card

    @ViewBuilder
    private var pendingCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Text(prompt.title)
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.cardBackground.opacity(0.3))
        }
    }

    // MARK: - Actions

    private func moveFocus(_ delta: Int) {
        let count = prompt.options?.count ?? 0
        guard count > 0 else { return }
        focusedIndex = (focusedIndex + delta + count) % count
    }

    private func submitFocused() {
        switch prompt.style {
        case .singleChoice:
            guard let options = prompt.options, focusedIndex < options.count else { return }
            submitSingleChoice(options[focusedIndex])
        case .multiChoice:
            guard let options = prompt.options, focusedIndex < options.count else { return }
            toggleSelection(options[focusedIndex].key)
        case .confirmation:
            // Enter = accept
            let response = InteractivePromptKit.PromptResponse(
                promptId: prompt.id,
                selectedKeys: ["accept"]
            )
            promptService.resolveCurrentPrompt(response)
        case .freeText:
            submitFreeText()
        }
    }

    private func submitSingleChoice(_ option: InteractivePromptKit.PromptOption) {
        if option.isFreeText == true && !freeText.trimmingCharacters(in: .whitespaces).isEmpty {
            let response = InteractivePromptKit.PromptResponse(
                promptId: prompt.id,
                freeText: freeText
            )
            promptService.resolveCurrentPrompt(response)
        } else {
            let response = InteractivePromptKit.PromptResponse(
                promptId: prompt.id,
                selectedKeys: [option.key]
            )
            promptService.resolveCurrentPrompt(response)
        }
    }

    private func toggleSelection(_ key: String) {
        if selectedKeys.contains(key) {
            selectedKeys.remove(key)
        } else {
            selectedKeys.insert(key)
        }
    }

    private func submitMultiChoice() {
        guard !selectedKeys.isEmpty else { return }
        let response = InteractivePromptKit.PromptResponse(
            promptId: prompt.id,
            selectedKeys: Array(selectedKeys)
        )
        promptService.resolveCurrentPrompt(response)
    }

    private func submitFreeText() {
        let trimmed = freeText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let response = InteractivePromptKit.PromptResponse(
            promptId: prompt.id,
            freeText: trimmed
        )
        promptService.resolveCurrentPrompt(response)
    }

    private func answerSummary(_ response: InteractivePromptKit.PromptResponse) -> String {
        if response.skipped {
            return String(localized: "Skipped", bundle: .module)
        }
        if let text = response.freeText, !text.isEmpty {
            return text
        }
        if let keys = response.selectedKeys, let options = prompt.options {
            let labels = keys.compactMap { key in options.first(where: { $0.key == key })?.label }
            return labels.joined(separator: ", ")
        }
        return ""
    }
}
