<#
.SYNOPSIS
    Detects stale or orphaned credentials in Windows Credential Manager.

.DESCRIPTION
    Checks for stale application-created (generic) credentials that may be causing authentication
    issues or clutter. Windows domain credentials ('Domain:target=...') are never flagged, and
    by-design credentials that Windows creates and regenerates itself (virtualapp/didlogical,
    _MSLITE_, MicrosoftAccount, WindowsLive) are deliberately excluded from detection.
    Runs as SYSTEM, so cmdkey enumerates only the SYSTEM credential store; per-user stores are
    not visible from this context and are not checked.
    Exit codes:
    - 0: healthy - no stale credentials found (also returned when cmdkey cannot enumerate).
    - 1: non-compliant - stale credentials detected, or the check failed.

.NOTES
    File Name: Test-RemediationFixCredentialManager.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixCredentialManager.ps1
    Lists any stale generic credentials and returns 0 when healthy, 1 when remediation is needed.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\Test-RemediationFixCredentialManager.ps1
    Runs the same detection under the Intune Management Extension SYSTEM context.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Configuration
# Generic (application-created) credential types. Windows domain credentials
# ('Domain:target=...') are required for network authentication and are deliberately excluded.
$GenericTypePatterns = @('LegacyGeneric:', 'LegacyDiscardable:')

# Credentials Windows creates and regenerates by design - not staleness signals. Never flag these.
$ByDesignPatterns = @('virtualapp/didlogical', '_MSLITE_', 'MicrosoftAccount', 'WindowsLive')
#endregion

#region Functions

function Invoke-CmdKeyList {
    <#
    .SYNOPSIS
        Thin wrapper around the native cmdkey.exe CLI (the mock seam for tests).
    #>
    $output = & cmdkey.exe /list 2>&1 | Out-String
    [pscustomobject] @{ Output = $output; ExitCode = $LASTEXITCODE }
}

function Main {
    try {
        $outputMsg = "[*] Checking Windows Credential Manager for stale credentials..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $staleCredentials = @()

        # Out-String coalesces the line-per-object native output into a single newline-separated
        # string so the Target: regex matches each credential line individually (an array passed
        # to [regex]::Matches would be space-joined, collapsing all entries).
        $result = Invoke-CmdKeyList
        if ($result.ExitCode -eq 0) {
            $matchResults = [regex]::Matches($result.Output, "Target:\s+(.+)")
            foreach ($credMatch in $matchResults) {
                $target = $credMatch.Groups[1].Value.Trim()

                # Skip by-design credentials
                $isByDesign = $false
                foreach ($byDesign in $ByDesignPatterns) {
                    if ($target -match $byDesign) {
                        $isByDesign = $true
                        break
                    }
                }
                if ($isByDesign) { continue }

                # Flag generic (app-created) credentials
                foreach ($typePattern in $GenericTypePatterns) {
                    if ($target -like "$typePattern*") {
                        $staleCredentials += $target
                        break
                    }
                }
            }
        }
        else {
            $outputMsg = "[!] cmdkey failed to enumerate credentials (code $($result.ExitCode)); treating as healthy."
            Write-Host $outputMsg -ForegroundColor Yellow
        }

        if ($staleCredentials.Count -gt 0) {
            $outputMsg = "[!] Potentially stale credentials detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($cred in $staleCredentials) {
                Write-Host "- $cred"
            }
            return 1
        }

        $outputMsg = "[+] Credential Manager appears healthy."

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking Credential Manager: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}
#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
