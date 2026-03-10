import Foundation
import Testing
@testable import McClawKit

// MARK: - URL Building Tests

@Suite("RocketChatKit.URLBuilding")
struct RocketChatURLBuildingTests {
    let server = "https://chat.example.com"

    @Test("Build WebSocket URL from HTTPS")
    func wsURLFromHTTPS() {
        let url = RocketChatKit.webSocketURL(serverURL: server)
        #expect(url != nil)
        #expect(url?.absoluteString == "wss://chat.example.com/websocket")
    }

    @Test("Build WebSocket URL from HTTP")
    func wsURLFromHTTP() {
        let url = RocketChatKit.webSocketURL(serverURL: "http://localhost:3000")
        #expect(url != nil)
        #expect(url?.absoluteString == "ws://localhost:3000/websocket")
    }

    @Test("Build WebSocket URL strips trailing slash")
    func wsURLStripsSlash() {
        let url = RocketChatKit.webSocketURL(serverURL: "https://chat.example.com/")
        #expect(url != nil)
        #expect(url?.absoluteString == "wss://chat.example.com/websocket")
    }

    @Test("Build WebSocket URL from bare hostname adds wss")
    func wsURLBareHostname() {
        let url = RocketChatKit.webSocketURL(serverURL: "chat.example.com")
        #expect(url != nil)
        #expect(url?.absoluteString == "wss://chat.example.com/websocket")
    }

    @Test("Build sendMessage URL")
    func sendMessageURL() {
        let url = RocketChatKit.sendMessageURL(serverURL: server)
        #expect(url != nil)
        #expect(url!.absoluteString.contains("/api/v1/chat.sendMessage"))
    }

    @Test("Build me URL")
    func meURL() {
        let url = RocketChatKit.meURL(serverURL: server)
        #expect(url != nil)
        #expect(url!.absoluteString.contains("/api/v1/me"))
    }
}

// MARK: - DDP Parsing Tests

@Suite("RocketChatKit.DDPParsing")
struct RocketChatDDPParsingTests {
    @Test("Parse DDP connected message")
    func parseDDPConnected() {
        let json = """
        {"msg": "connected", "session": "sess1"}
        """.data(using: .utf8)!

        let ddp = RocketChatKit.parseDDPMessage(data: json)
        #expect(ddp != nil)
        #expect(ddp?.msg == "connected")
        #expect(ddp?.isConnected == true)
    }

    @Test("Parse DDP ping message")
    func parseDDPPing() {
        let json = """
        {"msg": "ping"}
        """.data(using: .utf8)!

        let ddp = RocketChatKit.parseDDPMessage(data: json)
        #expect(ddp != nil)
        #expect(ddp?.isPing == true)
    }

    @Test("Parse DDP changed message")
    func parseDDPChanged() {
        let json = """
        {"msg": "changed", "collection": "stream-room-messages", "id": "sub-0"}
        """.data(using: .utf8)!

        let ddp = RocketChatKit.parseDDPMessage(data: json)
        #expect(ddp != nil)
        #expect(ddp?.isChanged == true)
        #expect(ddp?.collection == "stream-room-messages")
    }

    @Test("Parse DDP result message")
    func parseDDPResult() {
        let json = """
        {"msg": "result", "id": "login-1", "result": {"id": "u1", "token": "tok1"}}
        """.data(using: .utf8)!

        let ddp = RocketChatKit.parseDDPMessage(data: json)
        #expect(ddp != nil)
        #expect(ddp?.isResult == true)
        #expect(ddp?.id == "login-1")
    }

