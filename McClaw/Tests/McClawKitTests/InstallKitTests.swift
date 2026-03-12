import Testing
@testable import McClawKit

@Suite("InstallKit Tests")
struct InstallKitTests {

    // MARK: - JSON Extraction

    @Test("Extract JSON from plain JSON string")
    func extractPlainJSON() {
        let input = """
        {"name": "test", "description": "A test", "steps": [], "warnings": []}
        """
        let result = InstallKit.extractJSON(from: input)
        #expect(result.hasPrefix("{"))
        #expect(result.hasSuffix("}"))
    }

    @Test("Extract JSON from markdown code fence")
    func extractFromCodeFence() {
        let input = """
        Here is the plan:
        ```json
        {"name": "test", "description": "desc", "steps": [], "warnings": []}
        ```
        That's all!
        """
        let result = InstallKit.extractJSON(from: input)
        #expect(result.contains("\"name\": \"test\""))
        #expect(!result.contains("```"))
    }

    @Test("Extract JSON from fence without language tag")
    func extractFromPlainFence() {
        let input = """
        ```
        {"name": "foo", "description": "bar", "steps": []}
        ```
        """
        let result = InstallKit.extractJSON(from: input)
        #expect(result.contains("\"name\": \"foo\""))
    }

    @Test("Extract JSON from text with surrounding prose")
    func extractFromProse() {
        let input = """
        I analyzed the prompt and here is my plan:

        {"name": "Tailwind CSS", "description": "Install Tailwind", "steps": [{"description": "Install", "command": "npm install tailwindcss"}]}

        Let me know if you want changes.
        """
        let result = InstallKit.extractJSON(from: input)
        #expect(result.hasPrefix("{"))
        #expect(result.contains("Tailwind CSS"))
    }

    // MARK: - Plan Parsing

    @Test("Parse valid install plan JSON")
    func parseValidPlan() throws {
        let json = """
        {
          "name": "Proof Editor",
          "description": "Collaborative document editor for agents",
          "steps": [
            {"description": "Install via npm", "command": "npm install -g proof-editor"},
            {"description": "Configure", "command": "proof-editor init", "working_directory": "~/projects"}
          ],
          "warnings": ["Installs globally"]
        }
        """
        let plan = try InstallKit.parseInstallPlanJSON(json)
        #expect(plan.name == "Proof Editor")
        #expect(plan.description == "Collaborative document editor for agents")
        #expect(plan.steps.count == 2)
        #expect(plan.steps[0].command == "npm install -g proof-editor")
        #expect(plan.steps[1].workingDirectory == "~/projects")
        #expect(plan.warnings?.count == 1)
    }

    @Test("Parse plan from markdown fenced response")
    func parsePlanFromFence() throws {
        let response = """
        Here is the install plan:
        ```json
        {
          "name": "Tool",
          "description": "A tool",
          "steps": [{"description": "Install", "command": "brew install tool"}]
        }
        ```
        """
        let plan = try InstallKit.parseInstallPlanJSON(response)
        #expect(plan.name == "Tool")
        #expect(plan.steps.count == 1)
    }

