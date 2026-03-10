import Foundation
import Testing
@testable import McClawKit

// MARK: - URL Building Tests

@Suite("MatrixKit.URLBuilding")
struct MatrixURLBuildingTests {
    let hs = "https://matrix.example.org"

    @Test("Build sync URL without since token")
    func syncURLNoSince() {
        let url = MatrixKit.syncURL(homeserver: hs)
        #expect(url != nil)
        let str = url!.absoluteString
        #expect(str.contains("/_matrix/client/v3/sync"))
        #expect(str.contains("timeout=30000"))
        #expect(!str.contains("since="))
    }

    @Test("Build sync URL with since token")
    func syncURLWithSince() {
        let url = MatrixKit.syncURL(homeserver: hs, sinceToken: "s123_456")
        #expect(url != nil)
        #expect(url!.absoluteString.contains("since=s123_456"))
    }

    @Test("Build sync URL strips trailing slash")
    func syncURLTrailingSlash() {
        let url = MatrixKit.syncURL(homeserver: "https://matrix.example.org/")
        #expect(url != nil)
        #expect(!url!.absoluteString.contains("org//"))
    }

    @Test("Build sendMessage URL")
    func sendMessageURL() {
        let url = MatrixKit.sendMessageURL(homeserver: hs, roomId: "!room:example.org", txnId: "txn1")
        #expect(url != nil)
        let str = url!.absoluteString
        #expect(str.contains("/send/m.room.message/txn1"))
    }

    @Test("Build whoAmI URL")
    func whoAmIURL() {
        let url = MatrixKit.whoAmIURL(homeserver: hs)
        #expect(url != nil)
        #expect(url!.absoluteString.contains("/account/whoami"))
    }

    @Test("Build joinedRooms URL")
    func joinedRoomsURL() {
        let url = MatrixKit.joinedRoomsURL(homeserver: hs)
        #expect(url != nil)
        #expect(url!.absoluteString.contains("/joined_rooms"))
    }
}

// MARK: - Parsing Tests

