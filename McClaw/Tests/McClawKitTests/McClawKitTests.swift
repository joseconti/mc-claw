import Testing
@testable import McClawKit

@Suite("McClawKit Tests")
struct McClawKitTests {
    @Test("CLI execution options have sensible defaults")
    func executionOptionsDefaults() {
        let options = CLIExecutionOptions()
        #expect(options.timeout == 300)
        #expect(options.sessionId == nil)
        #expect(options.maxTokens == nil)
    }
}
