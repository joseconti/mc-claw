import Foundation
import Testing
@testable import McClawKit

// MARK: - URL Building Tests

@Suite("TwitchKit.URLBuilding")
struct TwitchURLBuildingTests {
    @Test("EventSub WebSocket URL")
    func eventSubWSURL() {
        let url = TwitchKit.eventSubWSURL()
        #expect(url.absoluteString == "wss://eventsub.wss.twitch.tv/ws")
    }

    @Test("Build subscriptions URL")
    func subscriptionsURL() {
        let url = TwitchKit.subscriptionsURL()
        #expect(url != nil)
        #expect(url!.absoluteString.contains("/eventsub/subscriptions"))
    }

    @Test("Build chat messages URL")
    func chatMessagesURL() {
        let url = TwitchKit.chatMessagesURL()
        #expect(url != nil)
        #expect(url!.absoluteString.contains("/chat/messages"))
    }

    @Test("Build users URL without login")
    func usersURL() {
        let url = TwitchKit.usersURL()
        #expect(url != nil)
        #expect(url!.absoluteString.contains("/users"))
        #expect(!url!.absoluteString.contains("login="))
    }

    @Test("Build users URL with login")
    func usersURLWithLogin() {
        let url = TwitchKit.usersURL(login: "botuser")
        #expect(url != nil)
        #expect(url!.absoluteString.contains("login=botuser"))
    }

    @Test("Build validate token URL")
    func validateTokenURL() {
        let url = TwitchKit.validateTokenURL()
        #expect(url != nil)
        #expect(url!.absoluteString.contains("oauth2/validate"))
    }
}

// MARK: - Parsing Tests

@Suite("TwitchKit.Parsing")
struct TwitchParsingTests {
    @Test("Parse session_welcome message")
    func parseSessionWelcome() {
        let json = """
        {
            "metadata": {
                "message_id": "m1",
                "message_type": "session_welcome",
                "message_timestamp": "2024-01-01T00:00:00Z"
            },
            "payload": {
                "session": {
                    "id": "sess1",
                    "status": "connected",
                    "connected_at": "2024-01-01T00:00:00Z",
                    "keepalive_timeout_seconds": 10
                }
            }
        }
        """.data(using: .utf8)!

        let msg = TwitchKit.parseWebSocketMessage(data: json)
        #expect(msg != nil)
        #expect(msg?.metadata.messageType == "session_welcome")

        let sessionId = TwitchKit.parseSessionId(from: msg!)
        #expect(sessionId == "sess1")
    }

