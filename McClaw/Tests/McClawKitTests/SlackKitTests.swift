import Foundation
import Testing
@testable import McClawKit

// MARK: - Envelope Parsing Tests

@Suite("SlackKit.EnvelopeParsing")
struct SlackEnvelopeParsingTests {
    @Test("Parse hello envelope")
    func parseHello() {
        let json = """
        {"type": "hello"}
        """.data(using: .utf8)!

        let envelope = SlackKit.parseEnvelope(data: json)
        #expect(envelope != nil)
        #expect(envelope?.type == "hello")
        #expect(envelope?.envelopeId == nil)
    }

    @Test("Parse disconnect envelope")
    func parseDisconnect() {
        let json = """
        {"type": "disconnect", "reason": "link_disabled"}
        """.data(using: .utf8)!

        let envelope = SlackKit.parseEnvelope(data: json)
        #expect(envelope != nil)
        #expect(envelope?.type == "disconnect")
    }

    @Test("Parse events_api envelope with message")
    func parseEventsApiMessage() {
        let json = """
        {
            "envelope_id": "env-123",
            "type": "events_api",
            "accepts_response_payload": false,
            "retry_attempt": 0,
            "payload": {
                "event": {
                    "type": "message",
                    "channel": "C1234567",
                    "user": "U9876543",
                    "text": "Hello bot!",
                    "ts": "1700000000.000100",
                    "channel_type": "im"
                }
            }
        }
        """.data(using: .utf8)!

        let envelope = SlackKit.parseEnvelope(data: json)
        #expect(envelope != nil)
        #expect(envelope?.type == "events_api")
        #expect(envelope?.envelopeId == "env-123")
        #expect(envelope?.acceptsResponsePayload == false)
        #expect(envelope?.retryAttempt == 0)

        let event = envelope?.payload?.event
        #expect(event != nil)
        #expect(event?.type == "message")
        #expect(event?.channel == "C1234567")
        #expect(event?.user == "U9876543")
        #expect(event?.text == "Hello bot!")
        #expect(event?.channelType == "im")
    }

    @Test("Parse events_api envelope with app_mention")
    func parseAppMention() {
        let json = """
        {
            "envelope_id": "env-456",
            "type": "events_api",
            "payload": {
                "event": {
                    "type": "app_mention",
                    "channel": "C5555555",
                    "user": "U1111111",
                    "text": "<@U0BOT123> what is 2+2?",
                    "ts": "1700000001.000200"
                }
            }
        }
        """.data(using: .utf8)!

        let envelope = SlackKit.parseEnvelope(data: json)
        let event = envelope?.payload?.event
        #expect(event?.type == "app_mention")
        #expect(event?.isAppMention == true)
    }

    @Test("Parse invalid JSON returns nil")
    func parseInvalid() {
        let json = "not json".data(using: .utf8)!
        #expect(SlackKit.parseEnvelope(data: json) == nil)
    }
}

// MARK: - Bot Identity Tests

@Suite("SlackKit.BotIdentity")
struct SlackBotIdentityTests {
    @Test("Parse auth.test response")
    func parseAuthTest() {
        let json = """
        {
            "ok": true,
            "url": "https://team.slack.com/",
            "team": "My Workspace",
            "user": "mcclaw-bot",
            "team_id": "T1234567",
            "user_id": "U0BOT123",
            "bot_id": "B9999999"
        }
        """.data(using: .utf8)!

        let identity = SlackKit.parseBotIdentity(data: json)
        #expect(identity != nil)
        #expect(identity?.userId == "U0BOT123")
        #expect(identity?.botId == "B9999999")
        #expect(identity?.teamId == "T1234567")
        #expect(identity?.team == "My Workspace")
        #expect(identity?.user == "mcclaw-bot")
        #expect(identity?.displayName == "mcclaw-bot")
    }

    @Test("Parse failed auth.test returns nil")
    func parseFailedAuth() {
        let json = """
        {"ok": false, "error": "invalid_auth"}
        """.data(using: .utf8)!

        #expect(SlackKit.parseBotIdentity(data: json) == nil)
    }

    @Test("Bot identity displayName fallback")
    func displayNameFallback() {
        let identity = SlackKit.BotIdentity(userId: "U123", teamId: "T456")
        #expect(identity.displayName == "Bot U123")
    }
}

// MARK: - Acknowledge Tests

