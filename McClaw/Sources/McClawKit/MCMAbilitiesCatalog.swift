import Foundation

// MARK: - MCM Abilities Catalog
// Pre-cataloged abilities for MCP Content Manager for WordPress v2.5.0
// Source: abilities-catalog.md (278 abilities)

public struct MCMAbility: Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let params: [MCMParam]
    public let requiresConfirmation: Bool

    public init(id: String, name: String, description: String, params: [MCMParam] = [], requiresConfirmation: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.params = params
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct MCMParam: Sendable, Equatable {
    public let name: String
    public let type: String
    public let description: String
    public let required: Bool
    public let defaultValue: String?
    public let enumValues: [String]?

    public init(name: String, type: String = "string", description: String, required: Bool = false, defaultValue: String? = nil, enumValues: [String]? = nil) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.defaultValue = defaultValue
        self.enumValues = enumValues
    }
}

public struct MCMSubConnector: Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let icon: String
    public let abilities: [MCMAbility]

    public init(id: String, name: String, description: String, icon: String, abilities: [MCMAbility]) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.abilities = abilities
    }
}

// MARK: - Catalog

public enum MCMAbilitiesCatalog {
    public static let version = "2.5.0"

    public static let subConnectors: [MCMSubConnector] = [
        content, media, woocommerce, security, themes, system, users, seo, database, navigation, config, automation, vigia,
    ]

    public static var totalAbilities: Int {
        subConnectors.reduce(0) { $0 + $1.abilities.count }
    }

    /// Find a sub-connector by ID.
    public static func subConnector(for id: String) -> MCMSubConnector? {
        subConnectors.first { $0.id == id }
    }

    /// Find an ability by ID across all sub-connectors.
    public static func ability(for id: String) -> MCMAbility? {
        for sub in subConnectors {
            if let a = sub.abilities.first(where: { $0.id == id }) { return a }
        }
        return nil
    }

    /// Find which sub-connector contains a given ability ID.
    public static func subConnector(forAbility abilityId: String) -> MCMSubConnector? {
        subConnectors.first { sub in
            sub.abilities.contains { $0.id == abilityId }
        }
    }

    /// Find abilities matching a search query (name or description).
    public static func search(_ query: String) -> [MCMAbility] {
        let q = query.lowercased()
        return subConnectors.flatMap { $0.abilities }.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
    }

    // MARK: - wp.content

