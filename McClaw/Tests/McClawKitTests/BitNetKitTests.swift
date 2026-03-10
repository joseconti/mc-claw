import Foundation
import Testing
@testable import McClawKit

@Suite("BitNetKit Tests")
struct BitNetKitTests {

    // MARK: - Paths

    @Test("Home path ends with .mcclaw/bitnet")
    func homePath() {
        #expect(BitNetKit.Paths.home.hasSuffix("/.mcclaw/bitnet"))
    }

    @Test("Models dir is under home")
    func modelsDir() {
        #expect(BitNetKit.Paths.modelsDir == BitNetKit.Paths.home + "/models")
    }

    @Test("Server script path is correct")
    func serverScript() {
        #expect(BitNetKit.Paths.serverScript.hasSuffix("/run_inference_server.py"))
    }

    @Test("Binary path is correct")
    func binaryPath() {
        #expect(BitNetKit.Paths.binary.hasSuffix("/build/bin/llama-cli"))
    }

    @Test("Manifest file path is correct")
    func manifestPath() {
        #expect(BitNetKit.Paths.manifestFile.hasSuffix("/install-manifest.json"))
    }

    @Test("Model dir resolves correctly")
    func modelDir() {
        let dir = BitNetKit.Paths.modelDir("BitNet-b1.58-2B-4T")
        #expect(dir.hasSuffix("/models/BitNet-b1.58-2B-4T"))
    }

    @Test("Resolve model path uses fallback when no .gguf found")
    func resolveModelPathFallback() {
        let path = BitNetKit.Paths.resolveModelPath("nonexistent-model")
        #expect(path.hasSuffix("/ggml-model-i2_s.gguf"))
    }

    // MARK: - Model Registry

    @Test("Registry has 8 models")
    func registryCount() {
        #expect(BitNetKit.modelRegistry.count == 8)
    }

    @Test("Default model is Falcon3-3B-Instruct-1.58bit")
    func defaultModel() {
        let defaultModel = BitNetKit.defaultModel
        #expect(defaultModel != nil)
        #expect(defaultModel?.modelId == "Falcon3-3B-Instruct-1.58bit")
    }

    @Test("Instruct models are marked correctly")
    func instructModels() {
        let instructModels = BitNetKit.modelRegistry.filter(\.isInstruct)
        let baseModels = BitNetKit.modelRegistry.filter { !$0.isInstruct }
        #expect(instructModels.count == 4)
        #expect(baseModels.count == 4)
        // All Falcon3 Instruct should be instruct
        for model in instructModels {
            #expect(model.modelId.contains("Instruct"))
        }
    }

    @Test("Only one default model exists")
    func singleDefault() {
        let defaults = BitNetKit.modelRegistry.filter(\.isDefault)
        #expect(defaults.count == 1)
    }

    @Test("Registry lookup by ID works")
    func registryLookup() {
        let model = BitNetKit.registryModel(for: "bitnet_b1_58-3B")
        #expect(model != nil)
        #expect(model?.parameters == "3.3B")
    }

    @Test("Registry lookup for unknown returns nil")
    func registryLookupMissing() {
        let model = BitNetKit.registryModel(for: "nonexistent")
        #expect(model == nil)
    }

    // MARK: - Version Parsing

    @Test("Parse Python version")
    func parsePythonVersion() {
        let version = BitNetKit.parseVersion(from: "Python 3.11.5")
        #expect(version == "3.11.5")
    }

    @Test("Parse CMake version")
    func parseCMakeVersion() {
        let version = BitNetKit.parseVersion(from: "cmake version 3.28.1")
        #expect(version == "3.28.1")
    }

    @Test("Parse Conda version")
    func parseCondaVersion() {
        let version = BitNetKit.parseVersion(from: "conda 24.1.0")
        #expect(version == "24.1.0")
    }

    @Test("Parse Clang version")
    func parseClangVersion() {
        let version = BitNetKit.parseVersion(from: "Apple clang version 18.0.0 (clang-1800.0.26.1)")
        #expect(version == "18.0.0")
    }

    @Test("Parse version returns nil for garbage")
    func parseVersionGarbage() {
        let version = BitNetKit.parseVersion(from: "no version here")
        #expect(version == nil)
    }

    // MARK: - Version Comparison

    @Test("Version meets minimum - equal")
    func versionEqual() {
        #expect(BitNetKit.versionMeetsMinimum("3.9", minimum: "3.9"))
    }

