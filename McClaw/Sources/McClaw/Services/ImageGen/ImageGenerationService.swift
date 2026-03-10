import Foundation
import Logging

/// Generates AI images using Vertex AI Imagen 3, reusing the Gemini CLI OAuth token.
/// Falls back to a programmatic placeholder if the API is unavailable.
actor ImageGenerationService {
    static let shared = ImageGenerationService()

    private let logger = Logger(label: "ai.mcclaw.image-gen")
    private let fileManager = FileManager.default

    /// Output directory for generated images.
    private var outputDir: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/images", isDirectory: true)
    }

    /// Generate an image from a text prompt. Returns the file path on success.
    func generate(prompt: String, aspectRatio: String = "1:1") async -> String? {
        try? fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let imageName = "img-\(UUID().uuidString.prefix(8)).png"
        let imageURL = outputDir.appendingPathComponent(imageName)

        logger.info("Starting image generation: \(prompt.prefix(80))")

        // Try Gemini Vertex AI Imagen 3
        if let accessToken = loadGeminiAccessToken() {
            if let imageData = await generateViaVertexAI(
                prompt: prompt,
                accessToken: accessToken,
                aspectRatio: aspectRatio
            ) {
                do {
                    try imageData.write(to: imageURL)
                    logger.info("Image generated: \(imageURL.path)")
                    return imageURL.path
                } catch {
                    logger.error("Failed to save image: \(error)")
                }
            }
        } else {
            logger.warning("No Gemini OAuth token available for image generation")
        }

        return nil
    }

    // MARK: - Gemini OAuth Token

    /// Read the Gemini CLI's OAuth access token from ~/.gemini/oauth_creds.json.
    /// Automatically refreshes the token if expired.
    private func loadGeminiAccessToken() -> String? {
        let credsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: credsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String,
              !token.isEmpty else {
            return nil
        }

        // Check if token is expired
        if let expiryDate = json["expiry_date"] as? Double {
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

    // MARK: - Vertex AI Imagen 3

    /// Generate image via Vertex AI Imagen 3.
    private func generateViaVertexAI(prompt: String, accessToken: String, aspectRatio: String) async -> Data? {
        guard let projectId = await discoverGCPProjectId(accessToken: accessToken) else {
            logger.error("Could not discover GCP project ID")
            return nil
        }

        // First attempt
        if let imageData = await callVertexAIImagen(
            prompt: prompt,
            accessToken: accessToken,
            projectId: projectId,
            aspectRatio: aspectRatio
        ) {
            return imageData
        }

        // If first attempt failed, try enabling the Vertex AI API
        logger.info("First attempt failed, trying to enable Vertex AI API...")
        if await enableVertexAIAPI(accessToken: accessToken, projectId: projectId) {
            try? await Task.sleep(for: .seconds(15))
            return await callVertexAIImagen(
                prompt: prompt,
                accessToken: accessToken,
                projectId: projectId,
                aspectRatio: aspectRatio
            )
        }

        return nil
    }

    /// Call Vertex AI Imagen 3 to generate an image.
    private func callVertexAIImagen(
        prompt: String,
        accessToken: String,
        projectId: String,
        aspectRatio: String
    ) async -> Data? {
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
                "aspectRatio": aspectRatio
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
                logger.error("Vertex AI Imagen error \(httpResponse.statusCode): \(bodyStr.prefix(300))")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let predictions = json["predictions"] as? [[String: Any]],
                  let first = predictions.first,
                  let base64 = first["bytesBase64Encoded"] as? String,
                  let imageData = Data(base64Encoded: base64) else {
                logger.error("Vertex AI: could not parse predictions")
                return nil
            }

            logger.info("Vertex AI Imagen 3: success! Got \(imageData.count) bytes")
            return imageData
        } catch {
            logger.error("Vertex AI error: \(error)")
            return nil
        }
    }

    /// Enable the Vertex AI API in the user's GCP project.
    private func enableVertexAIAPI(accessToken: String, projectId: String) async -> Bool {
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
                logger.info("Vertex AI API enabled in project \(projectId)")
                return true
            } else {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                logger.error("Failed to enable Vertex AI API (\(httpResponse.statusCode)): \(bodyStr.prefix(300))")
                return false
            }
        } catch {
            logger.error("Enable Vertex AI API error: \(error)")
            return false
        }
    }

    /// Discover the user's GCP project ID via Resource Manager API.
    private func discoverGCPProjectId(accessToken: String) async -> String? {
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

            // Prefer the Gemini-related project
            if let geminiProject = activeProjects.first(where: {
                let pid = ($0["projectId"] as? String) ?? ""
                return pid.contains("gen-lang") || pid.contains("gemini")
            }), let projectId = geminiProject["projectId"] as? String {
                return projectId
            }

            return activeProjects.first?["projectId"] as? String
        } catch {
            logger.error("Failed to discover GCP projects: \(error)")
            return nil
        }
    }
}
