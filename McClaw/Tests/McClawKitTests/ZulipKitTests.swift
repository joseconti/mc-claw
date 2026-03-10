import Foundation
import Testing
@testable import McClawKit

// MARK: - URL Building Tests

@Suite("ZulipKit.URLBuilding")
struct ZulipURLBuildingTests {
    let server = "https://zulip.example.org"

    @Test("Build register URL")
    func registerURL() {
        let url = ZulipKit.registerURL(serverURL: server)
        #expect(url != nil)
        #expect(url!.absoluteString == "https://zulip.example.org/api/v1/register")
    }

    @Test("Build events URL")
    func eventsURL() {
        let url = ZulipKit.eventsURL(serverURL: server, queueId: "q1", lastEventId: 5)
        #expect(url != nil)
        let str = url!.absoluteString
        #expect(str.contains("/api/v1/events"))
        #expect(str.contains("queue_id=q1"))
        #expect(str.contains("last_event_id=5"))
    }

    @Test("Build messages URL")
    func messagesURL() {
        let url = ZulipKit.messagesURL(serverURL: server)
        #expect(url != nil)
        #expect(url!.absoluteString == "https://zulip.example.org/api/v1/messages")
    }

    @Test("Build users URL")
    func usersURL() {
        let url = ZulipKit.usersURL(serverURL: server)
        #expect(url != nil)
        #expect(url!.absoluteString == "https://zulip.example.org/api/v1/users/me")
    }

    @Test("URL strips trailing slash")
    func urlStripsSlash() {
        let url = ZulipKit.registerURL(serverURL: "https://zulip.example.org/")
        #expect(url != nil)
        #expect(!url!.absoluteString.contains("org//"))
    }
}

// MARK: - Auth Tests

@Suite("ZulipKit.Auth")
struct ZulipAuthTests {
    @Test("Build basic auth header")
    func basicAuthHeader() {
        let header = ZulipKit.basicAuthHeader(email: "bot@example.org", apiKey: "abcdef123456")
        #expect(header.hasPrefix("Basic "))
        // Decode and verify
        let base64 = String(header.dropFirst("Basic ".count))
        let decoded = Data(base64Encoded: base64).flatMap { String(data: $0, encoding: .utf8) }
        #expect(decoded == "bot@example.org:abcdef123456")
    }
}

// MARK: - Parsing Tests

@Suite("ZulipKit.Parsing")
struct ZulipParsingTests {
    @Test("Parse register response")
    func parseRegister() {
        let json = """
        {"queue_id": "q123", "last_event_id": -1, "event_queue_longpoll_timeout_seconds": 90}
        """.data(using: .utf8)!

        let resp = ZulipKit.parseRegisterResponse(data: json)
        #expect(resp != nil)
        #expect(resp?.queueId == "q123")
        #expect(resp?.lastEventId == -1)
    }

