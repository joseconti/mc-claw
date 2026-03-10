import Foundation
import Testing
@testable import McClawKit

// MARK: - URL Building Tests

@Suite("MattermostKit.URLBuilding")
struct MattermostURLBuildingTests {
    let server = "https://mattermost.example.com"

    @Test("Build WebSocket URL from HTTPS")
    func wsURLFromHTTPS() {
        let url = MattermostKit.webSocketURL(serverURL: server)
        #expect(url != nil)
        #expect(url?.absoluteString == "wss://mattermost.example.com/api/v4/websocket")
    }

    @Test("Build WebSocket URL from HTTP")
    func wsURLFromHTTP() {
        let url = MattermostKit.webSocketURL(serverURL: "http://localhost:8065")
        #expect(url != nil)
        #expect(url?.absoluteString == "ws://localhost:8065/api/v4/websocket")
    }

    @Test("Build WebSocket URL strips trailing slash")
    func wsURLStripsSlash() {
        let url = MattermostKit.webSocketURL(serverURL: "https://mm.example.com/")
        #expect(url != nil)
        #expect(url?.absoluteString == "wss://mm.example.com/api/v4/websocket")
    }

    @Test("Build WebSocket URL returns nil for no scheme")
    func wsURLNoScheme() {
        let url = MattermostKit.webSocketURL(serverURL: "mattermost.example.com")
        #expect(url == nil)
    }

    @Test("Build posts URL")
    func postsURL() {
        let url = MattermostKit.postsURL(serverURL: server)
        #expect(url != nil)
        #expect(url!.absoluteString.contains("/api/v4/posts"))
    }

    @Test("Build users URL")
    func usersURL() {
        let url = MattermostKit.usersURL(serverURL: server)
        #expect(url != nil)
        #expect(url!.absoluteString.contains("/api/v4/users/me"))
    }
}

// MARK: - Parsing Tests

@Suite("MattermostKit.Parsing")
struct MattermostParsingTests {
    @Test("Parse WebSocket event")
    func parseWSEvent() {
        let json = """
        {
            "event": "posted",
            "data": {
                "channel_id": "ch1",
                "sender_name": "alice",
                "post": "{\\"id\\":\\"post1\\",\\"channel_id\\":\\"ch1\\",\\"user_id\\":\\"u1\\",\\"message\\":\\"Hello\\",\\"create_at\\":1700000000000}"
            },
            "broadcast": {"channel_id": "ch1"},
            "seq": 5
        }
        """.data(using: .utf8)!

        let event = MattermostKit.parseWebSocketEvent(data: json)
        #expect(event != nil)
        #expect(event?.event == "posted")
        #expect(event?.data?.channelId == "ch1")
        #expect(event?.data?.senderName == "alice")
        #expect(event?.seq == 5)
    }

    @Test("Parse Post from JSON string")
    func parsePost() {
        let postJSON = """
        {"id":"post1","channel_id":"ch1","user_id":"u1","root_id":"root1","message":"Hello world","create_at":1700000000000,"type":""}
        """
        let post = MattermostKit.parsePost(from: postJSON)
        #expect(post != nil)
        #expect(post?.id == "post1")
        #expect(post?.channelId == "ch1")
        #expect(post?.message == "Hello world")
        #expect(post?.rootId == "root1")
        #expect(post?.isReply == true)
    }

    @Test("Parse Post without rootId is not a reply")
    func parsePostNoRoot() {
        let postJSON = """
        {"id":"post1","channel_id":"ch1","user_id":"u1","message":"Hi","create_at":1700000000000}
        """
        let post = MattermostKit.parsePost(from: postJSON)
        #expect(post != nil)
        #expect(post?.isReply == false)
    }

    @Test("Parse User from API response")
    func parseUser() {
        let json = """
        {"id":"u1","username":"alice","first_name":"Alice","last_name":"Smith","nickname":"Ali","email":"alice@example.com"}
        """.data(using: .utf8)!

        let user = MattermostKit.parseUser(data: json)
        #expect(user != nil)
        #expect(user?.username == "alice")
        #expect(user?.displayName == "Ali") // nickname preferred
    }

    @Test("Parse User displayName fallback")
    func parseUserDisplayFallback() {
        let user = MattermostKit.User(id: "u1", username: "bob")
        #expect(user.displayName == "bob")

        let userWithName = MattermostKit.User(id: "u2", username: "bob", firstName: "Bob", lastName: "Jones")
        #expect(userWithName.displayName == "Bob Jones")
    }

    @Test("Parse invalid data returns nil")
    func parseInvalid() {
        let data = "bad".data(using: .utf8)!
        #expect(MattermostKit.parseWebSocketEvent(data: data) == nil)
        #expect(MattermostKit.parseUser(data: data) == nil)
        #expect(MattermostKit.parsePost(from: "bad") == nil)
    }
}

// MARK: - Event Filtering Tests

