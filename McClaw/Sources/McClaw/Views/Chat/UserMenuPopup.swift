import SwiftUI

/// Claude Desktop-style user menu popup, shown above the sidebar footer.
struct UserMenuPopup: View {
    let onSettings: () -> Void
    let onHelp: () -> Void
    let onDismiss: () -> Void

    @State private var showLanguages = false
    @State private var hoveredItem: String?
    @State private var showRestartAlert = false
    @State private var pendingLanguageCode: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header: email + version
            headerSection

            Divider()
                .padding(.horizontal, 12)

            // Menu items
            menuSection

            Divider()
                .padding(.horizontal, 12)

            // Promotional section
            promotionalSection
        }
        .padding(.vertical, 8)
        .frame(width: 260)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: -4)
        .alert(
            String(localized: "user_menu_language_restart_title", bundle: .module),
            isPresented: $showRestartAlert
        ) {
            Button(String(localized: "user_menu_language_restart_button", bundle: .module)) {
                if let code = pendingLanguageCode {
                    LanguageSwitcher.setLanguage(code)
                    LanguageSwitcher.restartApp()
                }
            }
            Button(String(localized: "user_menu_language_later_button", bundle: .module), role: .cancel) {
                if let code = pendingLanguageCode {
                    LanguageSwitcher.setLanguage(code)
                }
            }
        } message: {
            Text(String(localized: "user_menu_language_restart_message", bundle: .module))
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("j.conti@joseconti.com")
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            Text("v\(UpdaterService.shared.currentVersion)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Menu Items

    @ViewBuilder
    private var menuSection: some View {
        VStack(spacing: 0) {
            // Settings
            menuRow(
                id: "settings",
                icon: "gearshape",
                label: String(localized: "user_menu_settings", bundle: .module)
            ) {
                onDismiss()
                onSettings()
            }

            // Language
            menuRow(
                id: "language",
                icon: "globe",
                label: String(localized: "user_menu_language", bundle: .module),
                trailing: {
                    Image(systemName: showLanguages ? "chevron.up" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLanguages.toggle()
                }
            }

            // Language submenu (inline expand)
            if showLanguages {
                languageSubmenu
            }

            // Help
            menuRow(
                id: "help",
                icon: "questionmark.circle",
                label: String(localized: "user_menu_help", bundle: .module)
            ) {
                onDismiss()
                onHelp()
            }

            // License
            menuRow(
                id: "license",
                icon: "doc.text",
                label: String(localized: "user_menu_license", bundle: .module)
            ) {
                onDismiss()
                LicenseWindowController.shared.show()
            }

            // Disclaimer
            menuRow(
                id: "disclaimer",
                icon: "exclamationmark.triangle",
                label: String(localized: "user_menu_disclaimer", bundle: .module)
            ) {
                onDismiss()
                DisclaimerWindowController.shared.show()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Language Submenu

    @ViewBuilder
    private var languageSubmenu: some View {
        VStack(spacing: 0) {
            // System Default
            languageRow(
                code: nil,
                name: String(localized: "user_menu_language_system", bundle: .module),
                isSelected: LanguageSwitcher.currentOverride == nil
            )

            // Available languages from bundle
            ForEach(LanguageSwitcher.availableLanguages, id: \.code) { lang in
                languageRow(
                    code: lang.code,
                    name: lang.nativeName,
                    isSelected: LanguageSwitcher.currentOverride == lang.code
                )
            }
        }
        .padding(.leading, 28)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func languageRow(code: String?, name: String, isSelected: Bool) -> some View {
        let itemId = "lang_\(code ?? "system")"
        Button {
            pendingLanguageCode = code
            showRestartAlert = true
        } label: {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 16)
                } else {
                    Spacer()
                        .frame(width: 16)
                }

                Text(name)
                    .font(.callout)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(hoveredItem == itemId ? Theme.hoverBackground : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredItem = isHovered ? itemId : nil
        }
    }

    // MARK: - Promotional Section

    @ViewBuilder
    private var promotionalSection: some View {
        VStack(spacing: 0) {
            // Section header
            Text(String(localized: "user_menu_get_more", bundle: .module))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // McClaw Mobile (coming soon)
            promoRow(
                id: "mobile",
                icon: "iphone",
                label: String(localized: "user_menu_mobile_app", bundle: .module),
                badge: String(localized: "user_menu_coming_soon", bundle: .module)
            ) {
                // No action yet — coming soon
            }

            // MCP Content Manager
            promoRow(
                id: "mcp_cm",
                icon: "link.circle",
                label: String(localized: "user_menu_mcp_content_manager", bundle: .module)
            ) {
                onDismiss()
                NSWorkspace.shared.open(URL(string: "https://plugins.joseconti.com/product/mcp-content-manager-for-wordpress/")!)
            }

            // Smart AI Translate
            promoRow(
                id: "translate",
                icon: "link.circle",
                label: String(localized: "user_menu_smart_translate", bundle: .module)
            ) {
                onDismiss()
                NSWorkspace.shared.open(URL(string: "https://plugins.joseconti.com/en/product/smart-ai-translate-for-wp-translate-wordpress-and-woocommerce-with-artificial-intelligence/")!)
            }

            // More by José Conti
            promoRow(
                id: "more",
                icon: "link.circle",
                label: String(localized: "user_menu_more_products", bundle: .module)
            ) {
                onDismiss()
                NSWorkspace.shared.open(URL(string: "https://plugins.joseconti.com/en")!)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Row Helpers

    @ViewBuilder
    private func menuRow<Trailing: View>(
        id: String,
        icon: String,
        label: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(label)
                    .font(.callout)
                    .foregroundStyle(.primary)

                Spacer()

                trailing()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(hoveredItem == id ? Theme.hoverBackground : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { isHovered in
            hoveredItem = isHovered ? id : nil
        }
    }

    @ViewBuilder
    private func promoRow(
        id: String,
        icon: String,
        label: String,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.8))
                        .clipShape(Capsule())
                }

                if badge == nil {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(hoveredItem == id ? Theme.hoverBackground : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { isHovered in
            hoveredItem = isHovered ? id : nil
        }
    }
}
