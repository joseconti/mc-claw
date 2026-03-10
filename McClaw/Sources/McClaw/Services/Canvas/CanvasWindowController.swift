import AppKit
import WebKit
import Logging
import McClawKit

/// Manages the Canvas window lifecycle, placement, and WebView.
@MainActor
final class CanvasWindowController {
    private let logger = Logger(label: "ai.mcclaw.canvas.window")

    /// The canvas NSPanel (floating, non-activating).
    private(set) var panel: NSPanel?

    /// The WKWebView displaying canvas content.
    private(set) var webView: WKWebView?

    /// The A2UI message handler for JS→Swift communication.
    private let a2uiHandler = CanvasA2UIActionMessageHandler()

    /// Current session key for this canvas.
    let sessionKey: String

    /// Saved frame for this session (persisted per session).
    private var savedFrame: NSRect?

    // MARK: - Constants

    private static let panelDefaultSize = NSSize(width: 520, height: 680)
    private static let panelMinSize = NSSize(width: 360, height: 360)
    private static let windowDefaultSize = NSSize(width: 1120, height: 840)
    private static let windowMinSize = NSSize(width: 880, height: 680)

    init(sessionKey: String) {
        self.sessionKey = sessionKey
    }

    // MARK: - Show / Hide

    /// Show the canvas panel with optional placement.
    func show(placement: CanvasPlacementParams? = nil) {
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        if let placement {
            applyPlacement(placement)
        } else if let saved = savedFrame {
            panel.setFrame(saved, display: true)
        }

        panel.orderFront(nil)
        logger.info("Canvas panel shown for session \(sessionKey)")
    }

    /// Hide the canvas panel.
    func hide() {
        guard let panel else { return }
        savedFrame = panel.frame
        panel.orderOut(nil)
        logger.info("Canvas panel hidden")
    }

    /// Close and release the canvas panel.
    func close() {
        savedFrame = panel?.frame
        panel?.close()
        panel = nil
        webView = nil
        logger.info("Canvas panel closed")
    }

    /// Whether the panel is currently visible.
    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Navigation

    /// Navigate to a URL in the canvas.
    func navigate(to url: URL) {
        webView?.load(URLRequest(url: url))
        logger.info("Canvas navigating to \(url)")
    }

    /// Navigate to a canvas-scheme URL for the session.
    func navigateToSession(path: String = "index.html") {
        let url = URL(string: "mcclaw-canvas://\(sanitizeSessionKey(sessionKey))/\(path)")!
        navigate(to: url)
    }

    /// Load raw HTML content.
    func loadHTML(_ html: String) {
        let baseURL = URL(string: "mcclaw-canvas://\(sanitizeSessionKey(sessionKey))/")
        webView?.loadHTMLString(html, baseURL: baseURL)
    }

    // MARK: - JavaScript Evaluation

    /// Evaluate JavaScript in the canvas WebView.
    func evaluateJavaScript(_ script: String) async throws -> Any? {
        guard let webView else {
            throw NodeError(code: .unavailable, message: "Canvas WebView not available")
        }
        return try await webView.evaluateJavaScript(script)
    }

    // MARK: - Snapshot

    /// Take a snapshot of the current canvas content.
    func takeSnapshot(maxWidth: Int?, quality: Double?, format: CanvasSnapshotFormat?) async throws -> Data {
        guard let webView else {
            throw NodeError(code: .unavailable, message: "Canvas WebView not available")
        }

        let config = WKSnapshotConfiguration()
        let image = try await webView.takeSnapshot(configuration: config)

        let bitmapRep: NSBitmapImageRep
        if let maxWidth, maxWidth > 0, Int(image.size.width) > maxWidth {
            let scale = Double(maxWidth) / image.size.width
            let newSize = NSSize(width: Double(maxWidth), height: image.size.height * scale)
            let resizedImage = NSImage(size: newSize)
            resizedImage.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize))
            resizedImage.unlockFocus()
            guard let rep = resizedImage.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) }) else {
                throw NodeError(code: .internalError, message: "Failed to create bitmap")
            }
            bitmapRep = rep
        } else {
            guard let rep = image.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) }) else {
                throw NodeError(code: .internalError, message: "Failed to create bitmap")
            }
            bitmapRep = rep
        }

        let fmt = format ?? .png
        switch fmt {
        case .png:
            guard let data = bitmapRep.representation(using: .png, properties: [:]) else {
                throw NodeError(code: .internalError, message: "PNG encoding failed")
            }
            return data
        case .jpeg:
            let q = quality ?? 0.85
            guard let data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: q]) else {
                throw NodeError(code: .internalError, message: "JPEG encoding failed")
            }
            return data
        }
    }

    // MARK: - Private

    private func createPanel() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(CanvasSchemeHandler(), forURLScheme: "mcclaw-canvas")

        // Register A2UI message handler
        config.userContentController.add(a2uiHandler, name: "mcclawCanvasA2UIAction")

        // Inject A2UI bridge JavaScript
        let bridgeScript = WKUserScript(source: Self.a2uiBridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(bridgeScript)

        let wv = WKWebView(frame: NSRect(origin: .zero, size: Self.panelDefaultSize), configuration: config)
        wv.setValue(false, forKey: "drawsBackground") // Transparent background

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelDefaultSize),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "McClaw Canvas"
        p.contentView = wv
        p.minSize = Self.panelMinSize
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.center()

        self.webView = wv
        self.panel = p

        // Load initial scaffold
        loadScaffoldPage()
    }

    private func loadScaffoldPage() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
                    background: #1a1a2e;
                    color: #e0e0e0;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    min-height: 100vh;
                }
                .container {
                    text-align: center;
                    padding: 2rem;
                }
                .icon { font-size: 3rem; margin-bottom: 1rem; opacity: 0.6; }
                h2 { font-weight: 500; margin-bottom: 0.5rem; opacity: 0.8; }
                p { font-size: 0.9rem; opacity: 0.5; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="icon">🖼️</div>
                <h2>Canvas Ready</h2>
                <p>Awaiting agent instructions.</p>
            </div>
        </body>
        </html>
        """
        loadHTML(html)
    }

    private func applyPlacement(_ placement: CanvasPlacementParams) {
        guard let panel else { return }
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let x = placement.x.map { screenFrame.origin.x + $0 } ?? panel.frame.origin.x
        let y = placement.y.map { screenFrame.origin.y + screenFrame.height - $0 - (placement.height ?? panel.frame.height) } ?? panel.frame.origin.y
        let w = placement.width ?? panel.frame.width
        let h = placement.height ?? panel.frame.height

        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    // MARK: - A2UI Bridge JS

    private static let a2uiBridgeJS = """
    (function() {
        'use strict';

        // Listen for A2UI action events from the canvas content
        document.addEventListener('a2uiaction', function(e) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mcclawCanvasA2UIAction) {
                var detail = e.detail || {};
                window.webkit.messageHandlers.mcclawCanvasA2UIAction.postMessage({
                    actionName: detail.name || '',
                    surfaceId: detail.surfaceId || '',
                    sourceComponentId: detail.sourceComponentId || '',
                    context: detail.context || {}
                });
            }
        });

        // Provide a global function for receiving action status from Swift
        globalThis.__mcclawCanvasA2UIActionStatus = function(actionId, ok, error) {
            document.dispatchEvent(new CustomEvent('a2uiactionstatus', {
                detail: { actionId: actionId, ok: ok, error: error }
            }));
        };
    })();
    """
}
