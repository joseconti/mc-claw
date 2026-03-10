# 11 - Native Channels (Without Gateway)

## Status: Phase 1 (Telegram) ✅ | Phase 2 (Slack) ✅ | Phase 3 (Discord) Pending

## Goal

Implement messaging Channels directly from McClaw, without depending on the Gateway. McClaw will maintain persistent background connections (same as LocalScheduler) using the native APIs/SDKs of each platform.

---

## Channels to Implement

### Phase 1: Telegram ✅ (Sprint 19)
- **Bot API** via HTTP long polling (`/getUpdates` with offset tracking)
- TelegramKit pure logic (McClawKit) + TelegramNativeService actor
- Auth: Bot Token from existing Telegram ConnectorProvider
- 48 tests

### Phase 2: Slack ✅ (Sprint 20)
- **Web API** + **Socket Mode** (WebSocket)
- SlackKit pure logic (McClawKit) + SlackNativeService actor
- Dual tokens: Bot Token (xoxb- from ConnectorProvider) + App-Level Token (xapp- in config)
- Flow: `apps.connections.open` → WebSocket → envelope ack → event processing → `chat.postMessage`
- Features: DM-only mode, allowed channel IDs, threaded replies, mention stripping
- 39 tests

### Phase 3: Discord (Pending)
- **Bot API** + **Gateway WebSocket**
- Direct WebSocket connection from McClaw
- Auth: Bot Token (Discord ConnectorProvider already exists)

### ~~Phase 4: WhatsApp~~ (Dropped)
- Excluded: Cloud API requires webhook server, goes against WhatsApp TOS for automated bots

---

## Planned Architecture

- **Connectors** = on-demand data read/write (`@fetch`)
- **Channels** = persistent messaging connections (bot listening + responding)
- Both 100% local, no Gateway
- Existing Connectors (Slack, Discord, Telegram) are reused for auth and credentials
- Channels add the persistent connection layer on top
- Runs in the background while McClaw is in the menu bar (same pattern as LocalScheduler)
