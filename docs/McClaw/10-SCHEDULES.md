# McClaw - Schedules (Scheduled Actions)

## 1. Overview

The **Schedules** section allows the user to set up automatic actions that run with any available AI provider (Claude, Gemini, ChatGPT, Ollama). It is a top-level section in the sidebar, at the same level as Chats, Projects, and Trash.

### Design Principles

- **Visual simplicity**: clean and clear interface inspired by Apple Reminders
- **Power without complexity**: all the power of the scheduling system without overwhelming the user
- **AI selector**: each scheduled action can run with a different AI provider
- **Friendly terminology**: "Schedules" and "scheduled actions" are used throughout the UI, never "cron"

---

## 2. Architecture

### 2.1 Hybrid Backend

McClaw uses a hybrid backend depending on the AI provider:

| Provider | Backend | Mechanism |
|----------|---------|-----------|
| Claude CLI | Native | `claude task list/create/delete` via CLIBridge |
| Gemini, ChatGPT, Ollama | Gateway | WebSocket RPC `cron.*` methods |

The user does not need to know which backend is being used. The interface is identical for all providers.

### 2.2 Data Models

```
CronJob
  +-- id: String
  +-- name: String
  +-- description: String?
  +-- agentId: String?            // ID of the selected AI provider
  +-- enabled: Bool
  +-- schedule: CronSchedule
  |     +-- .at(date)             // One-time execution
  |     +-- .every(ms, anchor?)   // Fixed interval
  |     +-- .cron(expr, tz?)      // Unix cron expression
  +-- sessionTarget: CronSessionTarget
  |     +-- .main                 // Injects into main session
  |     +-- .isolated             // Dedicated session
  +-- wakeMode: CronWakeMode
  |     +-- .now                  // Executes immediately
  |     +-- .nextHeartbeat        // Waits for next heartbeat
  +-- payload: CronPayload
  |     +-- .systemEvent(text)    // Text injected into session
  |     +-- .agentTurn(message, thinking, timeout, ..., connectorBindings)
  +-- delivery: CronDelivery?
  |     +-- mode: none | announce | webhook
  |     +-- channel, to, bestEffort
  +-- state: CronJobState
        +-- nextRunAtMs, lastRunAtMs, lastStatus, lastError
```

### 2.3 Store

`CronJobsStore` is a `@MainActor @Observable` singleton that:

- Automatically detects whether the active provider is Claude (uses native CLI) or another (uses Gateway)
- Polls the active backend every 30 seconds
- Listens for `CronEvent` events from the Gateway via WebSocket
- Persists in `~/.mcclaw/cron/jobs.json` (Gateway) or via `claude task` (Claude CLI)

---

## 3. User Interface

### 3.1 Sidebar Section

Schedules appears as the fourth item in the sidebar:

```
+---------------------------+
|  [+] New Conversation     |
+---------------------------+
|  > Chats                  |
|  > Projects               |
|  > Schedules         (3)  |  <-- badge = active jobs
|  > Trash             (2)  |
+---------------------------+
```

Icon: `calendar.badge.clock` (SF Symbols). The badge shows the number of active (enabled) schedules.

### 3.2 Main View (SchedulesContentView)

List + detail layout, similar to Apple Mail:

```
+---------------------------------------------------------------+
|  Schedules                           [Refresh] [+ New Schedule]|
|  3 active . Next: in 23m                                      |
+---------------------------------------------------------------+
|  [Banner scheduler disabled - only if applicable]             |
+----------------------------+----------------------------------+
|  LIST (260px)              |  DETAIL PANEL                    |
|                            |                                   |
|  ● Daily summary           |  Daily summary                   |
|    Every 1h . in 23m       |  [Toggle] [Run Now] [Edit] [Del] |
|                            |                                   |
|  ● Weekly report           |  Schedule: every 1h              |
|    Mon 9:00 . in 2d        |  AI Provider: Claude             |
|                            |  Session: isolated               |
|  ○ One-time backup         |  Next: Mar 11, 9:00 AM          |
|    Mar 15 . paused         |  Last: Mar 10, 8:00 AM . ok     |
|                            |                                   |
|                            |  "Summarize my inbox and..."     |
|                            |                                   |
|                            |  Run History                     |
|                            |  ● Mar 10 8:00 AM . 2.3s        |
|                            |  ● Mar 10 7:00 AM . 1.8s        |
|                            |  ● Mar 10 6:00 AM . timeout     |
+----------------------------+----------------------------------+
```

### 3.3 Job List

Each row shows:
- **Color dot**: green (active + ok), red (active + error), gray (disabled)
- **Name**: main text in `.subheadline.weight(.medium)`
- **Secondary line**: schedule summary + time until next execution

Context menu: Run Now, Enable/Disable, Edit, Delete.

### 3.4 Detail Panel

When a schedule is selected:
- **Header**: name + on/off toggle + buttons (Run Now, Edit, Delete)
- **Info card**: Schedule, AI Provider, Session, Wake, Next/Last run, Last status, Payload
- **Run History**: list of executions with color dot, date, duration

