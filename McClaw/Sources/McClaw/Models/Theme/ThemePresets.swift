/// Static definitions of all built-in theme presets.
enum ThemePresets {

    /// Returns the `ThemeColors` for a given preset.
    /// For `.custom`, returns the McClaw Dark palette as a starting point.
    static func colors(for preset: ThemePresetId) -> ThemeColors {
        switch preset {
        case .mcclawDark: return mcclawDark
        case .midnightBlue: return midnightBlue
        case .dracula: return dracula
        case .mcclawLight: return mcclawLight
        case .solarizedLight: return solarizedLight
        case .paper: return paper
        case .custom: return mcclawDark
        }
    }

    // MARK: - Dark Presets

    /// McClaw Dark — warm brown dark theme inspired by Claude Desktop.
    static let mcclawDark = ThemeColors(
        background: CodableColor(r: 0.11, g: 0.10, b: 0.09),        // #1C1A17
        sidebarBackground: CodableColor(r: 0.16, g: 0.14, b: 0.13), // #292421
        cardBackground: CodableColor(r: 0.20, g: 0.18, b: 0.16),    // #332E29
        userBubble: CodableColor(r: 0.24, g: 0.21, b: 0.18),        // #3D362E
        border: CodableColor(r: 0.32, g: 0.29, b: 0.26),            // #524A42
        hoverBackground: CodableColor(r: 0.22, g: 0.20, b: 0.18),   // #38332E
        accent: CodableColor(r: 0.85, g: 0.55, b: 0.35),            // #D98C59
        sidebarSelection: CodableColor(r: 0.24, g: 0.21, b: 0.18),  // #3D362E
        foreground: CodableColor(hex: "#E8E4E0"),
        secondaryForeground: CodableColor(hex: "#A89E94")
    )

    /// Midnight Blue — deep blue-tinted dark theme, GitHub-inspired.
    static let midnightBlue = ThemeColors(
        background: CodableColor(hex: "#0D1117"),
        sidebarBackground: CodableColor(hex: "#161B22"),
        cardBackground: CodableColor(hex: "#21262D"),
        userBubble: CodableColor(hex: "#272D36"),
        border: CodableColor(hex: "#30363D"),
        hoverBackground: CodableColor(hex: "#1C2128"),
        accent: CodableColor(hex: "#58A6FF"),
        sidebarSelection: CodableColor(hex: "#272D36"),
        foreground: CodableColor(hex: "#C9D1D9"),
        secondaryForeground: CodableColor(hex: "#8B949E")
    )

    /// Dracula — popular purple-tinted dark theme.
    static let dracula = ThemeColors(
        background: CodableColor(hex: "#282A36"),
        sidebarBackground: CodableColor(hex: "#2D2F3D"),
        cardBackground: CodableColor(hex: "#44475A"),
        userBubble: CodableColor(hex: "#4A4D63"),
        border: CodableColor(hex: "#565975"),
        hoverBackground: CodableColor(hex: "#383A4E"),
        accent: CodableColor(hex: "#BD93F9"),
        sidebarSelection: CodableColor(hex: "#4A4D63"),
        foreground: CodableColor(hex: "#F8F8F2"),
        secondaryForeground: CodableColor(hex: "#B0AEA6")
    )

    // MARK: - Light Presets

    /// McClaw Light — warm light theme, inversion of McClaw Dark.
    static let mcclawLight = ThemeColors(
        background: CodableColor(hex: "#FAF8F6"),
        sidebarBackground: CodableColor(hex: "#F0EDE8"),
        cardBackground: CodableColor(hex: "#E8E4DF"),
        userBubble: CodableColor(hex: "#E0DBD5"),
        border: CodableColor(hex: "#D4CEC6"),
        hoverBackground: CodableColor(hex: "#ECE8E3"),
        accent: CodableColor(hex: "#D98C59"),
        sidebarSelection: CodableColor(hex: "#E0DBD5"),
        foreground: CodableColor(hex: "#2C2520"),
        secondaryForeground: CodableColor(hex: "#7A6E62")
    )

    /// Solarized Light — classic warm light theme by Ethan Schoonover.
    static let solarizedLight = ThemeColors(
        background: CodableColor(hex: "#FDF6E3"),
        sidebarBackground: CodableColor(hex: "#EEE8D5"),
        cardBackground: CodableColor(hex: "#E4DDCB"),
        userBubble: CodableColor(hex: "#DDD6C4"),
        border: CodableColor(hex: "#D0C8B4"),
        hoverBackground: CodableColor(hex: "#E8E1CF"),
        accent: CodableColor(hex: "#268BD2"),
        sidebarSelection: CodableColor(hex: "#DDD6C4"),
        foreground: CodableColor(hex: "#586E75"),
        secondaryForeground: CodableColor(hex: "#93A1A1")
    )

    /// Paper — clean white minimal theme.
    static let paper = ThemeColors(
        background: CodableColor(hex: "#FFFFFF"),
        sidebarBackground: CodableColor(hex: "#F5F5F5"),
        cardBackground: CodableColor(hex: "#EBEBEB"),
        userBubble: CodableColor(hex: "#E2E2E2"),
        border: CodableColor(hex: "#D4D4D4"),
        hoverBackground: CodableColor(hex: "#F0F0F0"),
        accent: CodableColor(hex: "#2563EB"),
        sidebarSelection: CodableColor(hex: "#E2E2E2"),
        foreground: CodableColor(hex: "#1A1A1A"),
        secondaryForeground: CodableColor(hex: "#6B6B6B")
    )
}
