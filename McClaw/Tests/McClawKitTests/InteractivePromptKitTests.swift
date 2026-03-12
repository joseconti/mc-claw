import Testing
@testable import McClawKit

@Suite("InteractivePromptKit Tests")
struct InteractivePromptKitTests {

    // MARK: - Extraction: Single Choice

    @Test("Extract single choice prompt from text with JSON block")
    func extractSingleChoice() {
        let input = """
        Here are some options for you:

        ```json
        {"type":"interactive_prompt","id":"q1","title":"What project type?","style":"single_choice","options":[{"key":"1","label":"Presentation"},{"key":"2","label":"Document"}],"required":false}
        ```

        Let me know your choice!
        """
        let (clean, prompts) = InteractivePromptKit.extractPrompts(from: input)
        #expect(prompts.count == 1)
        #expect(prompts[0].id == "q1")
        #expect(prompts[0].style == .singleChoice)
        #expect(prompts[0].options?.count == 2)
        #expect(prompts[0].options?[0].label == "Presentation")
        #expect(prompts[0].title == "What project type?")
        #expect(!clean.contains("interactive_prompt"))
        #expect(clean.contains("Here are some options"))
        #expect(clean.contains("Let me know your choice!"))
    }

    // MARK: - Extraction: Multi Choice

    @Test("Extract multi choice prompt")
    func extractMultiChoice() {
        let input = """
        ```json
        {"type":"interactive_prompt","id":"q2","title":"Select features","style":"multi_choice","options":[{"key":"a","label":"Auth"},{"key":"b","label":"DB"},{"key":"c","label":"Cache"}],"required":true}
        ```
        """
        let (_, prompts) = InteractivePromptKit.extractPrompts(from: input)
        #expect(prompts.count == 1)
        #expect(prompts[0].style == .multiChoice)
        #expect(prompts[0].required == true)
        #expect(prompts[0].options?.count == 3)
    }

    // MARK: - Extraction: Confirmation

    @Test("Extract confirmation prompt")
    func extractConfirmation() {
        let input = """
        I need your approval:

        ```json
        {"type":"interactive_prompt","id":"c1","title":"Delete all files?","description":"This action cannot be undone.","style":"confirmation","required":true}
        ```
        """
        let (clean, prompts) = InteractivePromptKit.extractPrompts(from: input)
        #expect(prompts.count == 1)
        #expect(prompts[0].style == .confirmation)
        #expect(prompts[0].description == "This action cannot be undone.")
        #expect(clean.contains("I need your approval"))
    }

    // MARK: - Extraction: Free Text

    @Test("Extract free text prompt")
    func extractFreeText() {
        let input = """
        ```json
        {"type":"interactive_prompt","id":"ft1","title":"Enter project name","style":"free_text","required":true}
        ```
        """
        let (_, prompts) = InteractivePromptKit.extractPrompts(from: input)
        #expect(prompts.count == 1)
        #expect(prompts[0].style == .freeText)
        #expect(prompts[0].options == nil)
    }

    // MARK: - Extraction: Multiple Prompts

    @Test("Extract multiple prompts from text")
    func extractMultiplePrompts() {
        let input = """
        First question:

        ```json
        {"type":"interactive_prompt","id":"q1","title":"Question 1","style":"single_choice","options":[{"key":"1","label":"A"},{"key":"2","label":"B"}],"required":false}
        ```

        Second question:

        ```json
        {"type":"interactive_prompt","id":"q2","title":"Question 2","style":"confirmation","required":true}
        ```
        """
        let (clean, prompts) = InteractivePromptKit.extractPrompts(from: input)
        #expect(prompts.count == 2)
        #expect(prompts[0].id == "q1")
        #expect(prompts[1].id == "q2")
        #expect(clean.contains("First question"))
        #expect(clean.contains("Second question"))
        #expect(!clean.contains("interactive_prompt"))
    }

    // MARK: - Extraction: Group (Multi-Page)

    @Test("Extract grouped prompts with groupId")
    func extractGroupedPrompts() {
        let input = """
        ```json
        {"type":"interactive_prompt","id":"g1-q1","title":"Step 1","style":"single_choice","options":[{"key":"1","label":"Yes"},{"key":"2","label":"No"}],"required":true,"groupId":"onboarding","groupIndex":0,"groupTotal":3}
        ```

        ```json
        {"type":"interactive_prompt","id":"g1-q2","title":"Step 2","style":"free_text","required":true,"groupId":"onboarding","groupIndex":1,"groupTotal":3}
        ```

        ```json
        {"type":"interactive_prompt","id":"g1-q3","title":"Step 3","style":"confirmation","required":false,"groupId":"onboarding","groupIndex":2,"groupTotal":3}
        ```
        """
        let (_, prompts) = InteractivePromptKit.extractPrompts(from: input)
        #expect(prompts.count == 3)
        #expect(prompts[0].groupId == "onboarding")
        #expect(prompts[0].groupIndex == 0)
        #expect(prompts[0].groupTotal == 3)
        #expect(prompts[2].groupIndex == 2)
    }

    // MARK: - Extraction: No Prompts

