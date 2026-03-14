import Foundation

/// Centralized prompt templates for contextual AI actions on Git elements.
/// Each template uses `{{placeholder}}` syntax for dynamic values.
enum GitPromptTemplates {

    // MARK: - Pull Request Actions

    static func reviewPR(_ pr: GitPRInfo) -> String {
        "Review PR #\(pr.number) '\(pr.title)' in detail. Analyze the diff for bugs, security issues, performance problems, and style inconsistencies. Be specific about line numbers."
    }

    static func summarizePR(_ pr: GitPRInfo) -> String {
        "Summarize what PR #\(pr.number) '\(pr.title)' does. Explain the changes in non-technical terms."
    }

    static func suggestImprovementsPR(_ pr: GitPRInfo) -> String {
        "Look at PR #\(pr.number) '\(pr.title)' and suggest concrete improvements to the code. Focus on readability, maintainability, and edge cases."
    }

    static func checkConflictsPR(_ pr: GitPRInfo) -> String {
        "Check if PR #\(pr.number) from '\(pr.sourceBranch)' to '\(pr.targetBranch)' has merge conflicts. If so, explain what conflicts exist and how to resolve them."
    }

    static func postReviewPR(_ pr: GitPRInfo) -> String {
        "Write a review comment for PR #\(pr.number) '\(pr.title)' and post it. Be constructive and specific."
    }

    static func mergePR(_ pr: GitPRInfo) -> String {
        "Merge PR #\(pr.number) '\(pr.title)' into \(pr.targetBranch)."
    }

    // MARK: - Issue Actions

    static func analyzeIssue(_ issue: GitIssueInfo) -> String {
        "Analyze issue #\(issue.number) '\(issue.title)'. Based on the codebase, suggest where the fix should be made and what approach to take."
    }

    static func suggestFixIssue(_ issue: GitIssueInfo) -> String {
        "For issue #\(issue.number) '\(issue.title)', search the codebase and propose a specific code fix. Show me the files that need to change and what the changes should be."
    }

    static func createBranchForIssue(_ issue: GitIssueInfo) -> String {
        let slug = issue.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(40)
        return "Create a branch named 'fix/\(issue.number)-\(slug)' to work on issue #\(issue.number)."
    }

    static func closeIssue(_ issue: GitIssueInfo) -> String {
        "Close issue #\(issue.number) '\(issue.title)' with a comment summarizing the resolution."
    }

    static func findRelatedIssues(_ issue: GitIssueInfo) -> String {
        "Find issues in this repo that are related to issue #\(issue.number) '\(issue.title)'. Look for duplicates or dependencies."
    }

    // MARK: - Commit Actions

    static func explainCommit(_ commit: GitCommitInfo) -> String {
        "Explain what commit \(commit.shortSha) '\(commit.message)' does in detail. Walk me through each changed file and why."
    }

    static func analyzeImpactCommit(_ commit: GitCommitInfo) -> String {
        "Analyze the impact of commit \(commit.shortSha). What parts of the system does it affect? Could it break anything?"
    }

    static func revertCommit(_ commit: GitCommitInfo) -> String {
        "Revert commit \(commit.shortSha) '\(commit.message)'."
    }

    static func cherryPickCommit(_ commit: GitCommitInfo) -> String {
        "Cherry-pick commit \(commit.shortSha) to the current branch."
    }

    // MARK: - Branch Actions

    static func compareBranch(_ branch: GitBranch, defaultBranch: String) -> String {
        "Compare branch '\(branch.name)' with '\(defaultBranch)'. Show me what's different and summarize the changes."
    }

    static func createPRFromBranch(_ branch: GitBranch, defaultBranch: String) -> String {
        "Create a pull request from '\(branch.name)' to '\(defaultBranch)'. Generate a good title and description based on the commits."
    }

    static func deleteBranch(_ branch: GitBranch) -> String {
        "Delete branch '\(branch.name)' both locally and on the remote."
    }

    static func mergeBranch(_ branch: GitBranch, currentBranch: String) -> String {
        "Merge branch '\(branch.name)' into the current branch '\(currentBranch)'."
    }

    // MARK: - File Actions

    static func explainFile(_ filePath: String) -> String {
        "Explain what this file does: \(filePath). Describe its purpose, main classes/functions, and how it fits in the architecture."
    }

    static func findUsagesFile(_ filePath: String) -> String {
        "Find all files in this repo that import or use code from \(filePath)."
    }

    static func suggestImprovementsFile(_ filePath: String) -> String {
        "Review \(filePath) and suggest improvements: refactoring opportunities, potential bugs, missing error handling, performance issues."
    }

