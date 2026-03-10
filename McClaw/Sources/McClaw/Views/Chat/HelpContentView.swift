import SwiftUI

/// Full help guide displayed in the main content area.
struct HelpContentView: View {

    var body: some View {
        VStack(spacing: 0) {
            // Back header
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                Text(String(localized: "help_title", bundle: .module))
                    .font(.title2.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    slashCommandsSection
                    keyboardShortcutsSection
                    chatFeaturesSection
                    voiceModeSection
                    canvasSection
                    projectsSection
                    mcpSection
                    connectorsSection
                }
                .padding(20)
            }
        }
    }

    // MARK: - Slash Commands

    @ViewBuilder
    private var slashCommandsSection: some View {
        helpSection(
            title: String(localized: "help_slash_commands", bundle: .module),
            icon: "terminal"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                // Native commands
                ForEach(SlashCommandRegistry.nativeCommands) { cmd in
                    commandRow(cmd)
                }

                Divider()
                    .padding(.vertical, 8)

                Text(String(localized: "help_cli_commands_header", bundle: .module))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                // CLI commands
                ForEach(SlashCommandRegistry.cliCommands) { cmd in
                    commandRow(cmd)
                }
            }
        }
    }

    @ViewBuilder
    private func commandRow(_ cmd: SlashCommandDefinition) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: cmd.icon)
                .font(.system(size: 12))
                .foregroundStyle(cmd.isNative ? Theme.accent : .secondary)
                .frame(width: 18, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cmd.command)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    if let hint = cmd.argumentHint {
                        Text(hint)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if let cliHint = cmd.cliHint {
                        Text(cliHint)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary.opacity(0.3))
                            .clipShape(Capsule())
                    }
                }
                Text(cmd.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Keyboard Shortcuts

    @ViewBuilder
    private var keyboardShortcutsSection: some View {
        helpSection(
            title: String(localized: "help_keyboard_shortcuts", bundle: .module),
            icon: "keyboard"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                shortcutRow("⌘ N", String(localized: "help_shortcut_new_chat", bundle: .module))
                shortcutRow("⌘ ,", String(localized: "help_shortcut_settings", bundle: .module))
                shortcutRow("⌘ ⇧ V", String(localized: "help_shortcut_voice", bundle: .module))
                shortcutRow("⌘ .", String(localized: "help_shortcut_abort", bundle: .module))
                shortcutRow("⌘ L", String(localized: "help_shortcut_clear", bundle: .module))
                shortcutRow("⌘ ⇧ C", String(localized: "help_shortcut_copy_last", bundle: .module))
                shortcutRow("Enter", String(localized: "help_shortcut_send", bundle: .module))
                shortcutRow("⇧ Enter", String(localized: "help_shortcut_newline", bundle: .module))
            }
        }
    }

    @ViewBuilder
    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .trailing)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - Chat Features

    @ViewBuilder
    private var chatFeaturesSection: some View {
        helpSection(
            title: String(localized: "help_chat_features", bundle: .module),
            icon: "bubble.left.and.bubble.right"
        ) {
            featureList([
                (String(localized: "help_feature_streaming", bundle: .module),
                 String(localized: "help_feature_streaming_desc", bundle: .module)),
                (String(localized: "help_feature_model_selection", bundle: .module),
                 String(localized: "help_feature_model_selection_desc", bundle: .module)),
                (String(localized: "help_feature_plan_mode", bundle: .module),
                 String(localized: "help_feature_plan_mode_desc", bundle: .module)),
                (String(localized: "help_feature_image_gen", bundle: .module),
                 String(localized: "help_feature_image_gen_desc", bundle: .module)),
                (String(localized: "help_feature_markdown", bundle: .module),
                 String(localized: "help_feature_markdown_desc", bundle: .module)),
                (String(localized: "help_feature_multi_provider", bundle: .module),
                 String(localized: "help_feature_multi_provider_desc", bundle: .module)),
            ])
        }
    }

    // MARK: - Voice Mode

    @ViewBuilder
    private var voiceModeSection: some View {
        helpSection(
            title: String(localized: "help_voice_mode", bundle: .module),
            icon: "mic"
        ) {
            featureList([
                (String(localized: "help_voice_wake_word", bundle: .module),
                 String(localized: "help_voice_wake_word_desc", bundle: .module)),
                (String(localized: "help_voice_push_to_talk", bundle: .module),
                 String(localized: "help_voice_push_to_talk_desc", bundle: .module)),
                (String(localized: "help_voice_settings", bundle: .module),
                 String(localized: "help_voice_settings_desc", bundle: .module)),
            ])
        }
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvasSection: some View {
        helpSection(
            title: String(localized: "help_canvas", bundle: .module),
            icon: "paintbrush"
        ) {
            featureList([
                (String(localized: "help_canvas_inline", bundle: .module),
                 String(localized: "help_canvas_inline_desc", bundle: .module)),
                (String(localized: "help_canvas_external", bundle: .module),
                 String(localized: "help_canvas_external_desc", bundle: .module)),
                (String(localized: "help_canvas_hot_reload", bundle: .module),
                 String(localized: "help_canvas_hot_reload_desc", bundle: .module)),
            ])
        }
    }

    // MARK: - Projects

    @ViewBuilder
    private var projectsSection: some View {
        helpSection(
            title: String(localized: "help_projects", bundle: .module),
            icon: "folder"
        ) {
            featureList([
                (String(localized: "help_projects_create", bundle: .module),
                 String(localized: "help_projects_create_desc", bundle: .module)),
                (String(localized: "help_projects_sessions", bundle: .module),
                 String(localized: "help_projects_sessions_desc", bundle: .module)),
                (String(localized: "help_projects_memory", bundle: .module),
                 String(localized: "help_projects_memory_desc", bundle: .module)),
                (String(localized: "help_projects_artifacts", bundle: .module),
                 String(localized: "help_projects_artifacts_desc", bundle: .module)),
            ])
        }
    }

    // MARK: - MCP

    @ViewBuilder
    private var mcpSection: some View {
        helpSection(
            title: String(localized: "help_mcp", bundle: .module),
            icon: "server.rack"
        ) {
            featureList([
                (String(localized: "help_mcp_add", bundle: .module),
                 String(localized: "help_mcp_add_desc", bundle: .module)),
                (String(localized: "help_mcp_config", bundle: .module),
                 String(localized: "help_mcp_config_desc", bundle: .module)),
                (String(localized: "help_mcp_providers", bundle: .module),
                 String(localized: "help_mcp_providers_desc", bundle: .module)),
            ])
        }
    }

    // MARK: - Connectors

    @ViewBuilder
    private var connectorsSection: some View {
        helpSection(
            title: String(localized: "help_connectors", bundle: .module),
            icon: "link"
        ) {
            featureList([
                (String(localized: "help_connectors_fetch", bundle: .module),
                 String(localized: "help_connectors_fetch_desc", bundle: .module)),
                (String(localized: "help_connectors_types", bundle: .module),
                 String(localized: "help_connectors_types_desc", bundle: .module)),
                (String(localized: "help_connectors_oauth", bundle: .module),
                 String(localized: "help_connectors_oauth_desc", bundle: .module)),
            ])
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func helpSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup {
            content()
                .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)
                Text(title)
                    .font(.headline)
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func featureList(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0)
                        .font(.callout.weight(.medium))
                    Text(item.1)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
