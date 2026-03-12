import SwiftUI

/// Environment key to propagate the image overlay action from ChatWindow
/// down to deeply nested GeneratedImageCard views.
private struct ShowImageOverlayKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ((GeneratedImage) -> Void)? = nil
}

extension EnvironmentValues {
    /// Closure to show a full-screen overlay for a generated image.
    var showImageOverlay: ((GeneratedImage) -> Void)? {
        get { self[ShowImageOverlayKey.self] }
        set { self[ShowImageOverlayKey.self] = newValue }
    }
}
