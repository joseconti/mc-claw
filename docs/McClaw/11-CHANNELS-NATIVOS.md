# 11 - Native Channels (Without Gateway)

## Status: Phase 1 (Telegram) ✅ | Phase 2 (Slack) ✅ | Phase 3-9 Pending

## Goal

Implement messaging Channels directly from McClaw, without depending on the Gateway. McClaw will maintain persistent background connections (same as LocalScheduler) using the native APIs/SDKs of each platform.

---

## Channels Implemented

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

---

## Channels to Implement

### Phase 3: Discord (Sprint 21)
- **Bot API** + **Gateway WebSocket** (wss://gateway.discord.gg)
- DiscordKit pure logic (McClawKit) + DiscordNativeService actor
- Gateway v10: Identify → heartbeat loop → READY → dispatch events
- Intents: GUILDS, GUILD_MESSAGES, DIRECT_MESSAGES, MESSAGE_CONTENT
- Auth: Bot Token (Discord ConnectorProvider already exists)
- Features: DM mode, allowed channel/guild IDs, mention stripping, embed support

### Phase 4: Matrix/Element (Sprint 21)
- **Client-Server API** via HTTP long-polling (`/sync` with since token)
- MatrixKit pure logic (McClawKit) + MatrixNativeService actor
- Open protocol, decentralized — bots are first-class citizens
- Auth: Access Token (homeserver URL + token)
- Features: Room filtering, E2EE-aware (unencrypted rooms), formatted messages (org.matrix.custom.html)

### Phase 5: Mattermost (Sprint 21)
- **REST API** + **WebSocket** (`/api/v4/websocket`)
- MattermostKit pure logic (McClawKit) + MattermostNativeService actor
- Open source (MIT), self-hostable, enterprise-friendly
- Auth: Personal Access Token or Bot Account token
- Features: Channel filtering, threaded replies, markdown support

### Phase 6: Mastodon/Fediverse (Sprint 22)
- **REST API** + **WebSocket streaming** (`/api/v1/streaming`)
- MastodonKit pure logic (McClawKit) + MastodonNativeService actor
- Decentralized — bot flag (`bot: true`) is official
- Auth: OAuth2 app token (instance URL + access token)
- Features: Mention-based replies, visibility control (public/unlisted/private), CW support, 500 char limit

### Phase 7: Zulip (Sprint 22)
- **REST API** + **Event queue** (`/api/v1/register` + `/api/v1/events` long-polling)
- ZulipKit pure logic (McClawKit) + ZulipNativeService actor
- Open source (Apache 2.0), bots are core feature
- Auth: Bot email + API key
- Features: Stream/topic filtering, topic-aware replies, markdown support

### Phase 8: Rocket.Chat (Sprint 22)
- **REST API** + **DDP WebSocket** (Distributed Data Protocol)
- RocketChatKit pure logic (McClawKit) + RocketChatNativeService actor
- Open source, self-hostable
- Auth: Personal Access Token (userId + token)
- Features: Channel filtering, threaded replies, DM mode

### Phase 9: Twitch (Sprint 23)
- **Helix REST API** + **EventSub WebSocket** (replaces deprecated IRC)
- TwitchKit pure logic (McClawKit) + TwitchNativeService actor
- Bots are fundamental to Twitch culture
- Auth: OAuth2 token (client ID + access token with chat scopes)
- Features: Channel-specific, chat commands, emote-aware, 500 char limit

---

## Dropped Channels

### ~~WhatsApp~~ ❌
- Meta explicitly bans general-purpose AI chatbots on WhatsApp Business Platform (Jan 2026)
- Cloud API requires webhook server — incompatible with desktop-only architecture

### ~~Signal~~ ❌
- No official Bot API (intentional — privacy focus)
- Creating automated accounts violates TOS
- All bot solutions are unofficial hacks with ban risk

### ~~WeChat~~ ❌
- Requires registered Chinese business entity + ICP license
- Actively kicks out AI chatbot apps
- Webhook-only, no desktop-direct connection

### ~~LINE~~ ❌
- Webhook-only (no long-polling or WebSocket for receiving)
- Requires Gateway server — incompatible with native channel architecture

### ~~Viber~~ ❌
- Webhook-only + mandatory commercial terms (~100€/month)
- Impractical for open desktop app

### ~~Google Chat~~ ❌
- Requires Google Cloud Pub/Sub or webhook endpoint
- No desktop-direct connection option

### ~~Microsoft Teams~~ ❌
- Requires publicly accessible HTTPS endpoint
- Push-based architecture incompatible with desktop-only

---

## Architecture

- **Connectors** = on-demand data read/write (`@fetch`)
- **Channels** = persistent messaging connections (bot listening + responding)
- Both 100% local, no Gateway
- Existing Connectors are reused for auth and credentials where available
- Channels add the persistent connection layer on top
- Runs in the background while McClaw is in the menu bar (same pattern as LocalScheduler)

### Pattern per Channel
```
[Platform]Kit.swift (McClawKit)     → Pure logic: models, URL building, parsing, formatting, validation
[Platform]NativeService.swift       → Actor: connection lifecycle, polling/WebSocket loop, message routing
NativeChannelsManager.swift         → Coordinator: start/stop, config persistence, CLIBridge dispatch
NativeChannelsSettingsTab.swift     → UI: status cards, config sheets, start/stop controls
[Platform]KitTests.swift            → Tests: parsing, filtering, formatting, validation
```

### Connector Dependencies
| Channel | Connector ID | Auth Method |
|---|---|---|
| Telegram | `comm.telegram` | Bot Token (Keychain) |
| Slack | `comm.slack` | Bot Token (xoxb-) + App Token (xapp-) |
| Discord | `comm.discord` | Bot Token (Keychain) |
| Matrix | New: `comm.matrix` | Homeserver URL + Access Token |
| Mattermost | New: `comm.mattermost` | Server URL + Personal Access Token |
| Mastodon | New: `comm.mastodon` | Instance URL + OAuth2 Token |
| Zulip | New: `comm.zulip` | Server URL + Bot Email + API Key |
| Rocket.Chat | New: `comm.rocketchat` | Server URL + User ID + Token |
| Twitch | New: `comm.twitch` | Client ID + OAuth2 Token |
