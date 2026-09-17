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

# Single source of truth: .github/labels.json, shared with tools/Sync-Labels.ps1.
# This script previously defined its own 46-label list that had drifted from that one.
$labelCatalogPath = Join-Path $PSScriptRoot ".." "labels.json"
if (-not (Test-Path -LiteralPath $labelCatalogPath)) {
    throw "Canonical label catalog not found at $labelCatalogPath"
}
$labelCatalog = Get-Content -LiteralPath $labelCatalogPath -Raw | ConvertFrom-Json
$labels = @()
foreach ($property in $labelCatalog.PSObject.Properties) {
    $labels += @{
        name        = $property.Name
        color       = $property.Value.color
        description = $property.Value.description
    }
}


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
