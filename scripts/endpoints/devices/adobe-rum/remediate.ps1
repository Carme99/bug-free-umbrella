<#
.SYNOPSIS
    Remediate Adobe Creative Cloud app updates via Remote Update Manager

.DESCRIPTION
    Intune Proactive Remediation remediation script for Adobe Creative Cloud updates. Runs the Adobe Remote Update
    Manager (RUM) to install all applicable Adobe Creative Cloud app updates, logs the run to the Intune Management
    Extension log directory, and reports which apps were updated.

    Idempotent check-then-act: when no updates are applicable RUM reports nothing to install and the script exits 0
    without changes. Exits 0 on success (including nothing to do) and 1 when the run fails. Must run in the SYSTEM
    context because RUM requires elevated privileges.

.EXAMPLE
    PS C:\> .\remediate.ps1

    Installs all applicable Adobe Creative Cloud updates; exits 0 on success or 1 on failure.

.EXAMPLE
    PS C:\> .\remediate.ps1 -Verbose

    Runs the remediation with verbose preference enabled for richer diagnostics.

.NOTES
    File Name  : remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23

    Used in Intune Proactive Remediation "SW-Update_CCApps"; runs as SYSTEM.
    The update installation itself is delegated to Adobe Remote Update Manager, which owns download and install
    behaviour.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# PSScriptAnalyzer: Write-Host with prefix/color output is mandated by docs/RELAUNCH-SPEC.md section 3.

#region Config
$AppName = 'Remediate-CCUpdates'
$OrgName = 'TMBC'
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = "$LogPath\$($OrgName)-$($AppName).log"

$rumDir = 'C:\Program Files (x86)\Common Files\Adobe\OOBE_Enterprise\RemoteUpdateManager'
$script:ARUMPath = "$rumDir\RemoteUpdateManager.exe"

# Search pattern to match in the RUM output and regex for sap codes, versions, and platforms.
$updatesInstalled = 'Following Updates were successfully installed'
$regexPattern = '\((\w+)\/([\d\.]+)\/(win\d+)\)'

# Product names for each Sap Code (sap codes obtained from various Internet sources).
$productNames = @{
    "AAM" = "Application Manager"
    "ACR" = "Camera Raw"
    "AEFT" = "After Effects"
    "AICY" = "InCopy"
    "AME" = "Media Encoder"
    "ANML" = "Character Animator"
    "APRO" = "Acrobat DC"
    "ASCT" = "Scout"
    "AUDT" = "Audition"
    "CCXP" = "Creative Cloud Experience"
    "CDEC" = "Codecs"
    "CHAR" = "Character Animator"
    "COCM" = "STI_ColorCommonSet_CMYK_HD"
    "COMP" = "STI_Color_MotionPicture_HD"
    "COPS" = "STI_Color_Photoshop_HD"
    "CORE" = "STI_Color_HD"
    "CORG" = "STI_Color_CommonSetRGB_HD"
    "COSY" = "CoreSync"
    "CPAS" = "Captivate Assets"
    "CPTL" = "Presenter"
    "CPTV" = "Captivate"
    "CPVC" = "Captivate Voices"
    "DIST" = "Acrobat Distiller"
    "DOTN" = "Microsoft Dot Net Framework"
    "DRWV" = "Dreamweaver"
    "EORG" = "Elements Organiser"
    "ESHR" = "Dimension"
    "FLBR" = "Flash Builder Premium"
    "FLPR" = "Animate and Mobile Device Packaging"
    "FM" = "FrameMaker"
    "FMDN" = "Microsoft Dot Net Framework"
    "FRSC" = "Fresco"
    "FUSE" = "FUSE"
    "FWKS" = "Fireworks"
    "GSDK" = "Gaming SDK"
    "HPRE" = "Premiere Elements Home Screen"
    "HPSE" = "Photoshop Elements Home Screen"
    "IDSN" = "InDesign"
    "ILST" = "Illustrator"
    "KANC" = "Notification Client"
    "KASU" = "HD_ASU"
    "KBRG" = "Bridge"
    "KCCC" = "Creative Cloud"
    "KEMN" = "Extension Manager"
    "KETK" = "Extendscript Toolkit"
    "KFNT" = "Fonts"
    "LIBS" = "Library"
    "LRCC" = "Lightroom"
    "LTRM" = "Lightroom Classic"
    "MSXML" = "MSXML 6 Framework"
    "MUSE" = "MUSE"
    "PHSP" = "Photoshop"
    "PPRO" = "Premiere Pro"
    "PRE" = "Premiere Elements"
    "PRLD" = "Prelude"
    "PSE" = "Photoshop Elements"
    "PSTI" = "Preview"
    "PVX" = "Presenter Video Express"
    "RBHP" = "RoboHelp"
    "RUSH" = "Premiere Rush"
    "SBSTA" = "Substance Sampler"
    "SBSTD" = "Substance Designer"
    "SBSTP" = "Substance Painter"
    "SPGD" = "SpeedGrade"
    "SPRK" = "XD"
    "STGR" = "Substance Stager"
    "TAPI" = "Touch App Plugins"
}
#endregion

function Invoke-RemoteUpdateManager {
# Thin wrapper around the native RemoteUpdateManager executable (mock seam for tests).
    return (& $script:ARUMPath @args 2>&1 | Out-String)
}

function Main {
    [CmdletBinding()]
    param()

    try {
        if (-not (Test-Path -Path $LogPath)) {
            New-Item -Path $LogPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        Start-Transcript -Path $LogFile -Force -ErrorAction Stop

        Write-Host '[*] Running Adobe Remote Update Manager to install applicable updates.' -ForegroundColor Cyan
        $arumOutput = Invoke-RemoteUpdateManager

# Find the app codes, version numbers, and platforms in the output text.
        $discoveries = [regex]::Matches($arumOutput, $regexPattern)
        $results = @()
        foreach ($discovered in $discoveries) {
            $sapCode = $discovered.Groups[1].Value
            $versionNumber = $discovered.Groups[2].Value
            $productName = $productNames[$sapCode]
            $results += "$($productName) ($($sapCode)) (v$($versionNumber))"
        }
        $resultsString = (($results -join ', ') -replace "`r`n", ', ').Trim()

# Search the output for the successful-install marker.
        $installedConfirmed = ($null -ne ($arumOutput | Select-String -Pattern $updatesInstalled))
        if ($installedConfirmed) {
            Write-Host "[+] Updates were installed: $($resultsString)" -ForegroundColor Green
            Write-Output ('Updates were successfully installed for the following Adobe Creative Cloud Apps: ' +
                $resultsString)
        }
        else {
            Write-Output 'No updates are required for Adobe Creative Cloud Apps'
            Write-Host '[+] No updates were required for Adobe Creative Cloud Apps.' -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
    finally {
        try { Stop-Transcript | Out-Null } catch { Write-Verbose 'No active transcript to stop' }
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
