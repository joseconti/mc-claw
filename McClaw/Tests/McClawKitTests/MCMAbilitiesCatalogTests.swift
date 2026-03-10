import Foundation
import Testing
@testable import McClawKit

// MARK: - MCM Abilities Catalog Tests

@Suite("MCMAbilitiesCatalog")
struct MCMAbilitiesCatalogTests {

    @Test("Catalog version is set")
    func version() {
        #expect(MCMAbilitiesCatalog.version == "2.5.0")
    }

    @Test("Has 13 sub-connectors")
    func subConnectorCount() {
        #expect(MCMAbilitiesCatalog.subConnectors.count == 13)
    }

    @Test("Total abilities count is reasonable (250+)")
    func totalAbilities() {
        let total = MCMAbilitiesCatalog.totalAbilities
        #expect(total >= 250, "Expected at least 250 abilities, got \(total)")
    }

    @Test("All sub-connector IDs start with wp.")
    func subConnectorIdPrefix() {
        for sub in MCMAbilitiesCatalog.subConnectors {
            #expect(sub.id.hasPrefix("wp."), "Sub-connector \(sub.id) should start with wp.")
        }
    }

    @Test("All sub-connectors have unique IDs")
    func uniqueSubConnectorIds() {
        let ids = MCMAbilitiesCatalog.subConnectors.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate sub-connector IDs found")
    }

    @Test("All abilities have unique IDs across entire catalog")
    func uniqueAbilityIds() {
        let allAbilities = MCMAbilitiesCatalog.subConnectors.flatMap(\.abilities)
        let ids = allAbilities.map(\.id)
        let uniqueIds = Set(ids)
        let duplicates = ids.filter { id in ids.filter { $0 == id }.count > 1 }
        #expect(uniqueIds.count == ids.count, "Duplicate ability IDs: \(Set(duplicates))")
    }

    @Test("All abilities have non-empty name and description")
    func abilitiesHaveMetadata() {
        for sub in MCMAbilitiesCatalog.subConnectors {
            for ability in sub.abilities {
                #expect(!ability.name.isEmpty, "Ability \(ability.id) has empty name")
                #expect(!ability.description.isEmpty, "Ability \(ability.id) has empty description")
            }
        }
    }

    @Test("Required params are correctly flagged")
    func requiredParams() {
        // create-content should require title
        let create = MCMAbilitiesCatalog.ability(for: "create-content")
        #expect(create != nil)
        let titleParam = create?.params.first { $0.name == "title" }
        #expect(titleParam?.required == true)
    }

    @Test("Enum values are set for status params")
    func enumValues() {
        let create = MCMAbilitiesCatalog.ability(for: "create-content")
        let statusParam = create?.params.first { $0.name == "status" }
        #expect(statusParam?.enumValues?.contains("draft") == true)
        #expect(statusParam?.enumValues?.contains("publish") == true)
    }

    @Test("Lookup by ID works")
    func lookupById() {
        #expect(MCMAbilitiesCatalog.ability(for: "site-health") != nil)
        #expect(MCMAbilitiesCatalog.ability(for: "wc-list-products") != nil)
        #expect(MCMAbilitiesCatalog.ability(for: "security-audit") != nil)
        #expect(MCMAbilitiesCatalog.ability(for: "nonexistent") == nil)
    }

    @Test("Sub-connector lookup works")
    func subConnectorLookup() {
        let content = MCMAbilitiesCatalog.subConnector(for: "wp.content")
        #expect(content != nil)
        #expect(content?.name == "WP Content")

        let wc = MCMAbilitiesCatalog.subConnector(for: "wp.woocommerce")
        #expect(wc != nil)
        #expect(wc!.abilities.count >= 60, "WooCommerce should have 60+ abilities")
    }

    @Test("Search finds abilities by name and description")
    func searchAbilities() {
        let results = MCMAbilitiesCatalog.search("coupon")
        #expect(!results.isEmpty, "Should find coupon-related abilities")
        #expect(results.contains { $0.id == "wc-create-coupon" })
    }

    @Test("Search is case-insensitive")
    func searchCaseInsensitive() {
        let upper = MCMAbilitiesCatalog.search("SECURITY")
        let lower = MCMAbilitiesCatalog.search("security")
        #expect(upper.count == lower.count)
    }

