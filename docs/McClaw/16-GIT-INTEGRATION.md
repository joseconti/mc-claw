# 16 - Git Integration

## Status: Planned

## Goal

Add a dedicated **Git section** in McClaw's sidebar where the user can browse repositories from connected platforms (GitHub, GitLab), interact with them through the AI chat, and perform both read and write Git operations — all assisted by the selected AI provider.

---

## Design Principles

- **AI-first interaction**: the primary way to operate on repos is through the chat. The AI executes Git actions on behalf of the user.
- **Platform + local**: combines platform API actions (via existing Connectors) with local `git` CLI operations (via a new `GitService`).
- **Consistent patterns**: reuses the CLI selector pill, chat layout, connector infrastructure, and write-action confirmation flow already present in McClaw.
- **Progressive disclosure**: the repo list is simple by default; drill-down into branches, PRs, and commits is available on demand.

---

## Prerequisites

- GitHub and/or GitLab connectors configured and connected (Settings > Connectors).
- `git` CLI installed on the user's machine (pre-installed on macOS).
- For local operations: repos must be cloned on disk (GitService can clone them).

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Git Section (UI)                      │
│  ┌──────────────┐  ┌──────────────┐                     │
│  │ CLI Selector  │  │ Platform     │    ← Top bar       │
│  │ (AI provider) │  │ Selector     │                     │
│  └──────────────┘  └──────────────┘                     │
│  ┌─────────────────────────────────────────────────────┐│
│  │              Chat (with Git context)                 ││
│  │  ┌─────────────────────────────────┐                ││
│  │  │ [acme-api / main]  ← context chip               ││
│  │  └─────────────────────────────────┘                ││
│  └─────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────┐│
│  │              Repository Panel                        ││
│  │  search + filter                                     ││
│  │  ┌──────────────────────────────────────────────┐   ││
│  │  │ repo-1    ★  Swift   3 PRs   2h ago          │   ││
│  │  │ repo-2       Python  1 PR    1d ago          │   ││
│  │  │ repo-3       TS      —       5d ago          │   ││
│  │  └──────────────────────────────────────────────┘   ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### Service Layers

```
GitPanelView / GitRepoListView / GitRepoDetailView
    ↓
GitPanelViewModel (@Observable @MainActor)
    ↓
GitService (actor) ─── local git operations via Process
    ↓
ConnectorStore ─── platform API operations (GitHub/GitLab connectors)
```

---

## 2. Settings Toggle

In Settings > General, add a toggle:

```
Git Section
[Toggle] Show Git section in sidebar

When enabled, a "Git" item appears in the sidebar.
Requires at least one Git connector (GitHub or GitLab) to be connected.
If no connector is connected, show an inline hint linking to Settings > Connectors.
```

**AppState addition**:
```swift
var gitSectionEnabled: Bool = false
```

**SidebarSection addition**:
```swift
case git
```

Sidebar icon: `chevron.left.forwardslash.chevron.right` (SF Symbols). Badge shows total open PRs across connected platforms (optional, can be deferred).

---

## 3. Top Bar Layout

The top bar of the Git section has two selectors, separated by a flexible spacer, aligned on the same row:

### 3.1 AI CLI Selector (left)

Identical to the existing `cliSelector` in `ChatWindow.swift`:
- Capsule pill with `matchedGeometryEffect` animation
- Shows only installed and detected CLIs
- Selection persists via `AppState.currentCLIIdentifier`
- Reuses the exact same component — no duplication

### 3.2 Platform Selector (right)

Same visual style as the CLI selector (capsule pill), but showing connected Git platforms:

| Platform | Icon | Condition |
|----------|------|-----------|
| GitHub | `github` (custom asset or SF Symbol) | `dev.github` connector is connected |
| GitLab | `gitlab` (custom asset) | `dev.gitlab` connector is connected |

- If only one platform is connected, show it as static text (no pill animation).
- Selection stored in `GitPanelViewModel.selectedPlatform`.
- Changing platform reloads the repository list.

