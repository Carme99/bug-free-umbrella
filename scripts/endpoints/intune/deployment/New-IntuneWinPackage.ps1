<#
.SYNOPSIS
    Bulk converts application installers to .intunewin format for Intune deployment.
.DESCRIPTION
    Converts a single installer (-SetupFile) or every installer found under a folder
    (-SourceFolder) into .intunewin packages using the Microsoft Win32 Content Prep Tool
    (IntuneWinAppUtil.exe).

    Features:
    - Batch conversion of multiple installers
    - Automatic discovery or download of the Content Prep Tool when missing
    - Organized output structure under -OutputFolder
    - Timestamped PackageList CSV summarizing conversion results

    Re-running against the same inputs is safe: existing packages are overwritten by the
    prep tool and the run reports success as long as conversions succeed. Folder creation,
    package generation, and CSV export honor -WhatIf/-Confirm.
.PARAMETER SourceFolder
    Folder containing installer files to convert in batch mode.
.PARAMETER OutputFolder
    Where to save .intunewin packages. Default: MyDocuments\Reports\IntuneWinPackages.
.PARAMETER SetupFile
    Specific installer file to convert (single file mode). Takes precedence over
    -SourceFolder when both are supplied.
.PARAMETER ContentPrepToolPath
    Path to IntuneWinAppUtil.exe. If not provided, the script searches common locations
    and falls back to downloading the tool from GitHub.
.EXAMPLE
    PS C:\> .\New-IntuneWinPackage.ps1 -SourceFolder "C:\Installers"
    Converts all installers found under C:\Installers into .intunewin packages.
.EXAMPLE
    PS C:\> .\New-IntuneWinPackage.ps1 -SetupFile "C:\Installers\App\setup.exe" -OutputFolder "D:\Packages"
    Converts a single installer file and saves the package to D:\Packages.
.NOTES
    File Name   : New-IntuneWinPackage.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23

    Requires IntuneWinAppUtil.exe (Microsoft Win32 Content Prep Tool)
    Download from: https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool
    Each installer should be in its own subfolder for best results.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$SourceFolder,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder,

    [Parameter(Mandatory = $false)]
    [string]$SetupFile,

    [Parameter(Mandatory = $false)]
    [string]$ContentPrepToolPath
)

$ErrorActionPreference = 'Stop'

function Invoke-ContentPrepTool {
    # Thin wrapper around the native IntuneWinAppUtil.exe; returns the process exit code (mock seam for tests).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ToolPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceDir,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupFileName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationFolder
    )

    $process = Start-Process -FilePath $ToolPath `
        -ArgumentList "-c `"$SourceDir`" -s `"$SetupFileName`" -o `"$DestinationFolder`" -q" `
        -Wait -PassThru -NoNewWindow -ErrorAction Stop

    return $process.ExitCode
}

function Get-ContentPrepToolPath {
    # Resolves IntuneWinAppUtil.exe from common locations or downloads it on demand.
    [CmdletBinding()]
    param()

    # Check common locations
    $commonPaths = @(
        "$env:USERPROFILE\Downloads\IntuneWinAppUtil.exe",
        "$env:USERPROFILE\Desktop\IntuneWinAppUtil.exe",
        "$PSScriptRoot\IntuneWinAppUtil.exe",
        "C:\Tools\IntuneWinAppUtil.exe"
    )

    foreach ($candidate in $commonPaths) {
        if (Test-Path -LiteralPath $candidate) {
            Write-Host "[+] Found IntuneWinAppUtil.exe at: $candidate" -ForegroundColor Green
            return $candidate
        }
    }

    Write-Host "[-] IntuneWinAppUtil.exe not found" -ForegroundColor Red
    Write-Host "`n[*] Downloading Microsoft Win32 Content Prep Tool..." -ForegroundColor Yellow

    $downloadUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
    $downloadPath = Join-Path $env:USERPROFILE "Downloads\IntuneWinAppUtil.exe"

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing -ErrorAction Stop
        Write-Host "[+] Downloaded to: $downloadPath" -ForegroundColor Green
        return $downloadPath
    }
    catch {
        Write-Host "[-] Failed to download IntuneWinAppUtil.exe" -ForegroundColor Red
        Write-Host "`n[!] Please download manually from:" -ForegroundColor Yellow
        Write-Host "https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool" -ForegroundColor Cyan
        return $null
    }
}

