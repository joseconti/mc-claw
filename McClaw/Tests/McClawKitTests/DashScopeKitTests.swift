import Foundation
import Testing
@testable import McClawKit

@Suite("DashScopeKit")
struct DashScopeKitTests {

    // MARK: - Region URLs

    @Test("International region URL is correct")
    func internationalURL() {
        let url = DashScopeKit.chatCompletionsURL(for: .international)
        #expect(url?.absoluteString == "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions")
    }

    @Test("US Virginia region URL is correct")
    func usVirginiaURL() {
        let url = DashScopeKit.chatCompletionsURL(for: .usVirginia)
        #expect(url?.absoluteString == "https://dashscope-us.aliyuncs.com/compatible-mode/v1/chat/completions")
    }

    @Test("Models URL is correct")
    func modelsURL() {
        let url = DashScopeKit.modelsURL(for: .international)
        #expect(url?.absoluteString == "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/models")
    }

    @Test("Region display names are non-empty")
    func regionDisplayNames() {
        for region in DashScopeKit.Region.allCases {
            #expect(!region.displayName.isEmpty)
        }
    }

    // MARK: - API Key Validation

    @Test("Valid API key passes validation")
    func validAPIKey() {
        #expect(DashScopeKit.validateAPIKey("sk-abcdefghijklmnopqrstuvwxyz123456") == true)
    }

    @Test("Short key fails validation")
    func shortAPIKey() {
        #expect(DashScopeKit.validateAPIKey("sk-abc") == false)
    }

    @Test("Empty key fails validation")
    func emptyAPIKey() {
        #expect(DashScopeKit.validateAPIKey("") == false)
    }

    @Test("Key without sk- prefix fails validation")
    func wrongPrefixAPIKey() {
        #expect(DashScopeKit.validateAPIKey("abcdefghijklmnopqrstuvwxyz123456") == false)
    }

    @Test("Key with whitespace is trimmed")
    func whitespaceAPIKey() {
        #expect(DashScopeKit.validateAPIKey("  sk-abcdefghijklmnopqrstuvwxyz123456  ") == true)
    }

    // MARK: - SSE Streaming

    @Test("Parse text delta from SSE line")
    func parseTextDelta() {
        let line = #"data: {"choices":[{"delta":{"content":"Hello"},"index":0}]}"#
        let result = DashScopeKit.parseStreamLine(line)
        #expect(result == .text("Hello"))
    }

    @Test("Parse [DONE] marker")
    func parseDone() {
        let result = DashScopeKit.parseStreamLine("data: [DONE]")
        #expect(result == .done)
    }

    @Test("Parse finish_reason stop")
    func parseFinishReason() {
        let line = #"data: {"choices":[{"delta":{},"finish_reason":"stop","index":0}]}"#
        let result = DashScopeKit.parseStreamLine(line)
        #expect(result == .done)
    }

    @Test("Parse empty line returns skip")
    func parseEmptyLine() {
        #expect(DashScopeKit.parseStreamLine("") == .skip)
    }

    @Test("Parse SSE comment returns skip")
    func parseComment() {
        #expect(DashScopeKit.parseStreamLine(": keep-alive") == .skip)
    }

    @Test("Parse non-data line returns skip")
    func parseNonDataLine() {
        #expect(DashScopeKit.parseStreamLine("event: message") == .skip)
    }

    @Test("Parse error response")
    func parseError() {
        let line = #"data: {"error":{"message":"Rate limit exceeded","type":"rate_limit_error"}}"#
        let result = DashScopeKit.parseStreamLine(line)
        #expect(result == .error("Rate limit exceeded"))
    }

    @Test("Parse malformed JSON returns skip")
    func parseMalformedJSON() {
        let result = DashScopeKit.parseStreamLine("data: {invalid json}")
        #expect(result == .skip)
    }

    // MARK: - Request Building

    @Test("Build request body produces valid JSON")
    func buildRequestBody() throws {
        let messages = [
            DashScopeKit.ChatMessage(role: .system, content: "You are helpful."),
            DashScopeKit.ChatMessage(role: .user, content: "Hello"),
        ]
        let data = DashScopeKit.buildRequestBody(model: "qwen3-coder-plus", messages: messages)
        #expect(data != nil)

        let jsonObj = try JSONSerialization.jsonObject(with: data!) as! [String: Any]
        let modelValue = jsonObj["model"] as? String
        #expect(modelValue == "qwen3-coder-plus")
        let streamValue = jsonObj["stream"] as? Bool
        #expect(streamValue == true)

        let msgs = jsonObj["messages"] as! [[String: String]]
        #expect(msgs.count == 2)
        #expect(msgs[0]["role"] == "system")
        #expect(msgs[1]["role"] == "user")
        #expect(msgs[1]["content"] == "Hello")
    }

    @Test("Build stream request sets correct headers")
    func buildStreamRequest() {
        let messages = [DashScopeKit.ChatMessage(role: .user, content: "Hi")]
        let request = DashScopeKit.buildStreamRequest(
            region: .international,
            apiKey: "sk-test-key-12345",
            model: "qwen3-coder-plus",
            messages: messages
        )

        #expect(request != nil)
        #expect(request?.httpMethod == "POST")
        #expect(request?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-key-12345")
        #expect(request?.url?.host() == "dashscope-intl.aliyuncs.com")
    }

    // MARK: - Model Catalog

    @Test("Model catalog has expected models")
    func catalogHasModels() {
        #expect(DashScopeKit.modelCatalog.count == 7)
    }

    @Test("Model catalog IDs are unique")
    func catalogUniqueIds() {
        let ids = DashScopeKit.modelCatalog.map(\.modelId)
        #expect(Set(ids).count == ids.count)
    }

    @Test("All catalog models have valid fields")
    func catalogValidFields() {
        for model in DashScopeKit.modelCatalog {
            #expect(!model.modelId.isEmpty)
            #expect(!model.displayName.isEmpty)
            #expect(!model.originalProvider.isEmpty)
        }
    }

    @Test("Default model exists in catalog")
    func defaultModelExists() {
        let found = DashScopeKit.model(for: DashScopeKit.defaultModelId)
        #expect(found != nil)
        #expect(found?.modelId == "qwen3-coder-plus")
    }

    @Test("Model lookup returns nil for unknown ID")
    func unknownModelLookup() {
        #expect(DashScopeKit.model(for: "nonexistent") == nil)
    }

    @Test("Catalog covers all categories")
    func catalogCoversCategories() {
        let categories = Set(DashScopeKit.modelCatalog.map(\.category))
        for cat in DashScopeKit.ModelCategory.allCases {
            #expect(categories.contains(cat), "Missing category: \(cat.rawValue)")
        }
    }

    @Test("Keychain constants are non-empty")
    func keychainConstants() {
        #expect(!DashScopeKit.keychainService.isEmpty)
        #expect(!DashScopeKit.keychainAccount.isEmpty)
    }
}
