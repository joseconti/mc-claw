import Foundation
import IOKit.pwr_mgt
import Logging

/// Prevents the Mac from going to sleep using IOKit power assertions.
@MainActor
final class SleepPreventionService {
    static let shared = SleepPreventionService()

    private let logger = Logger(label: "ai.mcclaw.sleep-prevention")
    private var assertionID: IOPMAssertionID = 0
    private var isActive = false

    private init() {}

    /// Enable or disable sleep prevention based on the current state.
    func update(enabled: Bool) {
        if enabled && !isActive {
            activate()
        } else if !enabled && isActive {
            deactivate()
        }
    }

    private func activate() {
        let reason = "McClaw is running" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isActive = true
            logger.info("Sleep prevention activated")
        } else {
            logger.warning("Failed to create sleep assertion: \(result)")
        }
    }

    private func deactivate() {
        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            isActive = false
            assertionID = 0
            logger.info("Sleep prevention deactivated")
        } else {
            logger.warning("Failed to release sleep assertion: \(result)")
        }
    }
}
