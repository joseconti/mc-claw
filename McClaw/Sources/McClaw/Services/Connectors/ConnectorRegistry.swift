import Foundation
import McClawKit

/// Static registry of all available connector definitions.
enum ConnectorRegistry {

    /// All connector definitions grouped by category.
    static let definitions: [ConnectorDefinition] = google + microsoft + dev + communication + productivity + utilities + wordpress

    /// Look up a definition by ID.
    static func definition(for id: String) -> ConnectorDefinition? {
        definitions.first { $0.id == id }
    }

    /// All definitions for a given category.
    static func definitions(for category: ConnectorCategory) -> [ConnectorDefinition] {
        definitions.filter { $0.category == category }
    }

    /// All categories that have definitions, sorted.
    static var categories: [ConnectorCategory] {
        ConnectorCategory.allCases.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Google

    static let google: [ConnectorDefinition] = [
        ConnectorDefinition(
            id: "google.gmail",
            category: .google,
            name: "Gmail",
            description: "Read and search emails from your Gmail account",
            icon: "envelope",
            authType: .oauth2,
            actions: [
                ConnectorActionDef(id: "search", name: "Search emails", description: "Search emails by query", parameters: [
                    ConnectorActionParam(name: "q", description: "Search query (e.g. 'is:unread from:boss')", required: true),
                    ConnectorActionParam(name: "maxResults", description: "Max results to return", defaultValue: "10"),
                ]),
                ConnectorActionDef(id: "read", name: "Read email", description: "Read a specific email by ID", parameters: [
                    ConnectorActionParam(name: "messageId", description: "Gmail message ID", required: true),
                ]),
                ConnectorActionDef(id: "list_unread", name: "List unread", description: "List unread emails", parameters: [
                    ConnectorActionParam(name: "maxResults", description: "Max results", defaultValue: "10"),
                ]),
                ConnectorActionDef(id: "list_labels", name: "List labels", description: "List all Gmail labels"),
            ],
            requiredScopes: ["https://www.googleapis.com/auth/gmail.readonly"]
        ),
        ConnectorDefinition(
            id: "google.calendar",
            category: .google,
            name: "Google Calendar",
            description: "Read events and check availability from Google Calendar",
            icon: "calendar",
            authType: .oauth2,
            actions: [
                ConnectorActionDef(id: "list_events", name: "List events", description: "List calendar events in a date range", parameters: [
                    ConnectorActionParam(name: "timeMin", description: "Start date (ISO 8601)", required: true),
                    ConnectorActionParam(name: "timeMax", description: "End date (ISO 8601)", required: true),
                    ConnectorActionParam(name: "calendarId", description: "Calendar ID", defaultValue: "primary"),
                ]),
                ConnectorActionDef(id: "get_event", name: "Get event", description: "Get details of a specific event", parameters: [
                    ConnectorActionParam(name: "eventId", description: "Event ID", required: true),
                    ConnectorActionParam(name: "calendarId", description: "Calendar ID", defaultValue: "primary"),
                ]),
                ConnectorActionDef(id: "list_calendars", name: "List calendars", description: "List all calendars"),
            ],
            requiredScopes: ["https://www.googleapis.com/auth/calendar.readonly"]
        ),
        ConnectorDefinition(
            id: "google.drive",
            category: .google,
            name: "Google Drive",
            description: "Search and list files from Google Drive",
            icon: "externaldrive",
            authType: .oauth2,
            actions: [
                ConnectorActionDef(id: "search", name: "Search files", description: "Search files by name or content", parameters: [
                    ConnectorActionParam(name: "q", description: "Search query", required: true),
                ]),
                ConnectorActionDef(id: "list_recent", name: "Recent files", description: "List recently modified files", parameters: [
                    ConnectorActionParam(name: "maxResults", description: "Max results", defaultValue: "10"),
                ]),
                ConnectorActionDef(id: "get_file_metadata", name: "File metadata", description: "Get metadata of a file", parameters: [
                    ConnectorActionParam(name: "fileId", description: "File ID", required: true),
                ]),
            ],
            requiredScopes: ["https://www.googleapis.com/auth/drive.readonly"]
        ),
        ConnectorDefinition(
            id: "google.sheets",
            category: .google,
            name: "Google Sheets",
            description: "Read data from Google Sheets spreadsheets",
            icon: "tablecells",
            authType: .oauth2,
            actions: [
                ConnectorActionDef(id: "read_range", name: "Read range", description: "Read a cell range from a spreadsheet", parameters: [
                    ConnectorActionParam(name: "spreadsheetId", description: "Spreadsheet ID", required: true),
                    ConnectorActionParam(name: "range", description: "Cell range (e.g. 'Sheet1!A1:D10')", required: true),
                ]),
                ConnectorActionDef(id: "list_sheets", name: "List sheets", description: "List all sheets in a spreadsheet", parameters: [
                    ConnectorActionParam(name: "spreadsheetId", description: "Spreadsheet ID", required: true),
                ]),
            ],
            requiredScopes: ["https://www.googleapis.com/auth/spreadsheets.readonly"]
        ),
        ConnectorDefinition(
            id: "google.contacts",
            category: .google,
            name: "Google Contacts",
            description: "Search and list contacts from Google",
            icon: "person.2",
            authType: .oauth2,
            actions: [
                ConnectorActionDef(id: "search", name: "Search contacts", description: "Search contacts by name or email", parameters: [
                    ConnectorActionParam(name: "query", description: "Search query", required: true),
                ]),
                ConnectorActionDef(id: "list_groups", name: "List groups", description: "List contact groups"),
            ],
            requiredScopes: ["https://www.googleapis.com/auth/contacts.readonly"]
        ),
    ]

    // MARK: - Microsoft

    static let microsoft: [ConnectorDefinition] = [
        ConnectorDefinition(
            id: "microsoft.outlook",
            category: .microsoft,
            name: "Outlook Mail",
            description: "Read and search emails from Outlook / Microsoft 365",
            icon: "envelope.badge",
            authType: .oauth2,
            actions: [
                ConnectorActionDef(id: "list_messages", name: "List messages", description: "List recent emails", parameters: [
                    ConnectorActionParam(name: "folder", description: "Folder (inbox, sentitems, etc.)", defaultValue: "inbox"),
                    ConnectorActionParam(name: "top", description: "Number of messages", defaultValue: "10"),
                ]),
                ConnectorActionDef(id: "read_message", name: "Read message", description: "Read a specific email", parameters: [
                    ConnectorActionParam(name: "messageId", description: "Message ID", required: true),
                ]),
                ConnectorActionDef(id: "search", name: "Search emails", description: "Search emails by keyword", parameters: [
                    ConnectorActionParam(name: "query", description: "Search query", required: true),
                ]),
                ConnectorActionDef(id: "list_folders", name: "List folders", description: "List mail folders"),
            ],
            requiredScopes: ["Mail.Read"]
        ),
        ConnectorDefinition(
            id: "microsoft.calendar",
            category: .microsoft,
            name: "Outlook Calendar",
            description: "Read events from Outlook / Microsoft 365 Calendar",
            icon: "calendar.badge.clock",
            authType: .oauth2,
            actions: [
                ConnectorActionDef(id: "list_events", name: "List events", description: "List calendar events", parameters: [
                    ConnectorActionParam(name: "startDateTime", description: "Start (ISO 8601)", required: true),
                    ConnectorActionParam(name: "endDateTime", description: "End (ISO 8601)", required: true),
                ]),
                ConnectorActionDef(id: "get_event", name: "Get event", description: "Get event details", parameters: [
                    ConnectorActionParam(name: "eventId", description: "Event ID", required: true),
                ]),
                ConnectorActionDef(id: "list_calendars", name: "List calendars", description: "List all calendars"),
            ],
            requiredScopes: ["Calendars.Read"]
        ),
        ConnectorDefinition(
            id: "microsoft.onedrive",
            category: .microsoft,
            name: "OneDrive",
            description: "Search and list files from OneDrive",
            icon: "cloud",
            authType: .oauth2,
            actions: [
                ConnectorActionDef(id: "list_recent", name: "Recent files", description: "List recently accessed files"),
                ConnectorActionDef(id: "search", name: "Search files", description: "Search files by name", parameters: [
                    ConnectorActionParam(name: "query", description: "Search query", required: true),
                ]),
                ConnectorActionDef(id: "get_item", name: "Get item", description: "Get file/folder metadata", parameters: [
                    ConnectorActionParam(name: "itemId", description: "Item ID", required: true),
                ]),
            ],
            requiredScopes: ["Files.Read"]
        ),
        ConnectorDefinition(
            id: "microsoft.todo",
            category: .microsoft,
            name: "Microsoft To Do",
            description: "Read tasks and lists from Microsoft To Do",
            icon: "checklist",
            authType: .oauth2,
            actions: [
                ConnectorActionDef(id: "list_tasks", name: "List tasks", description: "List tasks in a list", parameters: [
                    ConnectorActionParam(name: "listId", description: "Task list ID", required: true),
                ]),
                ConnectorActionDef(id: "list_lists", name: "List task lists", description: "List all task lists"),
                ConnectorActionDef(id: "get_task", name: "Get task", description: "Get task details", parameters: [
                    ConnectorActionParam(name: "listId", description: "Task list ID", required: true),
                    ConnectorActionParam(name: "taskId", description: "Task ID", required: true),
                ]),
            ],
            requiredScopes: ["Tasks.Read"]
        ),
    ]

    // MARK: - Development

    static let dev: [ConnectorDefinition] = [
        ConnectorDefinition(
            id: "dev.github",
            category: .dev,
            name: "GitHub",
            description: "Access issues, PRs, repos, and notifications from GitHub",
            icon: "arrow.triangle.branch",
            authType: .pat,
            actions: [
                ConnectorActionDef(id: "list_issues", name: "List issues", description: "List issues in a repository", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                    ConnectorActionParam(name: "state", description: "State filter (open, closed, all)", defaultValue: "open"),
                ]),
                ConnectorActionDef(id: "list_prs", name: "List PRs", description: "List pull requests", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                    ConnectorActionParam(name: "state", description: "State filter", defaultValue: "open"),
                ]),
                ConnectorActionDef(id: "list_repos", name: "List repos", description: "List your repositories", parameters: [
                    ConnectorActionParam(name: "sort", description: "Sort by (updated, created, pushed)", defaultValue: "updated"),
                ]),
                ConnectorActionDef(id: "search_code", name: "Search code", description: "Search code across repositories", parameters: [
                    ConnectorActionParam(name: "query", description: "Search query", required: true),
                ]),
                ConnectorActionDef(id: "get_notifications", name: "Notifications", description: "Get unread notifications"),
            ]
        ),
        ConnectorDefinition(
            id: "dev.gitlab",
            category: .dev,
            name: "GitLab",
            description: "Access issues, merge requests, and projects from GitLab",
            icon: "arrow.triangle.branch",
            authType: .pat,
            actions: [
                ConnectorActionDef(id: "list_issues", name: "List issues", description: "List project issues", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                    ConnectorActionParam(name: "state", description: "State filter (opened, closed, all)", defaultValue: "opened"),
                ]),
                ConnectorActionDef(id: "list_mrs", name: "List MRs", description: "List merge requests", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                    ConnectorActionParam(name: "state", description: "State filter", defaultValue: "opened"),
                ]),
                ConnectorActionDef(id: "list_projects", name: "List projects", description: "List your projects"),
            ]
        ),
        ConnectorDefinition(
            id: "dev.linear",
            category: .dev,
            name: "Linear",
            description: "Access issues and projects from Linear",
            icon: "lines.measurement.horizontal",
            authType: .oauth2,
            actions: [
                ConnectorActionDef(id: "list_issues", name: "List issues", description: "List issues", parameters: [
                    ConnectorActionParam(name: "teamId", description: "Team ID"),
                    ConnectorActionParam(name: "state", description: "State filter"),
                ]),
                ConnectorActionDef(id: "list_projects", name: "List projects", description: "List all projects"),
                ConnectorActionDef(id: "my_assigned", name: "My assigned", description: "List issues assigned to you"),
            ]
        ),
        ConnectorDefinition(
            id: "dev.jira",
            category: .dev,
            name: "Jira",
            description: "Access issues, sprints, and projects from Jira",
            icon: "ticket",
            authType: .apiKey,
            actions: [
                ConnectorActionDef(id: "list_issues", name: "List issues", description: "List project issues", parameters: [
                    ConnectorActionParam(name: "projectKey", description: "Project key (e.g. PROJ)", required: true),
                ]),
                ConnectorActionDef(id: "search_jql", name: "Search JQL", description: "Search with JQL query", parameters: [
                    ConnectorActionParam(name: "jql", description: "JQL query", required: true),
                ]),
                ConnectorActionDef(id: "my_assigned", name: "My assigned", description: "Issues assigned to you"),
            ]
        ),
        ConnectorDefinition(
            id: "dev.notion",
            category: .dev,
            name: "Notion",
            description: "Search and read pages and databases from Notion",
            icon: "doc.text",
            authType: .apiKey,
            actions: [
                ConnectorActionDef(id: "search", name: "Search", description: "Search pages and databases", parameters: [
                    ConnectorActionParam(name: "query", description: "Search query", required: true),
                ]),
                ConnectorActionDef(id: "list_databases", name: "List databases", description: "List all databases"),
                ConnectorActionDef(id: "query_database", name: "Query database", description: "Query a specific database", parameters: [
                    ConnectorActionParam(name: "databaseId", description: "Database ID", required: true),
                ]),
            ]
        ),
    ]

    // MARK: - Communication

    static let communication: [ConnectorDefinition] = [
        ConnectorDefinition(
            id: "comm.slack",
            category: .communication,
            name: "Slack",
            description: "Read messages and channels from Slack",
            icon: "number",
            authType: .botToken,
            actions: [
                ConnectorActionDef(id: "list_channels", name: "List channels", description: "List workspace channels"),
                ConnectorActionDef(id: "read_channel", name: "Read channel", description: "Read recent messages from a channel", parameters: [
                    ConnectorActionParam(name: "channelId", description: "Channel ID", required: true),
                    ConnectorActionParam(name: "limit", description: "Number of messages", defaultValue: "20"),
                ]),
                ConnectorActionDef(id: "search_messages", name: "Search messages", description: "Search messages across workspace", parameters: [
                    ConnectorActionParam(name: "query", description: "Search query", required: true),
                ]),
            ]
        ),
        ConnectorDefinition(
            id: "comm.discord",
            category: .communication,
            name: "Discord",
            description: "Read messages and channels from Discord servers",
            icon: "bubble.left",
            authType: .botToken,
            actions: [
                ConnectorActionDef(id: "list_guilds", name: "List servers", description: "List servers the bot is in"),
                ConnectorActionDef(id: "list_channels", name: "List channels", description: "List channels in a server", parameters: [
                    ConnectorActionParam(name: "guildId", description: "Server ID", required: true),
                ]),
                ConnectorActionDef(id: "read_channel", name: "Read channel", description: "Read recent messages", parameters: [
                    ConnectorActionParam(name: "channelId", description: "Channel ID", required: true),
                    ConnectorActionParam(name: "limit", description: "Number of messages", defaultValue: "20"),
                ]),
            ]
        ),
        ConnectorDefinition(
            id: "comm.telegram",
            category: .communication,
            name: "Telegram",
            description: "Read messages and updates from Telegram bot",
            icon: "paperplane",
            authType: .botToken,
            actions: [
                ConnectorActionDef(id: "get_updates", name: "Get updates", description: "Get recent bot updates", parameters: [
                    ConnectorActionParam(name: "limit", description: "Max updates", defaultValue: "20"),
                ]),
                ConnectorActionDef(id: "get_me", name: "Bot info", description: "Get bot information"),
            ]
        ),
        ConnectorDefinition(
            id: "comm.matrix",
            category: .communication,
            name: "Matrix",
            description: "Connect to Matrix homeserver for decentralized messaging",
            icon: "square.grid.3x3",
            authType: .pat,
            actions: [
                ConnectorActionDef(id: "whoami", name: "Who am I", description: "Get authenticated user info"),
                ConnectorActionDef(id: "joined_rooms", name: "Joined rooms", description: "List rooms the bot has joined"),
                ConnectorActionDef(id: "sync", name: "Sync", description: "Sync latest events from joined rooms"),
            ]
        ),
        ConnectorDefinition(
            id: "comm.mattermost",
            category: .communication,
            name: "Mattermost",
            description: "Connect to Mattermost server for team messaging",
            icon: "bubble.left.and.bubble.right",
            authType: .pat,
            actions: [
                ConnectorActionDef(id: "get_me", name: "Get profile", description: "Get authenticated user profile"),
                ConnectorActionDef(id: "list_channels", name: "List channels", description: "List channels in a team", parameters: [
                    ConnectorActionParam(name: "teamId", description: "Team ID", required: true),
                ]),
                ConnectorActionDef(id: "list_teams", name: "List teams", description: "List teams the user belongs to"),
            ]
        ),
        ConnectorDefinition(
            id: "comm.mastodon",
            category: .communication,
            name: "Mastodon",
            description: "Connect to Mastodon/Fediverse instance for social messaging",
            icon: "globe",
            authType: .pat,
            actions: [
                ConnectorActionDef(id: "verify_credentials", name: "Verify credentials", description: "Get authenticated account info"),
                ConnectorActionDef(id: "notifications", name: "Notifications", description: "Get recent notifications", parameters: [
                    ConnectorActionParam(name: "limit", description: "Max notifications", defaultValue: "20"),
                ]),
                ConnectorActionDef(id: "home_timeline", name: "Home timeline", description: "Get home timeline"),
            ]
        ),
        ConnectorDefinition(
            id: "comm.zulip",
            category: .communication,
            name: "Zulip",
            description: "Connect to Zulip server for organized team chat",
            icon: "bubble.left.and.text.bubble.right",
            authType: .apiKey,
            actions: [
                ConnectorActionDef(id: "get_profile", name: "Get profile", description: "Get bot profile"),
                ConnectorActionDef(id: "list_streams", name: "List streams", description: "List available streams"),
                ConnectorActionDef(id: "get_messages", name: "Get messages", description: "Get messages from a stream", parameters: [
                    ConnectorActionParam(name: "stream", description: "Stream name", required: true),
                    ConnectorActionParam(name: "topic", description: "Topic name"),
                ]),
            ]
        ),
        ConnectorDefinition(
            id: "comm.rocketchat",
            category: .communication,
            name: "Rocket.Chat",
            description: "Connect to Rocket.Chat server for team messaging",
            icon: "bubble.left.and.exclamationmark.bubble.right",
            authType: .pat,
            actions: [
                ConnectorActionDef(id: "get_me", name: "Get profile", description: "Get authenticated user profile"),
                ConnectorActionDef(id: "list_channels", name: "List channels", description: "List public channels"),
                ConnectorActionDef(id: "list_dms", name: "List DMs", description: "List direct message rooms"),
            ]
        ),
        ConnectorDefinition(
            id: "comm.twitch",
            category: .communication,
            name: "Twitch",
            description: "Connect to Twitch for chat bot integration",
            icon: "play.tv",
            authType: .pat,
            actions: [
                ConnectorActionDef(id: "validate_token", name: "Validate token", description: "Validate OAuth token"),
                ConnectorActionDef(id: "get_user", name: "Get user", description: "Get user info by login", parameters: [
                    ConnectorActionParam(name: "login", description: "Twitch username", required: true),
                ]),
            ]
        ),
    ]

    // MARK: - Productivity

    static let productivity: [ConnectorDefinition] = [
        ConnectorDefinition(
            id: "prod.todoist",
            category: .productivity,
            name: "Todoist",
            description: "Read tasks and projects from Todoist",
            icon: "checkmark.circle",
            authType: .apiKey,
            actions: [
                ConnectorActionDef(id: "list_tasks", name: "List tasks", description: "List active tasks", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID (optional)"),
                    ConnectorActionParam(name: "filter", description: "Filter expression"),
                ]),
                ConnectorActionDef(id: "list_projects", name: "List projects", description: "List all projects"),
                ConnectorActionDef(id: "get_task", name: "Get task", description: "Get task details", parameters: [
                    ConnectorActionParam(name: "taskId", description: "Task ID", required: true),
                ]),
            ]
        ),
        ConnectorDefinition(
            id: "prod.trello",
            category: .productivity,
            name: "Trello",
            description: "Read boards, lists, and cards from Trello",
            icon: "rectangle.split.3x1",
            authType: .apiKey,
            actions: [
                ConnectorActionDef(id: "list_boards", name: "List boards", description: "List your boards"),
                ConnectorActionDef(id: "list_cards", name: "List cards", description: "List cards in a list", parameters: [
                    ConnectorActionParam(name: "listId", description: "List ID", required: true),
                ]),
                ConnectorActionDef(id: "list_lists", name: "List lists", description: "List lists in a board", parameters: [
                    ConnectorActionParam(name: "boardId", description: "Board ID", required: true),
                ]),
            ]
        ),
        ConnectorDefinition(
            id: "prod.airtable",
            category: .productivity,
            name: "Airtable",
            description: "Read records and tables from Airtable bases",
            icon: "tablecells.badge.ellipsis",
            authType: .apiKey,
            actions: [
                ConnectorActionDef(id: "list_records", name: "List records", description: "List records in a table", parameters: [
                    ConnectorActionParam(name: "baseId", description: "Base ID", required: true),
                    ConnectorActionParam(name: "tableId", description: "Table ID or name", required: true),
                ]),
                ConnectorActionDef(id: "list_bases", name: "List bases", description: "List all accessible bases"),
                ConnectorActionDef(id: "get_record", name: "Get record", description: "Get a specific record", parameters: [
                    ConnectorActionParam(name: "baseId", description: "Base ID", required: true),
                    ConnectorActionParam(name: "tableId", description: "Table ID", required: true),
                    ConnectorActionParam(name: "recordId", description: "Record ID", required: true),
                ]),
            ]
        ),
        ConnectorDefinition(
            id: "prod.dropbox",
            category: .productivity,
            name: "Dropbox",
            description: "Search and list files from Dropbox",
            icon: "shippingbox",
            authType: .oauth2,
            actions: [
                ConnectorActionDef(id: "list_files", name: "List files", description: "List files in a folder", parameters: [
                    ConnectorActionParam(name: "path", description: "Folder path", defaultValue: ""),
                ]),
                ConnectorActionDef(id: "search", name: "Search files", description: "Search files by name", parameters: [
                    ConnectorActionParam(name: "query", description: "Search query", required: true),
                ]),
                ConnectorActionDef(id: "get_metadata", name: "Get metadata", description: "Get file metadata", parameters: [
                    ConnectorActionParam(name: "path", description: "File path", required: true),
                ]),
            ]
        ),
    ]

    // MARK: - Utilities

    static let utilities: [ConnectorDefinition] = [
        ConnectorDefinition(
            id: "util.weather",
            category: .utilities,
            name: "Weather",
            description: "Get current weather and forecasts (OpenWeatherMap)",
            icon: "cloud.sun",
            authType: .apiKey,
            actions: [
                ConnectorActionDef(id: "current", name: "Current weather", description: "Get current weather for a location", parameters: [
                    ConnectorActionParam(name: "city", description: "City name (e.g. 'Madrid,ES')", required: true),
                ]),
                ConnectorActionDef(id: "forecast", name: "Forecast", description: "Get weather forecast", parameters: [
                    ConnectorActionParam(name: "city", description: "City name", required: true),
                ]),
                ConnectorActionDef(id: "alerts", name: "Weather alerts", description: "Get weather alerts for coordinates", parameters: [
                    ConnectorActionParam(name: "lat", description: "Latitude", required: true),
                    ConnectorActionParam(name: "lon", description: "Longitude", required: true),
                ]),
            ]
        ),
        ConnectorDefinition(
            id: "util.rss",
            category: .utilities,
            name: "RSS / Feeds",
            description: "Read RSS and Atom feeds from any URL",
            icon: "dot.radiowaves.left.and.right",
            authType: .none,
            actions: [
                ConnectorActionDef(id: "fetch_feed", name: "Fetch feed", description: "Fetch and parse an RSS/Atom feed", parameters: [
                    ConnectorActionParam(name: "url", description: "Feed URL", required: true),
                    ConnectorActionParam(name: "maxEntries", description: "Max entries to return", defaultValue: "10"),
                ]),
            ]
        ),
        ConnectorDefinition(
            id: "util.webhook",
            category: .utilities,
            name: "Webhook",
            description: "Send HTTP requests to any URL",
            icon: "arrow.up.arrow.down.circle",
            authType: .none,
            actions: [
                ConnectorActionDef(id: "call", name: "Call webhook", description: "Make an HTTP request", parameters: [
                    ConnectorActionParam(name: "url", description: "Target URL", required: true),
                    ConnectorActionParam(name: "method", description: "HTTP method (GET or POST)", defaultValue: "GET"),
                    ConnectorActionParam(name: "body", description: "Request body (JSON string)"),
                ]),
            ]
        ),
    ]

    // MARK: - WordPress (via MCP Content Manager — single connector, all abilities)

    static let wordpress: [ConnectorDefinition] = [
        ConnectorDefinition(
            id: "wp.mcm",
            category: .wordpress,
            name: "WordPress (MCP Content Manager)",
            description: "Full WordPress & WooCommerce management via MCP Content Manager — \(MCMAbilitiesCatalog.totalAbilities) abilities across \(MCMAbilitiesCatalog.subConnectors.count) modules",
            icon: "w.circle.fill",
            authType: .mcpBridge,
            actions: MCMAbilitiesCatalog.subConnectors.flatMap { sub in
                sub.abilities.map { ability in
                    ConnectorActionDef(
                        id: ability.id,
                        name: ability.name,
                        description: "[\(sub.name)] \(ability.description)",
                        parameters: ability.params.map { p in
                            ConnectorActionParam(
                                name: p.name,
                                description: p.description,
                                type: p.type,
                                required: p.required,
                                defaultValue: p.defaultValue,
                                enumValues: p.enumValues
                            )
                        }
                    )
                }
            }
        ),
    ]
}
