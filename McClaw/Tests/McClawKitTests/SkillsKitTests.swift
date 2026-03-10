import Foundation
import Testing
@testable import McClawKit

// MARK: - YAML Frontmatter Parsing

@Suite("SkillsKit Frontmatter Parsing")
struct SkillsFrontmatterTests {

    @Test("Parse full SKILL.md with all fields")
    func parseFullFrontmatter() {
        let content = """
        ---
        name: woocommerce
        description: "WooCommerce development patterns and hooks"
        version: 1.0
        compatibility: "WooCommerce 9.0+ on WordPress 6.9+"
        emoji: "🛒"
        author: "José Conti"
        ---

        # WooCommerce Development

        ## When to use
        - Writing or modifying a WooCommerce extension
        """

        let result = SkillsKit.parseFrontmatter(content)
        #expect(result != nil)
        #expect(result?.metadata.name == "woocommerce")
        #expect(result?.metadata.description == "WooCommerce development patterns and hooks")
        #expect(result?.metadata.version == "1.0")
        #expect(result?.metadata.compatibility == "WooCommerce 9.0+ on WordPress 6.9+")
        #expect(result?.metadata.emoji == "🛒")
        #expect(result?.metadata.author == "José Conti")
        #expect(result?.body.contains("# WooCommerce Development") == true)
    }

    @Test("Parse minimal SKILL.md (only name)")
    func parseMinimalFrontmatter() {
        let content = """
        ---
        name: my-skill
        ---

        Some instructions.
        """

        let result = SkillsKit.parseFrontmatter(content)
        #expect(result != nil)
        #expect(result?.metadata.name == "my-skill")
        #expect(result?.metadata.description == "")
        #expect(result?.metadata.version == nil)
        #expect(result?.metadata.emoji == nil)
        #expect(result?.body == "Some instructions.")
    }

    @Test("Returns nil without frontmatter")
    func noFrontmatter() {
        let content = "# Just markdown\n\nNo frontmatter here."
        #expect(SkillsKit.parseFrontmatter(content) == nil)
    }

    @Test("Returns nil with missing closing ---")
    func unclosedFrontmatter() {
        let content = """
        ---
        name: broken
        description: no closing marker
        """
        #expect(SkillsKit.parseFrontmatter(content) == nil)
    }

    @Test("Returns nil with missing name")
    func missingName() {
        let content = """
        ---
        description: "No name field"
        ---

        Body text.
        """
        #expect(SkillsKit.parseFrontmatter(content) == nil)
    }

    @Test("Handles single-quoted values")
    func singleQuotedValues() {
        let content = """
        ---
        name: 'test-skill'
        description: 'A test skill'
        ---

        Body.
        """
        let result = SkillsKit.parseFrontmatter(content)
        #expect(result?.metadata.name == "test-skill")
        #expect(result?.metadata.description == "A test skill")
    }

    @Test("Handles unquoted values")
    func unquotedValues() {
        let content = """
        ---
        name: site-security
        description: WordPress security hardening
        version: 2.0
        ---

        Instructions.
        """
        let result = SkillsKit.parseFrontmatter(content)
        #expect(result?.metadata.name == "site-security")
        #expect(result?.metadata.description == "WordPress security hardening")
        #expect(result?.metadata.version == "2.0")
    }
}

// MARK: - Skill Folder Validation

@Suite("SkillsKit Folder Validation")
struct SkillsFolderValidationTests {

    @Test("Valid skill folder has SKILL.md")
    func validFolder() {
        #expect(SkillsKit.isValidSkillFolder(files: ["SKILL.md", "references"]) == true)
    }

    @Test("Invalid folder without SKILL.md")
    func invalidFolder() {
        #expect(SkillsKit.isValidSkillFolder(files: ["README.md", "references"]) == false)
    }

    @Test("Empty folder is invalid")
    func emptyFolder() {
        #expect(SkillsKit.isValidSkillFolder(files: []) == false)
    }
}

