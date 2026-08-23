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

### 3. **PowerShell Script Validator** (`validate-powershell.yml`)

**Purpose:** Validates PowerShell scripts for syntax and best practices

**Triggers:**
- Push to main, develop, or claude/* branches
- Pull requests targeting main or develop
- Manual trigger via workflow_dispatch

**What it does:**
- Runs PSScriptAnalyzer on all `.ps1` files under `scripts/` using the curated `.vscode/PSScriptAnalyzerSettings.psd1` settings
- Validates PowerShell syntax with PSParser
- **Hard-fails** the pipeline on any Error-severity PSScriptAnalyzer finding
- Uploads analysis results as artifacts

**Configuration:**
- Uses curated PSScriptAnalyzer settings (`.vscode/PSScriptAnalyzerSettings.psd1`) shared with local development
- Gates the pipeline on Error-severity findings; warnings are reported but do not block
- Runs a PowerShell syntax check that also gates the pipeline

**Note:** This workflow is gating, not informational — it blocks PRs on Error-severity PSScriptAnalyzer findings and on PowerShell syntax errors. It does not run Pester tests.

---

### 4. **Claude Code** (`claude.yml`)

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

### 5. **Claude Code Review** (`claude-code-review.yml`)

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
- Uses repository's `AGENTS.md` for style guidance

**Note:** Currently configured to run on all PRs. Can be filtered by author or file paths if needed.

---

### 6. **Markdown Link Check** (`markdown-link-check.yml`)

**Purpose:** Validates links across all repository markdown files

**Triggers:**
- Pushes to `main` touching `**/*.md` files
- Pull requests touching `**/*.md` files
- Weekly schedule (Mondays 06:00 UTC)
- Manual dispatch

**What it does:**
- Runs `lychee` link checking over changed/whole markdown docs
- Flags broken internal and external links as check failures

---

### 7. **Release Module** (`release-module.yml`)

**Purpose:** Builds and publishes the `BugFreeUmbrella` module on release tags

**Triggers:**
- Push of a `v*` tag
- Manual dispatch (`workflow_dispatch`)

**What it does:**
- Builds the module from `src/BugFreeUmbrella/`
- Publishes to PSGallery **only** when the tag starts with `v` AND `PSGALLERY_API_KEY` is configured; otherwise the publish step is skipped with an explicit notice (the key never appears inline in step scripts)

**Configuration:**
- Requires `PSGALLERY_API_KEY` secret for actual publishing
- `contents: read` permission only

---

## 🚀 Setup & Configuration

### Prerequisites

All workflows require these secrets to be configured in repository settings:
- `CLAUDE_CODE_OAUTH_TOKEN` - For Claude Code workflows (claude.yml, claude-code-review.yml)
- `PSGALLERY_API_KEY` - For PSGallery publishing on `v*` tags (release-module.yml)

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
- Download artifacts (analysis results)

### Common Issues

**Issue Labeler not working:**
- Verify labels exist: `gh label list`
- Check workflow permissions (needs `issues: write`)
- Review logs for API errors

**Stale workflow closing too many issues:**
- Adjust `operations-per-run` to process fewer items
- Add exempt labels to protect important issues
- Increase `days-before-stale` threshold

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
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)

---

**Last Updated:** 2026-01-05
**Maintained by:** @Carme99 with Claude Code
