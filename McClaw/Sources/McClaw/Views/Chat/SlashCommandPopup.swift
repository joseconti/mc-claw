import SwiftUI

/// Autocomplete popup that appears above the chat input when the user types "/".
struct SlashCommandPopup: View {
    let commands: [SlashCommandDefinition]
    let selectedIndex: Int
    let onSelect: (SlashCommandDefinition) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, cmd in
                        commandRow(cmd, isSelected: index == selectedIndex)
                            .id(cmd.id)
                            .onTapGesture { onSelect(cmd) }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                guard newIndex >= 0 && newIndex < commands.count else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(commands[newIndex].id, anchor: .center)
                }
            }
        }
        .frame(maxHeight: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: -4)
    }

    @ViewBuilder
    private func commandRow(_ cmd: SlashCommandDefinition, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.icon)
                .font(.system(size: 14))
                .foregroundStyle(cmd.isNative ? Theme.accent : .secondary)
                .frame(width: 20)

            Text(cmd.command)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            if let hint = cmd.argumentHint {
                Text(hint)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let cliHint = cmd.cliHint {
                Text(cliHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(Capsule())
            }

            Text(cmd.localizedDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Theme.hoverBackground : .clear)
        .contentShape(Rectangle())
    }
}
