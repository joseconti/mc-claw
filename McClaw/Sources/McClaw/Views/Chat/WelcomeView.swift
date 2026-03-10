import SwiftUI
import AppKit

/// Welcome screen shown when no messages exist, styled like Claude Desktop.
/// Input bar is centered in the view (not at bottom) with quick actions below.
struct WelcomeView: View {
    let onSend: (String, [Attachment]) -> Void
    let onAbort: () -> Void
    let isWorking: Bool

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Upper spacer (smaller to push content up, like Claude Desktop)
            Spacer()
                .frame(maxHeight: .infinity)

            // Logo — large and centered (like Claude Desktop)
            Group {
                if let url = Bundle.module.url(forResource: "mcclaw-logo", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.orange.gradient)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Spacer()
                .frame(height: 20)

            // Greeting text
            Text(greeting)
                .font(.system(size: 32, weight: .semibold))

            Spacer()
                .frame(height: 36)

            // Centered input bar
            ChatInputBar(
                onSend: onSend,
                onAbort: onAbort,
                isWorking: isWorking
            )
            .environment(appState)

            Spacer()
                .frame(height: 14)

            // Quick action chips
            quickActions

            // Bottom spacer (larger to push content up)
            Spacer()
                .frame(maxHeight: .infinity)
            Spacer()
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = appState.userName?.components(separatedBy: " ").first
        let timeGreeting: String
        switch hour {
        case 5..<12: timeGreeting = "Good morning"
        case 12..<18: timeGreeting = "Good afternoon"
        default: timeGreeting = "Good evening"
        }
        if let name = name, !name.isEmpty {
            return "\(timeGreeting), \(name)"
        }
        return timeGreeting
    }

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickActionChip(icon: "pencil.line", label: "Write") {
                onSend("Help me write something", [])
            }
            QuickActionChip(icon: "book", label: "Learn") {
                onSend("Explain a concept to me", [])
            }
            QuickActionChip(icon: "chevron.left.forwardslash.chevron.right", label: "Code") {
                onSend("Help me with code", [])
            }
            QuickActionChip(icon: "lightbulb", label: "Brainstorm") {
                onSend("Help me brainstorm ideas", [])
            }
        }
        .padding(.horizontal, 40)
    }
}

private struct QuickActionChip: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.4))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
