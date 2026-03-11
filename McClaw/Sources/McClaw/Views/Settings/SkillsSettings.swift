import McClawKit
import SwiftUI
import UniformTypeIdentifiers

/// Skills management tab in Settings — local file-based skills.
struct SkillsSettingsTab: View {
    @State private var store = LocalSkillsStore.shared
    @State private var showImporter = false
    @State private var confirmRemove: LocalSkillInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusBanner
            skillsList
            Spacer(minLength: 0)
        }
        .padding()
        .onAppear { store.refresh() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await store.importZIP(from: url) }
            }
        }
        .alert("Remove Skill?",
               isPresented: Binding(
                get: { confirmRemove != nil },
                set: { if !$0 { confirmRemove = nil } }
               )) {
            Button("Cancel", role: .cancel) { confirmRemove = nil }
            Button("Remove", role: .destructive) {
                if let skill = confirmRemove {
                    store.remove(skillId: skill.id)
                }
            }
        } message: {
            if let skill = confirmRemove {
                Text("Remove \"\(skill.metadata.name)\"? The skill folder will be deleted from disk.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skills")
                        .font(.headline)
                    Text("Import specialized knowledge that the AI can read on demand.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Button {
                    showImporter = true
                } label: {
                    Label("Import ZIP", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Button {
                    store.openSkillsFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    store.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            skillsInfoNote
        }
    }

    /// Informational note explaining how skills work.
    private var skillsInfoNote: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Label("How Skills Work", systemImage: "info.circle")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Text("Each skill is a folder with a SKILL.md file (instructions for the AI) and an optional references/ folder with detailed docs. When you chat, McClaw tells the AI which skills are available — the AI reads the relevant ones automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                Text("Skills are stored in ~/.mcclaw/skills/. You can import a ZIP or drop folders there manually.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .padding(4)
        }
    }

    // MARK: - Status Banner

    @ViewBuilder
    private var statusBanner: some View {
        if let error = store.error {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.orange)
        } else if let message = store.statusMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.green)
        }
    }

    // MARK: - Skills List

    @ViewBuilder
    private var skillsList: some View {
        if store.skills.isEmpty && !store.isLoading {
            ContentUnavailableView(
                "No skills installed",
                systemImage: "sparkles",
                description: Text("Import a ZIP file or drop a skill folder into ~/.mcclaw/skills/")
            )
        } else {
            let grouped = groupedSkills
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(grouped, id: \.category) { group in
                        skillGroupSection(group)
                    }
                }
            }
        }
    }

    private func skillGroupSection(_ group: SkillGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: group.icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(group.category)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("(\(group.skills.count))")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 4)
            .padding(.top, 4)

            VStack(spacing: 2) {
                ForEach(group.skills) { skill in
                    skillRow(skill)
                }
            }
        }
    }

    // MARK: - Grouping Logic

    private struct SkillGroup {
        let category: String
        let icon: String
        let skills: [LocalSkillInfo]
    }

    private var groupedSkills: [SkillGroup] {
        var buckets: [String: [LocalSkillInfo]] = [:]

        for skill in store.skills {
            let cat = skillCategory(for: skill.id)
            buckets[cat, default: []].append(skill)
        }

        // Sort skills alphabetically within each group
        for key in buckets.keys {
            buckets[key]?.sort { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }
        }

        // Define display order for categories
        let order: [(String, String)] = [
            ("Documents & Files", "doc.richtext"),
            ("Product Management", "chart.bar"),
            ("Developer Tools", "wrench.and.screwdriver"),
            ("WordPress Core", "globe"),
            ("WordPress Themes", "paintbrush"),
            ("WooCommerce", "cart"),
            ("WordPress Site Management", "server.rack"),
        ]

        var result: [SkillGroup] = []
        for (cat, icon) in order {
            if let skills = buckets[cat], !skills.isEmpty {
                result.append(SkillGroup(category: cat, icon: icon, skills: skills))
            }
        }

        // Any remaining categories not in the predefined order
        let knownCats = Set(order.map(\.0))
        for (cat, skills) in buckets.sorted(by: { $0.key < $1.key }) {
            if !knownCats.contains(cat) && !skills.isEmpty {
                result.append(SkillGroup(category: cat, icon: "sparkles", skills: skills))
            }
        }

        return result
    }

    /// Derive a category from the skill folder ID.
    private func skillCategory(for id: String) -> String {
        // WordPress Themes
        if id.hasPrefix("theme-") { return "WordPress Themes" }

        // WooCommerce
        if id == "woocommerce" { return "WooCommerce" }

        // WordPress Site Management (creation, updates, security)
        if ["site-creation", "site-security", "site-update"].contains(id) {
            return "WordPress Site Management"
        }

        // WordPress Core development skills
        if id.hasPrefix("wp-") || id == "wpds" || id == "wordpress-router" {
            return "WordPress Core"
        }

        // Documents & Files
        if ["pdf", "docx", "pptx", "xlsx"].contains(id) {
            return "Documents & Files"
        }

        // Product Management
        if ["competitive-analysis", "feature-spec", "metrics-tracking",
            "roadmap-management", "stakeholder-comms", "user-research-synthesis"].contains(id) {
            return "Product Management"
        }

        // Developer Tools
        if ["mcp-builder", "skill-creator"].contains(id) {
            return "Developer Tools"
        }

        return "Other"
    }

    private func skillRow(_ skill: LocalSkillInfo) -> some View {
        HStack(spacing: 10) {
            Text(skill.metadata.emoji ?? "⚡")
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.metadata.name)
                        .font(.body)

                    if let version = skill.metadata.version {
                        Text("v\(version)")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !skill.metadata.description.isEmpty {
                    Text(skill.metadata.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    SkillTag(text: "Local")

                    if !skill.referenceFiles.isEmpty {
                        SkillTag(text: "\(skill.referenceFiles.count) refs")
                    }

                    if let author = skill.metadata.author {
                        Text("by \(author)")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { skill.isEnabled },
                set: { store.setEnabled(skillId: skill.id, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()

            Button {
                confirmRemove = skill
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Helpers

private struct SkillTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
            .liquidGlassCapsule(interactive: false)
    }
}
