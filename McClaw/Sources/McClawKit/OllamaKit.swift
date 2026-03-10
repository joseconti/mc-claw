import Foundation

/// Pure logic helpers for Ollama provider, extracted for testability.
/// Handles model catalog, hardware detection, recommendations, and output parsing.
public enum OllamaKit {

    // MARK: - Server Status

    /// Possible states for the Ollama server.
    public enum ServerStatus: String, Sendable {
        case running
        case stopped
        case unknown
    }

    // MARK: - Model Categories

    /// Size category for Ollama models based on parameter count.
    public enum ModelSizeCategory: String, Sendable, CaseIterable {
        case small      // 1-3B params, ~8GB RAM
        case medium     // 3-8B params, ~16GB RAM
        case large      // 8-14B params, ~32GB RAM
        case veryLarge  // 14B+ params, ~64GB RAM
    }

    /// Use-case group for organizing models by specialty.
    public enum ModelGroup: String, Sendable, CaseIterable, Identifiable {
        case reasoning    // Chain-of-thought, math, logic, analysis
        case coding       // Code generation, debugging, refactoring
        case general      // General purpose conversation and writing
        case creative     // Creative writing, translation, summarization
        case multimodal   // Vision + text models

        public var id: String { rawValue }

        /// Display name for the group.
        public var displayName: String {
            switch self {
            case .reasoning: "Reasoning"
            case .coding: "Coding"
            case .general: "General Purpose"
            case .creative: "Creative & Writing"
            case .multimodal: "Multimodal (Vision)"
            }
        }

        /// SF Symbol icon for the group.
        public var icon: String {
            switch self {
            case .reasoning: "brain.head.profile"
            case .coding: "chevron.left.forwardslash.chevron.right"
            case .general: "bubble.left.and.text.bubble.right"
            case .creative: "pencil.and.outline"
            case .multimodal: "eye"
            }
        }

        /// Short description of what this group excels at.
        public var groupDescription: String {
            switch self {
            case .reasoning: "Complex analysis, math, logic, step-by-step problem solving"
            case .coding: "Code generation, debugging, refactoring, code review"
            case .general: "Chat, Q&A, text generation, everyday tasks"
            case .creative: "Creative writing, translation, summarization, content"
            case .multimodal: "Image understanding, visual Q&A, document analysis"
            }
        }
    }

    // MARK: - Model Catalog

    /// Information about a known Ollama model available for download.
    public struct OllamaModelInfo: Sendable, Equatable, Identifiable {
        public var id: String { modelId }
        public let modelId: String
        public let displayName: String
        public let parameterSize: String
        public let parameterCount: Double
        public let sizeCategory: ModelSizeCategory
        public let group: ModelGroup
        /// Quality rank within the group (1 = best). Used to sort models best-to-worst.
        public let qualityRank: Int
        public let minimumRAMGB: Int
        public let description: String

        public init(
            modelId: String,
            displayName: String,
            parameterSize: String,
            parameterCount: Double,
            sizeCategory: ModelSizeCategory,
            group: ModelGroup,
            qualityRank: Int,
            minimumRAMGB: Int,
            description: String
        ) {
            self.modelId = modelId
            self.displayName = displayName
            self.parameterSize = parameterSize
            self.parameterCount = parameterCount
            self.sizeCategory = sizeCategory
            self.group = group
            self.qualityRank = qualityRank
            self.minimumRAMGB = minimumRAMGB
            self.description = description
        }
    }