---

## 4. Chat with Git Context

The chat occupies the middle portion of the Git section. It reuses `ChatViewModel` with one addition: **Git context injection**.

### 4.1 Context Chip

When the user selects a repo (and optionally a branch) in the repository panel below, a context chip appears in the `ChatInputBar`:

```
┌──────────────────────────────────────────────┐
│  [✕ acme-api / main]                         │
│                                               │
│  Ask anything about this repo...         [▶] │
└──────────────────────────────────────────────┘
```

The chip shows `repo-name / branch-name` and has a dismiss button (✕) to clear the context.

### 4.2 Prompt Enrichment

When a Git context is active, `PromptEnrichmentService` prepends a header to the AI prompt:

```
[McClaw Git Context]
Platform: GitHub
Repository: joseconti/acme-api (https://github.com/joseconti/acme-api)
Branch: main
Local path: /Users/joseconti/Developer/acme-api (if cloned)
Available actions:
  Platform (GitHub API): list_issues, list_prs, get_pr_diff, create_issue, create_pr, create_comment, search_code, list_releases, list_branches, get_commit
  Local (git CLI): log, diff, status, blame, show, clone, checkout, branch, add, commit, push, pull, tag, stash
To execute an action, use: @fetch(github.list_prs, repo=acme-api, state=open) or @git(log --since="1 week ago" --oneline)
```

This way the AI knows what repo is selected, what actions are available, and can request execution.

### 4.3 New Intercept: @git()

In addition to the existing `@fetch()` intercept for connector actions, add a new `@git()` intercept for local Git operations:

```
AI response:  @git(log --since="2 weeks ago" --pretty=format:"%h %an %s" -20)
McClaw:       Intercepts → GitService.execute(command:, repoPath:) → returns output
McClaw:       Forwards result to AI as context
AI:           Generates human-readable summary
```

**Intercept rules** (same as @fetch):
- Maximum 3 rounds of @git per message
- Output truncation: 8000 characters (git output can be verbose)
- Errors forwarded as text, not fatal

---

## 5. Repository Panel

### 5.1 Repository List (GitRepoListView)

Displayed below the chat. Fetches repos from the selected platform's connector.

**Fetch mechanism**: `@fetch(github.list_repos)` or `@fetch(gitlab.list_projects)` via `ConnectorStore`.

Each row displays:
- **Repo name** (`.body.weight(.medium)`)
- **Star indicator** if starred/favorited
- **Primary language** (color dot + name)
- **Open PR count** badge
- **Last activity** (relative time)

Features:
- Search field at the top (filters by name)
- Sort options: last updated, name, stars
- Pull to refresh

### 5.2 Repository Selection

**Single click** on a repo:
- Sets it as the active Git context
- Shows the context chip in the chat input
- Default branch is auto-selected (usually `main` or `master`)
- A branch selector dropdown appears inline in the context chip or as a popover

**Double click** (or expand button) on a repo:
- Navigates to `GitRepoDetailView` (drill-down)
- Breadcrumb appears: `← All Repositories / acme-api`

### 5.3 Repository Detail (GitRepoDetailView)

Drill-down view for a single repository. Split into tabs or sections:

```
┌─────────────────────────────────────────────────────┐
│  ← All Repositories / acme-api                      │
│  ★ joseconti/acme-api          Swift   MIT License  │
├─────────────────────────────────────────────────────┤
│  [Branches]  [Pull Requests]  [Issues]  [Commits]  │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Branches (5)                                        │
│  ● main (default)                  3 ahead           │
│  ○ feature/auth                    12 commits        │
│  ○ fix/memory-leak                 2 commits         │
│  ○ release/2.0                     28 commits        │
│  ○ dev                             45 ahead          │
│                                                      │
└─────────────────────────────────────────────────────┘
```