    @Test("Parse notification with chat event")
    func parseNotification() {
        let json = """
        {
            "metadata": {
                "message_id": "m2",
                "message_type": "notification",
                "message_timestamp": "2024-01-01T00:00:00Z",
                "subscription_type": "channel.chat.message",
                "subscription_version": "1"
            },
            "payload": {
                "subscription": {
                    "id": "sub1",
                    "type": "channel.chat.message",
                    "version": "1",
                    "status": "enabled",
                    "condition": {"broadcaster_user_id": "bc1", "user_id": "u1"},
                    "transport": {"method": "websocket", "session_id": "sess1"}
                },
                "event": {
                    "broadcaster_user_id": "bc1",
                    "broadcaster_user_login": "streamer",
                    "broadcaster_user_name": "Streamer",
                    "chatter_user_id": "u2",
                    "chatter_user_login": "viewer",
                    "chatter_user_name": "Viewer",
                    "message_id": "chat1",
                    "message": {
                        "text": "Hello streamer!",
                        "fragments": [{"type": "text", "text": "Hello streamer!"}]
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let msg = TwitchKit.parseWebSocketMessage(data: json)
        #expect(msg != nil)

        let event = TwitchKit.parseChatEvent(from: msg!)
        #expect(event != nil)
        #expect(event?.chatterUserLogin == "viewer")
        #expect(event?.message.text == "Hello streamer!")
        #expect(event?.broadcasterUserId == "bc1")
    }

    @Test("Parse token validation")
    func parseTokenValidation() {
        let json = """
        {"client_id": "cid1", "login": "botuser", "user_id": "u1", "scopes": ["chat:read", "chat:edit"], "expires_in": 3600}
        """.data(using: .utf8)!

        let validation = TwitchKit.parseTokenValidation(data: json)
        #expect(validation != nil)
        #expect(validation?.clientId == "cid1")
        #expect(validation?.login == "botuser")
        #expect(validation?.scopes.count == 2)
        #expect(validation?.expiresIn == 3600)
    }

    @Test("Parse user from Helix response")
    func parseUser() {
        let json = """
        {
            "data": [
                {"id": "u1", "login": "botuser", "display_name": "BotUser", "broadcaster_type": ""}
            ]
        }
        """.data(using: .utf8)!

        let user = TwitchKit.parseUser(data: json)
        #expect(user != nil)
        #expect(user?.id == "u1")
        #expect(user?.login == "botuser")
        #expect(user?.displayName == "BotUser")
    }

    @Test("Parse user with empty data returns nil")
    func parseUserEmpty() {
        let json = """
        {"data": []}
        """.data(using: .utf8)!

        #expect(TwitchKit.parseUser(data: json) == nil)
    }

    @Test("parseSessionId returns nil for non-welcome")
    func parseSessionIdNonWelcome() {
        let json = """
        {
            "metadata": {"message_id": "m1", "message_type": "session_keepalive", "message_timestamp": "2024-01-01"},
            "payload": {}
        }
        """.data(using: .utf8)!

        let msg = TwitchKit.parseWebSocketMessage(data: json)!
        #expect(TwitchKit.parseSessionId(from: msg) == nil)
    }

    @Test("parseChatEvent returns nil for non-notification")
    func parseChatEventNonNotification() {
        let json = """
        {
            "metadata": {"message_id": "m1", "message_type": "session_welcome", "message_timestamp": "2024-01-01"},
            "payload": {"session": {"id": "s1", "status": "connected", "connected_at": "2024-01-01"}}
        }
        """.data(using: .utf8)!

        let msg = TwitchKit.parseWebSocketMessage(data: json)!
        #expect(TwitchKit.parseChatEvent(from: msg) == nil)
    }

    @Test("Parse invalid data returns nil")
    func parseInvalid() {
        let data = "bad".data(using: .utf8)!
        #expect(TwitchKit.parseWebSocketMessage(data: data) == nil)
        #expect(TwitchKit.parseTokenValidation(data: data) == nil)
        #expect(TwitchKit.parseUser(data: data) == nil)
    }
}

// MARK: - Event Filtering Tests

@Suite("TwitchKit.EventFiltering")
struct TwitchEventFilteringTests {
    private func makeChatEvent(chatterId: String = "u1", text: String = "Hello") -> TwitchKit.ChatEvent {
        TwitchKit.ChatEvent(
            broadcasterUserId: "bc1",
            broadcasterUserLogin: "streamer",
            broadcasterUserName: "Streamer",
            chatterUserId: chatterId,
            chatterUserLogin: "chatter",
            chatterUserName: "Chatter",
            messageId: "m1",
            message: TwitchKit.ChatMessage(text: text)
        )
    }

    @Test("Process event from other user")
    func processOtherUser() {
        let event = makeChatEvent(chatterId: "viewer1")
        #expect(TwitchKit.shouldProcess(event: event, botUserId: "bot1") == true)
    }

    @Test("Skip own events")
    func skipOwnEvents() {
        let event = makeChatEvent(chatterId: "bot1")
        #expect(TwitchKit.shouldProcess(event: event, botUserId: "bot1") == false)
    }

    @Test("Extract text from chat event")
    func extractText() {
        let event = makeChatEvent(text: "Hello world!")
        #expect(TwitchKit.extractText(from: event) == "Hello world!")
    }

    @Test("Extract text returns nil for empty message")
    func extractTextEmpty() {
        let event = makeChatEvent(text: "")
        #expect(TwitchKit.extractText(from: event) == nil)
    }
}

// MARK: - Request Body Tests

@Suite("TwitchKit.RequestBody")
struct TwitchRequestBodyTests {
    @Test("Build subscribe body")
    func subscribeBody() {
        let data = TwitchKit.subscribeBody(
            type: "channel.chat.message",
            version: "1",
            condition: ["broadcaster_user_id": "bc1", "user_id": "u1"],
            sessionId: "sess1"
        )
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["type"] as? String == "channel.chat.message")
        #expect(json?["version"] as? String == "1")
        let transport = json?["transport"] as? [String: Any]
        #expect(transport?["method"] as? String == "websocket")
        #expect(transport?["session_id"] as? String == "sess1")
    }

    @Test("Build chat message subscribe body")
    func chatMessageSubscribeBody() {
        let data = TwitchKit.chatMessageSubscribeBody(
            broadcasterUserId: "bc1", userId: "u1", sessionId: "sess1"
        )
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["type"] as? String == "channel.chat.message")
        let condition = json?["condition"] as? [String: String]
        #expect(condition?["broadcaster_user_id"] == "bc1")
        #expect(condition?["user_id"] == "u1")
    }

    @Test("Build send chat body")
    func sendChatBody() {
        let data = TwitchKit.sendChatBody(broadcasterId: "bc1", senderId: "u1", message: "Hello!")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["broadcaster_id"] as? String == "bc1")
        #expect(json?["sender_id"] as? String == "u1")
        #expect(json?["message"] as? String == "Hello!")
    }
}

// MARK: - Auth Headers Tests

@Suite("TwitchKit.AuthHeaders")
struct TwitchAuthHeadersTests {
    @Test("Build auth headers")
    func authHeaders() {
        let headers = TwitchKit.authHeaders(token: "tok1", clientId: "cid1")
        #expect(headers["Authorization"] == "Bearer tok1")
        #expect(headers["Client-Id"] == "cid1")
        #expect(headers["Content-Type"] == "application/json")
    }
}

// MARK: - Formatting Tests

@Suite("TwitchKit.Formatting")
struct TwitchFormattingTests {
    @Test("Truncate long text")
    func truncate() {
        let long = String(repeating: "A", count: 600)
        let truncated = TwitchKit.truncateForTwitch(long)
        #expect(truncated.count <= 500)
        #expect(truncated.hasSuffix("... (truncated)"))
    }

    @Test("Short text not truncated")
    func noTruncate() {
        #expect(TwitchKit.truncateForTwitch("Hello!") == "Hello!")
    }
}

// MARK: - Validation Tests

@Suite("TwitchKit.Validation")
struct TwitchValidationTests {
    @Test("Valid token")
    func validToken() {
        #expect(TwitchKit.isValidToken("abcdefghij1234567890") == true)
    }

    @Test("Invalid token - too short")
    func invalidTokenShort() {
        #expect(TwitchKit.isValidToken("short") == false)
    }

    @Test("Invalid token - empty")
    func invalidTokenEmpty() {
        #expect(TwitchKit.isValidToken("") == false)
    }

    @Test("Valid client ID")
    func validClientId() {
        #expect(TwitchKit.isValidClientId("abcdefghij1234567890abcdefghij") == true)
    }

    @Test("Invalid client ID - empty")
    func invalidClientIdEmpty() {
        #expect(TwitchKit.isValidClientId("") == false)
    }

    @Test("Invalid client ID - special chars")
    func invalidClientIdSpecialChars() {
        #expect(TwitchKit.isValidClientId("abc-def-ghi-jkl") == false)
    }

    @Test("Invalid client ID - too short")
    func invalidClientIdShort() {
        #expect(TwitchKit.isValidClientId("abc") == false)
    }
}

// MARK: - Model / Constants Tests

@Suite("TwitchKit.Constants")
struct TwitchConstantsTests {
    @Test("Message type constants")
    func messageTypes() {
        #expect(TwitchKit.sessionWelcome == "session_welcome")
        #expect(TwitchKit.sessionKeepalive == "session_keepalive")
        #expect(TwitchKit.notification == "notification")
        #expect(TwitchKit.sessionReconnect == "session_reconnect")
        #expect(TwitchKit.revocation == "revocation")
    }

    @Test("Subscription type constants")
    func subscriptionTypes() {
        #expect(TwitchKit.channelChatMessage == "channel.chat.message")
    }
}