    /// Curated catalog of popular Ollama models, organized by use-case group
    /// and ranked best-to-worst within each group.
    public static let modelCatalog: [OllamaModelInfo] = [

        // =====================================================================
        // MARK: Reasoning — Chain-of-thought, math, logic, analysis
        // Ordered best to worst
        // =====================================================================
        OllamaModelInfo(
            modelId: "deepseek-r1:70b",
            displayName: "DeepSeek R1 70B",
            parameterSize: "70B",
            parameterCount: 70.0,
            sizeCategory: .veryLarge,
            group: .reasoning,
            qualityRank: 1,
            minimumRAMGB: 64,
            description: "Best open reasoning model. Rivals frontier models on math and logic."
        ),
        OllamaModelInfo(
            modelId: "qwq",
            displayName: "QwQ 32B",
            parameterSize: "32B",
            parameterCount: 32.0,
            sizeCategory: .veryLarge,
            group: .reasoning,
            qualityRank: 2,
            minimumRAMGB: 64,
            description: "Alibaba's reasoning model. Excellent at math and analytical tasks."
        ),
        OllamaModelInfo(
            modelId: "deepseek-r1:32b",
            displayName: "DeepSeek R1 32B",
            parameterSize: "32B",
            parameterCount: 32.0,
            sizeCategory: .large,
            group: .reasoning,
            qualityRank: 3,
            minimumRAMGB: 32,
            description: "Strong reasoning with chain-of-thought. Great quality/size balance."
        ),
        OllamaModelInfo(
            modelId: "phi4",
            displayName: "Phi-4 14B",
            parameterSize: "14B",
            parameterCount: 14.0,
            sizeCategory: .medium,
            group: .reasoning,
            qualityRank: 4,
            minimumRAMGB: 16,
            description: "Microsoft's reasoning model. Punches above its weight on math."
        ),
        OllamaModelInfo(
            modelId: "deepseek-r1:14b",
            displayName: "DeepSeek R1 14B",
            parameterSize: "14B",
            parameterCount: 14.0,
            sizeCategory: .medium,
            group: .reasoning,
            qualityRank: 5,
            minimumRAMGB: 16,
            description: "Compact reasoning model. Good chain-of-thought on 16GB Macs."
        ),
        OllamaModelInfo(
            modelId: "phi4-mini",
            displayName: "Phi-4 Mini",
            parameterSize: "3.8B",
            parameterCount: 3.8,
            sizeCategory: .small,
            group: .reasoning,
            qualityRank: 6,
            minimumRAMGB: 8,
            description: "Smallest reasoning model. Surprisingly capable for 8GB Macs."
        ),

        // =====================================================================
        // MARK: Coding — Code generation, debugging, refactoring
        // Ordered best to worst
        // =====================================================================
        OllamaModelInfo(
            modelId: "qwen2.5-coder:32b",
            displayName: "Qwen 2.5 Coder 32B",
            parameterSize: "32B",
            parameterCount: 32.0,
            sizeCategory: .veryLarge,
            group: .coding,
            qualityRank: 1,
            minimumRAMGB: 64,
            description: "Best open coding model. Excels at generation, review, and refactoring."
        ),
        OllamaModelInfo(
            modelId: "codestral",
            displayName: "Codestral 22B",
            parameterSize: "22B",
            parameterCount: 22.0,
            sizeCategory: .large,
            group: .coding,
            qualityRank: 2,
            minimumRAMGB: 32,
            description: "Mistral's code specialist. Great for multi-file edits and debugging."
        ),
        OllamaModelInfo(
            modelId: "devstral",
            displayName: "Devstral 24B",
            parameterSize: "24B",
            parameterCount: 24.0,
            sizeCategory: .large,
            group: .coding,
            qualityRank: 3,
            minimumRAMGB: 32,
            description: "Mistral's agentic coding model. Optimized for code agents and tools."
        ),
        OllamaModelInfo(
            modelId: "qwen2.5-coder:7b",
            displayName: "Qwen 2.5 Coder 7B",
            parameterSize: "7B",
            parameterCount: 7.0,
            sizeCategory: .medium,
            group: .coding,
            qualityRank: 4,
            minimumRAMGB: 16,
            description: "Solid coding model for 16GB Macs. Fast completions and generation."
        ),
        OllamaModelInfo(
            modelId: "codegemma:7b",
            displayName: "CodeGemma 7B",
            parameterSize: "7B",
            parameterCount: 7.0,
            sizeCategory: .medium,
            group: .coding,
            qualityRank: 5,
            minimumRAMGB: 16,
            description: "Google's code model. Good at infill and code completion."
        ),
        OllamaModelInfo(
            modelId: "qwen2.5-coder:1.5b",
            displayName: "Qwen 2.5 Coder 1.5B",
            parameterSize: "1.5B",
            parameterCount: 1.5,
            sizeCategory: .small,
            group: .coding,
            qualityRank: 6,
            minimumRAMGB: 8,
            description: "Ultra-fast code completions. Best coding model for 8GB Macs."
        ),

        // =====================================================================
        // MARK: General Purpose — Chat, Q&A, everyday tasks
        // Ordered best to worst
        // =====================================================================
        OllamaModelInfo(
            modelId: "qwen2.5:72b",
            displayName: "Qwen 2.5 72B",
            parameterSize: "72B",
            parameterCount: 72.0,
            sizeCategory: .veryLarge,
            group: .general,
            qualityRank: 1,
            minimumRAMGB: 64,
            description: "One of the best open models. Near-frontier quality across all tasks."
        ),
        OllamaModelInfo(
            modelId: "llama3.3",
            displayName: "Llama 3.3 70B",
            parameterSize: "70B",
            parameterCount: 70.0,
            sizeCategory: .veryLarge,
            group: .general,
            qualityRank: 2,
            minimumRAMGB: 64,
            description: "Meta's flagship. Excellent at conversation, writing, and analysis."
        ),
        OllamaModelInfo(
            modelId: "gemma3:27b",
            displayName: "Gemma 3 27B",
            parameterSize: "27B",
            parameterCount: 27.0,
            sizeCategory: .large,
            group: .general,
            qualityRank: 3,
            minimumRAMGB: 32,
            description: "Google's best Gemma. Outstanding quality for its size."
        ),
        OllamaModelInfo(
            modelId: "command-r",
            displayName: "Command R 35B",
            parameterSize: "35B",
            parameterCount: 35.0,
            sizeCategory: .large,
            group: .general,
            qualityRank: 4,
            minimumRAMGB: 32,
            description: "Cohere's model. Excels at RAG, retrieval, and structured output."
        ),
        OllamaModelInfo(
            modelId: "gemma3:12b",
            displayName: "Gemma 3 12B",
            parameterSize: "12B",
            parameterCount: 12.0,
            sizeCategory: .large,
            group: .general,
            qualityRank: 5,
            minimumRAMGB: 32,
            description: "Google's mid-large model. Great quality with 32GB RAM."
        ),
        OllamaModelInfo(
            modelId: "mistral",
            displayName: "Mistral 7B",
            parameterSize: "7B",
            parameterCount: 7.0,
            sizeCategory: .medium,
            group: .general,
            qualityRank: 6,
            minimumRAMGB: 16,
            description: "Mistral AI's classic. Excellent quality-to-size ratio."
        ),
        OllamaModelInfo(
            modelId: "gemma3:4b",
            displayName: "Gemma 3 4B",
            parameterSize: "4B",
            parameterCount: 4.0,
            sizeCategory: .medium,
            group: .general,
            qualityRank: 7,
            minimumRAMGB: 16,
            description: "Google's efficient model. Good quality on moderate hardware."
        ),
        OllamaModelInfo(
            modelId: "llama3.2:3b",
            displayName: "Llama 3.2 3B",
            parameterSize: "3B",
            parameterCount: 3.0,
            sizeCategory: .small,
            group: .general,
            qualityRank: 8,
            minimumRAMGB: 8,
            description: "Meta's compact model. Best general model for 8GB Macs."
        ),
        OllamaModelInfo(
            modelId: "gemma3:1b",
            displayName: "Gemma 3 1B",
            parameterSize: "1B",
            parameterCount: 1.0,
            sizeCategory: .small,
            group: .general,
            qualityRank: 9,
            minimumRAMGB: 8,
            description: "Fastest model. Simple tasks only, ultra-low resource usage."
        ),

        // =====================================================================
        // MARK: Creative & Writing — Translation, summarization, content
        // Ordered best to worst
        // =====================================================================
        OllamaModelInfo(
            modelId: "command-r-plus",
            displayName: "Command R+ 104B",
            parameterSize: "104B",
            parameterCount: 104.0,
            sizeCategory: .veryLarge,
            group: .creative,
            qualityRank: 1,
            minimumRAMGB: 64,
            description: "Cohere's largest. Outstanding for long-form writing and summarization."
        ),
        OllamaModelInfo(
            modelId: "mistral-nemo",
            displayName: "Mistral Nemo 12B",
            parameterSize: "12B",
            parameterCount: 12.0,
            sizeCategory: .large,
            group: .creative,
            qualityRank: 2,
            minimumRAMGB: 32,
            description: "Strong multilingual model. Excellent for translation and writing."
        ),
        OllamaModelInfo(
            modelId: "llama3.2",
            displayName: "Llama 3.2 3B",
            parameterSize: "3B",
            parameterCount: 3.0,
            sizeCategory: .medium,
            group: .creative,
            qualityRank: 3,
            minimumRAMGB: 16,
            description: "Good for drafting and brainstorming. Fast creative iteration."
        ),
        OllamaModelInfo(
            modelId: "llama3.2:1b",
            displayName: "Llama 3.2 1B",
            parameterSize: "1B",
            parameterCount: 1.0,
            sizeCategory: .small,
            group: .creative,
            qualityRank: 4,
            minimumRAMGB: 8,
            description: "Quick text generation. Basic writing assistance on minimal hardware."
        ),

        // =====================================================================
        // MARK: Multimodal (Vision) — Image understanding, visual Q&A
        // Ordered best to worst
        // =====================================================================
        OllamaModelInfo(
            modelId: "llama3.2-vision:90b",
            displayName: "Llama 3.2 Vision 90B",
            parameterSize: "90B",
            parameterCount: 90.0,
            sizeCategory: .veryLarge,
            group: .multimodal,
            qualityRank: 1,
            minimumRAMGB: 64,
            description: "Best open vision model. Understands images, charts, and documents."
        ),
        OllamaModelInfo(
            modelId: "gemma3:27b",
            displayName: "Gemma 3 27B (Vision)",
            parameterSize: "27B",
            parameterCount: 27.0,
            sizeCategory: .large,
            group: .multimodal,
            qualityRank: 2,
            minimumRAMGB: 32,
            description: "Gemma with vision. Understands images alongside text prompts."
        ),
        OllamaModelInfo(
            modelId: "llava:13b",
            displayName: "LLaVA 13B",
            parameterSize: "13B",
            parameterCount: 13.0,
            sizeCategory: .large,
            group: .multimodal,
            qualityRank: 3,
            minimumRAMGB: 32,
            description: "Visual assistant. Good at describing and analyzing images."
        ),
        OllamaModelInfo(
            modelId: "llama3.2-vision:11b",
            displayName: "Llama 3.2 Vision 11B",
            parameterSize: "11B",
            parameterCount: 11.0,
            sizeCategory: .medium,
            group: .multimodal,
            qualityRank: 4,
            minimumRAMGB: 16,
            description: "Compact vision model. Image understanding on 16GB Macs."
        ),
        OllamaModelInfo(
            modelId: "llava:7b",
            displayName: "LLaVA 7B",
            parameterSize: "7B",
            parameterCount: 7.0,
            sizeCategory: .medium,
            group: .multimodal,
            qualityRank: 5,
            minimumRAMGB: 16,
            description: "Lightweight vision model. Basic image Q&A on moderate hardware."
        ),
    ]

