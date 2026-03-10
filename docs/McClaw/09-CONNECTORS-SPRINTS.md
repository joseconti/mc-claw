# McClaw Connectors — Full Implementation Plan

## Context

McClaw is a wrapper for AI CLIs (Claude, ChatGPT, Gemini, Ollama). CLIs like ChatGPT and Ollama lack access to external services (Gmail, Calendar, GitHub, etc.). The Connectors system turns McClaw into a **data proxy**: McClaw accesses external services and provides the data as plain text to any CLI.

**Key innovation**: McClaw injects a header into each prompt listing the available connectors. The AI can request data with `@fetch(connector.action)`, and McClaw intercepts, executes the API call, and forwards the result. The user can also use `/fetch` manually.

**WordPress/WooCommerce**: Only connects through MCP Content Manager (a commercial plugin by Jose Conti). McClaw detects existing installations and integrates them as a connector. No direct connection to the WordPress REST API is implemented.

---

## Flow Architecture

### Live Chat
```
1. User types a message
2. McClaw automatically prepends a header:
   "[McClaw Connectors] Available data sources:
    - calendar: list_events, get_event, list_calendars
    - gmail: search, read, list_unread
    - github: list_issues, list_prs
    To request data, reply with: @fetch(connector.action, param=value)"
3. CLI receives message + header
4. The AI responds normally OR requests data: @fetch(calendar.list_events, timeMin=2026-03-10)
5. McClaw intercepts @fetch -> calls Google Calendar API -> gets events
6. McClaw forwards the result to the CLI:
   "Result from calendar.list_events:
    - Monday 10: 09:00-10:00 Meeting, 14:00-15:30 Dentist
    - Tuesday 11: 18:00-19:00 Padel
    - Wednesday 12: (no events)..."
7. The AI generates the final response: "You're free at 18:30 on Monday, Wednesday, and Friday"
8. McClaw shows the user the final response
```

### Manual User Command
```
1. User types: /fetch calendar.list_events
2. McClaw executes -> displays result as a system message
3. User asks about those data -> the AI already has them in context
```

### Cron Jobs (Scheduled Tasks)
```
1. Job triggers according to the configured schedule
2. McClaw executes the @fetch commands pre-configured by the user in the editor
3. McClaw builds an enriched prompt: original message + retrieved data
4. Sends the enriched prompt to the CLI
5. AI processes -> result delivered via channel (Slack, WhatsApp, etc.)
```

### Enrichment Engine Rules
- Maximum loop of 3 @fetch rounds per message (prevents infinite loops)
- Truncation limit: 4000 characters per connector result (configurable)
- If a connector fails: include the error message in the result, don't fail everything
- Credentials NEVER appear in prompts, logs, or config files

---

## Connectors (23 total)

### Google (OAuth 2.0 — a single consent grants access to multiple services)
| Connector | Actions | API |
|-----------|---------|-----|
| Gmail | search, read, list_unread, list_labels | Gmail API v1 |
| Google Calendar | list_events, get_event, list_calendars | Calendar API v3 |
| Google Drive | search, list_recent, get_file_metadata | Drive API v3 |
| Google Sheets | read_range, list_sheets | Sheets API v4 |
| Google Contacts | search, list_groups | People API v1 |

### Microsoft (OAuth 2.0 via Graph API — a single token)
| Connector | Actions | API |
|-----------|---------|-----|
| Outlook Mail | list_messages, read_message, search, list_folders | Graph /me/messages |
| Outlook Calendar | list_events, get_event, list_calendars | Graph /me/events |
| OneDrive | list_recent, search, get_item | Graph /me/drive |
| Microsoft To Do | list_tasks, list_lists, get_task | Graph /me/todo |

### Development (OAuth / PAT)
| Connector | Auth | Actions |
|-----------|------|---------|
| GitHub | OAuth or PAT | list_issues, list_prs, list_repos, search_code, get_notifications |
| GitLab | OAuth or PAT | list_issues, list_mrs, list_projects |
| Linear | OAuth | list_issues, list_projects, my_assigned |
| Jira | Atlassian OAuth | list_issues, search_jql, my_assigned |
| Notion | Internal OAuth | search, list_databases, query_database |

### Communication (Bot Token)
| Connector | Auth | Actions |
|-----------|------|---------|
| Slack | Bot Token | list_channels, read_channel, search_messages |
| Discord | Bot Token | list_guilds, list_channels, read_channel |
| Telegram | Bot Token | get_updates, get_chat_history, get_me |

### Productivity (API Key / Token)
| Connector | Auth | Actions |
|-----------|------|---------|
| Todoist | API Token | list_tasks, list_projects, get_task |
| Trello | API Key + Token | list_boards, list_cards, list_lists |
| Airtable | PAT | list_records, list_bases, get_record |
| Dropbox | OAuth | list_files, search, get_metadata |

### Utilities
| Connector | Auth | Actions |
|-----------|------|---------|
| Weather | API Key (OpenWeatherMap) | current, forecast, alerts |
| RSS/Feeds | None | fetch_feed, list_entries |
| Generic Webhook | URL + optional secret | call (configurable GET/POST) |

### WordPress / WooCommerce (via MCP Content Manager)
- Does NOT call the WordPress REST API directly
- Detects MCP Content Manager installations in MCP configs (~/.claude/mcp.json, ~/.gemini/settings.json)
- Bridges to existing plugin abilities
- Actions: list_posts, list_products, list_orders, site_health, list_pages
- If MCP Content Manager is not detected: shows a link to get it

