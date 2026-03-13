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
                ConnectorActionDef(id: "send_email", name: "Send email", description: "Send a new email", parameters: [
                    ConnectorActionParam(name: "to", description: "Recipient email address", required: true),
                    ConnectorActionParam(name: "subject", description: "Email subject", required: true),
                    ConnectorActionParam(name: "body", description: "Email body", required: true),
                    ConnectorActionParam(name: "cc", description: "CC recipients (comma-separated)"),
                    ConnectorActionParam(name: "bcc", description: "BCC recipients (comma-separated)"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "reply_to_email", name: "Reply to email", description: "Reply to an existing email", parameters: [
                    ConnectorActionParam(name: "messageId", description: "Gmail message ID to reply to", required: true),
                    ConnectorActionParam(name: "body", description: "Reply body", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "create_draft", name: "Create draft", description: "Create a draft email", parameters: [
                    ConnectorActionParam(name: "to", description: "Recipient email address", required: true),
                    ConnectorActionParam(name: "subject", description: "Email subject", required: true),
                    ConnectorActionParam(name: "body", description: "Email body", required: true),
                ], isWriteAction: true),
            ],
            requiredScopes: ["https://www.googleapis.com/auth/gmail.readonly", "https://www.googleapis.com/auth/gmail.compose"]
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
                ConnectorActionDef(id: "create_event", name: "Create event", description: "Create a new calendar event", parameters: [
                    ConnectorActionParam(name: "summary", description: "Event title", required: true),
                    ConnectorActionParam(name: "startDateTime", description: "Start date/time (ISO 8601)", required: true),
                    ConnectorActionParam(name: "endDateTime", description: "End date/time (ISO 8601)", required: true),
                    ConnectorActionParam(name: "location", description: "Event location"),
                    ConnectorActionParam(name: "description", description: "Event description"),
                    ConnectorActionParam(name: "calendarId", description: "Calendar ID", defaultValue: "primary"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "update_event", name: "Update event", description: "Update an existing calendar event", parameters: [
                    ConnectorActionParam(name: "eventId", description: "Event ID", required: true),
                    ConnectorActionParam(name: "summary", description: "Event title"),
                    ConnectorActionParam(name: "startDateTime", description: "Start date/time (ISO 8601)"),
                    ConnectorActionParam(name: "endDateTime", description: "End date/time (ISO 8601)"),
                    ConnectorActionParam(name: "location", description: "Event location"),
                    ConnectorActionParam(name: "description", description: "Event description"),
                    ConnectorActionParam(name: "calendarId", description: "Calendar ID", defaultValue: "primary"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "delete_event", name: "Delete event", description: "Delete a calendar event", parameters: [
                    ConnectorActionParam(name: "eventId", description: "Event ID", required: true),
                    ConnectorActionParam(name: "calendarId", description: "Calendar ID", defaultValue: "primary"),
                ], isWriteAction: true),
            ],
            requiredScopes: ["https://www.googleapis.com/auth/calendar.events"]
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
                ConnectorActionDef(id: "create_folder", name: "Create folder", description: "Create a new folder in Drive", parameters: [
                    ConnectorActionParam(name: "name", description: "Folder name", required: true),
                    ConnectorActionParam(name: "parentId", description: "Parent folder ID"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "move_file", name: "Move file", description: "Move a file to a different folder", parameters: [
                    ConnectorActionParam(name: "fileId", description: "File ID", required: true),
                    ConnectorActionParam(name: "newParentId", description: "New parent folder ID", required: true),
                ], isWriteAction: true),
            ],
            requiredScopes: ["https://www.googleapis.com/auth/drive.file"]
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
                ConnectorActionDef(id: "write_range", name: "Write range", description: "Write values to a cell range", parameters: [
                    ConnectorActionParam(name: "spreadsheetId", description: "Spreadsheet ID", required: true),
                    ConnectorActionParam(name: "range", description: "Cell range (e.g. 'Sheet1!A1:D10')", required: true),
                    ConnectorActionParam(name: "values", description: "Values to write (JSON array of arrays)", required: true),
                ], isWriteAction: true),
            ],
            requiredScopes: ["https://www.googleapis.com/auth/spreadsheets"]
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
                ConnectorActionDef(id: "create_contact", name: "Create contact", description: "Create a new contact", parameters: [
                    ConnectorActionParam(name: "givenName", description: "First name", required: true),
                    ConnectorActionParam(name: "familyName", description: "Last name"),
                    ConnectorActionParam(name: "email", description: "Email address"),
                    ConnectorActionParam(name: "phone", description: "Phone number"),
                ], isWriteAction: true),
            ],
            requiredScopes: ["https://www.googleapis.com/auth/contacts"]
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
                ConnectorActionDef(id: "send_email", name: "Send email", description: "Send a new email", parameters: [
                    ConnectorActionParam(name: "to", description: "Recipient email address", required: true),
                    ConnectorActionParam(name: "subject", description: "Email subject", required: true),
                    ConnectorActionParam(name: "body", description: "Email body", required: true),
                    ConnectorActionParam(name: "cc", description: "CC recipients (comma-separated)"),
                    ConnectorActionParam(name: "bcc", description: "BCC recipients (comma-separated)"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "reply_to_email", name: "Reply to email", description: "Reply to an existing email", parameters: [
                    ConnectorActionParam(name: "messageId", description: "Message ID to reply to", required: true),
                    ConnectorActionParam(name: "body", description: "Reply body", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "create_draft", name: "Create draft", description: "Create a draft email", parameters: [
                    ConnectorActionParam(name: "to", description: "Recipient email address", required: true),
                    ConnectorActionParam(name: "subject", description: "Email subject", required: true),
                    ConnectorActionParam(name: "body", description: "Email body", required: true),
                ], isWriteAction: true),
            ],
            requiredScopes: ["Mail.Read", "Mail.Send"]
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
                ConnectorActionDef(id: "create_event", name: "Create event", description: "Create a new calendar event", parameters: [
                    ConnectorActionParam(name: "subject", description: "Event subject", required: true),
                    ConnectorActionParam(name: "start", description: "Start date/time (ISO 8601)", required: true),
                    ConnectorActionParam(name: "end", description: "End date/time (ISO 8601)", required: true),
                    ConnectorActionParam(name: "location", description: "Event location"),
                    ConnectorActionParam(name: "body", description: "Event body/description"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "update_event", name: "Update event", description: "Update an existing calendar event", parameters: [
                    ConnectorActionParam(name: "eventId", description: "Event ID", required: true),
                    ConnectorActionParam(name: "subject", description: "Event subject"),
                    ConnectorActionParam(name: "start", description: "Start date/time (ISO 8601)"),
                    ConnectorActionParam(name: "end", description: "End date/time (ISO 8601)"),
                    ConnectorActionParam(name: "location", description: "Event location"),
                    ConnectorActionParam(name: "body", description: "Event body/description"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "delete_event", name: "Delete event", description: "Delete a calendar event", parameters: [
                    ConnectorActionParam(name: "eventId", description: "Event ID", required: true),
                ], isWriteAction: true),
            ],
            requiredScopes: ["Calendars.ReadWrite"]
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
                ConnectorActionDef(id: "create_folder", name: "Create folder", description: "Create a new folder in OneDrive", parameters: [
                    ConnectorActionParam(name: "name", description: "Folder name", required: true),
                    ConnectorActionParam(name: "parentPath", description: "Parent folder path"),
                ], isWriteAction: true),
            ],
            requiredScopes: ["Files.ReadWrite"]
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
                ConnectorActionDef(id: "create_task", name: "Create task", description: "Create a new task", parameters: [
                    ConnectorActionParam(name: "listId", description: "Task list ID", required: true),
                    ConnectorActionParam(name: "title", description: "Task title", required: true),
                    ConnectorActionParam(name: "body", description: "Task body/notes"),
                    ConnectorActionParam(name: "dueDateTime", description: "Due date/time (ISO 8601)"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "complete_task", name: "Complete task", description: "Mark a task as completed", parameters: [
                    ConnectorActionParam(name: "listId", description: "Task list ID", required: true),
                    ConnectorActionParam(name: "taskId", description: "Task ID", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "delete_task", name: "Delete task", description: "Delete a task", parameters: [
                    ConnectorActionParam(name: "listId", description: "Task list ID", required: true),
                    ConnectorActionParam(name: "taskId", description: "Task ID", required: true),
                ], isWriteAction: true),
            ],
            requiredScopes: ["Tasks.ReadWrite"]
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
                ConnectorActionDef(id: "get_repo", name: "Get repo", description: "Get details of a specific repository", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                ]),
                ConnectorActionDef(id: "list_branches", name: "List branches", description: "List branches of a repository", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                ]),
                ConnectorActionDef(id: "get_pr_diff", name: "Get PR diff", description: "Get the diff of a pull request", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                    ConnectorActionParam(name: "pullNumber", description: "PR number", required: true),
                ]),
                ConnectorActionDef(id: "list_commits", name: "List commits", description: "List recent commits on a branch", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                    ConnectorActionParam(name: "sha", description: "Branch name or SHA", defaultValue: "main"),
                ]),
                ConnectorActionDef(id: "list_releases", name: "List releases", description: "List releases of a repository", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                ]),
                ConnectorActionDef(id: "create_issue", name: "Create issue", description: "Create a new issue in a repository", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                    ConnectorActionParam(name: "title", description: "Issue title", required: true),
                    ConnectorActionParam(name: "body", description: "Issue body"),
                    ConnectorActionParam(name: "labels", description: "Comma-separated labels"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "create_comment", name: "Create comment", description: "Add a comment to an issue or PR", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                    ConnectorActionParam(name: "issueNumber", description: "Issue or PR number", required: true),
                    ConnectorActionParam(name: "body", description: "Comment body", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "create_pr", name: "Create PR", description: "Create a pull request", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                    ConnectorActionParam(name: "title", description: "PR title", required: true),
                    ConnectorActionParam(name: "head", description: "Source branch", required: true),
                    ConnectorActionParam(name: "base", description: "Target branch", required: true),
                    ConnectorActionParam(name: "body", description: "PR description"),
                    ConnectorActionParam(name: "draft", description: "Create as draft (true/false)"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "merge_pr", name: "Merge PR", description: "Merge a pull request", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                    ConnectorActionParam(name: "pullNumber", description: "PR number", required: true),
                    ConnectorActionParam(name: "mergeMethod", description: "Merge method (merge, squash, rebase)", defaultValue: "merge"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "close_issue", name: "Close issue", description: "Close an issue", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                    ConnectorActionParam(name: "issueNumber", description: "Issue number", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "add_labels", name: "Add labels", description: "Add labels to an issue or PR", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                    ConnectorActionParam(name: "issueNumber", description: "Issue or PR number", required: true),
                    ConnectorActionParam(name: "labels", description: "Comma-separated labels", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "create_release", name: "Create release", description: "Create a new release", parameters: [
                    ConnectorActionParam(name: "repo", description: "Repository (owner/repo)", required: true),
                    ConnectorActionParam(name: "tagName", description: "Tag name (e.g. v2.0)", required: true),
                    ConnectorActionParam(name: "name", description: "Release title"),
                    ConnectorActionParam(name: "body", description: "Release notes"),
                    ConnectorActionParam(name: "generateNotes", description: "Auto-generate notes (true/false)", defaultValue: "false"),
                ], isWriteAction: true),
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
                ConnectorActionDef(id: "get_project", name: "Get project", description: "Get details of a specific project", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                ]),
                ConnectorActionDef(id: "list_branches", name: "List branches", description: "List branches of a project", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                ]),
                ConnectorActionDef(id: "get_mr_diff", name: "Get MR diff", description: "Get the diff of a merge request", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                    ConnectorActionParam(name: "mrIid", description: "MR IID", required: true),
                ]),
                ConnectorActionDef(id: "list_commits", name: "List commits", description: "List recent commits on a branch", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                    ConnectorActionParam(name: "refName", description: "Branch name", defaultValue: "main"),
                ]),
                ConnectorActionDef(id: "list_releases", name: "List releases", description: "List releases of a project", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                ]),
                ConnectorActionDef(id: "create_issue", name: "Create issue", description: "Create a new issue in a project", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                    ConnectorActionParam(name: "title", description: "Issue title", required: true),
                    ConnectorActionParam(name: "description", description: "Issue description"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "create_comment", name: "Create comment", description: "Add a comment to an issue", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                    ConnectorActionParam(name: "issueIid", description: "Issue IID", required: true),
                    ConnectorActionParam(name: "body", description: "Comment body", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "create_mr", name: "Create MR", description: "Create a merge request", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                    ConnectorActionParam(name: "title", description: "MR title", required: true),
                    ConnectorActionParam(name: "sourceBranch", description: "Source branch", required: true),
                    ConnectorActionParam(name: "targetBranch", description: "Target branch", required: true),
                    ConnectorActionParam(name: "description", description: "MR description"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "merge_mr", name: "Merge MR", description: "Merge a merge request", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                    ConnectorActionParam(name: "mrIid", description: "MR IID", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "close_issue", name: "Close issue", description: "Close an issue", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                    ConnectorActionParam(name: "issueIid", description: "Issue IID", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "create_note", name: "Create note", description: "Add a note to a merge request", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                    ConnectorActionParam(name: "mrIid", description: "MR IID", required: true),
                    ConnectorActionParam(name: "body", description: "Note body", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "create_release", name: "Create release", description: "Create a new release", parameters: [
                    ConnectorActionParam(name: "projectId", description: "Project ID or path", required: true),
                    ConnectorActionParam(name: "tagName", description: "Tag name (e.g. v2.0)", required: true),
                    ConnectorActionParam(name: "name", description: "Release title"),
                    ConnectorActionParam(name: "description", description: "Release notes"),
                ], isWriteAction: true),
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
                ConnectorActionDef(id: "create_issue", name: "Create issue", description: "Create a new issue", parameters: [
                    ConnectorActionParam(name: "teamId", description: "Team ID", required: true),
                    ConnectorActionParam(name: "title", description: "Issue title", required: true),
                    ConnectorActionParam(name: "description", description: "Issue description"),
                    ConnectorActionParam(name: "priority", description: "Priority (0=none, 1=urgent, 2=high, 3=medium, 4=low)"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "update_issue", name: "Update issue", description: "Update an existing issue", parameters: [
                    ConnectorActionParam(name: "issueId", description: "Issue ID", required: true),
                    ConnectorActionParam(name: "title", description: "Issue title"),
                    ConnectorActionParam(name: "description", description: "Issue description"),
                    ConnectorActionParam(name: "stateId", description: "State ID"),
                    ConnectorActionParam(name: "priority", description: "Priority (0=none, 1=urgent, 2=high, 3=medium, 4=low)"),
                ], isWriteAction: true),
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
                ConnectorActionDef(id: "create_issue", name: "Create issue", description: "Create a new Jira issue", parameters: [
                    ConnectorActionParam(name: "projectKey", description: "Project key (e.g. PROJ)", required: true),
                    ConnectorActionParam(name: "summary", description: "Issue summary", required: true),
                    ConnectorActionParam(name: "issueType", description: "Issue type (Bug, Task, Story, etc.)", required: true),
                    ConnectorActionParam(name: "description", description: "Issue description"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "add_comment", name: "Add comment", description: "Add a comment to an issue", parameters: [
                    ConnectorActionParam(name: "issueKey", description: "Issue key (e.g. PROJ-123)", required: true),
                    ConnectorActionParam(name: "body", description: "Comment body", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "transition_issue", name: "Transition issue", description: "Change issue status/state", parameters: [
                    ConnectorActionParam(name: "issueKey", description: "Issue key (e.g. PROJ-123)", required: true),
                    ConnectorActionParam(name: "transitionId", description: "Transition ID", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "assign_issue", name: "Assign issue", description: "Assign an issue to a user", parameters: [
                    ConnectorActionParam(name: "issueKey", description: "Issue key (e.g. PROJ-123)", required: true),
                    ConnectorActionParam(name: "accountId", description: "User account ID", required: true),
                ], isWriteAction: true),
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
                ConnectorActionDef(id: "create_page", name: "Create page", description: "Create a new page", parameters: [
                    ConnectorActionParam(name: "parentId", description: "Parent page or database ID", required: true),
                    ConnectorActionParam(name: "title", description: "Page title", required: true),
                    ConnectorActionParam(name: "content", description: "Page content (Markdown)"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "append_block", name: "Append block", description: "Append content to a block", parameters: [
                    ConnectorActionParam(name: "blockId", description: "Block or page ID", required: true),
                    ConnectorActionParam(name: "content", description: "Content to append", required: true),
                ], isWriteAction: true),
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
                ConnectorActionDef(id: "send_message", name: "Send message", description: "Send a message to a channel", parameters: [
                    ConnectorActionParam(name: "channelId", description: "Channel ID", required: true),
                    ConnectorActionParam(name: "text", description: "Message text", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "reply_to_thread", name: "Reply to thread", description: "Reply to a message thread", parameters: [
                    ConnectorActionParam(name: "channelId", description: "Channel ID", required: true),
                    ConnectorActionParam(name: "threadTs", description: "Thread timestamp", required: true),
                    ConnectorActionParam(name: "text", description: "Reply text", required: true),
                ], isWriteAction: true),
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
                ConnectorActionDef(id: "send_message", name: "Send message", description: "Send a message to a channel", parameters: [
                    ConnectorActionParam(name: "channelId", description: "Channel ID", required: true),
                    ConnectorActionParam(name: "content", description: "Message content", required: true),
                ], isWriteAction: true),
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
                ConnectorActionDef(id: "send_message", name: "Send message", description: "Send a message via the bot", parameters: [
                    ConnectorActionParam(name: "chatId", description: "Chat ID", required: true),
                    ConnectorActionParam(name: "text", description: "Message text", required: true),
                ], isWriteAction: true),
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
                ConnectorActionDef(id: "create_task", name: "Create task", description: "Create a new task", parameters: [
                    ConnectorActionParam(name: "content", description: "Task content/title", required: true),
                    ConnectorActionParam(name: "projectId", description: "Project ID"),
                    ConnectorActionParam(name: "dueString", description: "Due date (e.g. 'tomorrow', '2024-12-31')"),
                    ConnectorActionParam(name: "priority", description: "Priority (1=normal, 2=high, 3=very high, 4=urgent)"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "complete_task", name: "Complete task", description: "Mark a task as completed", parameters: [
                    ConnectorActionParam(name: "taskId", description: "Task ID", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "delete_task", name: "Delete task", description: "Delete a task", parameters: [
                    ConnectorActionParam(name: "taskId", description: "Task ID", required: true),
                ], isWriteAction: true),
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
                ConnectorActionDef(id: "create_card", name: "Create card", description: "Create a new card", parameters: [
                    ConnectorActionParam(name: "listId", description: "List ID", required: true),
                    ConnectorActionParam(name: "name", description: "Card name", required: true),
                    ConnectorActionParam(name: "desc", description: "Card description"),
                ], isWriteAction: true),
                ConnectorActionDef(id: "move_card", name: "Move card", description: "Move a card to a different list", parameters: [
                    ConnectorActionParam(name: "cardId", description: "Card ID", required: true),
                    ConnectorActionParam(name: "listId", description: "Destination list ID", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "archive_card", name: "Archive card", description: "Archive a card", parameters: [
                    ConnectorActionParam(name: "cardId", description: "Card ID", required: true),
                ], isWriteAction: true),
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
                ConnectorActionDef(id: "create_record", name: "Create record", description: "Create a new record in a table", parameters: [
                    ConnectorActionParam(name: "baseId", description: "Base ID", required: true),
                    ConnectorActionParam(name: "tableId", description: "Table ID or name", required: true),
                    ConnectorActionParam(name: "fields", description: "Record fields (JSON object)", required: true),
                ], isWriteAction: true),
                ConnectorActionDef(id: "update_record", name: "Update record", description: "Update an existing record", parameters: [
                    ConnectorActionParam(name: "baseId", description: "Base ID", required: true),
                    ConnectorActionParam(name: "tableId", description: "Table ID or name", required: true),
                    ConnectorActionParam(name: "recordId", description: "Record ID", required: true),
                    ConnectorActionParam(name: "fields", description: "Fields to update (JSON object)", required: true),
                ], isWriteAction: true),
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
                ConnectorActionDef(id: "create_folder", name: "Create folder", description: "Create a new folder", parameters: [
                    ConnectorActionParam(name: "path", description: "Folder path", required: true),
                ], isWriteAction: true),
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