    @Test("No prompts in plain text returns original text")
    func noPrompts() {
        let input = "Hello, this is a normal message with no prompts."
        let (clean, prompts) = InteractivePromptKit.extractPrompts(from: input)
        #expect(prompts.isEmpty)
        #expect(clean == input)
    }

    // MARK: - Extraction: Malformed JSON

    @Test("Malformed JSON block is left in text")
    func malformedJSON() {
        let input = """
        Check this:

        ```json
        {"type":"interactive_prompt","id":"bad","title":INVALID}
        ```

        Rest of text.
        """
        let (clean, prompts) = InteractivePromptKit.extractPrompts(from: input)
        #expect(prompts.isEmpty)
        #expect(clean.contains("INVALID"))
    }

    // MARK: - Extraction: Non-interactive JSON block

    @Test("JSON block without interactive_prompt type is preserved")
    func nonInteractiveJSON() {
        let input = """
        Here is some data:

        ```json
        {"type":"other","name":"test","value":42}
        ```
        """
        let (clean, prompts) = InteractivePromptKit.extractPrompts(from: input)
        #expect(prompts.isEmpty)
        #expect(clean.contains("\"type\":\"other\""))
    }

    // MARK: - Extraction: Options with isFreeText

    @Test("Option with isFreeText flag")
    func optionWithFreeText() {
        let input = """
        ```json
        {"type":"interactive_prompt","id":"q1","title":"Choose","style":"single_choice","options":[{"key":"1","label":"Option A"},{"key":"other","label":"Something else...","isFreeText":true}],"required":false}
        ```
        """
        let (_, prompts) = InteractivePromptKit.extractPrompts(from: input)
        #expect(prompts.count == 1)
        #expect(prompts[0].options?[1].isFreeText == true)
        #expect(prompts[0].options?[1].label == "Something else...")
    }

    // MARK: - Response Formatting

    @Test("Format single choice response")
    func formatSingleChoice() {
        let prompt = InteractivePromptKit.InteractivePrompt(
            id: "q1",
            title: "Favorite color",
            style: .singleChoice,
            options: [
                InteractivePromptKit.PromptOption(key: "1", label: "Red"),
                InteractivePromptKit.PromptOption(key: "2", label: "Blue")
            ]
        )
        let response = InteractivePromptKit.PromptResponse(
            promptId: "q1",
            selectedKeys: ["2"]
        )
        let formatted = InteractivePromptKit.formatResponse(response, prompt: prompt)
        #expect(formatted == "[Favorite color: Blue]")
    }

    @Test("Format multi choice response")
    func formatMultiChoice() {
        let prompt = InteractivePromptKit.InteractivePrompt(
            id: "q2",
            title: "Features",
            style: .multiChoice,
            options: [
                InteractivePromptKit.PromptOption(key: "a", label: "Auth"),
                InteractivePromptKit.PromptOption(key: "b", label: "DB"),
                InteractivePromptKit.PromptOption(key: "c", label: "Cache")
            ]
        )
        let response = InteractivePromptKit.PromptResponse(
            promptId: "q2",
            selectedKeys: ["a", "c"]
        )
        let formatted = InteractivePromptKit.formatResponse(response, prompt: prompt)
        #expect(formatted == "[Features: Auth, Cache]")
    }

    @Test("Format skipped response")
    func formatSkipped() {
        let prompt = InteractivePromptKit.InteractivePrompt(
            id: "q1",
            title: "Choose",
            style: .singleChoice
        )
        let response = InteractivePromptKit.PromptResponse(
            promptId: "q1",
            skipped: true
        )
        let formatted = InteractivePromptKit.formatResponse(response, prompt: prompt)
        #expect(formatted == "[Choose: Skipped]")
    }

    @Test("Format free text response")
    func formatFreeText() {
        let prompt = InteractivePromptKit.InteractivePrompt(
            id: "ft1",
            title: "Project name",
            style: .freeText
        )
        let response = InteractivePromptKit.PromptResponse(
            promptId: "ft1",
            freeText: "My Cool App"
        )
        let formatted = InteractivePromptKit.formatResponse(response, prompt: prompt)
        #expect(formatted == "[Project name: My Cool App]")
    }

    @Test("Format confirmation accept response")
    func formatConfirmationAccept() {
        let prompt = InteractivePromptKit.InteractivePrompt(
            id: "c1",
            title: "Delete files?",
            style: .confirmation,
            options: [
                InteractivePromptKit.PromptOption(key: "accept", label: "Accept"),
                InteractivePromptKit.PromptOption(key: "cancel", label: "Cancel")
            ]
        )
        let response = InteractivePromptKit.PromptResponse(
            promptId: "c1",
            selectedKeys: ["accept"]
        )
        let formatted = InteractivePromptKit.formatResponse(response, prompt: prompt)
        #expect(formatted == "[Delete files?: Accept]")
    }

    @Test("Format empty response")
    func formatEmptyResponse() {
        let prompt = InteractivePromptKit.InteractivePrompt(
            id: "q1",
            title: "Choose",
            style: .singleChoice
        )
        let response = InteractivePromptKit.PromptResponse(
            promptId: "q1"
        )
        let formatted = InteractivePromptKit.formatResponse(response, prompt: prompt)
        #expect(formatted == "[Choose: No response]")
    }
}
