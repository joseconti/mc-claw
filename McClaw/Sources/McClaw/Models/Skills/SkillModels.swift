import Foundation
import McClawKit

/// A local skill loaded from ~/.mcclaw/skills/.
struct LocalSkillInfo: Identifiable, Sendable {
    let id: String              // folder name = skill key
    let metadata: SkillsKit.SkillMetadata
    let folderPath: String
    let referenceFiles: [String]
    var isEnabled: Bool

    /// Convert to the pure-logic type for prompt building.
    var asLocalSkill: SkillsKit.LocalSkill {
        SkillsKit.LocalSkill(
            id: id,
            metadata: metadata,
            folderPath: folderPath,
            referenceFiles: referenceFiles
        )
    }
}
