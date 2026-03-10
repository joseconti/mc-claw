import SwiftUI
import Logging

/// Handles `mcclaw://` URL scheme routing.
///
/// Supported URLs:
/// - `mcclaw://chat` — Open chat window
/// - `mcclaw://chat?session=NAME` — Open chat with specific session
/// - `mcclaw://settings` — Open settings
/// - `mcclaw://canvas` — Open canvas
/// - `mcclaw://new` — Start new chat session
/// - `mcclaw://status` — Show status in chat
enum DeepLinkRouter {
    private static let logger = Logger(label: "ai.mcclaw.deep-links")

    /// Handle an incoming URL. Call from onOpenURL.
    @MainActor
    static func handle(_ url: URL, openWindow: OpenWindowAction) {
        guard url.scheme == "mcclaw" else { return }

        let host = url.host() ?? url.path()
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]

        logger.info("Deep link: \(url.absoluteString)")

        switch host {
        case "chat":
            if let session = params["session"], !session.isEmpty {
                AppState.shared.currentSessionId = session
            }
            openWindow(id: "chat")

        case "settings":
            // Open settings via NSApp
            if #available(macOS 14.0, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }

        case "canvas":
            openWindow(id: "canvas")

        case "new":
            AppState.shared.currentSessionId = UUID().uuidString
            openWindow(id: "chat")

        case "status":
            openWindow(id: "chat")
            // The /status command will be triggered by the user or could be auto-sent

        default:
            logger.warning("Unknown deep link host: \(host)")
            openWindow(id: "chat")
        }
    }
}
