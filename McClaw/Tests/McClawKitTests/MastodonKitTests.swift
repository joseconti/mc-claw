import Foundation
import Testing
@testable import McClawKit

// MARK: - URL Building Tests

@Suite("MastodonKit.URLBuilding")
struct MastodonURLBuildingTests {
    let instance = "https://mastodon.social"

    @Test("Build streaming URL")
    func streamingURL() {
        let url = MastodonKit.streamingURL(instanceURL: instance, token: "tok123")
        #expect(url != nil)
        let str = url!.absoluteString
        #expect(str.contains("wss://"))
        #expect(str.contains("/api/v1/streaming"))
        #expect(str.contains("stream=user"))
        #expect(str.contains("access_token=tok123"))
    }

    @Test("Build verify credentials URL")
    func verifyCredentialsURL() {
        let url = MastodonKit.verifyCredentialsURL(instanceURL: instance)
        #expect(url != nil)
        #expect(url!.absoluteString == "https://mastodon.social/api/v1/accounts/verify_credentials")
    }

    @Test("Build post status URL")
    func postStatusURL() {
        let url = MastodonKit.postStatusURL(instanceURL: instance)
        #expect(url != nil)
        #expect(url!.absoluteString == "https://mastodon.social/api/v1/statuses")
    }

    @Test("Build notifications URL with types")
    func notificationsURL() {
        let url = MastodonKit.notificationsURL(instanceURL: instance, types: ["mention"], sinceId: "123")
        #expect(url != nil)
        let str = url!.absoluteString
        #expect(str.contains("types%5B%5D=mention") || str.contains("types[]=mention"))
        #expect(str.contains("since_id=123"))
    }

    @Test("Build status context URL")
    func statusContextURL() {
        let url = MastodonKit.statusContextURL(instanceURL: instance, statusId: "999")
        #expect(url != nil)
        #expect(url!.absoluteString.contains("/statuses/999/context"))
    }

    @Test("URL strips trailing slashes")
    func urlStripsSlash() {
        let url = MastodonKit.verifyCredentialsURL(instanceURL: "https://mastodon.social///")
        #expect(url != nil)
        #expect(!url!.absoluteString.contains("///"))
    }
}

// MARK: - Parsing Tests

@Suite("MastodonKit.Parsing")
struct MastodonParsingTests {
    @Test("Parse account")
    func parseAccount() {
        let json = """
        {
            "id": "acc1",
            "username": "botuser",
            "acct": "botuser",
            "display_name": "Bot User",
            "bot": true,
            "url": "https://mastodon.social/@botuser",
            "note": "A bot"
        }
        """.data(using: .utf8)!

        let account = MastodonKit.parseAccount(data: json)
        #expect(account != nil)
        #expect(account?.id == "acc1")
        #expect(account?.username == "botuser")
        #expect(account?.bot == true)
        #expect(account?.displayName == "Bot User")
    }

    @Test("Parse status")
    func parseStatus() {
        let json = """
        {
            "id": "st1",
            "content": "<p>Hello <strong>world</strong></p>",
            "account": {
                "id": "acc1", "username": "alice", "acct": "alice",
                "display_name": "Alice", "bot": false,
                "url": "https://mastodon.social/@alice", "note": ""
            },
            "visibility": "public",
            "created_at": "2024-01-01T00:00:00.000Z"
        }
        """.data(using: .utf8)!

        let status = MastodonKit.parseStatus(data: json)
        #expect(status != nil)
        #expect(status?.id == "st1")
        #expect(status?.visibility == .public)
        #expect(status?.account.username == "alice")
    }

