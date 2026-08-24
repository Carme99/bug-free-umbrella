<#
.SYNOPSIS
    Removes expired certificates from Personal certificate stores machine-wide.

.DESCRIPTION
    Removes expired certificates from the Personal (My) certificate store of the local
    machine (Cert:\LocalMachine\My), the current process user (Cert:\CurrentUser\My -
    under Intune proactive remediations this is the SYSTEM account), and every user
    profile on the device whose NTUSER.DAT hive is temporarily loaded via reg.exe,
    matching the companion detection script. Trusted Root stores are intentionally not
    scanned and not modified, and re-running on a converged device removes nothing and
    exits 0 (idempotent). This script deletes data; every removal is gated behind
    ShouldProcess so -WhatIf performs a dry run.
    Exit codes:
    - 0: remediation completed (expired certificates removed or none present).
    - 1: an unexpected error aborted the remediation.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixCertificateExpiry.ps1
    Scans all Personal stores and removes every expired certificate found.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixCertificateExpiry.ps1 -WhatIf
    Reports which expired certificates would be removed without deleting anything.

.NOTES
    File Name: Invoke-RemediationFixCertificateExpiry.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    Limitations (SYSTEM context): certificate registry blobs whose record with
    PropertyId 0x20 cannot be parsed are skipped; user hives that cannot be
    loaded are skipped for that profile only.
#>

[CmdletBinding(SupportsShouldProcess)]

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Checking certificate stores for expired certificates..." -ForegroundColor Cyan

        $remediationActions = @()
        $skippedProfiles = 0

        # Thin wrapper for the native reg.exe tool; returns its exit code.
        function Invoke-Reg {
            param([string[]]$ArgumentList)
            & reg.exe @ArgumentList 2>$null | Out-Null
            return $LASTEXITCODE
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

        function Remove-ExpiredFromCertStoreRegistry {
            [CmdletBinding(SupportsShouldProcess)]
            param(
                [string]$CertificatesPath,
                [string]$StoreLabel,
                [ref]$ActionsRef
            )
            # $CertificatesPath points at ...\SystemCertificates\My\Certificates
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
                            $ActionsRef.Value += "Removed expired certificate: $($cert.Subject) ($StoreLabel)"
                        }
                    }
                }
                catch {
                    Write-Host "[!] Warning: Could not remove certificate in $StoreLabel : $_" -ForegroundColor Yellow
                }
            }
        }

        # 1) Local machine + current (SYSTEM) user Personal stores via the cert provider
        # Provider paths kept as literals: Join-Path throws on Windows-only drives when absent.
        $stores = @("Cert:\LocalMachine\My", "Cert:\CurrentUser\My")

        foreach ($storePath in $stores) {
            if (Test-Path $storePath) {
                $certs = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue

                foreach ($cert in $certs) {
                    if ($cert.NotAfter -lt (Get-Date)) {
                        try {
                            # Remove expired certificate
                            $target = "$storePath\$($cert.Thumbprint)"
                            if ($PSCmdlet.ShouldProcess($target, 'Remove expired certificate')) {
                                Remove-Item -Path "$storePath\$($cert.Thumbprint)" -Force -ErrorAction Stop
                                $remediationActions += "Removed expired certificate: $($cert.Subject) ($storePath)"
                            }
                        }
                        catch {
                            $warn = "[!] Warning: Could not remove certificate $($cert.Subject): $_"
                            Write-Host $warn -ForegroundColor Yellow
                        }
                    }
                }
            }
        }

        # 2) Per-user Personal stores via a temporary hive load (mirrors detection script)
        $userProfiles = Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object {
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
                $loadResult = Invoke-Reg -ArgumentList @('load', "HKU\$hiveKey", $ntUserDat)
                if ($loadResult -ne 0) {
                    $skippedProfiles++
                    continue
                }
                $loadedByUs = $true
            }

            try {
                $certificatesPath =
                    "Registry::HKEY_USERS\$hiveKey\SOFTWARE\Microsoft\SystemCertificates\My\Certificates"
                $userName = Split-Path $profile.LocalPath -Leaf
                $storeLabel = "User $userName ($sid)\My"
                $actionsRef = [ref]$remediationActions
                Remove-ExpiredFromCertStoreRegistry -CertificatesPath $certificatesPath `
                    -StoreLabel $storeLabel -ActionsRef $actionsRef
            }
            finally {
                if ($loadedByUs) {
                    Invoke-Reg -ArgumentList @('unload', "HKU\$hiveKey") | Out-Null
                }
            }
        }

        if ($skippedProfiles -gt 0) {
            $note = "[!] Note: $skippedProfiles user profile(s) could not be loaded and were skipped"
            Write-Host $note -ForegroundColor Yellow
        }

        if ($remediationActions.Count -gt 0) {
            Write-Host "[+] Certificate remediation completed:" -ForegroundColor Green
            foreach ($action in $remediationActions) {
                Write-Host "  - $action" -ForegroundColor Green
            }
        }
        else {
            Write-Host "[+] No expired certificates found to remove" -ForegroundColor Green
        }

        return 0
    }
    catch {
        Write-Host "[-] Error during certificate remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