---

## Files to Create

```
McClaw/Sources/McClaw/
  Models/Connectors/
    ConnectorModels.swift                    # Sprint 11
  Services/Connectors/
    ConnectorProtocol.swift                  # Sprint 11
    ConnectorStore.swift                     # Sprint 11
    ConnectorRegistry.swift                  # Sprint 11
    ConnectorExecutor.swift                  # Sprint 12
    PromptEnrichmentService.swift            # Sprint 17
    Auth/
      KeychainService.swift                  # Sprint 11
      OAuthService.swift                     # Sprint 12
    Providers/
      GoogleProviders.swift                  # Sprint 12
      DevProviders.swift                     # Sprint 13
      CommunicationProviders.swift           # Sprint 14
      MicrosoftProviders.swift               # Sprint 15
      ProductivityProviders.swift            # Sprint 16
      UtilityProviders.swift                 # Sprint 16
      WordPressProvider.swift                # Sprint 18
  Views/Settings/
    ConnectorsSettingsTab.swift              # Sprint 11
    ConnectorDetailView.swift               # Sprint 12
    ConnectorActionPicker.swift             # Sprint 17
McClaw/Sources/McClawKit/
    ConnectorsKit.swift                      # Sprint 11
docs/McClaw/
    09-CONNECTORS.md                         # Sprint 20
```

## Files to Modify

| File | Sprint | Change |
|------|--------|--------|
| Views/Settings/SettingsWindow.swift | 11 | Add .connectors to SettingsSection enum and integrationSections |
| Infrastructure/Config/ConfigStore.swift | 11 | Add connectors directory to ensureDirectories() |
| Services/CLIBridge/CLIBridge.swift | 17 | Inject connectors header + intercept @fetch in responses |
| Views/Chat/ChatViewModel.swift | 17 | Manual /fetch command from the user |
| Services/Cron/CronJobsStore.swift | 17 | Enrichment before sending task to CLI |
| Models/Cron/CronModels.swift | 17 | connectorBindings in CronPayload.agentTurn |
| Views/Settings/CronJobEditor.swift | 17 | New "Data Sources" GroupBox with connector picker |

## Dependencies

No new SPM dependencies are needed. Everything uses Apple frameworks:
- `URLSession` — HTTP calls to APIs
- `Security` — Keychain for credentials
- `AuthenticationServices` — ASWebAuthenticationSession for OAuth
- All available on macOS 15+

---

## Sprint 11: Connectors Core Architecture

**Goal**: Models, store, keychain, registry, settings tab, protocol. No real API calls yet — infrastructure only.

### 11.1 ConnectorModels.swift
- **File**: `McClaw/Sources/McClaw/Models/Connectors/ConnectorModels.swift`
- **Change**: Define all system types:
  - `ConnectorCategory` enum: google, microsoft, dev, communication, productivity, utilities, wordpress
  - `ConnectorAuthType` enum: oauth2, apiKey, botToken, pat, mcpBridge, none
  - `OAuthConfig` struct: authUrl, tokenUrl, scopes, redirectScheme
  - `ConnectorDefinition` struct: id, category, name, description, icon (SF Symbol), authType, oauthConfig, actions, requiredScopes — static definition of what a connector can do
  - `ConnectorInstance` struct: id, definitionId, name, isConnected, lastSyncAt, lastError, config:[String:String] — user-configured instance (credentials in Keychain, NOT here)
  - `ConnectorActionDef` struct: id, name, description, parameters
  - `ConnectorActionResult` struct: data (String), metadata, timestamp
  - `ConnectorCredentials` struct: accessToken, refreshToken, apiKey, expiresAt
  - `ConnectorBinding` struct: connectorInstanceId, actionId, params, outputFormat — for pre-configuring in cron jobs

### 11.2 KeychainService.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/Auth/KeychainService.swift`
- **Change**: Actor wrapping the Security framework for credential CRUD
  - `save(service:account:data:)` -> SecItemAdd
  - `load(service:account:) -> Data?` -> SecItemCopyMatching
  - `update(service:account:data:)` -> SecItemUpdate
  - `delete(service:account:)` -> SecItemDelete
  - High-level helpers: `saveCredentials(instanceId:credentials:)`, `loadCredentials(instanceId:) -> ConnectorCredentials?`, `deleteCredentials(instanceId:)`
  - Service name pattern: `ai.mcclaw.connector.{instanceId}`
  - Access control: `.whenUnlockedThisDeviceOnly`

### 11.3 ConnectorProtocol.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/ConnectorProtocol.swift`
- **Change**: Protocol that each provider implements:
  ```swift
  protocol ConnectorProvider: Sendable {
      static var definitionId: String { get }
      func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult
      func testConnection(credentials: ConnectorCredentials) async throws -> Bool
      func refreshTokenIfNeeded(credentials: ConnectorCredentials) async throws -> ConnectorCredentials?
  }
  ```

### 11.4 ConnectorRegistry.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/ConnectorRegistry.swift`
- **Change**: Static registry of all 23 connector definitions
  - `static let definitions: [ConnectorDefinition]` — all definitions with their actions
  - `static func definition(for id: String) -> ConnectorDefinition?`
  - `static func definitions(for category: ConnectorCategory) -> [ConnectorDefinition]`
  - Only defines metadata, does NOT implement API calls (that goes in Providers)

