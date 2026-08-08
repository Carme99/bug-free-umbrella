<#
.SYNOPSIS
    Detects unauthorized local administrator accounts.

.DESCRIPTION
    Checks for local administrator accounts that are not in the approved list.
    Helps maintain security compliance and prevents unauthorized admin access.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Only authorized admins present
    Exit 1: Unauthorized admin accounts detected

.CONFIGURATION
    $approvedAdmins: List of approved admin account names (default: Administrator)
#>

try {
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
            # See https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/get-localgroupmember?view=powershell-5.1
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
        Write-Host "Unauthorized local administrator accounts detected:"
        foreach ($admin in $unauthorizedAdmins) {
            Write-Host "  - $admin"
        }
        exit 1
    }

    if ($issues.Count -gt 0) {
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "Local administrator accounts are properly configured"
    exit 0

} catch {
    Write-Host "Error checking local administrator accounts: $_"
    exit 1
}