    @Test("Parse events")
    func parseEvents() {
        let json = """
        {
            "result": "success",
            "events": [
                {
                    "type": "message",
                    "id": 1,
                    "message": {
                        "id": 100,
                        "sender_id": 42,
                        "sender_full_name": "Alice",
                        "sender_email": "alice@example.org",
                        "content": "Hello!",
                        "display_recipient": "general",
                        "subject": "greetings",
                        "type": "stream",
                        "timestamp": 1700000000
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let events = ZulipKit.parseEvents(data: json)
        #expect(events != nil)
        #expect(events?.count == 1)
        #expect(events?[0].type == "message")
        #expect(events?[0].message?.senderFullName == "Alice")
        #expect(events?[0].message?.content == "Hello!")
        // Stream display recipient
        if case .stream(let name) = events?[0].message?.displayRecipient {
            #expect(name == "general")
        } else {
            Issue.record("Expected stream display recipient")
        }
    }

    @Test("Parse events with DM recipient")
    func parseEventsDM() {
        let json = """
        {
            "result": "success",
            "events": [
                {
                    "type": "message",
                    "id": 2,
                    "message": {
                        "id": 101,
                        "sender_id": 42,
                        "sender_full_name": "Alice",
                        "sender_email": "alice@example.org",
                        "content": "Hi",
                        "display_recipient": [{"id": 42, "full_name": "Alice", "email": "alice@example.org"}],
                        "type": "private",
                        "timestamp": 1700000000
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let events = ZulipKit.parseEvents(data: json)
        #expect(events != nil)
        if case .users(let users) = events?[0].message?.displayRecipient {
            #expect(users.count == 1)
            #expect(users[0].fullName == "Alice")
        } else {
            Issue.record("Expected users display recipient")
        }
    }

    @Test("Parse events with error result returns nil")
    func parseEventsError() {
        let json = """
        {"result": "error", "msg": "Bad event queue", "events": []}
        """.data(using: .utf8)!

        #expect(ZulipKit.parseEvents(data: json) == nil)
    }

    @Test("Parse user profile")
    func parseUserProfile() {
        let json = """
        {"user_id": 99, "full_name": "Bot", "email": "bot@example.org", "is_bot": true}
        """.data(using: .utf8)!

        let profile = ZulipKit.parseUserProfile(data: json)
        #expect(profile != nil)
        #expect(profile?.userId == 99)
        #expect(profile?.isBot == true)
    }

    @Test("Parse invalid data returns nil")
    func parseInvalid() {
        let data = "bad".data(using: .utf8)!
        #expect(ZulipKit.parseRegisterResponse(data: data) == nil)
        #expect(ZulipKit.parseEvents(data: data) == nil)
        #expect(ZulipKit.parseUserProfile(data: data) == nil)
    }
}

// MARK: - Event Filtering Tests

@Suite("ZulipKit.EventFiltering")
struct ZulipEventFilteringTests {
    @Test("Process message event from other user")
    func processOtherUser() {
        let msg = ZulipKit.ZulipMessage(
            id: 1, senderId: 42, senderFullName: "Alice",
            senderEmail: "a@b", content: "Hi",
            type: "stream", timestamp: 1700000000
        )
        let event = ZulipKit.Event(type: "message", id: 1, message: msg)
        #expect(ZulipKit.shouldProcess(event: event, myUserId: 99) == true)
    }

    @Test("Skip own message events")
    func skipOwnMessages() {
        let msg = ZulipKit.ZulipMessage(
            id: 1, senderId: 99, senderFullName: "Bot",
            senderEmail: "bot@b", content: "Reply",
            type: "stream", timestamp: 1700000000
        )
        let event = ZulipKit.Event(type: "message", id: 1, message: msg)
        #expect(ZulipKit.shouldProcess(event: event, myUserId: 99) == false)
    }

    @Test("Skip non-message events")
    func skipNonMessage() {
        let event = ZulipKit.Event(type: "heartbeat", id: 1)
        #expect(ZulipKit.shouldProcess(event: event, myUserId: 99) == false)
    }

    @Test("isStreamMessage and isDirectMessage")
    func messageType() {
        let stream = ZulipKit.ZulipMessage(
            id: 1, senderId: 1, senderFullName: "A",
            senderEmail: "a@b", content: "Hi",
            type: "stream", timestamp: 0
        )
        let dm = ZulipKit.ZulipMessage(
            id: 2, senderId: 1, senderFullName: "A",
            senderEmail: "a@b", content: "Hi",
            type: "private", timestamp: 0
        )
        #expect(ZulipKit.isStreamMessage(stream) == true)
        #expect(ZulipKit.isDirectMessage(stream) == false)
        #expect(ZulipKit.isStreamMessage(dm) == false)
        #expect(ZulipKit.isDirectMessage(dm) == true)
    }

    @Test("Extract text from message")
    func extractText() {
        let msg = ZulipKit.ZulipMessage(
            id: 1, senderId: 1, senderFullName: "A",
            senderEmail: "a@b", content: "Hello world",
            type: "stream", timestamp: 0
        )
        #expect(ZulipKit.extractText(from: msg) == "Hello world")
    }

    @Test("Extract text returns nil for empty content")
    func extractTextEmpty() {
        let msg = ZulipKit.ZulipMessage(
            id: 1, senderId: 1, senderFullName: "A",
            senderEmail: "a@b", content: "   ",
            type: "stream", timestamp: 0
        )
        #expect(ZulipKit.extractText(from: msg) == nil)
    }

    @Test("Topic from stream message")
    func topicFromMessage() {
        let msg = ZulipKit.ZulipMessage(
            id: 1, senderId: 1, senderFullName: "A",
            senderEmail: "a@b", content: "Hi",
            subject: "greetings",
            type: "stream", timestamp: 0
        )
        #expect(ZulipKit.topicFromMessage(msg) == "greetings")
    }

    @Test("Topic returns nil for DM")
    func topicFromDM() {
        let msg = ZulipKit.ZulipMessage(
            id: 1, senderId: 1, senderFullName: "A",
            senderEmail: "a@b", content: "Hi",
            subject: "ignored",
            type: "private", timestamp: 0
        )
        #expect(ZulipKit.topicFromMessage(msg) == nil)
    }
}

// MARK: - Request Body Tests

@Suite("ZulipKit.RequestBody")
struct ZulipRequestBodyTests {
    @Test("Build register body")
    func registerBody() {
        let data = ZulipKit.registerBody(eventTypes: ["message"])
        #expect(data != nil)
        let str = String(data: data!, encoding: .utf8)!
        #expect(str.contains("event_types="))
    }

    @Test("Build send stream message body")
    func sendStreamMessageBody() {
        let data = ZulipKit.sendStreamMessageBody(stream: "general", topic: "test", content: "Hello!")
        #expect(data != nil)
        let str = String(data: data!, encoding: .utf8)!
        #expect(str.contains("type=stream"))
        #expect(str.contains("to=general"))
        #expect(str.contains("topic=test"))
        #expect(str.contains("content=Hello!"))
    }

    @Test("Build send direct message body")
    func sendDirectMessageBody() {
        let data = ZulipKit.sendDirectMessageBody(to: "alice@example.org", content: "Hi")
        #expect(data != nil)
        let str = String(data: data!, encoding: .utf8)!
        #expect(str.contains("type=private"))
    }
}

// MARK: - Formatting Tests

@Suite("ZulipKit.Formatting")
struct ZulipFormattingTests {
    @Test("Truncate long text")
    func truncate() {
        let long = String(repeating: "A", count: 12000)
        let truncated = ZulipKit.truncateForZulip(long)
        #expect(truncated.count <= 10000)
        #expect(truncated.hasSuffix("… (truncated)"))
    }

    @Test("Short text not truncated")
    func noTruncate() {
        #expect(ZulipKit.truncateForZulip("Hello") == "Hello")
    }
}

// MARK: - Validation Tests

@Suite("ZulipKit.Validation")
struct ZulipValidationTests {
    @Test("Valid API key")
    func validAPIKey() {
        #expect(ZulipKit.isValidAPIKey("abcdefghijklmnopqrstuvwxyz1234") == true)
    }

    @Test("Invalid API key - too short")
    func invalidAPIKeyShort() {
        #expect(ZulipKit.isValidAPIKey("short") == false)
    }

    @Test("Valid email")
    func validEmail() {
        #expect(ZulipKit.isValidEmail("bot@example.org") == true)
    }

    @Test("Invalid email - no @")
    func invalidEmailNoAt() {
        #expect(ZulipKit.isValidEmail("botexample.org") == false)
    }

    @Test("Invalid email - no dot")
    func invalidEmailNoDot() {
        #expect(ZulipKit.isValidEmail("bot@localhost") == false)
    }

    @Test("Valid server URL")
    func validServerURL() {
        #expect(ZulipKit.isValidServerURL("https://zulip.example.org") == true)
        #expect(ZulipKit.isValidServerURL("http://localhost:9991") == true)
    }

    @Test("Invalid server URL - no scheme")
    func invalidServerURLNoScheme() {
        #expect(ZulipKit.isValidServerURL("zulip.example.org") == false)
    }

    @Test("Invalid server URL - empty")
    func invalidServerURLEmpty() {
        #expect(ZulipKit.isValidServerURL("") == false)
    }
}

// MARK: - Model Tests

@Suite("ZulipKit.Models")
struct ZulipModelTests {
    @Test("Message dateValue conversion")
    func messageDateValue() {
        let msg = ZulipKit.ZulipMessage(
            id: 1, senderId: 1, senderFullName: "A",
            senderEmail: "a@b", content: "Hi",
            type: "stream", timestamp: 1700000000
        )
        let expected = Date(timeIntervalSince1970: 1700000000)
        #expect(msg.dateValue == expected)
    }

    @Test("DisplayRecipient stream name accessor")
    func displayRecipientStreamName() {
        let recipient = ZulipKit.DisplayRecipient.stream("general")
        #expect(recipient.streamName == "general")
        #expect(recipient.recipientUsers == nil)
    }

    @Test("DisplayRecipient users accessor")
    func displayRecipientUsers() {
        let user = ZulipKit.DisplayRecipient.RecipientUser(id: 1, fullName: "Alice", email: "a@b")
        let recipient = ZulipKit.DisplayRecipient.users([user])
        #expect(recipient.streamName == nil)
        #expect(recipient.recipientUsers?.count == 1)
    }

    @Test("Message type constants")
    func typeConstants() {
        #expect(ZulipKit.streamType == "stream")
        #expect(ZulipKit.directType == "private")
    }
}