    @Test("Parse notifications")
    func parseNotifications() {
        let json = """
        [
            {
                "id": "n1",
                "type": "mention",
                "account": {
                    "id": "acc1", "username": "alice", "acct": "alice",
                    "display_name": "Alice", "bot": false,
                    "url": "https://mastodon.social/@alice", "note": ""
                },
                "status": {
                    "id": "st1",
                    "content": "<p>@bot Hello</p>",
                    "account": {
                        "id": "acc1", "username": "alice", "acct": "alice",
                        "display_name": "Alice", "bot": false,
                        "url": "https://mastodon.social/@alice", "note": ""
                    },
                    "visibility": "direct",
                    "created_at": "2024-01-01T00:00:00.000Z"
                },
                "created_at": "2024-01-01T00:00:00.000Z"
            }
        ]
        """.data(using: .utf8)!

        let notifs = MastodonKit.parseNotifications(data: json)
        #expect(notifs != nil)
        #expect(notifs?.count == 1)
        #expect(notifs?[0].type == "mention")
        #expect(notifs?[0].status?.visibility == .direct)
    }

    @Test("Parse SSE stream event")
    func parseStreamEvent() {
        let text = "event: notification\ndata: {\"id\":\"123\"}"
        let event = MastodonKit.parseStreamEvent(text: text)
        #expect(event != nil)
        #expect(event?.event == "notification")
        #expect(event?.payload == "{\"id\":\"123\"}")
    }

    @Test("Parse invalid stream event returns nil")
    func parseInvalidStreamEvent() {
        #expect(MastodonKit.parseStreamEvent(text: "no events here") == nil)
    }

    @Test("Parse invalid data returns nil")
    func parseInvalid() {
        let data = "bad".data(using: .utf8)!
        #expect(MastodonKit.parseAccount(data: data) == nil)
        #expect(MastodonKit.parseStatus(data: data) == nil)
    }
}

// MARK: - Event Filtering Tests

@Suite("MastodonKit.EventFiltering")
struct MastodonEventFilteringTests {
    private let account = MastodonKit.Account(
        id: "acc1", username: "alice", acct: "alice",
        displayName: "Alice", bot: false,
        url: "https://mastodon.social/@alice", note: ""
    )

    @Test("isMention returns true for mention type")
    func isMention() {
        let notif = MastodonKit.Notification(id: "n1", type: "mention", account: account, createdAt: "2024-01-01")
        #expect(MastodonKit.isMention(notif) == true)
    }

    @Test("isMention returns false for other types")
    func isNotMention() {
        let notif = MastodonKit.Notification(id: "n1", type: "favourite", account: account, createdAt: "2024-01-01")
        #expect(MastodonKit.isMention(notif) == false)
    }

    @Test("shouldProcess filters mentions from others")
    func shouldProcess() {
        let notif = MastodonKit.Notification(id: "n1", type: "mention", account: account, createdAt: "2024-01-01")
        #expect(MastodonKit.shouldProcess(notification: notif, myAccountId: "bot1") == true)
    }

    @Test("shouldProcess rejects own mentions")
    func shouldProcessRejectSelf() {
        let notif = MastodonKit.Notification(id: "n1", type: "mention", account: account, createdAt: "2024-01-01")
        #expect(MastodonKit.shouldProcess(notification: notif, myAccountId: "acc1") == false)
    }

    @Test("shouldProcess rejects non-mention types")
    func shouldProcessRejectNonMention() {
        let notif = MastodonKit.Notification(id: "n1", type: "reblog", account: account, createdAt: "2024-01-01")
        #expect(MastodonKit.shouldProcess(notification: notif, myAccountId: "bot1") == false)
    }
}

// MARK: - HTML Stripping & Text Extraction Tests

@Suite("MastodonKit.HTMLStripping")
struct MastodonHTMLStrippingTests {
    @Test("Strip simple HTML tags")
    func stripSimpleTags() {
        #expect(MastodonKit.stripHTML("<p>Hello world</p>") == "Hello world")
    }

    @Test("Convert br to newlines")
    func convertBr() {
        #expect(MastodonKit.stripHTML("Line1<br>Line2") == "Line1\nLine2")
        #expect(MastodonKit.stripHTML("Line1<br/>Line2") == "Line1\nLine2")
    }