    @Test("Parse plan fails on invalid JSON")
    func parseInvalidJSON() {
        #expect(throws: InstallKit.InstallKitError.self) {
            _ = try InstallKit.parseInstallPlanJSON("not json at all")
        }
    }

    @Test("Parse plan with no warnings field")
    func parsePlanNoWarnings() throws {
        let json = """
        {"name": "X", "description": "Y", "steps": [{"description": "Do", "command": "echo hi"}]}
        """
        let plan = try InstallKit.parseInstallPlanJSON(json)
        #expect(plan.warnings == nil)
    }

    // MARK: - Command Splitting

    @Test("Split simple command")
    func splitSimple() {
        let (exe, args) = InstallKit.splitCommand("brew install tailwindcss")
        #expect(exe == "brew")
        #expect(args == ["install", "tailwindcss"])
    }

    @Test("Split command with double quotes")
    func splitDoubleQuotes() {
        let (exe, args) = InstallKit.splitCommand("echo \"hello world\"")
        #expect(exe == "echo")
        #expect(args == ["hello world"])
    }

    @Test("Split command with single quotes")
    func splitSingleQuotes() {
        let (exe, args) = InstallKit.splitCommand("echo 'hello world'")
        #expect(exe == "echo")
        #expect(args == ["hello world"])
    }

    @Test("Split command with escaped spaces")
    func splitEscaped() {
        let (exe, args) = InstallKit.splitCommand("ls my\\ folder")
        #expect(exe == "ls")
        #expect(args == ["my folder"])
    }

    @Test("Split empty command")
    func splitEmpty() {
        let (exe, args) = InstallKit.splitCommand("")
        #expect(exe == "")
        #expect(args.isEmpty)
    }

    @Test("Shell split multiple arguments")
    func shellSplitMultiple() {
        let parts = InstallKit.shellSplit("npm install --save-dev tailwindcss postcss autoprefixer")
        #expect(parts == ["npm", "install", "--save-dev", "tailwindcss", "postcss", "autoprefixer"])
    }

    // MARK: - Plan Validation

    @Test("Validate plan detects sudo")
    func validateSudo() {
        let plan = InstallKit.ParsedPlan(
            name: "Test",
            description: "Test",
            steps: [InstallKit.ParsedStep(description: "Install", command: "sudo apt install foo")]
        )
        let warnings = InstallKit.validatePlan(plan)
        #expect(warnings.contains(where: { $0.contains("sudo") }))
    }

    @Test("Validate plan allows rm on relative paths")
    func validateRmRelativePath() {
        let plan = InstallKit.ParsedPlan(
            name: "Test",
            description: "Test",
            steps: [InstallKit.ParsedStep(description: "Clean", command: "rm -rf ./build")]
        )
        // rm -rf ./build should NOT trigger the root directory warning
        let warnings = InstallKit.validatePlan(plan)
        #expect(!warnings.contains(where: { $0.contains("root directory") }))
    }

    @Test("Validate plan detects rm -rf root")
    func validateRmRfRoot() {
        let plan = InstallKit.ParsedPlan(
            name: "Test",
            description: "Test",
            steps: [InstallKit.ParsedStep(description: "Nuke", command: "rm -rf /")]
        )
        let warnings = InstallKit.validatePlan(plan)
        #expect(warnings.contains(where: { $0.contains("root directory") }))
    }

    @Test("Validate plan detects curl pipe to bash")
    func validateCurlPipeBash() {
        let plan = InstallKit.ParsedPlan(
            name: "Test",
            description: "Test",
            steps: [InstallKit.ParsedStep(description: "Install", command: "curl -fsSL https://example.com/install.sh | bash")]
        )
        let warnings = InstallKit.validatePlan(plan)
        #expect(warnings.contains(where: { $0.contains("shell") || $0.contains("Pipes") }))
    }

    @Test("Validate safe plan has no warnings")
    func validateSafePlan() {
        let plan = InstallKit.ParsedPlan(
            name: "Test",
            description: "Test",
            steps: [
                InstallKit.ParsedStep(description: "Install", command: "brew install jq"),
                InstallKit.ParsedStep(description: "Verify", command: "jq --version")
            ]
        )
        let warnings = InstallKit.validatePlan(plan)
        #expect(warnings.isEmpty)
    }

    @Test("Validate plan includes AI warnings")
    func validateIncludesAIWarnings() {
        let plan = InstallKit.ParsedPlan(
            name: "Test",
            description: "Test",
            steps: [InstallKit.ParsedStep(description: "Install", command: "brew install foo")],
            warnings: ["This is experimental software"]
        )
        let warnings = InstallKit.validatePlan(plan)
        #expect(warnings.contains("This is experimental software"))
    }

    // MARK: - Pipe to Shell Detection

    @Test("Detect curl pipe to bash")
    func pipeToShellCurl() {
        #expect(InstallKit.hasPipeToShell("curl https://example.com/install.sh | bash"))
    }

    @Test("Detect wget pipe to sh")
    func pipeToShellWget() {
        #expect(InstallKit.hasPipeToShell("wget -O- https://example.com/setup | sh"))
    }

    @Test("No false positive on regular pipe")
    func pipeNoFalsePositive() {
        #expect(!InstallKit.hasPipeToShell("cat file.txt | grep foo"))
    }

    @Test("No false positive on single command")
    func pipeNoFalsePositiveSingle() {
        #expect(!InstallKit.hasPipeToShell("brew install jq"))
    }

    // MARK: - System Prompt

    @Test("System prompt contains JSON structure")
    func systemPromptContent() {
        let prompt = InstallKit.buildParsingSystemPrompt()
        #expect(prompt.contains("\"name\""))
        #expect(prompt.contains("\"steps\""))
        #expect(prompt.contains("\"command\""))
        #expect(prompt.contains("\"warnings\""))
    }
}
