<#
.SYNOPSIS
    Remediate regional settings to UK standards.

.DESCRIPTION
    Aligns the device regional configuration with the required UK values: sets
    the geographic location to United Kingdom (GeoId 242), the time zone to GMT
    Standard Time, the system locale and culture to en-GB, and makes en-GB the
    primary entry of the user language list. Every deviation is corrected with a
    persisted cmdlet call (Set-WinHomeLocation, Set-TimeZone, Set-WinSystemLocale,
    Set-Culture, Set-WinUserLanguageList); each mutation is gated behind
    -WhatIf/-Confirm via SupportsShouldProcess and reported. Re-running against an
    already-compliant device makes no changes and still exits 0 (idempotent).
    A restart may be required for some changes to fully take effect.

.EXAMPLE
    PS C:\> .\Invoke-RemediationRegionLanguageSettings.ps1

    Applies every required UK regional setting that deviates on this device.

.EXAMPLE
    PS C:\> .\Invoke-RemediationRegionLanguageSettings.ps1 -WhatIf

    Shows which regional settings would be changed without changing anything.

.NOTES
    File Name  : Invoke-RemediationRegionLanguageSettings.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Remediating regional settings to UK standards..." -ForegroundColor Cyan

        # Required settings
        $requiredCulture = 'en-GB'
        $requiredGeoId = 242      # United Kingdom
        $requiredTimeZone = 'GMT Standard Time'

        $changes = @()

        # Geographic location -> United Kingdom
        $currentGeoId = (Get-WinHomeLocation -ErrorAction Stop).GeoId
        if ($currentGeoId -ne $requiredGeoId) {
            if ($PSCmdlet.ShouldProcess("GeoId $requiredGeoId (United Kingdom)", "Set geographic location")) {
                Set-WinHomeLocation -GeoId $requiredGeoId -ErrorAction Stop
                $changes += "Geographic location set to UK"
            }
        }

        # Time zone -> GMT Standard Time
        $currentTimeZone = (Get-TimeZone -ErrorAction Stop).Id
        if ($currentTimeZone -ne $requiredTimeZone) {
            if ($PSCmdlet.ShouldProcess($requiredTimeZone, "Set time zone")) {
                Set-TimeZone -Id $requiredTimeZone -ErrorAction Stop
                $changes += "Time zone set to GMT Standard Time"
            }
        }

        # System locale -> en-GB
        $systemLocale = (Get-WinSystemLocale -ErrorAction Stop).Name
        if ($systemLocale -ne $requiredCulture) {
            if ($PSCmdlet.ShouldProcess($requiredCulture, "Set system locale")) {
                Set-WinSystemLocale -SystemLocale $requiredCulture -ErrorAction Stop
                $changes += "System locale set to en-GB"
            }
        }

        # Culture -> en-GB
        $currentCulture = (Get-Culture).Name
        if ($currentCulture -ne $requiredCulture) {
            if ($PSCmdlet.ShouldProcess($requiredCulture, "Set culture")) {
                Set-Culture -CultureInfo $requiredCulture -ErrorAction Stop
                $changes += "Culture set to en-GB"
            }
        }

        # User language list -> en-GB primary
        $userLanguageList = @(Get-WinUserLanguageList -ErrorAction Stop)
        $primaryLanguage = $userLanguageList[0].LanguageTag
        if ($primaryLanguage -ne $requiredCulture) {
            if ($PSCmdlet.ShouldProcess("$requiredCulture as primary language", "Set user language list")) {
                $languageList = New-WinUserLanguageList -Language $requiredCulture -ErrorAction Stop
                Set-WinUserLanguageList -LanguageList $languageList -Force -ErrorAction Stop
                $changes += "Primary language set to en-GB"
            }
        }

        if ($changes.Count -gt 0) {
            Write-Host "[+] Regional settings remediated: $($changes -join '; ')" -ForegroundColor Green
            Write-Host "[!] Restart may be required for all changes to take effect." -ForegroundColor Yellow
        }
        else {
            Write-Host "[+] Already compliant: no regional changes needed" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error remediating regional settings: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
