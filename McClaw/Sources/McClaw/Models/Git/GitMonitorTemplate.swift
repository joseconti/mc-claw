import Foundation

/// Pre-defined templates for automated Git repository monitoring via CronJobs.
struct GitMonitorTemplate: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let defaultCronExpression: String
    let promptTemplate: String

    /// All available monitor templates.
    static let allTemplates: [GitMonitorTemplate] = [
        GitMonitorTemplate(
            id: "pr-reviewer",
            name: String(localized: "git_monitor_pr_reviewer", bundle: .module),
            description: String(localized: "git_monitor_pr_reviewer_desc", bundle: .module),
            icon: "arrow.triangle.pull",
            defaultCronExpression: "0 9 * * 1-5",
            promptTemplate: "List all open PRs in {{repo}} that need review. Flag PRs older than 3 days. For each PR, show: number, title, author, age, and review status."
        ),
        GitMonitorTemplate(
            id: "ci-watcher",
            name: String(localized: "git_monitor_ci_watcher", bundle: .module),
            description: String(localized: "git_monitor_ci_watcher_desc", bundle: .module),
            icon: "gearshape.2",
            defaultCronExpression: "*/30 * * * *",
            promptTemplate: "Check if any CI pipeline has failed on the default branch of {{repo}}. If so, report which commit caused the failure and who authored it."
        ),
        GitMonitorTemplate(
            id: "stale-branches",
            name: String(localized: "git_monitor_stale_branches", bundle: .module),
            description: String(localized: "git_monitor_stale_branches_desc", bundle: .module),
            icon: "arrow.triangle.branch",
            defaultCronExpression: "0 10 * * 1",
            promptTemplate: "List branches in {{repo}} with no activity in the last 30 days. Suggest which ones can be safely deleted."
        ),
        GitMonitorTemplate(
            id: "security-scan",
            name: String(localized: "git_monitor_security_scan", bundle: .module),
            description: String(localized: "git_monitor_security_scan_desc", bundle: .module),
            icon: "lock.shield",
            defaultCronExpression: "0 8 * * 0",
            promptTemplate: "Scan {{repo}} for potential security issues: hardcoded secrets in recent commits, vulnerable dependency patterns, insecure configurations. Report findings with severity."
        ),
        GitMonitorTemplate(
            id: "activity-summary",
            name: String(localized: "git_monitor_activity_summary", bundle: .module),
            description: String(localized: "git_monitor_activity_summary_desc", bundle: .module),
            icon: "chart.bar",
            defaultCronExpression: "0 17 * * 5",
            promptTemplate: "Generate a weekly activity summary for {{repo}}: total commits, PRs merged, issues closed, most active contributors, and most changed areas of the codebase."
        ),
        GitMonitorTemplate(
            id: "issue-triage",
            name: String(localized: "git_monitor_issue_triage", bundle: .module),
            description: String(localized: "git_monitor_issue_triage_desc", bundle: .module),
            icon: "circle.circle",
            defaultCronExpression: "0 10 * * 1-5",
            promptTemplate: "List new unassigned issues in {{repo}} from the last 24 hours. For each, suggest a priority level and potential assignee based on the area of code affected."
        ),
    ]
}
