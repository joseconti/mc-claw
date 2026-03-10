# McClaw - BitNet CLI Provider (Experimental)

## 1. Overview

BitNet is an open-source inference framework by Microsoft for 1-bit Large Language Models (1.58-bit LLMs). Unlike traditional models that use 16/32-bit weights, BitNet models restrict all weights to ternary values {-1, 0, +1}, enabling dramatically more efficient inference on CPUs.

McClaw integrates BitNet as an **experimental CLI provider**, allowing users to download and run ultra-efficient local models directly from the McClaw interface. BitNet complements the existing Ollama provider: while Ollama runs standard quantized models, BitNet runs natively ternary models that are significantly more efficient in memory and energy consumption.

```
McClaw CLI Bridge
    |
    +---> claude (Anthropic CLI)
    +---> chatgpt (OpenAI CLI)
    +---> gemini (Google CLI)
    +---> ollama (local, standard quantization)
    +---> bitnet (local, 1.58-bit native)    <-- NEW
```

**Status**: Experimental

---

## 2. System Requirements

BitNet has heavier installation requirements than other CLI providers. McClaw must verify these prerequisites before attempting installation.

| Requirement | Minimum | Detection Command |
|---|---|---|
| Python | 3.9+ | `python3 --version` |
| Conda | Any | `conda --version` |
| CMake | 3.22+ | `cmake --version` |
| Clang | 18+ | `clang --version` |
| Git | Any | `git --version` |
| Disk space | ~5 GB (framework + models) | `df -h` |

### 2.1 macOS-Specific Notes

- Works on both Apple Silicon (ARM) and Intel (x86) Macs
- ARM Macs use `TL1` and `I2_S` quantization kernels
- x86 Macs use `TL2` and `I2_S` quantization kernels (benefit from AVX2/AVX-512)
- Clang 18+ is required; macOS default clang may not suffice. Install via Homebrew: `brew install llvm@18`

---

## 3. Installation Flow

BitNet installation is multi-step and more complex than other providers. McClaw handles this through a guided, phased installation process.

### 3.1 Installation Phases

```
Phase 1: Prerequisites Check
    |
    v
Phase 2: Clone Repository
    |
    v
Phase 3: Create Conda Environment
    |
    v
Phase 4: Install Python Dependencies
    |
    v
Phase 5: Download Default Model
    |
    v
Phase 6: Build (setup_env.py)
    |
    v
Phase 7: Verification
```

### 3.2 Installation Commands (Sequential)

```bash
# Phase 1: Prerequisites (McClaw verifies silently)
python3 --version        # >= 3.9
conda --version          # must exist
cmake --version          # >= 3.22
clang --version          # >= 18
git --version            # must exist

# Phase 2: Clone repository
git clone --recursive https://github.com/microsoft/BitNet.git ~/.mcclaw/bitnet

# Phase 3: Create conda environment
conda create -n mcclaw-bitnet python=3.9 -y

# Phase 4: Install dependencies
conda run -n mcclaw-bitnet pip install -r ~/.mcclaw/bitnet/requirements.txt

# Phase 5: Download default model (BitNet-b1.58-2B-4T)
conda run -n mcclaw-bitnet huggingface-cli download microsoft/BitNet-b1.58-2B-4T-gguf \
    --local-dir ~/.mcclaw/bitnet/models/BitNet-b1.58-2B-4T

# Phase 6: Build with setup_env.py (compiles llama.cpp kernels for the model)
cd ~/.mcclaw/bitnet
conda run -n mcclaw-bitnet python setup_env.py \
    -md models/BitNet-b1.58-2B-4T \
    -q i2_s

# Phase 7: Verify binary exists
ls ~/.mcclaw/bitnet/build/bin/llama-cli   # or equivalent built binary
```

### 3.3 Installation Directory Structure

```
~/.mcclaw/
    bitnet/
        BitNet/                    # Cloned repository
            build/
                bin/
                    llama-cli      # Compiled inference binary
            models/
                BitNet-b1.58-2B-4T/
                    ggml-model-i2_s.gguf
                bitnet_b1_58-large/
                    ...
            run_inference.py
            setup_env.py
            requirements.txt
```

### 3.4 UI During Installation

McClaw shows a dedicated installation panel with:

```
+--------------------------------------------------+
|  BitNet Installation (Experimental)              |
|                                                  |
|  Prerequisites:                                  |
|    [OK] Python 3.11                              |
|    [OK] Conda 24.1                               |
|    [OK] CMake 3.28                               |
|    [!!] Clang 15 (need 18+)                      |
|         [Install clang 18 via Homebrew]          |
|    [OK] Git 2.43                                 |
|                                                  |
|  Installation Progress:                          |
|    [====] Clone repository        Done           |
|    [====] Create environment      Done           |
|    [==  ] Install dependencies    48%            |
|    [    ] Download model          Pending        |
|    [    ] Build                   Pending        |
|    [    ] Verify                  Pending        |
|                                                  |
|  Estimated time: ~10-15 minutes                  |
|  [Cancel]                                        |
+--------------------------------------------------+
```

### 3.5 CLIInstallMethod

BitNet requires a new install method type to handle the multi-phase process:

```swift
enum CLIInstallMethod {
    case homebrew(formula: String)
    case npm(package: String)
    case curl(url: URL)
    case appStore(bundleId: String)
    case manual(instructions: String)
    case multiStep(steps: [InstallStep])   // NEW - for BitNet and similar
}

struct InstallStep: Sendable {
    let id: String
    let description: String
    let command: [String]
    let workingDirectory: String?
    let condaEnvironment: String?       // Run inside conda env
    let estimatedDuration: TimeInterval
    let canRetry: Bool
    let skipCondition: (() async -> Bool)?  // Skip if already done
}
```

---

## 4. BitNet CLI Provider

### 4.1 Provider Implementation

```swift
struct BitNetCLIProvider: CLIProvider {
    let id = "bitnet"
    let displayName = "BitNet (Microsoft, Local)"
    let binaryName = "llama-cli"   // Built binary name
    let isExperimental = true

    let installMethods: [CLIInstallMethod] = [
        .multiStep(steps: BitNetInstaller.installSteps)
    ]

    // Detection
    let versionCommand = ["python3", "~/.mcclaw/bitnet/run_inference.py", "--help"]
    let authCheckCommand: [String]? = nil  // No auth needed (local)

    // Capabilities
    let supportsStreaming = false          // Not confirmed in BitNet
    let supportsInteractiveMode = true     // -cnv flag
    let supportsToolUse = false
    let supportsVision = false
    let supportsThinking = false

    // Models (dynamic, based on downloaded models)
    let defaultModel = "BitNet-b1.58-2B-4T"
    var availableModels: [String] {
        get async { await listDownloadedModels() }
    }

    // Command building
    func buildChatCommand(message: String, options: ChatOptions) -> [String] {
        let modelPath = resolveModelPath(options.model ?? defaultModel)
        var args = [
            "conda", "run", "-n", "mcclaw-bitnet", "--no-banner",
            "python3", bitnetPath("run_inference.py"),
            "-m", modelPath,
            "-p", message,
            "-cnv"
        ]
        if let threads = options.threads {
            args += ["-t", String(threads)]
        }
        if let maxTokens = options.maxTokens {
            args += ["-n", String(maxTokens)]
        }
        if let temperature = options.temperature {
            args += ["-temp", String(temperature)]
        }
        return args
    }

    // Output parsing
    func parseStreamLine(_ line: String) -> CLIStreamEvent {
        // BitNet outputs plain text (no structured JSON stream)
        // Parse line-by-line as text chunks
        if line.isEmpty { return .done }
        return .text(line)
    }

    func parseOutput(data: Data) -> CLIResponse {
        let text = String(data: data, encoding: .utf8) ?? ""
        return CLIResponse(
            text: text,
            provider: id,
            model: defaultModel,
            usage: nil,
            toolCalls: nil,
            exitCode: 0,
            duration: 0
        )
    }

    // Environment
    func environmentOverrides() -> [String: String] {
        return [
            "BITNET_HOME": NSString("~/.mcclaw/bitnet").expandingTildeInPath
        ]
    }
}
```

### 4.2 Model Path Resolution

```swift
extension BitNetCLIProvider {
    private func bitnetPath(_ relative: String) -> String {
        let home = NSString("~/.mcclaw/bitnet").expandingTildeInPath
        return "\(home)/\(relative)"
    }

    private func resolveModelPath(_ modelName: String) -> String {
        let modelsDir = bitnetPath("models/\(modelName)")
        // Find the .gguf file inside the model directory
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: modelsDir) {
            if let gguf = contents.first(where: { $0.hasSuffix(".gguf") }) {
                return "\(modelsDir)/\(gguf)"
            }
        }
        return "\(modelsDir)/ggml-model-i2_s.gguf"
    }

    func listDownloadedModels() async -> [String] {
        let modelsDir = bitnetPath("models")
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: modelsDir) else {
            return []
        }
        return dirs.filter { dir in
            let path = "\(modelsDir)/\(dir)"
            var isDir: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &isDir)
            return isDir.boolValue
        }
    }
}
```