    @Test("Version meets minimum - higher major")
    func versionHigherMajor() {
        #expect(BitNetKit.versionMeetsMinimum("4.0", minimum: "3.9"))
    }

    @Test("Version meets minimum - higher minor")
    func versionHigherMinor() {
        #expect(BitNetKit.versionMeetsMinimum("3.11", minimum: "3.9"))
    }

    @Test("Version does not meet minimum")
    func versionBelowMinimum() {
        #expect(!BitNetKit.versionMeetsMinimum("3.8", minimum: "3.9"))
    }

    @Test("Version comparison with different depths")
    func versionDifferentDepths() {
        #expect(BitNetKit.versionMeetsMinimum("3.11.5", minimum: "3.9"))
        #expect(BitNetKit.versionMeetsMinimum("18.0.0", minimum: "18"))
        #expect(!BitNetKit.versionMeetsMinimum("17.9.9", minimum: "18"))
    }

    // MARK: - Command Building

    @Test("Server start args include llama-server and port")
    func serverStartArgs() {
        let config = BitNetKit.ServerConfig(port: 9000)
        let args = BitNetKit.buildServerStartArgs(modelPath: "/path/to/model.gguf", config: config)
        #expect(args.first?.hasSuffix("llama-server") == true)
        #expect(args.contains("-m"))
        #expect(args.contains("/path/to/model.gguf"))
        #expect(args.contains("--port"))
        #expect(args.contains("9000"))
        #expect(args.contains("--host"))
    }

    @Test("Model download args include repo and local dir")
    func modelDownloadArgs() {
        let args = BitNetKit.buildModelDownloadArgs(
            repo: "microsoft/BitNet-b1.58-2B-4T-gguf",
            localDir: "/tmp/model"
        )
        #expect(args.contains("download"))
        #expect(args.contains("microsoft/BitNet-b1.58-2B-4T-gguf"))
        #expect(args.contains("/tmp/model"))
    }

    @Test("Setup args include model dir and quantization")
    func setupArgs() {
        let args = BitNetKit.buildSetupArgs(modelDir: "models/test", quantization: "tl1")
        #expect(args.contains(where: { $0.hasSuffix("setup_env.py") }))
        #expect(args.contains("-md"))
        #expect(args.contains("models/test"))
        #expect(args.contains("-q"))
        #expect(args.contains("tl1"))
    }

    @Test("Conda create args include python version")
    func condaCreateArgs() {
        let args = BitNetKit.buildCondaCreateArgs()
        #expect(args.contains("create"))
        #expect(args.contains("-n"))
        #expect(args.contains(BitNetKit.condaEnvironment))
        #expect(args.contains("python=\(BitNetKit.pythonVersion)"))
        #expect(args.contains("-y"))
    }

    @Test("Pip install args reference requirements file")
    func pipInstallArgs() {
        let args = BitNetKit.buildPipInstallArgs()
        #expect(args.contains("pip"))
        #expect(args.contains("install"))
        #expect(args.contains("-r"))
        #expect(args.contains(BitNetKit.Paths.requirements))
    }

    @Test("Inference args with all options")
    func inferenceArgsAllOptions() {
        let args = BitNetKit.buildInferenceArgs(
            modelPath: "/model.gguf",
            prompt: "Hello",
            threads: 8,
            maxTokens: 512,
            temperature: 0.5
        )
        #expect(args.contains("-t"))
        #expect(args.contains("8"))
        #expect(args.contains("-n"))
        #expect(args.contains("512"))
        #expect(args.contains("-temp"))
        #expect(args.contains("0.5"))
        #expect(args.contains("Hello"))
    }

    @Test("Inference args without optional params")
    func inferenceArgsMinimal() {
        let args = BitNetKit.buildInferenceArgs(modelPath: "/model.gguf", prompt: "Hi")
        #expect(!args.contains("-t"))
        #expect(!args.contains("-temp"))
        #expect(args.contains("Hi"))
    }

    // MARK: - Response Parsing

    @Test("Parse text line")
    func parseTextLine() {
        let event = BitNetKit.parseResponseLine("Hello world")
        #expect(event == .text("Hello world"))
    }

    @Test("Parse empty line")
    func parseEmptyLine() {
        let event = BitNetKit.parseResponseLine("")
        #expect(event == .empty)
    }

    @Test("Parse whitespace-only line")
    func parseWhitespaceLine() {
        let event = BitNetKit.parseResponseLine("   ")
        #expect(event == .empty)
    }