function Convert-SingleInstaller {
    # Converts one setup file into a .intunewin package; returns a result object or $null on failure.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,

        [Parameter(Mandatory = $true)]
        [string]$ToolPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )

    $sourceDir = Split-Path -Path $InstallerPath -Parent
    $setupFileName = Split-Path -Path $InstallerPath -Leaf

    Write-Host "`n[*] Packaging: $setupFileName" -ForegroundColor Cyan
    Write-Host "  Source: $sourceDir" -ForegroundColor White
    Write-Host "  Output: $DestinationFolder" -ForegroundColor White

    $exitCode = Invoke-ContentPrepTool -ToolPath $ToolPath -SourceDir $sourceDir `
        -SetupFileName $setupFileName -DestinationFolder $DestinationFolder -ErrorAction Stop

    if ($exitCode -eq 0) {
        Write-Host "  [+] Package created successfully" -ForegroundColor Green

        $packageName = [System.IO.Path]::GetFileNameWithoutExtension($setupFileName)
        $intunewinFile = Join-Path $DestinationFolder "$packageName.intunewin"
        return [PSCustomObject]@{
            FileName    = $setupFileName
            PackagePath = $intunewinFile
            Status      = "Success"
        }
    }

    Write-Host "  [-] Failed to create package (Exit code: $exitCode)" -ForegroundColor Red
    return $null
}

function Convert-BatchInstallers {
    # Converts every installer under $SourceFolder; returns an array of per-file result objects.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerFolder,

        [Parameter(Mandatory = $true)]
        [string]$ToolPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )

    if (-not (Test-Path -LiteralPath $InstallerFolder)) {
        throw "Source folder not found: $InstallerFolder"
    }

    Write-Host "[*] Scanning for installer files in: $InstallerFolder" -ForegroundColor Cyan

    $installerExtensions = @("*.exe", "*.msi", "*.msix", "*.appx")
    $installerFiles = @()

    foreach ($ext in $installerExtensions) {
        $installerFiles += @(Get-ChildItem -LiteralPath $InstallerFolder -Filter $ext -Recurse -File)
    }

    if ($installerFiles.Count -eq 0) {
        Write-Host "[-] No installer files found in source folder" -ForegroundColor Red
        Write-Host "Looking for: $($installerExtensions -join ', ')" -ForegroundColor White
        return @()
    }

    Write-Host "[+] Found $($installerFiles.Count) installer files" -ForegroundColor Green

    $results = @()
    $counter = 0
    foreach ($installer in $installerFiles) {
        $counter++
        Write-Host "`n[$counter/$($installerFiles.Count)] Processing: $($installer.Name)" -ForegroundColor Cyan

        Write-Host "  Source: $($installer.DirectoryName)" -ForegroundColor White
        Write-Host "  Output: $DestinationFolder" -ForegroundColor White

        try {
            $exitCode = Invoke-ContentPrepTool -ToolPath $ToolPath -SourceDir $installer.DirectoryName `
                -SetupFileName $installer.Name -DestinationFolder $DestinationFolder -ErrorAction Stop

            if ($exitCode -eq 0) {
                Write-Host "  [+] Package created successfully" -ForegroundColor Green

                $packageName = [System.IO.Path]::GetFileNameWithoutExtension($installer.Name)
                $intunewinFile = Join-Path $DestinationFolder "$packageName.intunewin"
                $results += [PSCustomObject]@{
                    FileName    = $installer.Name
                    SourcePath  = $installer.FullName
                    PackagePath = $intunewinFile
                    PackageSize = (Get-PackageFileSize -Path $intunewinFile)
                    Status      = "Success"
                }
            }
            else {
                Write-Host "  [-] Failed (Exit code: $exitCode)" -ForegroundColor Red
                $results += [PSCustomObject]@{
                    FileName    = $installer.Name
                    SourcePath  = $installer.FullName
                    PackagePath = "N/A"
                    PackageSize = 0
                    Status      = "Failed"
                }
            }
        }
        catch {
            Write-Host "  [-] Error: $($_.Exception.Message)" -ForegroundColor Red
            $results += [PSCustomObject]@{
                FileName    = $installer.Name
                SourcePath  = $installer.FullName
                PackagePath = "N/A"
                PackageSize = 0
                Status      = "Error"
            }
        }
    }

    return $results
}

function Get-PackageFileSize {
    # Returns the size of an existing package file, or 0 when it does not exist yet.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        return (Get-Item -LiteralPath $Path).Length
    }

    return 0
}

function Show-PackagingSummary {
    # Prints the packaging summary, exports the result CSV, and lists failures.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Results,

        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "PACKAGING SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $successful = @($Results | Where-Object { $_.Status -eq "Success" })
    $failed = @($Results | Where-Object { $_.Status -ne "Success" })

    Write-Host "Total Processed:  $(@($Results).Count)" -ForegroundColor White
    Write-Host "Successful:       $($successful.Count)" -ForegroundColor Green
    $failedColor = if ($failed.Count -gt 0) { 'Red' } else { 'Green' }
    Write-Host "Failed:           $($failed.Count)" -ForegroundColor $failedColor

    if ($successful.Count -gt 0) {
        Write-Host "`nPackages Created:" -ForegroundColor Cyan
        foreach ($pkg in $successful) {
            $sizeKB = [math]::Round($pkg.PackageSize / 1KB, 2)
            Write-Host "  [+] $($pkg.FileName) ($sizeKB KB)" -ForegroundColor Green
        }

        Write-Host "`nOutput Location: $DestinationFolder" -ForegroundColor Cyan

        # Export list
        $csvPath = Join-Path $DestinationFolder "PackageList_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        if ($PSCmdlet.ShouldProcess($csvPath, 'Write package list CSV')) {
            @($successful + $failed) | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "Package list saved: $csvPath" -ForegroundColor White
        }
    }

    if ($failed.Count -gt 0) {
        Write-Host "`nFailed Packages:" -ForegroundColor Red
        foreach ($pkg in $failed) {
            Write-Host "  [-] $($pkg.FileName)" -ForegroundColor Red
        }
    }

    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "1. Upload .intunewin files to Intune portal" -ForegroundColor White
    Write-Host "2. Create Win32 app definitions" -ForegroundColor White
    Write-Host "3. Configure install/uninstall commands" -ForegroundColor White
    Write-Host "4. Set detection rules" -ForegroundColor White
    Write-Host "5. Assign to device groups" -ForegroundColor White
}

