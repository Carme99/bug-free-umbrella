<#
.SYNOPSIS
    Attempts to remediate common TPM issues on the local machine.

.DESCRIPTION
    Checks the TPM state and attempts software-side remediation: initializes the TPM when it is
    not ready and attempts to provision ownership when the TPM is present but unowned. Issues that
    require firmware changes (TPM missing, disabled or deactivated in BIOS/UEFI) are reported and
    cannot be fixed by this script. Re-running on a healthy TPM changes nothing (idempotent).
    Exit codes:
    - 0: TPM remediation successful or attempted, or the TPM is already in a healthy state.
    - 1: TPM is missing, requires BIOS/UEFI configuration, or an error occurred.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckTPMStatus.ps1
    Initializes or provisions the TPM when software remediation is possible.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Invoke-RemediationCheckTPMStatus.ps1'
    Runs the TPM remediation under the Intune Management Extension SYSTEM context.

.NOTES
    File Name: Invoke-RemediationCheckTPMStatus.ps1
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
        $outputMsg = "[*] Checking TPM status..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $remediationActions = @()

        # Get TPM status; a null result means no usable TPM was found.
        $tpm = Get-Tpm -ErrorAction SilentlyContinue
        if (-not $tpm) {
            $outputMsg = "[!] TPM is not present - requires hardware or BIOS/UEFI enablement"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        # Try to initialize TPM if not ready
        if ($tpm.TpmReady -eq $false) {
            try {
                if ($PSCmdlet.ShouldProcess("TPM", "Initialize TPM")) {
                    Initialize-Tpm -AllowClear -AllowPhysicalPresence -ErrorAction Stop
                }
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
                    if ($PSCmdlet.ShouldProcess("TPM", "Take TPM ownership via Win32_Tpm")) {
                        $provisionResult = Invoke-CimMethod -Namespace "root\cimv2\Security\MicrosoftTpm" `
                            -ClassName "Win32_Tpm" -MethodName "TakeOwnership" -ErrorAction Stop
                    }
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
            $outputMsg = "[!] TPM remediation cannot proceed:"
            Write-Host $outputMsg -ForegroundColor Yellow
            Write-Host "  - TPM must be enabled and activated in BIOS/UEFI firmware"
            Write-Host "  - This requires manual intervention or remote BIOS management"
            return 1
        }

        if ($remediationActions.Count -gt 0) {
            $outputMsg = "[+] TPM remediation completed:"
            Write-Host $outputMsg -ForegroundColor Green
            foreach ($action in $remediationActions) {
                Write-Host "  - $action"
            }
        }
        else {
            $outputMsg = "[+] TPM is already in a healthy state"
            Write-Host $outputMsg -ForegroundColor Green
        }

        return 0
    }
    catch {
        $outputMsg = "[-] Error during TPM remediation: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