### 11.5 ConnectorStore.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/ConnectorStore.swift`
- **Change**: `@MainActor @Observable` singleton (same pattern as CronJobsStore)
  - `static let shared = ConnectorStore()`
  - `var instances: [ConnectorInstance]` — user-configured instances
  - `var selectedInstanceId: String?` — UI selection
  - `var lastError: String?`
  - CRUD: `addInstance(definitionId:)`, `removeInstance(id:)`, `updateInstance(_:)`
  - `connectedInstances() -> [ConnectorInstance]` — only connected ones
  - `buildConnectorsHeader() -> String?` — generates the header to inject into prompts (nil if no active connectors)
  - Persistence in `~/.mcclaw/connectors.json` (separate from main config)
  - Load on start(), save after each change

### 11.6 ConnectorsSettingsTab.swift
- **File**: `McClaw/Sources/McClaw/Views/Settings/ConnectorsSettingsTab.swift`
- **Change**: Settings view for managing connectors
  - Layout: list grouped by category (Google, Microsoft, Dev, Communication, Productivity, Utilities, WordPress)
  - Each connector shows: SF Symbol icon, name, status badge (connected green / disconnected gray)
  - On selection: detail panel (placeholder for now, implemented in Sprint 12)
  - WordPress section with special text about MCP Content Manager

### 11.7 SettingsWindow.swift (modify)
- **File**: `McClaw/Sources/McClaw/Views/Settings/SettingsWindow.swift`
- **Change**: Add `.connectors` case to the `SettingsSection` enum
  - Add to `integrationSections` array
  - Icon: `"cable.connector"` or `"link"`
  - Label: "Connectors"
  - Add case in `settingsContent` @ViewBuilder switch -> `ConnectorsSettingsTab()`

### 11.8 ConfigStore.swift (modify)
- **File**: `McClaw/Sources/McClaw/Infrastructure/Config/ConfigStore.swift`
- **Change**: Add `"connectors"` to the directories array in `ensureDirectories()`

### 11.9 ConnectorsKit.swift
- **File**: `McClaw/Sources/McClawKit/ConnectorsKit.swift`
- **Change**: Pure testable logic in McClawKit:
  - `parseFetchCommand(_ text: String) -> (connector: String, action: String, params: [String:String])?` — parses `@fetch(connector.action, param=value)`
  - `containsFetchCommand(_ text: String) -> Bool`
  - `buildConnectorsHeader(connectors: [(name: String, actions: [String])]) -> String`
  - `formatActionResult(_ result: String, maxLength: Int) -> String` — smart truncation
  - `validateTokenExpiry(expiresAt: Date) -> Bool`
  - `buildOAuthURL(config: ...) -> URL`

### 11.10 Tests
- Tests for ConnectorsKit: @fetch parsing (valid and invalid cases), header generation, truncation, token validation, OAuth URL building

---

## Sprint 12: Google Connectors (OAuth 2.0)

**Goal**: Complete and functional OAuth 2.0 flow + 5 operational Google connectors.

### 12.1 OAuthService.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/Auth/OAuthService.swift`
- **Change**: Complete OAuth 2.0 service
  - Uses `ASWebAuthenticationSession` from the AuthenticationServices framework
  - Implements PKCE: generates code_verifier (random 43-128 chars), computes code_challenge (SHA256 + base64url)
  - `startOAuthFlow(config: OAuthConfig, instanceId: String) async throws` — opens the system browser
  - Callback via deep link `mcclaw://oauth/callback` (handler already exists from Sprint 10)
  - `exchangeCodeForTokens(code:, config:, codeVerifier:) async throws -> ConnectorCredentials` — POST to tokenUrl
  - `refreshAccessToken(refreshToken:, config:) async throws -> ConnectorCredentials` — automatic refresh
  - Stores tokens in Keychain via KeychainService
  - State parameter validation for CSRF protection

### 12.2 GoogleProviders.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/Providers/GoogleProviders.swift`
- **Change**: Implement ConnectorProvider for each Google service
  - **Shared helper `GoogleAPIClient`**: Authorization Bearer header injection, Google error handling (401 -> refresh, 403 -> insufficient scope, 429 -> rate limit), base URL `https://www.googleapis.com/`
  - **GmailProvider**:
    - `search(q:, maxResults:)` -> GET gmail/v1/users/me/messages?q={q} + batch GET per messageId
    - `read(messageId:)` -> GET gmail/v1/users/me/messages/{id}?format=full
    - `list_unread(maxResults:)` -> search with q=is:unread
    - `list_labels()` -> GET gmail/v1/users/me/labels
  - **GoogleCalendarProvider**:
    - `list_events(timeMin:, timeMax:, calendarId:)` -> GET calendar/v3/calendars/{id}/events
    - `get_event(eventId:, calendarId:)` -> GET calendar/v3/calendars/{id}/events/{eventId}
    - `list_calendars()` -> GET calendar/v3/users/me/calendarList
  - **GoogleDriveProvider**:
    - `search(q:)` -> GET drive/v3/files?q={q}
    - `list_recent(maxResults:)` -> GET drive/v3/files?orderBy=modifiedTime desc
    - `get_file_metadata(fileId:)` -> GET drive/v3/files/{fileId}
  - **GoogleSheetsProvider**:
    - `read_range(spreadsheetId:, range:)` -> GET sheets/v4/spreadsheets/{id}/values/{range}
    - `list_sheets(spreadsheetId:)` -> GET sheets/v4/spreadsheets/{id}
  - **GoogleContactsProvider**:
    - `search(query:)` -> GET people/v1/people:searchContacts?query={query}
    - `list_groups()` -> GET people/v1/contactGroups
  - Required OAuth scopes: gmail.readonly, calendar.readonly, drive.readonly, spreadsheets.readonly, contacts.readonly

