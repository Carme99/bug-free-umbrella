<#
.SYNOPSIS
    Bulk converts installers to .intunewin format for Intune deployment.

.DESCRIPTION
    This script automates the conversion of application installers to .intunewin packages
    using the Microsoft Win32 Content Prep Tool. Supports batch processing of multiple apps.

    Features:
    - Batch conversion of multiple installers
    - Automatic download of Content Prep Tool if missing
    - Organized output structure
    - Validation of packages
    - Support for various installer types (EXE, MSI, etc.)

.PARAMETER SourceFolder
    Folder containing installer files to convert.

.PARAMETER OutputFolder
    Where to save .intunewin packages (default: Desktop\IntuneWinPackages).

.PARAMETER SetupFile
    Specific installer file to convert (for single file mode).

.PARAMETER ContentPrepToolPath
    Path to IntuneWinAppUtil.exe. If not provided, script will download it.

.EXAMPLE
    .\New-IntuneWinPackage.ps1 -SourceFolder "C:\Installers"
    Converts all installers in C:\Installers folder.

.EXAMPLE
    .\New-IntuneWinPackage.ps1 -SetupFile "C:\Installers\App.exe"
    Converts a single installer file.

.NOTES
    Requires IntuneWinAppUtil.exe (Microsoft Win32 Content Prep Tool)
    Download from: https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool
    Each installer should be in its own subfolder for best results
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$SourceFolder,

    [Parameter(Mandatory=$false)]
    [string]$OutputFolder,

    [Parameter(Mandatory=$false)]
    [string]$SetupFile,

    [Parameter(Mandatory=$false)]
    [string]$ContentPrepToolPath
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Intune .intunewin Package Creator" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Set output folder
if (-not $OutputFolder) {
    $OutputFolder = Join-Path $env:USERPROFILE "Desktop\IntuneWinPackages"
}

# Create output folder
if (-not (Test-Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    Write-Host "✓ Created output folder: $OutputFolder" -ForegroundColor Green
}

# Check for Content Prep Tool
if (-not $ContentPrepToolPath -or -not (Test-Path $ContentPrepToolPath)) {
    Write-Host "Searching for IntuneWinAppUtil.exe..." -ForegroundColor Cyan

    # Check common locations
    $commonPaths = @(
        "$env:USERPROFILE\Downloads\IntuneWinAppUtil.exe",
        "$env:USERPROFILE\Desktop\IntuneWinAppUtil.exe",
        "$PSScriptRoot\IntuneWinAppUtil.exe",
        "C:\Tools\IntuneWinAppUtil.exe"
    )

    $found = $false
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $ContentPrepToolPath = $path
            $found = $true
            Write-Host "✓ Found IntuneWinAppUtil.exe at: $path" -ForegroundColor Green
            break
        }
    }

    if (-not $found) {
        Write-Host "✗ IntuneWinAppUtil.exe not found" -ForegroundColor Red
        Write-Host "`nDownloading Microsoft Win32 Content Prep Tool..." -ForegroundColor Yellow

        $downloadUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
        $downloadPath = Join-Path $env:USERPROFILE "Downloads\IntuneWinAppUtil.exe"

        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing
            $ContentPrepToolPath = $downloadPath
            Write-Host "✓ Downloaded to: $downloadPath" -ForegroundColor Green
        }
        catch {
            Write-Host "✗ Failed to download IntuneWinAppUtil.exe" -ForegroundColor Red
            Write-Host "`nPlease download manually from:" -ForegroundColor Yellow
            Write-Host "https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool" -ForegroundColor Cyan
            exit 1
        }
    }
}

