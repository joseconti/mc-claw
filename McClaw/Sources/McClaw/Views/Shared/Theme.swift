import SwiftUI
import AppKit

/// Centralized color palette for McClaw.
/// Warm-toned dark theme inspired by Claude Desktop's aesthetic.
enum Theme {

    // MARK: - Surface Colors (warm dark browns)

    /// Main window / chat area background.
    /// Claude-style deep warm black.
    static let background = Color(nsColor: NSColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1.0))

    /// Sidebar background — slightly lighter than main.
    static let sidebarBackground = Color(nsColor: NSColor(red: 0.16, green: 0.14, blue: 0.13, alpha: 1.0))

    /// Card / input field / code block background.
    static let cardBackground = Color(nsColor: NSColor(red: 0.20, green: 0.18, blue: 0.16, alpha: 1.0))

    /// User message bubble background.
    static let userBubble = Color(nsColor: NSColor(red: 0.24, green: 0.21, blue: 0.18, alpha: 1.0))

    /// Subtle border for inputs, cards, code blocks.
    static let border = Color(nsColor: NSColor(red: 0.32, green: 0.29, blue: 0.26, alpha: 1.0))

    /// Hover / active state background.
    static let hoverBackground = Color(nsColor: NSColor(red: 0.22, green: 0.20, blue: 0.18, alpha: 1.0))

    // MARK: - NSColor equivalents (for AppKit views)

    static let cardBackgroundNS = NSColor(red: 0.20, green: 0.18, blue: 0.16, alpha: 1.0)
    static let borderNS = NSColor(red: 0.32, green: 0.29, blue: 0.26, alpha: 1.0)
    static let backgroundNS = NSColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1.0)

    // MARK: - Accent

    /// Primary accent — warm orange, matching Claude's branding.
    static let accent = Color(nsColor: NSColor(red: 0.85, green: 0.55, blue: 0.35, alpha: 1.0))

    // MARK: - Sidebar Selection

    /// Sidebar item active/selected highlight.
    static let sidebarSelection = Color(nsColor: NSColor(red: 0.24, green: 0.21, blue: 0.18, alpha: 1.0))
}