function Main {
    # Justification: Write-Host with colors is mandated by the relaunch output-prefix standard.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Intune .intunewin Package Creator" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan

        # Set output folder
        if (-not $OutputFolder) {
            $reportsRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
            $OutputFolder = Join-Path $reportsRoot 'IntuneWinPackages'
        }

        # Create output folder
        if (-not (Test-Path -LiteralPath $OutputFolder)) {
            if ($PSCmdlet.ShouldProcess($OutputFolder, 'Create output folder')) {
                New-Item -Path $OutputFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Write-Host "[+] Created output folder: $OutputFolder" -ForegroundColor Green
            }
        }

        # Check for Content Prep Tool
        if (-not $ContentPrepToolPath -or -not (Test-Path -LiteralPath $ContentPrepToolPath)) {
            Write-Host "[*] Searching for IntuneWinAppUtil.exe..." -ForegroundColor Cyan

            $resolved = Get-ContentPrepToolPath
            if (-not $resolved) {
                return 1
            }
            $ContentPrepToolPath = $resolved
        }

        # Validate Content Prep Tool
        if (-not (Test-Path -LiteralPath $ContentPrepToolPath)) {
            Write-Host "[-] IntuneWinAppUtil.exe not found at: $ContentPrepToolPath" -ForegroundColor Red
            return 1
        }

        Write-Host "[+] Using Content Prep Tool: $ContentPrepToolPath" -ForegroundColor Green

        # Process files
        $packagesCreated = @()
        $processed = $false

        if ($SetupFile) {
            # Single file mode
            if (-not (Test-Path -LiteralPath $SetupFile)) {
                Write-Host "[-] Setup file not found: $SetupFile" -ForegroundColor Red
                return 1
            }

            if (-not $PSCmdlet.ShouldProcess($SetupFile, 'Create .intunewin package')) {
                Write-Host "[*] WhatIf: would create package for $SetupFile" -ForegroundColor Cyan
                return 0
            }

            $result = Convert-SingleInstaller -InstallerPath $SetupFile -ToolPath $ContentPrepToolPath `
                -DestinationFolder $OutputFolder -ErrorAction Stop

            if ($result) {
                $packagesCreated += $result
                $processed = $true
            }
        }
        elseif ($SourceFolder) {
            # Batch mode - process all installers in source folder
            if (-not $PSCmdlet.ShouldProcess($SourceFolder, 'Create .intunewin packages for installers')) {
                Write-Host "[*] WhatIf: would process installers under $SourceFolder" -ForegroundColor Cyan
                return 0
            }

            $batchResults = Convert-BatchInstallers -InstallerFolder $SourceFolder -ToolPath $ContentPrepToolPath `
                -DestinationFolder $OutputFolder -ErrorAction Stop

            if (@($batchResults).Count -gt 0) {
                $packagesCreated += @($batchResults)
                $processed = $true
            }
        }
        else {
            Write-Host "[-] Please specify either -SourceFolder or -SetupFile" -ForegroundColor Red
            Write-Host "`nExamples:" -ForegroundColor Yellow
            Write-Host "  .\New-IntuneWinPackage.ps1 -SourceFolder 'C:\Installers'" -ForegroundColor White
            Write-Host "  .\New-IntuneWinPackage.ps1 -SetupFile 'C:\Installers\App.exe'" -ForegroundColor White
            return 1
        }

        if (-not $processed) {
            return 1
        }

        # Display summary
        Show-PackagingSummary -Results $packagesCreated -DestinationFolder $OutputFolder

        # Open output folder
        if (@($packagesCreated | Where-Object { $_.Status -eq "Success" }).Count -gt 0) {
            Write-Host "`n[*] Opening output folder..." -ForegroundColor Cyan
            try {
                Start-Process -FilePath $OutputFolder -ErrorAction Stop
            }
            catch {
                Write-Host "[!] Could not open output folder: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        Write-Host "`n[+] Packaging completed!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
