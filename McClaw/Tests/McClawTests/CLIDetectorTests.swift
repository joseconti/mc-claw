import Testing
@testable import McClawKit

@Suite("McClawKit Integration Tests")
struct McClawKitIntegrationTests {
    @Test("CLI execution options can be created with defaults")
    func executionOptions() {
        let options = CLIExecutionOptions()
        #expect(options.timeout == 300)
        #expect(options.sessionId == nil)
    }

    @Test("CLI execution options accept custom values")
    func customOptions() {
        let options = CLIExecutionOptions(
            sessionId: "test-session",
            maxTokens: 4096,
            temperature: 0.7,
            systemPrompt: "You are helpful.",
            timeout: 60
        )
        #expect(options.sessionId == "test-session")
        #expect(options.maxTokens == 4096)
        #expect(options.timeout == 60)
    }
}