// MARK: - System Prompt Building

@Suite("SkillsKit System Prompt")
struct SkillsSystemPromptTests {

    @Test("Returns nil for empty skills")
    func emptySkills() {
        #expect(SkillsKit.buildSkillsSystemPrompt(skills: []) == nil)
    }

    @Test("Builds prompt with single skill")
    func singleSkill() {
        let skill = SkillsKit.LocalSkill(
            id: "woocommerce",
            metadata: SkillsKit.SkillMetadata(
                name: "WooCommerce",
                description: "WooCommerce development",
                emoji: "🛒"
            ),
            folderPath: "/home/.mcclaw/skills/woocommerce",
            referenceFiles: ["hooks.md", "hpos.md"]
        )
        let prompt = SkillsKit.buildSkillsSystemPrompt(skills: [skill])
        #expect(prompt != nil)
        #expect(prompt!.contains("# Available Skills"))
        #expect(prompt!.contains("🛒 WooCommerce"))
        #expect(prompt!.contains("WooCommerce development"))
        #expect(prompt!.contains("/home/.mcclaw/skills/woocommerce/SKILL.md"))
        #expect(prompt!.contains("hooks.md"))
        #expect(prompt!.contains("hpos.md"))
    }

    @Test("Builds prompt with multiple skills")
    func multipleSkills() {
        let skills = [
            SkillsKit.LocalSkill(
                id: "security",
                metadata: SkillsKit.SkillMetadata(name: "Security", description: "Hardening"),
                folderPath: "/skills/security",
                referenceFiles: []
            ),
            SkillsKit.LocalSkill(
                id: "seo",
                metadata: SkillsKit.SkillMetadata(name: "SEO", description: "Optimization"),
                folderPath: "/skills/seo",
                referenceFiles: ["guide.md"]
            ),
        ]
        let prompt = SkillsKit.buildSkillsSystemPrompt(skills: skills)
        #expect(prompt != nil)
        #expect(prompt!.contains("Security"))
        #expect(prompt!.contains("SEO"))
    }

    @Test("Uses default emoji when none provided")
    func defaultEmoji() {
        let skill = SkillsKit.LocalSkill(
            id: "test",
            metadata: SkillsKit.SkillMetadata(name: "Test", description: "desc"),
            folderPath: "/skills/test",
            referenceFiles: []
        )
        let prompt = SkillsKit.buildSkillsSystemPrompt(skills: [skill])!
        #expect(prompt.contains("⚡ Test"))
    }
}

// MARK: - ZIP Structure Detection

@Suite("SkillsKit ZIP Detection")
struct SkillsZIPDetectionTests {

    @Test("Detect nested root folder")
    func nestedRoot() {
        let entries = ["my-skill/SKILL.md", "my-skill/references/guide.md"]
        #expect(SkillsKit.detectZipRootFolder(entries: entries) == "my-skill")
    }

    @Test("Flat structure returns nil")
    func flatStructure() {
        let entries = ["SKILL.md", "references/guide.md"]
        #expect(SkillsKit.detectZipRootFolder(entries: entries) == nil)
    }

    @Test("Mixed roots returns nil")
    func mixedRoots() {
        let entries = ["folder-a/SKILL.md", "folder-b/other.md"]
        #expect(SkillsKit.detectZipRootFolder(entries: entries) == nil)
    }
}

// MARK: - SkillsConfig

@Suite("SkillsKit Config")
struct SkillsConfigTests {

    @Test("Default config has no disabled skills")
    func defaultConfig() {
        let config = SkillsKit.SkillsConfig()
        #expect(config.disabled.isEmpty)
    }

    @Test("Config encodes and decodes")
    func codable() throws {
        let config = SkillsKit.SkillsConfig(disabled: ["skill-a", "skill-b"])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SkillsKit.SkillsConfig.self, from: data)
        #expect(decoded.disabled == config.disabled)
    }
}