**Branches tab**: list branches, click to set as active context in the chat.
**Pull Requests tab**: list open PRs with title, author, status, review state.
**Issues tab**: list open issues with title, labels, assignee.
**Commits tab**: recent commits on the selected branch (author, message, date).

All fetched via the platform connector. Selecting a branch updates the chat context chip.

---

## 6. GitService (Local Git Operations)

### 6.1 Design

```swift
actor GitService {
    static let shared = GitService()

    // Discovery
    func isGitInstalled() async -> Bool
    func findLocalRepos(searchPaths: [String]) async -> [LocalRepoInfo]
    func getRepoPath(for remoteURL: String) async -> String?

    // Read operations (no confirmation needed)
    func log(repoPath: String, branch: String?, since: String?, limit: Int, format: String?) async throws -> String
    func diff(repoPath: String, target: String?) async throws -> String
    func status(repoPath: String) async throws -> String
    func blame(repoPath: String, file: String) async throws -> String
    func show(repoPath: String, ref: String) async throws -> String
    func branches(repoPath: String) async throws -> [GitBranch]

    // Write operations (require user confirmation)
    func clone(url: String, destination: String) async throws -> String
    func checkout(repoPath: String, branch: String, create: Bool) async throws -> String
    func pull(repoPath: String) async throws -> String
    func add(repoPath: String, files: [String]) async throws -> String
    func commit(repoPath: String, message: String) async throws -> String
    func push(repoPath: String, remote: String, branch: String) async throws -> String
    func tag(repoPath: String, name: String, message: String?) async throws -> String
    func stash(repoPath: String, action: StashAction) async throws -> String
    func createBranch(repoPath: String, name: String, from: String?) async throws -> String

    // Internal
    private func execute(args: [String], workingDirectory: String?) async throws -> ProcessResult
}
```

### 6.2 Process Execution

Uses `Foundation.Process` (same pattern as `CLIBridge`):

```swift
private func execute(args: [String], workingDirectory: String?) async throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    if let wd = workingDirectory {
        process.currentDirectoryURL = URL(fileURLWithPath: wd)
    }
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    // ... read pipes, return ProcessResult
}
```

### 6.3 Local Repo Discovery

GitService can find locally cloned repos by:
1. Checking common paths: `~/Developer/`, `~/Documents/GitHub/`, `~/Projects/`
2. Matching remote URLs to platform repos (`git remote get-url origin`)
3. Caching known paths in `~/.mcclaw/git/repos.json`

When the user selects a repo from the platform list and it has a matching local clone, GitService can execute local operations directly. If not cloned, the AI can offer to clone it.

---

## 7. Actions the AI Can Perform

### 7.1 Read Operations (automatic, no confirmation)

| Category | Action | Mechanism | Example prompt |
|----------|--------|-----------|----------------|
| History | View commit log | `@git(log)` | "What changed this week?" |
| History | View specific commit | `@git(show <hash>)` | "Show me commit abc1234" |
| Diff | Compare branches | `@git(diff main..feature/auth)` | "What's different between main and the auth branch?" |
| Diff | View PR diff | `@fetch(github.get_pr_diff)` | "Show me the changes in PR #15" |
| Status | Current state | `@git(status)` | "What files are modified?" |
| Blame | File authorship | `@git(blame <file>)` | "Who last touched this file?" |
| Search | Search code | `@fetch(github.search_code)` | "Find all uses of UserService in the repo" |
| List | Branches | `@git(branch -a)` | "What branches exist?" |
| List | Open PRs | `@fetch(github.list_prs)` | "Show me open pull requests" |
| List | Issues | `@fetch(github.list_issues)` | "What issues are assigned to me?" |
| List | Releases | `@fetch(github.list_releases)` | "What was in the last release?" |
| Analysis | AI summary | git log + AI | "Summarize this week's development activity" |
| Analysis | PR review | PR diff + AI | "Review PR #15 and tell me if you see issues" |
| Analysis | Contributor stats | git shortlog + AI | "Who's been most active this month?" |

