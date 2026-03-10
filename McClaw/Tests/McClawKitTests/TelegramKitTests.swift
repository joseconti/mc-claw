import Foundation
import Testing
@testable import McClawKit

// MARK: - URL Building Tests

@Suite("TelegramKit.URLBuilding")
struct TelegramURLBuildingTests {
    let token = "123456789:ABCdefGHIjklMNOpqrsTUVwxyz"

    @Test("Build getMe URL")
    func getMeURL() {
        let url = TelegramKit.getMeURL(token: token)
        #expect(url != nil)
        #expect(url?.absoluteString == "https://api.telegram.org/bot\(token)/getMe")
    }

    @Test("Build sendMessage URL")
    func sendMessageURL() {
        let url = TelegramKit.sendMessageURL(token: token)
        #expect(url != nil)
        #expect(url?.absoluteString == "https://api.telegram.org/bot\(token)/sendMessage")
    }

    @Test("Build getUpdates URL without offset")
    func getUpdatesNoOffset() {
        let url = TelegramKit.getUpdatesURL(token: token, offset: nil, limit: 50, timeout: 15)
        #expect(url != nil)
        let urlStr = url!.absoluteString
        #expect(urlStr.contains("getUpdates"))
        #expect(urlStr.contains("limit=50"))
        #expect(urlStr.contains("timeout=15"))
        #expect(!urlStr.contains("offset="))
    }

    @Test("Build getUpdates URL with offset")
    func getUpdatesWithOffset() {
        let url = TelegramKit.getUpdatesURL(token: token, offset: 12345)
        #expect(url != nil)
        #expect(url!.absoluteString.contains("offset=12345"))
    }

    @Test("Build API URL with params")
    func apiURLWithParams() {
        let url = TelegramKit.apiURL(token: token, method: "getChat", params: ["chat_id": "123"])
        #expect(url != nil)
        #expect(url!.absoluteString.contains("getChat"))
        #expect(url!.absoluteString.contains("chat_id=123"))
    }
}

// MARK: - Parsing Tests

@Suite("TelegramKit.Parsing")
struct TelegramKitParsingTests {
    @Test("Parse getMe response")
    func parseBotInfo() {
        let json = """
        {
            "ok": true,
            "result": {
                "id": 123456789,
                "is_bot": true,
                "first_name": "TestBot",
                "username": "test_bot"
            }
        }
        """.data(using: .utf8)!

        let info = TelegramKit.parseBotInfo(data: json)
        #expect(info != nil)
        #expect(info?.id == 123456789)
        #expect(info?.isBot == true)
        #expect(info?.firstName == "TestBot")
        #expect(info?.username == "test_bot")
    }