    // MARK: - Model Catalog Helpers

    /// Get all models in a specific group, sorted by quality (best first).
    public static func models(in group: ModelGroup) -> [OllamaModelInfo] {
        modelCatalog
            .filter { $0.group == group }
            .sorted { $0.qualityRank < $1.qualityRank }
    }

    /// Get all groups that have at least one model matching the hardware.
    public static func availableGroups(for hardware: HardwareInfo) -> [ModelGroup] {
        let maxParams = maxRecommendedParams(ramGB: hardware.totalRAMGB, appleSilicon: hardware.isAppleSilicon)
        return ModelGroup.allCases.filter { group in
            modelCatalog.contains { $0.group == group && $0.parameterCount <= maxParams }
        }
    }

    // MARK: - Hardware Detection

    /// Chip family for Apple Silicon or Intel.
    public enum ChipFamily: String, Sendable {
        case m1, m2, m3, m4, intel, unknown
    }

    /// Hardware information for the current Mac.
    public struct HardwareInfo: Sendable, Equatable {
        public let totalRAMGB: Int
        public let cpuCores: Int
        public let chipFamily: ChipFamily
        public let isAppleSilicon: Bool
        public let chipName: String

        public init(totalRAMGB: Int, cpuCores: Int, chipFamily: ChipFamily, isAppleSilicon: Bool, chipName: String) {
            self.totalRAMGB = totalRAMGB
            self.cpuCores = cpuCores
            self.chipFamily = chipFamily
            self.isAppleSilicon = isAppleSilicon
            self.chipName = chipName
        }
    }

