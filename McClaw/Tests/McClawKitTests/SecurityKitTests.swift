import Testing
@testable import McClawKit

@Suite("SecurityKit Tests")
struct SecurityKitTests {

    // MARK: - Glob Pattern Matching

    @Test("Glob matches exact path")
    func globMatchesExact() {
        #expect(SecurityKit.globMatches(pattern: "/usr/bin/python3", path: "/usr/bin/python3"))
    }

    @Test("Glob does not match different path")
    func globNoMatchDifferent() {
        #expect(!SecurityKit.globMatches(pattern: "/usr/bin/python3", path: "/usr/bin/ruby"))
    }

    @Test("Glob star matches single component")
    func globStarSingleComponent() {
        #expect(SecurityKit.globMatches(pattern: "/usr/bin/python*", path: "/usr/bin/python3"))
        #expect(SecurityKit.globMatches(pattern: "/usr/bin/python*", path: "/usr/bin/python3.9"))
        #expect(!SecurityKit.globMatches(pattern: "/usr/bin/python*", path: "/usr/bin/ruby"))
    }

    @Test("Glob star does not cross directories")
    func globStarNoCrossDir() {
        #expect(!SecurityKit.globMatches(pattern: "/usr/bin/*", path: "/usr/bin/sub/cmd"))
    }

    @Test("Glob double star crosses directories")
    func globDoubleStarCrossDir() {
        #expect(SecurityKit.globMatches(pattern: "/usr/**", path: "/usr/bin/python3"))
        #expect(SecurityKit.globMatches(pattern: "/usr/**", path: "/usr/local/bin/node"))
    }

    @Test("Glob question mark matches single char")
    func globQuestionMark() {
        #expect(SecurityKit.globMatches(pattern: "/usr/bin/python?", path: "/usr/bin/python3"))
        #expect(!SecurityKit.globMatches(pattern: "/usr/bin/python?", path: "/usr/bin/python39"))
    }

    @Test("Glob is case-insensitive")
    func globCaseInsensitive() {
        #expect(SecurityKit.globMatches(pattern: "/usr/bin/Python3", path: "/usr/bin/python3"))
    }

    @Test("Glob normalizes backslashes")
    func globNormalizesBackslashes() {
        #expect(SecurityKit.globMatches(pattern: "/usr\\bin\\cmd", path: "/usr/bin/cmd"))
    }

    // MARK: - Pattern Validation

    @Test("Valid patterns accepted")
    func validPatterns() {
        #expect(SecurityKit.validateAllowlistPattern("/usr/bin/python*") == .valid("/usr/bin/python*"))
        #expect(SecurityKit.validateAllowlistPattern("~/bin/my-tool") == .valid("~/bin/my-tool"))
    }

    @Test("Empty pattern rejected")
    func emptyPatternRejected() {
        #expect(SecurityKit.validateAllowlistPattern("") == .invalid(reason: "Pattern cannot be empty"))
        #expect(SecurityKit.validateAllowlistPattern("   ") == .invalid(reason: "Pattern cannot be empty"))
    }

    @Test("Non-path pattern rejected")
    func nonPathPatternRejected() {
        if case .invalid(let reason) = SecurityKit.validateAllowlistPattern("python3") {
            #expect(reason.contains("path"))
        } else {
            Issue.record("Expected invalid validation for non-path pattern")
        }
    }

    // MARK: - Shell Wrapper Parsing

    @Test("Parses bash -c command")
    func parsesBashC() {
        let commands = SecurityKit.parseShellPayload(
            shell: "/bin/bash",
            arguments: ["-c", "ls -la | grep foo"]
        )
        #expect(commands == ["ls -la", "grep foo"])
    }

    @Test("Parses zsh -lc command")
    func parsesZshLC() {
        let commands = SecurityKit.parseShellPayload(
            shell: "/bin/zsh",
            arguments: ["-lc", "which python3"]
        )
        #expect(commands == ["which python3"])
    }

    @Test("Returns empty for non-shell")
    func nonShellReturnsEmpty() {
        let commands = SecurityKit.parseShellPayload(
            shell: "/usr/bin/python3",
            arguments: ["-c", "print('hello')"]
        )
        #expect(commands.isEmpty)
    }

