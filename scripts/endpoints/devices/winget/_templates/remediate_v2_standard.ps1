<#
.SYNOPSIS
    Standard winget update script that waits for app to close before updating.

.DESCRIPTION
    This template checks if an app update is available and installs it.
    If the app is running, it will skip the update and retry later.
    It prefers the Microsoft.WinGet.Client PowerShell module (the winget CLI is NOT
    supported in the SYSTEM context that Intune Proactive Remediations run in) and
    falls back to the winget.exe CLI only when the module is unavailable.

.NOTES
    REQUIRED: Only the winget ID is required. The script will auto-detect app name and process.

.CONFIGURATION
    1. Set the $ID variable to your winget package ID
    2. (Optional) Customize $name if you want a specific display name
    3. (Optional) Set $AppProcess if auto-detection doesn't work

.EXAMPLE
    # For Google Chrome, you only need to set:
    $ID = 'Google.Chrome'

    # The script will automatically use:
    # - Name: "Google Chrome" (from winget)
    # - Process: "chrome" (auto-detected)
#>

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'WINGETID'  # Example: 'Google.Chrome', 'Mozilla.Firefox', 'Adobe.Acrobat.Reader.64-bit'

# ===== OPTIONAL: Customize these if needed =====
$name = $null           # Leave as $null to auto-detect from winget, or set manually: 'Google Chrome'
$AppProcess = $null     # Leave as $null to auto-detect, or set manually: 'chrome'
#endregion

#region Script - DO NOT MODIFY BELOW THIS LINE
try {
    # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
    # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
    # winget.exe CLI when the module is unavailable.
    # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
    if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
        try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop } catch { }
        if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
            $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue

            # Auto-detect name if not provided
            if (-not $name) {
                $name = if ($package.Name) { $package.Name } else { $ID }
            }

            # Check if package is installed
            if (-not $package) {
                Write-Host "$name is not installed on this device."
                exit 0
            }

            # Check if update is available
            if ($package.IsUpdateAvailable) {
                $verInstalled = $package.InstalledVersion
                $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                Write-Verbose -Verbose "Application update available for $name. Current: $verInstalled, Available: $verAvailable"

                # Auto-detect process name if not provided
                if (-not $AppProcess) {
                    # Extract process name from package ID (e.g., 'Google.Chrome' -> 'chrome')
                    $AppProcess = ($ID -split '\.')[-1]
                }

                # Check if app is running
                $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Host "$name is currently running. Will try again later."
                    [pscustomobject] @{
                        Name = $name
                        InstalledVersion = $verInstalled
                        AvailableVersion = $verAvailable
                        Status = "Skipped - App Running"
                    }
                    exit 1
                }

                # Perform upgrade via the module
                Write-Host "Installing $name update ($verInstalled -> $verAvailable)..."
                Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -Mode Silent -Force -ErrorAction Stop

                # Verify installation
                Start-Sleep -Seconds 5
                $verifyPackage = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
                if ($verifyPackage) {
                    $versionInstalled = $verifyPackage.InstalledVersion
                    Write-Host "$name updated successfully to version $versionInstalled"
                    [pscustomobject] @{
                        Name = $name
                        InstalledVersion = $versionInstalled
                        Status = "Updated Successfully"
                    }
                    exit 0
                }
            }
            else {
                # No update available
                $versionInstalled = $package.InstalledVersion
                Write-Host "$name is already up to date (version $versionInstalled)"
                [pscustomobject] @{
                    Name = $name
                    InstalledVersion = $versionInstalled
                    Status = "Up to Date"
                }
                exit 0
            }
        }
    }

    # Fallback: winget.exe CLI (only reached when the Microsoft.WinGet.Client module is unavailable)
    # Locate winget executable
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $SystemContext = $wingetexe[-1].Path
    New-Alias -Name sysget -Value "$SystemContext" -Force

    # Get package information (exact ID match)
    $packageInfo = sysget list --exact --id $ID --accept-source-agreements 2>$null

    # Auto-detect name if not provided
    if (-not $name) {
        $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
        if ($nameMatch) {
            $name = $nameMatch.Matches[0].Groups[2].Value.Trim()
        }
        else {
            $name = $ID
        }
    }

    # Check if package is installed
    if ($packageInfo -match "No installed package found matching input criteria") {
        Write-Host "$name is not installed on this device."
        exit 0
    }

    # Check if update is available
    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3, -2]
        Write-Verbose -Verbose "Application update available for $name. Current: $verInstalled, Available: $verAvailable"

        # Auto-detect process name if not provided
        if (-not $AppProcess) {
            # Extract process name from package ID (e.g., 'Google.Chrome' -> 'chrome')
            $AppProcess = ($ID -split '\.')[-1]
        }

        # Check if app is running
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
        if ($process) {
            Write-Host "$name is currently running. Will try again later."
            [pscustomobject] @{
                Name = $name
                InstalledVersion = $verInstalled
                AvailableVersion = $verAvailable
                Status = "Skipped - App Running"
            }
            exit 1
        }

        # Perform upgrade
        Write-Host "Installing $name update ($verInstalled -> $verAvailable)..."
        sysget upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements

        # Verify installation
        Start-Sleep -Seconds 5
        $verifyInfo = sysget list --exact --id $ID --accept-source-agreements
        if ($verifyInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $verifyInfo[-1])[-2]
            Write-Host "$name updated successfully to version $versionInstalled"
            [pscustomobject] @{
                Name = $name
                InstalledVersion = $versionInstalled
                Status = "Updated Successfully"
            }
            exit 0
        }
    }
    else {
        # No update available
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Host "$name is already up to date (version $versionInstalled)"
            [pscustomobject] @{
                Name = $name
                InstalledVersion = $versionInstalled
                Status = "Up to Date"
            }
            exit 0
        }
    }
}
catch {
    $errMsg = $_.Exception.Message
    Write-Error "Failed to update $name : $errMsg"
    exit 1
}
#endregion