@Suite("SlackKit.Acknowledge")
struct SlackAcknowledgeTests {
    @Test("Build acknowledge body")
    func acknowledgeBody() {
        let body = SlackKit.acknowledgeBody(envelopeId: "env-123")
        #expect(body != nil)
        let json = try? JSONSerialization.jsonObject(with: body!) as? [String: Any]
        #expect(json?["envelope_id"] as? String == "env-123")
    }
}

// MARK: - URL Building Tests

@Suite("SlackKit.URLBuilding")
struct SlackURLBuildingTests {
    @Test("Build Web API URL")
    func webAPIURL() {
        let url = SlackKit.webAPIURL(method: "chat.postMessage")
        #expect(url != nil)
        #expect(url?.absoluteString == "https://slack.com/api/chat.postMessage")
    }

    @Test("Build connect URL")
    func connectURL() {
        let url = SlackKit.connectURL()
        #expect(url != nil)
        #expect(url?.absoluteString == "https://slack.com/api/apps.connections.open")
    }
}

// MARK: - WebSocket URL Parsing

@Suite("SlackKit.WebSocketURL")
struct SlackWebSocketURLTests {
    @Test("Parse WebSocket URL from connections.open")
    func parseWSURL() {
        let json = """
        {
            "ok": true,
            "url": "wss://wss-primary.slack.com/link/?ticket=abc123&app_id=A123"
        }
        """.data(using: .utf8)!

        let url = SlackKit.parseWebSocketURL(data: json)
        #expect(url != nil)
        #expect(url?.scheme == "wss")
    }

    @Test("Parse failed connections.open returns nil")
    func parseFailedWSURL() {
        let json = """
        {"ok": false, "error": "invalid_auth"}
        """.data(using: .utf8)!

        #expect(SlackKit.parseWebSocketURL(data: json) == nil)
    }
}

// MARK: - Request Body Tests

@Suite("SlackKit.RequestBody")
struct SlackRequestBodyTests {
    @Test("Build postMessage body")
    func postMessageBody() {
        let body = SlackKit.postMessageBody(channel: "C123", text: "Hello!")
        #expect(body != nil)
        let json = try? JSONSerialization.jsonObject(with: body!) as? [String: Any]
        #expect(json?["channel"] as? String == "C123")
        #expect(json?["text"] as? String == "Hello!")
        #expect(json?["thread_ts"] == nil)
    }

    @Test("Build postMessage body with thread")
    func postMessageBodyWithThread() {
        let body = SlackKit.postMessageBody(channel: "C123", text: "Reply", threadTs: "1700000000.000100")
        #expect(body != nil)
        let json = try? JSONSerialization.jsonObject(with: body!) as? [String: Any]
        #expect(json?["thread_ts"] as? String == "1700000000.000100")
    }
}

// MARK: - Event Filtering Tests

@Suite("SlackKit.EventFiltering")
struct SlackEventFilteringTests {
    @Test("User message should be processed")
    func processUserMessage() {
        let event = SlackKit.SlackEvent(type: "message", channel: "C123", user: "U456", text: "Hello")
        #expect(SlackKit.shouldProcess(event: event) == true)
    }

    @Test("App mention should be processed")
    func processAppMention() {
        let event = SlackKit.SlackEvent(type: "app_mention", channel: "C123", user: "U456", text: "<@U0BOT> hi")
        #expect(SlackKit.shouldProcess(event: event) == true)
    }

    @Test("Bot message should not be processed")
    func skipBotMessage() {
        let event = SlackKit.SlackEvent(type: "message", channel: "C123", text: "Bot reply", botId: "B999")
        #expect(SlackKit.shouldProcess(event: event) == false)
    }

    @Test("Subtype message should not be processed")
    func skipSubtypeMessage() {
        let event = SlackKit.SlackEvent(type: "message", subtype: "channel_join", channel: "C123")
        #expect(SlackKit.shouldProcess(event: event) == false)
    }

    @Test("Event without user should not be processed")
    func skipNoUser() {
        let event = SlackKit.SlackEvent(type: "message", channel: "C123", text: "ghost message")
        #expect(SlackKit.shouldProcess(event: event) == false)
    }

    @Test("isDirectMessage detects DM")
    func isDM() {
        let event = SlackKit.SlackEvent(type: "message", channelType: "im")
        #expect(event.isDirectMessage == true)
    }

    @Test("isDirectMessage false for channel")
    func isNotDM() {
        let event = SlackKit.SlackEvent(type: "message", channelType: "channel")
        #expect(event.isDirectMessage == false)
    }
}

