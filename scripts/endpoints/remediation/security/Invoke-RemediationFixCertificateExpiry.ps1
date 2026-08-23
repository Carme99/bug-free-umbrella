<#
.SYNOPSIS
    Removes expired certificates.

.DESCRIPTION
    Removes expired certificates from the Personal (My) certificate store of:
      - the local machine (Cert:\LocalMachine\My)
      - the current process user (Cert:\CurrentUser\My - under Intune proactive
        remediations this is the SYSTEM account)
      - every user profile on the device (hive loaded temporarily via reg.exe,
        matching detect.ps1)
    This converges with detect.ps1, which examines exactly these stores.

    Trusted Root stores are intentionally NOT scanned and NOT modified.

.NOTES
    Author: Intune Admin
    Version: 1.1
    Intune Context: SYSTEM
    Exit 0: Remediation successful

    Limitations (SYSTEM context): certificate registry blobs whose record with
    PropertyId 0x20 cannot be parsed are skipped; user hives that cannot be
    loaded are skipped for that profile only.
#>

try {
    $script:remediationActions = @()
    $script:skippedProfiles = 0

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
                }
                catch {
                    return $null
                }
            }
            if ($length -le 0) { break }  # malformed record - stop walking
            $offset = $dataStart + $length
        }
        return $null
    }

    function Remove-ExpiredFromCertStoreRegistry {
        [CmdletBinding(SupportsShouldProcess)]
        # $CertificatesPath points at ...\SystemCertificates\My\Certificates
        param([string]$CertificatesPath, [string]$StoreLabel)
        if (-not (Test-Path $CertificatesPath)) { return }
        $certKeys = Get-ChildItem -Path $CertificatesPath -ErrorAction SilentlyContinue
        foreach ($certKey in $certKeys) {
            try {
                $blob = (Get-ItemProperty -Path $certKey.PSPath -Name Blob -ErrorAction SilentlyContinue).Blob
                if ($null -eq $blob) { continue }
                $cert = Get-CertificateFromBlob $blob
                if ($null -ne $cert -and $cert.NotAfter -lt (Get-Date)) {
                    # Remove the certificate entry from the store
                    if ($PSCmdlet.ShouldProcess($certKey.PSPath, 'Remove expired certificate')) {
                        Remove-Item -Path $certKey.PSPath -Force -ErrorAction Stop
                        $script:remediationActions += "Removed expired certificate: $($cert.Subject) ($StoreLabel)"
                    }
                }
            }
            catch {
                Write-Host "Warning: Could not remove certificate in $StoreLabel : $_"
            }
        }
    }

    # 1) Local machine + current (SYSTEM) user Personal stores via the cert provider
    $stores = @("Cert:\LocalMachine\My", "Cert:\CurrentUser\My")

    foreach ($storePath in $stores) {
        if (Test-Path $storePath) {
            $certs = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue

            foreach ($cert in $certs) {
                if ($cert.NotAfter -lt (Get-Date)) {
                    try {
                        # Remove expired certificate
                        Remove-Item -Path "$storePath\$($cert.Thumbprint)" -Force -ErrorAction Stop
                        $script:remediationActions += "Removed expired certificate: $($cert.Subject) ($storePath)"
                    }
                    catch {
                        Write-Host "Warning: Could not remove certificate $($cert.Subject): $_"
                    }
                }
            }
        }
    }

    # 2) Per-user Personal stores via a temporary hive load (mirrors detect.ps1)
    $userProfiles = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.Special -eq $false -and $_.LocalPath -and $_.LocalPath -notmatch 'systemprofile|defaultuser' -and $_.SID
    }

    foreach ($profile in $userProfiles) {
        $sid = $profile.SID
        $hiveKey = $sid
        $loadedByUs = $false

        if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {
            $ntUserDat = Join-Path $profile.LocalPath "NTUSER.DAT"
            if (-not (Test-Path $ntUserDat)) { continue }
            $hiveKey = "Temp-$sid"
            & reg.exe load "HKU\$hiveKey" "$ntUserDat" 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                $script:skippedProfiles++
                continue
            }
            $loadedByUs = $true
        }

        try {
            $certificatesPath = "Registry::HKEY_USERS\$hiveKey\SOFTWARE\Microsoft\SystemCertificates\My\Certificates"
            $userName = Split-Path $profile.LocalPath -Leaf
            Remove-ExpiredFromCertStoreRegistry $certificatesPath "User $userName ($sid)\My"
        }
        finally {
            if ($loadedByUs) {
                & reg.exe unload "HKU\$hiveKey" 2>$null | Out-Null
            }
        }
    }

    if ($script:skippedProfiles -gt 0) {
        Write-Host "Note: $($script:skippedProfiles) user profile(s) could not be loaded and were skipped"
    }

    if ($script:remediationActions.Count -gt 0) {
        Write-Host "Certificate remediation completed:"
        foreach ($action in $script:remediationActions) {
            Write-Host "  - $action"
        }
    }
    else {
        Write-Host "No expired certificates found to remove"
    }

    exit 0

}
catch {
    Write-Host "Error during certificate remediation: $_"
    exit 1
}