### 7.2 Write Operations (require user confirmation)

Write operations follow the existing `isWriteAction` confirmation pattern from `ConnectorActionDef` (see doc 12). The AI proposes the action, McClaw shows a confirmation card, the user approves or rejects.

| Category | Action | Mechanism | Example prompt |
|----------|--------|-----------|----------------|
| Clone | Clone repo | `@git(clone <url>)` | "Clone this repo to my machine" |
| Branch | Create branch | `@git(checkout -b <name>)` | "Create a branch called feature/login" |
| Branch | Switch branch | `@git(checkout <name>)` | "Switch to the dev branch" |
| Commit | Stage + commit | `@git(add . && commit -m "...")` | "Commit all changes with message 'Fix login bug'" |
| Push | Push to remote | `@git(push)` | "Push my changes" |
| Pull | Pull latest | `@git(pull)` | "Pull the latest changes" |
| Tag | Create tag | `@git(tag -a v2.0)` | "Tag this as version 2.0" |
| Stash | Stash changes | `@git(stash)` | "Stash my current changes" |
| Issue | Create issue | `@fetch(github.create_issue)` | "Create an issue for the bug we discussed" |
| Issue | Close issue | `@fetch(github.close_issue)` | "Close issue #23" |
| PR | Create PR | `@fetch(github.create_pr)` | "Open a PR from feature/login to main" |
| PR | Comment on PR | `@fetch(github.create_comment)` | "Add a comment to PR #15 about the naming" |
| PR | Merge PR | `@fetch(github.merge_pr)` | "Merge PR #15" |
| Release | Create release | `@fetch(github.create_release)` | "Create a release for v2.0 with auto-generated notes" |

### 7.3 Confirmation Card for Write Actions

When the AI wants to execute a write action, McClaw shows a confirmation card in the chat:

```
┌─────────────────────────────────────────────┐
│  ⚙ Git Action: Create Branch               │
│                                              │
│  Repository: acme-api                        │
│  Action: git checkout -b feature/login       │
│  From: main                                  │
│                                              │
│         [Cancel]         [Confirm]           │
└─────────────────────────────────────────────┘
```

For platform write actions (create issue, merge PR, etc.) the same pattern applies:

```
┌─────────────────────────────────────────────┐
│  ⚙ GitHub Action: Create Issue              │
│                                              │
│  Repository: acme-api                        │
│  Title: Login fails on Safari                │
│  Labels: bug, priority-high                  │
│  Body: (preview...)                          │
│                                              │
│         [Cancel]         [Confirm]           │
└─────────────────────────────────────────────┘
```

---

## 8. Data Models

### 8.1 New Models

```swift
// Git context for chat enrichment
struct GitContext {
    let platform: GitPlatform          // .github or .gitlab
    let repoFullName: String           // "joseconti/acme-api"
    let repoURL: String                // "https://github.com/joseconti/acme-api"
    let branch: String                 // "main"
    let localPath: String?             // "/Users/.../acme-api" or nil if not cloned
}

enum GitPlatform: String, Codable, CaseIterable {
    case github
    case gitlab

    var connectorId: String {
        switch self {
        case .github: return "dev.github"
        case .gitlab: return "dev.gitlab"
        }
    }

    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        }
    }

    var icon: String {
        switch self {
        case .github: return "github.mark"      // custom asset
        case .gitlab: return "gitlab.mark"      // custom asset
        }
    }
}

struct GitRepoInfo: Identifiable, Codable {
    let id: String
    let name: String
    let fullName: String
    let description: String?
    let language: String?
    let isPrivate: Bool
    let isFork: Bool
    let starCount: Int
    let openIssueCount: Int
    let openPRCount: Int
    let defaultBranch: String
    let updatedAt: Date
    let cloneURL: String
    let htmlURL: String
    let localPath: String?              // discovered by GitService
}

struct GitBranch: Identifiable, Codable {
    let id: String                      // name is the id
    let name: String
    let isDefault: Bool
    let isProtected: Bool
    let aheadBehind: AheadBehind?
}

struct AheadBehind: Codable {
    let ahead: Int
    let behind: Int
}

struct GitPRInfo: Identifiable, Codable {
    let id: String
    let number: Int
    let title: String
    let author: String
    let state: String                   // open, closed, merged
    let sourceBranch: String
    let targetBranch: String
    let reviewState: String?            // approved, changes_requested, pending
    let createdAt: Date
    let updatedAt: Date
}

struct GitIssueInfo: Identifiable, Codable {
    let id: String
    let number: Int
    let title: String
    let author: String
    let state: String
    let labels: [String]
    let assignees: [String]
    let createdAt: Date
}

struct GitCommitInfo: Identifiable, Codable {
    let id: String                      // sha
    let shortSha: String
    let message: String
    let author: String
    let date: Date
}

struct LocalRepoInfo: Codable {
    let path: String
    let remoteURL: String?
    let currentBranch: String?
}
```

