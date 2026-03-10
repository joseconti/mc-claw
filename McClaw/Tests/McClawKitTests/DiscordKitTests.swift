import Foundation
import Testing
@testable import McClawKit

// MARK: - URL Building Tests

@Suite("DiscordKit.URLBuilding")
struct DiscordKitURLBuildingTests {
    @Test("Build Gateway URL")
    func gatewayURL() {
        let url = DiscordKit.gatewayURL()
        #expect(url != nil)
        #expect(url?.absoluteString == "wss://gateway.discord.gg/?v=10&encoding=json")
    }

    @Test("Build channel messages URL")
    func channelMessagesURL() {
        let url = DiscordKit.channelMessagesURL(channelId: "123456")
        #expect(url != nil)
        #expect(url?.absoluteString == "https://discord.com/api/v10/channels/123456/messages")
    }

    @Test("Build current user URL")
    func currentUserURL() {
        let url = DiscordKit.currentUserURL()
        #expect(url != nil)
        #expect(url?.absoluteString == "https://discord.com/api/v10/users/@me")
    }

    @Test("Build REST URL with path")
    func restURL() {
        let url = DiscordKit.restURL(path: "/guilds/999")
        #expect(url != nil)
        #expect(url?.absoluteString == "https://discord.com/api/v10/guilds/999")
    }
}

// MARK: - Parsing Tests

@Suite("DiscordKit.Parsing")
struct DiscordKitParsingTests {
    @Test("Parse Gateway payload")
    func parseGatewayPayload() {
        let json = """
        {"op": 10, "d": {"heartbeat_interval": 41250}, "s": null, "t": null}
        """.data(using: .utf8)!

        let payload = DiscordKit.parseGatewayPayload(data: json)
        #expect(payload != nil)
        #expect(payload?.op == 10)
    }

    @Test("Parse Hello from payload")
    func parseHello() {
        let json = """
        {"op": 10, "d": {"heartbeat_interval": 41250}, "s": null, "t": null}
        """.data(using: .utf8)!

        let payload = DiscordKit.parseGatewayPayload(data: json)!
        let hello = DiscordKit.parseHello(payload: payload)
        #expect(hello != nil)
        #expect(hello?.heartbeatInterval == 41250)
    }

    @Test("Parse Hello returns nil for wrong opcode")
    func parseHelloWrongOp() {
        let json = """
        {"op": 0, "d": {"heartbeat_interval": 41250}, "s": null, "t": null}
        """.data(using: .utf8)!

        let payload = DiscordKit.parseGatewayPayload(data: json)!
        let hello = DiscordKit.parseHello(payload: payload)
        #expect(hello == nil)
    }

    @Test("Parse Ready from payload")
    func parseReady() {
        let json = """
        {
            "op": 0, "s": 1, "t": "READY",
            "d": {
                "v": 10,
                "session_id": "sess_abc",
                "user": {"id": "111", "username": "TestBot", "bot": true},
                "guilds": [{"id": "222", "unavailable": true}],
                "resume_gateway_url": "wss://resume.discord.gg"
            }
        }
        """.data(using: .utf8)!

        let payload = DiscordKit.parseGatewayPayload(data: json)!
        let ready = DiscordKit.parseReady(payload: payload)
        #expect(ready != nil)
        #expect(ready?.user.id == "111")
        #expect(ready?.user.username == "TestBot")
        #expect(ready?.sessionId == "sess_abc")
        #expect(ready?.guilds.count == 1)
    }

    @Test("Parse MESSAGE_CREATE from payload")
    func parseMessageCreate() {
        let json = """
        {
            "op": 0, "s": 5, "t": "MESSAGE_CREATE",
            "d": {
                "id": "msg1",
                "channel_id": "ch1",
                "author": {"id": "user1", "username": "Alice"},
                "content": "Hello bot!",
                "timestamp": "2024-01-01T00:00:00.000Z"
            }
        }
        """.data(using: .utf8)!

        let payload = DiscordKit.parseGatewayPayload(data: json)!
        let msg = DiscordKit.parseMessageCreate(payload: payload)
        #expect(msg != nil)
        #expect(msg?.content == "Hello bot!")
        #expect(msg?.author.username == "Alice")
        #expect(msg?.channelId == "ch1")
    }

    @Test("Parse User from REST response")
    func parseUser() {
        let json = """
        {"id": "123", "username": "bot_user", "discriminator": "0", "bot": true, "global_name": "Bot User"}
        """.data(using: .utf8)!

        let user = DiscordKit.parseUser(data: json)
        #expect(user != nil)
        #expect(user?.id == "123")
        #expect(user?.displayName == "Bot User")
        #expect(user?.isBot == true)
    }