### 12.3 ConnectorExecutor.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/ConnectorExecutor.swift`
- **Change**: Actor that dispatches action executions
  - `static let shared = ConnectorExecutor()`
  - `execute(instanceId:, actionId:, params:) async throws -> ConnectorActionResult`
  - Flow: load credentials from Keychain -> check expiration -> refresh if needed -> dispatch to provider -> return result
  - Provider registry: `[String: any ConnectorProvider]` mapped by definitionId
  - `registerProvider(_ provider: any ConnectorProvider)`
  - Error handling with clear user-facing messages

### 12.4 ConnectorDetailView.swift
- **File**: `McClaw/Sources/McClaw/Views/Settings/ConnectorDetailView.swift`
- **Change**: Detail view for configuring each connector
  - Header: icon + name + status badge
  - **For OAuth**: "Sign in with Google" button (or Microsoft, etc.) that starts OAuthService
  - **For API Key/Token**: SecureField for manual entry
  - Connection indicator: green dot (connected) / red (error) / gray (disconnected)
  - Last sync: timestamp with relative age
  - Last error: if present, in red
  - List of available actions with descriptions
  - "Test Connection" button -> calls the provider's testConnection()
  - "Disconnect" button -> deletes credentials from Keychain + marks as disconnected
  - Provider-specific configuration (e.g.: default calendar, inbox filter)

### 12.5 Tests
- Parsing of Google API JSON responses (mock responses)
- OAuth URL building with PKCE
- Token refresh logic
- ConnectorExecutor dispatch

---

## Sprint 13: Development Connectors

**Goal**: GitHub, GitLab, Linear, Jira, Notion. Mix of OAuth and PAT (Personal Access Token).

### 13.1 DevProviders.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/Providers/DevProviders.swift`
- **Change**: Implement providers
  - **GitHubProvider** (OAuth App or PAT):
    - `list_issues(repo:, state:, labels:)` -> GET /repos/{owner}/{repo}/issues
    - `list_prs(repo:, state:)` -> GET /repos/{owner}/{repo}/pulls
    - `list_repos(sort:)` -> GET /user/repos
    - `search_code(query:)` -> GET /search/code?q={query}
    - `get_notifications(all:)` -> GET /notifications
    - Base URL: `https://api.github.com/`
    - Auth: `Authorization: Bearer {token}` or `token {pat}`
  - **GitLabProvider** (OAuth or PAT):
    - `list_issues(projectId:, state:)` -> GET /projects/{id}/issues
    - `list_mrs(projectId:, state:)` -> GET /projects/{id}/merge_requests
    - `list_projects(membership:)` -> GET /projects?membership=true
    - Base URL: `https://gitlab.com/api/v4/`
    - Auth: `PRIVATE-TOKEN: {pat}` or `Authorization: Bearer {token}`
  - **LinearProvider** (OAuth):
    - `list_issues(teamId:, state:)` -> GraphQL query
    - `list_projects()` -> GraphQL query
    - `my_assigned()` -> GraphQL query with filter assignedTo=me
    - Base URL: `https://api.linear.app/graphql`
  - **JiraProvider** (Atlassian OAuth or API Token):
    - `list_issues(projectKey:, status:)` -> GET /rest/api/3/search?jql=project={key}
    - `search_jql(jql:)` -> GET /rest/api/3/search?jql={jql}
    - `my_assigned()` -> search with jql=assignee=currentUser()
    - Base URL: `https://{domain}.atlassian.net`
    - Auth: Basic (email:apiToken) or OAuth
  - **NotionProvider** (Internal OAuth Integration):
    - `search(query:)` -> POST /v1/search
    - `list_databases()` -> POST /v1/search with filter type=database
    - `query_database(databaseId:, filter:)` -> POST /v1/databases/{id}/query
    - Base URL: `https://api.notion.com/`
    - Auth: `Authorization: Bearer {secret}`, `Notion-Version: 2022-06-28`

### 13.2 OAuthService.swift (extend)
- Add OAuthConfig for each provider: GitHub, GitLab, Linear, Jira, Notion
- Each has its own authUrl, tokenUrl, and scopes

### 13.3 ConnectorDetailView.swift (extend)
- For connectors that support both OAuth AND PAT (GitHub, GitLab, Jira): show tabs or segmented control
  - Tab "OAuth": sign-in button
  - Tab "Token": SecureField for pasting PAT manually
- "Validate Token" button that calls testConnection()
- Additional fields per provider: GitLab domain, Jira domain, etc.

### 13.4 Tests
- Parsing of GitHub REST API, GitLab API, Linear GraphQL, Jira, and Notion responses
- PAT format validation

---

## Sprint 14: Communication Connectors

**Goal**: Slack, Discord, Telegram via Bot Tokens.