### 8.2 Modified Models

| File | Change |
|------|--------|
| `AppState.swift` | Add `gitSectionEnabled: Bool` |
| `ChatSidebar.swift` | Add `case git` to `SidebarSection` |
| `ConfigStore.swift` | Persist `gitSectionEnabled` |

---

## 9. ViewModel

```swift
@MainActor @Observable
final class GitPanelViewModel {
    // State
    var selectedPlatform: GitPlatform = .github
    var availablePlatforms: [GitPlatform] = []
    var repos: [GitRepoInfo] = []
    var filteredRepos: [GitRepoInfo] = []
    var searchText: String = ""
    var sortOrder: GitSortOrder = .lastUpdated
    var isLoadingRepos: Bool = false

    // Selected context
    var selectedRepo: GitRepoInfo?
    var selectedBranch: GitBranch?
    var gitContext: GitContext?          // published to ChatViewModel

    // Detail view
    var isShowingDetail: Bool = false
    var branches: [GitBranch] = []
    var pullRequests: [GitPRInfo] = []
    var issues: [GitIssueInfo] = []
    var recentCommits: [GitCommitInfo] = []

    // Dependencies
    private let connectorStore = ConnectorStore.shared
    private let gitService = GitService.shared

    // Actions
    func loadRepos() async { ... }
    func selectRepo(_ repo: GitRepoInfo) { ... }
    func selectBranch(_ branch: GitBranch) { ... }
    func loadRepoDetail(_ repo: GitRepoInfo) async { ... }
    func refreshAll() async { ... }
}

enum GitSortOrder: String, CaseIterable {
    case lastUpdated
    case name
    case stars
}
```

---

## 10. Files to Create

```
McClaw/Sources/McClaw/
  Models/Git/
    GitModels.swift                              # All Git data models (section 8)
  Services/Git/
    GitService.swift                             # Local git CLI operations (section 6)
  ViewModels/Git/
    GitPanelViewModel.swift                      # State management (section 9)
  Views/Git/
    GitPanelView.swift                           # Main Git section layout (section 3)
    GitRepoListView.swift                        # Repository list (section 5.1)
    GitRepoRow.swift                             # Single repo row
    GitRepoDetailView.swift                      # Repo detail with tabs (section 5.3)
    GitBranchListView.swift                      # Branch list tab
    GitPRListView.swift                          # PR list tab
    GitIssueListView.swift                       # Issue list tab
    GitCommitListView.swift                      # Commit list tab
    GitContextChip.swift                         # Context chip for ChatInputBar
    GitActionConfirmationCard.swift              # Write action confirmation (section 7.3)
    GitPlatformSelector.swift                    # Platform pill selector (section 3.2)
    GitEmptyStateView.swift                      # Empty state when no repos/no connector
```

## 11. Files to Modify

