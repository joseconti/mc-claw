import SwiftUI
import AppKit

/// Centralized color palette for McClaw.
/// All properties delegate to ThemeManager.shared.activeColors
/// so they update dynamically when the user switches themes.
@MainActor
enum Theme {

    // MARK: - Surface Colors

    /// Main window / chat area background.
    static var background: Color { ThemeManager.shared.activeColors.background.color }

    /// Sidebar background — slightly lighter than main.
    static var sidebarBackground: Color { ThemeManager.shared.activeColors.sidebarBackground.color }

    /// Card / input field / code block background.
    static var cardBackground: Color { ThemeManager.shared.activeColors.cardBackground.color }

    /// User message bubble background.
    static var userBubble: Color { ThemeManager.shared.activeColors.userBubble.color }

    /// Subtle border for inputs, cards, code blocks.
    static var border: Color { ThemeManager.shared.activeColors.border.color }

    /// Hover / active state background.
    static var hoverBackground: Color { ThemeManager.shared.activeColors.hoverBackground.color }

    // MARK: - NSColor equivalents (for AppKit views)

    static var cardBackgroundNS: NSColor { ThemeManager.shared.activeColors.cardBackground.nsColor }
    static var borderNS: NSColor { ThemeManager.shared.activeColors.border.nsColor }
    static var backgroundNS: NSColor { ThemeManager.shared.activeColors.background.nsColor }

    // MARK: - Accent

    /// Primary accent color.
    static var accent: Color { ThemeManager.shared.activeColors.accent.color }

    // MARK: - Sidebar Selection

    /// Sidebar item active/selected highlight.
    static var sidebarSelection: Color { ThemeManager.shared.activeColors.sidebarSelection.color }

    // MARK: - Text Colors

    /// Primary text / foreground color.
    static var foreground: Color { ThemeManager.shared.activeColors.foreground.color }

    /// Secondary text color.
    static var secondaryForeground: Color { ThemeManager.shared.activeColors.secondaryForeground.color }
}
