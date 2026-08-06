# GitHub Actions Workflows

This directory contains automated workflows for repository management and quality assurance.

## 📋 Active Workflows

### 1. **Issue Auto-Labeler** (`issue-labeler.yml`)

**Purpose:** Automatically labels new issues based on content analysis

**Triggers:**
- When an issue is opened
- When an issue is edited

**What it does:**
- Analyzes issue title and body for keywords
- Applies relevant technology labels (azure, intune, m365, etc.)
- Applies issue type labels (bug, enhancement, documentation, etc.)
- Applies priority labels (priority-high, good-first-issue)
- Adds a comment when multiple categories are detected
- Adds a helpful comment when no labels match

**Labels Applied** (46 total):
- **Technology** (29): azure, aws, containers, intune, winget, windows-server, active-directory, security, etc.
- **Issue Type** (6): bug, enhancement, documentation, question, performance, testing
- **Priority** (2): priority-high, good-first-issue
- **Process** (5): stale, broken-links, automated, dependencies, github-actions

**Configuration:**
- Runs automatically on every new or edited issue
- No manual intervention required
- Labels must exist in the repository (created via `.github/scripts/create-labels.ps1`)

---

### 2. **Stale Issue/PR Manager** (`stale.yml`)

**Purpose:** Automatically closes inactive issues and pull requests

**Triggers:**
- Daily at midnight UTC (scheduled)
- Manual trigger via workflow_dispatch

**What it does:**
- Marks issues inactive for 60+ days as "stale" (7-day warning)
- Marks PRs inactive for 30+ days as "stale" (7-day warning)
- Closes stale issues/PRs after 7 days if no activity
- Removes stale label if activity resumes
- Exempts important labels: pinned, security, help-wanted, good-first-issue

**Configuration:**
- `operations-per-run: 100` - Processes up to 100 items per run
- `remove-stale-when-updated: true` - Removes label when activity resumes
- `ascending: false` - Processes newest first

**Exemptions:**
- Issues with labels: `pinned`, `security`, `help-wanted`, `good-first-issue`
- PRs with labels: `pinned`, `security`, `work-in-progress`

---

### 3. **Documentation Link Checker** (`link-checker.yml`)

**Purpose:** Validates all markdown links to prevent dead links

