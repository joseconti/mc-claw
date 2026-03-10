import AppKit
import SwiftUI

/// First-run wizard that detects CLIs and configures the app.
struct OnboardingWizard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: OnboardingPage = .welcome
    @State private var detectedCLIs: [CLIProviderInfo] = []
    @State private var isScanning = false
    @State private var emailInput: String = ""
    @State private var isFetchingAvatar = false
    @State private var avatarPreview: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch currentPage {
                case .welcome:
                    welcomePage
                case .profile:
                    profilePage
                case .cliDetection:
                    cliDetectionPage
                case .cliSelection:
                    cliSelectionPage
                case .permissions:
                    permissionsPage
                case .done:
                    donePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation
            HStack {
                if currentPage != .welcome {
                    Button("Back") {
                        currentPage = currentPage.previous
                    }
                }
                Spacer()
                Button(currentPage == .done ? "Get Started" : "Continue") {
                    if currentPage == .done {
                        completeOnboarding()
                    } else {
                        currentPage = currentPage.next
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentPage == .cliDetection && isScanning)
            }
            .padding()
        }
        .frame(width: 520, height: 440)
    }

    // MARK: - Pages

    @ViewBuilder
    private var welcomePage: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain")
                .font(.system(size: 60))
                .foregroundStyle(.purple)

            Text("Welcome to McClaw")
                .font(.largeTitle.weight(.bold))

            Text("Your native macOS AI assistant. McClaw works with the official CLI tools from AI providers installed on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .padding()
    }

    @ViewBuilder
    private var profilePage: some View {
        VStack(spacing: 20) {
            Text("Your Profile")
                .font(.title2.weight(.semibold))

            Text("Enter your email to load your avatar from Gravatar. Your email is never sent to any server, never shared with third parties, and is only stored locally on your Mac. It is used exclusively to download your avatar image for a better experience.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            // Privacy notice
            Label("Your email stays on your device. Only a hash is used to fetch the avatar.", systemImage: "lock.shield")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 380)

            // Avatar preview
            Group {
                if let image = avatarPreview {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Circle()
                        .fill(.blue.gradient)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())

            HStack(spacing: 10) {
                TextField("your@email.com", text: $emailInput)
                    .mcclawTextField()
                    .frame(maxWidth: 260)
                    .onSubmit { fetchAvatarPreview() }

                Button {
                    fetchAvatarPreview()
                } label: {
                    if isFetchingAvatar {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Load Avatar")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(emailInput.isEmpty || isFetchingAvatar)
            }

            Text("This is completely optional. If you skip it, your initials will be used as avatar.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func fetchAvatarPreview() {
        guard !emailInput.isEmpty else { return }
        isFetchingAvatar = true
        Task {
            let updated = await GravatarService.shared.fetchAvatar(for: emailInput)
            if updated || GravatarService.shared.cachedImage != nil {
                avatarPreview = GravatarService.shared.cachedImage
                appState.userEmail = emailInput
                appState.userAvatarImage = avatarPreview
            }
            isFetchingAvatar = false
        }
    }

    @ViewBuilder
    private var cliDetectionPage: some View {
        VStack(spacing: 16) {
            Text("Detecting AI CLIs")
                .font(.title2.weight(.semibold))

            Text("McClaw will scan your system for installed AI provider CLIs.")
                .foregroundStyle(.secondary)

            if isScanning {
                ProgressView("Scanning...")
            } else if detectedCLIs.isEmpty {
                Button("Scan Now") {
                    scanForCLIs()
                }
                .buttonStyle(.borderedProminent)
            } else {
                List(detectedCLIs) { cli in
                    HStack {
                        Text(cli.displayName)
                        Spacer()
                        if cli.isInstalled {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline)
                        } else {
                            Button("Install") {
                                // TODO: trigger installation
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .onAppear {
            if detectedCLIs.isEmpty {
                scanForCLIs()
            }
        }
    }

    @ViewBuilder
    private var cliSelectionPage: some View {
        VStack(spacing: 16) {
            Text("Select Default CLI")
                .font(.title2.weight(.semibold))

            Text("Choose which AI provider to use by default.")
                .foregroundStyle(.secondary)

            let installed = detectedCLIs.filter(\.isInstalled)
            if installed.isEmpty {
                Text("No CLIs detected. Please install at least one AI provider CLI.")
                    .foregroundStyle(.orange)
            } else {
                @Bindable var state = appState
                Picker("Default Provider", selection: $state.currentCLIIdentifier) {
                    ForEach(installed) { cli in
                        Text(cli.displayName).tag(Optional(cli.id))
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .padding()
    }

    @State private var permissionManager = PermissionManager.shared

    @ViewBuilder
    private var permissionsPage: some View {
        VStack(spacing: 16) {
            Text("Permissions")
                .font(.title2.weight(.semibold))

            Text("McClaw needs certain permissions for some features. All are optional — you can grant them later in Settings.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                OnboardingPermissionRow(
                    icon: "mic",
                    title: "Microphone",
                    description: "Voice input and speech recognition",
                    status: permissionManager.microphoneStatus
                ) {
                    Task { _ = await permissionManager.requestMicrophone() }
                }
                OnboardingPermissionRow(
                    icon: "camera",
                    title: "Camera",
                    description: "Node mode visual capture",
                    status: permissionManager.cameraStatus
                ) {
                    Task { _ = await permissionManager.requestCamera() }
                }
                OnboardingPermissionRow(
                    icon: "bell",
                    title: "Notifications",
                    description: "Message and cron alerts",
                    status: permissionManager.notificationsStatus
                ) {
                    Task { _ = await permissionManager.requestNotifications() }
                }
            }
            .frame(maxWidth: 380)
        }
        .padding()
        .onAppear { permissionManager.refreshAll() }
    }


    @ViewBuilder
    private var donePage: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("All Set!")
                .font(.title.weight(.bold))

            Text("McClaw is ready to use. Access it from the menu bar icon.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Actions

    private func scanForCLIs() {
        isScanning = true
        Task {
            let detector = CLIDetector()
            detectedCLIs = await detector.scan()
            appState.availableCLIs = detectedCLIs
            isScanning = false
        }
    }

    private func completeOnboarding() {
        appState.hasCompletedOnboarding = true
        appState.showOnboarding = false
        dismiss()

        Task {
            // Save config to persist onboarding completion
            await ConfigStore.shared.saveFromState()
        }
    }
}

/// A row showing a permission with icon and description.
struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Permission row with real request button for onboarding.
struct OnboardingPermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status == .granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if status == .notDetermined {
                Button("Allow") { onRequest() }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            } else {
                Text("Denied")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Onboarding Page Enum

enum OnboardingPage: Int, CaseIterable {
    case welcome
    case profile
    case cliDetection
    case cliSelection
    case permissions
    case done

    var next: OnboardingPage {
        OnboardingPage(rawValue: rawValue + 1) ?? .done
    }

    var previous: OnboardingPage {
        OnboardingPage(rawValue: rawValue - 1) ?? .welcome
    }
}