### 14.1 CommunicationProviders.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/Providers/CommunicationProviders.swift`
- **Change**: Implement providers
  - **SlackProvider** (Bot Token):
    - `list_channels(types:)` -> GET /api/conversations.list
    - `read_channel(channelId:, limit:)` -> GET /api/conversations.history
    - `search_messages(query:)` -> GET /api/search.messages
    - Base URL: `https://slack.com`
    - Auth: `Authorization: Bearer xoxb-{token}`
    - On validation: shows workspace name (auth.test)
  - **DiscordProvider** (Bot Token):
    - `list_guilds()` -> GET /api/v10/users/@me/guilds
    - `list_channels(guildId:)` -> GET /api/v10/guilds/{id}/channels
    - `read_channel(channelId:, limit:)` -> GET /api/v10/channels/{id}/messages
    - Base URL: `https://discord.com`
    - Auth: `Authorization: Bot {token}`
    - On validation: shows bot name (users/@me)
  - **TelegramProvider** (Bot Token from BotFather):
    - `get_updates(limit:, offset:)` -> GET /bot{token}/getUpdates
    - `get_chat_history(chatId:, limit:)` -> Not directly available via Bot API (note: Telegram Bot API does not allow reading full history, only recent updates)
    - `get_me()` -> GET /bot{token}/getMe
    - Base URL: `https://api.telegram.org`
    - On validation: shows bot name (getMe)

### 14.2 Bot Token UI
- SecureField for entering the token
- After entry: "Validate" button that calls testConnection()
- If valid: shows bot/workspace info (name, avatar if available)
- If invalid: clear error message

### 14.3 Informational Note in UI About Connectors vs Channels
- Show informational text in the section:
  - "Connectors READ data from these services to provide context to the AI"
  - "Channels (configured in the Channels section) SEND response messages"
  - "They are complementary — you can have Slack as both a connector and a channel"

### 14.4 Tests
- Parsing of Slack, Discord, and Telegram responses
- Token format validation

---

## Sprint 15: Microsoft Connectors (Graph API)

**Goal**: Outlook Mail, Outlook Calendar, OneDrive, Microsoft To Do via Microsoft Graph.

### 15.1 MicrosoftProviders.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/Providers/MicrosoftProviders.swift`
- **Change**: Implement providers via Microsoft Graph API v1.0
  - **Shared helper `MicrosoftGraphClient`**: auth header, error handling, base URL `https://graph.microsoft.com/v1.0/`
  - **OutlookMailProvider**:
    - `list_messages(folder:, top:)` -> GET /me/messages?$top={n}&$orderby=receivedDateTime desc
    - `read_message(messageId:)` -> GET /me/messages/{id}
    - `search(query:)` -> GET /me/messages?$search="{query}"
    - `list_folders()` -> GET /me/mailFolders
  - **OutlookCalendarProvider**:
    - `list_events(startDateTime:, endDateTime:)` -> GET /me/calendarview?startDateTime={}&endDateTime={}
    - `get_event(eventId:)` -> GET /me/events/{id}
    - `list_calendars()` -> GET /me/calendars
  - **OneDriveProvider**:
    - `list_recent()` -> GET /me/drive/recent
    - `search(query:)` -> GET /me/drive/root/search(q='{query}')
    - `get_item(itemId:)` -> GET /me/drive/items/{id}
  - **MicrosoftToDoProvider**:
    - `list_tasks(listId:)` -> GET /me/todo/lists/{id}/tasks
    - `list_lists()` -> GET /me/todo/lists
    - `get_task(listId:, taskId:)` -> GET /me/todo/lists/{listId}/tasks/{taskId}

### 15.2 OAuthService.swift (extend)
- Azure AD OAuth 2.0 endpoint: `https://login.microsoftonline.com/common/oauth2/v2.0/authorize`
- Token endpoint: `https://login.microsoftonline.com/common/oauth2/v2.0/token`
- Scopes: `Mail.Read Calendars.Read Files.Read Tasks.Read offline_access`
- Token refresh with standard Microsoft flow (uses offline_access for refresh_token)

### 15.3 Tests
- Parsing of Graph API responses (mock JSON)
- OAuth flow with Microsoft endpoints

---

## Sprint 16: Productivity + Utilities Connectors

**Goal**: Todoist, Trello, Airtable, Dropbox, Weather, RSS, Webhook.

### 16.1 ProductivityProviders.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/Providers/ProductivityProviders.swift`
- **Change**:
  - **TodoistProvider** (API Token):
    - `list_tasks(projectId:, filter:)` -> GET /rest/v2/tasks
    - `list_projects()` -> GET /rest/v2/projects
    - `get_task(taskId:)` -> GET /rest/v2/tasks/{id}
    - Base URL: `https://api.todoist.com`
    - Auth: `Authorization: Bearer {token}`
  - **TrelloProvider** (API Key + Token):
    - `list_boards()` -> GET /1/members/me/boards?key={key}&token={token}
    - `list_cards(boardId:, listId:)` -> GET /1/lists/{id}/cards
    - `list_lists(boardId:)` -> GET /1/boards/{id}/lists
    - Base URL: `https://api.trello.com`
    - Auth: query params key + token
  - **AirtableProvider** (PAT):
    - `list_records(baseId:, tableId:)` -> GET /v0/{baseId}/{tableId}
    - `list_bases()` -> GET /v0/meta/bases
    - `get_record(baseId:, tableId:, recordId:)` -> GET /v0/{baseId}/{tableId}/{recordId}
    - Base URL: `https://api.airtable.com`
    - Auth: `Authorization: Bearer {pat}`
  - **DropboxProvider** (OAuth):
    - `list_files(path:)` -> POST /2/files/list_folder
    - `search(query:)` -> POST /2/files/search_v2
    - `get_metadata(path:)` -> POST /2/files/get_metadata
    - Base URL: `https://api.dropboxapi.com`
    - Auth: `Authorization: Bearer {token}`

