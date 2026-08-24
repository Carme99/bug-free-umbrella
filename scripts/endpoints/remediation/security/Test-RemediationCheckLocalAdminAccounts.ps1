<#
.SYNOPSIS
    Detects unauthorized local administrator accounts.

.DESCRIPTION
    Checks for local administrator group members that are not in the approved list and
    reports the built-in Administrator account when it is enabled, which helps maintain
    security compliance and prevents unauthorized admin access. This is a read-only
    detection script: it never modifies anything, so re-running it on a compliant device
    converges to exit 0 (idempotent).
    Exit codes:
    - 0: compliant - only authorized admins present.
    - 1: non-compliant - unauthorized admin accounts detected or the check failed.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckLocalAdminAccounts.ps1
    Enumerates local administrators and exits 1 if unapproved accounts are found.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationCheckLocalAdminAccounts.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationCheckLocalAdminAccounts.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    Configuration - $approvedAdmins is the list of approved admin account
    names (default: Administrator, Domain Admins, Enterprise Admins).
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Checking local administrator accounts..." -ForegroundColor Cyan

        # Configuration - Add your approved admin accounts here
        $approvedAdmins = @(
            "Administrator",
            "Domain Admins",
            "Enterprise Admins"
        )

        $issues = @()
        $unauthorizedAdmins = @()

        # Get local administrators group
        $adminGroup = Get-LocalGroup -Name "Administrators" -ErrorAction SilentlyContinue

        if ($adminGroup) {
            $adminMembers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue

            foreach ($member in $adminMembers) {
                $memberName = $member.Name.Split('\')[-1]

                # Check if member is in approved list
                $isApproved = $false
                foreach ($approved in $approvedAdmins) {
                    if ($memberName -like $approved -or $member.Name -like "*\$approved") {
                        $isApproved = $true
                        break
                    }
                }

                # Check if it's a cloud-directory account (typically approved).
                # Documented PrincipalSource values are "Local", "Active Directory",
                # "Microsoft Entra group", and "Microsoft Account" (see Get-LocalGroupMember
                # docs); runtime values on some builds have historically been "AzureAD".
                # Match case-insensitively against the legacy "AzureAD" value and the
                # "Microsoft Entra ID"-era values; do not auto-approve Local/AD/MSA sources.
                # See https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/
                #   get-localgroupmember?view=powershell-5.1
                if ($member.PrincipalSource -match '^(?i)(AzureAD|Microsoft Entra group|Microsoft Entra ID)$') {
                    $isApproved = $true
                }

                if (-not $isApproved) {
                    $unauthorizedAdmins += $member.Name
                }
            }
        }

        # Check for enabled built-in Administrator account (security risk if enabled)
        $builtinAdmin = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
        if ($builtinAdmin -and $builtinAdmin.Enabled -eq $true) {
            $issues += "Built-in Administrator account is enabled (should be disabled)"
        }

        if ($unauthorizedAdmins.Count -gt 0) {
            Write-Host "[!] Unauthorized local administrator accounts detected:" -ForegroundColor Yellow
            foreach ($admin in $unauthorizedAdmins) {
                Write-Host "  - $admin" -ForegroundColor Yellow
            }
            return 1
        }

        if ($issues.Count -gt 0) {
            foreach ($issue in $issues) {
                Write-Host "[!] $issue" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] Local administrator accounts are properly configured" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking local administrator accounts: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
