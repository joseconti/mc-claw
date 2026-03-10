# 11 - Native Channels (Without Gateway)

## Status: Planning

## Goal

Implement messaging Channels directly from McClaw, without depending on the Gateway. McClaw will maintain persistent background connections (same as LocalScheduler) using the native APIs/SDKs of each platform.

---

## Channels to Implement

### Phase 1: Telegram
- **Bot API** via HTTP
- Long polling from McClaw (no server/webhook required)
- The client initiates the connection — perfect for a desktop app
- Auth: Bot Token

### Phase 2: Slack
- **Web API** + **Socket Mode**
- Direct WebSocket connection from McClaw
- No webhook server required
- Auth: Bot Token + OAuth2 (Slack ConnectorProvider already exists)

### Phase 3: Discord
- **Bot API** + **Gateway WebSocket**
- Direct WebSocket connection from McClaw
- Auth: Bot Token (Discord ConnectorProvider already exists)

### Phase 4 (future): WhatsApp
- More complex: Cloud API requires a webhook server
- Pending evaluation of options (polling, local solution, or dropping it)
- To be decided later

---

## Planned Architecture

- **Connectors** = on-demand data read/write (`@fetch`)
- **Channels** = persistent messaging connections (bot listening + responding)
- Both 100% local, no Gateway
- Existing Connectors (Slack, Discord, Telegram) are reused for auth and credentials
- Channels add the persistent connection layer on top
- Runs in the background while McClaw is in the menu bar (same pattern as LocalScheduler)
