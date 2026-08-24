<#
.SYNOPSIS
    Detects unauthorized SMB network shares on the local device.
.DESCRIPTION
    Enumerates all SMB shares via Get-SmbShare and flags every share whose name does not match
    the approved list (ADMIN$, C$, D$, IPC$ and print$ by default), since unauthorized shares
    can represent a security risk or data exposure. This is a read-only detection script: it
    never removes shares itself, so re-running it on a converged system is safe (idempotent).
    Exit codes:
    - 0: compliant - only authorized shares are present.
    - 1: non-compliant - unauthorized shares were detected, or the check failed.
.EXAMPLE
    PS C:\> .\Test-RemediationCheckSharedFolders.ps1
    Lists shares outside the approved set and exits 1 when any unauthorized share exists.
.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationCheckSharedFolders.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.
.NOTES
    File Name: Test-RemediationCheckSharedFolders.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Checking for unauthorized network shares..." -ForegroundColor Cyan

        # Configuration - Add your approved share names here.
        $approvedShares = @(
            'ADMIN$',
            'C$',
            'D$',
            'IPC$',
            'print$'
        )

        $unauthorizedShares = @()

        # Get all network shares.
        $shares = Get-SmbShare -ErrorAction Stop

        foreach ($share in $shares) {
            # Skip special shares (ending with $) if they're in approved list.
            $isApproved = $false

            foreach ($approved in $approvedShares) {
                if ($share.Name -like $approved) {
                    $isApproved = $true
                    break
                }
            }

            if (-not $isApproved) {
                $unauthorizedShares += [PSCustomObject]@{
                    Name = $share.Name
                    Path = $share.Path
                }
            }
        }

        if ($unauthorizedShares.Count -gt 0) {
            Write-Host "[!] Unauthorized network shares detected:" -ForegroundColor Yellow
            foreach ($share in $unauthorizedShares) {
                Write-Host "[!]   - $($share.Name) ($($share.Path))" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] No unauthorized network shares detected" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking network shares: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
