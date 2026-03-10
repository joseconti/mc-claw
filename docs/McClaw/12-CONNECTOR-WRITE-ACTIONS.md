# 12 - Connector Write Actions

## Status: Planned

## Goal

Add write capabilities to connectors so the AI can take actions on behalf of the user (create events, send emails, create tasks, post messages, etc.), not just read data.

---

## Current State

All connectors are **read-only**. They can fetch and list data but cannot create, update, or delete resources.

## Scope

### Phase 1 — Google Write Actions

| Connector | New Actions | OAuth Scope Change |
|-----------|-------------|-------------------|
| Google Calendar | `create_event`, `update_event`, `delete_event`, `find_free_slots` | `calendar.readonly` → `calendar.events` |
| Gmail | `send_email`, `reply_to_email`, `create_draft` | `gmail.readonly` → `gmail.compose` + `gmail.readonly` |
| Google Drive | `upload_file`, `create_folder`, `move_file` | `drive.readonly` → `drive.file` |
| Google Tasks | `create_task`, `complete_task`, `delete_task` | `tasks.readonly` → `tasks` |
| Google Contacts | `create_contact`, `update_contact` | `contacts.readonly` → `contacts` |

### Phase 2 — Microsoft Write Actions

| Connector | New Actions | Scope Change |
|-----------|-------------|-------------|
| Outlook Mail | `send_email`, `reply_to_email`, `create_draft` | Add `Mail.Send` |
| Outlook Calendar | `create_event`, `update_event`, `delete_event` | Add `Calendars.ReadWrite` |
| OneDrive | `upload_file`, `create_folder` | Add `Files.ReadWrite` |
| Microsoft To Do | `create_task`, `complete_task`, `delete_task` | Add `Tasks.ReadWrite` |

### Phase 3 — Dev & Communication Write Actions

| Connector | New Actions |
|-----------|-------------|
| GitHub | `create_issue`, `create_comment`, `create_pr` |
| GitLab | `create_issue`, `create_comment`, `create_mr` |
| Linear | `create_issue`, `update_issue` |
| Jira | `create_issue`, `update_issue`, `add_comment` |
| Notion | `create_page`, `update_page`, `append_block` |
| Slack | `send_message`, `reply_to_thread` |
| Discord | `send_message` |
| Telegram | `send_message` |

### Phase 4 — Productivity Write Actions

| Connector | New Actions |
|-----------|-------------|
| Todoist | `create_task`, `complete_task`, `delete_task` |
| Trello | `create_card`, `move_card`, `archive_card` |
| Airtable | `create_record`, `update_record` |
| Dropbox | `upload_file`, `create_folder` |

---

## Technical Requirements

### 1. GoogleAPIClient — POST/PUT/PATCH/DELETE Support

```swift
// Add to GoogleAPIClient
static func post(path:, body:, credentials:) async throws -> (Data, Int)
static func put(path:, body:, credentials:) async throws -> (Data, Int)
static func patch(path:, body:, credentials:) async throws -> (Data, Int)
static func delete(path:, credentials:) async throws -> (Data, Int)
```

Similar changes needed for Microsoft, GitHub, and other API clients.

### 2. User Confirmation Before Write Actions

Write actions must require explicit user confirmation before execution. The AI should present what it intends to do and wait for approval.

```
ConnectorActionMetadata:
  - isWriteAction: Bool
  - confirmationRequired: Bool
  - description: String (human-readable summary of the action)
```

### 3. OAuth Scope Upgrade

Users with existing read-only connections will need to re-authenticate with broader scopes. The app should:
- Detect when a write action requires upgraded scopes
- Prompt the user to re-authorize
- Preserve existing credentials during the upgrade flow

### 4. ConnectorRegistry Updates

Each connector definition needs updated `actions` list and `oauthConfig` with write scopes.

---

## Example Use Case

**User**: "Find a free slot next week in the afternoon and book a tennis match"

**McClaw flow**:
1. `@fetch google.calendar list_events` → get next week's events
2. AI identifies free afternoon slots
3. AI proposes: "Tuesday 17:00-18:00 is free. Create event 'Tennis Match' on Tuesday 17:00-18:00?"
4. User confirms
5. `@fetch google.calendar create_event` → creates the event
6. AI confirms: "Done! Tennis Match booked for Tuesday 17:00-18:00"

---

## Priority Order

1. **Google Calendar** — most impactful (scheduling use case)
2. **Gmail** — send/reply emails
3. **Todoist / Microsoft To Do** — task creation
4. **Slack** — send messages
5. Rest of connectors

---

## Security Considerations

- All write actions require user confirmation (no silent writes)
- Rate limiting on write actions to prevent accidental mass operations
- Audit log of all write actions performed
- Option to disable write actions globally in settings
- Destructive actions (delete) require double confirmation
