<#
.SYNOPSIS
    Detects expired or expiring certificates.

.DESCRIPTION
    Checks for expired certificates or certificates expiring within 30 days
    in Personal and Trusted Root certificate stores.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: No expired certificates
    Exit 1: Expired or expiring certificates found

.CONFIGURATION
    $daysBeforeExpiry: Warning threshold in days (default: 30)
#>

try {
    # Configuration
    $daysBeforeExpiry = 30
    $warningDate = (Get-Date).AddDays($daysBeforeExpiry)

    $expiredCerts = @()
    $expiringSoon = @()

    # Check Personal store (current user and local machine)
    $stores = @("Cert:\LocalMachine\My", "Cert:\CurrentUser\My")

    foreach ($storePath in $stores) {
        if (Test-Path $storePath) {
            $certs = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue

            foreach ($cert in $certs) {
                if ($cert.NotAfter -lt (Get-Date)) {
                    $expiredCerts += [PSCustomObject]@{
                        Subject = $cert.Subject
                        Thumbprint = $cert.Thumbprint
                        Expiry = $cert.NotAfter
                        Store = $storePath
                    }
                } elseif ($cert.NotAfter -lt $warningDate) {
                    $expiringSoon += [PSCustomObject]@{
                        Subject = $cert.Subject
                        Thumbprint = $cert.Thumbprint
                        Expiry = $cert.NotAfter
                        DaysUntilExpiry = ($cert.NotAfter - (Get-Date)).Days
                        Store = $storePath
                    }
                }
            }
        }
    }

    $issuesFound = $false

    if ($expiredCerts.Count -gt 0) {
        Write-Host "Expired certificates found:"
        foreach ($cert in $expiredCerts) {
            Write-Host "  - $($cert.Subject) (Expired: $($cert.Expiry))"
        }
        $issuesFound = $true
    }

    if ($expiringSoon.Count -gt 0) {
        Write-Host "Certificates expiring within $daysBeforeExpiry days:"
        foreach ($cert in $expiringSoon) {
            Write-Host "  - $($cert.Subject) (Expires in $($cert.DaysUntilExpiry) days)"
        }
        $issuesFound = $true
    }

    if ($issuesFound) {
        exit 1
    }

    Write-Host "No expired or expiring certificates found"
    exit 0

} catch {
    Write-Host "Error checking certificate expiry: $_"
    exit 1
}