### 3.5 Schedule Editor (CronJobEditor)

The editor opens as a modal sheet. Sections:

1. **Basics**: Name, Description, **AI Provider** (Picker), Enabled, Session target, Wake mode
2. **Schedule**: Kind (at/every/cron) + specific fields
3. **Payload**: System event or Agent turn with message, thinking, timeout
4. **Data Sources**: Connector bindings for @fetch enrichment (only if connectors exist)

### 3.6 Empty State

When there are no schedules:

```
+-----------------------------------------------+
|                                                |
|          [calendar.badge.clock icon]           |
|                                                |
|          No schedules yet                      |
|                                                |
|   Create scheduled actions to automate         |
|   tasks with any AI provider.                  |
|                                                |
|          [Create Schedule]                     |
|                                                |
+-----------------------------------------------+
```

---

## 4. AI Selector

Each scheduled action can run with a different AI provider. In the editor, the "AI Provider" field shows a Picker with:

| Option | Behavior |
|--------|----------|
| Default (active) | Uses whichever provider is active at execution time |
| Claude | Runs with Claude CLI (native `claude task`) |
| Gemini | Runs with Gemini CLI via Gateway |
| ChatGPT | Runs with ChatGPT CLI via Gateway |
| Ollama | Runs with Ollama CLI via Gateway |

Only installed and detected providers (via `CLIDetector`) are shown. The value is persisted as `agentId` in the `CronJob` model.

---

## 5. Schedule Types

### 5.1 At (One-time Execution)

Runs once at a specific date and time. Option to auto-delete after successful execution.

```
Type: at
Date: 15 Mar 2026, 09:00
Auto-delete: yes/no
```

### 5.2 Every (Fixed Interval)

Repeats every X time. Accepts formats: `10m`, `1h`, `6h`, `1d`.

```
Type: every
Interval: 1h
```

### 5.3 Cron (Unix Expression)

5-field cron expression for advanced scheduling. Optional timezone.

```
Type: cron
Expression: 0 9 * * 3    (every Wednesday at 9:00)
Timezone: Europe/Madrid   (optional)
```

---

## 6. Flows

### 6.1 Create a Schedule

1. Click "New Schedule" (header or empty state)
2. CronJobEditor opens as a sheet
3. Fill in: name, select AI provider, configure schedule, write payload
4. Click "Save"
5. The schedule appears in the list, active

### 6.2 Edit a Schedule

1. Select a schedule in the list
2. Click "Edit" in the detail panel (or context menu)
3. CronJobEditor opens pre-filled
4. Modify and save

### 6.3 Run Manually

1. Select a schedule
2. Click "Run Now" in the detail panel (or context menu)
3. It runs immediately regardless of the schedule

### 6.4 Delete a Schedule

1. Click the trash icon in the detail panel (or context menu "Delete...")
2. Confirmation: "Delete this schedule?"
3. Deleted from the backend

### 6.5 View Execution History

1. Select a schedule
2. The detail panel shows "Run History" with all executions
3. Each entry: color dot (ok/error), date, duration, summary

---

## 7. Integration with Connectors

### 7.1 Data Sources (ConnectorBinding)

Scheduled actions of type `agentTurn` can configure **Data Sources**: data that is pre-fetched from connectors before running the AI.

Example: a schedule that every day at 9:00 summarizes the user's emails:
- Connector: Gmail
- Action: Read recent messages
- The result is automatically injected into the prompt

### 7.2 Prompt Enrichment

`PromptEnrichmentService` processes the bindings before execution:

```
Schedule fires
  -> PromptEnrichmentService.enrichForCronJob()
    -> Executes each ConnectorBinding (Gmail, Calendar, etc.)
    -> Combines results into the message
  -> Sends enriched message to the AI
```

---

## 8. McClaw's Approach to Schedules

| Aspect | Gateway Raw API | McClaw |
|--------|-----------------|--------|
| **Location** | Settings tab | Top-level sidebar |
| **Terminology** | "Cron" | "Schedules" |
| **AI Selector** | Manual Agent ID | Visual provider picker |
| **Claude Backend** | Gateway cron | Native `claude task` (via CLI Bridge) |
| **Other Backends** | Gateway cron | Gateway cron (identical) |
| **UI** | Settings tab (list+detail) | Main view (simplified list+detail) |
| **Empty state** | Plain text | Dedicated view with icon and CTA |

---

## 9. Relevant Files

| File | Description |
|------|-------------|
| `Views/Chat/SchedulesContentView.swift` | Main Schedules view (sidebar section) |
| `Views/Chat/ChatSidebar.swift` | Sidebar with Schedules nav item |
| `Views/Chat/ChatWindow.swift` | Router connecting .schedules to SchedulesContentView |
| `Views/Settings/CronJobEditor.swift` | Schedule editor (modal sheet) |
| `Models/Cron/CronModels.swift` | CronJob, CronSchedule, CronPayload, CronDelivery |
| `Services/Cron/CronJobsStore.swift` | Singleton store with hybrid backend |
| `Services/Cron/WebhookReceiver.swift` | Webhook receiver for delivery |
