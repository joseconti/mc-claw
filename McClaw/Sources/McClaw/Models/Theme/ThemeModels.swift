import SwiftUI
import AppKit

// MARK: - CodableColor

/// A color wrapper that can be serialized as a hex string for JSON persistence.
struct CodableColor: Codable, Sendable, Equatable {
    var hex: String

    /// SwiftUI Color from hex.
    var color: Color {
        Color(nsColor: nsColor)
    }

    /// AppKit NSColor from hex.
    var nsColor: NSColor {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let value = UInt64(h, radix: 16) else {
            return NSColor.magenta // fallback for invalid hex
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    init(hex: String) {
        self.hex = hex.hasPrefix("#") ? hex : "#\(hex)"
    }

    /// Initialize from RGB components (0.0–1.0) and convert to hex.
    init(r: Double, g: Double, b: Double) {
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        self.hex = String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    /// Initialize from an NSColor (converts to sRGB hex).
    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
    }
}

// MARK: - ThemeColors

/// All customizable color slots in a theme.
struct ThemeColors: Codable, Sendable, Equatable {
    /// Main window / chat area background.
    var background: CodableColor
    /// Sidebar background.
    var sidebarBackground: CodableColor
    /// Card / input field / code block background.
    var cardBackground: CodableColor
    /// User message bubble background.
    var userBubble: CodableColor
    /// Subtle border for inputs, cards, code blocks.
    var border: CodableColor
    /// Hover / active state background.
    var hoverBackground: CodableColor
    /// Primary accent color.
    var accent: CodableColor
    /// Sidebar item active/selected highlight.
    var sidebarSelection: CodableColor
    /// Primary text color.
    var foreground: CodableColor
    /// Secondary text color.
    var secondaryForeground: CodableColor
}

// MARK: - ThemePresetId

/// Identifies which theme preset is active.
enum ThemePresetId: String, Codable, Sendable, CaseIterable {
    // Dark
    case mcclawDark
    case midnightBlue
    case dracula
    // Light
    case mcclawLight
    case solarizedLight
    case paper
    // Custom
    case custom

    var displayName: String {
        switch self {
        case .mcclawDark: return String(localized: "McClaw Dark")
        case .midnightBlue: return String(localized: "Midnight Blue")
        case .dracula: return String(localized: "Dracula")
        case .mcclawLight: return String(localized: "McClaw Light")
        case .solarizedLight: return String(localized: "Solarized Light")
        case .paper: return String(localized: "Paper")
        case .custom: return String(localized: "Custom")
        }
    }

    /// Whether this preset is a dark theme. Custom returns nil (user decides).
    var isDark: Bool? {
        switch self {
        case .mcclawDark, .midnightBlue, .dracula: return true
        case .mcclawLight, .solarizedLight, .paper: return false
        case .custom: return nil
        }
    }

    /// SF Symbol icon for the preset card.
    var iconName: String {
        switch self {
        case .mcclawDark: return "moon.fill"
        case .midnightBlue: return "moon.stars.fill"
        case .dracula: return "wand.and.stars"
        case .mcclawLight: return "sun.max.fill"
        case .solarizedLight: return "sun.haze.fill"
        case .paper: return "doc.fill"
        case .custom: return "paintpalette.fill"
        }
    }

    /// Dark presets only.
    static var darkPresets: [ThemePresetId] {
        [.mcclawDark, .midnightBlue, .dracula]
    }

    /// Light presets only.
    static var lightPresets: [ThemePresetId] {
        [.mcclawLight, .solarizedLight, .paper]
    }
}
