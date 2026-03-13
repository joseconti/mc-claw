import SwiftUI

/// Manages the active theme and custom color overrides.
/// Singleton accessed via `ThemeManager.shared`.
@MainActor
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    /// Currently selected preset identifier.
    var selectedPreset: ThemePresetId = .mcclawDark {
        didSet {
            // Auto-set color scheme to match preset's light/dark nature
            if let isDark = selectedPreset.isDark {
                AppState.shared.appColorScheme = isDark ? .dark : .light
            }
        }
    }

    /// User's custom color overrides (only used when selectedPreset == .custom).
    var customColors: ThemeColors = ThemePresets.mcclawDark

    /// The resolved active colors for the current theme.
    var activeColors: ThemeColors {
        selectedPreset == .custom ? customColors : ThemePresets.colors(for: selectedPreset)
    }

    private init() {}
}