    /// Detect the current Mac's hardware specifications.
    public static func detectHardware() -> HardwareInfo {
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        let ramGB = Int(ramBytes / (1024 * 1024 * 1024))
        let cores = ProcessInfo.processInfo.activeProcessorCount

        let brandString = cpuBrandString()
        let chipFamily = parseChipFamily(from: brandString)
        let isAppleSilicon = chipFamily != .intel && chipFamily != .unknown

        return HardwareInfo(
            totalRAMGB: ramGB,
            cpuCores: cores,
            chipFamily: chipFamily,
            isAppleSilicon: isAppleSilicon,
            chipName: brandString
        )
    }

    /// Read the CPU brand string via sysctl.
    private static func cpuBrandString() -> String {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    /// Parse chip family from brand string.
    public static func parseChipFamily(from brandString: String) -> ChipFamily {
        let lower = brandString.lowercased()
        if lower.contains("m4") { return .m4 }
        if lower.contains("m3") { return .m3 }
        if lower.contains("m2") { return .m2 }
        if lower.contains("m1") { return .m1 }
        if lower.contains("intel") || lower.contains("core") { return .intel }
        // Apple Silicon chips contain "Apple" in brand string
        if lower.contains("apple") {
            // Try to detect from the full string
            if lower.contains("m4") { return .m4 }
            if lower.contains("m3") { return .m3 }
            if lower.contains("m2") { return .m2 }
            return .m1  // Default Apple Silicon to M1 if unknown
        }
        return .unknown
    }

    // MARK: - Recommendations

    /// Maximum recommended parameter count (in billions) for given hardware.
    public static func maxRecommendedParams(ramGB: Int, appleSilicon: Bool) -> Double {
        // Apple Silicon gets a boost due to unified memory architecture
        let effectiveRAM = appleSilicon ? Int(Double(ramGB) * 1.25) : ramGB

        switch effectiveRAM {
        case ..<12: return 3.0
        case 12..<20: return 8.0
        case 20..<40: return 14.0
        case 40..<80: return 35.0
        default: return 72.0
        }
    }

    /// Filter the model catalog to models recommended for the given hardware.
    public static func recommendedModels(for hardware: HardwareInfo) -> [OllamaModelInfo] {
        let maxParams = maxRecommendedParams(ramGB: hardware.totalRAMGB, appleSilicon: hardware.isAppleSilicon)
        return modelCatalog.filter { $0.parameterCount <= maxParams }
    }

    /// Get recommended models for hardware, grouped by use-case and sorted by quality.
    public static func recommendedModelsByGroup(for hardware: HardwareInfo) -> [(group: ModelGroup, models: [OllamaModelInfo])] {
        let maxParams = maxRecommendedParams(ramGB: hardware.totalRAMGB, appleSilicon: hardware.isAppleSilicon)
        return ModelGroup.allCases.compactMap { group in
            let models = modelCatalog
                .filter { $0.group == group && $0.parameterCount <= maxParams }
                .sorted { $0.qualityRank < $1.qualityRank }
            guard !models.isEmpty else { return nil }
            return (group: group, models: models)
        }
    }

    /// Human-readable recommendation text for the given hardware.
    public static func recommendationText(for hardware: HardwareInfo) -> String {
        let maxParams = maxRecommendedParams(ramGB: hardware.totalRAMGB, appleSilicon: hardware.isAppleSilicon)
        if maxParams >= 70 {
            return "Your Mac can comfortably run models up to ~70B parameters."
        } else {
            return "Your Mac can comfortably run models up to ~\(Int(maxParams))B parameters."
        }
    }

    // MARK: - Parse `ollama ps`

    /// A model currently loaded in Ollama's memory.
    public struct RunningModel: Sendable, Equatable {
        public let name: String
        public let size: String
        public let processor: String

        public init(name: String, size: String, processor: String) {
            self.name = name
            self.size = size
            self.processor = processor
        }
    }

    /// Parse the output of `ollama ps` into running model entries.
    /// Format: NAME  ID  SIZE  PROCESSOR  UNTIL
    public static func parseOllamaPs(_ output: String) -> [RunningModel] {
        let lines = output.components(separatedBy: .newlines)
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            // Split by two or more whitespace characters to handle column alignment
            let columns = trimmed.components(separatedBy: "  ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Expected: NAME, ID, SIZE, PROCESSOR, UNTIL (at least 4 columns)
            guard columns.count >= 4 else { return nil }

            return RunningModel(
                name: columns[0],
                size: columns[2],
                processor: columns[3]
            )
        }
    }

    // MARK: - Default Port

    /// Default Ollama server port.
    public static let defaultPort = 11434

    /// Health check URL for the Ollama server.
    public static func healthURL(port: Int = defaultPort) -> String {
        "http://localhost:\(port)"
    }

    /// API tags URL (list models via REST).
    public static func tagsURL(port: Int = defaultPort) -> String {
        "http://localhost:\(port)/api/tags"
    }
}
