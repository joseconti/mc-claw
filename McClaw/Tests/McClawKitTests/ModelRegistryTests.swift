import Testing
@testable import McClawKit

@Suite("ModelRegistry")
struct ModelRegistryTests {

    @Test("Known providers return non-empty model lists")
    func modelsForKnownProviders() {
        for provider in ["claude", "chatgpt", "gemini", "ollama"] {
            let models = ModelRegistry.models(for: provider)
            #expect(!models.isEmpty, "Expected models for \(provider)")
        }
    }

    @Test("Each provider has exactly one default model")
    func defaultModelExists() {
        for provider in ["claude", "chatgpt", "gemini", "ollama"] {
            let defaults = ModelRegistry.models(for: provider).filter(\.isDefault)
            #expect(defaults.count == 1, "Expected 1 default for \(provider), got \(defaults.count)")
        }
    }

    @Test("defaultModel returns the default for known providers")
    func defaultModelHelper() {
        #expect(ModelRegistry.defaultModel(for: "claude")?.modelId == "claude-sonnet-4-20250514")
        #expect(ModelRegistry.defaultModel(for: "chatgpt")?.modelId == "gpt-4o")
        #expect(ModelRegistry.defaultModel(for: "gemini")?.modelId == "gemini-2.5-pro")
        #expect(ModelRegistry.defaultModel(for: "ollama")?.modelId == "llama3.2")
    }

    @Test("Unknown provider returns empty list")
    func unknownProviderReturnsEmpty() {
        #expect(ModelRegistry.models(for: "unknown").isEmpty)
        #expect(ModelRegistry.defaultModel(for: "unknown") == nil)
    }

    @Test("Merge deduplicates by modelId")
    func mergeDeduplicate() {
        let staticModels = [
            RegisteredModel(modelId: "a", displayName: "A", provider: "test", isDefault: true),
            RegisteredModel(modelId: "b", displayName: "B", provider: "test"),
        ]
        let dynamicModels = [
            RegisteredModel(modelId: "b", displayName: "B-dyn", provider: "test"),
            RegisteredModel(modelId: "c", displayName: "C", provider: "test"),
        ]
        let merged = ModelRegistry.merge(staticModels: staticModels, dynamicModels: dynamicModels)
        #expect(merged.count == 3)
        // Static "b" kept, dynamic "b" deduplicated
        #expect(merged.first(where: { $0.modelId == "b" })?.displayName == "B")
        #expect(merged.contains(where: { $0.modelId == "c" }))
    }

    @Test("Parse ollama list output")
    func parseOllamaList() {
        let output = """
        NAME                   SIZE      MODIFIED
        llama3.2:latest        3.2 GB    2 weeks ago
        codestral:latest       12 GB     3 days ago
        mistral:7b             4.1 GB    1 month ago
        """
        let models = ModelRegistry.parseOllamaList(output)
        #expect(models.count == 3)
        #expect(models[0].modelId == "llama3.2:latest")
        #expect(models[0].displayName == "Llama3.2")
        #expect(models[1].modelId == "codestral:latest")
        #expect(models[2].modelId == "mistral:7b")
        #expect(models[2].displayName == "Mistral")
    }

    @Test("Parse empty ollama list")
    func parseOllamaListEmpty() {
        let output = "NAME                   SIZE      MODIFIED\n"
        let models = ModelRegistry.parseOllamaList(output)
        #expect(models.isEmpty)
    }

    @Test("All registered models have correct provider field")
    func providerFieldConsistency() {
        for provider in ["claude", "chatgpt", "gemini", "ollama"] {
            for model in ModelRegistry.models(for: provider) {
                #expect(model.provider == provider)
            }
        }
    }
}
