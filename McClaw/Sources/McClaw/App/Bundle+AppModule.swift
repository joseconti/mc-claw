import Foundation

extension Bundle {
    /// Resource bundle accessor that works both with `swift run` (development)
    /// and inside a `.app` bundle (distribution).
    ///
    /// SPM's auto-generated `Bundle.module` only checks `Bundle.main.bundleURL`
    /// (which points to `McClaw.app/` for `.app` bundles) and a hardcoded build path.
    /// It never checks `Bundle.main.resourceURL` (`Contents/Resources/`), which is
    /// where `build-app.sh` places `McClaw_McClaw.bundle`.
    static let appModule: Bundle = {
        let bundleName = "McClaw_McClaw"

        // 1. Check Contents/Resources/ — standard location in .app bundles
        if let resourceURL = Bundle.main.resourceURL {
            let path = resourceURL.appendingPathComponent("\(bundleName).bundle").path
            if let bundle = Bundle(path: path) {
                return bundle
            }
        }

        // 2. Check Bundle.main.bundleURL — works for swift run (CLI executable)
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle").path
        if let bundle = Bundle(path: mainPath) {
            return bundle
        }

        // 3. Fallback: main bundle itself (localizations may still work via .lproj)
        return Bundle.main
    }()
}
