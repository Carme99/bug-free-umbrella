<#
.SYNOPSIS
    Detects Windows Update states that have been stuck for more than 7 days.

.DESCRIPTION
    Detects a Windows Update state that has been stuck for more than 7 days: either the
    Windows Update service is not running/missing, or pending updates have persisted for more
    than 7 days. The persistence window is tracked via a first-seen marker under
    HKLM\SOFTWARE\BugFreeUmbrella (a registry write, gated behind -WhatIf/-Confirm).
    Ordinary pending updates installed recently (still within the 7-day window) do NOT trigger
    remediation - the full component reset in remediate.ps1 only runs for genuinely stuck states.
    Exit codes:
    - 0: compliant - Windows Update is healthy, the pending state is not yet stuck, or the
      first-seen marker was just recorded/reset.
    - 1: non-compliant or failure - the service is missing/not running, the update query failed,
      or pending updates have been stuck for more than 7 days.

.EXAMPLE
    PS C:\> .\Test-RemediationFixWindowsUpdateStuck.ps1
    Runs the detection check and exits 0 when Windows Update is healthy, 1 when stuck.

.EXAMPLE
    PS C:\> .\Test-RemediationFixWindowsUpdateStuck.ps1 -WhatIf
    Runs the check but shows which first-seen marker writes would happen without performing them.

.NOTES
    File Name: Test-RemediationFixWindowsUpdateStuck.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]

$ErrorActionPreference = 'Stop'

#region Configuration

# Marker registry location recording when the pending-update state was first seen
$markerPath = "HKLM:\SOFTWARE\BugFreeUmbrella\WUStuckFirstSeen"
$markerName = "FirstSeen"
$STUCK_DAYS = 7

#endregion

#region Functions

function Get-PendingUpdateCount {
    <#
    .SYNOPSIS
        Queries the Microsoft Update COM API for the number of installed-but-pending updates.
    #>
    [CmdletBinding()]
    param()

    $updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0")
    return $searchResult.Updates.Count
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $outputMsg = "[*] Checking for a stuck Windows Update state..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $wuService = Get-Service wuauserv -ErrorAction SilentlyContinue

        if (-not $wuService) {
            $outputMsg = "[!] Windows Update service not found"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        if ($wuService.Status -ne 'Running') {
            $outputMsg = "[!] Windows Update service is $($wuService.Status)"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        try {
            $pendingCount = Get-PendingUpdateCount -ErrorAction Stop
        }
        catch {
            $outputMsg = "[!] Could not query updates: $($_.Exception.Message)"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        if ($pendingCount -eq 0) {
            # No pending updates - clear the first-seen marker (state is healthy)
            if (Test-Path $markerPath) {
                if ($PSCmdlet.ShouldProcess($markerPath, "Remove stale first-seen marker")) {
                    Remove-Item -Path $markerPath -Force -ErrorAction SilentlyContinue
                }
            }
            $outputMsg = "[+] Windows Update healthy"
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }

        # Pending updates exist - check how long the pending state has persisted
        $firstSeen = (Get-ItemProperty -Path $markerPath -Name $markerName -ErrorAction SilentlyContinue).$markerName

        if (-not $firstSeen) {
            # First observation of the pending state - record the timestamp but do NOT
            # flag yet; remediation only triggers once the state persists > 7 days.
            if (-not (Test-Path $markerPath)) {
                if ($PSCmdlet.ShouldProcess($markerPath, "Create first-seen marker key")) {
                    New-Item -Path $markerPath -Force | Out-Null
                }
            }
            if ($PSCmdlet.ShouldProcess($markerPath, "Record first-seen timestamp")) {
                Set-ItemProperty -Path $markerPath -Name $markerName -Value (Get-Date).ToString("o") -Force
            }
            $outputMsg = "[*] Found $pendingCount pending updates"
            Write-Host $outputMsg -ForegroundColor Cyan
            $outputMsg = "[*]   first observation - not yet flagged"
            Write-Host $outputMsg -ForegroundColor Cyan
            return 0
        }

        try {
            $firstSeenDate = [DateTime]::Parse($firstSeen)
        }
        catch {
            # Unparseable marker - reset it and re-observe
            if ($PSCmdlet.ShouldProcess($markerPath, "Reset unparseable first-seen marker")) {
                Set-ItemProperty -Path $markerPath -Name $markerName -Value (Get-Date).ToString("o") -Force
            }
            $outputMsg = "[*] Found $pendingCount pending updates (marker reset - not yet flagged)"
            Write-Host $outputMsg -ForegroundColor Cyan
            return 0
        }

        $pendingDays = ((Get-Date) - $firstSeenDate).Days

        if ($pendingDays -gt $STUCK_DAYS) {
            $outputMsg = "[!] Found $pendingCount pending updates stuck"
            Write-Host $outputMsg -ForegroundColor Yellow
            $outputMsg = "[!]   more than $STUCK_DAYS days since first seen"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        $outputMsg = "[*] Found $pendingCount pending updates (pending for $pendingDays days)"

        Write-Host $outputMsg -ForegroundColor Cyan
        $outputMsg = "[*]   not yet stuck"
        Write-Host $outputMsg -ForegroundColor Cyan
        return 0
    }
    catch {
        $outputMsg = "[-] Error during stuck-state check: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
