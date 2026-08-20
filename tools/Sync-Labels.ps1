<#
.SYNOPSIS
    Synchronizes GitHub repository labels from a canonical definition.

.DESCRIPTION
    Reads a hardcoded hashtable of 48 canonical labels (colors and descriptions)
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

    Synchronizes all 48 canonical labels to the repository.

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
    $labelDefinitions = @{
        'bug'                      = @{ Color = 'd73a4a'; Description = "Something isn't working" }
        'documentation'            = @{ Color = '0075ca'; Description = 'Improvements or additions to documentation' }
        'duplicate'                = @{ Color = 'cfd3d7'; Description = 'This issue or pull request already exists' }
        'enhancement'              = @{ Color = 'a2eeef'; Description = 'New feature or request' }
        'good first issue'         = @{ Color = '7057ff'; Description = 'Good for newcomers' }
        'good-first-issue'         = @{ Color = '7057FF'; Description = 'Good first issue for contributors' }
        'help wanted'              = @{ Color = '008672'; Description = 'Extra attention is needed' }
        'invalid'                  = @{ Color = 'e4e669'; Description = "This doesn't seem right" }
        'question'                 = @{ Color = 'd876e3'; Description = 'Further information is requested' }
        'wontfix'                  = @{ Color = 'ffffff'; Description = 'This will not be worked on' }
        'automated'                = @{ Color = 'ededed'; Description = 'Automated workflow' }
        'broken-links'             = @{ Color = 'ededed'; Description = 'Broken link detected' }
        'security'                 = @{ Color = 'D73A49'; Description = 'Security-related issues' }
        'priority-high'            = @{ Color = 'B60205'; Description = 'High priority issue' }
        'priority-medium'          = @{ Color = 'fbca04'; Description = 'Medium priority issue' }
        'priority-low'             = @{ Color = '0e8a16'; Description = 'Low priority issue' }
        'code-quality'             = @{ Color = '9400D3'; Description = 'Code quality and best practices' }
        'stale'                    = @{ Color = 'ededed'; Description = 'Inactive issue or PR' }
        'proactive-remediations'   = @{ Color = '00A4EF'; Description = 'Proactive remediation scripts' }
        'github-actions'           = @{ Color = '2088FF'; Description = 'GitHub Actions workflows' }
        'windows-update'           = @{ Color = '0078D6'; Description = 'Windows Update / Autopatch' }
        'mslearn-review'           = @{ Color = '5319e7'; Description = 'Findings from the 2026-08-08 Microsoft Learn alignment review' }
        'active-directory'         = @{ Color = '003366'; Description = 'Active Directory' }
        'api'                      = @{ Color = '0052CC'; Description = 'API scripts' }
        'aws'                      = @{ Color = 'FF9900'; Description = 'AWS cloud scripts' }
        'azure'                    = @{ Color = '0078D4'; Description = 'Azure cloud scripts' }
        'azure-ad'                 = @{ Color = '00BCF2'; Description = 'Azure AD/Entra ID' }
        'compliance'               = @{ Color = 'B60205'; Description = 'Compliance frameworks' }
        'containers'               = @{ Color = '0DB7ED'; Description = 'Docker/Kubernetes' }
        'database'                 = @{ Color = '336791'; Description = 'Databases' }
        'defender'                 = @{ Color = '00A4EF'; Description = 'Microsoft Defender' }
        'devops'                   = @{ Color = '24292E'; Description = 'DevOps pipelines' }
        'exchange'                 = @{ Color = '0078D4'; Description = 'Exchange' }
        'group-policy'             = @{ Color = '4A90E2'; Description = 'Group Policy' }
        'hardening'                = @{ Color = 'D93F0B'; Description = 'Security hardening' }
        'iac'                      = @{ Color = '623CE4'; Description = 'Terraform/Bicep IaC' }
        'iis'                      = @{ Color = '512BD4'; Description = 'IIS web server' }
        'intune'                   = @{ Color = '0066CC'; Description = 'Intune management' }
        'linux'                    = @{ Color = 'FCC624'; Description = 'Linux scripts' }
        'microsoft-365'            = @{ Color = 'D83B01'; Description = 'Microsoft 365' }
        'networking'               = @{ Color = '00B294'; Description = 'Networking' }
        'performance'              = @{ Color = 'FEF2C0'; Description = 'Performance' }
        'sharepoint'               = @{ Color = '03787C'; Description = 'SharePoint/OneDrive' }
        'teams'                    = @{ Color = '6264A3'; Description = 'Microsoft Teams' }
        'testing'                  = @{ Color = '0E8A16'; Description = 'Testing' }
        'virtualization'           = @{ Color = '7B68EE'; Description = 'Hyper-V/VMware' }
        'windows-server'           = @{ Color = '0078D6'; Description = 'Windows Server' }
        'winget'                   = @{ Color = '00CC6A'; Description = 'Winget updates' }
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
