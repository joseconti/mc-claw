import Foundation

/// Centralized prompt templates for contextual AI actions on Git elements.
/// Every template MUST instruct the AI to use McClaw's @git and @fetch commands
/// instead of trying to use external tools or APIs directly.
enum GitPromptTemplates {

    // MARK: - Pull Request Actions

    static func reviewPR(_ pr: GitPRInfo) -> String {
        """
        Review PR #\(pr.number) '\(pr.title)' in detail using McClaw's tools.
        Use these commands to gather the information:
        @fetch(github.get_pr, repo=\(pr.repoFullName), number=\(pr.number))
        @fetch(github.get_pr_diff, repo=\(pr.repoFullName), number=\(pr.number))

        With that data, analyze the diff for bugs, security issues, performance problems, and style inconsistencies. Be specific about file names and line numbers.
        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func summarizePR(_ pr: GitPRInfo) -> String {
        """
        Summarize what PR #\(pr.number) '\(pr.title)' does using McClaw's tools.
        Use these commands:
        @fetch(github.get_pr, repo=\(pr.repoFullName), number=\(pr.number))
        @fetch(github.get_pr_diff, repo=\(pr.repoFullName), number=\(pr.number))

        With that data, explain the changes in non-technical terms that anyone on the team can understand.
        Do NOT use WebFetch or external APIs — use only the @fetch commands above.
        """
    }

    static func suggestImprovementsPR(_ pr: GitPRInfo) -> String {
        """
        Look at PR #\(pr.number) '\(pr.title)' and suggest improvements using McClaw's tools.
        Use these commands:
        @fetch(github.get_pr, repo=\(pr.repoFullName), number=\(pr.number))
        @fetch(github.get_pr_diff, repo=\(pr.repoFullName), number=\(pr.number))

        With that data, suggest concrete improvements focusing on readability, maintainability, and edge cases. Reference specific files and lines.
        Do NOT use WebFetch or external APIs — use only the @fetch commands above.
        """
    }

    static func checkConflictsPR(_ pr: GitPRInfo) -> String {
        """
        Check if PR #\(pr.number) from '\(pr.sourceBranch)' to '\(pr.targetBranch)' has merge conflicts using McClaw's tools.
        Use these commands:
        @fetch(github.get_pr, repo=\(pr.repoFullName), number=\(pr.number))
        @git(log --oneline \(pr.targetBranch)..\(pr.sourceBranch))

        With that data, explain what conflicts exist and how to resolve them.
        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func postReviewPR(_ pr: GitPRInfo) -> String {
        """
        Write and post a review comment for PR #\(pr.number) '\(pr.title)' using McClaw's tools.
        First, analyze the PR:
        @fetch(github.get_pr, repo=\(pr.repoFullName), number=\(pr.number))
        @fetch(github.get_pr_diff, repo=\(pr.repoFullName), number=\(pr.number))

        Then post the review:
        @fetch(github.create_pr_review, repo=\(pr.repoFullName), number=\(pr.number), body=YOUR_REVIEW, event=COMMENT)

        Be constructive and specific. Reference file names and line numbers.
        Do NOT use WebFetch or external APIs — use only the @fetch commands above.
        """
    }

    static func mergePR(_ pr: GitPRInfo) -> String {
        """
        Merge PR #\(pr.number) '\(pr.title)' into \(pr.targetBranch) using McClaw's tools.
        First check the PR status:
        @fetch(github.get_pr, repo=\(pr.repoFullName), number=\(pr.number))

        If it's ready to merge, proceed:
        @fetch(github.merge_pr, repo=\(pr.repoFullName), number=\(pr.number))

        Report the result.
        Do NOT use WebFetch or external APIs — use only the @fetch commands above.
        """
    }

    // MARK: - Issue Actions

    static func analyzeIssue(_ issue: GitIssueInfo) -> String {
        """
        Analyze issue #\(issue.number) '\(issue.title)' using McClaw's tools.
        Use these commands:
        @fetch(github.get_issue, repo=\(issue.repoFullName), number=\(issue.number))
        @git(ls-tree -r --name-only HEAD | head -60)
        @git(grep -rn '\(issue.title.components(separatedBy: " ").prefix(3).joined(separator: "\\|"))' -- ':(exclude)*.lock' | head -20)

        With that data, suggest where the fix should be made and what approach to take.
        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func suggestFixIssue(_ issue: GitIssueInfo) -> String {
        """
        Propose a fix for issue #\(issue.number) '\(issue.title)' using McClaw's tools.
        Use these commands:
        @fetch(github.get_issue, repo=\(issue.repoFullName), number=\(issue.number))
        @git(ls-tree -r --name-only HEAD | head -60)

        With that data, search the codebase using @git(grep ...) to find the relevant files, then propose a specific code fix showing the files that need to change and what the changes should be.
        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func createBranchForIssue(_ issue: GitIssueInfo) -> String {
        let slug = issue.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(40)
        return """
        Create a branch to work on issue #\(issue.number) using McClaw's tools.
        Use these commands:
        @git(checkout -b fix/\(issue.number)-\(slug))

        Confirm the branch was created and tell me I'm ready to start working on the issue.
        Do NOT use external tools — use only the @git command above.
        """
    }

    static func closeIssue(_ issue: GitIssueInfo) -> String {
        """
        Close issue #\(issue.number) '\(issue.title)' using McClaw's tools.
        Use this command:
        @fetch(github.update_issue, repo=\(issue.repoFullName), number=\(issue.number), state=closed)

        Add a comment summarizing the resolution:
        @fetch(github.create_issue_comment, repo=\(issue.repoFullName), number=\(issue.number), body=YOUR_SUMMARY)

        Do NOT use WebFetch or external APIs — use only the @fetch commands above.
        """
    }

    static func findRelatedIssues(_ issue: GitIssueInfo) -> String {
        """
        Find issues related to #\(issue.number) '\(issue.title)' using McClaw's tools.
        Use these commands:
        @fetch(github.get_issue, repo=\(issue.repoFullName), number=\(issue.number))
        @fetch(github.list_issues, repo=\(issue.repoFullName), state=open)

        With that data, identify duplicates or dependencies among the open issues.
        Do NOT use WebFetch or external APIs — use only the @fetch commands above.
        """
    }

    // MARK: - Commit Actions

    static func explainCommit(_ commit: GitCommitInfo) -> String {
        """
        Explain what commit \(commit.shortSha) '\(commit.message)' does using McClaw's tools.
        Use these commands:
        @git(show \(commit.id) --stat)
        @git(show \(commit.id) --no-stat)

        With that data, walk me through each changed file and explain why the changes were made.
        Do NOT use WebFetch or external APIs — use only the @git commands above.
        """
    }

    static func analyzeImpactCommit(_ commit: GitCommitInfo) -> String {
        """
        Analyze the impact of commit \(commit.shortSha) using McClaw's tools.
        Use these commands:
        @git(show \(commit.id) --stat)
        @git(show \(commit.id) --no-stat)
        @git(log --oneline -5 \(commit.id)..HEAD)

        With that data, tell me what parts of the system it affects and whether it could break anything.
        Do NOT use WebFetch or external APIs — use only the @git commands above.
        """
    }

    static func revertCommit(_ commit: GitCommitInfo) -> String {
        """
        Revert commit \(commit.shortSha) '\(commit.message)' using McClaw's tools.
        First, show me what will be reverted:
        @git(show \(commit.id) --stat)

        Then ask for my confirmation before executing:
        @git-confirm(revert \(commit.id))

        Do NOT use external tools — use only the @git and @git-confirm commands above.
        """
    }

    static func cherryPickCommit(_ commit: GitCommitInfo) -> String {
        """
        Cherry-pick commit \(commit.shortSha) to the current branch using McClaw's tools.
        First, show me what will be cherry-picked:
        @git(show \(commit.id) --stat)
        @git(branch --show-current)

        Then ask for my confirmation before executing:
        @git-confirm(cherry-pick \(commit.id))

        Do NOT use external tools — use only the @git and @git-confirm commands above.
        """
    }

    // MARK: - Branch Actions

    static func compareBranch(_ branch: GitBranch, defaultBranch: String) -> String {
        """
        Compare branch '\(branch.name)' with '\(defaultBranch)' using McClaw's tools.
        Use these commands:
        @git(log --oneline \(defaultBranch)..\(branch.name))
        @git(diff --stat \(defaultBranch)...\(branch.name))

        With that data, show me what's different and summarize the changes.
        Do NOT use WebFetch or external APIs — use only the @git commands above.
        """
    }

    static func createPRFromBranch(_ branch: GitBranch, defaultBranch: String) -> String {
        """
        Create a pull request from '\(branch.name)' to '\(defaultBranch)' using McClaw's tools.
        First, gather the commits to generate a good title and description:
        @git(log --oneline \(defaultBranch)..\(branch.name))
        @git(diff --stat \(defaultBranch)...\(branch.name))

        Then create the PR:
        @fetch(github.create_pr, head=\(branch.name), base=\(defaultBranch), title=YOUR_TITLE, body=YOUR_DESCRIPTION)

        Do NOT use WebFetch or external APIs — use only the @git and @fetch commands above.
        """
    }

    static func deleteBranch(_ branch: GitBranch) -> String {
        """
        Delete branch '\(branch.name)' using McClaw's tools.
        First, check if the branch has unmerged commits:
        @git(log --oneline main..\(branch.name))

        Then ask for my confirmation before deleting:
        @git-confirm(branch -d \(branch.name))

        If there are unmerged commits, warn me and ask if I want to force-delete with -D instead.
        Do NOT use external tools — use only the @git and @git-confirm commands above.
        """
    }

    static func mergeBranch(_ branch: GitBranch, currentBranch: String) -> String {
        """
        Merge branch '\(branch.name)' into '\(currentBranch)' using McClaw's tools.
        First, show me what will be merged:
        @git(log --oneline \(currentBranch)..\(branch.name))
        @git(diff --stat \(currentBranch)...\(branch.name))

        Then ask for my confirmation:
        @git-confirm(merge \(branch.name))

        Do NOT use external tools — use only the @git and @git-confirm commands above.
        """
    }

    // MARK: - File Actions

    static func explainFile(_ filePath: String) -> String {
        """
        Explain what this file does using McClaw's tools.
        Use this command to read the file:
        @git(show HEAD:\(filePath))

        With that data, describe its purpose, main classes/functions, and how it fits in the architecture.
        Do NOT use WebFetch or external APIs — use only the @git command above.
        """
    }

    static func findUsagesFile(_ filePath: String) -> String {
        let filename = (filePath as NSString).lastPathComponent
        let nameWithoutExt = (filename as NSString).deletingPathExtension
        return """
        Find all files that use code from \(filePath) using McClaw's tools.
        Use these commands:
        @git(grep -rn '\(nameWithoutExt)' -- ':(exclude)*.lock' ':(exclude)node_modules' | head -40)

        With that data, list all files that import or reference this module, grouped by type of usage.
        Do NOT use WebFetch or external APIs — use only the @git command above.
        """
    }

    static func suggestImprovementsFile(_ filePath: String) -> String {
        """
        Review \(filePath) and suggest improvements using McClaw's tools.
        Use this command to read the file:
        @git(show HEAD:\(filePath))

        With that data, identify refactoring opportunities, potential bugs, missing error handling, and performance issues. Be specific about line numbers.
        Do NOT use WebFetch or external APIs — use only the @git command above.
        """
    }

    static func writeTestsFile(_ filePath: String) -> String {
        """
        Write unit tests for \(filePath) using McClaw's tools.
        First, read the file:
        @git(show HEAD:\(filePath))

        Then check the project's existing test patterns:
        @git(ls-tree -r --name-only HEAD | grep -i test | head -10)

        With that data, write unit tests for the main functions using the testing framework this project already uses.
        Do NOT use WebFetch or external APIs — use only the @git commands above.
        """
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

    // MARK: - Quick Actions (used by panels and menus)

    static func pullLatest() -> String {
        """
        Pull the latest changes from the remote using McClaw's tools.
        First, check the current state:
        @git(status --short)
        @git(remote -v)

        Then pull:
        @git-confirm(pull)

        Report the result: new commits pulled, files changed, or if already up to date.
        Do NOT use external tools — use only the @git and @git-confirm commands above.
        """
    }

    static func createBranch() -> String {
        """
        Help me create a new branch using McClaw's tools.
        First, check the current state:
        @git(branch --show-current)
        @git(branch -a | head -20)

        Ask me what feature or fix I'm working on and suggest a good branch name. When I approve, create the branch:
        @git-confirm(checkout -b BRANCH_NAME)

        Do NOT use external tools — use only the @git and @git-confirm commands above.
        """
    }

    static func reviewOpenPRs(_ repoName: String) -> String {
        """
        List all open PRs in \(repoName) using McClaw's tools.
        Use this command:
        @fetch(github.list_prs, repo=\(repoName), state=open)

        With that data, give me a summary of each PR: title, author, age, and whether it needs attention (conflicts, stale, no reviews).
        Do NOT use WebFetch or external APIs — use only the @fetch command above.
        """
    }

    // MARK: - Merge Conflict Resolution

    static func mergeConflictResolution() -> String {
        """
        Help me resolve merge conflicts using McClaw's tools.
        Use these commands to identify the conflicts:
        @git(status --short)
        @git(diff --name-only --diff-filter=U)

        For each conflicted file, examine the content:
        @git(diff FILE_PATH)

        Then:
        1. Analyze the intent of both changes using commit messages for context
        2. Propose a resolution for each conflict, explaining your reasoning
        3. After I approve, stage the resolved files using @git-confirm

        Do NOT use external tools — use only the @git and @git-confirm commands above.
        """
    }
}