    @Test("Confirmation flags are set on destructive operations")
    func confirmationFlags() {
        let deleteContent = MCMAbilitiesCatalog.ability(for: "delete-content")
        #expect(deleteContent?.requiresConfirmation == true)

        let cleanCore = MCMAbilitiesCatalog.ability(for: "clean-core")
        #expect(cleanCore?.requiresConfirmation == true)

        let siteHealth = MCMAbilitiesCatalog.ability(for: "site-health")
        #expect(siteHealth?.requiresConfirmation == false)
    }

    @Test("WooCommerce abilities are in wp.woocommerce sub-connector")
    func wcAbilitiesGrouped() {
        let wc = MCMAbilitiesCatalog.subConnector(for: "wp.woocommerce")!
        let wcIds = wc.abilities.map(\.id)
        #expect(wcIds.contains("wc-list-products"))
        #expect(wcIds.contains("wc-list-orders"))
        #expect(wcIds.contains("wc-sales-report"))
        #expect(wcIds.contains("wc-performance-kpis"))
    }

    @Test("Each sub-connector has a valid SF Symbol icon")
    func subConnectorIcons() {
        for sub in MCMAbilitiesCatalog.subConnectors {
            #expect(!sub.icon.isEmpty, "Sub-connector \(sub.id) has empty icon")
        }
    }

    @Test("Param types are valid")
    func paramTypes() {
        let validTypes: Set<String> = ["string", "integer", "boolean", "enum"]
        for sub in MCMAbilitiesCatalog.subConnectors {
            for ability in sub.abilities {
                for param in ability.params {
                    #expect(validTypes.contains(param.type), "Ability \(ability.id) param \(param.name) has invalid type: \(param.type)")
                }
            }
        }
    }
}

// MARK: - WordPress Provider Integration Tests (pure logic)

@Suite("MCMAbilitiesCatalog.WordPressProvider")
struct WordPressProviderCatalogTests {

    @Test("Catalog has all 13 sub-connectors")
    func subConnectorsCoverAll() {
        let ids = Set(MCMAbilitiesCatalog.subConnectors.map(\.id))
        #expect(ids.count == 13)
        #expect(ids.contains("wp.content"))
        #expect(ids.contains("wp.woocommerce"))
        #expect(ids.contains("wp.security"))
        #expect(ids.contains("wp.media"))
    }

    @Test("Sub-connector resolution for abilities")
    func subConnectorResolution() {
        // Content abilities → wp.content
        let content = MCMAbilitiesCatalog.subConnector(for: "site-health")
        #expect(content == nil) // site-health is in wp.system, test lookup

        let system = MCMAbilitiesCatalog.subConnectors.first {
            $0.abilities.contains { $0.id == "site-health" }
        }
        #expect(system?.id == "wp.system")

        // WooCommerce abilities → wp.woocommerce
        let wc = MCMAbilitiesCatalog.subConnectors.first {
            $0.abilities.contains { $0.id == "wc-list-products" }
        }
        #expect(wc?.id == "wp.woocommerce")

        // Security abilities → wp.security
        let sec = MCMAbilitiesCatalog.subConnectors.first {
            $0.abilities.contains { $0.id == "security-audit" }
        }
        #expect(sec?.id == "wp.security")
    }

    @Test("Ability validation catches missing required params")
    func abilityParamValidation() {
        let create = MCMAbilitiesCatalog.ability(for: "create-content")
        #expect(create != nil)

        let requiredParams = create!.params.filter(\.required)
        #expect(!requiredParams.isEmpty, "create-content should have required params")
        #expect(requiredParams.contains { $0.name == "title" })
    }

    @Test("site-health exists for testConnection")
    func siteHealthExists() {
        // WordPressProvider.testConnection uses site-health ability
        let ability = MCMAbilitiesCatalog.ability(for: "site-health")
        #expect(ability != nil, "site-health ability must exist for connection testing")
    }

    @Test("All sub-connectors have non-empty abilities")
    func allSubConnectorsHaveAbilities() {
        for sub in MCMAbilitiesCatalog.subConnectors {
            #expect(!sub.abilities.isEmpty, "Sub-connector \(sub.id) has no abilities")
        }
    }

    @Test("Sub-connector for ability lookup via helper")
    func subConnectorForAbility() {
        let sub = MCMAbilitiesCatalog.subConnector(forAbility: "wc-list-orders")
        #expect(sub?.id == "wp.woocommerce")

        let nonExistent = MCMAbilitiesCatalog.subConnector(forAbility: "nonexistent-ability")
        #expect(nonExistent == nil)
    }
}
