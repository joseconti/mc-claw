import Foundation

/// Pure logic helpers for BitNet provider, extracted for testability.
/// BitNet is Microsoft's 1-bit LLM inference framework (1.58-bit weights).
public enum BitNetKit {

    // MARK: - Paths

    /// Resolve BitNet-related file system paths.
    public enum Paths {
        /// Root installation directory.
        public static var home: String {
            NSHomeDirectory() + "/.mcclaw/bitnet"
        }

        /// Root directory for tools installed by McClaw.
        public static var toolsDir: String {
            NSHomeDirectory() + "/.mcclaw/tools"
        }

        /// Path to the locally installed CMake binary.
        public static var cmakeBin: String {
            toolsDir + "/cmake/CMake.app/Contents/bin/cmake"
        }

        /// Directory containing the locally installed CMake binary.
        public static var cmakeBinDir: String {
            toolsDir + "/cmake/CMake.app/Contents/bin"
        }

        /// Path to the HuggingFace CLI standalone binary.
        public static var hfCliBin: String {
            NSHomeDirectory() + "/.local/bin/hf"
        }

        /// Directory containing the HuggingFace CLI standalone installation.
        public static var hfCliHome: String {
            NSHomeDirectory() + "/.hf-cli"
        }

        /// Directory containing downloaded models.
        public static var modelsDir: String {
            home + "/models"
        }

        /// Path to the inference REST API server script.
        public static var serverScript: String {
            home + "/run_inference_server.py"
        }

        /// Path to the CLI inference script (fallback).
        public static var inferenceScript: String {
            home + "/run_inference.py"
        }

        /// Path to the setup/build script.
        public static var setupScript: String {
            home + "/setup_env.py"
        }

        /// Path to the compiled inference binary (CLI).
        public static var binary: String {
            home + "/build/bin/llama-cli"
        }

        /// Path to the compiled server binary.
        public static var llamaServer: String {
            home + "/build/bin/llama-server"
        }

        /// Path to the requirements file.
        public static var requirements: String {
            home + "/requirements.txt"
        }

        /// Path to the install manifest JSON.
        public static var manifestFile: String {
            home + "/install-manifest.json"
        }

        /// Resolve the directory for a specific model.
        public static func modelDir(_ modelId: String) -> String {
            modelsDir + "/\(modelId)"
        }

        /// Find the .gguf file inside a model directory.
        public static func ggufFile(in modelDir: String) -> String? {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: modelDir) else {
                return nil
            }
            let ggufs = contents.filter { $0.hasSuffix(".gguf") }
            // Prefer i2_s quantized model (small, BitNet-optimized)
            if let i2s = ggufs.first(where: { $0.contains("i2_s") }) {
                return modelDir + "/\(i2s)"
            }
            if let first = ggufs.first {
                return modelDir + "/\(first)"
            }
            return nil
        }

