<#
.SYNOPSIS
    Removes expired certificates.

.DESCRIPTION
    Removes expired certificates from Personal certificate stores to prevent
    authentication issues and clean up certificate clutter.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Check Personal store (current user and local machine)
    $stores = @("Cert:\LocalMachine\My", "Cert:\CurrentUser\My")

    foreach ($storePath in $stores) {
        if (Test-Path $storePath) {
            $certs = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue

            foreach ($cert in $certs) {
                if ($cert.NotAfter -lt (Get-Date)) {
                    try {
                        # Remove expired certificate
                        Remove-Item -Path "$storePath\$($cert.Thumbprint)" -Force -ErrorAction Stop
                        $remediationActions += "Removed expired certificate: $($cert.Subject)"
                    } catch {
                        Write-Host "Warning: Could not remove certificate $($cert.Subject): $_"
                    }
                }
            }
        }
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Certificate remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    } else {
        Write-Host "No expired certificates found to remove"
    }

    exit 0

} catch {
    Write-Host "Error during certificate remediation: $_"
    exit 1
}