| File | Change |
|------|--------|
| `State/AppState.swift` | Add `gitSectionEnabled: Bool` |
| `Infrastructure/Config/ConfigStore.swift` | Persist `gitSectionEnabled`, add `~/.mcclaw/git/` directory |
| `Views/Chat/ChatSidebar.swift` | Add `case git` to `SidebarSection`, show when enabled |
| `Views/Chat/ChatWindow.swift` | Route `.git` section to `GitPanelView` in `mainContentForSection` |
| `Views/Chat/ChatInputBar.swift` | Support `GitContextChip` display alongside existing attachment chips |
| `Views/Chat/ChatViewModel.swift` | Accept `GitContext?`, inject into `PromptEnrichmentService` |
| `Services/Connectors/PromptEnrichmentService.swift` | Handle `@git()` intercept, build Git context header |
| `Views/Settings/GeneralSettingsTab.swift` | Add Git section toggle |
| `Models/Connectors/ConnectorModels.swift` | Add new actions to GitHub/GitLab connector definitions (if not already present) |
| `Services/Connectors/ConnectorRegistry.swift` | Register new GitHub/GitLab actions: `get_pr_diff`, `create_pr`, `merge_pr`, `create_release`, `close_issue`, `create_comment` |
| `Resources/en.lproj/Localizable.strings` | All new UI strings |

---

## 12. New Connector Actions Required

### GitHub (dev.github) — New Actions

| Action | Method | Endpoint | Write? |
|--------|--------|----------|--------|
| `list_repos` | GET | `/user/repos` | No |
| `get_repo` | GET | `/repos/{owner}/{repo}` | No |
| `list_branches` | GET | `/repos/{owner}/{repo}/branches` | No |
| `list_prs` | GET | `/repos/{owner}/{repo}/pulls` | No |
| `get_pr_diff` | GET | `/repos/{owner}/{repo}/pulls/{number}` (Accept: diff) | No |
| `list_issues` | GET | `/repos/{owner}/{repo}/issues` | No |
| `list_commits` | GET | `/repos/{owner}/{repo}/commits` | No |
| `list_releases` | GET | `/repos/{owner}/{repo}/releases` | No |
| `search_code` | GET | `/search/code` | No |
| `get_notifications` | GET | `/notifications` | No |
| `create_issue` | POST | `/repos/{owner}/{repo}/issues` | Yes |
| `close_issue` | PATCH | `/repos/{owner}/{repo}/issues/{number}` | Yes |
| `create_comment` | POST | `/repos/{owner}/{repo}/issues/{number}/comments` | Yes |
| `create_pr` | POST | `/repos/{owner}/{repo}/pulls` | Yes |
| `merge_pr` | PUT | `/repos/{owner}/{repo}/pulls/{number}/merge` | Yes |
| `create_release` | POST | `/repos/{owner}/{repo}/releases` | Yes |

### GitLab (dev.gitlab) — New Actions

| Action | Method | Endpoint | Write? |
|--------|--------|----------|--------|
| `list_projects` | GET | `/projects?membership=true` | No |
| `get_project` | GET | `/projects/{id}` | No |
| `list_branches` | GET | `/projects/{id}/repository/branches` | No |
| `list_mrs` | GET | `/projects/{id}/merge_requests` | No |
| `get_mr_diff` | GET | `/projects/{id}/merge_requests/{iid}/changes` | No |
| `list_issues` | GET | `/projects/{id}/issues` | No |
| `list_commits` | GET | `/projects/{id}/repository/commits` | No |
| `list_releases` | GET | `/projects/{id}/releases` | No |
| `create_issue` | POST | `/projects/{id}/issues` | Yes |
| `close_issue` | PUT | `/projects/{id}/issues/{iid}` | Yes |
| `create_note` | POST | `/projects/{id}/issues/{iid}/notes` | Yes |
| `create_mr` | POST | `/projects/{id}/merge_requests` | Yes |
| `merge_mr` | PUT | `/projects/{id}/merge_requests/{iid}/merge` | Yes |
| `create_release` | POST | `/projects/{id}/releases` | Yes |