// MARK: - Text Extraction Tests

@Suite("SlackKit.TextExtraction")
struct SlackTextExtractionTests {
    @Test("Extract text with bot mention stripped")
    func stripBotMention() {
        let event = SlackKit.SlackEvent(type: "app_mention", text: "<@U0BOT123> what is 2+2?")
        let text = SlackKit.extractText(from: event, botUserId: "U0BOT123")
        #expect(text == "what is 2+2?")
    }

    @Test("Extract text without mention")
    func noMention() {
        let event = SlackKit.SlackEvent(type: "message", text: "Hello world")
        let text = SlackKit.extractText(from: event, botUserId: "U0BOT123")
        #expect(text == "Hello world")
    }

    @Test("Extract text that becomes empty after stripping returns nil")
    func emptyAfterStrip() {
        let event = SlackKit.SlackEvent(type: "app_mention", text: "<@U0BOT123>")
        let text = SlackKit.extractText(from: event, botUserId: "U0BOT123")
        #expect(text == nil)
    }

    @Test("Extract text with nil text returns nil")
    func nilText() {
        let event = SlackKit.SlackEvent(type: "message")
        let text = SlackKit.extractText(from: event, botUserId: nil)
        #expect(text == nil)
    }
}

// MARK: - Formatting Tests

@Suite("SlackKit.Formatting")
struct SlackFormattingTests {
    @Test("Truncate long text")
    func truncate() {
        let long = String(repeating: "A", count: 5000)
        let truncated = SlackKit.truncateForSlack(long)
        #expect(truncated.count <= 4000)
        #expect(truncated.hasSuffix("… (truncated)"))
    }

    @Test("Short text is not truncated")
    func noTruncate() {
        #expect(SlackKit.truncateForSlack("Hello!") == "Hello!")
    }

    @Test("Escape mrkdwn characters")
    func escapeMrkdwn() {
        let text = "Use <this> & *that*"
        let escaped = SlackKit.escapeSlackMrkdwn(text)
        #expect(escaped == "Use &lt;this&gt; &amp; *that*")
    }
}

// MARK: - Token Validation Tests

@Suite("SlackKit.TokenValidation")
struct SlackTokenValidationTests {
    @Test("Valid bot token")
    func validBotToken() {
        #expect(SlackKit.isValidBotToken("xoxb-1234567890-1234567890123-abcdefghijklmnopqrstuvwx") == true)
    }

    @Test("Invalid bot token - wrong prefix")
    func invalidBotTokenPrefix() {
        #expect(SlackKit.isValidBotToken("xoxp-1234567890") == false)
    }

    @Test("Invalid bot token - too short")
    func invalidBotTokenShort() {
        #expect(SlackKit.isValidBotToken("xoxb-short") == false)
    }

    @Test("Valid app-level token")
    func validAppToken() {
        #expect(SlackKit.isValidAppToken("xapp-1-A1234567890-1234567890123-abcdefghijklmnop") == true)
    }

    @Test("Invalid app token - wrong prefix")
    func invalidAppTokenPrefix() {
        #expect(SlackKit.isValidAppToken("xoxb-1234567890") == false)
    }

    @Test("Invalid app token - too short")
    func invalidAppTokenShort() {
        #expect(SlackKit.isValidAppToken("xapp-short") == false)
    }

    @Test("Empty tokens are invalid")
    func emptyTokens() {
        #expect(SlackKit.isValidBotToken("") == false)
        #expect(SlackKit.isValidAppToken("") == false)
    }
}

// MARK: - Model Tests

@Suite("SlackKit.Models")
struct SlackModelTests {
    @Test("SlackEvent isUserMessage")
    func isUserMessage() {
        let event = SlackKit.SlackEvent(type: "message", channel: "C123", user: "U456", text: "Hi")
        #expect(event.isUserMessage == true)
    }

    @Test("SlackEvent with subtype is not user message")
    func subtypeNotUserMessage() {
        let event = SlackKit.SlackEvent(type: "message", subtype: "bot_message", channel: "C123", user: "U456", text: "Hi")
        #expect(event.isUserMessage == false)
    }

    @Test("SlackEvent with botId is not user message")
    func botIdNotUserMessage() {
        let event = SlackKit.SlackEvent(type: "message", channel: "C123", user: "U456", text: "Hi", botId: "B789")
        #expect(event.isUserMessage == false)
    }
}