    @Test("Parse invalid data returns nil")
    func parseInvalid() {
        let data = "not json".data(using: .utf8)!
        #expect(DiscordKit.parseGatewayPayload(data: data) == nil)
        #expect(DiscordKit.parseUser(data: data) == nil)
    }
}

// MARK: - Event Classification Tests

@Suite("DiscordKit.EventClassification")
struct DiscordKitEventClassificationTests {
    @Test("Classify hello event")
    func classifyHello() {
        let json = """
        {"op": 10, "d": {"heartbeat_interval": 41250}, "s": null, "t": null}
        """.data(using: .utf8)!
        let payload = DiscordKit.parseGatewayPayload(data: json)!
        let event = DiscordKit.classifyPayload(payload)
        if case .hello(let interval) = event {
            #expect(interval == 41250)
        } else {
            Issue.record("Expected hello event")
        }
    }

    @Test("Classify reconnect event")
    func classifyReconnect() {
        let json = """
        {"op": 7, "d": null, "s": null, "t": null}
        """.data(using: .utf8)!
        let payload = DiscordKit.parseGatewayPayload(data: json)!
        let event = DiscordKit.classifyPayload(payload)
        if case .reconnect = event {
            // pass
        } else {
            Issue.record("Expected reconnect event")
        }
    }

    @Test("Classify heartbeat request")
    func classifyHeartbeat() {
        let json = """
        {"op": 1, "d": null, "s": null, "t": null}
        """.data(using: .utf8)!
        let payload = DiscordKit.parseGatewayPayload(data: json)!
        let event = DiscordKit.classifyPayload(payload)
        if case .heartbeatRequest = event {
            // pass
        } else {
            Issue.record("Expected heartbeat request event")
        }
    }
}

// MARK: - Filtering Tests

@Suite("DiscordKit.Filtering")
struct DiscordKitFilteringTests {
    private func makeMessage(authorId: String = "user1", isBot: Bool = false, content: String = "Hello") -> DiscordKit.Message {
        DiscordKit.Message(
            id: "msg1",
            channelId: "ch1",
            author: DiscordKit.User(id: authorId, username: "test", bot: isBot),
            content: content,
            timestamp: "2024-01-01T00:00:00Z"
        )
    }

    @Test("Process normal user message")
    func processNormalMessage() {
        let msg = makeMessage()
        #expect(DiscordKit.shouldProcess(message: msg, botUserId: "bot1") == true)
    }

    @Test("Skip bot messages")
    func skipBotMessages() {
        let msg = makeMessage(isBot: true)
        #expect(DiscordKit.shouldProcess(message: msg, botUserId: "bot1") == false)
    }

    @Test("Skip own messages")
    func skipOwnMessages() {
        let msg = makeMessage(authorId: "bot1")
        #expect(DiscordKit.shouldProcess(message: msg, botUserId: "bot1") == false)
    }

    @Test("Skip empty messages")
    func skipEmptyMessages() {
        let msg = makeMessage(content: "")
        #expect(DiscordKit.shouldProcess(message: msg, botUserId: "bot1") == false)
    }

    @Test("Extract text stripping bot mention")
    func extractTextStripMention() {
        let msg = makeMessage(content: "<@bot1> What time is it?")
        let text = DiscordKit.extractText(from: msg, botUserId: "bot1")
        #expect(text == "What time is it?")
    }

    @Test("Extract text stripping nickname mention")
    func extractTextStripNickMention() {
        let msg = makeMessage(content: "<@!bot1> Hello")
        let text = DiscordKit.extractText(from: msg, botUserId: "bot1")
        #expect(text == "Hello")
    }

    @Test("Extract text returns nil for mention-only content")
    func extractTextMentionOnly() {
        let msg = makeMessage(content: "<@bot1>")
        let text = DiscordKit.extractText(from: msg, botUserId: "bot1")
        #expect(text == nil)
    }

    @Test("Check if message mentions bot")
    func isMentioned() {
        let msg = makeMessage(content: "<@bot1> hey")
        #expect(DiscordKit.isMentioned(in: msg, botUserId: "bot1") == true)
        #expect(DiscordKit.isMentioned(in: msg, botUserId: "other") == false)
    }
}

// MARK: - Formatting Tests

@Suite("DiscordKit.Formatting")
struct DiscordKitFormattingTests {
    @Test("Truncate long text")
    func truncate() {
        let long = String(repeating: "A", count: 2500)
        let truncated = DiscordKit.truncateForDiscord(long)
        #expect(truncated.count <= 2000)
        #expect(truncated.hasSuffix("… (truncated)"))
    }

    @Test("Short text not truncated")
    func noTruncate() {
        let short = "Hello!"
        #expect(DiscordKit.truncateForDiscord(short) == short)
    }

    @Test("Format user mention")
    func formatMention() {
        #expect(DiscordKit.formatUserMention("123") == "<@123>")
    }

