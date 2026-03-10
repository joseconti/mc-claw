import AppKit
import Foundation
import Logging

/// Persists projects to disk at `~/.mcclaw/projects/`.
/// Each project is stored as a JSON file named `{projectId}.json`.
@MainActor
@Observable
final class ProjectStore {
    static let shared = ProjectStore()

    /// All known projects, sorted by last update (newest first).
    private(set) var projects: [ProjectInfo] = []

    private let logger = Logger(label: "ai.mcclaw.projects")
    private let fileManager = FileManager.default

    private var projectsDir: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/projects", isDirectory: true)
    }

    private init() {}

    // MARK: - Directory

    func ensureDirectory() {
        try? fileManager.createDirectory(at: projectsDir, withIntermediateDirectories: true)
    }

    // MARK: - Create

    /// Create a new project with the given name.
    @discardableResult
    func create(name: String, description: String = "") -> ProjectInfo {
        let project = ProjectInfo(name: name, description: description)
        save(project)
        return project
    }

    // MARK: - Save

    /// Save a project to disk.
    func save(_ project: ProjectInfo) {
        ensureDirectory()
        let url = projectsDir.appendingPathComponent("\(project.id).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(project)
            try data.write(to: url, options: .atomic)
            logger.info("Project saved: \(project.name) (\(project.sessionIds.count) sessions)")
            refreshIndex()
        } catch {
            logger.error("Failed to save project \(project.id): \(error)")
        }
    }

    // MARK: - Load

    /// Load a single project from disk.
    func load(projectId: String) -> ProjectInfo? {
        let url = projectsDir.appendingPathComponent("\(projectId).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(ProjectInfo.self, from: data)
        } catch {
            logger.error("Failed to load project \(projectId): \(error)")
            return nil
        }
    }

    // MARK: - Delete

    /// Delete a project. Sessions inside are NOT deleted; they return to the main list.
    func delete(projectId: String) {
        // Unassign sessions from this project
        let sessionStore = SessionStore.shared
        if let project = load(projectId: projectId) {
            for sessionId in project.sessionIds {
                sessionStore.unassignFromProject(sessionId: sessionId)
            }
        }

        let url = projectsDir.appendingPathComponent("\(projectId).json")
        try? fileManager.removeItem(at: url)
        logger.info("Project deleted: \(projectId)")
        refreshIndex()
    }

    // MARK: - Session Management

    /// Add a session to a project.
    func addSession(_ sessionId: String, toProject projectId: String) {
        guard var project = load(projectId: projectId) else { return }
        guard !project.sessionIds.contains(sessionId) else { return }
        project.sessionIds.append(sessionId)
        project.updatedAt = Date()
        save(project)

        // Mark session as belonging to this project
        SessionStore.shared.assignToProject(sessionId: sessionId, projectId: projectId)
    }

    /// Remove a session from a project (returns it to the main list).
    func removeSession(_ sessionId: String, fromProject projectId: String) {
        guard var project = load(projectId: projectId) else { return }
        project.sessionIds.removeAll { $0 == sessionId }
        project.updatedAt = Date()
        save(project)

        SessionStore.shared.unassignFromProject(sessionId: sessionId)
    }

    // MARK: - Update

    /// Rename a project.
    func rename(projectId: String, newName: String) {
        guard var project = load(projectId: projectId) else { return }
        project.name = newName
        project.updatedAt = Date()
        save(project)
    }

    /// Update all editable fields of a project.
    func update(projectId: String, name: String, description: String, rules: String) {
        guard var project = load(projectId: projectId) else { return }
        project.name = name
        project.description = description
        project.rules = rules
        project.updatedAt = Date()
        save(project)
    }

    /// Set the cover image path for a project.
    func setImagePath(projectId: String, imagePath: String) {
        guard var project = load(projectId: projectId) else { return }
        project.imagePath = imagePath
        project.updatedAt = Date()
        save(project)
    }

    // MARK: - Image

    /// Directory where project images are stored.
    var imagesDir: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/projects/images", isDirectory: true)
    }

    /// Generate a cover image for the project using the Gemini API (Imagen model).
    /// Reads the OAuth token from Gemini CLI's config (~/.gemini/oauth_creds.json)
    /// and calls the generativelanguage API directly for real AI image generation.
    func generateCoverImage(projectId: String) async {
        guard let project = load(projectId: projectId) else { return }

        try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let imageName = "\(projectId)_cover.png"
        let imageURL = imagesDir.appendingPathComponent(imageName)

        let description = project.description.isEmpty
            ? project.name
            : project.description

        let prompt = """
        Create a professional cover illustration for a software project. \
        Project name: "\(project.name)". \
        What this project does: \(description). \
        The image MUST visually represent the specific subject described above using recognizable \
        elements and metaphors directly related to it. \
        For example, if the project is about e-commerce orders, show shopping carts, packages, \
        receipts, databases. If it's about a website, show web elements. Be specific to the topic. \
        Style: modern 3D illustration with soft lighting, clean composition, professional colors. \
        No text or words in the image. Landscape 16:9.
        """

        // Try Gemini API with OAuth token first
        print("[IMAGE-GEN] Starting image generation for project: \(project.name)")
        print("[IMAGE-GEN] Prompt: \(prompt)")

        if let accessToken = loadGeminiAccessToken() {
            print("[IMAGE-GEN] Got OAuth token: \(accessToken.prefix(20))...")
            if let imageData = await generateImageViaGeminiAPI(prompt: prompt, accessToken: accessToken) {
                do {
                    try imageData.write(to: imageURL)
                    setImagePath(projectId: projectId, imagePath: "images/\(imageName)")
                    logger.info("AI cover image generated for project: \(project.name)")
                    print("[IMAGE-GEN] SUCCESS — AI image saved to \(imageURL.path)")
                    return
                } catch {
                    logger.error("Failed to save AI-generated image: \(error)")
                    print("[IMAGE-GEN] Failed to write image file: \(error)")
                }
            } else {
                print("[IMAGE-GEN] generateImageViaGeminiAPI returned nil — all methods failed")
            }
        } else {
            print("[IMAGE-GEN] No OAuth token available")
        }

        // Fallback: generate a programmatic gradient image using CLIBridge for color suggestion
        logger.info("Falling back to programmatic image generation")
        print("[IMAGE-GEN] FALLBACK — using programmatic gradient image")
        await generateFallbackImage(project: project, saveTo: imageURL)
        setImagePath(projectId: projectId, imagePath: "images/\(imageName)")
    }

    // MARK: - Gemini API Image Generation

    /// Read the Gemini CLI's OAuth access token from ~/.gemini/oauth_creds.json.
    /// Automatically refreshes the token if expired.
    private func loadGeminiAccessToken() -> String? {
        let credsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: credsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String,
              !token.isEmpty else {
            logger.warning("No Gemini OAuth token found at ~/.gemini/oauth_creds.json")
            return nil
        }

        // Check if token is expired
        if let expiryDate = json["expiry_date"] as? Double {
            // expiry_date is in milliseconds
            let expirySeconds = expiryDate > 1e12 ? expiryDate / 1000 : expiryDate
            if Date().timeIntervalSince1970 > expirySeconds {
                logger.info("Gemini OAuth token expired, refreshing via CLI...")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["gemini", "--version"]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()

                guard let newData = try? Data(contentsOf: credsURL),
                      let newJson = try? JSONSerialization.jsonObject(with: newData) as? [String: Any],
                      let newToken = newJson["access_token"] as? String else {
                    logger.error("Failed to refresh Gemini OAuth token")
                    return nil
                }
                return newToken
            }
        }

        return token
    }

    /// Generate image via Vertex AI Imagen 3 using the cloud-platform OAuth token.
    ///
    /// Why Vertex AI instead of generativelanguage.googleapis.com?
    /// The Gemini CLI's OAuth token has `cloud-platform` scope, which works with Vertex AI
    /// but NOT with the AI Studio API (generativelanguage.googleapis.com) for image generation.
    /// Vertex AI requires the `aiplatform.googleapis.com` API to be enabled in the GCP project.
    /// If not enabled, this method auto-enables it via the Service Usage API.
    private nonisolated func generateImageViaGeminiAPI(prompt: String, accessToken: String) async -> Data? {
        // Discover the user's GCP project ID
        guard let projectId = await discoverGCPProjectId(accessToken: accessToken) else {
            print("[IMAGE-GEN] Could not discover GCP project ID")
            return nil
        }
        print("[IMAGE-GEN] Using GCP project: \(projectId)")

        // Try to generate the image; if 403, auto-enable the API and retry once
        if let imageData = await callVertexAIImagen(prompt: prompt, accessToken: accessToken, projectId: projectId) {
            return imageData
        }

        // If first attempt failed, try enabling the Vertex AI API automatically
        print("[IMAGE-GEN] First attempt failed, trying to enable Vertex AI API...")
        if await enableVertexAIAPI(accessToken: accessToken, projectId: projectId) {
            // Wait for API activation to propagate
            print("[IMAGE-GEN] Vertex AI API enable requested, waiting 15s for propagation...")
            try? await Task.sleep(for: .seconds(15))
            return await callVertexAIImagen(prompt: prompt, accessToken: accessToken, projectId: projectId)
        }

        return nil
    }

    /// Call Vertex AI Imagen 3 to generate an image.
    private nonisolated func callVertexAIImagen(prompt: String, accessToken: String, projectId: String) async -> Data? {
        let model = "imagen-3.0-generate-002"
        let region = "us-central1"
        let urlString = "https://\(region)-aiplatform.googleapis.com/v1/projects/\(projectId)/locations/\(region)/publishers/google/models/\(model):predict"
        guard let url = URL(string: urlString) else { return nil }

        let requestBody: [String: Any] = [
            "instances": [
                ["prompt": prompt]
            ],
            "parameters": [
                "sampleCount": 1,
                "aspectRatio": "16:9"
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 90

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode != 200 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                print("[IMAGE-GEN] Vertex AI Imagen 3 error \(httpResponse.statusCode): \(bodyStr.prefix(300))")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let predictions = json["predictions"] as? [[String: Any]],
                  let first = predictions.first,
                  let base64 = first["bytesBase64Encoded"] as? String,
                  let imageData = Data(base64Encoded: base64) else {
                print("[IMAGE-GEN] Vertex AI: could not parse predictions")
                return nil
            }

            print("[IMAGE-GEN] Vertex AI Imagen 3: success! Got \(imageData.count) bytes")
            return imageData
        } catch {
            print("[IMAGE-GEN] Vertex AI error: \(error)")
            return nil
        }
    }

    /// Enable the Vertex AI API (`aiplatform.googleapis.com`) in the user's GCP project.
    /// This is required once per project for image generation to work.
    /// Uses the Service Usage API: POST /v1/projects/{project}/services/{service}:enable
    private nonisolated func enableVertexAIAPI(accessToken: String, projectId: String) async -> Bool {
        let urlString = "https://serviceusage.googleapis.com/v1/projects/\(projectId)/services/aiplatform.googleapis.com:enable"
        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }

            if httpResponse.statusCode == 200 {
                print("[IMAGE-GEN] Vertex AI API enabled successfully in project \(projectId)")
                return true
            } else {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                print("[IMAGE-GEN] Failed to enable Vertex AI API (\(httpResponse.statusCode)): \(bodyStr.prefix(300))")
                return false
            }
        } catch {
            print("[IMAGE-GEN] Enable Vertex AI API error: \(error)")
            return false
        }
    }

    /// Discover the user's GCP project ID via Resource Manager API.
    /// Looks for Gemini-related projects first, then falls back to the first active project.
    private nonisolated func discoverGCPProjectId(accessToken: String) async -> String? {
        guard let url = URL(string: "https://cloudresourcemanager.googleapis.com/v1/projects?pageSize=10") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let projects = json["projects"] as? [[String: Any]] else {
                return nil
            }

            let activeProjects = projects.filter { ($0["lifecycleState"] as? String) == "ACTIVE" }

            // Prefer the Gemini-related project (created by Gemini CLI)
            if let geminiProject = activeProjects.first(where: {
                let pid = ($0["projectId"] as? String) ?? ""
                return pid.contains("gen-lang") || pid.contains("gemini")
            }), let projectId = geminiProject["projectId"] as? String {
                return projectId
            }

            return activeProjects.first?["projectId"] as? String
        } catch {
            print("[IMAGE-GEN] Failed to discover GCP projects: \(error)")
            return nil
        }
    }

    // MARK: - Fallback Image Generation

    /// Generate a gradient image using CLIBridge for color suggestion, then Core Graphics.
    private func generateFallbackImage(project: ProjectInfo, saveTo url: URL) async {
        // Ask active CLI for color suggestion
        let appState = AppState.shared
        let provider = appState.availableCLIs.first(where: {
            $0.isInstalled && $0.isAuthenticated
        }) ?? appState.currentCLI

        var color1 = "#4A90D9"
        var color2 = "#7B68EE"
        var symbol = "folder.fill"

        if let provider {
            let prompt = """
            Reply with ONLY a JSON object with these keys:
            - "color1": hex color (e.g. "#4A90D9")
            - "color2": hex color (e.g. "#7B68EE")
            - "symbol": SF Symbol name (e.g. "doc.text", "gearshape.2")
            For a project called "\(project.name)". JSON only:
            """
            let stream = await CLIBridge.shared.send(message: prompt, provider: provider)
            var response = ""
            for await event in stream {
                if case .text(let chunk) = event { response += chunk }
            }
            // Parse JSON from response
            if let start = response.firstIndex(of: "{"),
               let end = response.lastIndex(of: "}"),
               let data = String(response[start...end]).data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                color1 = json["color1"] as? String ?? color1
                color2 = json["color2"] as? String ?? color2
                symbol = json["symbol"] as? String ?? symbol
            }
        }

        // Generate gradient image with Core Graphics
        let size = NSSize(width: 512, height: 288)
        let image = NSImage(size: size, flipped: false) { rect in
            let c1 = NSColor.fromHex(color1) ?? NSColor.systemBlue
            let c2 = NSColor.fromHex(color2) ?? NSColor.systemPurple
            let gradient = NSGradient(starting: c1, ending: c2) ?? NSGradient(starting: .systemBlue, ending: .systemPurple)!
            gradient.draw(in: rect, angle: 135)

            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 80, weight: .light)
            if let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig) {
                let symbolSize = symbolImage.size
                let symbolRect = NSRect(
                    x: (rect.width - symbolSize.width) / 2,
                    y: (rect.height - symbolSize.height) / 2 + 16,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                symbolImage.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 0.85)
            }

            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9)
            ]
            let nameStr = NSAttributedString(string: String(project.name.prefix(30)), attributes: nameAttrs)
            let nameSize = nameStr.size()
            nameStr.draw(at: NSPoint(x: (rect.width - nameSize.width) / 2, y: 32))

            return true
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        try? pngData.write(to: url)
    }

    // MARK: - Index

    /// Refresh the project index by scanning the projects directory.
    func refreshIndex() {
        ensureDirectory()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var infos: [ProjectInfo] = []

        guard let urls = try? fileManager.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            projects = []
            return
        }

        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let project = try? decoder.decode(ProjectInfo.self, from: data) else {
                continue
            }
            infos.append(project)
        }

        projects = infos.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Load the cover image for a project, if one exists.
    func loadCoverImage(for project: ProjectInfo) -> NSImage? {
        guard let imagePath = project.imagePath else { return nil }
        let url = projectsDir.appendingPathComponent(imagePath)
        return NSImage(contentsOf: url)
    }
}

// MARK: - NSColor Hex

extension NSColor {
    /// Create an NSColor from a hex string like "#4A90D9" or "4A90D9".
    static func fromHex(_ hex: String) -> NSColor? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}
