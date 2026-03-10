import SwiftUI
import AppKit

/// Custom About window styled like Claude for Mac — large centered logo, app name, and version.
@MainActor
final class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let aboutView = NSHostingView(rootView: AboutContentView())
        aboutView.frame = NSRect(x: 0, y: 0, width: 320, height: 400)

        let panel = NSPanel(
            contentRect: aboutView.frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = aboutView
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.makeKeyAndOrderFront(nil)

        window = panel
    }
}

/// Content view for the About window.
private struct AboutContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Logo — large and centered
            Group {
                if let url = Bundle.module.url(forResource: "mcclaw-logo", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.orange.gradient)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 48))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 128, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            // App name
            Text("McClaw")
                .font(.title.weight(.semibold))

            // Version
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            // Buttons — Claude style: outlined pills with hover fill
            VStack(spacing: 12) {
                AboutPillButton(title: "Website") {
                    NSWorkspace.shared.open(URL(string: "https://mcclaw.joseconti.com")!)
                }
                AboutPillButton(title: "Developer Website") {
                    NSWorkspace.shared.open(URL(string: "https://plugins.joseconti.com/en")!)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
                .frame(height: 16)
        }
        .frame(width: 320, height: 400)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

/// Claude-style pill button: outlined with rounded corners, fills dark on hover.
private struct AboutPillButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundColor(isHovered
                    ? (colorScheme == .dark ? .black : .white)
                    : (colorScheme == .dark ? .white : .black))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isHovered
                            ? (colorScheme == .dark ? Color.white : Color.black)
                            : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            colorScheme == .dark
                                ? Color.white.opacity(0.3)
                                : Color.black.opacity(0.3),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