    public static let content = MCMSubConnector(
        id: "wp.content",
        name: "WP Content",
        description: "Content CRUD, taxonomy, comments, revisions, blocks, patterns, custom fields, import/export",
        icon: "doc.text",
        abilities: [
            // Content CRUD
            MCMAbility(id: "create-content", name: "Create Content", description: "Create content (any post type)", params: [
                MCMParam(name: "title", description: "Post title", required: true),
                MCMParam(name: "content", description: "Post content (HTML or blocks)"),
                MCMParam(name: "post_type", description: "Content type", defaultValue: "post"),
                MCMParam(name: "status", description: "Post status", defaultValue: "draft", enumValues: ["draft", "publish", "pending", "private", "future"]),
                MCMParam(name: "categories", description: "Category IDs (comma-separated)"),
                MCMParam(name: "tags", description: "Tag IDs (comma-separated)"),
                MCMParam(name: "excerpt", description: "Post excerpt"),
                MCMParam(name: "slug", description: "URL slug"),
                MCMParam(name: "author", type: "integer", description: "Author user ID"),
                MCMParam(name: "featured_media", type: "integer", description: "Featured image attachment ID"),
            ]),
            MCMAbility(id: "read-content", name: "Read Content", description: "Read content by ID (alias: get-content)", params: [
                MCMParam(name: "id", type: "integer", description: "Post ID", required: true),
            ]),
            MCMAbility(id: "update-content", name: "Update Content", description: "Update existing content", params: [
                MCMParam(name: "id", type: "integer", description: "Post ID", required: true),
                MCMParam(name: "title", description: "New title"),
                MCMParam(name: "content", description: "New content"),
                MCMParam(name: "status", description: "New status", enumValues: ["draft", "publish", "pending", "private", "future", "trash"]),
                MCMParam(name: "excerpt", description: "New excerpt"),
                MCMParam(name: "slug", description: "New slug"),
                MCMParam(name: "categories", description: "Category IDs"),
                MCMParam(name: "tags", description: "Tag IDs"),
            ]),
            MCMAbility(id: "search-content", name: "Search Content", description: "Search/list content with filters", params: [
                MCMParam(name: "search", description: "Search query"),
                MCMParam(name: "post_type", description: "Content type", defaultValue: "post"),
                MCMParam(name: "status", description: "Status filter", defaultValue: "publish"),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "10"),
                MCMParam(name: "page", type: "integer", description: "Page number", defaultValue: "1"),
                MCMParam(name: "orderby", description: "Sort field", defaultValue: "date", enumValues: ["date", "title", "modified", "id", "relevance"]),
                MCMParam(name: "order", description: "Sort direction", defaultValue: "desc", enumValues: ["asc", "desc"]),
                MCMParam(name: "author", type: "integer", description: "Filter by author ID"),
                MCMParam(name: "categories", description: "Filter by category IDs"),
                MCMParam(name: "tags", description: "Filter by tag IDs"),
            ]),
            MCMAbility(id: "delete-content", name: "Delete Content", description: "Delete content (trash or permanent)", params: [
                MCMParam(name: "id", type: "integer", description: "Post ID", required: true),
                MCMParam(name: "force", type: "boolean", description: "Permanently delete (skip trash)", defaultValue: "false"),
            ], requiresConfirmation: true),

            // Discovery
            MCMAbility(id: "site-schema", name: "Site Schema", description: "View site structure and content types"),
            MCMAbility(id: "inspect-post-type", name: "Inspect Post Type", description: "Inspect a specific content type", params: [
                MCMParam(name: "post_type", description: "Post type slug", required: true),
            ]),

            // Taxonomy
            MCMAbility(id: "list-terms", name: "List Terms", description: "List terms of a taxonomy", params: [
                MCMParam(name: "taxonomy", description: "Taxonomy slug (category, post_tag, etc.)", required: true),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "100"),
                MCMParam(name: "search", description: "Search query"),
                MCMParam(name: "parent", type: "integer", description: "Parent term ID"),
                MCMParam(name: "hide_empty", type: "boolean", description: "Hide terms with no posts", defaultValue: "false"),
            ]),
            MCMAbility(id: "create-term", name: "Create Term", description: "Create taxonomy term", params: [
                MCMParam(name: "taxonomy", description: "Taxonomy slug", required: true),
                MCMParam(name: "name", description: "Term name", required: true),
                MCMParam(name: "slug", description: "Term slug"),
                MCMParam(name: "description", description: "Term description"),
                MCMParam(name: "parent", type: "integer", description: "Parent term ID"),
            ]),
            MCMAbility(id: "update-term", name: "Update Term", description: "Update taxonomy term", params: [
                MCMParam(name: "taxonomy", description: "Taxonomy slug", required: true),
                MCMParam(name: "term_id", type: "integer", description: "Term ID", required: true),
                MCMParam(name: "name", description: "New name"),
                MCMParam(name: "slug", description: "New slug"),
                MCMParam(name: "description", description: "New description"),
            ]),
            MCMAbility(id: "delete-term", name: "Delete Term", description: "Delete taxonomy term", params: [
                MCMParam(name: "taxonomy", description: "Taxonomy slug", required: true),
                MCMParam(name: "term_id", type: "integer", description: "Term ID", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "bulk-create-terms", name: "Bulk Create Terms", description: "Bulk create taxonomy tree (nested children, existing term detection)", params: [
                MCMParam(name: "taxonomy", description: "Taxonomy slug", required: true),
                MCMParam(name: "terms", description: "JSON array of terms with name, slug, children", required: true),
            ], requiresConfirmation: true),

            // Comments
            MCMAbility(id: "list-comments", name: "List Comments", description: "List/search comments", params: [
                MCMParam(name: "post_id", type: "integer", description: "Filter by post ID"),
                MCMParam(name: "status", description: "Status filter", defaultValue: "approve", enumValues: ["approve", "hold", "spam", "trash", "all"]),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "10"),
                MCMParam(name: "search", description: "Search query"),
            ]),
            MCMAbility(id: "manage-comment", name: "Manage Comment", description: "Moderate/reply to comments", params: [
                MCMParam(name: "comment_id", type: "integer", description: "Comment ID", required: true),
                MCMParam(name: "action", description: "Action to perform", required: true, enumValues: ["approve", "unapprove", "spam", "trash", "delete", "reply"]),
                MCMParam(name: "content", description: "Reply content (required for reply action)"),
            ]),

            // Content Advanced
            MCMAbility(id: "list-revisions", name: "List Revisions", description: "List post revisions with author, date, excerpt", params: [
                MCMParam(name: "post_id", type: "integer", description: "Post ID", required: true),
            ]),
            MCMAbility(id: "restore-revision", name: "Restore Revision", description: "Restore to specific revision", params: [
                MCMParam(name: "revision_id", type: "integer", description: "Revision ID", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "manage-post-meta", name: "Manage Post Meta", description: "Universal CRUD for any post meta key", params: [
                MCMParam(name: "post_id", type: "integer", description: "Post ID", required: true),
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["get", "set", "delete", "list"]),
                MCMParam(name: "meta_key", description: "Meta key (required for get/set/delete)"),
                MCMParam(name: "meta_value", description: "Meta value (required for set)"),
            ]),
            MCMAbility(id: "manage-user-meta", name: "Manage User Meta", description: "Universal CRUD for any user meta key", params: [
                MCMParam(name: "user_id", type: "integer", description: "User ID", required: true),
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["get", "set", "delete", "list"]),
                MCMParam(name: "meta_key", description: "Meta key"),
                MCMParam(name: "meta_value", description: "Meta value"),
            ]),
            MCMAbility(id: "bulk-content-action", name: "Bulk Content Action", description: "Bulk publish/draft/trash/change_author/change_category", params: [
                MCMParam(name: "action", description: "Bulk action", required: true, enumValues: ["publish", "draft", "trash", "change_author", "change_category"]),
                MCMParam(name: "post_ids", description: "Comma-separated post IDs", required: true),
                MCMParam(name: "value", description: "Target value (author ID or category ID for change actions)"),
            ], requiresConfirmation: true),
            MCMAbility(id: "clone-content", name: "Clone Content", description: "Duplicate post with meta, taxonomies, featured image", params: [
                MCMParam(name: "id", type: "integer", description: "Source post ID", required: true),
                MCMParam(name: "status", description: "Status for clone", defaultValue: "draft"),
            ]),
            MCMAbility(id: "editorial-calendar", name: "Editorial Calendar", description: "View drafts/scheduled/pending by week/month", params: [
                MCMParam(name: "view", description: "View mode", defaultValue: "month", enumValues: ["week", "month"]),
                MCMParam(name: "date", description: "Start date (YYYY-MM-DD)"),
                MCMParam(name: "post_type", description: "Content type", defaultValue: "post"),
            ]),
            MCMAbility(id: "diff-content", name: "Diff Content", description: "Compare two revisions with line-by-line changes", params: [
                MCMParam(name: "revision_from", type: "integer", description: "First revision ID", required: true),
                MCMParam(name: "revision_to", type: "integer", description: "Second revision ID", required: true),
            ]),

            // Blocks & Patterns
            MCMAbility(id: "list-reusable-blocks", name: "List Reusable Blocks", description: "List wp_block posts with usage statistics"),
            MCMAbility(id: "manage-reusable-block", name: "Manage Reusable Block", description: "Create/update/delete reusable blocks", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["create", "update", "delete"]),
                MCMParam(name: "id", type: "integer", description: "Block ID (required for update/delete)"),
                MCMParam(name: "title", description: "Block title"),
                MCMParam(name: "content", description: "Block content (HTML/blocks)"),
            ], requiresConfirmation: true),
            MCMAbility(id: "list-block-patterns", name: "List Block Patterns", description: "List registered patterns from core, theme, plugins", params: [
                MCMParam(name: "category", description: "Filter by pattern category"),
            ]),
            MCMAbility(id: "register-block-pattern", name: "Register Block Pattern", description: "Register custom block pattern (persisted in wp_options)", params: [
                MCMParam(name: "title", description: "Pattern title", required: true),
                MCMParam(name: "content", description: "Pattern content (blocks HTML)", required: true),
                MCMParam(name: "categories", description: "Pattern categories (comma-separated)"),
                MCMParam(name: "description", description: "Pattern description"),
            ]),

            // Custom Fields
            MCMAbility(id: "list-field-groups", name: "List Field Groups", description: "List field groups from ACF/Meta Box/Pods/JetEngine with fields and locations"),
            MCMAbility(id: "read-structured-fields", name: "Read Structured Fields", description: "Read post fields via plugin-native API (resolves repeaters/groups/flexible)", params: [
                MCMParam(name: "post_id", type: "integer", description: "Post ID", required: true),
                MCMParam(name: "group", description: "Field group name (optional filter)"),
            ]),
            MCMAbility(id: "update-structured-fields", name: "Update Structured Fields", description: "Update fields via plugin-native API (respects validation)", params: [
                MCMParam(name: "post_id", type: "integer", description: "Post ID", required: true),
                MCMParam(name: "fields", description: "JSON object of field_name: value pairs", required: true),
            ]),

            // Import/Export
            MCMAbility(id: "export-content", name: "Export Content", description: "Export content as WXR (filters: content type, author, dates, status, category)", params: [
                MCMParam(name: "post_type", description: "Content type to export"),
                MCMParam(name: "status", description: "Status filter"),
                MCMParam(name: "author", type: "integer", description: "Author ID filter"),
                MCMParam(name: "start_date", description: "Start date (YYYY-MM-DD)"),
                MCMParam(name: "end_date", description: "End date (YYYY-MM-DD)"),
                MCMParam(name: "category", description: "Category filter"),
            ]),
            MCMAbility(id: "import-content", name: "Import Content", description: "Import content from WXR file", params: [
                MCMParam(name: "file", description: "WXR file path on server", required: true),
            ], requiresConfirmation: true),
        ]
    )

    // MARK: - wp.media

    public static let media = MCMSubConnector(
        id: "wp.media",
        name: "WP Media",
        description: "Media library, upload, optimization, analysis, AI image generation",
        icon: "photo.on.rectangle",
        abilities: [
            MCMAbility(id: "list-media", name: "List Media", description: "List media attachments", params: [
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "10"),
                MCMParam(name: "page", type: "integer", description: "Page number", defaultValue: "1"),
                MCMParam(name: "search", description: "Search query"),
                MCMParam(name: "mime_type", description: "MIME type filter (image, video, application/pdf)"),
                MCMParam(name: "orderby", description: "Sort field", defaultValue: "date"),
            ]),
            MCMAbility(id: "upload-media", name: "Upload Media", description: "Upload media from URL", params: [
                MCMParam(name: "url", description: "Source URL", required: true),
                MCMParam(name: "title", description: "Media title"),
                MCMParam(name: "alt_text", description: "Alt text for accessibility"),
                MCMParam(name: "caption", description: "Media caption"),
                MCMParam(name: "post_id", type: "integer", description: "Attach to post ID"),
            ]),
            MCMAbility(id: "update-media", name: "Update Media", description: "Update media metadata", params: [
                MCMParam(name: "id", type: "integer", description: "Attachment ID", required: true),
                MCMParam(name: "title", description: "New title"),
                MCMParam(name: "alt_text", description: "New alt text"),
                MCMParam(name: "caption", description: "New caption"),
                MCMParam(name: "description", description: "New description"),
            ]),
            MCMAbility(id: "delete-media", name: "Delete Media", description: "Delete media attachment", params: [
                MCMParam(name: "id", type: "integer", description: "Attachment ID", required: true),
                MCMParam(name: "force", type: "boolean", description: "Permanently delete", defaultValue: "true"),
            ], requiresConfirmation: true),
            MCMAbility(id: "set-featured-image", name: "Set Featured Image", description: "Set featured image on a post", params: [
                MCMParam(name: "post_id", type: "integer", description: "Post ID", required: true),
                MCMParam(name: "media_id", type: "integer", description: "Attachment ID", required: true),
            ]),

            // Media Analysis
            MCMAbility(id: "media-stats", name: "Media Stats", description: "Complete media dashboard (MIME types, formats, alt coverage, sizes)"),
            MCMAbility(id: "media-unused", name: "Media Unused", description: "Detect orphaned media not referenced in content", params: [
                MCMParam(name: "dry_run", type: "boolean", description: "Preview only (no deletions)", defaultValue: "true"),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "20"),
            ]),
            MCMAbility(id: "media-convert", name: "Media Convert", description: "Convert images to WebP/AVIF (preserves originals)", params: [
                MCMParam(name: "format", description: "Target format", required: true, enumValues: ["webp", "avif"]),
                MCMParam(name: "quality", type: "integer", description: "Compression quality (1-100)", defaultValue: "80"),
                MCMParam(name: "dry_run", type: "boolean", description: "Preview only", defaultValue: "true"),
            ], requiresConfirmation: true),
            MCMAbility(id: "media-regenerate", name: "Media Regenerate", description: "Regenerate thumbnails after theme/size changes", params: [
                MCMParam(name: "dry_run", type: "boolean", description: "Preview only", defaultValue: "true"),
                MCMParam(name: "attachment_id", type: "integer", description: "Specific attachment ID (optional)"),
            ], requiresConfirmation: true),

            // AI Image Generation
            MCMAbility(id: "generate-image", name: "Generate Image", description: "Generate AI image with Gemini/Imagen and save to Media Library", params: [
                MCMParam(name: "prompt", description: "Image description prompt", required: true),
                MCMParam(name: "post_id", type: "integer", description: "Set as featured image for this post"),
                MCMParam(name: "insert_in_content", type: "boolean", description: "Insert in post content", defaultValue: "false"),
                MCMParam(name: "title", description: "Media title"),
                MCMParam(name: "alt_text", description: "Alt text"),
            ]),
            MCMAbility(id: "edit-image", name: "Edit Image", description: "Edit existing image with AI", params: [
                MCMParam(name: "media_id", type: "integer", description: "Source attachment ID", required: true),
                MCMParam(name: "prompt", description: "Edit instruction", required: true),
            ]),
        ]
    )

    // MARK: - wp.security

    public static let security = MCMSubConnector(
        id: "wp.security",
        name: "WP Security",
        description: "Security audit, hardening, malware scanning, core integrity, cleanup",
        icon: "shield.checkered",
        abilities: [
            // Security Hardening
            MCMAbility(id: "security-audit", name: "Security Audit", description: "Full security audit (score 0-100, grade A+ to F)"),
            MCMAbility(id: "security-apply", name: "Security Apply", description: "Apply a specific security measure", params: [
                MCMParam(name: "measure", description: "Measure ID to apply", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "security-status", name: "Security Status", description: "Quick security status summary"),
            MCMAbility(id: "security-guidelines", name: "Security Guidelines", description: "Security hardening guide"),
            MCMAbility(id: "security-apply-safe", name: "Security Apply Safe", description: "Batch-apply all 12 SAFE measures at once"),
            MCMAbility(id: "security-revert", name: "Security Revert", description: "Revert a previously applied measure", params: [
                MCMParam(name: "measure", description: "Measure ID to revert", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "security-revert-safe", name: "Security Revert Safe", description: "Batch-revert all applied SAFE measures", requiresConfirmation: true),
            MCMAbility(id: "security-emergency-login", name: "Emergency Login", description: "Restore /wp-login.php temporarily (15 min)", requiresConfirmation: true),
            MCMAbility(id: "security-force-logout", name: "Force Logout", description: "Force logout all user sessions", requiresConfirmation: true),
            MCMAbility(id: "detect-default-content", name: "Detect Default Content", description: "Detect/cleanup default WP content (Hello World, Sample Page, Hello Dolly, inactive themes)"),

            // Cleanup & Malware Scan
            MCMAbility(id: "verify-core-integrity", name: "Verify Core Integrity", description: "Verify WP core file integrity against checksums"),
            MCMAbility(id: "scan-content-malware", name: "Scan Content Malware", description: "Scan wp-content for malware patterns"),
            MCMAbility(id: "scan-database-malware", name: "Scan Database Malware", description: "Scan database for injections"),
            MCMAbility(id: "verify-plugins", name: "Verify Plugins", description: "Verify plugins against WP.org checksums"),
            MCMAbility(id: "check-htaccess", name: "Check Htaccess", description: "Analyze .htaccess for malicious rules"),
            MCMAbility(id: "clean-core", name: "Clean Core", description: "Replace core files with clean versions", requiresConfirmation: true),
            MCMAbility(id: "regenerate-salts", name: "Regenerate Salts", description: "Regenerate security salts in wp-config.php", requiresConfirmation: true),
            MCMAbility(id: "generate-cleanup-report", name: "Generate Cleanup Report", description: "Generate comprehensive security cleanup report"),
            MCMAbility(id: "scan-content-dirs", name: "Scan Content Dirs", description: "Scan and classify wp-content directories"),
            MCMAbility(id: "clear-cache", name: "Clear Cache", description: "Empty ALL cache directories (destructive)", requiresConfirmation: true),
            MCMAbility(id: "security-assessment", name: "Security Assessment", description: "Comprehensive security assessment"),
        ]
    )

    // MARK: - wp.seo

    public static let seo = MCMSubConnector(
        id: "wp.seo",
        name: "WP SEO",
        description: "SEO meta, redirects, analytics, content audit, link analysis",
        icon: "chart.line.uptrend.xyaxis",
        abilities: [
            MCMAbility(id: "seo-meta", name: "SEO Meta", description: "Read/write SEO meta for posts and terms. Supports Yoast, Rank Math, AIOSEO, The SEO Framework, SiteSEO, Slim SEO, Squirrly SEO, SureRank", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["get", "set"]),
                MCMParam(name: "object_type", description: "Object type", defaultValue: "post", enumValues: ["post", "term"]),
                MCMParam(name: "post_id", type: "integer", description: "Post ID (for post type)"),
                MCMParam(name: "term_id", type: "integer", description: "Term ID (for term type)"),
                MCMParam(name: "title", description: "SEO title (for set)"),
                MCMParam(name: "description", description: "Meta description (for set)"),
                MCMParam(name: "focus_keyword", description: "Focus keyword (for set)"),
            ]),
            MCMAbility(id: "manage-redirects", name: "Manage Redirects", description: "Manage URL redirects", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["list", "add", "delete"]),
                MCMParam(name: "source", description: "Source URL path (for add)"),
                MCMParam(name: "target", description: "Target URL (for add)"),
                MCMParam(name: "type", type: "integer", description: "Redirect type", defaultValue: "301", enumValues: ["301", "302", "307"]),
            ]),
            MCMAbility(id: "site-stats", name: "Site Stats", description: "Site statistics (auto-detect analytics source)"),
            MCMAbility(id: "content-audit", name: "Content Audit", description: "Content freshness audit", params: [
                MCMParam(name: "post_type", description: "Content type", defaultValue: "post"),
                MCMParam(name: "days_old", type: "integer", description: "Flag content older than N days", defaultValue: "180"),
            ]),
            MCMAbility(id: "analyze-links", name: "Analyze Links", description: "Analyze links for broken/internal opportunities", params: [
                MCMParam(name: "post_id", type: "integer", description: "Analyze specific post"),
                MCMParam(name: "post_type", description: "Content type to scan", defaultValue: "post"),
                MCMParam(name: "per_page", type: "integer", description: "Posts to scan", defaultValue: "20"),
            ]),
        ]
    )

    // MARK: - wp.users

    public static let users = MCMSubConnector(
        id: "wp.users",
        name: "WP Users",
        description: "Users, roles, capabilities, application passwords, GDPR compliance",
        icon: "person.2",
        abilities: [
            // Users
            MCMAbility(id: "list-users", name: "List Users", description: "List WordPress users", params: [
                MCMParam(name: "role", description: "Filter by role"),
                MCMParam(name: "search", description: "Search query"),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "10"),
                MCMParam(name: "orderby", description: "Sort by", defaultValue: "name", enumValues: ["id", "name", "email", "registered_date"]),
            ]),
            MCMAbility(id: "read-user", name: "Read User", description: "View user details", params: [
                MCMParam(name: "id", type: "integer", description: "User ID", required: true),
            ]),
            MCMAbility(id: "create-user", name: "Create User", description: "Create WordPress user", params: [
                MCMParam(name: "username", description: "Username", required: true),
                MCMParam(name: "email", description: "Email address", required: true),
                MCMParam(name: "password", description: "Password", required: true),
                MCMParam(name: "role", description: "User role", defaultValue: "subscriber"),
                MCMParam(name: "first_name", description: "First name"),
                MCMParam(name: "last_name", description: "Last name"),
            ]),
            MCMAbility(id: "update-user", name: "Update User", description: "Update WordPress user", params: [
                MCMParam(name: "id", type: "integer", description: "User ID", required: true),
                MCMParam(name: "email", description: "New email"),
                MCMParam(name: "role", description: "New role"),
                MCMParam(name: "first_name", description: "First name"),
                MCMParam(name: "last_name", description: "Last name"),
            ]),
            MCMAbility(id: "list-user-meta-keys", name: "List User Meta Keys", description: "Discover available user meta fields"),
            MCMAbility(id: "delete-user", name: "Delete User", description: "Delete WordPress user", params: [
                MCMParam(name: "id", type: "integer", description: "User ID", required: true),
                MCMParam(name: "reassign", type: "integer", description: "Reassign content to user ID"),
            ], requiresConfirmation: true),

            // Roles
            MCMAbility(id: "list-roles", name: "List Roles", description: "List all WordPress roles with details (caps, user count)"),
            MCMAbility(id: "get-capabilities-catalog", name: "Capabilities Catalog", description: "Full capability catalog with human descriptions, groups, security levels"),
            MCMAbility(id: "create-role", name: "Create Role", description: "Create custom role with validation", params: [
                MCMParam(name: "role", description: "Role slug", required: true),
                MCMParam(name: "display_name", description: "Display name", required: true),
                MCMParam(name: "capabilities", description: "JSON array of capability names", required: true),
                MCMParam(name: "clone_from", description: "Clone capabilities from existing role"),
            ]),
            MCMAbility(id: "update-role", name: "Update Role", description: "Modify role capabilities (add/remove caps, rename)", params: [
                MCMParam(name: "role", description: "Role slug", required: true),
                MCMParam(name: "add_caps", description: "Capabilities to add (JSON array)"),
                MCMParam(name: "remove_caps", description: "Capabilities to remove (JSON array)"),
                MCMParam(name: "display_name", description: "New display name"),
            ], requiresConfirmation: true),
            MCMAbility(id: "delete-role", name: "Delete Role", description: "Delete custom role with user reassignment", params: [
                MCMParam(name: "role", description: "Role slug", required: true),
                MCMParam(name: "reassign_to", description: "Reassign users to this role", defaultValue: "subscriber"),
            ], requiresConfirmation: true),
            MCMAbility(id: "audit-user-capabilities", name: "Audit User Capabilities", description: "Audit user effective capabilities (role vs individual)", params: [
                MCMParam(name: "user_id", type: "integer", description: "User ID", required: true),
            ]),
            MCMAbility(id: "compare-roles", name: "Compare Roles", description: "Compare capabilities between 2+ roles", params: [
                MCMParam(name: "roles", description: "Comma-separated role slugs", required: true),
            ]),
            MCMAbility(id: "assign-role", name: "Assign Role", description: "Assign role to user (by ID, login, or email)", params: [
                MCMParam(name: "user", description: "User ID, login, or email", required: true),
                MCMParam(name: "role", description: "Role slug", required: true),
            ]),
            MCMAbility(id: "grant-super-admin", name: "Grant Super Admin", description: "Grant Super Admin privileges (Multisite only)", params: [
                MCMParam(name: "user_id", type: "integer", description: "User ID", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "revoke-super-admin", name: "Revoke Super Admin", description: "Revoke Super Admin privileges (Multisite only)", params: [
                MCMParam(name: "user_id", type: "integer", description: "User ID", required: true),
            ], requiresConfirmation: true),

            // App Passwords
            MCMAbility(id: "list-app-passwords", name: "List App Passwords", description: "List application passwords for a user", params: [
                MCMParam(name: "user_id", type: "integer", description: "User ID", required: true),
            ]),
            MCMAbility(id: "create-app-password", name: "Create App Password", description: "Create new application password (shown once only)", params: [
                MCMParam(name: "user_id", type: "integer", description: "User ID", required: true),
                MCMParam(name: "name", description: "Password name/label", required: true),
            ]),
            MCMAbility(id: "revoke-app-password", name: "Revoke App Password", description: "Revoke application password by UUID", params: [
                MCMParam(name: "user_id", type: "integer", description: "User ID", required: true),
                MCMParam(name: "uuid", description: "Password UUID", required: true),
            ], requiresConfirmation: true),

            // GDPR
            MCMAbility(id: "export-user-data", name: "Export User Data", description: "GDPR personal data export request (auto-confirmed)", params: [
                MCMParam(name: "email", description: "User email address", required: true),
            ]),
            MCMAbility(id: "erase-user-data", name: "Erase User Data", description: "GDPR personal data erasure request", params: [
                MCMParam(name: "email", description: "User email address", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "compliance-status", name: "Compliance Status", description: "GDPR compliance overview (privacy policy, consent plugins, pending requests)"),
            MCMAbility(id: "consent-audit", name: "Consent Audit", description: "GDPR request audit trail with pagination", params: [
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "20"),
                MCMParam(name: "page", type: "integer", description: "Page number", defaultValue: "1"),
            ]),
        ]
    )

    // MARK: - wp.database

    public static let database = MCMSubConnector(
        id: "wp.database",
        name: "WP Database",
        description: "Options, transients, database queries, table info, index management",
        icon: "cylinder",
        abilities: [
            // Options
            MCMAbility(id: "get-option", name: "Get Option", description: "Read WordPress option", params: [
                MCMParam(name: "option", description: "Option name", required: true),
            ]),
            MCMAbility(id: "update-option", name: "Update Option", description: "Update WordPress option", params: [
                MCMParam(name: "option", description: "Option name", required: true),
                MCMParam(name: "value", description: "New value", required: true),
                MCMParam(name: "autoload", description: "Autoload setting", enumValues: ["yes", "no"]),
            ]),
            MCMAbility(id: "delete-option", name: "Delete Option", description: "Delete WordPress option", params: [
                MCMParam(name: "option", description: "Option name", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "list-options-by-prefix", name: "List Options by Prefix", description: "List options by prefix", params: [
                MCMParam(name: "prefix", description: "Option name prefix", required: true),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "50"),
            ]),
            MCMAbility(id: "list-registered-settings", name: "List Registered Settings", description: "List registered settings with groups"),

            // DB
            MCMAbility(id: "db-query", name: "DB Query", description: "Execute read-only database queries (SELECT only)", params: [
                MCMParam(name: "query", description: "SQL SELECT query", required: true),
            ]),

            // Transients
            MCMAbility(id: "list-transients", name: "List Transients", description: "List transients with size, expiration, pagination", params: [
                MCMParam(name: "search", description: "Search transient names"),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "20"),
                MCMParam(name: "expired_only", type: "boolean", description: "Show only expired transients", defaultValue: "false"),
            ]),
            MCMAbility(id: "delete-transient", name: "Delete Transient", description: "Delete by name or prefix, expired_only filter", params: [
                MCMParam(name: "name", description: "Transient name (or prefix with wildcard)"),
                MCMParam(name: "prefix", description: "Delete all with this prefix"),
                MCMParam(name: "expired_only", type: "boolean", description: "Only delete expired", defaultValue: "false"),
            ], requiresConfirmation: true),

            // Tables & Indexes
            MCMAbility(id: "db-table-info", name: "DB Table Info", description: "List tables with size, rows, engine, sort options", params: [
                MCMParam(name: "sort", description: "Sort by", defaultValue: "size", enumValues: ["name", "size", "rows", "engine"]),
            ]),
            MCMAbility(id: "db-analyze-indexes", name: "DB Analyze Indexes", description: "Analyze indexes, detect redundant/duplicate", params: [
                MCMParam(name: "table", description: "Specific table name (optional)"),
            ]),
            MCMAbility(id: "db-manage-index", name: "DB Manage Index", description: "Create/drop indexes (ALTER TABLE)", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["create", "drop"]),
                MCMParam(name: "table", description: "Table name", required: true),
                MCMParam(name: "index_name", description: "Index name", required: true),
                MCMParam(name: "columns", description: "Columns (for create, comma-separated)"),
            ], requiresConfirmation: true),
        ]
    )

    // MARK: - wp.navigation

    public static let navigation = MCMSubConnector(
        id: "wp.navigation",
        name: "WP Navigation",
        description: "Classic menus, FSE navigation, sidebars, widgets",
        icon: "list.bullet",
        abilities: [
            // Classic Menus
            MCMAbility(id: "list-menus", name: "List Menus", description: "List classic navigation menus"),
            MCMAbility(id: "update-menu", name: "Update Menu", description: "Update classic navigation menu", params: [
                MCMParam(name: "menu_id", type: "integer", description: "Menu ID", required: true),
                MCMParam(name: "items", description: "JSON array of menu items"),
                MCMParam(name: "name", description: "Menu name"),
            ]),

            // FSE Navigation
            MCMAbility(id: "list-fse-navigations", name: "List FSE Navigations", description: "List FSE navigation menus"),
            MCMAbility(id: "create-fse-navigation", name: "Create FSE Navigation", description: "Create FSE navigation menu", params: [
                MCMParam(name: "title", description: "Navigation title", required: true),
                MCMParam(name: "content", description: "Navigation blocks content", required: true),
            ]),
            MCMAbility(id: "update-fse-navigation", name: "Update FSE Navigation", description: "Update FSE navigation menu", params: [
                MCMParam(name: "id", type: "integer", description: "Navigation post ID", required: true),
                MCMParam(name: "content", description: "Updated blocks content"),
                MCMParam(name: "title", description: "Updated title"),
            ]),

            // Widgets
            MCMAbility(id: "list-sidebars", name: "List Sidebars", description: "List registered sidebar areas with assigned widgets"),
            MCMAbility(id: "list-widget-types", name: "List Widget Types", description: "List available widget types (classic + block)"),
            MCMAbility(id: "manage-widget", name: "Manage Widget", description: "Add, update, move, or delete widgets", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["add", "update", "move", "delete"]),
                MCMParam(name: "sidebar_id", description: "Target sidebar ID"),
                MCMParam(name: "widget_type", description: "Widget type (for add)"),
                MCMParam(name: "widget_id", description: "Widget instance ID (for update/move/delete)"),
                MCMParam(name: "settings", description: "Widget settings (JSON)"),
                MCMParam(name: "position", type: "integer", description: "Position in sidebar"),
            ], requiresConfirmation: true),
        ]
    )

    // MARK: - wp.config

    public static let config = MCMSubConnector(
        id: "wp.config",
        name: "WP Config",
        description: "wp-config.php, .htaccess, permalinks, multisite network",
        icon: "gearshape.2",
        abilities: [
            MCMAbility(id: "wp-config", name: "WP Config", description: "Read/write wp-config.php constants", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["get", "set", "delete", "list"]),
                MCMParam(name: "constant", description: "Constant name (for get/set/delete)"),
                MCMParam(name: "value", description: "Constant value (for set)"),
            ]),
            MCMAbility(id: "manage-htaccess", name: "Manage Htaccess", description: "Read/update/remove .htaccess sections via markers", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["read", "write", "remove"]),
                MCMParam(name: "marker", description: "Section marker name (for write/remove)"),
                MCMParam(name: "content", description: "Section content (for write)"),
            ], requiresConfirmation: true),
            MCMAbility(id: "manage-permalinks", name: "Manage Permalinks", description: "Read/update permalink structure and flush rewrite rules", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["get", "set"]),
                MCMParam(name: "structure", description: "Permalink structure (for set, e.g. '/%postname%/')"),
            ], requiresConfirmation: true),

            // Multisite
            MCMAbility(id: "multisite-info", name: "Multisite Info", description: "Detect multisite, list network sites with domain/path/status"),
            MCMAbility(id: "manage-network-site", name: "Manage Network Site", description: "Create/activate/deactivate/archive/spam/delete network sites", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["create", "activate", "deactivate", "archive", "spam", "delete"]),
                MCMParam(name: "blog_id", type: "integer", description: "Site ID (for actions on existing sites)"),
                MCMParam(name: "domain", description: "Domain (for create)"),
                MCMParam(name: "path", description: "Path (for create)"),
                MCMParam(name: "title", description: "Site title (for create)"),
            ], requiresConfirmation: true),
            MCMAbility(id: "switch-to-blog", name: "Switch to Blog", description: "Execute any ability in another site's context", params: [
                MCMParam(name: "blog_id", type: "integer", description: "Target site ID", required: true),
                MCMParam(name: "ability", description: "Ability ID to execute", required: true),
                MCMParam(name: "params", description: "Ability parameters (JSON)"),
            ]),
            MCMAbility(id: "network-plugins", name: "Network Plugins", description: "List/activate/deactivate network-wide plugins", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["list", "activate", "deactivate"]),
                MCMParam(name: "plugin", description: "Plugin slug (for activate/deactivate)"),
            ], requiresConfirmation: true),
            MCMAbility(id: "network-themes", name: "Network Themes", description: "List/enable/disable network-wide themes", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["list", "enable", "disable"]),
                MCMParam(name: "theme", description: "Theme slug (for enable/disable)"),
            ], requiresConfirmation: true),
        ]
    )

    // MARK: - wp.automation

    public static let automation = MCMSubConnector(
        id: "wp.automation",
        name: "WP Automation",
        description: "Batch execution, action log, unified search",
        icon: "gearshape.arrow.triangle.2.circlepath",
        abilities: [
            MCMAbility(id: "batch-execute", name: "Batch Execute", description: "Execute multiple abilities in sequence with {{step_N.exports.key}} references", params: [
                MCMParam(name: "steps", description: "JSON array of {ability, params} steps", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "list-action-log", name: "List Action Log", description: "Query structured action log (filter, stats, cleanup)", params: [
                MCMParam(name: "action", description: "Action", defaultValue: "list", enumValues: ["list", "stats", "cleanup"]),
                MCMParam(name: "ability", description: "Filter by ability ID"),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "20"),
            ], requiresConfirmation: true),
            MCMAbility(id: "search-everything", name: "Search Everything", description: "Unified search across posts, pages, products, orders, users, options, terms with suggested actions", params: [
                MCMParam(name: "query", description: "Search query", required: true),
                MCMParam(name: "types", description: "Limit to specific types (comma-separated)"),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "10"),
            ]),
        ]
    )

    // MARK: - wp.themes

    public static let themes = MCMSubConnector(
        id: "wp.themes",
        name: "WP Themes",
        description: "Global styles, templates, template parts, fonts, FSE design control, theme inspector tasks",
        icon: "paintbrush",
        abilities: [
            // Theme Config
            MCMAbility(id: "get-global-styles", name: "Get Global Styles", description: "Read Global Styles (block themes)", params: [
                MCMParam(name: "section", description: "Section filter (color, typography, spacing, all)", defaultValue: "all"),
            ]),
            MCMAbility(id: "set-global-styles", name: "Set Global Styles", description: "Update Global Styles", params: [
                MCMParam(name: "styles", description: "JSON styles object to merge", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "reset-global-styles", name: "Reset Global Styles", description: "Reset Global Styles to theme defaults", requiresConfirmation: true),
            MCMAbility(id: "get-theme-options", name: "Get Theme Options", description: "Read classic theme options (Avada, The7, etc.)", params: [
                MCMParam(name: "option", description: "Specific option key (or omit for all)"),
            ]),
            MCMAbility(id: "set-theme-options", name: "Set Theme Options", description: "Update classic theme options", params: [
                MCMParam(name: "options", description: "JSON object of option_key: value pairs", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "theme-config-guide", name: "Theme Config Guide", description: "Theme-specific configuration guide"),

            // Theme Mods
            MCMAbility(id: "get-theme-mod", name: "Get Theme Mod", description: "Read theme modification", params: [
                MCMParam(name: "name", description: "Mod name", required: true),
            ]),
            MCMAbility(id: "set-theme-mod", name: "Set Theme Mod", description: "Set theme modification", params: [
                MCMParam(name: "name", description: "Mod name", required: true),
                MCMParam(name: "value", description: "Mod value", required: true),
            ]),

            // Theme FSE Control
            MCMAbility(id: "theme-get-compatibility", name: "Theme Compatibility", description: "Detect _mcm tag in theme.json, theme type, capabilities"),
            MCMAbility(id: "theme-get-style-variations", name: "Get Style Variations", description: "List style variations with palette/font previews"),
            MCMAbility(id: "theme-apply-style-variation", name: "Apply Style Variation", description: "Switch between theme style variations", params: [
                MCMParam(name: "variation", description: "Variation name or slug", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "theme-get-pattern-library", name: "Get Pattern Library", description: "List block patterns by category/source", params: [
                MCMParam(name: "category", description: "Pattern category filter"),
                MCMParam(name: "source", description: "Source filter (theme, plugin, core)"),
            ]),
            MCMAbility(id: "theme-insert-pattern", name: "Insert Pattern", description: "Insert pattern into page/template", params: [
                MCMParam(name: "pattern_name", description: "Pattern name", required: true),
                MCMParam(name: "target_id", type: "integer", description: "Target post/template ID", required: true),
                MCMParam(name: "position", description: "Insert position", defaultValue: "append", enumValues: ["append", "prepend", "replace"]),
            ], requiresConfirmation: true),
            MCMAbility(id: "theme-reorder-blocks", name: "Reorder Blocks", description: "Reorder top-level blocks in page/template", params: [
                MCMParam(name: "post_id", type: "integer", description: "Post or template ID", required: true),
                MCMParam(name: "order", description: "JSON array of block indices in new order", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "theme-update-color-token", name: "Update Color Token", description: "Change color token globally (e.g. primary→#FF0000)", params: [
                MCMParam(name: "token", description: "Color token name (e.g. primary, secondary, base)", required: true),
                MCMParam(name: "value", description: "New color value (hex)", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "theme-update-typography", name: "Update Typography", description: "Update font family/size globally", params: [
                MCMParam(name: "element", description: "Target element", required: true, enumValues: ["body", "heading", "button", "caption"]),
                MCMParam(name: "fontFamily", description: "Font family name"),
                MCMParam(name: "fontSize", description: "Font size (e.g. '16px', '1rem')"),
            ], requiresConfirmation: true),
            MCMAbility(id: "theme-update-spacing", name: "Update Spacing", description: "Update spacing scale/gap/padding/margin globally", params: [
                MCMParam(name: "property", description: "Spacing property", required: true, enumValues: ["blockGap", "padding", "margin", "scale"]),
                MCMParam(name: "value", description: "Spacing value or scale config", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "theme-update-block-style", name: "Update Block Style", description: "Update block type styles globally (e.g. all buttons)", params: [
                MCMParam(name: "blockName", description: "Block type (e.g. core/button, core/heading)", required: true),
                MCMParam(name: "styles", description: "JSON styles object", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "theme-get-computed-styles", name: "Get Computed Styles", description: "Read merged styles/settings/supports for a block type", params: [
                MCMParam(name: "blockName", description: "Block type name", required: true),
            ]),

            // Theme Inspector Tasks
            MCMAbility(id: "task-create", name: "Create Task", description: "Create theme task from Inspector or agent", params: [
                MCMParam(name: "human_intent", description: "Task description", required: true),
                MCMParam(name: "selector", description: "CSS selector"),
                MCMParam(name: "viewport", description: "Viewport", enumValues: ["desktop", "tablet", "mobile"]),
                MCMParam(name: "priority", type: "integer", description: "Priority (1=urgent to 10=low)", defaultValue: "5"),
                MCMParam(name: "page_url", description: "Page URL for context"),
            ]),
            MCMAbility(id: "task-list", name: "List Tasks", description: "List tasks with filters", params: [
                MCMParam(name: "status", description: "Status filter", enumValues: ["pending", "in_progress", "done", "dismissed"]),
                MCMParam(name: "viewport", description: "Viewport filter"),
                MCMParam(name: "page_url", description: "Page URL filter"),
                MCMParam(name: "priority_max", type: "integer", description: "Max priority (lower = more urgent)"),
            ]),
            MCMAbility(id: "task-get", name: "Get Task", description: "Full task detail (current_styles, screenshot_b64, result)", params: [
                MCMParam(name: "task_id", type: "integer", description: "Task ID", required: true),
            ]),
            MCMAbility(id: "task-execute", name: "Execute Task", description: "Mark in_progress, return full context for AI execution", params: [
                MCMParam(name: "task_id", type: "integer", description: "Task ID", required: true),
            ]),
            MCMAbility(id: "task-mark-done", name: "Mark Task Done", description: "Mark completed with result description", params: [
                MCMParam(name: "task_id", type: "integer", description: "Task ID", required: true),
                MCMParam(name: "result", description: "Result description", required: true),
            ]),
            MCMAbility(id: "task-dismiss", name: "Dismiss Task", description: "Dismiss task (status→dismissed)", params: [
                MCMParam(name: "task_id", type: "integer", description: "Task ID", required: true),
            ]),
            MCMAbility(id: "task-batch-execute", name: "Batch Execute Tasks", description: "Batch mark in_progress, return all contexts", params: [
                MCMParam(name: "task_ids", description: "Comma-separated task IDs", required: true),
            ]),
            MCMAbility(id: "task-schedule", name: "Schedule Task", description: "Schedule task via Action Scheduler for deferred execution", params: [
                MCMParam(name: "task_id", type: "integer", description: "Task ID", required: true),
                MCMParam(name: "delay_minutes", type: "integer", description: "Delay in minutes", defaultValue: "5"),
            ]),
            MCMAbility(id: "task-update-priority", name: "Update Task Priority", description: "Change priority (1=urgent to 10=low)", params: [
                MCMParam(name: "task_id", type: "integer", description: "Task ID", required: true),
                MCMParam(name: "priority", type: "integer", description: "New priority (1-10)", required: true),
            ]),

            // Templates
            MCMAbility(id: "list-templates", name: "List Templates", description: "List block templates (index, single, archive, etc.)", params: [
                MCMParam(name: "type", description: "Template type filter"),
            ]),
            MCMAbility(id: "read-template", name: "Read Template", description: "Read template content with parsed blocks", params: [
                MCMParam(name: "id", description: "Template ID (e.g. theme-slug//index)", required: true),
            ]),
            MCMAbility(id: "update-template", name: "Update Template", description: "Modify template content (creates DB override for theme templates)", params: [
                MCMParam(name: "id", description: "Template ID", required: true),
                MCMParam(name: "content", description: "New template content (blocks)", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "reset-template", name: "Reset Template", description: "Restore template to theme version", params: [
                MCMParam(name: "id", description: "Template ID", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "list-template-parts", name: "List Template Parts", description: "List template parts (header, footer, sidebar)"),
            MCMAbility(id: "manage-template-part", name: "Manage Template Part", description: "Create/update/delete template parts", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["create", "update", "delete"]),
                MCMParam(name: "id", description: "Template part ID (for update/delete)"),
                MCMParam(name: "slug", description: "Slug (for create)"),
                MCMParam(name: "area", description: "Area", enumValues: ["header", "footer", "sidebar", "uncategorized"]),
                MCMParam(name: "content", description: "Content (blocks)"),
            ], requiresConfirmation: true),

            // Fonts
            MCMAbility(id: "list-fonts", name: "List Fonts", description: "List installed font families with variants (WP 6.5+)"),
            MCMAbility(id: "install-font", name: "Install Font", description: "Install font family with font face variants", params: [
                MCMParam(name: "family", description: "Font family name", required: true),
                MCMParam(name: "source", description: "Font source (google, upload)", required: true, enumValues: ["google", "upload"]),
                MCMParam(name: "variants", description: "JSON array of font face variants"),
            ]),
            MCMAbility(id: "remove-font", name: "Remove Font", description: "Remove font family, faces, and files", params: [
                MCMParam(name: "family", description: "Font family name or ID", required: true),
            ], requiresConfirmation: true),
        ]
    )

    // MARK: - wp.system

    public static let system = MCMSubConnector(
        id: "wp.system",
        name: "WP System",
        description: "Site health, file ops, plugins, updates, snapshots, maintenance, cache, WP-CLI, profiler, optimizer",
        icon: "server.rack",
        abilities: [
            // Recovery & Files
            MCMAbility(id: "sentinel-info", name: "Sentinel Info", description: "Emergency sentinel endpoint info"),
            MCMAbility(id: "site-health", name: "Site Health", description: "Site health status (fatal errors, paused plugins, memory, disk)"),
            MCMAbility(id: "read-file", name: "Read File", description: "Read any site file", params: [
                MCMParam(name: "path", description: "File path relative to WP root", required: true),
            ]),
            MCMAbility(id: "list-directory", name: "List Directory", description: "List directory contents", params: [
                MCMParam(name: "path", description: "Directory path relative to WP root", required: true),
                MCMParam(name: "recursive", type: "boolean", description: "List recursively", defaultValue: "false"),
            ]),
            MCMAbility(id: "write-file", name: "Write File", description: "Write site file (auto-backup before write)", params: [
                MCMParam(name: "path", description: "File path", required: true),
                MCMParam(name: "content", description: "File content", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "replace-in-file", name: "Replace in File", description: "Search and replace in a file", params: [
                MCMParam(name: "path", description: "File path", required: true),
                MCMParam(name: "search", description: "Search string", required: true),
                MCMParam(name: "replace", description: "Replacement string", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "list-plugins", name: "List Plugins", description: "List all plugins (active/inactive)"),
            MCMAbility(id: "toggle-plugin", name: "Toggle Plugin", description: "Activate or deactivate a plugin", params: [
                MCMParam(name: "plugin", description: "Plugin slug or file", required: true),
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["activate", "deactivate"]),
            ]),
            MCMAbility(id: "error-log", name: "Error Log", description: "Read PHP error log (last N lines)", params: [
                MCMParam(name: "lines", type: "integer", description: "Number of lines", defaultValue: "50"),
            ]),
            MCMAbility(id: "list-backups", name: "List Backups", description: "List file backups created by write-file"),
            MCMAbility(id: "restore-backup", name: "Restore Backup", description: "Restore file from backup", params: [
                MCMParam(name: "backup_id", description: "Backup identifier", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "delete-maintenance", name: "Delete Maintenance", description: "Delete stuck .maintenance file"),
            MCMAbility(id: "clear-recovery", name: "Clear Recovery", description: "Clear WP recovery mode"),

            // Updates
            MCMAbility(id: "list-updates", name: "List Updates", description: "List available updates (core/plugins/themes/translations)"),
            MCMAbility(id: "run-update", name: "Run Update", description: "Execute an update (plugin/theme/core)", params: [
                MCMParam(name: "type", description: "Update type", required: true, enumValues: ["plugin", "theme", "core", "translation"]),
                MCMParam(name: "slug", description: "Plugin/theme slug (for plugin/theme type)", required: true),
            ], requiresConfirmation: true),

            // Time Machine
            MCMAbility(id: "list-snapshots", name: "List Snapshots", description: "List ZIP snapshots"),
            MCMAbility(id: "create-snapshot", name: "Create Snapshot", description: "Create ZIP snapshot of plugin/theme", params: [
                MCMParam(name: "type", description: "Item type", required: true, enumValues: ["plugin", "theme"]),
                MCMParam(name: "slug", description: "Plugin/theme slug", required: true),
            ]),
            MCMAbility(id: "restore-snapshot", name: "Restore Snapshot", description: "Restore from snapshot (auto-creates safety snapshot)", params: [
                MCMParam(name: "snapshot_id", description: "Snapshot identifier", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "delete-snapshot", name: "Delete Snapshot", description: "Delete a snapshot", params: [
                MCMParam(name: "snapshot_id", description: "Snapshot identifier", required: true),
            ]),

            // Maintenance
            MCMAbility(id: "list-cron-events", name: "List Cron Events", description: "List WordPress cron events"),
            MCMAbility(id: "run-cron-event", name: "Run Cron Event", description: "Run cron event manually", params: [
                MCMParam(name: "hook", description: "Cron hook name", required: true),
            ]),
            MCMAbility(id: "unschedule-cron", name: "Unschedule Cron", description: "Unschedule a cron event", params: [
                MCMParam(name: "hook", description: "Cron hook name", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "flush-cache", name: "Flush Cache", description: "Flush cache and transients (safe)"),
            MCMAbility(id: "clean-scheduled-actions", name: "Clean Scheduled Actions", description: "Clean Action Scheduler entries"),
            MCMAbility(id: "optimize-db", name: "Optimize DB", description: "Database cleanup and optimization"),

            // System
            MCMAbility(id: "system-info", name: "System Info", description: "Comprehensive server diagnostics"),
            MCMAbility(id: "toggle-debug", name: "Toggle Debug", description: "Toggle WP debug mode", params: [
                MCMParam(name: "enabled", type: "boolean", description: "Enable or disable debug", required: true),
            ]),

            // Cache
            MCMAbility(id: "cache-status", name: "Cache Status", description: "Detect cache plugin, object cache, page cache status"),
            MCMAbility(id: "cache-purge", name: "Cache Purge", description: "Purge page/object/transient cache (auto-detects plugin)", params: [
                MCMParam(name: "type", description: "Cache type to purge", defaultValue: "all", enumValues: ["all", "page", "object", "transient"]),
            ], requiresConfirmation: true),
            MCMAbility(id: "cache-warm", name: "Cache Warm", description: "Pre-warm cache by crawling homepage, menus, posts, pages"),
            MCMAbility(id: "cache-config", name: "Cache Config", description: "Read active cache plugin configuration (read-only)"),

            // Installation
            MCMAbility(id: "install-plugin", name: "Install Plugin", description: "Install plugin from WP.org or ZIP URL", params: [
                MCMParam(name: "slug", description: "Plugin slug on WP.org or ZIP URL", required: true),
                MCMParam(name: "activate", type: "boolean", description: "Activate after install", defaultValue: "true"),
            ]),
            MCMAbility(id: "install-theme", name: "Install Theme", description: "Install theme from WP.org or ZIP URL", params: [
                MCMParam(name: "slug", description: "Theme slug or ZIP URL", required: true),
                MCMParam(name: "activate", type: "boolean", description: "Activate after install", defaultValue: "false"),
            ]),
            MCMAbility(id: "install-plugins-from-folder", name: "Install from Folder", description: "Install plugins from Dropbox folder", params: [
                MCMParam(name: "folder_url", description: "Dropbox folder URL", required: true),
            ]),

            // WP-CLI
            MCMAbility(id: "check-wpcli", name: "Check WP-CLI", description: "Check WP-CLI availability"),
            MCMAbility(id: "list-wpcli-commands", name: "List WP-CLI Commands", description: "List available WP-CLI commands"),
            MCMAbility(id: "execute-wpcli", name: "Execute WP-CLI", description: "Execute WP-CLI command", params: [
                MCMParam(name: "command", description: "WP-CLI command to execute", required: true),
            ], requiresConfirmation: true),

            // Profiler
            MCMAbility(id: "profile-start", name: "Profile Start", description: "Start profiling session", params: [
                MCMParam(name: "label", description: "Session label"),
            ]),
            MCMAbility(id: "profile-page", name: "Profile Page", description: "Profile a page automatically", params: [
                MCMParam(name: "url", description: "Page URL to profile", required: true),
            ]),
            MCMAbility(id: "profile-results", name: "Profile Results", description: "Get profiling results", params: [
                MCMParam(name: "session_id", description: "Session ID"),
            ]),
            MCMAbility(id: "profile-compare", name: "Profile Compare", description: "Compare two profiling sessions", params: [
                MCMParam(name: "session_a", description: "First session ID", required: true),
                MCMParam(name: "session_b", description: "Second session ID", required: true),
            ]),
            MCMAbility(id: "profile-cleanup", name: "Profile Cleanup", description: "Clean up profiler data"),

            // Optimizer
            MCMAbility(id: "optimize-list", name: "Optimize List", description: "List available optimizations"),
            MCMAbility(id: "optimize-apply", name: "Optimize Apply", description: "Apply performance optimizations", params: [
                MCMParam(name: "optimization_id", description: "Optimization ID", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "optimize-rollback", name: "Optimize Rollback", description: "Rollback optimization", params: [
                MCMParam(name: "optimization_id", description: "Optimization ID", required: true),
            ]),
            MCMAbility(id: "optimize-status", name: "Optimize Status", description: "Current optimization status"),
            MCMAbility(id: "optimize-assets", name: "Optimize Assets", description: "Optimize CSS/JS assets", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["analyze", "optimize", "restore"]),
            ], requiresConfirmation: true),

            // Guidelines
            MCMAbility(id: "coding-guidelines", name: "Coding Guidelines", description: "Fetch WordPress coding guidelines by context", params: [
                MCMParam(name: "context", description: "Context topic", defaultValue: "all", enumValues: ["all", "plugin", "block", "theme", "rest-api", "security", "site-update"]),
                MCMParam(name: "include_references", type: "boolean", description: "Include references", defaultValue: "false"),
            ]),
            MCMAbility(id: "gutenberg-reference", name: "Gutenberg Reference", description: "Gutenberg block reference", params: [
                MCMParam(name: "block", description: "Block name (e.g. core/paragraph)"),
            ]),
            MCMAbility(id: "site-creation-guide", name: "Site Creation Guide", description: "Complete site creation guide (14 phases)"),
            MCMAbility(id: "maintenance-runbook", name: "Maintenance Runbook", description: "Step-by-step maintenance procedure"),
        ]
    )

    // MARK: - wp.woocommerce

    public static let woocommerce = MCMSubConnector(
        id: "wp.woocommerce",
        name: "WP WooCommerce",
        description: "Products, orders, customers, coupons, analytics, attributes, webhooks, settings, shipping, subscriptions",
        icon: "cart",
        abilities: [
            // Products
            MCMAbility(id: "wc-list-products", name: "List Products", description: "List WooCommerce products", params: [
                MCMParam(name: "status", description: "Status filter", defaultValue: "publish", enumValues: ["publish", "draft", "pending", "private", "trash"]),
                MCMParam(name: "type", description: "Product type", enumValues: ["simple", "variable", "grouped", "external"]),
                MCMParam(name: "category", description: "Category slug or ID"),
                MCMParam(name: "search", description: "Search query"),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "10"),
                MCMParam(name: "page", type: "integer", description: "Page number", defaultValue: "1"),
                MCMParam(name: "orderby", description: "Sort by", defaultValue: "date", enumValues: ["date", "title", "price", "popularity", "rating"]),
                MCMParam(name: "order", description: "Sort direction", defaultValue: "desc", enumValues: ["asc", "desc"]),
                MCMParam(name: "stock_status", description: "Stock filter", enumValues: ["instock", "outofstock", "onbackorder"]),
            ]),
            MCMAbility(id: "wc-read-product", name: "Read Product", description: "Read product details", params: [
                MCMParam(name: "id", type: "integer", description: "Product ID", required: true),
            ]),
            MCMAbility(id: "wc-create-product", name: "Create Product", description: "Create WooCommerce product", params: [
                MCMParam(name: "name", description: "Product name", required: true),
                MCMParam(name: "type", description: "Product type", defaultValue: "simple", enumValues: ["simple", "variable", "grouped", "external"]),
                MCMParam(name: "regular_price", description: "Regular price", required: true),
                MCMParam(name: "sale_price", description: "Sale price"),
                MCMParam(name: "description", description: "Product description"),
                MCMParam(name: "short_description", description: "Short description"),
                MCMParam(name: "sku", description: "SKU"),
                MCMParam(name: "status", description: "Status", defaultValue: "draft"),
                MCMParam(name: "categories", description: "Category IDs (JSON array)"),
                MCMParam(name: "manage_stock", type: "boolean", description: "Enable stock management", defaultValue: "false"),
                MCMParam(name: "stock_quantity", type: "integer", description: "Stock quantity"),
            ]),
            MCMAbility(id: "wc-update-product", name: "Update Product", description: "Update WooCommerce product", params: [
                MCMParam(name: "id", type: "integer", description: "Product ID", required: true),
                MCMParam(name: "name", description: "Product name"),
                MCMParam(name: "regular_price", description: "Regular price"),
                MCMParam(name: "sale_price", description: "Sale price"),
                MCMParam(name: "description", description: "Description"),
                MCMParam(name: "status", description: "Status"),
                MCMParam(name: "stock_quantity", type: "integer", description: "Stock quantity"),
            ]),
            MCMAbility(id: "wc-delete-product", name: "Delete Product", description: "Delete product", params: [
                MCMParam(name: "id", type: "integer", description: "Product ID", required: true),
                MCMParam(name: "force", type: "boolean", description: "Permanently delete", defaultValue: "false"),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-manage-variations", name: "Manage Variations", description: "Manage product variations", params: [
                MCMParam(name: "product_id", type: "integer", description: "Parent product ID", required: true),
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["list", "create", "update", "delete"]),
                MCMParam(name: "variation_id", type: "integer", description: "Variation ID (for update/delete)"),
                MCMParam(name: "attributes", description: "Variation attributes (JSON)"),
                MCMParam(name: "regular_price", description: "Price"),
                MCMParam(name: "stock_quantity", type: "integer", description: "Stock"),
            ]),
            MCMAbility(id: "wc-inventory-report", name: "Inventory Report", description: "Inventory report with stock levels"),

            // Products Extended
            MCMAbility(id: "wc-import-products", name: "Import Products", description: "Import products from CSV file", params: [
                MCMParam(name: "file", description: "CSV file path on server", required: true),
                MCMParam(name: "update_existing", type: "boolean", description: "Update existing products by SKU", defaultValue: "false"),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-export-products", name: "Export Products", description: "Export products to CSV", params: [
                MCMParam(name: "type", description: "Product type filter"),
                MCMParam(name: "category", description: "Category filter"),
                MCMParam(name: "status", description: "Status filter"),
            ]),
            MCMAbility(id: "wc-bulk-update-products", name: "Bulk Update Products", description: "Bulk update price/stock/status/category", params: [
                MCMParam(name: "product_ids", description: "Comma-separated product IDs", required: true),
                MCMParam(name: "action", description: "Bulk action", required: true, enumValues: ["update_price", "update_stock", "update_status", "update_category"]),
                MCMParam(name: "value", description: "New value", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-duplicate-product", name: "Duplicate Product", description: "Duplicate product with variations, meta, images", params: [
                MCMParam(name: "id", type: "integer", description: "Source product ID", required: true),
                MCMParam(name: "status", description: "Status for duplicate", defaultValue: "draft"),
            ]),
            MCMAbility(id: "wc-manage-downloadable-files", name: "Manage Downloads", description: "List/add/remove downloadable files and set limits", params: [
                MCMParam(name: "product_id", type: "integer", description: "Product ID", required: true),
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["list", "add", "remove"]),
                MCMParam(name: "file_url", description: "File URL (for add)"),
                MCMParam(name: "file_name", description: "File display name (for add)"),
            ]),

            // Attributes
            MCMAbility(id: "wc-list-attributes", name: "List Attributes", description: "List global product attributes (Color, Size, etc.)"),
            MCMAbility(id: "wc-manage-attribute", name: "Manage Attribute", description: "Create/update/delete global attributes", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["create", "update", "delete"]),
                MCMParam(name: "attribute_id", type: "integer", description: "Attribute ID (for update/delete)"),
                MCMParam(name: "name", description: "Attribute name (for create/update)"),
                MCMParam(name: "slug", description: "Attribute slug"),
                MCMParam(name: "type", description: "Attribute type", defaultValue: "select", enumValues: ["select", "text"]),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-list-attribute-terms", name: "List Attribute Terms", description: "List terms of an attribute (Red, Blue for Color)", params: [
                MCMParam(name: "attribute_id", type: "integer", description: "Attribute ID", required: true),
            ]),
            MCMAbility(id: "wc-manage-attribute-term", name: "Manage Attribute Term", description: "Create/update/delete attribute terms", params: [
                MCMParam(name: "attribute_id", type: "integer", description: "Attribute ID", required: true),
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["create", "update", "delete"]),
                MCMParam(name: "term_id", type: "integer", description: "Term ID (for update/delete)"),
                MCMParam(name: "name", description: "Term name (for create/update)"),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-list-shipping-classes", name: "List Shipping Classes", description: "List shipping classes (standard, fragile, refrigerated)"),
            MCMAbility(id: "wc-manage-shipping-class", name: "Manage Shipping Class", description: "Create/update/delete shipping classes", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["create", "update", "delete"]),
                MCMParam(name: "class_id", type: "integer", description: "Class ID (for update/delete)"),
                MCMParam(name: "name", description: "Class name"),
                MCMParam(name: "slug", description: "Class slug"),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-list-brands", name: "List Brands", description: "List product brands (requires brand plugin)"),
            MCMAbility(id: "wc-manage-brand", name: "Manage Brand", description: "Create/update/delete brands", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["create", "update", "delete"]),
                MCMParam(name: "brand_id", type: "integer", description: "Brand ID (for update/delete)"),
                MCMParam(name: "name", description: "Brand name"),
            ], requiresConfirmation: true),

            // Orders
            MCMAbility(id: "wc-list-orders", name: "List Orders", description: "List WooCommerce orders", params: [
                MCMParam(name: "status", description: "Status filter", enumValues: ["pending", "processing", "on-hold", "completed", "cancelled", "refunded", "failed"]),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "10"),
                MCMParam(name: "page", type: "integer", description: "Page number", defaultValue: "1"),
                MCMParam(name: "search", description: "Search query"),
                MCMParam(name: "customer", type: "integer", description: "Customer ID filter"),
                MCMParam(name: "after", description: "Orders after date (ISO 8601)"),
                MCMParam(name: "before", description: "Orders before date (ISO 8601)"),
            ]),
            MCMAbility(id: "wc-read-order", name: "Read Order", description: "Read order details", params: [
                MCMParam(name: "id", type: "integer", description: "Order ID", required: true),
            ]),
            MCMAbility(id: "wc-create-order", name: "Create Order", description: "Create WooCommerce order", params: [
                MCMParam(name: "customer_id", type: "integer", description: "Customer ID"),
                MCMParam(name: "line_items", description: "JSON array of line items", required: true),
                MCMParam(name: "status", description: "Order status", defaultValue: "pending"),
                MCMParam(name: "billing", description: "Billing address (JSON)"),
                MCMParam(name: "shipping", description: "Shipping address (JSON)"),
                MCMParam(name: "payment_method", description: "Payment method"),
            ]),
            MCMAbility(id: "wc-manage-order", name: "Manage Order", description: "Manage order (status, notes, refunds)", params: [
                MCMParam(name: "id", type: "integer", description: "Order ID", required: true),
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["update_status", "add_note", "refund"]),
                MCMParam(name: "status", description: "New status (for update_status)"),
                MCMParam(name: "note", description: "Note text (for add_note)"),
                MCMParam(name: "amount", description: "Refund amount (for refund)"),
                MCMParam(name: "reason", description: "Refund reason (for refund)"),
            ]),
            MCMAbility(id: "wc-list-refunds", name: "List Refunds", description: "List refunds globally or per order", params: [
                MCMParam(name: "order_id", type: "integer", description: "Order ID (optional, omit for all)"),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "10"),
            ]),
            MCMAbility(id: "wc-delete-order", name: "Delete Order", description: "Trash or permanently delete order", params: [
                MCMParam(name: "id", type: "integer", description: "Order ID", required: true),
                MCMParam(name: "force", type: "boolean", description: "Permanently delete", defaultValue: "false"),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-bulk-update-orders", name: "Bulk Update Orders", description: "Bulk status change (max 100)", params: [
                MCMParam(name: "order_ids", description: "Comma-separated order IDs", required: true),
                MCMParam(name: "status", description: "New status", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-fulfillments", name: "Fulfillments", description: "Tracking management + partial fulfillment", params: [
                MCMParam(name: "order_id", type: "integer", description: "Order ID", required: true),
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["list", "add", "update", "complete"]),
                MCMParam(name: "tracking_number", description: "Tracking number (for add)"),
                MCMParam(name: "provider", description: "Shipping provider (for add)"),
                MCMParam(name: "items", description: "Line item IDs for partial fulfillment (JSON)"),
            ]),

            // Customers
            MCMAbility(id: "wc-list-customers", name: "List Customers", description: "List WooCommerce customers", params: [
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "10"),
                MCMParam(name: "search", description: "Search query"),
                MCMParam(name: "role", description: "Role filter", defaultValue: "customer"),
                MCMParam(name: "orderby", description: "Sort by", defaultValue: "registered_date"),
            ]),
            MCMAbility(id: "wc-read-customer", name: "Read Customer", description: "Read customer details", params: [
                MCMParam(name: "id", type: "integer", description: "Customer ID", required: true),
            ]),
            MCMAbility(id: "wc-create-customer", name: "Create Customer", description: "Create WooCommerce customer", params: [
                MCMParam(name: "email", description: "Email address", required: true),
                MCMParam(name: "first_name", description: "First name"),
                MCMParam(name: "last_name", description: "Last name"),
                MCMParam(name: "username", description: "Username"),
                MCMParam(name: "billing", description: "Billing address (JSON)"),
                MCMParam(name: "shipping", description: "Shipping address (JSON)"),
            ]),
            MCMAbility(id: "wc-update-customer", name: "Update Customer", description: "Update WooCommerce customer", params: [
                MCMParam(name: "id", type: "integer", description: "Customer ID", required: true),
                MCMParam(name: "email", description: "Email"),
                MCMParam(name: "first_name", description: "First name"),
                MCMParam(name: "last_name", description: "Last name"),
                MCMParam(name: "billing", description: "Billing address (JSON)"),
            ]),
            MCMAbility(id: "wc-delete-customer", name: "Delete Customer", description: "Delete customer with optional content reassignment", params: [
                MCMParam(name: "id", type: "integer", description: "Customer ID", required: true),
                MCMParam(name: "reassign", type: "integer", description: "Reassign orders to user ID"),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-customer-downloads", name: "Customer Downloads", description: "List download permissions and history", params: [
                MCMParam(name: "customer_id", type: "integer", description: "Customer ID", required: true),
            ]),

            // Analytics
            MCMAbility(id: "wc-sales-report", name: "Sales Report", description: "Sales report", params: [
                MCMParam(name: "period", description: "Report period", defaultValue: "month", enumValues: ["week", "month", "last_month", "year"]),
                MCMParam(name: "date_min", description: "Start date (YYYY-MM-DD)"),
                MCMParam(name: "date_max", description: "End date (YYYY-MM-DD)"),
            ]),
            MCMAbility(id: "wc-top-sellers", name: "Top Sellers", description: "Top selling products", params: [
                MCMParam(name: "period", description: "Period", defaultValue: "month"),
                MCMParam(name: "limit", type: "integer", description: "Max results", defaultValue: "10"),
            ]),
            MCMAbility(id: "wc-list-coupons", name: "List Coupons", description: "List WooCommerce coupons", params: [
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "10"),
                MCMParam(name: "search", description: "Search query"),
            ]),
            MCMAbility(id: "wc-create-coupon", name: "Create Coupon", description: "Create WooCommerce coupon", params: [
                MCMParam(name: "code", description: "Coupon code", required: true),
                MCMParam(name: "discount_type", description: "Discount type", required: true, enumValues: ["percent", "fixed_cart", "fixed_product"]),
                MCMParam(name: "amount", description: "Discount amount", required: true),
                MCMParam(name: "expiry_date", description: "Expiry date (YYYY-MM-DD)"),
                MCMParam(name: "usage_limit", type: "integer", description: "Usage limit"),
                MCMParam(name: "individual_use", type: "boolean", description: "Individual use only", defaultValue: "false"),
            ]),
            MCMAbility(id: "wc-update-coupon", name: "Update Coupon", description: "Update WooCommerce coupon", params: [
                MCMParam(name: "id", type: "integer", description: "Coupon ID", required: true),
                MCMParam(name: "amount", description: "New amount"),
                MCMParam(name: "expiry_date", description: "New expiry date"),
                MCMParam(name: "usage_limit", type: "integer", description: "New usage limit"),
            ]),
            MCMAbility(id: "wc-tax-rates", name: "Tax Rates", description: "List tax rates"),

            // Analytics Extended
            MCMAbility(id: "wc-revenue-stats", name: "Revenue Stats", description: "Revenue breakdown (gross, net, refunds, tax, shipping, discounts)", params: [
                MCMParam(name: "period", description: "Period", defaultValue: "month"),
                MCMParam(name: "compare", description: "Compare with previous period", defaultValue: "previous_period", enumValues: ["previous_period", "previous_year"]),
            ]),
            MCMAbility(id: "wc-category-report", name: "Category Report", description: "Sales by product category", params: [
                MCMParam(name: "period", description: "Period", defaultValue: "month"),
            ]),
            MCMAbility(id: "wc-customer-stats", name: "Customer Stats", description: "New vs returning, AOV by segment", params: [
                MCMParam(name: "period", description: "Period", defaultValue: "month"),
            ]),
            MCMAbility(id: "wc-coupon-report", name: "Coupon Report", description: "Coupon usage with attributed revenue", params: [
                MCMParam(name: "period", description: "Period", defaultValue: "month"),
            ]),
            MCMAbility(id: "wc-tax-report", name: "Tax Report", description: "Tax by rate and region", params: [
                MCMParam(name: "period", description: "Period", defaultValue: "month"),
            ]),
            MCMAbility(id: "wc-stock-report", name: "Stock Report", description: "Stock analysis (low/out/backorder filters, value)", params: [
                MCMParam(name: "status", description: "Stock status filter", enumValues: ["low", "out", "onbackorder", "all"]),
            ]),
            MCMAbility(id: "wc-variation-report", name: "Variation Report", description: "Variation performance per variable product", params: [
                MCMParam(name: "product_id", type: "integer", description: "Variable product ID", required: true),
                MCMParam(name: "period", description: "Period", defaultValue: "month"),
            ]),
            MCMAbility(id: "wc-performance-kpis", name: "Performance KPIs", description: "Executive KPIs with period comparison", params: [
                MCMParam(name: "period", description: "Period", defaultValue: "month"),
                MCMParam(name: "compare", description: "Comparison period", defaultValue: "previous_period"),
            ]),

            // Webhooks
            MCMAbility(id: "wc-list-webhooks", name: "List Webhooks", description: "List webhooks with status summary"),
            MCMAbility(id: "wc-manage-webhook", name: "Manage Webhook", description: "Create/update/delete/pause/activate", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["create", "update", "delete", "pause", "activate"]),
                MCMParam(name: "webhook_id", type: "integer", description: "Webhook ID (for update/delete/pause/activate)"),
                MCMParam(name: "name", description: "Webhook name (for create)"),
                MCMParam(name: "topic", description: "Topic (for create)", enumValues: ["order.created", "order.updated", "product.created", "product.updated", "customer.created"]),
                MCMParam(name: "delivery_url", description: "Delivery URL (for create)"),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-webhook-deliveries", name: "Webhook Deliveries", description: "Delivery history for debugging", params: [
                MCMParam(name: "webhook_id", type: "integer", description: "Webhook ID", required: true),
            ]),

            // Settings
            MCMAbility(id: "wc-store-info", name: "Store Info", description: "Store information (name, address, currency, etc.)"),
            MCMAbility(id: "wc-payment-gateways", name: "Payment Gateways", description: "List payment gateways with status"),
            MCMAbility(id: "wc-emails", name: "Email Settings", description: "WooCommerce email settings"),
            MCMAbility(id: "wc-list-settings-groups", name: "List Settings Groups", description: "List all WC settings groups (general, products, tax, shipping)"),
            MCMAbility(id: "wc-read-settings", name: "Read Settings", description: "Read all settings in a group with values, types, options, defaults", params: [
                MCMParam(name: "group_id", description: "Settings group ID", required: true),
            ]),
            MCMAbility(id: "wc-update-setting", name: "Update Setting", description: "Update individual WC setting", params: [
                MCMParam(name: "group_id", description: "Settings group ID", required: true),
                MCMParam(name: "setting_id", description: "Setting ID", required: true),
                MCMParam(name: "value", description: "New value", required: true),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-manage-shipping-method", name: "Manage Shipping Method", description: "Read/update shipping method instance settings", params: [
                MCMParam(name: "zone_id", type: "integer", description: "Shipping zone ID", required: true),
                MCMParam(name: "instance_id", type: "integer", description: "Method instance ID", required: true),
                MCMParam(name: "action", description: "Action", defaultValue: "read", enumValues: ["read", "update"]),
                MCMParam(name: "settings", description: "Settings to update (JSON, for update action)"),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-shipping-zones", name: "Shipping Zones", description: "List shipping zones with methods"),

            // Subscriptions
            MCMAbility(id: "wc-list-subscriptions", name: "List Subscriptions", description: "List WooCommerce subscriptions (requires WCS)", params: [
                MCMParam(name: "status", description: "Status filter", enumValues: ["active", "on-hold", "cancelled", "expired", "pending"]),
                MCMParam(name: "per_page", type: "integer", description: "Results per page", defaultValue: "10"),
            ]),
            MCMAbility(id: "wc-subscription-stats", name: "Subscription Stats", description: "Subscription statistics (MRR, churn, growth)"),

            // System Tools & Logs
            MCMAbility(id: "wc-system-tools", name: "WC System Tools", description: "List/execute WC system tools (clear transients, recount terms, etc.)", params: [
                MCMParam(name: "action", description: "Action", defaultValue: "list", enumValues: ["list", "execute"]),
                MCMParam(name: "tool_id", description: "Tool ID (for execute)"),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-logs", name: "WC Logs", description: "List and read WooCommerce log files", params: [
                MCMParam(name: "action", description: "Action", defaultValue: "list", enumValues: ["list", "read"]),
                MCMParam(name: "file", description: "Log file name (for read)"),
                MCMParam(name: "lines", type: "integer", description: "Number of lines (for read)", defaultValue: "100"),
            ]),
            MCMAbility(id: "wc-clear-logs", name: "Clear WC Logs", description: "Delete specific or all WC log files", params: [
                MCMParam(name: "file", description: "Specific file to delete (omit for all)"),
            ], requiresConfirmation: true),
            MCMAbility(id: "wc-delete-coupon", name: "Delete Coupon", description: "Delete WooCommerce coupon", params: [
                MCMParam(name: "id", type: "integer", description: "Coupon ID", required: true),
                MCMParam(name: "force", type: "boolean", description: "Permanently delete", defaultValue: "false"),
            ], requiresConfirmation: true),
        ]
    )

    // MARK: - wp.vigia

    public static let vigia = MCMSubConnector(
        id: "wp.vigia",
        name: "WP VigIA",
        description: "AI crawler monitoring, blocking, robots.txt management (requires VigIA plugin)",
        icon: "eye.trianglebadge.exclamationmark",
        abilities: [
            MCMAbility(id: "vigia-stats", name: "VigIA Stats", description: "AI crawler statistics", params: [
                MCMParam(name: "period", description: "Time period", defaultValue: "30d", enumValues: ["24h", "7d", "30d", "90d"]),
            ]),
            MCMAbility(id: "vigia-crawlers", name: "VigIA Crawlers", description: "Top AI crawlers", params: [
                MCMParam(name: "period", description: "Time period", defaultValue: "30d"),
                MCMParam(name: "limit", type: "integer", description: "Max results", defaultValue: "20"),
            ]),
            MCMAbility(id: "vigia-top-pages", name: "VigIA Top Pages", description: "Most crawled pages", params: [
                MCMParam(name: "period", description: "Time period", defaultValue: "30d"),
                MCMParam(name: "limit", type: "integer", description: "Max results", defaultValue: "20"),
            ]),
            MCMAbility(id: "vigia-timeline", name: "VigIA Timeline", description: "Crawl activity timeline", params: [
                MCMParam(name: "period", description: "Time period", defaultValue: "7d"),
                MCMParam(name: "granularity", description: "Data granularity", defaultValue: "hour", enumValues: ["hour", "day"]),
            ]),
            MCMAbility(id: "vigia-recent", name: "VigIA Recent", description: "Recent crawl events", params: [
                MCMParam(name: "limit", type: "integer", description: "Max results", defaultValue: "50"),
                MCMParam(name: "crawler", description: "Filter by crawler name"),
            ]),
            MCMAbility(id: "vigia-categories", name: "VigIA Categories", description: "Crawler categories breakdown"),
            MCMAbility(id: "vigia-settings", name: "VigIA Settings", description: "VigIA plugin settings", params: [
                MCMParam(name: "action", description: "Action", defaultValue: "get", enumValues: ["get", "update"]),
            ]),
            MCMAbility(id: "vigia-blocking", name: "VigIA Blocking", description: "Manage AI crawler blocking", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["list", "block", "unblock"]),
                MCMParam(name: "crawler", description: "Crawler name (for block/unblock)"),
            ]),
            MCMAbility(id: "vigia-robots", name: "VigIA Robots", description: "Manage robots.txt rules for AI crawlers", params: [
                MCMParam(name: "action", description: "Action", required: true, enumValues: ["get", "update"]),
                MCMParam(name: "rules", description: "Robots.txt rules (for update)"),
            ]),
        ]
    )
}
