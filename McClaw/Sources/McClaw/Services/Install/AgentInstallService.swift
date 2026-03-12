import Foundation
import Logging
import McClawKit

/// Manages the Agent Install flow: parsing install prompts via AI,
/// presenting plans for review, and executing steps with security approval.
@MainActor
@Observable
final class AgentInstallService {
    static let shared = AgentInstallService()

    var phase: AgentInstallPhase = .idle
    var currentPlan: AgentInstallPlan?
    var installRegistry: [AgentInstallRecord] = []
    /// Whether the service is currently aborting execution.
    var isAborting = false

    /// The plan currently awaiting user review, if any.
    var reviewingPlan: AgentInstallPlan? {
        if case .reviewingPlan(let plan) = phase { return plan }
        return nil
    }

    private let logger = Logger(label: "ai.mcclaw.install")

    private static var registryFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw")
            .appendingPathComponent("install-registry.json")
    }

    // MARK: - Init

    private init() {
        loadRegistry()
    }

    // MARK: - Parse Install Prompt

    /// Send the raw install prompt to the active AI CLI and parse the response
    /// into a structured install plan.
    func parseInstallPrompt(_ prompt: String) async {
        phase = .parsing
        isAborting = false

        guard let provider = AppState.shared.currentCLI,
              provider.isInstalled else {
            phase = .failed(String(localized: "No AI provider available. Please configure a CLI in Settings.", bundle: .module))
            return
        }

        let systemPrompt = InstallKit.buildParsingSystemPrompt()

        // Collect the full AI response
        var fullResponse = ""
        let stream = await CLIBridge.shared.send(
            message: prompt,
            provider: provider,
            systemPrompt: systemPrompt
        )

        for await event in stream {
            switch event {
            case .text(let chunk):
                fullResponse += chunk
            case .error(let error):
                logger.error("AI parsing error: \(error)")
                phase = .failed(error)
                return
            case .done:
                break
            default:
                break
            }
        }

        guard !fullResponse.isEmpty else {
            phase = .failed(String(localized: "No response from AI provider.", bundle: .module))
            return
        }

        // Parse the JSON response
        do {
            let parsed = try InstallKit.parseInstallPlanJSON(fullResponse)

            guard !parsed.steps.isEmpty else {
                phase = .failed(String(localized: "The install plan has no steps.", bundle: .module))
                return
            }

            // Validate for dangerous patterns
            let warnings = InstallKit.validatePlan(parsed)

            // Convert to app model
            let steps = parsed.steps.enumerated().map { index, step in
                AgentInstallStep(
                    order: index + 1,
                    description: step.description,
                    command: step.command,
                    workingDirectory: step.workingDirectory
                )
            }

            let plan = AgentInstallPlan(
                name: parsed.name,
                description: parsed.description,
                sourcePrompt: prompt,
                steps: steps,
                warnings: warnings
            )

            currentPlan = plan
            phase = .reviewingPlan(plan)
        } catch {
            logger.error("Failed to parse install plan: \(error)")
            phase = .failed(String(localized: "No install plan could be parsed from the prompt.", bundle: .module))
        }
    }

    // MARK: - Execute Plan

    /// Execute all steps in the plan sequentially, with security approval for each.
    func executePlan(_ plan: AgentInstallPlan) async {
        phase = .executing(plan)
        isAborting = false
        var updatedSteps = plan.steps

        for i in updatedSteps.indices {
            guard !isAborting else {
                updatedSteps[i].status = .skipped
                continue
            }

            updatedSteps[i].status = .running
            currentPlan = AgentInstallPlan(
                id: plan.id,
                name: plan.name,
                description: plan.description,
                sourcePrompt: plan.sourcePrompt,
                steps: updatedSteps,
                warnings: plan.warnings,
                timestamp: plan.timestamp
            )

            let (command, args) = InstallKit.splitCommand(updatedSteps[i].command)

            // Check security approval
            let approval = ExecApprovals.shared.checkApproval(command: command, arguments: args)

            switch approval {
            case .denied(let reason):
                updatedSteps[i].status = .denied
                updatedSteps[i].output = reason
                logger.info("Step \(i + 1) denied: \(reason)")
                // Stop execution on denial
                for j in (i + 1)..<updatedSteps.count {
                    updatedSteps[j].status = .skipped
                }
                break

            case .needsApproval(let fullCmd, let resolution):
                updatedSteps[i].status = .awaitingApproval
                updateCurrentPlan(plan: plan, steps: updatedSteps)

                // Request approval via the existing ExecApprovalDialog
                let request = ExecApprovalRequest(
                    command: command,
                    arguments: args,
                    resolution: resolution
                )
                ExecApprovals.shared.pendingApproval = request
                let decision = await waitForApprovalDecision()

                switch decision {
                case .deny:
                    updatedSteps[i].status = .denied
                    updatedSteps[i].output = String(localized: "Command denied by user.", bundle: .module)
                    for j in (i + 1)..<updatedSteps.count {
                        updatedSteps[j].status = .skipped
                    }
                    updateCurrentPlan(plan: plan, steps: updatedSteps)
                    let record = buildRecord(plan: plan, steps: updatedSteps)
                    persistRecord(record)
                    phase = .completed(record)
                    return

                case .allowAlways:
                    ExecApprovals.shared.addAllowlistEntry(
                        pattern: fullCmd,
                        command: fullCmd
                    )
                    updatedSteps[i].status = .running

                case .allowOnce:
                    updatedSteps[i].status = .running
                }

            case .approved:
                break
            }

            updateCurrentPlan(plan: plan, steps: updatedSteps)

            // Execute the command
            let result = await executeCommand(
                command: command,
                arguments: args,
                workingDirectory: updatedSteps[i].workingDirectory
            )

            updatedSteps[i].output = result.output
            updatedSteps[i].exitCode = result.exitCode

            if result.exitCode == 0 {
                updatedSteps[i].status = .completed
            } else {
                updatedSteps[i].status = .failed
                // Stop on failure — skip remaining steps
                for j in (i + 1)..<updatedSteps.count {
                    updatedSteps[j].status = .skipped
                }
                updateCurrentPlan(plan: plan, steps: updatedSteps)
                break
            }

            updateCurrentPlan(plan: plan, steps: updatedSteps)
        }

        let record = buildRecord(plan: plan, steps: updatedSteps)
        persistRecord(record)
        phase = .completed(record)
    }

    /// Abort the current execution.
    func abortExecution() {
        isAborting = true
    }

    /// Cancel the current flow and return to idle.
    func cancel() {
        isAborting = true
        currentPlan = nil
        phase = .idle
    }

    // MARK: - Uninstall & Registry Management

    /// Remove a record from the registry without running uninstall commands.
    func removeRecord(id: UUID) {
        installRegistry.removeAll { $0.id == id }
        saveRegistry()
    }

    /// Attempt to uninstall by running reverse commands, then remove the record.
    func uninstallRecord(id: UUID) async {
        guard let record = installRegistry.first(where: { $0.id == id }) else { return }

        // Try to generate uninstall commands from the install steps
        let uninstallCommands = generateUninstallCommands(from: record)

        for cmd in uninstallCommands {
            let (executable, args) = InstallKit.splitCommand(cmd)
            _ = await executeCommand(command: executable, arguments: args, workingDirectory: nil)
        }

        removeRecord(id: id)
    }

    /// Clear all records from the registry.
    func clearRegistry() {
        installRegistry.removeAll()
        saveRegistry()
    }

    /// Generate reverse uninstall commands from install steps.
    private func generateUninstallCommands(from record: AgentInstallRecord) -> [String] {
        var commands: [String] = []

        for step in record.steps where step.status == .completed {
            let cmd = step.command.trimmingCharacters(in: .whitespaces)

            // brew install X → brew uninstall X
            if cmd.hasPrefix("brew install ") {
                let pkg = String(cmd.dropFirst("brew install ".count))
                commands.append("brew uninstall \(pkg)")
            }
            // npm install -g X → npm uninstall -g X
            else if cmd.contains("npm install -g ") || cmd.contains("npm install --global ") {
                let cleaned = cmd
                    .replacingOccurrences(of: "npm install -g ", with: "npm uninstall -g ")
                    .replacingOccurrences(of: "npm install --global ", with: "npm uninstall --global ")
                commands.append(cleaned)
            }
            // pip install X → pip uninstall -y X
            else if cmd.hasPrefix("pip install ") || cmd.hasPrefix("pip3 install ") {
                let cleaned = cmd
                    .replacingOccurrences(of: "pip install ", with: "pip uninstall -y ")
                    .replacingOccurrences(of: "pip3 install ", with: "pip3 uninstall -y ")
                commands.append(cleaned)
            }
            // cargo install X → cargo uninstall X
            else if cmd.hasPrefix("cargo install ") {
                let pkg = String(cmd.dropFirst("cargo install ".count))
                commands.append("cargo uninstall \(pkg)")
            }
            // gem install X → gem uninstall X
            else if cmd.hasPrefix("gem install ") {
                let pkg = String(cmd.dropFirst("gem install ".count))
                commands.append("gem uninstall \(pkg)")
            }
        }

        return commands
    }

    // MARK: - Private Helpers

    private func updateCurrentPlan(plan: AgentInstallPlan, steps: [AgentInstallStep]) {
        currentPlan = AgentInstallPlan(
            id: plan.id,
            name: plan.name,
            description: plan.description,
            sourcePrompt: plan.sourcePrompt,
            steps: steps,
            warnings: plan.warnings,
            timestamp: plan.timestamp
        )
    }

    private func buildRecord(plan: AgentInstallPlan, steps: [AgentInstallStep]) -> AgentInstallRecord {
        AgentInstallRecord(
            id: plan.id,
            name: plan.name,
            description: plan.description,
            sourcePrompt: plan.sourcePrompt,
            steps: steps,
            providerId: AppState.shared.currentCLI?.id ?? "unknown"
        )
    }

    /// Wait for the user to make an approval decision via the ExecApprovalDialog.
    private func waitForApprovalDecision() async -> ExecApprovalDecision {
        await withCheckedContinuation { continuation in
            CLIBridge.pendingApprovalContinuation = continuation
        }
    }

    /// Execute a single command via Process, returning output and exit code.
    private nonisolated func executeCommand(
        command: String,
        arguments: [String],
        workingDirectory: String?
    ) async -> (output: String, exitCode: Int32) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", ([command] + arguments).joined(separator: " ")]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice

            if let dir = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: dir)
            }

            // Sanitize environment
            process.environment = HostEnvSanitizer.sanitize(isShellWrapper: true)

            do {
                try process.run()
            } catch {
                continuation.resume(returning: (output: error.localizedDescription, exitCode: -1))
                return
            }

            // Read output after process completes (avoids Sendable issues)
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            let combinedOutput = stdoutText.isEmpty ? stderrText : stdoutText

            continuation.resume(returning: (
                output: String(combinedOutput.prefix(10000)),
                exitCode: process.terminationStatus
            ))
        }
    }

    // MARK: - Registry Persistence

    private func loadRegistry() {
        let url = Self.registryFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            installRegistry = try JSONDecoder().decode([AgentInstallRecord].self, from: data)
            logger.info("Loaded \(installRegistry.count) install records")
        } catch {
            logger.error("Failed to load install registry: \(error)")
        }
    }

    private func persistRecord(_ record: AgentInstallRecord) {
        installRegistry.append(record)
        saveRegistry()
        logger.info("Persisted install record: \(record.name)")
    }

    /// Save the current registry to disk.
    private func saveRegistry() {
        let url = Self.registryFileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(installRegistry)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            logger.error("Failed to persist install registry: \(error)")
        }
    }
}