    @Test("Parse message from DDP changed event")
    func parseMessage() {
        let json = """
        {
            "msg": "changed",
            "collection": "stream-room-messages",
            "id": "sub-0",
            "fields": {
                "args": [
                    {
                        "_id": "msg1",
                        "rid": "room1",
                        "msg": "Hello world",
                        "ts": {"$date": 1700000000000},
                        "u": {"_id": "u1", "username": "alice", "name": "Alice Smith"},
                        "tmid": "thread1"
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let msg = RocketChatKit.parseMessage(from: json)
        #expect(msg != nil)
        #expect(msg?.id == "msg1")
        #expect(msg?.rid == "room1")
        #expect(msg?.msg == "Hello world")
        #expect(msg?.user.username == "alice")
        #expect(msg?.user.name == "Alice Smith")
        #expect(msg?.tmid == "thread1")
    }

    @Test("Parse me response")
    func parseMe() {
        let json = """
        {"_id": "u1", "username": "bot_user", "name": "Bot", "status": "online", "active": true}
        """.data(using: .utf8)!

        let me = RocketChatKit.parseMe(data: json)
        #expect(me != nil)
        #expect(me?.id == "u1")
        #expect(me?.username == "bot_user")
        #expect(me?.displayName == "Bot")
        #expect(me?.active == true)
    }

    @Test("Parse login result from DDP result")
    func parseLoginResult() {
        let json = """
        {"msg": "result", "id": "login-1", "result": {"id": "u1", "token": "tok123", "tokenExpires": {"$date": 1700000000000}}}
        """.data(using: .utf8)!

        let ddp = RocketChatKit.parseDDPMessage(data: json)!
        let login = RocketChatKit.parseLoginResult(from: ddp)
        #expect(login != nil)
        #expect(login?.id == "u1")
        #expect(login?.token == "tok123")
    }

    @Test("Parse invalid data returns nil")
    func parseInvalid() {
        let data = "bad".data(using: .utf8)!
        #expect(RocketChatKit.parseDDPMessage(data: data) == nil)
        #expect(RocketChatKit.parseMessage(from: data) == nil)
        #expect(RocketChatKit.parseMe(data: data) == nil)
    }
}

// MARK: - DDP Payload Building Tests

@Suite("RocketChatKit.DDPPayloads")
struct RocketChatDDPPayloadsTests {
    @Test("Build connect payload")
    func connectPayload() {
        let data = RocketChatKit.connectPayload()
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["msg"] as? String == "connect")
        #expect(json?["version"] as? String == "1")
    }

    @Test("Build login payload")
    func loginPayload() {
        let data = RocketChatKit.loginPayload(token: "my-token", id: "login-1")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["msg"] as? String == "method")
        #expect(json?["method"] as? String == "login")
        #expect(json?["id"] as? String == "login-1")
    }

    @Test("Build pong payload without id")
    func pongPayloadNoId() {
        let data = RocketChatKit.pongPayload()
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["msg"] as? String == "pong")
    }

    @Test("Build pong payload with id")
    func pongPayloadWithId() {
        let data = RocketChatKit.pongPayload(id: "abc")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["msg"] as? String == "pong")
        #expect(json?["id"] as? String == "abc")
    }

    @Test("Build subscribe messages payload")
    func subscribeMessagesPayload() {
        let data = RocketChatKit.subscribeMessagesPayload(subId: "sub-0")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["msg"] as? String == "sub")
        #expect(json?["id"] as? String == "sub-0")
        #expect(json?["name"] as? String == "stream-room-messages")
    }

    @Test("Build send message body")
    func sendMessageBody() {
        let data = RocketChatKit.sendMessageBody(roomId: "room1", text: "Hello!", threadId: "t1")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        let msg = json?["message"] as? [String: Any]
        #expect(msg?["rid"] as? String == "room1")
        #expect(msg?["msg"] as? String == "Hello!")
        #expect(msg?["tmid"] as? String == "t1")
    }
}

// MARK: - Auth Headers Tests

@Suite("RocketChatKit.AuthHeaders")
struct RocketChatAuthHeadersTests {
    @Test("Build auth headers")
    func authHeaders() {
        let headers = RocketChatKit.authHeaders(userId: "u1", token: "tok1")
        #expect(headers["X-Auth-Token"] == "tok1")
        #expect(headers["X-User-Id"] == "u1")
        #expect(headers["Content-Type"] == "application/json")
    }
}

// MARK: - Event Filtering Tests

@Suite("RocketChatKit.EventFiltering")
struct RocketChatEventFilteringTests {
    @Test("Process message from other user")
    func processOtherUser() {
        let msg = RocketChatKit.RCMessage(
            id: "m1", rid: "r1", msg: "Hello",
            ts: "123", user: RocketChatKit.RCUser(id: "u1", username: "alice")
        )
        #expect(RocketChatKit.shouldProcess(message: msg, myUserId: "bot1") == true)
    }

    @Test("Skip own messages")
    func skipOwnMessages() {
        let msg = RocketChatKit.RCMessage(
            id: "m1", rid: "r1", msg: "Hello",
            ts: "123", user: RocketChatKit.RCUser(id: "bot1", username: "bot")
        )
        #expect(RocketChatKit.shouldProcess(message: msg, myUserId: "bot1") == false)
    }

    @Test("Skip empty messages")
    func skipEmpty() {
        let msg = RocketChatKit.RCMessage(
            id: "m1", rid: "r1", msg: "",
            ts: "123", user: RocketChatKit.RCUser(id: "u1", username: "alice")
        )
        #expect(RocketChatKit.shouldProcess(message: msg, myUserId: "bot1") == false)
    }

    @Test("Extract text from message")
    func extractText() {
        let msg = RocketChatKit.RCMessage(
            id: "m1", rid: "r1", msg: "Hello world",
            ts: "123", user: RocketChatKit.RCUser(id: "u1", username: "alice")
        )
        #expect(RocketChatKit.extractText(from: msg) == "Hello world")
    }

    @Test("Extract text returns nil for whitespace-only")
    func extractTextWhitespace() {
        let msg = RocketChatKit.RCMessage(
            id: "m1", rid: "r1", msg: "   ",
            ts: "123", user: RocketChatKit.RCUser(id: "u1", username: "alice")
        )
        #expect(RocketChatKit.extractText(from: msg) == nil)
    }
}

// MARK: - Formatting Tests

@Suite("RocketChatKit.Formatting")
struct RocketChatFormattingTests {
    @Test("Truncate long text")
    func truncate() {
        let long = String(repeating: "A", count: 70000)
        let truncated = RocketChatKit.truncateForRocketChat(long)
        #expect(truncated.count <= 65536)
        #expect(truncated.hasSuffix("… (truncated)"))
    }

    @Test("Short text not truncated")
    func noTruncate() {
        #expect(RocketChatKit.truncateForRocketChat("Hello") == "Hello")
    }
}

// MARK: - Validation Tests

@Suite("RocketChatKit.Validation")
struct RocketChatValidationTests {
    @Test("Valid token")
    func validToken() {
        #expect(RocketChatKit.isValidToken("abcdefghij1234567890") == true)
    }

    @Test("Invalid token - too short")
    func invalidTokenShort() {
        #expect(RocketChatKit.isValidToken("short") == false)
    }

    @Test("Valid server URL")
    func validServerURL() {
        #expect(RocketChatKit.isValidServerURL("https://chat.example.com") == true)
        #expect(RocketChatKit.isValidServerURL("http://localhost:3000") == true)
    }

    @Test("Invalid server URL")
    func invalidServerURL() {
        #expect(RocketChatKit.isValidServerURL("ftp://chat.example.com") == false)
        #expect(RocketChatKit.isValidServerURL("") == false)
    }
}

// MARK: - Model Tests

@Suite("RocketChatKit.Models")
struct RocketChatModelTests {
    @Test("RCUser displayName prefers name")
    func userDisplayName() {
        let user = RocketChatKit.RCUser(id: "1", username: "alice", name: "Alice Smith")
        #expect(user.displayName == "Alice Smith")
    }

    @Test("RCUser displayName falls back to username")
    func userDisplayNameFallback() {
        let user = RocketChatKit.RCUser(id: "1", username: "alice")
        #expect(user.displayName == "alice")
    }

    @Test("RCChannel displayName")
    func channelDisplayName() {
        let named = RocketChatKit.RCChannel(id: "1", name: "general", type: "c")
        let unnamed = RocketChatKit.RCChannel(id: "2", type: "d")
        #expect(named.displayName == "general")
        #expect(unnamed.displayName == "Room 2")
    }

    @Test("MeResponse displayName")
    func meDisplayName() {
        let me = RocketChatKit.MeResponse(id: "1", username: "bot", name: "Bot User")
        #expect(me.displayName == "Bot User")

        let meNoName = RocketChatKit.MeResponse(id: "1", username: "bot")
        #expect(meNoName.displayName == "bot")
    }

    @Test("DDP message type constants")
    func ddpConstants() {
        #expect(RocketChatKit.ddpConnect == "connect")
        #expect(RocketChatKit.ddpConnected == "connected")
        #expect(RocketChatKit.ddpPing == "ping")
        #expect(RocketChatKit.ddpPong == "pong")
        #expect(RocketChatKit.ddpChanged == "changed")
        #expect(RocketChatKit.ddpResult == "result")
    }
}
