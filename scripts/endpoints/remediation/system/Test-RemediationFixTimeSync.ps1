<#
.SYNOPSIS
    Detects time synchronization issues on Windows devices.

.DESCRIPTION
    Checks that the Windows Time service (W32Time) is running and set to start automatically,
    then queries the time sync status through w32tm (invoked only via the Invoke-W32tm wrapper)
    to verify that the device syncs from a network source rather than the local CMOS clock and
    performed a successful sync within the last 24 hours. Healthy time sync is critical for
    Kerberos authentication and certificate validation. This is a read-only detection script:
    it changes nothing, so re-running it is safe (idempotent).
    Exit codes:
    - 0: healthy - time synchronization is working.
    - 1: issues detected - remediation needed, or the check failed.

.EXAMPLE
    PS C:\> .\Test-RemediationFixTimeSync.ps1
    Checks W32Time and w32tm sync status; exits 0 when healthy, 1 when remediation is needed.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixTimeSync.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationFixTimeSync.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Functions

function Invoke-W32tm {
    <#
    .SYNOPSIS
        Thin wrapper around the native w32tm.exe CLI; returns its output and exit code.
    #>
    param([string[]]$Arguments)

    $output = & w32tm.exe @Arguments 2>&1
    [pscustomobject] @{
        ExitCode = $LASTEXITCODE
        Output   = ($output | Out-String)
    }
}

function Main {
    try {
        $outputMsg = "[*] Checking time synchronization status..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $issues = @()

        # Check if Windows Time service is running.
        $w32timeService = Get-Service -Name "W32Time" -ErrorAction SilentlyContinue
        if ($w32timeService.Status -ne "Running") {
            $issues += "Windows Time service is not running"
        }

        # Check time sync status using w32tm (native exe via wrapper).
        $w32tmResult = Invoke-W32tm -Arguments @('/query', '/status')
        if ($w32tmResult.ExitCode -ne 0) {
            $issues += "Time sync status check failed - service may not be configured"
        }
        else {
            $syncStatus = $w32tmResult.Output

            # Check if time source is configured.
            if ($syncStatus -match "Source: Local CMOS Clock") {
                $issues += "Time source is set to Local CMOS Clock (should sync from network)"
            }

            # Check last successful sync.
            if ($syncStatus -match "Last Successful Sync Time: (.+)") {
                $lastSync = $Matches[1]
                if ($lastSync -notmatch "unspecified") {
                    try {
                        $lastSyncDate = [DateTime]::Parse($lastSync)
                        $hoursSinceSync = ((Get-Date) - $lastSyncDate).TotalHours
                        if ($hoursSinceSync -gt 24) {
                            $issues += "Last successful sync was over 24 hours ago"
                        }
                    }
                    catch {
                        Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
                    }
                }
            }
        }

        # Check service startup type (should be Automatic).
        if ($w32timeService.StartType -ne "Automatic") {
            $issues += "Windows Time service startup type is not set to Automatic"
        }

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] Time sync issues detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($issue in $issues) {
                $outputMsg = "[!]   - $issue"
                Write-Host $outputMsg -ForegroundColor Yellow
            }
            return 1
        }

        $outputMsg = "[+] Time synchronization is healthy"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking time sync status: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
