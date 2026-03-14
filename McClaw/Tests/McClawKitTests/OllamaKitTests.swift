import Testing
@testable import McClawKit

@Suite("OllamaKit")
struct OllamaKitTests {

    // MARK: - Model Catalog

    @Test("Model catalog covers all use-case groups")
    func catalogCoversAllGroups() {
        let groups = Set(OllamaKit.modelCatalog.map(\.group))
        for group in OllamaKit.ModelGroup.allCases {
            #expect(groups.contains(group), "Missing group: \(group.rawValue)")
        }
    }

    @Test("Model catalog covers all size categories")
    func catalogCoversAllSizes() {
        let sizes = Set(OllamaKit.modelCatalog.map(\.sizeCategory))
        #expect(sizes.contains(.small))
        #expect(sizes.contains(.medium))
        #expect(sizes.contains(.large))
        #expect(sizes.contains(.veryLarge))
    }

    @Test("Model catalog IDs are unique")
    func catalogUniqueIds() {
        // IDs can repeat across groups (e.g., gemma3:27b in general + multimodal)
        // but the compound key (modelId + group) must be unique
        let keys = OllamaKit.modelCatalog.map { "\($0.modelId)|\($0.group.rawValue)" }
        #expect(Set(keys).count == keys.count)
    }

    @Test("All catalog models have valid fields")
    func catalogValidFields() {
        for model in OllamaKit.modelCatalog {
            #expect(model.minimumRAMGB >= 8)
            #expect(!model.displayName.isEmpty)
            #expect(!model.description.isEmpty)
            #expect(model.parameterCount > 0)
            #expect(model.qualityRank >= 1)
        }
    }

