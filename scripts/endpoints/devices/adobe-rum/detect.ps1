<#
.SYNOPSIS
    Detect Adobe Creative Cloud app updates via Remote Update Manager

.DESCRIPTION
    Intune Proactive Remediation detection script for Adobe Creative Cloud updates. Runs the Adobe Remote Update
    Manager
    (RUM) in list mode to determine whether any Adobe Creative Cloud apps require an update, logs the run to the
    Intune
    Management Extension log directory, and reports the affected apps.

    Exit codes: 1 when updates are required so the paired remediation runs, 0 when the system is up to date or
    RUM is
    not installed, and 1 when the detection fails. Must run in the SYSTEM context because RUM requires elevated
    privileges.

.EXAMPLE
    PS C:\> .\detect.ps1

    Runs the detection; exits 1 if any Adobe Creative Cloud app requires an update, otherwise 0.

.EXAMPLE
    PS C:\> .\detect.ps1 -Verbose

    Runs the detection with verbose preference enabled for richer diagnostics.

.NOTES
    File Name  : detect.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23

    Used in Intune Proactive Remediation "SW-Update_CCApps"; runs as SYSTEM.
    Sample RUM output on a machine requiring updates:
    RemoteUpdateManager version is : 3.0.0.8 / Following Updates are applicable on the system :
    (KBRG/13.0.3.693/win64) (ILST/27.4.0.669/win64) (COSY/6.4.0.12/win32) (CCXP/4.14.2.2/win32)
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# PSScriptAnalyzer: Write-Host with prefix/color output is mandated by docs/RELAUNCH-SPEC.md section 3.

#region Config
$AppName = 'Detect-CCUpdates'
$OrgName = 'TMBC'
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = "$LogPath\$($OrgName)-$($AppName).log"

$rumDir = 'C:\Program Files (x86)\Common Files\Adobe\OOBE_Enterprise\RemoteUpdateManager'
$script:ARUMPath = "$rumDir\RemoteUpdateManager.exe"

# Latest version of the Adobe RUM executable.
[version]$LatestVersion = '3.0.0.8'

# Search pattern to match in the RUM output and regex for sap codes, versions, and platforms.
$updatesRequired = 'Following Updates are applicable on the system'
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

function Get-ApplicableUpdateReport {
# Runs RUM in list mode and returns the raw marker result plus a report string of applicable updates.
    [CmdletBinding()]
    param ()

    Write-Host '[*] Running Adobe Remote Update Manager in list mode.' -ForegroundColor Cyan
    $arumOutput = Invoke-RemoteUpdateManager --action=list

# Find the app codes, version numbers, and platforms in the output text.
    $discoveries = [regex]::Matches($arumOutput, $regexPattern)
    $results = @()
    foreach ($discovered in $discoveries) {
        $sapCode = $discovered.Groups[1].Value
        $versionNumber = $discovered.Groups[2].Value
        $productName = $productNames[$sapCode]
        $results += "$($productName) ($($sapCode)) (v$($versionNumber))"
    }

# Join the results into one string so the content fits the Proactive Remediations result output.
    $report = (($results -join ', ') -replace "`r`n", ', ').Trim()
    $applicable = ($null -ne ($arumOutput | Select-String -Pattern $updatesRequired))
    return [pscustomobject]@{ Report = $report; UpdatesApplicable = [bool]$applicable }
}

function Main {
    [CmdletBinding()]
    param()

    try {
        if (-not (Test-Path -Path $LogPath)) {
            New-Item -Path $LogPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        Start-Transcript -Path $LogFile -Force -ErrorAction Stop

        if (-not (Test-Path -Path $script:ARUMPath)) {
            Write-Output 'Adobe RUM not found N.B. Check if RUM should exist on this device'
            Write-Host '[!] Adobe RUM not found; check whether it should exist on this device.' -ForegroundColor Yellow
            return 0
        }

# Determine the version of RUM installed.
        [version]$installedVersion = (Get-Item -Path $script:ARUMPath -ErrorAction Stop).VersionInfo.FileVersion

        $detection = Get-ApplicableUpdateReport

        if ($detection.UpdatesApplicable) {
            Write-Host "[!] Updates are required: $($detection.Report)" -ForegroundColor Yellow
            $rumNote = ''
            if ($installedVersion -lt $LatestVersion) {
                $rumNote = (" N.B. Adobe RUM is outdated: latest is ($($LatestVersion)), " +
                    "installed ($($installedVersion)).")
            }
            $reqLine = 'Updates are required for the following Adobe Creative Cloud Apps: '
            Write-Output ($reqLine + "$($detection.Report)$rumNote")
            return 1
        }
        else {
            if ($installedVersion -ge $LatestVersion) {
                Write-Output 'No updates are required for Adobe Creative Cloud Apps'
            }
            else {
                Write-Output ('No updates are required for Adobe Creative Cloud Apps. ' +
                    "N.B. Adobe RUM is outdated: latest is ($($LatestVersion)), installed ($($installedVersion)).")
            }
            Write-Host '[+] No updates are required for Adobe Creative Cloud Apps.' -ForegroundColor Green
            return 0
        }
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