@Suite("MatrixKit.Parsing")
struct MatrixParsingTests {
    @Test("Parse sync response")
    func parseSyncResponse() {
        let json = """
        {
            "next_batch": "s123_456",
            "rooms": {
                "join": {
                    "!room:example.org": {
                        "timeline": {
                            "events": [
                                {
                                    "type": "m.room.message",
                                    "event_id": "$evt1",
                                    "sender": "@alice:example.org",
                                    "origin_server_ts": 1700000000000,
                                    "content": {
                                        "msgtype": "m.text",
                                        "body": "Hello!"
                                    }
                                }
                            ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let sync = MatrixKit.parseSyncResponse(data: json)
        #expect(sync != nil)
        #expect(sync?.nextBatch == "s123_456")
        let room = sync?.rooms?.join?["!room:example.org"]
        #expect(room != nil)
        #expect(room?.timeline?.events?.count == 1)
        #expect(room?.timeline?.events?[0].content?.body == "Hello!")
    }

    @Test("Parse empty sync response")
    func parseEmptySyncResponse() {
        let json = """
        {"next_batch": "s0"}
        """.data(using: .utf8)!

        let sync = MatrixKit.parseSyncResponse(data: json)
        #expect(sync != nil)
        #expect(sync?.nextBatch == "s0")
        #expect(sync?.rooms == nil)
    }

    @Test("Parse whoAmI response")
    func parseWhoAmI() {
        let json = """
        {"user_id": "@bot:example.org", "device_id": "ABCDEF"}
        """.data(using: .utf8)!

        let who = MatrixKit.parseWhoAmI(data: json)
        #expect(who != nil)
        #expect(who?.userId == "@bot:example.org")
        #expect(who?.deviceId == "ABCDEF")
    }

    @Test("Parse send response")
    func parseSendResponse() {
        let json = """
        {"event_id": "$new_evt"}
        """.data(using: .utf8)!

        let resp = MatrixKit.parseSendResponse(data: json)
        #expect(resp != nil)
        #expect(resp?.eventId == "$new_evt")
    }

    @Test("Parse invalid data returns nil")
    func parseInvalid() {
        let data = "invalid".data(using: .utf8)!
        #expect(MatrixKit.parseSyncResponse(data: data) == nil)
        #expect(MatrixKit.parseWhoAmI(data: data) == nil)
    }
}

// MARK: - Event Filtering Tests

@Suite("MatrixKit.EventFiltering")
struct MatrixEventFilteringTests {
    @Test("Extract messages filters own messages")
    func extractMessages() {
        let event1 = MatrixKit.RoomEvent(
            type: "m.room.message", eventId: "$1",
            sender: "@alice:example.org", originServerTs: 1700000000000,
            content: MatrixKit.EventContent(msgtype: "m.text", body: "Hi")
        )
        let event2 = MatrixKit.RoomEvent(
            type: "m.room.message", eventId: "$2",
            sender: "@bot:example.org", originServerTs: 1700000001000,
            content: MatrixKit.EventContent(msgtype: "m.text", body: "Reply")
        )
        let sync = MatrixKit.SyncResponse(
            nextBatch: "s1",
            rooms: MatrixKit.Rooms(join: [
                "!room:example.org": MatrixKit.JoinedRoom(
                    timeline: MatrixKit.Timeline(events: [event1, event2])
                ),
            ])
        )

        let messages = MatrixKit.extractMessages(from: sync, myUserId: "@bot:example.org")
        #expect(messages.count == 1)
        #expect(messages[0].event.sender == "@alice:example.org")
    }

    @Test("isTextMessage checks type and msgtype")
    func isTextMessage() {
        let textEvent = MatrixKit.RoomEvent(
            type: "m.room.message", eventId: "$1",
            sender: "@a:b", originServerTs: 0,
            content: MatrixKit.EventContent(msgtype: "m.text", body: "hi")
        )
        let noticeEvent = MatrixKit.RoomEvent(
            type: "m.room.message", eventId: "$2",
            sender: "@a:b", originServerTs: 0,
            content: MatrixKit.EventContent(msgtype: "m.notice", body: "notice")
        )
        let imageEvent = MatrixKit.RoomEvent(
            type: "m.room.message", eventId: "$3",
            sender: "@a:b", originServerTs: 0,
            content: MatrixKit.EventContent(msgtype: "m.image", body: "photo.jpg")
        )
        let memberEvent = MatrixKit.RoomEvent(
            type: "m.room.member", eventId: "$4",
            sender: "@a:b", originServerTs: 0
        )
        #expect(MatrixKit.isTextMessage(textEvent) == true)
        #expect(MatrixKit.isTextMessage(noticeEvent) == true)
        #expect(MatrixKit.isTextMessage(imageEvent) == false)
        #expect(MatrixKit.isTextMessage(memberEvent) == false)
    }

    @Test("Extract text from event")
    func extractText() {
        let event = MatrixKit.RoomEvent(
            type: "m.room.message", eventId: "$1",
            sender: "@a:b", originServerTs: 0,
            content: MatrixKit.EventContent(msgtype: "m.text", body: "Hello world")
        )
        #expect(MatrixKit.extractText(from: event) == "Hello world")
    }

    @Test("Extract text returns nil for empty body")
    func extractTextEmpty() {
        let event = MatrixKit.RoomEvent(
            type: "m.room.message", eventId: "$1",
            sender: "@a:b", originServerTs: 0,
            content: MatrixKit.EventContent(msgtype: "m.text", body: "")
        )
        #expect(MatrixKit.extractText(from: event) == nil)
    }

    @Test("Extract text returns nil for non-message events")
    func extractTextNonMessage() {
        let event = MatrixKit.RoomEvent(
            type: "m.room.member", eventId: "$1",
            sender: "@a:b", originServerTs: 0
        )
        #expect(MatrixKit.extractText(from: event) == nil)
    }
}

// MARK: - Request Body Tests

@Suite("MatrixKit.RequestBody")
struct MatrixRequestBodyTests {
    @Test("Build text message body")
    func textMessageBody() {
        let data = MatrixKit.textMessageBody(text: "Hello!")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["msgtype"] as? String == "m.text")
        #expect(json?["body"] as? String == "Hello!")
    }

    @Test("Build notice message body")
    func noticeMessageBody() {
        let data = MatrixKit.noticeMessageBody(text: "Notice")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["msgtype"] as? String == "m.notice")
    }

    @Test("Build HTML message body")
    func htmlMessageBody() {
        let data = MatrixKit.htmlMessageBody(text: "bold", html: "<b>bold</b>")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["format"] as? String == "org.matrix.custom.html")
        #expect(json?["formatted_body"] as? String == "<b>bold</b>")
    }
}

// MARK: - Formatting Tests

@Suite("MatrixKit.Formatting")
struct MatrixFormattingTests {
    @Test("Truncate long text")
    func truncate() {
        let long = String(repeating: "A", count: 70000)
        let truncated = MatrixKit.truncateForMatrix(long)
        #expect(truncated.count <= 65536)
        #expect(truncated.hasSuffix("… (truncated)"))
    }

    @Test("Short text not truncated")
    func noTruncate() {
        let short = "Hello"
        #expect(MatrixKit.truncateForMatrix(short) == short)
    }

    @Test("Generate transaction ID is UUID format")
    func generateTxnId() {
        let txnId = MatrixKit.generateTxnId()
        #expect(!txnId.isEmpty)
        #expect(txnId.count == 36) // UUID string length
    }
}

// MARK: - Validation Tests

@Suite("MatrixKit.Validation")
struct MatrixValidationTests {
    @Test("Valid access token")
    func validToken() {
        #expect(MatrixKit.isValidAccessToken("syt_abcdefghij_1234567890") == true)
    }

    @Test("Invalid access token - too short")
    func invalidTokenShort() {
        #expect(MatrixKit.isValidAccessToken("short") == false)
    }

    @Test("Invalid access token - empty")
    func invalidTokenEmpty() {
        #expect(MatrixKit.isValidAccessToken("") == false)
    }

    @Test("Valid homeserver URL")
    func validHomeserver() {
        #expect(MatrixKit.isValidHomeserverURL("https://matrix.example.org") == true)
        #expect(MatrixKit.isValidHomeserverURL("http://localhost:8008") == true)
    }

    @Test("Invalid homeserver URL - no scheme")
    func invalidHomeserverNoScheme() {
        #expect(MatrixKit.isValidHomeserverURL("matrix.example.org") == false)
    }

    @Test("Invalid homeserver URL - ftp scheme")
    func invalidHomeserverFTP() {
        #expect(MatrixKit.isValidHomeserverURL("ftp://matrix.example.org") == false)
    }
}

// MARK: - Model Tests

@Suite("MatrixKit.Models")
struct MatrixModelTests {
    @Test("RoomEvent dateValue conversion")
    func roomEventDate() {
        let event = MatrixKit.RoomEvent(
            type: "m.room.message", eventId: "$1",
            sender: "@a:b", originServerTs: 1700000000000
        )
        let expected = Date(timeIntervalSince1970: 1700000000)
        #expect(event.dateValue == expected)
    }
}
