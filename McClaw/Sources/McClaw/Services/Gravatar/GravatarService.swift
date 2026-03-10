import AppKit
import CryptoKit
import Logging

/// Fetches and caches user avatars from Gravatar.
@MainActor
final class GravatarService {
    static let shared = GravatarService()

    private let logger = Logger(label: "ai.mcclaw.gravatar")

    /// The cached user avatar image, if available.
    var cachedImage: NSImage? {
        guard let data = try? Data(contentsOf: avatarFileURL) else { return nil }
        return NSImage(data: data)
    }

    /// Path to the cached avatar file.
    private var avatarFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/avatar.png")
    }

    /// Path to the cached ETag file (for change detection).
    private var etagFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/avatar.etag")
    }

    /// Fetch the Gravatar for the given email and cache it locally.
    /// Returns true if the avatar was updated, false if unchanged.
    @discardableResult
    func fetchAvatar(for email: String) async -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }

        let hash = md5Hash(trimmed)
        let url = URL(string: "https://www.gravatar.com/avatar/\(hash)?s=256&d=404")!

        var request = URLRequest(url: url)
        // Send ETag for conditional request
        if let savedEtag = try? String(contentsOf: etagFileURL, encoding: .utf8) {
            request.setValue(savedEtag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }

            if httpResponse.statusCode == 304 {
                logger.info("Gravatar unchanged (304)")
                return false
            }

            guard httpResponse.statusCode == 200 else {
                logger.info("Gravatar not found (status \(httpResponse.statusCode))")
                return false
            }

            // Save avatar
            try data.write(to: avatarFileURL)

            // Save ETag
            if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
                try? etag.write(to: etagFileURL, atomically: true, encoding: .utf8)
            }

            logger.info("Gravatar avatar updated for \(trimmed)")
            return true
        } catch {
            logger.error("Gravatar fetch failed: \(error)")
            return false
        }
    }

    /// Delete the cached avatar.
    func clearCache() {
        try? FileManager.default.removeItem(at: avatarFileURL)
        try? FileManager.default.removeItem(at: etagFileURL)
    }

    /// MD5 hash of the email (Gravatar uses MD5).
    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
