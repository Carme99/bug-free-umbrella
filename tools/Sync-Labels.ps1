<#
.SYNOPSIS
    Synchronizes GitHub repository labels from a canonical definition.

.DESCRIPTION
    Reads the canonical label catalog (.github/labels.json - colors and descriptions)
    and reconciles them with the live repository via the GitHub CLI (gh).
    Creates missing labels and updates existing ones where color or description
    has drifted. Useful for maintainers after adding new technology domains or
    fixing the auto-labeler.

    Requires gh CLI authenticated (gh auth login) with repo scope.
    Safe to run repeatedly — idempotent.

.PARAMETER DryRun
    When specified, only reports what would be created or updated without
    making any changes.

.PARAMETER Repo
    Repository slug in owner/repo form. Defaults to Carme99/bug-free-umbrella.

.EXAMPLE
    PS C:\> .\tools\Sync-Labels.ps1 -DryRun

    Shows which labels would be created or updated without changing anything.

.EXAMPLE
    PS C:\> .\tools\Sync-Labels.ps1 -Repo Carme99/bug-free-umbrella

    Synchronizes every canonical label to the repository.

.NOTES
    File Name      : Sync-Labels.ps1
    Author         : Carme99
    Prerequisite   : PowerShell 7.0+, gh CLI authenticated
    Version        : 1.0.0
    Date           : 2026-08-20
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]$Repo = 'Carme99/bug-free-umbrella'
)

$ErrorActionPreference = 'Stop'

try {
    Write-Host "[*] Sync-Labels: reconciling labels for $Repo" -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "[!] DryRun enabled — no changes will be made" -ForegroundColor Yellow
    }

    # Verify gh CLI is available
    $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $ghCmd) {
        throw "gh CLI not found. Install from https://cli.github.com/ and run 'gh auth login'."
    }

    # Canonical label definitions — 48 labels (22 GitHub defaults + 27 domain + etc.)
    # Color values are 6-char hex without leading '#', as required by GitHub API.
    # Single source of truth: .github/labels.json, shared with .github/scripts/create-labels.ps1.
    # Both scripts previously carried their own copy (48 here, 46 there) and disagreed.
    $labelCatalogPath = Join-Path $PSScriptRoot ".." ".github" "labels.json"
    if (-not (Test-Path -LiteralPath $labelCatalogPath)) {
        throw "Canonical label catalog not found at $labelCatalogPath"
    }
    $labelCatalog = Get-Content -LiteralPath $labelCatalogPath -Raw | ConvertFrom-Json
    $labelDefinitions = @{}
    foreach ($property in $labelCatalog.PSObject.Properties) {
        $labelDefinitions[$property.Name] = @{
            Color       = $property.Value.color
            Description = $property.Value.description
        }
    }


    Write-Host "[*] Fetching existing labels from $Repo..." -ForegroundColor Cyan
    $json = gh label list --repo $Repo --limit 100 --json name,color,description 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh label list failed: $json"
    }
    $existing = $json | ConvertFrom-Json
    $existingMap = @{}
    foreach ($item in $existing) {
        $existingMap[$item.name] = $item
    }

    Write-Host "[*] Found $($existing.Count) existing labels; $($labelDefinitions.Count) canonical" -ForegroundColor Gray

    $created = 0
    $updated = 0
    $unchanged = 0

    foreach ($entry in $labelDefinitions.GetEnumerator() | Sort-Object Name) {
        $name = $entry.Key
        $desired = $entry.Value
        $live = $existingMap[$name]

        if (-not $live) {
            # Missing — create
            if ($DryRun) {
                Write-Host "[!] Would create: $name ($($desired.Color)) - $($desired.Description)" -ForegroundColor Yellow
            } else {
                if ($PSCmdlet.ShouldProcess($name, 'Create label')) {
                    $descArg = $desired.Description.Replace('"', '\"')
                    # Use gh label create
                    $createOut = gh label create $name --repo $Repo --color $desired.Color --description "$descArg" 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "[-] Failed to create ${name}: $createOut" -ForegroundColor Red
                    } else {
                        Write-Host "[+] Created: $name ($($desired.Color))" -ForegroundColor Green
                    }
                }
            }
            $created++
        } else {
            $colorMatch = $live.color -and $live.color.ToLower() -eq $desired.Color.ToLower()
            $descMatch = ($live.description -eq $desired.Description)
            if ($colorMatch -and $descMatch) {
                Write-Host "[*] Unchanged: $name" -ForegroundColor Gray
                $unchanged++
            } else {
                if ($DryRun) {
                    Write-Host "[!] Would update: $name (color: $($live.color) -> $($desired.Color), desc: '$($live.description)' -> '$($desired.Description)')" -ForegroundColor Yellow
                } else {
                    if ($PSCmdlet.ShouldProcess($name, 'Update label')) {
                        $descArg = $desired.Description.Replace('"', '\"')
                        $editOut = gh label edit $name --repo $Repo --color $desired.Color --description "$descArg" 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            Write-Host "[-] Failed to update ${name}: $editOut" -ForegroundColor Red
                        } else {
                            Write-Host "[+] Updated: $name ($($desired.Color))" -ForegroundColor Green
                        }
                    }
                }
                $updated++
            }
        }
    }

    Write-Host "" -ForegroundColor Gray
    Write-Host "[+] Sync complete: $created created, $updated updated, $unchanged unchanged (total $($labelDefinitions.Count))" -ForegroundColor Green
    if ($DryRun) {
        Write-Host "[!] DryRun — no changes were written" -ForegroundColor Yellow
    }
    exit 0
}
catch {
    Write-Host "[-] Sync-Labels failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