### 16.2 UtilityProviders.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/Providers/UtilityProviders.swift`
- **Change**:
  - **WeatherProvider** (OpenWeatherMap API Key):
    - `current(city:)` -> GET /data/2.5/weather?q={city}&appid={key}&units=metric
    - `forecast(city:, days:)` -> GET /data/2.5/forecast?q={city}&appid={key}&units=metric
    - `alerts(lat:, lon:)` -> GET /data/3.0/onecall?lat={}&lon={}&exclude=minutely,hourly&appid={key}
    - Base URL: `https://api.openweathermap.org`
  - **RSSProvider** (no auth):
    - `fetch_feed(url:)` -> GET {url} -> parse XML/Atom
    - `list_entries(url:, maxEntries:)` -> fetch + parse + limit
    - Uses Foundation's XMLParser
    - Extracts: title, link, description, pubDate per entry
  - **WebhookProvider** (configurable):
    - `call(url:, method:, headers:, body:)` -> configurable HTTP request
    - Supports GET and POST
    - Optional custom headers
    - Optional body (JSON string)
    - Returns response body as text

### 16.3 Tests
- Parsing for each provider
- RSS XML parsing
- Webhook request building

---

## Sprint 17: Prompt Enrichment Engine

**Goal**: This is the key sprint. It connects the connectors with chat and cron. Makes everything work end-to-end.

### 17.1 PromptEnrichmentService.swift
- **File**: `McClaw/Sources/McClaw/Services/Connectors/PromptEnrichmentService.swift`
- **Change**: Enrichment coordinator service
  - `@MainActor @Observable` (needs access to ConnectorStore)
  - `static let shared = PromptEnrichmentService()`
  - **`buildConnectorsHeader() -> String?`**
    - Reads active connectors from ConnectorStore
    - For each one, lists its available actions
    - Generates the header:
      ```
      [McClaw Connectors] Available data sources:
      - gmail: search, read, list_unread, list_labels
      - calendar: list_events, get_event, list_calendars
      To request data, reply with: @fetch(connector.action, param=value)
      ```
    - Returns nil if there are no active connectors
  - **`parseAndExecuteFetch(response: String) async throws -> (cleanResponse: String, fetchResults: String?)`**
    - Looks for `@fetch(...)` in the AI's response
    - If found: executes via ConnectorExecutor, formats the result
    - Returns the clean response (without @fetch) + the retrieved results
  - **`enrichForCronJob(message: String, bindings: [ConnectorBinding]) async throws -> String`**
    - Executes each pre-configured binding
    - Builds an enriched prompt: original message + all retrieved data
  - **Rules**:
    - Maximum 3 @fetch rounds per conversation (anti-loop)
    - Truncation to 4000 chars per result (configurable)
    - If a connector fails: includes the error as text, does not fail the entire job

### 17.2 CLIBridge.swift (modify)
- **File**: `McClaw/Sources/McClaw/Services/CLIBridge/CLIBridge.swift`
- **Change**: Integrate enrichment into the send flow
  - Before sending a message: prepend the connectors header (if there are active connectors)
  - After receiving the complete response: look for @fetch commands
  - If @fetch is found: execute -> forward the result as a new message -> wait for the final response
  - Round counter to prevent infinite loops (max 3)
  - The header is only injected in the first message, not in fetch re-sends