@Suite("MattermostKit.EventFiltering")
struct MattermostEventFilteringTests {
    @Test("Process posted event from other user")
    func processPostedEvent() {
        let event = MattermostKit.WebSocketEvent(
            event: "posted",
            data: MattermostKit.EventData(
                post: """
                {"id":"p1","channel_id":"ch1","user_id":"other_user","message":"Hi","create_at":1700000000000}
                """,
                userId: "other_user"
            )
        )
        #expect(MattermostKit.shouldProcess(event: event, myUserId: "my_user") == true)
    }

    @Test("Skip own posted events")
    func skipOwnEvent() {
        let event = MattermostKit.WebSocketEvent(
            event: "posted",
            data: MattermostKit.EventData(
                post: """
                {"id":"p1","channel_id":"ch1","user_id":"my_user","message":"Hi","create_at":1700000000000}
                """,
                userId: "my_user"
            )
        )
        #expect(MattermostKit.shouldProcess(event: event, myUserId: "my_user") == false)
    }

    @Test("Skip non-posted events")
    func skipNonPosted() {
        let event = MattermostKit.WebSocketEvent(event: "typing")
        #expect(MattermostKit.shouldProcess(event: event, myUserId: "my_user") == false)
    }

    @Test("Extract post from event")
    func extractPost() {
        let event = MattermostKit.WebSocketEvent(
            event: "posted",
            data: MattermostKit.EventData(
                post: """
                {"id":"p1","channel_id":"ch1","user_id":"u1","message":"Hello","create_at":1700000000000}
                """
            )
        )
        let post = MattermostKit.extractPost(from: event)
        #expect(post != nil)
        #expect(post?.message == "Hello")
    }
}

// MARK: - Request Body Tests

@Suite("MattermostKit.RequestBody")
struct MattermostRequestBodyTests {
    @Test("Build auth challenge body")
    func authChallenge() {
        let data = MattermostKit.authChallengeBody(token: "my-token")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["action"] as? String == "authentication_challenge")
        let authData = json?["data"] as? [String: Any]
        #expect(authData?["token"] as? String == "my-token")
    }

    @Test("Build create post body")
    func createPost() {
        let data = MattermostKit.createPostBody(channelId: "ch1", message: "Hello")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["channel_id"] as? String == "ch1")
        #expect(json?["message"] as? String == "Hello")
    }

    @Test("Build create post body with rootId")
    func createPostWithRoot() {
        let data = MattermostKit.createPostBody(channelId: "ch1", message: "Reply", rootId: "root1")
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["root_id"] as? String == "root1")
    }
}

// MARK: - Formatting Tests

@Suite("MattermostKit.Formatting")
struct MattermostFormattingTests {
    @Test("Truncate long text")
    func truncate() {
        let long = String(repeating: "A", count: 20000)
        let truncated = MattermostKit.truncateForMattermost(long)
        #expect(truncated.count <= 16383)
        #expect(truncated.hasSuffix("… (truncated)"))
    }

    @Test("Short text not truncated")
    func noTruncate() {
        #expect(MattermostKit.truncateForMattermost("Hello") == "Hello")
    }
}

// MARK: - Validation Tests

@Suite("MattermostKit.Validation")
struct MattermostValidationTests {
    @Test("Valid token")
    func validToken() {
        #expect(MattermostKit.isValidToken("abcdefghijklmnopqrstuvwxyz") == true)
    }

    @Test("Invalid token - too short")
    func invalidTokenShort() {
        #expect(MattermostKit.isValidToken("short") == false)
    }

    @Test("Valid server URL")
    func validServerURL() {
        #expect(MattermostKit.isValidServerURL("https://mattermost.example.com") == true)
        #expect(MattermostKit.isValidServerURL("http://localhost:8065") == true)
    }

    @Test("Invalid server URL")
    func invalidServerURL() {
        #expect(MattermostKit.isValidServerURL("ftp://mm.example.com") == false)
        #expect(MattermostKit.isValidServerURL("not a url") == false)
    }
}

// MARK: - Model Tests

@Suite("MattermostKit.Models")
struct MattermostModelTests {
    @Test("Post dateValue conversion")
    func postDateValue() {
        let post = MattermostKit.Post(id: "p1", channelId: "ch1", userId: "u1", message: "Hi", createAt: 1700000000000)
        let expected = Date(timeIntervalSince1970: 1700000000)
        #expect(post.dateValue == expected)
    }

    @Test("Channel isDirectMessage")
    func channelIsDM() {
        let dm = MattermostKit.Channel(id: "1", type: "D", displayName: "DM", name: "dm")
        let group = MattermostKit.Channel(id: "2", type: "G", displayName: "Group", name: "group")
        let open = MattermostKit.Channel(id: "3", type: "O", displayName: "Open", name: "open")
        #expect(dm.isDirectMessage == true)
        #expect(group.isGroupMessage == true)
        #expect(open.isDirectMessage == false)
    }

    @Test("Event type constants")
    func eventConstants() {
        #expect(MattermostKit.eventHello == "hello")
        #expect(MattermostKit.eventPosted == "posted")
        #expect(MattermostKit.eventPostEdited == "post_edited")
        #expect(MattermostKit.eventTyping == "typing")
    }
}
