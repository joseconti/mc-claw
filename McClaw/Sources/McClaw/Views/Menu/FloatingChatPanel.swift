import AppKit
import SwiftUI

/// Borderless floating panel that appears at the bottom-center of the screen,
/// styled like Claude Desktop's quick chat input.
final class FloatingChatPanel: NSPanel {
    private var clickOutsideMonitor: Any?

    init(contentView swiftUIView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 120),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isMovableByWindowBackground = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false

        // Container with dark background + rounded corners + subtle border
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 20
        container.layer?.masksToBounds = true

        // Visual effect background (dark material)
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.appearance = NSAppearance(named: .darkAqua)
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(visualEffect)

        // Subtle border overlay
        let borderLayer = CALayer()
        borderLayer.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        borderLayer.borderWidth = 0.5
        borderLayer.cornerRadius = 20
        container.layer?.addSublayer(borderLayer)
        // Border layer will be sized via layout

        // Host the SwiftUI view
        let hosting = NSHostingView(rootView: AnyView(swiftUIView))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)

        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        contentView = container

        // Size the border layer when the window resizes
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: container, queue: .main) { _ in
            borderLayer.frame = container.bounds
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Show the panel at the bottom center of the main screen.
    func showPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.minY + 120
        setFrameOrigin(NSPoint(x: x, y: y))

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Dismiss when clicking outside the panel
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissPanel()
        }
    }

    /// Hide the panel and clean up monitors.
    func dismissPanel() {
        orderOut(nil)
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    func toggle() {
        if isVisible {
            dismissPanel()
        } else {
            showPanel()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            dismissPanel()
        } else {
            super.keyDown(with: event)
        }
    }
}
