import Foundation

/// Type of artifact stored in a project.
enum ArtifactType: String, Codable, Sendable {
    case plan
    case document
    case diagnostic
}

/// Metadata for a single artifact stored in a project.
struct ProjectArtifact: Identifiable, Codable, Sendable {
    let id: String
    let fileName: String
    let type: ArtifactType
    let sourceCLI: String?
    let sourceSessionId: String?
    let createdAt: Date
    let originalPath: String?

    init(
        id: String = UUID().uuidString,
        fileName: String,
        type: ArtifactType = .plan,
        sourceCLI: String? = nil,
        sourceSessionId: String? = nil,
        createdAt: Date = Date(),
        originalPath: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.type = type
        self.sourceCLI = sourceCLI
        self.sourceSessionId = sourceSessionId
        self.createdAt = createdAt
        self.originalPath = originalPath
    }

    /// SF Symbol icon name based on artifact type.
    var iconName: String {
        switch type {
        case .plan: "doc.text.fill"
        case .document: "doc.fill"
        case .diagnostic: "stethoscope"
        }
    }

    /// Tint color name for the icon.
    var iconColorName: String {
        switch type {
        case .plan: "orange"
        case .document: "blue"
        case .diagnostic: "purple"
        }
    }

    /// Stored file name on disk: {id}_{fileName}
    var storedFileName: String {
        "\(id)_\(fileName)"
    }
}

/// Pending artifact save request (shown as a sheet in general chat).
struct PendingArtifactSave: Sendable {
    let filePath: String
    let fileName: String
    let sourceCLI: String
    let sessionId: String
}
