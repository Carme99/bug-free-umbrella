<#
===============================
|  Detect-AdobeCCUpdates.ps1  |
===============================

Detects if any Adobe Creative Cloud Apps require an update installing, by using Adobe Remote Update Manager (RUM).
Returns (1) if required updates are found, and (0) if not

Used in Proactive Remediation "SW-Update_CCApps"

This script must be run in the SYSTEM context (as RUM requires Admin priviledges to successfully run)
---------------------------------------------------------------
Sample Output from a machine requiring updates:

RemoteUpdateManager version is : 3.0.0.8
Starting the RemoteUpdateManager...

Following Updates are applicable on the system :
                (KBRG/13.0.3.693/win64)
                (ILST/27.4.0.669/win64)
                (COSY/6.4.0.12/win32)
                (CCXP/4.14.2.2/win32)
**************************************************
RemoteUpdateManager exiting with Return Code (0)

---------------------------------------------------------------

#>

#region functions
#endregion

#region Config
$AppName = "Detect-CCUpdates"
$OrgName = "TMBC"
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = "$LogPath\$($OrgName)-$($AppName).log"
# Set the path to the Adobe Remote Update Manager executable
$ARUMPath = "C:\Program Files (x86)\Common Files\Adobe\OOBE_Enterprise\RemoteUpdateManager\RemoteUpdateManager.exe"
# Define Latest Version of Adobe RUM executable
[version]$LatestVersion = "3.0.0.8"
# Define the search pattern to match in the output
$updatesrequired = "Following Updates are applicable on the system"
# Define the regex pattern to match Sap Codes, version numbers, and platforms
$regexpattern = '\((\w+)\/([\d\.]+)\/(win\d+)\)'
# Define a hash table of all product names for each Sap Code (sorted by Sap Code)
# N.B. Sap codes obtained from various Internet sources
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

#region Main process
if (!(Test-Path $LogPath)) {mkdir $LogPath -Force | Out-Null}

Start-Transcript -Path $LogFile -Force

try {
    if (Test-Path -Path $ARUMPath) {
        # Determine version of RUM installed
        [version]$InstalledVersion = (Get-ItemProperty $ARUMPath).VersionInfo.FileVersion

        # Run Adobe Remote Update Manager and capture its output
        $ARUMOutput = (& "$ARUMPath" --action=list) 2>&1 | Out-String

        # Use regex to find the app codes, version numbers, and platforms in the text string
        $discoveries = [regex]::Matches($ARUMOutput, $regexpattern)

        # Create an array to store the results
        $results = @()

        # Loop through the regex matches and add a row to the results array for each app
        foreach ($discovered in $discoveries) {
            $SapCode = $discovered.Groups[1].Value
            $versionNumber = $discovered.Groups[2].Value
            #$platform = $discovered.Groups[3].Value
            $productName = $productNames[$SapCode]

            <#
            # Add a row to the results array
            $results += [pscustomobject]@{
                "Product Name" = $productName
                "Sap Code" = $SapCode
                "Version Number" = $versionNumber
                "Platform Architecture" = $platform
            }
            #>
            $results += "$($productName) ($($SapCode)) (v$($versionNumber))"
        }
        
        # Convert $results array to a string and join each line with a comma (so content can be output in PR results)
        $resultsstring = (($results -join ", " ) -replace "`r`n", ", ").Trim()

        # Search the output for the string
        $ARUMStatus = $ARUMOutput | ForEach-Object {"$_" | Select-String -Pattern $updatesrequired}
        if ($ARUMStatus.Matches.Success -eq "True") {
            # proceed to remediation script
            If ($InstalledVersion -ge $LatestVersion){
                Write-Output "$($results.count) updates are required for the following Adobe Creative Cloud Apps: $($resultsstring)"
                exit 1 # Return a non-zero exit code to trigger the remediation
            } else {
                Write-Output "$($results.count) updates are required for the following Adobe Creative Cloud Apps: $($resultsstring) N.B. Adobe RUM is not the latest version ($($LatestVersion)), the version on this machine ($($InstalledVersion)) should be updated"
                exit 1 # Return a non-zero exit code to trigger the remediation
            }
        } else {
            # nothing further to do
            If ($InstalledVersion -ge $LatestVersion){
                Write-Output "No updates are required for Adobe Creative Cloud Apps"
                exit 0  # Return a zero exit code to indicate success
            } else {
                Write-Output "No updates are required for Adobe Creative Cloud Apps. N.B. Adobe RUM is not the latest version ($($LatestVersion)), the version on this machine ($($InstalledVersion)) should be updated"
                exit 0  # Return a zero exit code to indicate success
            }
        }
    } else {
        Write-Output "Adobe RUM not found N.B. Check if RUM should exist on this device"
        exit 0
    }
} catch {
    $errorMsg = $_.Exception.Message
} finally {
    if ($errorMsg) {
        Write-Output "Something went wrong: $errorMsg"
        Stop-Transcript | Out-Null
        Throw $errorMsg
} else {
        Stop-Transcript | Out-Null
    }
}
#endregion