    @Test("Parse prompt marker")
    func parsePromptMarker() {
        let event = BitNetKit.parseResponseLine("> ")
        #expect(event == .promptMarker)
    }

    // MARK: - Server Config

    @Test("Default server config values")
    func defaultServerConfig() {
        let config = BitNetKit.ServerConfig()
        #expect(config.host == "127.0.0.1")
        #expect(config.port == 8921)
        #expect(config.timeout == 120)
    }

    @Test("Server config base URL")
    func serverConfigBaseURL() {
        let config = BitNetKit.ServerConfig(port: 9000)
        #expect(config.baseURL == "http://127.0.0.1:9000")
    }

    @Test("Server config health URL")
    func serverConfigHealthURL() {
        let config = BitNetKit.ServerConfig()
        #expect(config.healthURL == "http://127.0.0.1:8921/health")
    }

    // MARK: - Install Manifest

    @Test("Record prerequisite in manifest")
    func manifestRecordPrerequisite() {
        var manifest = BitNetKit.InstallManifest()
        manifest.recordPrerequisite(
            name: "cmake",
            wasPresent: false,
            installedByMcClaw: true,
            version: "3.28",
            installMethod: "brew install cmake"
        )
        #expect(manifest.prerequisites["cmake"]?.installedByMcClaw == true)
        #expect(manifest.prerequisites["cmake"]?.wasPresent == false)
        #expect(manifest.prerequisites["cmake"]?.installMethod == "brew install cmake")
    }

    @Test("McClaw installed prerequisites filter")
    func manifestMcClawInstalled() {
        var manifest = BitNetKit.InstallManifest()
        manifest.recordPrerequisite(name: "cmake", wasPresent: false, installedByMcClaw: true)
        manifest.recordPrerequisite(name: "conda", wasPresent: true, installedByMcClaw: false)
        manifest.recordPrerequisite(name: "clang", wasPresent: false, installedByMcClaw: true)

        let installed = manifest.mcclawInstalledPrerequisites
        #expect(installed.count == 2)
        #expect(installed[0].name == "clang")
        #expect(installed[1].name == "cmake")
    }

    @Test("Add and remove models in manifest")
    func manifestModels() {
        var manifest = BitNetKit.InstallManifest()
        manifest.addModel("BitNet-b1.58-2B-4T")
        manifest.addModel("bitnet_b1_58-3B")
        #expect(manifest.components.installedModels.count == 2)

        // Adding duplicate does nothing
        manifest.addModel("BitNet-b1.58-2B-4T")
        #expect(manifest.components.installedModels.count == 2)

        manifest.removeModel("BitNet-b1.58-2B-4T")
        #expect(manifest.components.installedModels.count == 1)
        #expect(manifest.components.installedModels.first == "bitnet_b1_58-3B")
    }

    @Test("Manifest JSON round-trip")
    func manifestCodable() throws {
        var manifest = BitNetKit.InstallManifest(installedAt: Date(timeIntervalSince1970: 1000))
        manifest.recordPrerequisite(name: "cmake", wasPresent: false, installedByMcClaw: true)
        manifest.components.repositoryInstalled = true
        manifest.addModel("test-model")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BitNetKit.InstallManifest.self, from: data)

        #expect(decoded == manifest)
    }

    // MARK: - Prerequisites

    @Test("Prerequisites list has 5 entries")
    func prerequisitesCount() {
        #expect(BitNetKit.prerequisites.count == 5)
    }

    @Test("All prerequisites have check commands")
    func prerequisitesHaveCheckCommands() {
        for prereq in BitNetKit.prerequisites {
            #expect(!prereq.checkCommand.isEmpty)
        }
    }

    // MARK: - Uninstall Commands

    @Test("Conda remove args")
    func condaRemoveArgs() {
        let args = BitNetKit.buildCondaRemoveArgs()
        #expect(args.contains("env"))
        #expect(args.contains("remove"))
        #expect(args.contains(BitNetKit.condaEnvironment))
        #expect(args.contains("-y"))
    }

    @Test("Brew formula extraction")
    func brewFormulaExtraction() {
        #expect(BitNetKit.brewFormula(from: "brew install cmake") == "cmake")
        #expect(BitNetKit.brewFormula(from: "brew install llvm@18") == "llvm@18")
        #expect(BitNetKit.brewFormula(from: "invalid command") == nil)
        #expect(BitNetKit.brewFormula(from: "brew uninstall cmake") == nil)
    }
}