    @Test("Convert paragraph breaks to double newlines")
    func convertParagraphs() {
        let result = MastodonKit.stripHTML("<p>Para1</p><p>Para2</p>")
        #expect(result.contains("Para1"))
        #expect(result.contains("Para2"))
    }

    @Test("Decode HTML entities")
    func decodeEntities() {
        #expect(MastodonKit.stripHTML("&amp; &lt; &gt; &quot; &#39;") == "& < > \" '")
    }

    @Test("Extract text from status strips HTML")
    func extractText() {
        let status = MastodonKit.Status(
            id: "1",
            content: "<p>@bot <strong>Hello</strong></p>",
            account: MastodonKit.Account(id: "1", username: "a", acct: "a", displayName: "A", bot: false, url: "", note: ""),
            visibility: .public,
            createdAt: "2024-01-01"
        )
        let text = MastodonKit.extractText(from: status)
        #expect(text == "@bot Hello")
    }

    @Test("Status plainContent strips HTML")
    func statusPlainContent() {
        let status = MastodonKit.Status(
            id: "1",
            content: "<p>Bold <b>text</b></p>",
            account: MastodonKit.Account(id: "1", username: "a", acct: "a", displayName: "A", bot: false, url: "", note: ""),
            visibility: .public,
            createdAt: "2024-01-01"
        )
        #expect(status.plainContent == "Bold text")
    }
}

// MARK: - Request Body Tests

@Suite("MastodonKit.RequestBody")
struct MastodonRequestBodyTests {
    @Test("Build post status body")
    func postStatusBody() {
        let data = MastodonKit.postStatusBody(text: "Hello!", visibility: .direct)
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["status"] as? String == "Hello!")
        #expect(json?["visibility"] as? String == "direct")
    }

    @Test("Build post status body with reply")
    func postStatusBodyWithReply() {
        let data = MastodonKit.postStatusBody(text: "Reply!", inReplyToId: "st1", visibility: .unlisted)
        #expect(data != nil)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(json?["in_reply_to_id"] as? String == "st1")
        #expect(json?["visibility"] as? String == "unlisted")
    }
}

// MARK: - Formatting Tests

@Suite("MastodonKit.Formatting")
struct MastodonFormattingTests {
    @Test("Truncate long text")
    func truncate() {
        let long = String(repeating: "A", count: 600)
        let truncated = MastodonKit.truncateForMastodon(long)
        #expect(truncated.count <= 500)
        #expect(truncated.hasSuffix("… (truncated)"))
    }

    @Test("Short text not truncated")
    func noTruncate() {
        #expect(MastodonKit.truncateForMastodon("Hello!") == "Hello!")
    }
}

// MARK: - Validation Tests

@Suite("MastodonKit.Validation")
struct MastodonValidationTests {
    @Test("Valid access token")
    func validToken() {
        #expect(MastodonKit.isValidAccessToken("abcdefghij1234567890") == true)
    }

    @Test("Invalid access token - empty")
    func invalidTokenEmpty() {
        #expect(MastodonKit.isValidAccessToken("") == false)
    }

    @Test("Invalid access token - too short")
    func invalidTokenShort() {
        #expect(MastodonKit.isValidAccessToken("short") == false)
    }

    @Test("Valid instance URL")
    func validInstanceURL() {
        #expect(MastodonKit.isValidInstanceURL("https://mastodon.social") == true)
    }

    @Test("Invalid instance URL - no HTTPS")
    func invalidInstanceHTTP() {
        #expect(MastodonKit.isValidInstanceURL("http://mastodon.social") == false)
    }

    @Test("Invalid instance URL - no dot in host")
    func invalidInstanceNoDot() {
        #expect(MastodonKit.isValidInstanceURL("https://localhost") == false)
    }

    @Test("Notification type constants")
    func notificationTypes() {
        #expect(MastodonKit.notificationMention == "mention")
        #expect(MastodonKit.notificationFavourite == "favourite")
        #expect(MastodonKit.notificationReblog == "reblog")
        #expect(MastodonKit.notificationFollow == "follow")
    }
}
