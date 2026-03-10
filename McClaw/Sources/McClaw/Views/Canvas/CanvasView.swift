import SwiftUI
import WebKit
import McClawKit

/// Canvas panel - Inline canvas view for embedding in the main window.
/// The primary canvas uses CanvasWindowController as a floating panel,
/// but this view provides an inline fallback for settings preview.
struct CanvasView: View {
    @Environment(AppState.self) private var appState
    @State private var canvasManager = CanvasManager.shared

    var body: some View {
        if appState.canvasEnabled {
            VStack(spacing: 0) {
                canvasHeader
                Divider()
                canvasContent
            }
            .frame(minWidth: 400, minHeight: 300)
        } else {
            ContentUnavailableView(
                "Canvas Disabled",
                systemImage: "rectangle.on.rectangle.slash",
                description: Text("Enable Canvas in Settings > Advanced")
            )
        }
    }

    private var canvasHeader: some View {
        HStack {
            Image(systemName: "rectangle.on.rectangle")
            Text("Canvas")
                .font(.subheadline.weight(.medium))
            Spacer()
            if canvasManager.isCanvasVisible {
                Button("Close Panel") {
                    canvasManager.close()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            } else {
                Button("Open Panel") {
                    let sessionKey = appState.currentSessionId ?? "main"
                    canvasManager.show(sessionKey: sessionKey)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var canvasContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Canvas Panel")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("The canvas opens as a floating panel.\nUse the button above or wait for agent commands.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let sessionKey = canvasManager.currentSessionKey {
                Text("Session: \(sessionKey)")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Handles mcclaw-canvas:// URL scheme requests.
/// Serves local files from the canvas session directory (~/.mcclaw/canvas/{sessionKey}/).
final class CanvasSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        // Parse: mcclaw-canvas://sessionKey/path/to/file
        let sessionKey = url.host ?? "local"
        var filePath = url.path
        if filePath.isEmpty || filePath == "/" {
            filePath = "/index.html"
        }

        // Map to local filesystem
        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw")
        let sessionDir = canvasSessionDirectory(sessionKey: sessionKey, baseDir: baseDir)
        let fileURL = sessionDir.appendingPathComponent(filePath)

        // Check if file exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let ext = fileURL.pathExtension
                let mime = mimeTypeForExtension(ext)

                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": mime,
                        "Content-Length": "\(data.count)",
                        "Cache-Control": "no-cache",
                    ]
                )!
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
                return
            } catch {
                urlSchemeTask.didFailWithError(error)
                return
            }
        }

        // File not found - return 404
        let notFoundHTML = "<html><body><h1>404</h1><p>File not found: \(filePath)</p></body></html>"
        let data = Data(notFoundHTML.utf8)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
