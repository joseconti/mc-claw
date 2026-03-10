import WebKit
import Logging

/// Handles A2UI action messages from the Canvas WebView JavaScript bridge.
/// Receives user interactions from the canvas and forwards them to the Gateway.
final class CanvasA2UIActionMessageHandler: NSObject, WKScriptMessageHandler {
    private let logger = Logger(label: "ai.mcclaw.canvas.a2ui")

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mcclawCanvasA2UIAction" else { return }
        guard let body = message.body as? [String: Any] else {
            logger.warning("Invalid A2UI message body")
            return
        }

        let actionName = body["actionName"] as? String ?? ""
        let surfaceId = body["surfaceId"] as? String ?? ""
        let sourceComponentId = body["sourceComponentId"] as? String ?? ""
        let context = body["context"] as? [String: Any] ?? [:]

        logger.info("A2UI action: \(actionName) surface=\(surfaceId) component=\(sourceComponentId)")

        // Format as agent message and send via Gateway
        Task { @MainActor in
            let contextJSON: String
            if let data = try? JSONSerialization.data(withJSONObject: context),
               let str = String(data: data, encoding: .utf8) {
                contextJSON = str
            } else {
                contextJSON = "{}"
            }

            let message = "CANVAS_A2UI action=\(actionName) surface=\(surfaceId) component=\(sourceComponentId) context=\(contextJSON)"

            await CanvasManager.shared.handleA2UIAction(
                actionName: actionName,
                surfaceId: surfaceId,
                sourceComponentId: sourceComponentId,
                message: message
            )
        }
    }
}
