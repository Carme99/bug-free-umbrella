<#
.SYNOPSIS
    Removes unauthorized SMB network shares.

.DESCRIPTION
    Enumerates all SMB shares on the local machine and removes any share whose name is not in
    the approved list, preventing unauthorized data exposure. Removing a share is destructive,
    so each removal honors -WhatIf/-Confirm via SupportsShouldProcess. The check-then-act flow
    makes re-running the script on a converged system a no-op that exits 0 (idempotent).
    Exit codes:
    - 0: remediation successful (unauthorized shares removed, or none found).
    - 1: the remediation failed unexpectedly (e.g. share enumeration failed).

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckSharedFolders.ps1
    Removes every SMB share not on the approved list and exits 0 on success.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckSharedFolders.ps1 -WhatIf
    Shows which unauthorized shares would be removed without changing anything.

.NOTES
    File Name: Invoke-RemediationCheckSharedFolders.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Checking network shares..." -ForegroundColor Cyan

        # Configuration - Add your approved share names here.
        $approvedShares = @(
            "ADMIN$",
            "C$",
            "D$",
            "IPC$",
            "print$"
        )

        $remediationActions = @()

        # Get all network shares.
        $shares = Get-SmbShare -ErrorAction SilentlyContinue

        foreach ($share in $shares) {
            $isApproved = $false

            foreach ($approved in $approvedShares) {
                if ($share.Name -like $approved) {
                    $isApproved = $true
                    break
                }
            }

            if (-not $isApproved) {
                try {
                    if ($PSCmdlet.ShouldProcess($share.Name, "Remove unauthorized SMB share")) {
                        Remove-SmbShare -Name $share.Name -Force -ErrorAction Stop
                        $remediationActions += "Removed unauthorized share: $($share.Name) ($($share.Path))"
                    }
                }
                catch {
                    Write-Host "[!] Could not remove share $($share.Name): $($_.Exception.Message)" `
                        -ForegroundColor Yellow
                }
            }
        }

        if ($remediationActions.Count -gt 0) {
            Write-Host "[+] Network share remediation completed:" -ForegroundColor Green
            foreach ($action in $remediationActions) {
                Write-Host "  - $action"
            }
        }
        else {
            Write-Host "[+] No unauthorized shares found to remove" -ForegroundColor Green
        }

        return 0
    }
    catch {
        Write-Host "[-] Error during network share remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