    @Test("Models within each group are ranked consecutively from 1")
    func catalogGroupRanking() {
        for group in OllamaKit.ModelGroup.allCases {
            let models = OllamaKit.models(in: group)
            #expect(!models.isEmpty, "Group \(group.rawValue) has no models")
            // Ranks should be 1, 2, 3, ... (consecutive)
            for (index, model) in models.enumerated() {
                #expect(model.qualityRank == index + 1,
                        "Group \(group.rawValue): expected rank \(index + 1), got \(model.qualityRank) for \(model.modelId)")
            }
        }
    }

    @Test("Models in group are sorted best first")
    func modelsInGroupSorted() {
        for group in OllamaKit.ModelGroup.allCases {
            let models = OllamaKit.models(in: group)
            for i in 0..<models.count - 1 {
                #expect(models[i].qualityRank < models[i + 1].qualityRank)
            }
        }
    }

    @Test("ModelGroup has display names and icons")
    func groupMetadata() {
        for group in OllamaKit.ModelGroup.allCases {
            #expect(!group.displayName.isEmpty)
            #expect(!group.icon.isEmpty)
            #expect(!group.groupDescription.isEmpty)
        }
    }

    // MARK: - Hardware Detection

    @Test("Parse chip family from brand string")
    func parseChipFamily() {
        #expect(OllamaKit.parseChipFamily(from: "Apple M1 Pro") == .m1)
        #expect(OllamaKit.parseChipFamily(from: "Apple M2 Max") == .m2)
        #expect(OllamaKit.parseChipFamily(from: "Apple M3") == .m3)
        #expect(OllamaKit.parseChipFamily(from: "Apple M4 Pro") == .m4)
        #expect(OllamaKit.parseChipFamily(from: "Intel(R) Core(TM) i9-9980HK") == .intel)
        #expect(OllamaKit.parseChipFamily(from: "") == .unknown)
    }

    @Test("Detect hardware returns valid info")
    func detectHardware() {
        let hw = OllamaKit.detectHardware()
        #expect(hw.totalRAMGB > 0)
        #expect(hw.cpuCores > 0)
        #expect(!hw.chipName.isEmpty)
    }

    // MARK: - Recommendations

    @Test("8GB Intel gets only small models")
    func recommendations8GBIntel() {
        let maxParams = OllamaKit.maxRecommendedParams(ramGB: 8, appleSilicon: false)
        #expect(maxParams == 3.0)
    }

    @Test("8GB Apple Silicon gets slightly more")
    func recommendations8GBAppleSilicon() {
        let maxParams = OllamaKit.maxRecommendedParams(ramGB: 8, appleSilicon: true)
        #expect(maxParams == 3.0)
    }

    @Test("16GB Intel gets medium models")
    func recommendations16GBIntel() {
        let maxParams = OllamaKit.maxRecommendedParams(ramGB: 16, appleSilicon: false)
        #expect(maxParams == 8.0)
    }

    @Test("16GB Apple Silicon gets boosted to large")
    func recommendations16GBAppleSilicon() {
        let maxParams = OllamaKit.maxRecommendedParams(ramGB: 16, appleSilicon: true)
        #expect(maxParams == 14.0)
    }

    @Test("32GB Apple Silicon gets large models")
    func recommendations32GBAppleSilicon() {
        let maxParams = OllamaKit.maxRecommendedParams(ramGB: 32, appleSilicon: true)
        #expect(maxParams == 35.0)
    }

    @Test("64GB Apple Silicon gets very large models")
    func recommendations64GBAppleSilicon() {
        let maxParams = OllamaKit.maxRecommendedParams(ramGB: 64, appleSilicon: true)
        #expect(maxParams == 72.0)
    }

    @Test("Recommended models filtered by hardware")
    func recommendedModelsFiltered() {
        let hw8GB = OllamaKit.HardwareInfo(totalRAMGB: 8, cpuCores: 8, chipFamily: .intel, isAppleSilicon: false, chipName: "Intel Core i5")
        let models8 = OllamaKit.recommendedModels(for: hw8GB)
        for model in models8 {
            #expect(model.parameterCount <= 3.0)
        }
        #expect(!models8.isEmpty)
    }

    @Test("Recommended models by group returns sorted groups")
    func recommendedByGroup() {
        let hw32GB = OllamaKit.HardwareInfo(totalRAMGB: 32, cpuCores: 10, chipFamily: .m2, isAppleSilicon: true, chipName: "Apple M2 Pro")
        let groups = OllamaKit.recommendedModelsByGroup(for: hw32GB)
        // Should have multiple groups
        #expect(groups.count >= 3)
        // Each group's models should be sorted by qualityRank
        for entry in groups {
            for i in 0..<entry.models.count - 1 {
                #expect(entry.models[i].qualityRank < entry.models[i + 1].qualityRank)
            }
        }
    }

    @Test("Available groups match hardware")
    func availableGroups() {
        let hw8GB = OllamaKit.HardwareInfo(totalRAMGB: 8, cpuCores: 8, chipFamily: .intel, isAppleSilicon: false, chipName: "Intel Core i5")
        let groups = OllamaKit.availableGroups(for: hw8GB)
        // Even 8GB should have some groups (at least general, coding, reasoning)
        #expect(groups.count >= 3)
    }

    @Test("Recommendation text is meaningful")
    func recommendationText() {
        let hw = OllamaKit.HardwareInfo(totalRAMGB: 16, cpuCores: 10, chipFamily: .m2, isAppleSilicon: true, chipName: "Apple M2")
        let text = OllamaKit.recommendationText(for: hw)
        #expect(text.contains("14B"))
    }

    // MARK: - Parse ollama ps

    @Test("Parse ollama ps output")
    func parseOllamaPs() {
        let output = """
        NAME              ID              SIZE      PROCESSOR    UNTIL
        llama3.2:latest   a80c4f17acd5    2.0 GB    100% GPU     4 minutes from now
        mistral:latest    f974a74358d6    4.1 GB    100% GPU     4 minutes from now
        """
        let models = OllamaKit.parseOllamaPs(output)
        #expect(models.count == 2)
        #expect(models[0].name == "llama3.2:latest")
        #expect(models[1].name == "mistral:latest")
    }

    @Test("Parse empty ollama ps output")
    func parseOllamaPsEmpty() {
        let output = "NAME              ID              SIZE      PROCESSOR    UNTIL"
        let models = OllamaKit.parseOllamaPs(output)
        #expect(models.isEmpty)
    }

    @Test("Parse ollama ps with no output")
    func parseOllamaPsNoOutput() {
        let models = OllamaKit.parseOllamaPs("")
        #expect(models.isEmpty)
    }

    // MARK: - URLs

    @Test("Health URL uses correct port")
    func healthURL() {
        #expect(OllamaKit.healthURL() == "http://localhost:11434")
        #expect(OllamaKit.healthURL(port: 9999) == "http://localhost:9999")
    }

    @Test("Tags URL uses correct port")
    func tagsURL() {
        #expect(OllamaKit.tagsURL() == "http://localhost:11434/api/tags")
    }
}