    @Test("Parse getUpdates response with messages")
    func parseUpdates() {
        let json = """
        {
            "ok": true,
            "result": [
                {
                    "update_id": 100,
                    "message": {
                        "message_id": 1,
                        "from": {
                            "id": 555,
                            "is_bot": false,
                            "first_name": "Alice"
                        },
                        "chat": {
                            "id": 555,
                            "type": "private"
                        },
                        "date": 1700000000,
                        "text": "Hello bot!"
                    }
                },
                {
                    "update_id": 101,
                    "message": {
                        "message_id": 2,
                        "from": {
                            "id": 666,
                            "is_bot": false,
                            "first_name": "Bob",
                            "last_name": "Smith"
                        },
                        "chat": {
                            "id": 666,
                            "type": "private"
                        },
                        "date": 1700000001,
                        "text": "What is 2+2?"
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let updates = TelegramKit.parseUpdates(data: json)
        #expect(updates != nil)
        #expect(updates?.count == 2)
        #expect(updates?[0].updateId == 100)
        #expect(updates?[0].message?.text == "Hello bot!")
        #expect(updates?[0].message?.from?.firstName == "Alice")
        #expect(updates?[1].updateId == 101)
        #expect(updates?[1].message?.from?.displayName == "Bob Smith")
    }

    @Test("Parse empty updates")
    func parseEmptyUpdates() {
        let json = """
        {"ok": true, "result": []}
        """.data(using: .utf8)!

        let updates = TelegramKit.parseUpdates(data: json)
        #expect(updates != nil)
        #expect(updates?.isEmpty == true)
    }

    @Test("Parse failed response returns nil")
    func parseFailedResponse() {
        let json = """
        {"ok": false, "error_code": 401, "description": "Unauthorized"}
        """.data(using: .utf8)!

        let updates = TelegramKit.parseUpdates(data: json)
        #expect(updates == nil)
    }

    @Test("Parse sendMessage response")
    func parseSentMessage() {
        let json = """
        {
            "ok": true,
            "result": {
                "message_id": 42,
                "from": {"id": 123, "is_bot": true, "first_name": "Bot"},
                "chat": {"id": 555, "type": "private"},
                "date": 1700000010,
                "text": "Hello!"
            }
        }
        """.data(using: .utf8)!

        let msg = TelegramKit.parseSentMessage(data: json)
        #expect(msg != nil)
        #expect(msg?.messageId == 42)
        #expect(msg?.text == "Hello!")
    }
}

// MARK: - Offset Tests

@Suite("TelegramKit.Offset")
struct TelegramOffsetTests {
    @Test("Calculate next offset from updates")
    func nextOffset() {
        let updates = [
            TelegramKit.Update(updateId: 100),
            TelegramKit.Update(updateId: 102),
            TelegramKit.Update(updateId: 101),
        ]
        let offset = TelegramKit.nextOffset(from: updates)
        #expect(offset == 103) // max(100, 102, 101) + 1
    }

    @Test("Next offset from single update")
    func nextOffsetSingle() {
        let updates = [TelegramKit.Update(updateId: 50)]
        #expect(TelegramKit.nextOffset(from: updates) == 51)
    }

    @Test("Next offset from empty returns nil")
    func nextOffsetEmpty() {
        let offset = TelegramKit.nextOffset(from: [])
        #expect(offset == nil)
    }
}

// MARK: - Filtering Tests

@Suite("TelegramKit.Filtering")
struct TelegramFilteringTests {
    private func makeUpdate(id: Int, text: String?, isBot: Bool = false) -> TelegramKit.Update {
        let from = TelegramKit.User(id: 1, isBot: isBot, firstName: "Test")
        let chat = TelegramKit.Chat(id: 1, type: "private")
        let msg = TelegramKit.Message(
            messageId: id,
            from: from,
            chat: chat,
            date: 1700000000,
            text: text
        )
        return TelegramKit.Update(updateId: id, message: msg)
    }

    @Test("Filter out bot messages")
    func filterBotMessages() {
        let updates = [
            makeUpdate(id: 1, text: "Hello", isBot: false),
            makeUpdate(id: 2, text: "Bot reply", isBot: true),
            makeUpdate(id: 3, text: "World", isBot: false),
        ]
        let filtered = TelegramKit.filterTextMessages(updates)
        #expect(filtered.count == 2)
        #expect(filtered[0].updateId == 1)
        #expect(filtered[1].updateId == 3)
    }

    @Test("Filter out non-text messages")
    func filterNonText() {
        let updates = [
            makeUpdate(id: 1, text: "Hello"),
            makeUpdate(id: 2, text: nil),
        ]
        let filtered = TelegramKit.filterTextMessages(updates)
        #expect(filtered.count == 1)
    }
}

// MARK: - Formatting Tests

@Suite("TelegramKit.Formatting")
struct TelegramFormattingTests {
    @Test("Truncate long text")
    func truncate() {
        let long = String(repeating: "A", count: 5000)
        let truncated = TelegramKit.truncateForTelegram(long)
        #expect(truncated.count <= 4096)
        #expect(truncated.hasSuffix("… (truncated)"))
    }

    @Test("Short text is not truncated")
    func noTruncate() {
        let short = "Hello, world!"
        let result = TelegramKit.truncateForTelegram(short)
        #expect(result == short)
    }

    @Test("Format user mention with username")
    func mentionWithUsername() {
        let user = TelegramKit.User(id: 1, isBot: false, firstName: "Alice", username: "alice123")
        #expect(TelegramKit.formatUserMention(user) == "@alice123")
    }

    @Test("Format user mention without username")
    func mentionWithoutUsername() {
        let user = TelegramKit.User(id: 1, isBot: false, firstName: "Alice", lastName: "Smith")
        #expect(TelegramKit.formatUserMention(user) == "Alice Smith")
    }
}

// MARK: - Token Validation Tests

@Suite("TelegramKit.TokenValidation")
struct TelegramTokenValidationTests {
    @Test("Valid bot token")
    func validToken() {
        #expect(TelegramKit.isValidBotToken("123456789:ABCdefGHIjklMNOpqrsTUVwxyz") == true)
    }

    @Test("Invalid - no colon")
    func invalidNoColon() {
        #expect(TelegramKit.isValidBotToken("123456789ABCdef") == false)
    }

    @Test("Invalid - non-numeric prefix")
    func invalidNonNumeric() {
        #expect(TelegramKit.isValidBotToken("abc:ABCdefGHIjklMNOpqrsTUVwxyz") == false)
    }

    @Test("Invalid - short suffix")
    func invalidShortSuffix() {
        #expect(TelegramKit.isValidBotToken("123:short") == false)
    }

    @Test("Invalid - empty string")
    func invalidEmpty() {
        #expect(TelegramKit.isValidBotToken("") == false)
    }
}

// MARK: - Request Body Tests

@Suite("TelegramKit.RequestBody")
struct TelegramRequestBodyTests {
    @Test("Build sendMessage body")
    func sendMessageBody() {
        let body = TelegramKit.sendMessageBody(chatId: 123, text: "Hello!")
        #expect(body != nil)
        let json = try? JSONSerialization.jsonObject(with: body!) as? [String: Any]
        #expect(json?["chat_id"] as? Int64 == 123)
        #expect(json?["text"] as? String == "Hello!")
        #expect(json?["parse_mode"] as? String == "Markdown")
    }

    @Test("Build sendMessage body with reply")
    func sendMessageBodyWithReply() {
        let body = TelegramKit.sendMessageBody(chatId: 123, text: "Reply", replyToMessageId: 42)
        #expect(body != nil)
        let json = try? JSONSerialization.jsonObject(with: body!) as? [String: Any]
        #expect(json?["reply_to_message_id"] as? Int == 42)
    }
}

// MARK: - Model Tests

@Suite("TelegramKit.Models")
struct TelegramModelTests {
    @Test("User displayName with last name")
    func userDisplayNameFull() {
        let user = TelegramKit.User(id: 1, isBot: false, firstName: "Alice", lastName: "Smith")
        #expect(user.displayName == "Alice Smith")
    }

    @Test("User displayName without last name")
    func userDisplayNameFirst() {
        let user = TelegramKit.User(id: 1, isBot: false, firstName: "Alice")
        #expect(user.displayName == "Alice")
    }

    @Test("Chat displayName with title")
    func chatDisplayNameTitle() {
        let chat = TelegramKit.Chat(id: 1, type: "group", title: "My Group")
        #expect(chat.displayName == "My Group")
    }

    @Test("Chat displayName with username")
    func chatDisplayNameUsername() {
        let chat = TelegramKit.Chat(id: 1, type: "private", username: "alice")
        #expect(chat.displayName == "@alice")
    }

    @Test("Chat displayName fallback to ID")
    func chatDisplayNameFallback() {
        let chat = TelegramKit.Chat(id: 999, type: "private")
        #expect(chat.displayName == "Chat 999")
    }

    @Test("Update effectiveMessage prefers message over editedMessage")
    func effectiveMessagePreference() {
        let chat = TelegramKit.Chat(id: 1, type: "private")
        let msg = TelegramKit.Message(messageId: 1, chat: chat, date: 0, text: "original")
        let edited = TelegramKit.Message(messageId: 1, chat: chat, date: 1, text: "edited")
        let update = TelegramKit.Update(updateId: 1, message: msg, editedMessage: edited)
        #expect(update.effectiveMessage?.text == "original")
    }

    @Test("Update effectiveMessage falls back to editedMessage")
    func effectiveMessageFallback() {
        let chat = TelegramKit.Chat(id: 1, type: "private")
        let edited = TelegramKit.Message(messageId: 1, chat: chat, date: 1, text: "edited")
        let update = TelegramKit.Update(updateId: 1, message: nil, editedMessage: edited)
        #expect(update.effectiveMessage?.text == "edited")
    }

    @Test("Message dateValue conversion")
    func messageDateValue() {
        let chat = TelegramKit.Chat(id: 1, type: "private")
        let msg = TelegramKit.Message(messageId: 1, chat: chat, date: 1700000000)
        #expect(msg.dateValue == Date(timeIntervalSince1970: 1700000000))
    }
}