---

## 13. Dependencies

No new SPM dependencies. Uses existing infrastructure:

- `Foundation.Process` — for local git CLI execution (same as CLIBridge)
- `URLSession` — for platform API calls (via existing connector infrastructure)
- `Security` — Keychain for connector credentials (already in place)

---

## 14. Implementation Sprints

### Sprint A: Core Infrastructure

**Goal**: GitService, models, settings toggle, sidebar entry.

**Tasks**:
1. Create `GitModels.swift` with all data models (section 8)
2. Create `GitService.swift` actor with local git operations (section 6)
3. Add `gitSectionEnabled` to `AppState` and `ConfigStore`
4. Add `case git` to `SidebarSection` in `ChatSidebar`
5. Add Git toggle to `GeneralSettingsTab`
6. Route `.git` to placeholder view in `ChatWindow`
7. Add new connector actions to `ConnectorRegistry` (section 12)
8. Localize all new strings

### Sprint B: Git Panel UI

**Goal**: Complete Git section UI with repo list and platform selector.

**Tasks**:
1. Create `GitPanelView` with top bar layout (CLI selector + platform selector)
2. Create `GitPlatformSelector` (capsule pill, same style as CLI selector)
3. Create `GitPanelViewModel` with repo loading and filtering
4. Create `GitRepoListView` with search, sort, and `GitRepoRow`
5. Create `GitEmptyStateView` (no connector / no repos)
6. Implement repo selection and `GitContext` creation
7. Wire `GitContext` into `ChatViewModel` for prompt enrichment

### Sprint C: Chat Integration

**Goal**: AI can read and write Git operations through the chat.

**Tasks**:
1. Create `GitContextChip` and integrate into `ChatInputBar`
2. Implement `@git()` intercept in `PromptEnrichmentService`
3. Build Git context header for prompt enrichment
4. Implement write action confirmation card (`GitActionConfirmationCard`)
5. Connect `GitService` execution to `@git()` intercept responses
6. Test full flow: select repo → ask AI → AI executes git/connector action → result shown

### Sprint D: Repo Detail View

**Goal**: Drill-down into a repository with branches, PRs, issues, commits.

**Tasks**:
1. Create `GitRepoDetailView` with tab navigation
2. Create `GitBranchListView` with branch selection
3. Create `GitPRListView` with PR info and quick actions
4. Create `GitIssueListView` with issue info
5. Create `GitCommitListView` with commit history
6. Implement breadcrumb navigation (detail ↔ list)
7. Wire branch selection to update `GitContext`

---

## 15. Security Considerations

- **Credentials**: All connector tokens stored in macOS Keychain (existing `KeychainService`). Git SSH keys are managed by the user's system, not by McClaw.
- **Write confirmation**: All write operations (both platform API and local git) require explicit user confirmation via the confirmation card. No silent writes.
- **Local repo access**: GitService only operates on paths the user has explicitly associated or that match known remote URLs. No scanning of arbitrary directories.
- **Sensitive data**: Git credentials, SSH keys, and tokens never appear in chat messages, logs, or enriched prompts.
- **Private repos**: Accessible only through authenticated connector tokens. McClaw respects the same permissions the user has on the platform.

---

## 16. Out of Scope (for now)

- **Code editing**: McClaw does not provide a code editor. For file modifications, the AI works through the CLI (Claude CLI can edit files natively).
- **Merge conflict resolution**: Too complex for chat-based interaction. The user should resolve conflicts in their IDE.
- **Git submodules**: Not supported in initial implementation.
- **Multi-platform operations**: Cannot operate across GitHub and GitLab simultaneously in a single action.
- **CI/CD integration**: Viewing pipeline status could be added later as additional connector actions.
- **Git hooks management**: Out of scope for the chat-based workflow.
