import Foundation
import AppKit

/// Utility for switching the app language at runtime.
/// Changes take effect after app restart (standard macOS behavior).
@MainActor
enum LanguageSwitcher {

    /// Currently overridden language code, or nil if using system default.
    static var currentOverride: String? {
        guard let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
              let first = languages.first else {
            return nil
        }
        // Check if it was explicitly set by us (vs system default)
        return UserDefaults.standard.bool(forKey: "McClawLanguageOverride") ? first : nil
    }

    /// Set the app language. Pass nil to revert to system default.
    static func setLanguage(_ code: String?) {
        if let code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            UserDefaults.standard.set(true, forKey: "McClawLanguageOverride")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            UserDefaults.standard.set(false, forKey: "McClawLanguageOverride")
        }
        UserDefaults.standard.synchronize()
    }

    /// Restart the app by relaunching the bundle.
    static func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        try? task.run()

        // Give the new instance a moment to launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }

    /// Available languages detected from the app bundle's .lproj folders.
    /// Each entry has a language code and its native display name.
    static var availableLanguages: [(code: String, nativeName: String)] {
        let localizations = Bundle.appModule.localizations
            .filter { $0 != "Base" }
            .sorted()

        return localizations.compactMap { code in
            let locale = Locale(identifier: code)
            guard let name = locale.localizedString(forLanguageCode: code) else {
                return nil
            }
            // Capitalize first letter of the native name
            let capitalized = name.prefix(1).uppercased() + name.dropFirst()
            return (code: code, nativeName: capitalized)
        }
    }

    /// The effective language code currently in use (override or system).
    static var effectiveLanguage: String {
        if let override = currentOverride {
            return override
        }
        return Locale.current.language.languageCode?.identifier ?? "en"
    }
}
