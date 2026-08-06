<#
.SYNOPSIS
    Creates GitHub labels for the Bug-Free Umbrella repository.

.DESCRIPTION
    This script creates all the labels needed for the issue auto-labeler workflow.
    Labels are organized by category: Technology, Issue Type, Priority, and Process.

.PARAMETER DryRun
    If specified, shows what labels would be created without actually creating them.

.EXAMPLE
    PS C:\> .\create-labels.ps1
    Creates all labels in the repository.

.EXAMPLE
    PS C:\> .\create-labels.ps1 -DryRun
    Shows what labels would be created without creating them.

.NOTES
    File Name      : create-labels.ps1
    Author         : @Carme99
    Prerequisite   : gh CLI must be installed and authenticated
    Version        : 1.0.0
    Date           : 2026-01-05
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Check if gh CLI is installed
try {
    $null = gh --version
} catch {
    Write-Host "❌ Error: GitHub CLI (gh) is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Install it from: https://cli.github.com/" -ForegroundColor Yellow
    exit 1
}

# Check if we're in a git repository
try {
    $repo = gh repo view --json nameWithOwner -q .nameWithOwner
    Write-Host "📦 Repository: $repo" -ForegroundColor Cyan
} catch {
    Write-Host "❌ Error: Not in a git repository or gh not authenticated" -ForegroundColor Red
    exit 1
}

# Define labels by category
$labels = @(
    # ========== TECHNOLOGY DOMAINS (Cloud & Infrastructure) ==========
    @{ name = "azure"; color = "0078D4"; description = "Related to Microsoft Azure" }
    @{ name = "aws"; color = "FF9900"; description = "Related to Amazon Web Services" }
    @{ name = "containers"; color = "2496ED"; description = "Docker, Kubernetes, container technologies" }

    # ========== TECHNOLOGY DOMAINS (Endpoints & Devices) ==========
    @{ name = "intune"; color = "00BCF2"; description = "Microsoft Intune / Endpoint Manager" }
    @{ name = "winget"; color = "0067C0"; description = "Windows Package Manager" }
    @{ name = "proactive-remediations"; color = "00A4EF"; description = "Proactive remediation scripts" }
    @{ name = "windows-update"; color = "0078D6"; description = "Windows Update / Autopatch" }
    @{ name = "bitlocker"; color = "107C10"; description = "BitLocker encryption" }

    # ========== TECHNOLOGY DOMAINS (Infrastructure) ==========
    @{ name = "windows-server"; color = "0078D6"; description = "Windows Server administration" }
    @{ name = "active-directory"; color = "006CB8"; description = "Active Directory / Domain Services" }
    @{ name = "group-policy"; color = "0063B1"; description = "Group Policy Objects (GPO)" }
    @{ name = "virtualization"; color = "652D90"; description = "Hyper-V, VMware, virtualization" }
    @{ name = "iis"; color = "005A9E"; description = "Internet Information Services" }
    @{ name = "linux"; color = "FCC624"; description = "Linux administration" }
    @{ name = "networking"; color = "00758F"; description = "Network, DNS, DHCP, routing" }

    # ========== TECHNOLOGY DOMAINS (Security & Compliance) ==========
    @{ name = "security"; color = "D73A49"; description = "Security-related issues" }
    @{ name = "compliance"; color = "B60205"; description = "Compliance frameworks (CIS, NIST, etc.)" }
    @{ name = "hardening"; color = "C41E3A"; description = "Security hardening and baselines" }

    # ========== TECHNOLOGY DOMAINS (Automation & DevOps) ==========
    @{ name = "devops"; color = "0366D6"; description = "DevOps, CI/CD pipelines" }
    @{ name = "iac"; color = "5C2D91"; description = "Infrastructure as Code (Terraform, Bicep)" }

    # ========== TECHNOLOGY DOMAINS (Microsoft 365 & Collaboration) ==========
    @{ name = "microsoft-365"; color = "D83B01"; description = "Microsoft 365 / Office 365" }
    @{ name = "exchange"; color = "0072C6"; description = "Exchange Online / Exchange Server" }
    @{ name = "teams"; color = "6264A7"; description = "Microsoft Teams" }
    @{ name = "sharepoint"; color = "038387"; description = "SharePoint / OneDrive" }
    @{ name = "azure-ad"; color = "0078D4"; description = "Azure AD / Entra ID" }
    @{ name = "defender"; color = "00A4EF"; description = "Microsoft Defender" }

    # ========== TECHNOLOGY DOMAINS (Data & Databases) ==========
    @{ name = "database"; color = "336791"; description = "Databases (SQL, MySQL, PostgreSQL, MongoDB)" }
    @{ name = "api"; color = "009688"; description = "REST API, Graph API" }

    # ========== ISSUE TYPE (Secondary Categories) ==========
    @{ name = "bug"; color = "D73A49"; description = "Something isn't working" }
    @{ name = "enhancement"; color = "A2EEEF"; description = "New feature or improvement request" }
    @{ name = "documentation"; color = "0075CA"; description = "Documentation improvements" }
    @{ name = "question"; color = "D876E3"; description = "Questions or help needed" }
    @{ name = "performance"; color = "FBCA04"; description = "Performance optimization" }
    @{ name = "testing"; color = "BFD4F2"; description = "Testing, validation, Pester tests" }

    # ========== PRIORITY LEVELS ==========
    @{ name = "priority-high"; color = "B60205"; description = "High priority issue" }
    @{ name = "good-first-issue"; color = "7057FF"; description = "Good for newcomers" }

    # ========== PROCESS LABELS ==========
    @{ name = "pinned"; color = "FEF2C0"; description = "Pinned issue/PR exempt from stale-closing" }
    @{ name = "work-in-progress"; color = "FFD93D"; description = "PR or issue still in progress" }
    @{ name = "help-wanted"; color = "008672"; description = "Help wanted from contributors" }
    @{ name = "triage"; color = "B60205"; description = "Needs triage" }
    @{ name = "new-script"; color = "0E8A16"; description = "New script submission" }
    @{ name = "stale"; color = "EDEDED"; description = "Inactive issue/PR (auto-applied)" }
    @{ name = "broken-links"; color = "D93F0B"; description = "Broken links in documentation" }
    @{ name = "automated"; color = "BFDADC"; description = "Created by automation" }
    @{ name = "dependencies"; color = "0366D6"; description = "Dependency updates" }
    @{ name = "github-actions"; color = "2088FF"; description = "GitHub Actions workflows" }
)