**Triggers:**
- When markdown files are changed (push to main or claude/*)
- Pull requests targeting main
- Weekly on Sundays at midnight UTC (scheduled)
- Manual trigger via workflow_dispatch

**What it does:**
- Scans all `*.md` files for broken links
- Checks both internal and external links
- Retries failed links (3 attempts, 10s wait)
- Caches results for 1 day (based on markdown file content hash)
- Creates a GitHub issue when broken links are detected
- Uploads results as artifacts (30-day retention)

**Exclusions:**
- Social media sites: linkedin.com, twitter.com, facebook.com
- Legacy docs: `./docs` directory
- Changelog: `./CHANGELOG.md`

**Configuration:**
- `--accept 200,204,429` - Acceptable HTTP status codes
- `--timeout 20` - 20-second timeout per link
- `--max-retries 3` - Retry failed links 3 times

---

### 4. **PowerShell Script Validator** (`validate-powershell.yml`)

**Purpose:** Validates PowerShell scripts for syntax and best practices

**Triggers:**
- Push to main, develop, or claude/* branches
- Pull requests targeting main or develop
- Manual trigger via workflow_dispatch

**What it does:**
- Runs PSScriptAnalyzer on all `.ps1` files
- Validates PowerShell syntax with PSParser
- Reports errors and warnings (informational only - does not block)
- Uploads analysis results as artifacts

**Configuration:**
- Uses default PSScriptAnalyzer rules
- Checks for errors and warnings
- Always exits successfully (informational only)

**Note:** This workflow is informational and does not block PRs. It provides guidance on code quality.

---

### 5. **Wiki Sync** (`sync-wiki.yml`)

**Purpose:** Automatically syncs wiki content from repository to GitHub Wiki

**Triggers:**
- Push to main branch with changes in `wiki/` directory
- Manual trigger via workflow_dispatch

**What it does:**
- Copies all markdown files from `wiki/` directory to wiki repository
- Commits changes with descriptive message
- Links commit to triggering commit SHA

**Requirements:**
- `WIKI_TOKEN` secret must be configured
- Wiki must be enabled for the repository

---

### 6. **Claude Code** (`claude.yml`)

**Purpose:** AI-powered code review and assistance via Claude Code

**Triggers:**
- Issue comments containing `@claude`
- PR review comments containing `@claude`
- PR reviews containing `@claude`
- New issues with `@claude` in title or body

**What it does:**
- Responds to Claude Code mentions in issues and PRs
- Provides AI-powered code review and suggestions
- Can read CI results on PRs (requires `actions: read` permission)

**Configuration:**
- Requires `CLAUDE_CODE_OAUTH_TOKEN` secret
- Has access to: contents (read), pull-requests (read), issues (read), actions (read)

---

### 7. **Claude Code Review** (`claude-code-review.yml`)

**Purpose:** Automated AI code review for pull requests

**Triggers:**
- When a PR is opened
- When a PR is synchronized (new commits)

**What it does:**
- Reviews PR changes for code quality and best practices
- Checks for potential bugs and security issues
- Evaluates performance considerations
- Assesses test coverage
- Posts review as PR comment using `gh pr comment`

**Configuration:**
- Requires `CLAUDE_CODE_OAUTH_TOKEN` secret
- Restricted tool access for security: only specific `gh` commands allowed
- Uses repository's `CLAUDE.md` for style guidance

**Note:** Currently configured to run on all PRs. Can be filtered by author or file paths if needed.

---

## 🚀 Setup & Configuration

### Prerequisites

All workflows require these secrets to be configured in repository settings:
- `CLAUDE_CODE_OAUTH_TOKEN` - For Claude Code workflows (claude.yml, claude-code-review.yml)
- `WIKI_TOKEN` - For wiki sync workflow (sync-wiki.yml)

### Creating Labels

The issue-labeler workflow requires labels to exist. Create them using:

```bash
pwsh .github/scripts/create-labels.ps1
```

This creates all 46 labels with descriptions and color codes.

### Manual Triggers

Workflows with `workflow_dispatch` can be triggered manually:
1. Go to Actions tab
2. Select the workflow
3. Click "Run workflow"
4. Choose branch and confirm

---

## 📊 Monitoring

### View Workflow Runs
- **Actions Tab** → Select workflow → View recent runs
- Check logs for detailed execution information
- Download artifacts (analysis results, link check reports)

### Common Issues

**Issue Labeler not working:**
- Verify labels exist: `gh label list`
- Check workflow permissions (needs `issues: write`)
- Review logs for API errors

**Stale workflow closing too many issues:**
- Adjust `operations-per-run` to process fewer items
- Add exempt labels to protect important issues
- Increase `days-before-stale` threshold

**Link checker failing:**
- Check if links are temporarily unavailable
- Review exclusions in workflow file
- Adjust timeout settings if needed

**Wiki sync failing:**
- Verify `WIKI_TOKEN` is valid
- Ensure wiki is enabled
- Check token has wiki write permissions

---

## 🔧 Customization

### Modifying Issue Labels

Edit `issue-labeler.yml` to adjust keyword patterns:
- **Technology detection** (lines 28-68): Add/remove technology keywords
- **Issue types** (lines 72-100): Adjust bug, enhancement, documentation patterns
- **Priority** (lines 104-112): Modify priority detection logic

### Adjusting Stale Timelines

Edit `stale.yml`:
- `days-before-issue-stale: 60` - Days before marking issue stale
- `days-before-pr-stale: 30` - Days before marking PR stale
- `days-before-close: 7` - Days after stale before closing

### Link Checker Exclusions

Edit `link-checker.yml`:
- Add domains to `--exclude` list
- Add paths to `--exclude-path`
- Adjust retry settings: `--max-retries`, `--retry-wait-time`

---

## 📝 Best Practices

1. **Test workflows on feature branches** before merging to main
2. **Monitor workflow runs** regularly for failures
3. **Review stale issues** before they're auto-closed
4. **Keep labels updated** as technology keywords evolve
5. **Update documentation** when modifying workflows

---

## 🤖 Maintenance

### Regular Tasks

**Weekly:**
- Review link checker results
- Check stale issue queue
- Monitor workflow success rates

**Monthly:**
- Review label usage and effectiveness
- Adjust keyword patterns based on false positives/negatives
- Update exclusions as needed

**Quarterly:**
- Review workflow permissions and secrets
- Update action versions (dependabot recommended)
- Audit exempt labels for stale workflow

---

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [github-script Action](https://github.com/actions/github-script)
- [stale Action](https://github.com/actions/stale)
- [lychee Link Checker](https://github.com/lycheeverse/lychee-action)
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)

---

**Last Updated:** 2026-01-05
**Maintained by:** @Carme99 with Claude Code