---

## 5. Model Management

### 5.1 Available Models Registry

McClaw maintains a registry of known BitNet-compatible models that can be downloaded:

```swift
struct BitNetModelInfo: Sendable, Codable {
    let id: String
    let displayName: String
    let huggingFaceRepo: String
    let parameters: String          // "2.4B", "0.7B", etc.
    let sizeOnDisk: String          // Approximate download size
    let quantizationTypes: [String] // ["i2_s", "tl1", "tl2"]
    let isDefault: Bool
    let description: String
}

let bitnetModelRegistry: [BitNetModelInfo] = [
    BitNetModelInfo(
        id: "BitNet-b1.58-2B-4T",
        displayName: "BitNet 2B (Official)",
        huggingFaceRepo: "microsoft/BitNet-b1.58-2B-4T-gguf",
        parameters: "2.4B",
        sizeOnDisk: "~500 MB",
        quantizationTypes: ["i2_s"],
        isDefault: true,
        description: "Official Microsoft 1-bit LLM. 2.4B parameters trained on 4T tokens."
    ),
    BitNetModelInfo(
        id: "bitnet_b1_58-large",
        displayName: "BitNet Large (0.7B)",
        huggingFaceRepo: "1bitLLM/bitnet_b1_58-large",
        parameters: "0.7B",
        sizeOnDisk: "~200 MB",
        quantizationTypes: ["i2_s"],
        isDefault: false,
        description: "Smaller 1-bit model. Fast inference, lower quality."
    ),
    BitNetModelInfo(
        id: "bitnet_b1_58-3B",
        displayName: "BitNet 3B",
        huggingFaceRepo: "1bitLLM/bitnet_b1_58-3B",
        parameters: "3.3B",
        sizeOnDisk: "~700 MB",
        quantizationTypes: ["i2_s"],
        isDefault: false,
        description: "3.3B parameter 1-bit model."
    ),
    BitNetModelInfo(
        id: "Llama3-8B-1.58-100B-tokens",
        displayName: "Llama3 8B (1-bit)",
        huggingFaceRepo: "HF1BitLLM/Llama3-8B-1.58-100B-tokens",
        parameters: "8.0B",
        sizeOnDisk: "~1.5 GB",
        quantizationTypes: ["i2_s"],
        isDefault: false,
        description: "Llama3 8B architecture trained with 1-bit weights."
    )
]
```

### 5.2 Model Download Flow

```
User clicks [Download Model] in BitNet settings
    |
    v
McClaw shows model browser (from registry)
    |
    v
User selects a model
    |
    v
1. huggingface-cli download <repo> --local-dir ~/.mcclaw/bitnet/models/<id>
    |  (show progress bar)
    v
2. python setup_env.py -md models/<id> -q i2_s
    |  (compile kernels for this model)
    v
3. Verify .gguf file exists
    |
    v
Model available in provider's model list
```

### 5.3 Model Download Command

```bash
# Download
conda run -n mcclaw-bitnet huggingface-cli download <huggingFaceRepo> \
    --local-dir ~/.mcclaw/bitnet/models/<modelId>

# Build for the model (required per model)
cd ~/.mcclaw/bitnet
conda run -n mcclaw-bitnet python setup_env.py \
    -md models/<modelId> \
    -q i2_s
```

### 5.4 Model Management UI

```
+--------------------------------------------------+
|  BitNet Models (Experimental)                    |
|                                                  |
|  Installed:                                      |
|    BitNet 2B (Official) - 2.4B params            |
|      Path: ~/.mcclaw/bitnet/models/...           |
|      Size: 487 MB                                |
|      [Set as Default] [Delete]                   |
|                                                  |
|  Available to Download:                          |
|    BitNet Large (0.7B)      ~200 MB [Download]   |
|    BitNet 3B                ~700 MB [Download]   |
|    Llama3 8B (1-bit)        ~1.5 GB [Download]   |
|                                                  |
|  [Refresh Registry]                              |
+--------------------------------------------------+
```

---

## 6. Detection and Status

### 6.1 Detection Flow

BitNet detection is different from other providers since there is no single system binary. McClaw checks the installation directory:

```swift
extension BitNetCLIProvider {
    func detect() async -> CLIStatus {
        let bitnetHome = NSString("~/.mcclaw/bitnet").expandingTildeInPath
        let fm = FileManager.default

        // 1. Check if BitNet directory exists
        guard fm.fileExists(atPath: bitnetHome) else {
            return .notInstalled
        }

        // 2. Check if conda environment exists
        let condaCheck = try? await Process.run([
            "conda", "env", "list"
        ])
        guard let envList = condaCheck,
              envList.contains("mcclaw-bitnet") else {
            return .error("Conda environment 'mcclaw-bitnet' not found")
        }

        // 3. Check if run_inference.py exists
        guard fm.fileExists(atPath: "\(bitnetHome)/run_inference.py") else {
            return .error("run_inference.py not found")
        }

        // 4. Check if at least one model is downloaded
        let models = await listDownloadedModels()
        guard !models.isEmpty else {
            return .installedNotAuth(version: "no models")
        }

        // 5. Check if build exists for any model
        let buildBinary = "\(bitnetHome)/build/bin/llama-cli"
        guard fm.fileExists(atPath: buildBinary) else {
            return .error("BitNet not compiled. Run setup_env.py.")
        }

        return .installed(
            version: "1.58-bit",
            authenticated: true  // No auth needed for local
        )
    }
}
```

### 6.2 Connection Screen Entry

```
+------------------------------------------+
|  Detected AI CLIs                        |
|                                          |
|  [x] Claude CLI v1.2.3                   |
|      Status: Authenticated               |
|                                          |
|  [x] Ollama v0.5.1                       |
|      Status: Service active              |
|      Models: llama3, codestral           |
|                                          |
|  [x] BitNet (Experimental)               |  <-- NEW
|      Status: Ready                       |
|      Models: BitNet-b1.58-2B-4T          |
|      [Manage Models]                     |
|                                          |
|  -- OR if not installed --               |
|                                          |
|  [ ] BitNet (Experimental)               |
|      Status: Not installed               |
|      Requires: Python 3.9+, Conda,      |
|        CMake 3.22+, Clang 18+           |
|      [Install BitNet] (~10-15 min)       |
|                                          |
+------------------------------------------+
```

---

## 7. Chat Execution

### 7.1 Conversation Mode

BitNet's `-cnv` flag enables an interactive conversation mode where the `-p` parameter becomes the system prompt. McClaw uses this mode for chat interaction:

```
McClaw sends message:
    |
    v
conda run -n mcclaw-bitnet python3 run_inference.py \
    -m ~/.mcclaw/bitnet/models/BitNet-b1.58-2B-4T/ggml-model-i2_s.gguf \
    -p "You are a helpful assistant" \
    -cnv \
    -t 4 \
    -n 2048
    |
    v
Process stdin receives user message
    |
    v
Process stdout produces response text
    |
    v
McClaw reads stdout line-by-line and displays in chat
```

### 7.2 Session Management

Since BitNet runs in conversation mode as a persistent process, McClaw must manage the process lifecycle:

```swift
actor BitNetSessionManager {
    private var activeProcess: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?

    // Start a new conversation session
    func startSession(model: String, systemPrompt: String) async throws {
        let provider = BitNetCLIProvider()
        let modelPath = provider.resolveModelPath(model)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "conda", "run", "-n", "mcclaw-bitnet", "--no-banner",
            "python3", provider.bitnetPath("run_inference.py"),
            "-m", modelPath,
            "-p", systemPrompt,
            "-cnv"
        ]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdinPipe = stdin
        stdoutPipe = stdout
        activeProcess = process

        try process.run()
    }

    // Send a message within the session
    func send(message: String) async throws -> AsyncStream<String> {
        guard let stdin = stdinPipe,
              let stdout = stdoutPipe else {
            throw CLIBridgeError.cliNotFound("bitnet")
        }

        // Write message to stdin
        let messageData = (message + "\n").data(using: .utf8)!
        stdin.fileHandleForWriting.write(messageData)

        // Read response from stdout
        return AsyncStream { continuation in
            Task {
                for try await line in stdout.fileHandleForReading.bytes.lines {
                    // Detect end-of-response marker
                    if line.contains("> ") || line.isEmpty {
                        continuation.finish()
                        return
                    }
                    continuation.yield(line)
                }
                continuation.finish()
            }
        }
    }

    // End the session
    func endSession() async {
        activeProcess?.interrupt()
        try? await Task.sleep(for: .seconds(1))
        if activeProcess?.isRunning == true {
            activeProcess?.terminate()
        }
        activeProcess = nil
        stdinPipe = nil
        stdoutPipe = nil
    }
}
```