    @Test("Rejects command substitution")
    func rejectsSubstitution() {
        let commands1 = SecurityKit.parseShellPayload(
            shell: "/bin/bash",
            arguments: ["-c", "echo $(whoami)"]
        )
        #expect(commands1.isEmpty)

        let commands2 = SecurityKit.parseShellPayload(
            shell: "/bin/bash",
            arguments: ["-c", "echo `whoami`"]
        )
        #expect(commands2.isEmpty)
    }

    @Test("Returns empty without -c flag")
    func noCFlagReturnsEmpty() {
        let commands = SecurityKit.parseShellPayload(
            shell: "/bin/bash",
            arguments: ["-l", "script.sh"]
        )
        #expect(commands.isEmpty)
    }

    // MARK: - Environment Sanitization

    @Test("Removes blocked exact variables")
    func removesBlockedExact() {
        let env: [String: String] = [
            "PATH": "/usr/bin",
            "HOME": "/Users/test",
            "NODE_OPTIONS": "--experimental-loader",
            "PYTHONPATH": "/evil",
            "BASH_ENV": "/evil/.bashrc",
            "SAFE_VAR": "ok",
        ]
        let result = SecurityKit.sanitizeEnvironment(env: env)
        #expect(result["PATH"] == "/usr/bin")
        #expect(result["HOME"] == "/Users/test")
        #expect(result["SAFE_VAR"] == "ok")
        #expect(result["NODE_OPTIONS"] == nil)
        #expect(result["PYTHONPATH"] == nil)
        #expect(result["BASH_ENV"] == nil)
        #expect(result["MCCLAW_CLIENT"] == "1")
    }

    @Test("Removes blocked prefix variables")
    func removesBlockedPrefixes() {
        let env: [String: String] = [
            "PATH": "/usr/bin",
            "DYLD_INSERT_LIBRARIES": "/evil.dylib",
            "LD_PRELOAD": "/evil.so",
            "BASH_FUNC_evil%%": "() { evil; }",
        ]
        let result = SecurityKit.sanitizeEnvironment(env: env)
        #expect(result["PATH"] == "/usr/bin")
        #expect(result["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(result["LD_PRELOAD"] == nil)
        #expect(result["BASH_FUNC_evil%%"] == nil)
    }

    @Test("Override blocked variables rejected")
    func overrideBlockedRejected() {
        let env: [String: String] = ["PATH": "/usr/bin"]
        let overrides: [String: String] = [
            "HOME": "/tmp/evil",
            "EDITOR": "evil-editor",
            "PATH": "/evil/path",
            "GIT_CONFIG_GLOBAL": "/evil",
            "NPM_CONFIG_PREFIX": "/evil",
            "CUSTOM_VAR": "allowed",
        ]
        let result = SecurityKit.sanitizeEnvironment(env: env, overrides: overrides)
        #expect(result["PATH"] == "/usr/bin")  // Not overridden
        #expect(result["HOME"] == nil)  // Override blocked
        #expect(result["EDITOR"] == nil)  // Override blocked
        #expect(result["GIT_CONFIG_GLOBAL"] == nil)
        #expect(result["NPM_CONFIG_PREFIX"] == nil)
        #expect(result["CUSTOM_VAR"] == "allowed")  // Custom allowed
    }

    @Test("Shell wrapper mode is very restrictive")
    func shellWrapperRestrictive() {
        let env: [String: String] = [
            "PATH": "/usr/bin",
            "HOME": "/Users/test",
            "TERM": "xterm-256color",
            "LANG": "en_US.UTF-8",
            "SECRET_KEY": "supersecret",
            "CUSTOM_VAR": "value",
        ]
        let result = SecurityKit.sanitizeEnvironment(env: env, isShellWrapper: true)
        #expect(result["PATH"] == "/usr/bin")
        #expect(result["TERM"] == "xterm-256color")
        #expect(result["LANG"] == "en_US.UTF-8")
        #expect(result["MCCLAW_CLIENT"] == "1")
        #expect(result["HOME"] == nil)  // Not in shell wrapper allowlist
        #expect(result["SECRET_KEY"] == nil)
        #expect(result["CUSTOM_VAR"] == nil)
    }

    @Test("Injects MCCLAW_CLIENT marker")
    func injectsMcClawMarker() {
        let result = SecurityKit.sanitizeEnvironment(env: [:])
        #expect(result["MCCLAW_CLIENT"] == "1")
        #expect(result["NO_COLOR"] == "1")
    }
}
