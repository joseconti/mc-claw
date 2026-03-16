import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsTab: View {
    // MARK: - Export State

    @State private var isAuthenticated = false
    @State private var exportPassword = ""
    @State private var exportConfirmPassword = ""
    @State private var isExporting = false
    @State private var exportSuccess = false

    // MARK: - Import State

    @State private var importPassword = ""
    @State private var isImporting = false
    @State private var importResult: BackupImportResult?

    // MARK: - Shared

    @State private var errorMessage: String?
    @State private var showConfirmImport = false
    @State private var pendingImportURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            exportSection
            Divider().padding(.vertical, 12)
            importSection
            Spacer()
        }
        .padding(20)
        .alert(
            String(localized: "Restore Backup", bundle: .appModule),
            isPresented: $showConfirmImport
        ) {
            Button(String(localized: "Cancel", bundle: .appModule), role: .cancel) {
                pendingImportURL = nil
            }
            Button(String(localized: "Restore", bundle: .appModule), role: .destructive) {
                performImport()
            }
        } message: {
            Text("This will replace all current settings, credentials, sessions, projects, schedules, paired devices, and learning data. This action cannot be undone.", bundle: .appModule)
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Export Backup", bundle: .appModule), systemImage: "square.and.arrow.up")
                .font(.headline)

            Text("Export everything: settings, connectors, credentials, sessions, projects, skills, schedules, paired devices, learning data, and all app data to a single encrypted file.", bundle: .appModule)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !isAuthenticated {
                // Step 1: Authenticate with Touch ID / macOS password
                Button {
                    authenticateForExport()
                } label: {
                    Label(String(localized: "Authenticate to Export", bundle: .appModule), systemImage: "touchid")
                }
                .buttonStyle(.borderedProminent)
            } else {
                // Step 2: After authentication, show encryption password fields
                VStack(alignment: .leading, spacing: 8) {
                    SecureField(String(localized: "Encryption password", bundle: .appModule), text: $exportPassword)
                        .mcclawTextField()

                    SecureField(String(localized: "Confirm password", bundle: .appModule), text: $exportConfirmPassword)
                        .mcclawTextField()
                }
                .frame(maxWidth: 360)

                if !exportPasswordsMatch && !exportConfirmPassword.isEmpty {
                    Text("Passwords do not match", bundle: .appModule)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                HStack(spacing: 12) {
                    Button {
                        startExport()
                    } label: {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                            Text("Exporting…", bundle: .appModule)
                        } else {
                            Text("Export…", bundle: .appModule)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canExport || isExporting)

                    if exportSuccess {
                        Label(String(localized: "Backup exported successfully", bundle: .appModule), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Restore from Backup", bundle: .appModule), systemImage: "square.and.arrow.down")
                .font(.headline)

            Text("Restore everything from a previously exported .mcb backup file.", bundle: .appModule)
                .font(.callout)
                .foregroundStyle(.secondary)

            SecureField(String(localized: "Encryption password", bundle: .appModule), text: $importPassword)
                .mcclawTextField()
                .frame(maxWidth: 360)

            HStack(spacing: 12) {
                Button {
                    chooseImportFile()
                } label: {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                        Text("Restoring…", bundle: .appModule)
                    } else {
                        Text("Import…", bundle: .appModule)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(importPassword.isEmpty || isImporting)

                if let result = importResult {
                    Label(
                        String(localized: "Restored: \(result.filesRestored) files, \(result.credentialsRestored) credentials", bundle: .appModule),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    .font(.callout)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if let warnings = importResult?.warnings, !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Warnings:", bundle: .appModule)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    ForEach(warnings, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private var canExport: Bool {
        isAuthenticated && !exportPassword.isEmpty && exportPasswordsMatch
    }

    private var exportPasswordsMatch: Bool {
        exportPassword == exportConfirmPassword
    }

    private func authenticateForExport() {
        errorMessage = nil
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Fallback: if biometrics/password not available, allow export directly
            isAuthenticated = true
            return
        }

        let reason = String(localized: "Authenticate to export your McClaw configuration", bundle: .appModule)
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authError in
            DispatchQueue.main.async {
                if success {
                    isAuthenticated = true
                } else if let authError {
                    errorMessage = authError.localizedDescription
                }
            }
        }
    }

    private func startExport() {
        exportSuccess = false
        errorMessage = nil

        let panel = NSSavePanel()
        panel.title = String(localized: "Export McClaw Backup", bundle: .appModule)
        panel.nameFieldStringValue = "mcclaw-backup.mcb"
        panel.allowedContentTypes = [.init(filenameExtension: "mcb") ?? .data]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        let password = exportPassword

        Task {
            do {
                let data = try await BackupService.shared.exportBackup(password: password)
                try data.write(to: url, options: .atomic)
                isExporting = false
                exportSuccess = true
                exportPassword = ""
                exportConfirmPassword = ""
                isAuthenticated = false
            } catch {
                isExporting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseImportFile() {
        errorMessage = nil
        importResult = nil

        let panel = NSOpenPanel()
        panel.title = String(localized: "Select McClaw Backup", bundle: .appModule)
        panel.allowedContentTypes = [.init(filenameExtension: "mcb") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        pendingImportURL = url
        showConfirmImport = true
    }

    private func performImport() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        isImporting = true
        let password = importPassword

        Task {
            do {
                let data = try Data(contentsOf: url)
                let result = try await BackupService.shared.importBackup(data: data, password: password)
                isImporting = false
                importResult = result
                importPassword = ""

                // Reload all stores after import
                ConnectorStore.shared.start()
                SessionStore.shared.refreshIndex()
                ProjectStore.shared.refreshIndex()
                ImageIndexStore.shared.refreshIndex()
                DevicePairingService.shared.reloadFromDisk()
                await CronJobsStore.shared.refreshJobs()
                if let config = await ConfigStore.shared.loadConfig() {
                    await ConfigStore.shared.applyToState(config)
                }
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