    static func writeTestsFile(_ filePath: String) -> String {
        "Write unit tests for the main functions in \(filePath). Use the testing framework this project already uses."
    }

    // MARK: - Line Selection

    static func askAboutLines(filePath: String, startLine: Int, endLine: Int, code: String, language: String) -> String {
        """
        Explain lines \(startLine) to \(endLine) in \(filePath):
        ```\(language)
        \(code)
        ```
        What does this code do? Are there any issues?
        """
    }

    // MARK: - Repo-Level Actions

    static func explainRepo(_ repoName: String) -> String {
        """
        Use the data already available in McClaw to analyze this repository (\(repoName)).
        Use these commands to gather information:
        @git(ls-tree -r --name-only HEAD | head -80)
        @git(log --oneline -20)
        @git(log --format=%an --all | sort -u)

        With that data, give me an onboarding guide: project structure, main technologies, architecture patterns, entry points, how to build and run it, and key files to understand.
        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func whatChangedThisWeek(_ repoName: String) -> String {
        """
        Use the data already available in McClaw to summarize recent activity in \(repoName).
        Use these commands:
        @git(log --since='7 days ago' --pretty=format:'%h %an %ad %s' --date=short)
        @git(shortlog --since='7 days ago' -sn)
        @git(diff --stat HEAD~20..HEAD)

        With that data, summarize the development activity of the last 7 days. Group by contributor and area of the codebase.
        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func whatBroke(_ repoName: String) -> String {
        """
        Use the data already available in McClaw to look for potential regressions in \(repoName).
        Use these commands:
        @git(log --oneline -20)
        @git(log --diff-filter=D --name-only --pretty=format:'%h %s' -20)
        @git(log --all --pretty=format:'%h %s' -- '*.json' '*.yml' '*.yaml' '*.plist' '*.conf' -10)

        With that data, identify recent commits that might have introduced bugs or regressions. Focus on deleted files, modified configuration, and changes to critical paths.
        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func generateChangelog(_ repoName: String) -> String {
        """
        Use the data already available in McClaw to generate release notes for \(repoName).
        Use these commands:
        @git(describe --tags --abbrev=0 2>/dev/null || echo 'no-tags')
        @git(log --oneline --no-merges $(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~30)..HEAD)

        With that data, generate release notes grouped by: New Features, Bug Fixes, Breaking Changes, Other. Use human-readable descriptions, not raw commit messages.
        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func healthCheck(_ repoName: String) -> String {
        """
        Use the data already available in McClaw to analyze the health of \(repoName).
        Use these commands:
        @git(branch -a --no-merged)
        @git(log --oneline -5)
        @fetch(github.list_issues, repo=\(repoName), state=open)
        @fetch(github.list_prs, repo=\(repoName), state=open)

        With that data, give me an actionable health summary: stale PRs, old unresolved issues, branches that should be cleaned up, and overall status.
        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func securityAudit(_ repoName: String) -> String {
        """
        Use the data already available in McClaw to scan \(repoName) for security issues.
        Use these commands:
        @git(grep -rn 'password\\|secret\\|api_key\\|token\\|private_key' -- ':(exclude)*.lock' ':(exclude)*.sum')
        @git(ls-files '*.env' '*.pem' '*.key' '.env.*')
        @git(log --oneline --diff-filter=A -- '*.env' '*.pem' '*.key' '*.secret' -10)

        With that data, report potential security issues: hardcoded secrets, sensitive files tracked in git, vulnerable patterns, and insecure configurations. Be thorough.
        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func findTodos(_ repoName: String) -> String {
        """
        Use the data already available in McClaw to find pending work items in \(repoName).
        Use this command:
        @git(grep -rn 'TODO\\|FIXME\\|HACK\\|XXX' -- ':(exclude)*.lock' ':(exclude)node_modules')

        With that data, list all TODO, FIXME, HACK, and XXX comments grouped by file, with context about what each one refers to.
        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func commitAssistant() -> String {
        """
        Help me commit my changes. Use these commands to check the state:
        @git(status --short)
        @git(diff --stat)
        @git(log --oneline -5)

        Show me what's changed, generate a good commit message following this project's conventions, and use @git-confirm to stage + commit when I approve.
        Do NOT use external tools — use only the @git commands above.
        """
    }

    // MARK: - Merge Conflict Resolution

    static func mergeConflictResolution() -> String {
        """
        Help me resolve merge conflicts. Follow these steps:
        1. Check git status to find conflicted files
        2. For each conflicted file, examine the base, ours, and theirs versions
        3. Analyze the intent of both changes using commit messages for context
        4. Propose a resolution for each conflict, explaining your reasoning
        5. After I approve, stage the resolved files
        """
    }
}
