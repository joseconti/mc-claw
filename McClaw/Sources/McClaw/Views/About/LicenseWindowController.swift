import SwiftUI
import AppKit

/// Floating window that displays the GPLv3 license, following the AboutWindowController pattern.
@MainActor
final class LicenseWindowController {
    static let shared = LicenseWindowController()
    private var window: NSWindow?

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let licenseView = NSHostingView(rootView: LicenseContentView())
        licenseView.frame = NSRect(x: 0, y: 0, width: 500, height: 600)

        let panel = NSPanel(
            contentRect: licenseView.frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = licenseView
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.minSize = NSSize(width: 400, height: 400)
        panel.makeKeyAndOrderFront(nil)

        window = panel
    }
}

// MARK: - License Content View

private struct LicenseContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text(String(localized: "license_title", bundle: .appModule))
                    .font(.title2.weight(.semibold))

                Text("GNU General Public License v3.0")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("© 2024-2026 José Conti")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 20)

            // License text
            ScrollView {
                Text(licenseText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(20)
            }
        }
        .frame(width: 500, height: 600)
    }

    private var licenseText: String {
        // Try to read LICENSE file from the project bundle
        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
           let text = try? String(contentsOf: url) {
            return text
        }
        // Fallback summary
        return """
        McClaw - Native macOS AI Assistant
        Copyright (C) 2024-2026 José Conti

        This program is free software: you can redistribute it and/or modify
        it under the terms of the GNU General Public License as published by
        the Free Software Foundation, either version 3 of the License, or
        (at your option) any later version.

        This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
        GNU General Public License for more details.

        You should have received a copy of the GNU General Public License
        along with this program. If not, see <https://www.gnu.org/licenses/>.
        """
    }
}