        /// Resolve the .gguf path for a model, with fallback to default name.
        public static func resolveModelPath(_ modelId: String) -> String {
            let dir = modelDir(modelId)
            return ggufFile(in: dir) ?? dir + "/ggml-model-i2_s.gguf"
        }
    }

    // MARK: - Conda Environment

    /// Name of the isolated conda environment for BitNet.
    public static let condaEnvironment = "mcclaw-bitnet"

    /// Default Python version for the conda environment.
    public static let pythonVersion = "3.9"

    // MARK: - Server Configuration

    /// Configuration for the BitNet REST API server.
    public struct ServerConfig: Sendable, Codable, Equatable {
        public var host: String
        public var port: Int
        public var threads: Int
        public var contextSize: Int
        public var maxTokens: Int
        public var temperature: Double
        public var timeout: TimeInterval

        public init(
            host: String = "127.0.0.1",
            port: Int = 8921,
            threads: Int = 4,
            contextSize: Int = 2048,
            maxTokens: Int = 512,
            temperature: Double = 0.8,
            timeout: TimeInterval = 120
        ) {
            self.host = host
            self.port = port
            self.threads = threads
            self.contextSize = contextSize
            self.maxTokens = maxTokens
            self.temperature = temperature
            self.timeout = timeout
        }

        /// Base URL for the REST API server.
        public var baseURL: String {
            "http://\(host):\(port)"
        }

        /// Health check endpoint URL.
        public var healthURL: String {
            "\(baseURL)/health"
        }
    }

    // MARK: - Model Registry

    /// Information about a known BitNet-compatible model.
    public struct ModelInfo: Sendable, Codable, Equatable, Identifiable {
        public var id: String { modelId }
        public let modelId: String
        public let displayName: String
        public let huggingFaceRepo: String
        public let parameters: String
        public let sizeOnDisk: String
        public let quantizationTypes: [String]
        public let isDefault: Bool
        public let isInstruct: Bool
        public let description: String

        public init(
            modelId: String,
            displayName: String,
            huggingFaceRepo: String,
            parameters: String,
            sizeOnDisk: String,
            quantizationTypes: [String],
            isDefault: Bool,
            isInstruct: Bool = false,
            description: String
        ) {
            self.modelId = modelId
            self.displayName = displayName
            self.huggingFaceRepo = huggingFaceRepo
            self.parameters = parameters
            self.sizeOnDisk = sizeOnDisk
            self.quantizationTypes = quantizationTypes
            self.isDefault = isDefault
            self.isInstruct = isInstruct
            self.description = description
        }
    }

    /// Registry of known BitNet-compatible models available for download.
    /// Models marked as `isInstruct` support chat/conversation mode (-cnv).
    public static let modelRegistry: [ModelInfo] = [
        // Falcon3 Instruct models (recommended — chat-capable)
        ModelInfo(
            modelId: "Falcon3-3B-Instruct-1.58bit",
            displayName: "Falcon3 3B Instruct",
            huggingFaceRepo: "tiiuae/Falcon3-3B-Instruct-1.58bit",
            parameters: "3.0B",
            sizeOnDisk: "~700 MB",
            quantizationTypes: ["i2_s"],
            isDefault: true,
            isInstruct: true,
            description: "Falcon3 3B chat model. Best balance of quality and speed."
        ),
        ModelInfo(
            modelId: "Falcon3-1B-Instruct-1.58bit",
            displayName: "Falcon3 1B Instruct",
            huggingFaceRepo: "tiiuae/Falcon3-1B-Instruct-1.58bit",
            parameters: "1.0B",
            sizeOnDisk: "~300 MB",
            quantizationTypes: ["i2_s"],
            isDefault: false,
            isInstruct: true,
            description: "Falcon3 1B chat model. Fastest, lower quality."
        ),
        ModelInfo(
            modelId: "Falcon3-7B-Instruct-1.58bit",
            displayName: "Falcon3 7B Instruct",
            huggingFaceRepo: "tiiuae/Falcon3-7B-Instruct-1.58bit",
            parameters: "7.0B",
            sizeOnDisk: "~1.5 GB",
            quantizationTypes: ["i2_s"],
            isDefault: false,
            isInstruct: true,
            description: "Falcon3 7B chat model. Higher quality, slower."
        ),
        ModelInfo(
            modelId: "Falcon3-10B-Instruct-1.58bit",
            displayName: "Falcon3 10B Instruct",
            huggingFaceRepo: "tiiuae/Falcon3-10B-Instruct-1.58bit",
            parameters: "10.0B",
            sizeOnDisk: "~2.5 GB",
            quantizationTypes: ["i2_s"],
            isDefault: false,
            isInstruct: true,
            description: "Falcon3 10B chat model. Best quality, most resources."
        ),
        // Base/research models (no chat support)
        ModelInfo(
            modelId: "BitNet-b1.58-2B-4T",
            displayName: "BitNet 2B (Microsoft)",
            huggingFaceRepo: "microsoft/BitNet-b1.58-2B-4T-gguf",
            parameters: "2.4B",
            sizeOnDisk: "~500 MB",
            quantizationTypes: ["i2_s"],
            isDefault: false,
            description: "Official Microsoft 1-bit LLM. Known GGUF tokenizer issue."
        ),
        ModelInfo(
            modelId: "bitnet_b1_58-large",
            displayName: "BitNet Large (0.7B)",
            huggingFaceRepo: "1bitLLM/bitnet_b1_58-large",
            parameters: "0.7B",
            sizeOnDisk: "~200 MB",
            quantizationTypes: ["i2_s"],
            isDefault: false,
            description: "Base model (no chat). Fast inference, research only."
        ),
        ModelInfo(
            modelId: "bitnet_b1_58-3B",
            displayName: "BitNet 3B",
            huggingFaceRepo: "1bitLLM/bitnet_b1_58-3B",
            parameters: "3.3B",
            sizeOnDisk: "~700 MB",
            quantizationTypes: ["i2_s"],
            isDefault: false,
            description: "Base model (no chat). 3.3B parameters, research only."
        ),
        ModelInfo(
            modelId: "Llama3-8B-1.58-100B-tokens",
            displayName: "Llama3 8B (1-bit)",
            huggingFaceRepo: "HF1BitLLM/Llama3-8B-1.58-100B-tokens",
            parameters: "8.0B",
            sizeOnDisk: "~1.5 GB",
            quantizationTypes: ["i2_s"],
            isDefault: false,
            description: "Base model (no chat). Llama3 8B with 1-bit weights."
        ),
    ]

    /// The default model from the registry.
    public static var defaultModel: ModelInfo? {
        modelRegistry.first(where: \.isDefault)
    }

    /// Look up a model by ID in the registry.
    public static func registryModel(for id: String) -> ModelInfo? {
        modelRegistry.first(where: { $0.modelId == id })
    }

    // MARK: - Prerequisites

    /// A system prerequisite required for BitNet installation.
    public struct Prerequisite: Sendable, Equatable {
        public let name: String
        public let displayName: String
        public let minVersion: String?
        public let checkCommand: [String]
        public let installCommand: String?
        /// A shell script that can install this prerequisite without Homebrew.
        /// Used as the primary install method; `installCommand` (brew) is the fallback.
        public let directInstallScript: String?

        public init(
            name: String,
            displayName: String,
            minVersion: String?,
            checkCommand: [String],
            installCommand: String?,
            directInstallScript: String? = nil
        ) {
            self.name = name
            self.displayName = displayName
            self.minVersion = minVersion
            self.checkCommand = checkCommand
            self.installCommand = installCommand
            self.directInstallScript = directInstallScript
        }
    }

    /// Result of checking a single prerequisite.
    public struct PrerequisiteStatus: Sendable, Equatable {
        public let prerequisite: Prerequisite
        public let isPresent: Bool
        public let detectedVersion: String?
        public let meetsMinimum: Bool

        public init(prerequisite: Prerequisite, isPresent: Bool, detectedVersion: String?, meetsMinimum: Bool) {
            self.prerequisite = prerequisite
            self.isPresent = isPresent
            self.detectedVersion = detectedVersion
            self.meetsMinimum = meetsMinimum
        }
    }

    /// All prerequisites required by BitNet.
    /// Order matters: Conda (Miniforge) is installed first because it bundles Python 3.
    public static let prerequisites: [Prerequisite] = [
        Prerequisite(
            name: "git",
            displayName: "Git",
            minVersion: nil,
            checkCommand: ["git", "--version"],
            installCommand: nil
        ),
        Prerequisite(
            name: "conda",
            displayName: "Conda",
            minVersion: nil,
            checkCommand: ["conda", "--version"],
            installCommand: "brew install --cask miniconda",
            directInstallScript: """
                curl -fsSL -o /tmp/miniforge.sh \
                  https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-$(uname -m).sh && \
                bash /tmp/miniforge.sh -b -p $HOME/miniforge3 && \
                rm -f /tmp/miniforge.sh && \
                $HOME/miniforge3/bin/conda init zsh bash 2>/dev/null; true
                """
        ),
        Prerequisite(
            name: "python3",
            displayName: "Python",
            minVersion: "3.9",
            checkCommand: ["python3", "--version"],
            installCommand: "brew install python@3.11",
            directInstallScript: """
                curl -fsSL -o /tmp/python-installer.pkg \
                  "https://www.python.org/ftp/python/3.11.9/python-3.11.9-macos11.pkg" && \
                sudo installer -pkg /tmp/python-installer.pkg -target / 2>/dev/null || \
                installer -pkg /tmp/python-installer.pkg -target CurrentUserHomeDirectory 2>/dev/null; \
                rm -f /tmp/python-installer.pkg
                """
        ),
        Prerequisite(
            name: "cmake",
            displayName: "CMake",
            minVersion: "3.22",
            checkCommand: ["cmake", "--version"],
            installCommand: "brew install cmake",
            directInstallScript: """
                CMAKE_VER=3.31.6 && \
                mkdir -p $HOME/.mcclaw/tools/cmake && \
                curl -fsSL -o /tmp/cmake-macos.tar.gz \
                  "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-macos-universal.tar.gz" && \
                tar xf /tmp/cmake-macos.tar.gz -C $HOME/.mcclaw/tools/cmake --strip-components=1 && \
                rm -f /tmp/cmake-macos.tar.gz
                """
        ),
        Prerequisite(
            name: "clang",
            displayName: "Clang",
            minVersion: "18",
            checkCommand: ["clang", "--version"],
            installCommand: "brew install llvm@18",
            directInstallScript: """
                LLVM_VER=18.1.8 && \
                ARCH=$(uname -m) && \
                if [ "$ARCH" = "arm64" ]; then LLVM_ARCH="arm64-apple-macos11.0"; else LLVM_ARCH="x86_64-apple-darwin21.0"; fi && \
                curl -fsSL -o /tmp/llvm.tar.xz \
                  "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VER}/clang+llvm-${LLVM_VER}-${LLVM_ARCH}.tar.xz" && \
                mkdir -p $HOME/.local && \
                tar xf /tmp/llvm.tar.xz -C $HOME/.local --strip-components=1 && \
                rm -f /tmp/llvm.tar.xz
                """
        ),
    ]

    /// Parse a version string from command output.
    /// Handles formats like "Python 3.11.5", "cmake version 3.28.1", "conda 24.1.0", etc.
    public static func parseVersion(from output: String) -> String? {
        // Match version-like patterns: digits separated by dots
        let pattern = #"(\d+(?:\.\d+)*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        return String(output[range])
    }

    /// Compare two version strings (e.g. "3.11" >= "3.9").
    /// Returns true if `version` meets or exceeds `minimum`.
    public static func versionMeetsMinimum(_ version: String, minimum: String) -> Bool {
        let vParts = version.split(separator: ".").compactMap { Int($0) }
        let mParts = minimum.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(vParts.count, mParts.count) {
            let v = i < vParts.count ? vParts[i] : 0
            let m = i < mParts.count ? mParts[i] : 0
            if v > m { return true }
            if v < m { return false }
        }
        return true // Equal
    }

    // MARK: - Command Building

    /// Build arguments to start the BitNet REST API server (llama-server directly).
    public static func buildServerStartArgs(
        modelPath: String,
        config: ServerConfig = ServerConfig()
    ) -> [String] {
        [
            Paths.llamaServer,
            "-m", modelPath,
            "-c", String(config.contextSize),
            "-t", String(config.threads),
            "-n", String(config.maxTokens),
            "-ngl", "0",
            "--temp", String(config.temperature),
            "--host", config.host,
            "--port", String(config.port),
        ]
    }

    /// Build arguments to download a model via `hf` CLI.
    public static func buildModelDownloadArgs(repo: String, localDir: String) -> [String] {
        [
            "conda", "run", "-n", condaEnvironment,
            "hf", "download", repo,
            "--local-dir", localDir,
        ]
    }

    /// Build arguments to run setup_env.py for a model (compile kernels).
    /// When `usePretuned` is true, passes `-p` to use pretuned kernel parameters.
    public static func buildSetupArgs(
        modelDir: String,
        quantization: String = "i2_s",
        usePretuned: Bool = false
    ) -> [String] {
        var args = [
            "conda", "run", "-n", condaEnvironment,
            "python3", Paths.setupScript,
            "-md", modelDir,
            "-q", quantization,
        ]
        if usePretuned {
            args.append("-p")
        }
        return args
    }

    /// Build shell args for download + build in one step via conda shell hook.
    /// Uses `/bin/zsh -lc` with `conda shell.zsh hook` + `conda activate` so that
    /// the full conda environment is available (unlike `conda run` which has issues).
    public static func buildDownloadAndBuildShellArgs(
        repo: String,
        modelDir: String,
        quantization: String = "i2_s"
    ) -> [String] {
        // Find conda binary path (check common locations)
        let condaPaths = [
            NSHomeDirectory() + "/miniforge3/bin/conda",
            NSHomeDirectory() + "/miniconda3/bin/conda",
            NSHomeDirectory() + "/anaconda3/bin/conda",
            "/opt/homebrew/bin/conda",
        ]
        let condaBin = condaPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            ?? "conda"

        let shellCommand = """
        eval "$(\(condaBin) shell.zsh hook)" && \
        conda activate \(condaEnvironment) && \
        cd \(Paths.home) && \
        huggingface-cli download \(repo) --local-dir \(modelDir) && \
        python \(Paths.setupScript) -md \(modelDir) -q \(quantization)
        """
        return ["/bin/zsh", "-lc", shellCommand]
    }

    /// Build arguments to run setup_env.py with a HuggingFace repo (downloads + compiles).
    /// This is the recommended approach: `-hr` lets setup_env.py handle download + conversion.
    public static func buildSetupFromRepoArgs(
        repo: String,
        quantization: String = "i2_s",
        usePretuned: Bool = true
    ) -> [String] {
        var args = [
            "conda", "run", "-n", condaEnvironment,
            "python3", Paths.setupScript,
            "-hr", repo,
            "-q", quantization,
        ]
        if usePretuned {
            args.append("-p")
        }
        return args
    }

    /// Build arguments to create the conda environment.
    public static func buildCondaCreateArgs() -> [String] {
        ["conda", "create", "-n", condaEnvironment, "python=\(pythonVersion)", "-y"]
    }

    /// Build arguments to install Python dependencies.
    public static func buildPipInstallArgs() -> [String] {
        [
            "conda", "run", "-n", condaEnvironment,
            "pip", "install", "-r", Paths.requirements,
        ]
    }

    /// Build arguments to install HuggingFace CLI in the conda environment.
    /// Required by setup_env.py for model downloads (`huggingface-cli download`).
    /// Pinned to <1.0 for compatibility with transformers (requires huggingface-hub<1.0).
    public static func buildHfCliInstallArgs() -> [String] {
        [
            "conda", "run", "-n", condaEnvironment,
            "pip", "install", "-U", "huggingface_hub[cli]<1.0",
        ]
    }

    /// Build arguments for the inference CLI (non-server, single-shot).
    public static func buildInferenceArgs(
        modelPath: String,
        prompt: String,
        threads: Int? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) -> [String] {
        var args = [
            "conda", "run", "-n", condaEnvironment,
            "python3", Paths.inferenceScript,
            "-m", modelPath,
            "-p", prompt,
        ]
        if let threads {
            args += ["-t", String(threads)]
        }
        if let maxTokens {
            args += ["-n", String(maxTokens)]
        }
        if let temperature {
            args += ["-temp", String(temperature)]
        }
        return args
    }

    // MARK: - Response Parsing

    /// Parse a plain text response line from BitNet output.
    /// BitNet outputs plain text (no structured JSON), so we treat each line as text.
    public static func parseResponseLine(_ line: String) -> ResponseEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .empty
        }
        // Detect prompt marker (end of response in interactive mode)
        if trimmed.hasSuffix("> ") || trimmed == ">" {
            return .promptMarker
        }
        return .text(trimmed)
    }

    /// Events from parsing BitNet output.
    public enum ResponseEvent: Sendable, Equatable {
        case text(String)
        case promptMarker
        case empty
    }

    // MARK: - Install Manifest

    /// Tracks what McClaw installed so it can cleanly uninstall only what it owns.
    public struct InstallManifest: Codable, Sendable, Equatable {
        public var installedAt: Date
        public var prerequisites: [String: PrerequisiteRecord]
        public var components: ComponentsRecord

        public init(
            installedAt: Date = Date(),
            prerequisites: [String: PrerequisiteRecord] = [:],
            components: ComponentsRecord = ComponentsRecord()
        ) {
            self.installedAt = installedAt
            self.prerequisites = prerequisites
            self.components = components
        }

        /// Record whether a prerequisite was already present or installed by McClaw.
        public struct PrerequisiteRecord: Codable, Sendable, Equatable {
            public var wasPresent: Bool
            public var installedByMcClaw: Bool
            public var version: String?
            public var installMethod: String?

            public init(wasPresent: Bool, installedByMcClaw: Bool, version: String? = nil, installMethod: String? = nil) {
                self.wasPresent = wasPresent
                self.installedByMcClaw = installedByMcClaw
                self.version = version
                self.installMethod = installMethod
            }
        }

        /// Components that McClaw always owns (repo, env, models).
        public struct ComponentsRecord: Codable, Sendable, Equatable {
            public var repositoryInstalled: Bool
            public var condaEnvCreated: Bool
            public var installedModels: [String]

            public init(repositoryInstalled: Bool = false, condaEnvCreated: Bool = false, installedModels: [String] = []) {
                self.repositoryInstalled = repositoryInstalled
                self.condaEnvCreated = condaEnvCreated
                self.installedModels = installedModels
            }
        }

        /// Record a prerequisite check result.
        public mutating func recordPrerequisite(
            name: String,
            wasPresent: Bool,
            installedByMcClaw: Bool,
            version: String? = nil,
            installMethod: String? = nil
        ) {
            prerequisites[name] = PrerequisiteRecord(
                wasPresent: wasPresent,
                installedByMcClaw: installedByMcClaw,
                version: version,
                installMethod: installMethod
            )
        }

        /// Add a model to the installed list.
        public mutating func addModel(_ modelId: String) {
            if !components.installedModels.contains(modelId) {
                components.installedModels.append(modelId)
            }
        }

        /// Remove a model from the installed list.
        public mutating func removeModel(_ modelId: String) {
            components.installedModels.removeAll { $0 == modelId }
        }

        /// Get prerequisites that McClaw installed (candidates for uninstall).
        public var mcclawInstalledPrerequisites: [(name: String, record: PrerequisiteRecord)] {
            prerequisites
                .filter { $0.value.installedByMcClaw }
                .map { (name: $0.key, record: $0.value) }
                .sorted { $0.name < $1.name }
        }

        // MARK: - Persistence

        /// Load manifest from disk.
        public static func load() -> InstallManifest? {
            let path = Paths.manifestFile
            guard let data = FileManager.default.contents(atPath: path) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(InstallManifest.self, from: data)
        }

        /// Save manifest to disk.
        public func save() throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(self)

            let dir = (Paths.manifestFile as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: Paths.manifestFile))
        }

        /// Delete manifest from disk.
        public static func delete() {
            try? FileManager.default.removeItem(atPath: Paths.manifestFile)
        }
    }

    // MARK: - Installed Models Discovery

    /// List model IDs that are currently downloaded in the models directory.
    public static func listInstalledModels() -> [String] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: Paths.modelsDir) else {
            return []
        }
        return dirs.filter { dir in
            let path = Paths.modelsDir + "/\(dir)"
            var isDir: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted()
    }

    /// Check if BitNet is installed (basic check: directory + inference script exist).
    public static var isInstalled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: Paths.home) && (
            fm.fileExists(atPath: Paths.serverScript) ||
            fm.fileExists(atPath: Paths.inferenceScript)
        )
    }

    // MARK: - Uninstall Commands

    /// Build the command to remove the conda environment.
    public static func buildCondaRemoveArgs() -> [String] {
        ["conda", "env", "remove", "-n", condaEnvironment, "-y"]
    }

    /// Build the brew uninstall command for a prerequisite.
    public static func buildBrewUninstallArgs(formula: String) -> [String] {
        ["brew", "uninstall", formula]
    }

    /// Extract the brew formula from an install method string like "brew install cmake".
    public static func brewFormula(from installMethod: String) -> String? {
        let parts = installMethod.split(separator: " ")
        guard parts.count >= 3, parts[0] == "brew", parts[1] == "install" else {
            return nil
        }
        return String(parts[2])
    }
}