Write-Host "`n🏷️  Creating $($labels.Count) GitHub Labels" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Gray

if ($DryRun) {
    Write-Host "⚠️  DRY RUN MODE - No labels will be created" -ForegroundColor Yellow
    Write-Host ""
}

$created = 0
$updated = 0
$skipped = 0
$errors = 0

foreach ($label in $labels) {
    $name = $label.name
    $color = $label.color
    $description = $label.description

    if ($DryRun) {
        Write-Host "[DRY RUN] Would create: " -NoNewline -ForegroundColor Gray
        Write-Host "$name " -NoNewline -ForegroundColor White
        Write-Host "($description)" -ForegroundColor Gray
        continue
    }

    try {
        # Check if label already exists
        $existingLabel = gh label list --json name --jq ".[] | select(.name == `"$name`")" 2>&1

        if ($LASTEXITCODE -eq 0 -and $existingLabel) {
            # Label exists, update it
            $updateResult = gh label edit $name --color $color --description $description 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "🔄 Updated: " -NoNewline -ForegroundColor Yellow
                Write-Host "$name " -NoNewline -ForegroundColor White
                Write-Host "($description)" -ForegroundColor Gray
                $updated++
            } else {
                Write-Host "⏭️  Skipped: " -NoNewline -ForegroundColor Cyan
                Write-Host "$name " -NoNewline -ForegroundColor White
                Write-Host "(already exists, couldn't update)" -ForegroundColor Gray
                $skipped++
            }
        } else {
            # Label doesn't exist, create it
            $result = gh label create $name --color $color --description $description 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Created: " -NoNewline -ForegroundColor Green
                Write-Host "$name " -NoNewline -ForegroundColor White
                Write-Host "($description)" -ForegroundColor Gray
                $created++
            } else {
                Write-Host "❌ Error creating $name : $result" -ForegroundColor Red
                $errors++
            }
        }
    } catch {
        Write-Host "❌ Error processing $name : $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Gray
Write-Host "📊 Summary:" -ForegroundColor Cyan
Write-Host "   Created: $created" -ForegroundColor Green
Write-Host "   Updated: $updated" -ForegroundColor Yellow
Write-Host "   Skipped: $skipped" -ForegroundColor Cyan
Write-Host "   Errors:  $errors" -ForegroundColor Red
Write-Host "   Total:   $($labels.Count)" -ForegroundColor White
Write-Host ""

if ($DryRun) {
    Write-Host "💡 Run without -DryRun to actually create the labels" -ForegroundColor Yellow
} else {
    Write-Host "✅ Label creation complete!" -ForegroundColor Green
    Write-Host "   View labels: gh label list" -ForegroundColor Gray
    Write-Host "   Or visit: https://github.com/$repo/labels" -ForegroundColor Gray
}

if ($errors -gt 0) {
    exit 1
} else {
    exit 0
}
