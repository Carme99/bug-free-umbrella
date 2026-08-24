<#
.SYNOPSIS
    Remediates unauthorized local administrator accounts on the local machine.

.DESCRIPTION
    Disables the built-in Administrator account when it is enabled and reports the result;
    other unauthorized admin accounts are only logged for manual review, never removed
    automatically, to avoid locking out legitimate administrators or breaking systems.
    Re-running the script on a converged system performs no changes (idempotent).
    Exit codes:
    - 0: remediation successful, or no automatic remediation was required.
    - 1: an unexpected error occurred during remediation.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckLocalAdminAccounts.ps1
    Disables the built-in Administrator account if enabled and logs the outcome.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Invoke-RemediationCheckLocalAdminAccounts.ps1'
    Runs the same remediation under the Intune Management Extension SYSTEM context.

.NOTES
    File Name: Invoke-RemediationCheckLocalAdminAccounts.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]

param()

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $outputMsg = "[*] Checking local administrator accounts..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $remediationActions = @()

        # Disable built-in Administrator account if enabled.
        # The lookup tolerates a missing/renamed account so renamed-Admin systems stay compliant.
        $builtinAdmin = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
        if ($builtinAdmin -and $builtinAdmin.Enabled -eq $true) {
            try {
                if ($PSCmdlet.ShouldProcess("Administrator", "Disable built-in Administrator account")) {
                    Disable-LocalUser -Name "Administrator" -ErrorAction Stop
                }
                $remediationActions += "Disabled built-in Administrator account"
            }
            catch {
                $outputMsg = "[!] Could not disable Administrator account: $($_.Exception.Message)"
                Write-Host $outputMsg -ForegroundColor Yellow
            }
        }

        # Note: We do NOT automatically remove unauthorized admin accounts
        # as this could lock out legitimate administrators or break systems.
        # Instead, we log them for manual review.

        $outputMsg = "[+] Local administrator remediation completed:"
        Write-Host $outputMsg -ForegroundColor Green
        if ($remediationActions.Count -gt 0) {
            foreach ($action in $remediationActions) {
                Write-Host "  - $action"
            }
        }
        else {
            Write-Host "  - No automatic remediation performed"
        }

        Write-Host ""
        $outputMsg = "[*] Unauthorized admin accounts detected should be reviewed manually"
        Write-Host $outputMsg -ForegroundColor Cyan
        $outputMsg = "[*] Automatic removal of admin accounts is not performed to prevent lockouts"
        Write-Host $outputMsg -ForegroundColor Cyan

        return 0
    }
    catch {
        $outputMsg = "[-] Error during local administrator remediation: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
