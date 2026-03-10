# McClaw - Adaptive Learning System

Inspired by [OpenClaw-RL](https://arxiv.org/abs/2603.10165) (Wang et al., 2026). Adapted to McClaw's CLI Bridge architecture where we do not control model weights.

---

## 1. Vision

McClaw wraps official CLIs and cannot fine-tune model weights. However, OpenClaw-RL demonstrates that next-state signals (the user's reaction after each agent response) are an extremely rich and free source of information about quality and preferences. McClaw can capture these signals and use them to improve responses over time through context enrichment, without any RL infrastructure or GPU requirements.

The goal: McClaw gets better the more you use it, for every provider.

---

## 2. Core Concepts

### 2.1 Next-State Signals

Every time the agent responds, the user's next action implicitly evaluates that response. OpenClaw-RL classifies these into two types:

| Signal Type | What It Tells Us | McClaw Example |
|---|---|---|
| **Evaluative** | How well the response performed (good/bad) | User re-asks the same question, abandons conversation, switches provider |
| **Directive** | How the response should have been different | User corrects the agent ("no, I meant..."), rephrases with more detail |

McClaw recovers both signal types from normal usage and converts them into persistent preference data.

### 2.2 Turn Classification

Following OpenClaw-RL's session-aware design, McClaw classifies each interaction turn:

| Turn Type | Description | Used for Learning |
|---|---|---|
| **Main-line** | Agent's primary response to user query | Yes |
| **Side** | Tool calls, memory operations, internal processing | No |
| **System** | Error messages, status updates, onboarding | No |

Only main-line turns generate learning signals. This prevents noise from internal operations polluting the preference model.

---

## 3. Architecture

### 3.1 Overview

```
+------------------------------------------------------------------+
|                        McClaw.app                                |
|                                                                  |
|  +------------------+     +-------------------+                  |
|  | ChatViewModel    |---->| SignalDetector     |                  |
|  | (existing)       |     | (new)             |                  |
|  +------------------+     +--------+----------+                  |
|                                    |                             |
|                           +--------v----------+                  |
|                           | FeedbackStore     |                  |
|                           | (new)             |                  |
|                           +--------+----------+                  |
|                                    |                             |
|                           +--------v----------+                  |
|                           | PreferenceEngine  |                  |
|                           | (new)             |                  |
|                           +--------+----------+                  |
|                                    |                             |
|                           +--------v----------+                  |
|                           | ContextEnricher   |                  |
|                           | (new)             |                  |
|                           +------------------+                   |
+------------------------------------------------------------------+
```

### 3.2 New Components

| Component | Actor/Class | Responsibility |
|---|---|---|
| **SignalDetector** | `@MainActor class` | Monitors conversation flow and detects evaluative/directive signals in real time |
| **FeedbackStore** | `actor` | Persists raw feedback events to disk (`~/.mcclaw/learning/`) |
| **PreferenceEngine** | `actor` | Aggregates raw feedback into a structured preference profile |
| **ContextEnricher** | `struct` | Injects preference profile into system prompts before sending to CLI |

### 3.3 Data Flow

```
User sends message
        |
        v
ChatViewModel sends to CLIBridge (existing flow, unchanged)
        |
        v
Agent responds (streamed via CLIBridge)
        |
        v
User reacts (next message / action)
        |
        v
SignalDetector analyzes the pair (agent response + user reaction)
        |
        +--> FeedbackEvent written to FeedbackStore
        |
        v
PreferenceEngine updates UserPreferenceProfile (periodic, not per-message)
        |
        v
ContextEnricher reads profile and injects into next CLI call
```

---

## 4. Signal Detection

### 4.1 SignalDetector

```swift
@MainActor
final class SignalDetector {

    /// Analyze user's reaction to the previous agent response
    func analyze(
        agentResponse: ChatMessage,
        userReaction: ChatMessage,
        session: SessionInfo
    ) -> FeedbackEvent? {
        // 1. Classify turn type
        guard agentResponse.role == .assistant,
              userReaction.role == .user,
              isMainLineTurn(agentResponse) else {
            return nil // Side turn, skip
        }

        // 2. Detect signal type
        let signals = detectSignals(
            response: agentResponse.content,
            reaction: userReaction.content,
            provider: agentResponse.provider
        )

        guard !signals.isEmpty else { return nil }

        return FeedbackEvent(
            id: UUID(),
            timestamp: Date(),
            sessionKey: session.key,
            provider: agentResponse.provider ?? "unknown",
            model: agentResponse.model,
            signals: signals,
            responseExcerpt: agentResponse.content.prefix(500).description,
            reactionExcerpt: userReaction.content.prefix(500).description
        )
    }
}
```

### 4.2 Evaluative Signals

Detected heuristically from user behavior patterns:

| Signal | Detection Method | Score |
|---|---|---|
| **Re-query** | User asks same question rephrased (semantic similarity > 0.8) | -1 |
| **Correction** | Message starts with "no", "I meant", "actually", "that's wrong" (localized) | -1 |
| **Abandonment** | User starts new session within 30s of agent response | -1 |
| **Provider switch** | User changes CLI provider mid-conversation | -1 |
| **Continuation** | User follows up naturally building on agent's response | +1 |
| **Explicit positive** | "thanks", "perfect", "great", etc. (localized) | +1 |
| **Explicit negative** | "that's not helpful", "wrong", "bad response" (localized) | -1 |
| **Copy action** | User copies agent response to clipboard (via pasteboard monitoring) | +1 |

```swift
enum EvaluativeSignal: Codable, Sendable {
    case reQuery
    case correction
    case abandonment
    case providerSwitch(from: String, to: String)
    case continuation
    case explicitPositive
    case explicitNegative
    case copyAction

    var score: Int {
        switch self {
        case .reQuery, .correction, .abandonment,
             .providerSwitch, .explicitNegative:
            return -1
        case .continuation, .explicitPositive, .copyAction:
            return +1
        }
    }
}
```

### 4.3 Directive Signals

Extracted when the user's reaction contains explicit correction direction:

```swift
struct DirectiveSignal: Codable, Sendable {
    let category: DirectiveCategory
    let detail: String  // What the user wanted differently
}

enum DirectiveCategory: String, Codable, Sendable {
    case formatPreference    // "don't use bullet points", "shorter please"
    case contentCorrection   // "the capital of France is Paris, not Lyon"
    case stylePreference     // "be more formal", "less verbose"
    case languagePreference  // "respond in Spanish", "use simpler words"
    case behaviorPreference  // "always show code first", "ask before executing"
    case providerHint        // "Claude is better for this", "use Ollama for code"
}
```

Extraction uses pattern matching on the user's message. Unlike OpenClaw-RL which uses a separate judge model, McClaw uses lightweight heuristics to keep it local and fast:

```swift
func extractDirectives(from reaction: String) -> [DirectiveSignal] {
    var directives: [DirectiveSignal] = []

    // Format preferences
    let formatPatterns = [
        "shorter", "longer", "more detail", "less detail",
        "bullet points", "no bullets", "code first",
        "step by step", "summary", "concise"
    ]
    // ... pattern matching per category

    return directives
}
```

### 4.4 Turn Classification

```swift
func isMainLineTurn(_ message: ChatMessage) -> Bool {
    // Exclude tool-phase messages
    if message.toolPhase != nil { return false }

    // Exclude system messages
    if message.role == .system { return false }

    // Exclude very short responses (likely errors or acknowledgments)
    if message.content.count < 20 { return false }

    return true
}
```

---

## 5. Feedback Storage

### 5.1 FeedbackStore

```swift
actor FeedbackStore {
    private let directory: URL  // ~/.mcclaw/learning/feedback/

    func record(_ event: FeedbackEvent) async throws {
        let filename = "\(event.timestamp.ISO8601Format()).json"
        let data = try JSONEncoder().encode(event)
        try data.write(to: directory.appending(component: filename))
    }

    func events(since: Date) async throws -> [FeedbackEvent] {
        // Read and decode events from disk
    }

    func purgeOlderThan(_ date: Date) async throws {
        // Cleanup old raw events (keep aggregated preferences)
    }
}
```

### 5.2 FeedbackEvent Model

```swift
struct FeedbackEvent: Codable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let sessionKey: String
    let provider: String
    let model: String?

    let signals: [FeedbackSignal]
    let responseExcerpt: String   // First 500 chars of agent response
    let reactionExcerpt: String   // First 500 chars of user reaction
}

enum FeedbackSignal: Codable, Sendable {
    case evaluative(EvaluativeSignal)
    case directive(DirectiveSignal)
}
```

### 5.3 Disk Layout

```
~/.mcclaw/learning/
    feedback/                       # Raw events (JSONL, rotated weekly)
        2026-03-15T10:30:00Z.json
        2026-03-15T11:45:00Z.json
    profile.json                    # Aggregated preference profile
    provider-stats.json             # Per-provider satisfaction scores
```

Privacy: all data stays local. Nothing is sent to any server. The user can delete `~/.mcclaw/learning/` at any time to reset.

---

## 6. Preference Engine

### 6.1 UserPreferenceProfile

The aggregated output of all feedback signals. This is what gets injected into prompts.

```swift
struct UserPreferenceProfile: Codable, Sendable {
    var lastUpdated: Date
    var totalInteractions: Int
    var satisfactionRate: Double  // 0.0 - 1.0

    // Format preferences (with confidence)
    var formatPreferences: [FormatPreference]

    // Style preferences
    var stylePreferences: [StylePreference]

    // Per-provider stats
    var providerStats: [String: ProviderStat]

    // Learned behaviors
    var behaviors: [BehaviorPreference]

    // Language/locale
    var languagePreferences: [LanguagePreference]
}

struct FormatPreference: Codable, Sendable {
    let key: String          // e.g., "response_length", "code_style", "use_bullets"
    let value: String        // e.g., "concise", "commented", "never"
    var confidence: Double   // 0.0 - 1.0, increases with repeated signals
    var occurrences: Int
}

struct ProviderStat: Codable, Sendable {
    let provider: String
    var totalTurns: Int
    var positiveSignals: Int
    var negativeSignals: Int
    var satisfactionRate: Double {
        guard totalTurns > 0 else { return 0.5 }
        return Double(positiveSignals) / Double(totalTurns)
    }
    var bestFor: [String]    // Task categories where this provider excels
}

struct BehaviorPreference: Codable, Sendable {
    let key: String          // e.g., "ask_before_executing", "show_reasoning"
    let value: String
    var confidence: Double
}
```

### 6.2 PreferenceEngine

```swift
actor PreferenceEngine {
    private let profilePath: URL      // ~/.mcclaw/learning/profile.json
    private let feedbackStore: FeedbackStore
    private var profile: UserPreferenceProfile

    /// Rebuild profile from recent feedback (called periodically, not per-message)
    func updateProfile() async throws {
        let recentEvents = try await feedbackStore.events(
            since: profile.lastUpdated
        )

        for event in recentEvents {
            for signal in event.signals {
                switch signal {
                case .evaluative(let eval):
                    applyEvaluative(eval, provider: event.provider)
                case .directive(let dir):
                    applyDirective(dir)
                }
            }
            profile.totalInteractions += 1
        }

        profile.lastUpdated = Date()
        try save()
    }

    private func applyDirective(_ directive: DirectiveSignal) {
        switch directive.category {
        case .formatPreference:
            upsertPreference(
                in: &profile.formatPreferences,
                key: directive.detail,
                value: directive.detail
            )
        case .stylePreference:
            upsertPreference(
                in: &profile.stylePreferences,
                key: directive.detail,
                value: directive.detail
            )
        // ... other categories
        }
    }

    /// Increase confidence if preference already exists, create if new
    private func upsertPreference(
        in list: inout [FormatPreference],
        key: String,
        value: String
    ) {
        if let idx = list.firstIndex(where: { $0.key == key }) {
            list[idx].occurrences += 1
            list[idx].confidence = min(1.0, list[idx].confidence + 0.1)
        } else {
            list.append(FormatPreference(
                key: key, value: value,
                confidence: 0.3, occurrences: 1
            ))
        }
    }
}
```

### 6.3 Confidence Decay

Preferences lose confidence over time if not reinforced. This prevents stale preferences from dominating:

```swift
func decayConfidence() {
    let decayRate = 0.02 // Per day
    let daysSinceUpdate = Date().timeIntervalSince(profile.lastUpdated) / 86400
    let factor = max(0, 1.0 - (decayRate * daysSinceUpdate))

    for i in profile.formatPreferences.indices {
        profile.formatPreferences[i].confidence *= factor
    }
    // Remove preferences below threshold
    profile.formatPreferences.removeAll { $0.confidence < 0.1 }
}
```

---

## 7. Context Enrichment

### 7.1 ContextEnricher

This is where preferences become actionable. Before each CLI call, the enricher generates a preference block that gets prepended to the system context.

```swift
struct ContextEnricher {

    /// Generate preference context to inject before CLI call
    func enrichmentBlock(
        profile: UserPreferenceProfile,
        provider: String,
        taskHint: String? = nil
    ) -> String? {
        var lines: [String] = []

        // Only include high-confidence preferences
        let threshold = 0.5

        let relevantFormats = profile.formatPreferences
            .filter { $0.confidence >= threshold }
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)

        let relevantStyles = profile.stylePreferences
            .filter { $0.confidence >= threshold }
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)

        let relevantBehaviors = profile.behaviors
            .filter { $0.confidence >= threshold }
            .prefix(3)

        if relevantFormats.isEmpty && relevantStyles.isEmpty
           && relevantBehaviors.isEmpty {
            return nil  // No enrichment needed yet
        }

        lines.append("[User Preferences]")

        for pref in relevantFormats {
            lines.append("- \(pref.key): \(pref.value)")
        }
        for pref in relevantStyles {
            lines.append("- \(pref.key): \(pref.value)")
        }
        for pref in relevantBehaviors {
            lines.append("- \(pref.key): \(pref.value)")
        }

        return lines.joined(separator: "\n")
    }
}
```

### 7.2 Integration with CLIBridge

The enrichment block is injected via the existing system prompt mechanism. Each CLI provider handles this differently:

| Provider | Injection Method |
|---|---|
| **Claude CLI** | `--system-prompt` flag or `CLAUDE_SYSTEM_PROMPT` env var |
| **ChatGPT CLI** | System message in conversation context |
| **Gemini CLI** | System instruction parameter |
| **Ollama** | System message in `/api/chat` payload |

```swift
// In CLIBridge, before executing CLI command:
func buildSystemContext(
    basePrompt: String?,
    profile: UserPreferenceProfile,
    provider: String
) -> String {
    var parts: [String] = []

    if let base = basePrompt {
        parts.append(base)
    }

    let enricher = ContextEnricher()
    if let enrichment = enricher.enrichmentBlock(
        profile: profile, provider: provider
    ) {
        parts.append(enrichment)
    }

    return parts.joined(separator: "\n\n")
}
```

---

## 8. Provider Intelligence

### 8.1 Smart Provider Suggestions

With per-provider satisfaction data, McClaw can suggest which provider is best for a given task type:

```swift
extension PreferenceEngine {

    /// Suggest best provider for a task category
    func suggestProvider(for taskCategory: String) -> String? {
        let candidates = profile.providerStats.values
            .filter { $0.bestFor.contains(taskCategory) }
            .sorted { $0.satisfactionRate > $1.satisfactionRate }

        return candidates.first?.provider
    }
}
```

### 8.2 Task Category Detection

Simple keyword-based classification of user queries:

```swift
enum TaskCategory: String, CaseIterable {
    case coding = "coding"
    case writing = "writing"
    case analysis = "analysis"
    case conversation = "conversation"
    case math = "math"
    case creative = "creative"

    static func detect(from query: String) -> TaskCategory {
        let lower = query.lowercased()
        if lower.contains("code") || lower.contains("function")
           || lower.contains("bug") || lower.contains("implement") {
            return .coding
        }
        if lower.contains("write") || lower.contains("draft")
           || lower.contains("email") || lower.contains("document") {
            return .writing
        }
        // ... more patterns
        return .conversation
    }
}
```

---

## 9. Settings UI

### 9.1 Learning Tab in Settings

New tab in SettingsWindow under existing tabbed structure:

```
Settings > Learning
    [Toggle] Enable adaptive learning
    [Toggle] Show learning indicators in chat

    Preferences Learned: 12
    Total Interactions Analyzed: 847
    Satisfaction Rate: 78%

    Provider Performance:
        Claude   ████████░░ 82%  (best for: coding, analysis)
        ChatGPT  ███████░░░ 71%  (best for: writing, creative)
        Ollama   █████░░░░░ 54%  (best for: conversation)

    [Button] View Learned Preferences
    [Button] Reset All Learning Data
    [Button] Export Preferences
```

### 9.2 Chat Indicators

Optional subtle indicators in the chat UI:

| Indicator | When | Visual |
|---|---|---|
| Preference applied | Enrichment block was injected | Small icon near provider name |
| Learning event | A feedback signal was detected | Brief flash/highlight (respects Reduce Motion) |
| Suggestion available | Provider switch recommended | Non-intrusive banner |

---

## 10. Privacy and Security

| Aspect | Implementation |
|---|---|
| **Storage** | All data in `~/.mcclaw/learning/`, local only |
| **No network** | Zero data sent to any server, ever |
| **User control** | Toggle on/off, delete all data, export as JSON |
| **Data minimization** | Only excerpts stored (first 500 chars), not full conversations |
| **Rotation** | Raw feedback events purged after 30 days; only aggregated profile persists |
| **Encryption** | Follows system FileVault; no additional encryption layer needed |

---

## 11. Localization

All user-facing strings in this feature must follow McClaw's localization conventions:

```swift
// Signal detection patterns must be localized
let correctionPatterns: [String: [String]] = [
    "en": ["no,", "I meant", "actually", "that's wrong", "not what I asked"],
    "es": ["no,", "quise decir", "en realidad", "eso esta mal", "no es lo que pregunte"],
    "fr": ["non,", "je voulais dire", "en fait", "c'est faux"],
    // ...
]

// UI strings via String(localized:bundle:)
let learningLabel = String(localized: "settings.learning.title", bundle: .module)
```

Pattern matching for signal detection loads patterns based on the user's locale. The system supports adding patterns for new languages without code changes (patterns stored in a localizable JSON resource).

---

## 12. Implementation Plan

### Phase 1: Foundation (1 sprint)
- `FeedbackEvent` and `FeedbackSignal` models
- `FeedbackStore` actor with disk persistence
- `SignalDetector` with basic evaluative signals (re-query, explicit positive/negative)
- Integration point in `ChatViewModel` to call `SignalDetector` on each user message
- `~/.mcclaw/learning/` directory management

### Phase 2: Preferences (1 sprint)
- `UserPreferenceProfile` model
- `PreferenceEngine` actor with aggregation logic
- `ContextEnricher` struct
- Integration with `CLIBridge` to inject enrichment block
- Basic directive signal detection (format, style)

### Phase 3: Intelligence (1 sprint)
- Per-provider satisfaction tracking (`ProviderStat`)
- Task category detection
- Smart provider suggestions
- Confidence decay system

### Phase 4: UI (1 sprint)
- Learning tab in Settings
- Chat indicators (preference applied, learning event)
- Provider suggestion banners
- Export/import preferences
- Reset learning data

### Phase 5: Refinement (1 sprint)
- Expanded directive signal patterns
- Localized pattern sets (Tier 1 languages)
- Performance optimization (batch processing of events)
- Unit tests for all components
- Integration tests with mock CLI sessions

---

## 13. Relation to OpenClaw-RL

| OpenClaw-RL Concept | McClaw Adaptation |
|---|---|
| Next-state signals | Captured via `SignalDetector` from conversation flow |
| Binary RL (PRM judge) | Replaced by heuristic evaluative signals (no model needed) |
| OPD (hindsight distillation) | Replaced by directive signal extraction into persistent preferences |
| Asynchronous 4-component pipeline | Simplified to 4 sequential components (no training loop) |
| Model weight updates | Replaced by system prompt enrichment (works with any provider) |
| Main-line vs side turn classification | Directly adopted |
| Session-aware tracking | Directly adopted via existing `SessionInfo` |
| Process rewards per step | Not applicable (no RL training) |

The key insight we adopt: the user is already providing training signals for free. We just need to capture and act on them.

---

## 14. Future Considerations

### 14.1 Ollama Fine-Tuning (Experimental)

If the user runs Ollama with a local model (Qwen3, Llama), McClaw could eventually offer actual weight updates using accumulated feedback. This would require:

- Exporting feedback as training pairs (prompt + preferred response)
- Running `ollama create` with a Modelfile that includes training data
- Replacing the base model with the fine-tuned variant

This is the closest McClaw could get to actual OpenClaw-RL behavior, but it's a future exploration, not a priority.

### 14.2 Gateway-Side Learning

If the Gateway is running, McClaw could share anonymized, aggregated preference profiles across devices (macOS + future mobile app) via the WebSocket connection, enabling consistent personalization across clients.

### 14.3 Cross-Session Memory

The preference profile can complement McClaw's existing memory/context system by providing a stable "personality layer" that persists across all sessions, independent of conversation-specific context.