### 17.3 ChatViewModel.swift (modify)
- **File**: `McClaw/Sources/McClaw/Views/Chat/ChatViewModel.swift`
- **Change**: Support for manual /fetch and visual feedback
  - Command `/fetch connector.action param=value` — user manually requests data
  - Result is displayed as a system message in the chat (type .system or .info)
  - Visual indicator "Fetching data from Gmail..." when McClaw is executing a @fetch
  - Intermediate @fetch messages are not shown to the user (only the AI's final response)

### 17.4 CronJobsStore.swift (modify)
- **File**: `McClaw/Sources/McClaw/Services/Cron/CronJobsStore.swift`
- **Change**: Enrichment before sending a scheduled task
  - When a cron job fires and has connectorBindings:
    1. Calls `PromptEnrichmentService.enrichForCronJob(message:bindings:)`
    2. Receives the enriched prompt with real data
    3. Sends the enriched prompt to the CLI (instead of the original message)
  - If no bindings: current behavior unchanged

### 17.5 CronModels.swift (modify)
- **File**: `McClaw/Sources/McClaw/Models/Cron/CronModels.swift`
- **Change**: Add optional field to CronPayload
  - In `CronPayload.agentTurn`: add `connectorBindings: [ConnectorBinding]?`
  - ConnectorBinding already defined in ConnectorModels.swift (Sprint 11)

### 17.6 CronJobEditor.swift (modify)
- **File**: `McClaw/Sources/McClaw/Views/Settings/CronJobEditor.swift`
- **Change**: New "Data Sources" GroupBox in the task editor
  - Only visible if there are active connectors
  - List of connected connectors with checkbox to enable/disable
  - On enabling a connector: action picker (e.g.: gmail -> search / read / list_unread)
  - Optional parameter fields per action
  - Preview: text showing what data will be fetched
  - Bindings are saved in the CronPayload

### 17.7 ConnectorActionPicker.swift
- **File**: `McClaw/Sources/McClaw/Views/Settings/ConnectorActionPicker.swift`
- **Change**: Reusable component
  - Connector picker -> action picker -> parameter fields
  - Used in both CronJobEditor and potentially other places

### 17.8 ConnectorsKit.swift (extend)
- Extend with:
  - `parseFetchCommand()` improved with complex parameter support
  - `buildEnrichedPrompt(original:, results:) -> String` — combines message + results
  - `detectFetchInResponse(_ text: String) -> [FetchCommand]` — extracts all @fetch commands from a response

### 17.9 Tests
- Parsing of @fetch with complex parameters
- Header generation with multiple connectors
- Enrichment with mocks (simulate connector responses)
- Loop detection (verify it stops at 3 rounds)
- Truncation of long results

---

## Sprint 18: MCP Content Manager Connector (WordPress/WooCommerce)

**Goal**: Full integration with MCP Content Manager via a built-in abilities catalog. Does NOT access the WordPress REST API directly. McClaw knows the ~275 abilities of the plugin and organizes them into 13 themed sub-connectors.

### 18.1 MCMAbilitiesCatalog.swift ✅
- **File**: `McClaw/Sources/McClawKit/MCMAbilitiesCatalog.swift`
- **Change**: Complete catalog of pre-cataloged abilities (pure, testable, no side effects)
  - Types: `MCMAbility`, `MCMParam`, `MCMSubConnector`
  - 13 sub-connectors organized by functional domain:
    | Sub-connector | Domain | Abilities |
    |---|---|---|
    | `wp.content` | CRUD, taxonomy, comments, revisions, blocks, fields, import/export | ~31 |
    | `wp.media` | Media library, analysis, AI image gen | ~11 |
    | `wp.woocommerce` | Products, orders, customers, coupons, analytics, attributes, webhooks | ~65 |
    | `wp.security` | Audit, hardening, malware scan, cleanup | ~21 |
    | `wp.themes` | Global styles, templates, FSE, fonts, inspector tasks | ~37 |
    | `wp.system` | Health, plugins, updates, snapshots, cache, WP-CLI, profiler, optimizer | ~51 |
    | `wp.users` | Users, roles, capabilities, app passwords, GDPR | ~23 |
    | `wp.seo` | SEO meta, redirects, analytics, content audit | ~5 |
    | `wp.database` | Options, transients, queries, indexes | ~11 |
    | `wp.navigation` | Classic + FSE menus, widgets | ~8 |
    | `wp.config` | wp-config, htaccess, permalinks, multisite | ~8 |
    | `wp.automation` | Batch execute, action log, search everything | ~3 |
    | `wp.vigia` | AI crawler monitoring/blocking (VigIA) | ~9 |
  - Each ability with typed parameters: name, type (string/integer/boolean), description, required, defaultValue, enumValues
  - `requiresConfirmation` flag on destructive operations
  - Helpers: `ability(for:)`, `subConnector(for:)`, `search(_:)`, `totalAbilities`
  - Source: `abilities-catalog.md` v2.5.0

### 18.2 ConnectorRegistry.swift (modify) ✅
- **File**: `McClaw/Sources/McClaw/Services/Connectors/ConnectorRegistry.swift`
- **Change**: Replace the single `wp.mcp` connector (5 hardcoded actions) with dynamic mapping from MCMAbilitiesCatalog
  - `import McClawKit`
  - `static let wordpress` now maps `MCMAbilitiesCatalog.subConnectors` -> `[ConnectorDefinition]`
  - Each sub-connector becomes a `ConnectorDefinition` with authType `.mcpBridge`
  - Abilities become `ConnectorActionDef` with their `ConnectorActionParam`
  - Result: 13 ConnectorDefinitions in the `.wordpress` category instead of 1

### 18.3 Tests ✅
- **File**: `McClaw/Tests/McClawKitTests/MCMAbilitiesCatalogTests.swift`
- 17 tests covering:
  - Catalog version
  - Sub-connector count (13)
  - Total abilities (250+)
  - `wp.` prefix on all IDs
  - Unique IDs (sub-connectors and abilities)
  - Non-empty metadata (name, description)
  - Required parameters correctly marked
  - Enum values in status-type params
  - Lookup by ID (ability and sub-connector)
  - Text search (case-insensitive)
  - Confirmation flags on destructive operations
  - Correct grouping of WooCommerce abilities
  - Valid parameter types

### 18.4 WordPressProvider.swift (PENDING)
- **File**: `McClaw/Sources/McClaw/Services/Connectors/Providers/WordPressProvider.swift`
- **Change**: Bridge to MCP Content Manager
  - Detects MCP Content Manager installations by scanning:
    - `~/.claude/mcp.json` (Claude CLI MCP configurations)
    - `~/.gemini/settings.json` (Gemini MCP configurations)
  - Looks for entries containing "mcp-content-manager" or WordPress site URLs with the MCP endpoint
  - Uses the existing MCPConfigManager to read configs
  - Dispatches abilities to the MCP server using the catalog for local parameter validation
  - Benefits of the built-in catalog:
    - **Zero discovery latency**: McClaw already knows everything it can do
    - **Better prompt injection**: can inject only the abilities relevant to the context
    - **UI autocompletion**: the user sees available actions directly
    - **Local validation**: McClaw validates parameters before sending to the server

### 18.5 Special WordPress UI (PENDING)
- In ConnectorsSettingsTab, the WordPress section shows:
  - If MCP Content Manager is detected: list of detected sites with URL and status
  - If NOT detected: explanatory message + button/link "Get MCP Content Manager" -> opens Jose Conti's website
  - Text: "WordPress and WooCommerce connect through MCP Content Manager, the official plugin for AI-powered content management"
  - On connecting a detected site: shows available actions grouped by sub-connector
  - Sub-connector navigation: expandable list with abilities within each group
  - Conditional indicators: WooCommerce, VigIA, Subscriptions (depending on active plugins on the site)

---

## Sprint 19: Testing, Security, Polish

**Goal**: Robustness, security, polished UX, edge cases.

### 19.1 Robust Error Handling
- Retry with exponential backoff for transient errors:
  - HTTP 429 (rate limit) -> wait for Retry-After header or backoff
  - HTTP 500, 502, 503 -> retry up to 3 times with backoff
  - Timeout -> retry once
- Protection against race conditions in token refresh:
  - If two actions request a refresh simultaneously, only one executes the refresh
  - The other waits for the first one's result
- Graceful degradation:
  - If a connector is down, the rest keep working
  - The prompt includes a note "Gmail: temporarily unavailable" instead of failing
- Clear user-facing error messages:
  - "Token expired. Reconnect Gmail in Settings > Connectors"
  - "Access revoked. You need to authorize again"
  - "Rate limit reached. Retrying in {n} seconds"

### 19.2 Rate Limiting
- Per-connector rate limiter: maximum N requests per minute (configurable per provider)
- Google: 100 req/min (default quota)
- GitHub: 5000 req/hour with token
- Usage tracking: `ConnectorUsageTracker` that logs calls per connector/hour
- Automatic exponential backoff on receiving 429

### 19.3 Security
- Keychain: access control `.whenUnlockedThisDeviceOnly` on all credentials
- OAuth: validate state parameter in callback (CSRF protection)
- OAuth: use PKCE in all flows (even if the provider doesn't require it)
- Sanitization of API data before injecting into prompts:
  - Escape any pattern that looks like @fetch() in external data (prevent prompt injection)
  - Limit length of each individual field
  - Strip control characters
- Credentials NEVER in: config JSON, logs, prompts, error messages
- On disconnecting a connector: delete credentials from Keychain immediately

### 19.4 UI Polish
- Connection badges in the Settings sidebar (green/red dot next to "Connectors")
- Active connectors counter: "Connectors (3)"
- Per-connector health indicators in the list
- Last sync timestamps with relative age ("2h ago")
- Data preview before enrichment in cron jobs
- Loading animation when executing a @fetch
- Friendly empty state when no connectors are configured

### 19.5 Comprehensive Tests
- Target: 30+ new tests (minimum)
- Unit tests ConnectorsKit: parsing, formatting, validation, header, truncation
- Integration tests: parsing of real responses from each provider (with mock JSON)
- OAuth tests: URL building, PKCE generation, state validation, token refresh
- Keychain tests: save, load, update, delete, credentials lifecycle
- Prompt enrichment tests: with connector mocks, loop detection, error handling
- CronJob tests: enrichment with bindings, fallback without bindings

---

## Sprint 20: Documentation

### 20.1 docs/McClaw/09-CONNECTORS.md
- **File**: `docs/McClaw/09-CONNECTORS.md`
- **Content**:
  - Connectors system overview
  - Architecture: ConnectorStore, ConnectorExecutor, PromptEnrichmentService
  - Lifecycle: definition -> instance -> configuration -> connection (OAuth/token) -> usage -> disconnection
  - Authentication flows: OAuth 2.0 with PKCE, API Key, Bot Token, PAT, MCP Bridge
  - Prompt enrichment pipeline: header -> @fetch -> execution -> forwarding
  - Security model: Keychain, CSRF, sanitization, no-log
  - Connectors catalog: table with all 23 + their actions
  - Guide for adding new connectors: implement ConnectorProvider, register in Registry

### 20.2 SPRINTS.md
- Add Sprints 11-20 to the master document
- Format identical to Sprints 1-10: title, subtasks, files, changes

### 20.3 In-app Help
- Tooltips in connector settings explaining each section
- Update /help command with:
  - `/fetch connector.action` — manually request data
  - Description of available connectors
- Onboarding text (optional): tip about connectors on the welcome page

### 20.4 00-INDICE.md (update)
- Add reference to 09-CONNECTORS.md document in the index

---

## Sprint Summary

| Sprint | Goal | Connectors | New Tests |
|--------|------|------------|-----------|
| 11 | Core: models, store, keychain, registry, UI shell | 0 (infra) | ~10 |
| 12 | Google: OAuth + Gmail, Calendar, Drive, Sheets, Contacts | 5 | ~10 |
| 13 | Dev: GitHub, GitLab, Linear, Jira, Notion | 5 | ~8 |
| 14 | Communication: Slack, Discord, Telegram | 3 | ~6 |
| 15 | Microsoft: Outlook, Calendar, OneDrive, To Do | 4 | ~6 |
| 16 | Productivity + Utilities: Todoist, Trello, Airtable, Dropbox, Weather, RSS, Webhook | 7 | ~8 |
| 17 | Prompt Enrichment: chat + cron + @fetch integration | 0 (engine) | ~12 |
| 18 | MCM Abilities Catalog (~275 abilities, 13 sub-connectors) + WordPressProvider bridge | 13 | 17 ✅ (catalog) + ~4 (provider) |
| 19 | Testing, security, polish, rate limiting | 0 (polish) | ~30 |
| 20 | Documentation | 0 (docs) | 0 |
| **TOTAL** | | **25** (23 + WordPress multi-site) | **~94** |