    @Test("Format channel mention")
    func formatChannelMention() {
        #expect(DiscordKit.formatChannelMention("456") == "<#456>")
    }

    @Test("Escape markdown")
    func escapeMarkdown() {
        let result = DiscordKit.escapeDiscordMarkdown("*bold* _italic_")
        #expect(result.contains("\\*"))
        #expect(result.contains("\\_"))
    }
}

// MARK: - Token Validation Tests

@Suite("DiscordKit.TokenValidation")
struct DiscordKitTokenValidationTests {
    @Test("Valid bot token")
    func validToken() {
        #expect(DiscordKit.isValidBotToken("MTIzNDU2Nzg5MDEyMzQ1Njc4OQ.AbCdEf.GhIjKlMnOpQrStUvWxYz0123456789_-") == true)
    }

    @Test("Invalid - no dots")
    func invalidNoDots() {
        #expect(DiscordKit.isValidBotToken("this-is-not-a-valid-token-without-dots-at-all") == false)
    }

    @Test("Invalid - too short")
    func invalidShort() {
        #expect(DiscordKit.isValidBotToken("a.b.c") == false)
    }

    @Test("Invalid - empty")
    func invalidEmpty() {
        #expect(DiscordKit.isValidBotToken("") == false)
    }
}

// MARK: - Request Body Tests

@Suite("DiscordKit.RequestBody")
struct DiscordKitRequestBodyTests {
    @Test("Build identify payload")
    func identifyPayload() {
        let data = DiscordKit.identifyPayload(token: "test-token", intents: 513)
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["op"] as? Int == 2)
        let d = json?["d"] as? [String: Any]
        #expect(d?["token"] as? String == "test-token")
        #expect(d?["intents"] as? Int == 513)
    }

    @Test("Build heartbeat payload with sequence")
    func heartbeatWithSeq() {
        let data = DiscordKit.heartbeatPayload(sequence: 42)
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["op"] as? Int == 1)
        #expect(json?["d"] as? Int == 42)
    }

    @Test("Build heartbeat payload without sequence")
    func heartbeatNoSeq() {
        let data = DiscordKit.heartbeatPayload(sequence: nil)
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["op"] as? Int == 1)
    }

    @Test("Build send message body")
    func sendMessageBody() {
        let data = DiscordKit.sendMessageBody(content: "Hello!")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["content"] as? String == "Hello!")
    }
}

// MARK: - Model Tests

@Suite("DiscordKit.Models")
struct DiscordKitModelTests {
    @Test("User displayName prefers globalName")
    func userDisplayName() {
        let user = DiscordKit.User(id: "1", username: "alice", globalName: "Alice Wonder")
        #expect(user.displayName == "Alice Wonder")
    }

    @Test("User displayName falls back to username")
    func userDisplayNameFallback() {
        let user = DiscordKit.User(id: "1", username: "alice")
        #expect(user.displayName == "alice")
    }

    @Test("Channel isDM")
    func channelIsDM() {
        let dm = DiscordKit.Channel(id: "1", type: 1)
        let group = DiscordKit.Channel(id: "2", type: 3)
        let text = DiscordKit.Channel(id: "3", type: 0)
        #expect(dm.isDM == true)
        #expect(group.isDM == true)
        #expect(text.isDM == false)
    }

    @Test("Channel displayName")
    func channelDisplayName() {
        let named = DiscordKit.Channel(id: "1", type: 0, name: "general")
        let unnamed = DiscordKit.Channel(id: "2", type: 0)
        #expect(named.displayName == "#general")
        #expect(unnamed.displayName == "Channel 2")
    }

    @Test("Message isFromBot")
    func messageIsFromBot() {
        let botMsg = DiscordKit.Message(
            id: "1", channelId: "ch1",
            author: DiscordKit.User(id: "1", username: "bot", bot: true),
            content: "hi", timestamp: "2024-01-01"
        )
        let userMsg = DiscordKit.Message(
            id: "2", channelId: "ch1",
            author: DiscordKit.User(id: "2", username: "user"),
            content: "hi", timestamp: "2024-01-01"
        )
        #expect(botMsg.isFromBot == true)
        #expect(userMsg.isFromBot == false)
    }

    @Test("Gateway opcodes are correct")
    func opcodes() {
        #expect(DiscordKit.opcodeDispatch == 0)
        #expect(DiscordKit.opcodeHeartbeat == 1)
        #expect(DiscordKit.opcodeIdentify == 2)
        #expect(DiscordKit.opcodeReconnect == 7)
        #expect(DiscordKit.opcodeInvalidSession == 9)
        #expect(DiscordKit.opcodeHello == 10)
        #expect(DiscordKit.opcodeHeartbeatAck == 11)
    }

    @Test("Default intents value")
    func defaultIntents() {
        #expect(DiscordKit.defaultIntents == 33281)
    }
}
