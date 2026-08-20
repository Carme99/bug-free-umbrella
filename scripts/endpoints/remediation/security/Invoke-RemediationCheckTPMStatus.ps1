<#
.SYNOPSIS
    Attempts to remediate TPM issues.

.DESCRIPTION
    Tries to initialize and take ownership of TPM. Note that some issues
    require BIOS/UEFI configuration and cannot be fixed via software.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful or attempted
#>

try {
    $remediationActions = @()

    # Get TPM status
    $tpm = Get-Tpm -ErrorAction SilentlyContinue
    if (-not $tpm) {
        Write-Host "TPM is not present - requires hardware or BIOS/UEFI enablement"
        exit 1
    }

    # Try to initialize TPM if not ready
    if ($tpm.TpmReady -eq $false) {
        try {
            Initialize-Tpm -AllowClear -AllowPhysicalPresence -ErrorAction SilentlyContinue
            $remediationActions += "Attempted TPM initialization"
        }
        catch {
            $remediationActions += "TPM initialization failed - may require BIOS/UEFI intervention"
        }
    }

    # Clear TPM if it's in a bad state (use with caution)
    if ($tpm.TpmPresent -and $tpm.TpmEnabled -and -not $tpm.TpmOwned) {
        try {
            # Take ownership
            $owner = Get-TpmOwnerInfo -ErrorAction SilentlyContinue
            if (-not $owner) {
                # Try to provision TPM
                $provisionResult = Invoke-CimMethod -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -MethodName "TakeOwnership" -ErrorAction SilentlyContinue
                if ($provisionResult) {
                    $remediationActions += "Attempted to take TPM ownership"
                }
            }
        }
        catch {
            $remediationActions += "Could not take TPM ownership automatically"
        }
    }

    # If TPM is not enabled/activated, this requires BIOS intervention
    if ($tpm.TpmEnabled -eq $false -or $tpm.TpmActivated -eq $false) {
        $remediationActions += "TPM requires BIOS/UEFI configuration - cannot be fixed via software"
        Write-Host "TPM remediation cannot proceed:"
        Write-Host "  - TPM must be enabled and activated in BIOS/UEFI firmware"
        Write-Host "  - This requires manual intervention or remote BIOS management"
        exit 1
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "TPM remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    }
    else {
        Write-Host "TPM is already in a healthy state"
    }

    exit 0

}
catch {
    Write-Host "Error during TPM remediation: $_"
    exit 1
}
