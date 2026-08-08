<#
.SYNOPSIS
    Detects expired or expiring certificates.

.DESCRIPTION
    Checks for expired certificates or certificates expiring within 30 days in
    the Personal (My) certificate store of:
      - the local machine (Cert:\LocalMachine\My)
      - the current process user (Cert:\CurrentUser\My - under Intune proactive
        remediations this is the SYSTEM account)
      - every user profile on the device. Each user's NTUSER.DAT hive is loaded
        temporarily via reg.exe (or read directly if already loaded) and the
        My\Certificates registry entries are parsed, so real user certificates
        are examined even though the script runs as SYSTEM.

    Trusted Root stores are intentionally NOT scanned and NOT modified.

.NOTES
    Author: Intune Admin
    Version: 1.1
    Intune Context: SYSTEM
    Exit 0: No expired certificates
    Exit 1: Expired or expiring certificates found

    Limitations (SYSTEM context):
      - Certificate registry blobs are CAPI_CERT_BLOB_HEADER records; the record
        with PropertyId 0x20 carries the DER certificate. Entries whose blob
        cannot be parsed are skipped.
      - A user hive that cannot be loaded (profile in use, NTUSER.DAT missing)
        is skipped for that profile only; a note is printed when this happens.

.CONFIGURATION
    $daysBeforeExpiry: Warning threshold in days (default: 30)
#>

try {
    # Configuration
    $daysBeforeExpiry = 30
    $warningDate = (Get-Date).AddDays($daysBeforeExpiry)

    $script:expiredCerts = New-Object System.Collections.ArrayList
    $script:expiringSoon = New-Object System.Collections.ArrayList
    $script:skippedProfiles = 0

    function Add-CertificateResult {
        param($Cert, [string]$StoreLabel)
        if ($null -eq $Cert) { return }
        if ($Cert.NotAfter -lt (Get-Date)) {
            [void]$script:expiredCerts.Add([PSCustomObject]@{
                Subject = $Cert.Subject
                Thumbprint = $Cert.Thumbprint
                Expiry = $Cert.NotAfter
                Store = $StoreLabel
            })
        } elseif ($Cert.NotAfter -lt $warningDate) {
            [void]$script:expiringSoon.Add([PSCustomObject]@{
                Subject = $Cert.Subject
                Thumbprint = $Cert.Thumbprint
                Expiry = $Cert.NotAfter
                DaysUntilExpiry = ($Cert.NotAfter - (Get-Date)).Days
                Store = $StoreLabel
            })
        }
    }

    function Get-CertificateFromBlob {
        # Registry certificate blobs are a sequence of CAPI_CERT_BLOB_HEADER
        # records: PropertyId (DWORD) | Reserved (DWORD) | Length (DWORD) |
        # Data[Length]. The record with PropertyId 0x20 carries the DER-encoded
        # certificate (see NVISO "Extracting Certificates From the Windows
        # Registry" for the format).
        param([byte[]]$Blob)
        if ($null -eq $Blob -or $Blob.Length -lt 12) { return $null }
        $offset = 0
        while ($offset + 12 -le $Blob.Length) {
            $propertyId = [BitConverter]::ToInt32($Blob, $offset)
            $length = [BitConverter]::ToInt32($Blob, $offset + 8)
            $dataStart = $offset + 12
            if ($propertyId -eq 0x20 -and $length -gt 0 -and ($dataStart + $length) -le $Blob.Length) {
                $certBytes = New-Object byte[] $length
                [Array]::Copy($Blob, $dataStart, $certBytes, 0, $length)
                try {
                    return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (, $certBytes)
                } catch {
                    return $null
                }
            }
            if ($length -le 0) { break }  # malformed record - stop walking
            $offset = $dataStart + $length
        }
        return $null
    }

    function Test-CertStoreRegistry {
        # $CertificatesPath points at ...\SystemCertificates\My\Certificates
        param([string]$CertificatesPath, [string]$StoreLabel)
        if (-not (Test-Path $CertificatesPath)) { return }
        $certKeys = Get-ChildItem -Path $CertificatesPath -ErrorAction SilentlyContinue
        foreach ($certKey in $certKeys) {
            try {
                $blob = (Get-ItemProperty -Path $certKey.PSPath -Name Blob -ErrorAction SilentlyContinue).Blob
                if ($null -eq $blob) { continue }
                $cert = Get-CertificateFromBlob $blob
                if ($null -ne $cert) {
                    Add-CertificateResult $cert $StoreLabel
                }
            } catch {
                # Unparseable certificate entry - skip it
            }
        }
    }

    # 1) Local machine Personal store
    $storePath = "Cert:\LocalMachine\My"
    if (Test-Path $storePath) {
        Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue | ForEach-Object {
            Add-CertificateResult $_ "LocalMachine\My"
        }
    }

    # 2) Current (SYSTEM) user Personal store
    $storePath = "Cert:\CurrentUser\My"
    if (Test-Path $storePath) {
        Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue | ForEach-Object {
            Add-CertificateResult $_ "CurrentUser\My (SYSTEM)"
        }
    }

    # 3) Per-user Personal stores via a temporary hive load
    $userProfiles = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.Special -eq $false -and $_.LocalPath -and $_.LocalPath -notmatch 'systemprofile|defaultuser' -and $_.SID
    }

    foreach ($profile in $userProfiles) {
        $sid = $profile.SID
        $hiveKey = $sid
        $loadedByUs = $false

        if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {
            # Profile not loaded - mount its NTUSER.DAT under a temporary key.
            $ntUserDat = Join-Path $profile.LocalPath "NTUSER.DAT"
            if (-not (Test-Path $ntUserDat)) { continue }
            $hiveKey = "Temp-$sid"
            & reg.exe load "HKU\$hiveKey" "$ntUserDat" 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                # Hive in use or cannot be loaded - skip this profile only
                $script:skippedProfiles++
                continue
            }
            $loadedByUs = $true
        }

        try {
            $certificatesPath = "Registry::HKEY_USERS\$hiveKey\SOFTWARE\Microsoft\SystemCertificates\My\Certificates"
            $userName = Split-Path $profile.LocalPath -Leaf
            Test-CertStoreRegistry $certificatesPath "User $userName ($sid)\My"
        } finally {
            if ($loadedByUs) {
                & reg.exe unload "HKU\$hiveKey" 2>$null | Out-Null
                # If the unload fails (hive in use) the hive stays mounted under
                # HKU\$hiveKey; a subsequent run will then use the loaded path.
            }
        }
    }

    $issuesFound = $false

    if ($script:expiredCerts.Count -gt 0) {
        Write-Host "Expired certificates found:"
        foreach ($cert in $script:expiredCerts) {
            Write-Host "  - $($cert.Subject) (Expired: $($cert.Expiry), Store: $($cert.Store))"
        }
        $issuesFound = $true
    }

    if ($script:expiringSoon.Count -gt 0) {
        Write-Host "Certificates expiring within $daysBeforeExpiry days:"
        foreach ($cert in $script:expiringSoon) {
            Write-Host "  - $($cert.Subject) (Expires in $($cert.DaysUntilExpiry) days, Store: $($cert.Store))"
        }
        $issuesFound = $true
    }

    if ($script:skippedProfiles -gt 0) {
        Write-Host "Note: $($script:skippedProfiles) user profile(s) could not be loaded and were skipped"
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