---

## 8. Configuration

### 8.1 mcclaw.json Entry

```json
{
    "cli": {
        "providers": {
            "bitnet": {
                "enabled": true,
                "installPath": "~/.mcclaw/bitnet",
                "condaEnv": "mcclaw-bitnet",
                "defaultModel": "BitNet-b1.58-2B-4T",
                "defaultQuantization": "i2_s",
                "threads": 4,
                "contextSize": 2048,
                "maxTokens": 2048,
                "temperature": 0.7,
                "timeout": 120,
                "experimental": true
            }
        }
    }
}
```

### 8.2 Settings Panel

BitNet has its own section within Settings > CLIs, marked with an experimental badge:

```
+--------------------------------------------------+
|  BitNet Settings [EXPERIMENTAL]                  |
|                                                  |
|  Installation Path:                              |
|    ~/.mcclaw/bitnet                              |
|                                                  |
|  Conda Environment: mcclaw-bitnet                |
|                                                  |
|  Default Model: [BitNet-b1.58-2B-4T  v]         |
|                                                  |
|  Inference Settings:                             |
|    Threads:      [4      ]  (auto: 8 available)  |
|    Context Size: [2048   ]  tokens               |
|    Max Tokens:   [2048   ]  tokens               |
|    Temperature:  [0.7    ]                       |
|                                                  |
|  [Manage Models]                                 |
|  [Reinstall BitNet]                              |
|  [Uninstall BitNet]                              |
|                                                  |
|  Disk Usage: 1.2 GB (framework + models)         |
+--------------------------------------------------+
```

---

## 9. Uninstallation

McClaw provides a clean uninstall option:

```bash
# Remove conda environment
conda env remove -n mcclaw-bitnet -y

# Remove BitNet directory
rm -rf ~/.mcclaw/bitnet
```

---

## 10. Fallback Integration

BitNet is included in the fallback chain but with low priority (it is a local, limited model):

```json
{
    "cli": {
        "fallbackOrder": ["claude", "chatgpt", "gemini", "ollama", "bitnet"]
    }
}
```

BitNet should only be used as fallback when no other provider is available, since its model capabilities are more limited than cloud providers.

---

## 11. Limitations and Known Issues

### Current Limitations

1. **Limited model ecosystem**: Only a handful of 1-bit models exist today (vs. hundreds for Ollama)
2. **No streaming confirmation**: BitNet's streaming behavior is not documented; McClaw reads stdout line-by-line as best-effort streaming
3. **No tool use**: BitNet models do not support function calling or tool use
4. **No vision**: No multimodal support in current BitNet models
5. **Complex installation**: Requires conda, cmake, clang 18+ (much heavier than `brew install ollama`)
6. **Build per model**: Each new model requires running `setup_env.py` again to compile optimized kernels
7. **No usage metrics**: BitNet does not report token counts or cost (local, free)
8. **Interactive mode parsing**: The end-of-response detection in conversation mode may need refinement based on actual output format testing

### Experimental Status Implications

- Marked with `[EXPERIMENTAL]` badge throughout the UI
- Not included as default provider suggestion during onboarding
- Hidden behind "Show experimental providers" toggle in Settings
- May be removed or significantly changed in future versions
- Users see a one-time disclaimer when enabling:

```
BitNet is an experimental provider. It requires additional
software (Conda, CMake, Clang 18+) and installation takes
approximately 10-15 minutes. Model capabilities are more
limited than cloud providers.

[Enable BitNet]  [Not Now]
```

---

## 12. Future Considerations

1. **run_inference_server.py**: BitNet includes a REST API server script. A future version could use this instead of the CLI approach, enabling proper streaming and better session management.
2. **Model registry updates**: As the 1-bit model ecosystem grows, McClaw could fetch an updated model registry from a remote source.
3. **Automatic prerequisite installation**: McClaw could offer to install missing prerequisites (conda, cmake, clang) via Homebrew before starting BitNet installation.
4. **GPU support**: BitNet has experimental NVIDIA GPU support. Future versions could detect GPU availability and enable GPU inference.
5. **Promotion from experimental**: Once the ecosystem matures and the output parsing is stable, BitNet could be promoted to a standard provider.