# Validate Content Prep Tool
if (-not (Test-Path $ContentPrepToolPath)) {
    Write-Host "✗ IntuneWinAppUtil.exe not found at: $ContentPrepToolPath" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Using Content Prep Tool: $ContentPrepToolPath" -ForegroundColor Green

# Process files
$packagesCreated = @()

if ($SetupFile) {
    # Single file mode
    if (-not (Test-Path $SetupFile)) {
        Write-Host "✗ Setup file not found: $SetupFile" -ForegroundColor Red
        exit 1
    }

    $sourceDir = Split-Path $SetupFile -Parent
    $setupFileName = Split-Path $SetupFile -Leaf

    Write-Host "`nPackaging: $setupFileName" -ForegroundColor Cyan
    Write-Host "  Source: $sourceDir" -ForegroundColor Gray
    Write-Host "  Output: $OutputFolder" -ForegroundColor Gray

    # Run Content Prep Tool
    $process = Start-Process -FilePath $ContentPrepToolPath `
        -ArgumentList "-c `"$sourceDir`" -s `"$setupFileName`" -o `"$OutputFolder`" -q" `
        -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -eq 0) {
        Write-Host "  ✓ Package created successfully" -ForegroundColor Green

        $intunewinFile = Join-Path $OutputFolder "$([System.IO.Path]::GetFileNameWithoutExtension($setupFileName)).intunewin"
        $packagesCreated += [PSCustomObject]@{
            FileName = $setupFileName
            PackagePath = $intunewinFile
            Status = "Success"
        }
    }
    else {
        Write-Host "  ✗ Failed to create package (Exit code: $($process.ExitCode))" -ForegroundColor Red
    }
}
elseif ($SourceFolder) {
    # Batch mode - process all installers in source folder
    if (-not (Test-Path $SourceFolder)) {
        Write-Host "✗ Source folder not found: $SourceFolder" -ForegroundColor Red
        exit 1
    }

    Write-Host "Scanning for installer files in: $SourceFolder" -ForegroundColor Cyan

    # Find all installer files
    $installerExtensions = @("*.exe", "*.msi", "*.msix", "*.appx")
    $installerFiles = @()

    foreach ($ext in $installerExtensions) {
        $installerFiles += Get-ChildItem -Path $SourceFolder -Filter $ext -Recurse -File
    }

    if ($installerFiles.Count -eq 0) {
        Write-Host "✗ No installer files found in source folder" -ForegroundColor Red
        Write-Host "Looking for: $($installerExtensions -join ', ')" -ForegroundColor Gray
        exit 1
    }

    Write-Host "✓ Found $($installerFiles.Count) installer files" -ForegroundColor Green

    # Process each installer
    $counter = 0
    foreach ($installer in $installerFiles) {
        $counter++
        Write-Host "`n[$counter/$($installerFiles.Count)] Processing: $($installer.Name)" -ForegroundColor Cyan

        $sourceDir = $installer.DirectoryName
        $setupFileName = $installer.Name

        Write-Host "  Source: $sourceDir" -ForegroundColor Gray
        Write-Host "  Output: $OutputFolder" -ForegroundColor Gray

        # Run Content Prep Tool
        try {
            $process = Start-Process -FilePath $ContentPrepToolPath `
                -ArgumentList "-c `"$sourceDir`" -s `"$setupFileName`" -o `"$OutputFolder`" -q" `
                -Wait -PassThru -NoNewWindow

            if ($process.ExitCode -eq 0) {
                Write-Host "  ✓ Package created successfully" -ForegroundColor Green

                $intunewinFile = Join-Path $OutputFolder "$([System.IO.Path]::GetFileNameWithoutExtension($setupFileName)).intunewin"
                $packagesCreated += [PSCustomObject]@{
                    FileName = $setupFileName
                    SourcePath = $installer.FullName
                    PackagePath = $intunewinFile
                    PackageSize = if (Test-Path $intunewinFile) { (Get-Item $intunewinFile).Length } else { 0 }
                    Status = "Success"
                }
            }
            else {
                Write-Host "  ✗ Failed (Exit code: $($process.ExitCode))" -ForegroundColor Red
                $packagesCreated += [PSCustomObject]@{
                    FileName = $setupFileName
                    SourcePath = $installer.FullName
                    PackagePath = "N/A"
                    PackageSize = 0
                    Status = "Failed"
                }
            }
        }
        catch {
            Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
            $packagesCreated += [PSCustomObject]@{
                FileName = $setupFileName
                SourcePath = $installer.FullName
                PackagePath = "N/A"
                PackageSize = 0
                Status = "Error"
            }
        }
    }
}
else {
    Write-Host "✗ Please specify either -SourceFolder or -SetupFile" -ForegroundColor Red
    Write-Host "`nExamples:" -ForegroundColor Yellow
    Write-Host "  .\New-IntuneWinPackage.ps1 -SourceFolder 'C:\Installers'" -ForegroundColor Gray
    Write-Host "  .\New-IntuneWinPackage.ps1 -SetupFile 'C:\Installers\App.exe'" -ForegroundColor Gray
    exit 1
}

# Display summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PACKAGING SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$successful = ($packagesCreated | Where-Object { $_.Status -eq "Success" }).Count
$failed = ($packagesCreated | Where-Object { $_.Status -ne "Success" }).Count

Write-Host "Total Processed:  $($packagesCreated.Count)" -ForegroundColor White
Write-Host "Successful:       $successful" -ForegroundColor Green
Write-Host "Failed:           $failed" -ForegroundColor $(if($failed -gt 0){'Red'}else{'Green'})

if ($successful -gt 0) {
    Write-Host "`nPackages Created:" -ForegroundColor Cyan
    $successPackages = $packagesCreated | Where-Object { $_.Status -eq "Success" }
    foreach ($pkg in $successPackages) {
        $sizeKB = [math]::Round($pkg.PackageSize / 1KB, 2)
        Write-Host "  ✓ $($pkg.FileName) ($sizeKB KB)" -ForegroundColor Green
    }

    Write-Host "`nOutput Location: $OutputFolder" -ForegroundColor Cyan

    # Export list
    $csvPath = Join-Path $OutputFolder "PackageList_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $packagesCreated | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Package list saved: $csvPath" -ForegroundColor Gray
}

if ($failed -gt 0) {
    Write-Host "`nFailed Packages:" -ForegroundColor Red
    $failedPackages = $packagesCreated | Where-Object { $_.Status -ne "Success" }
    foreach ($pkg in $failedPackages) {
        Write-Host "  ✗ $($pkg.FileName)" -ForegroundColor Red
    }
}

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Upload .intunewin files to Intune portal" -ForegroundColor White
Write-Host "2. Create Win32 app definitions" -ForegroundColor White
Write-Host "3. Configure install/uninstall commands" -ForegroundColor White
Write-Host "4. Set detection rules" -ForegroundColor White
Write-Host "5. Assign to device groups" -ForegroundColor White

# Open output folder
if ($successful -gt 0) {
    Write-Host "`nOpening output folder..." -ForegroundColor Cyan
    Start-Process $OutputFolder
}

Write-Host "`n✓ Packaging completed!" -ForegroundColor Green
