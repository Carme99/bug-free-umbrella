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
    Exit codes: 0 = compliant (no expired or expiring certificates found),
    1 = non-compliant (expired or expiring certificates found, or an unexpected
    error occurred). The script is read-only apart from temporarily loading and
    unloading user hives under HKU\Temp-<SID>, so re-running it on a converged
    device converges to exit 0 (idempotent).
    Configuration: $daysBeforeExpiry sets the warning threshold in days
    (default: 30).

.EXAMPLE
    PS C:\> .\Test-RemediationFixCertificateExpiry.ps1
    Scans machine, SYSTEM and per-user Personal stores; exits 0 when no
    certificate is expired or expiring within 30 days, 1 otherwise.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixCertificateExpiry.ps1' -Verbose
    Runs the same scan from the Intune Management Extension under the SYSTEM
    context, printing verbose progress for skipped stores and hives.

.NOTES
    File Name: Test-RemediationFixCertificateExpiry.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    Limitations (SYSTEM context):
      - Certificate registry blobs are CAPI_CERT_BLOB_HEADER records; the record
        with PropertyId 0x20 carries the DER certificate. Entries whose blob
        cannot be parsed are skipped.
      - A user hive that cannot be loaded (profile in use, NTUSER.DAT missing)
        is skipped for that profile only; a note is printed when this happens.

#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Invoke-RegExe {
    # Thin wrapper around reg.exe (native executable) so tests can mock
    # the seam; returns the native $LASTEXITCODE.
    & reg.exe @args 2>$null | Out-Null
    return $LASTEXITCODE
}

function Main {
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
            }
            elseif ($Cert.NotAfter -lt $warningDate) {
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
                        return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 `
                            -ArgumentList (, $certBytes)
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
                }
                catch {
                    Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
                }
            }
        }

        Write-Host "[*] Checking certificate expiry..." -ForegroundColor Cyan

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
                if ((Invoke-RegExe load "HKU\$hiveKey" "$ntUserDat") -ne 0) {
                    # Hive in use or cannot be loaded - skip this profile only
                    $script:skippedProfiles++
                    continue
                }
                $loadedByUs = $true
            }

            try {
                $certificatesPath = "Registry::HKEY_USERS\$hiveKey\SOFTWARE\Microsoft" +
                    "\SystemCertificates\My\Certificates"
                $userName = Split-Path $profile.LocalPath -Leaf
                Test-CertStoreRegistry $certificatesPath "User $userName ($sid)\My"
            }
            finally {
                if ($loadedByUs) {
                    $null = Invoke-RegExe unload "HKU\$hiveKey"
                    # If the unload fails (hive in use) the hive stays mounted under
                    # HKU\$hiveKey; a subsequent run will then use the loaded path.
                }
            }
        }

        $issuesFound = $false

        if ($script:expiredCerts.Count -gt 0) {
            Write-Host "[!] Expired certificates found:" -ForegroundColor Yellow
            foreach ($cert in $script:expiredCerts) {
                Write-Host "  - $($cert.Subject) (Expired: $($cert.Expiry), Store: $($cert.Store))" `
                    -ForegroundColor Yellow
            }
            $issuesFound = $true
        }

        if ($script:expiringSoon.Count -gt 0) {
            Write-Host "[!] Certificates expiring within $daysBeforeExpiry days:" -ForegroundColor Yellow
            foreach ($cert in $script:expiringSoon) {
                Write-Host "  - $($cert.Subject) (Expires in $($cert.DaysUntilExpiry) days, Store: $($cert.Store))" `
                    -ForegroundColor Yellow
            }
            $issuesFound = $true
        }

        if ($script:skippedProfiles -gt 0) {
            Write-Host "[*] Note: $($script:skippedProfiles) user profile(s) were skipped"
        }

        if ($issuesFound) {
            return 1
        }

        Write-Host "[+] No expired or expiring certificates found" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking certificate expiry: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
