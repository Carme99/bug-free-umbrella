<#
.SYNOPSIS
    Update ASP.NET Core runtimes, audit EOL channels, clean lower patches, auto install the .NET Uninstall Tool if needed, and produce a disk usage report.
    Architecture aware for x64 and x86 installations.

.DESCRIPTION
    This comprehensive script manages .NET runtime installations across your system:

    - Detects installed Microsoft.AspNetCore.App and Microsoft.WindowsDesktop.App per major.minor channel for x64 and x86
    - Queries official releases metadata to determine latest patch and support phase
    - Installs updates when needed per architecture
    - Flags EOL (End of Life) channels and removes them automatically when permitted
    - Always prunes lower patch versions per channel after updates and EOL removal (falls back to filesystem cleanup if the uninstall tool is unavailable)
    - Installs the .NET Uninstall Tool if missing (optional) and uses it to clean lower patches and remove EOL channels across x64 and x86
    - Produces a disk usage report before and after actions with reclaimable and reclaimed space
    - Optionally exports the report to CSV and JSON formats

.PARAMETER Approve
    Non-interactive mode. Automatically installs updates and removes EOL when -RemoveEol is set. Defaults to $true for one-shot cleanup.

.PARAMETER RemoveEol
    Automatically remove EOL ASP.NET Core runtimes when approval is granted. Defaults to $true for one-shot cleanup.

.PARAMETER CleanupLowerPatches
    Always on: after updates and EOL handling prune lower patches within each major.minor channel
    for Microsoft.NETCore.App, Microsoft.AspNetCore.App, and Microsoft.WindowsDesktop.App.

.PARAMETER AutoInstallUninstallTool
    If the uninstall tool is missing download and install the latest MSI then proceed with cleanup actions. Defaults to $true.

.PARAMETER UninstallToolMsiUrl
    Optional override for the uninstall tool MSI URL. If omitted a pinned release URL is used.

.PARAMETER Arch
    Optional limiter for update and cleanup processing x64 or x86. If omitted both x64 and x86 are processed where present.

.PARAMETER LtsOnly
    Only consider LTS (Long Term Support) channels when updating. EOL audit still runs for all installed channels.

.PARAMETER IncludeChannels
    Restrict update consideration to specific channels e.g. '8.0', '9.0'.

.PARAMETER MinVersion
    Do not install if the latest version is below this floor e.g. '8.0.10'.

.PARAMETER LogPath
    Path to a transcript log file for detailed logging.

.PARAMETER ReportPath
    Optional CSV file path to export disk usage report.

.PARAMETER JsonSummaryPath
    Optional path to a JSON summary of actions and disk usage.

.PARAMETER ForceFileCleanup
    Enabled by default to remove lower patches even when the uninstall tool is not available.

.PARAMETER Interactive
    Optional interactive setup for switches with prompts for all parameters.

.PARAMETER DryRun
    Preview actions without changing the system. Use this to see what would happen.

.EXAMPLE
    .\Update-DotNetRuntimes.ps1

    Runs with default settings: auto-approve, remove EOL, cleanup lower patches, auto-install uninstall tool.

.EXAMPLE
    .\Update-DotNetRuntimes.ps1 -Interactive

    Prompts for all configuration options before proceeding.

.EXAMPLE
    .\Update-DotNetRuntimes.ps1 -DryRun

    Preview what would be updated/removed without making changes.

.EXAMPLE
    .\Update-DotNetRuntimes.ps1 -LtsOnly -IncludeChannels 8.0,9.0

    Only update LTS channels 8.0 and 9.0.

.EXAMPLE
    .\Update-DotNetRuntimes.ps1 -Arch x64 -LogPath "C:\Logs\dotnet-update.log"

    Update only x64 runtimes and save detailed log.

.EXAMPLE
    .\Update-DotNetRuntimes.ps1 -RemoveEol:$false -Approve:$false

    Interactive mode without auto-removal of EOL runtimes.

.EXAMPLE
    .\Update-DotNetRuntimes.ps1 -ReportPath "C:\Reports\dotnet-disk.csv" -JsonSummaryPath "C:\Reports\summary.json"

    Generate both CSV and JSON reports of disk usage and actions.

.NOTES
    File Name      : Update-DotNetRuntimes.ps1
    Author         : Bug-Free Umbrella
    Prerequisite   : PowerShell 5.1+, Administrator privileges (for install/uninstall)
    Version        : 1.0.0
    Date           : 2025-12-30

    IMPORTANT:
    - Run as Administrator for install/uninstall operations
    - Requires dotnet.exe at C:\Program Files\dotnet\dotnet.exe
    - Uses C:\Program Files (x86)\dotnet\dotnet.exe for x86 discovery
    - Internet connection required for downloading updates and metadata
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [switch]$Approve = $true,

    [Parameter(Mandatory=$false)]
    [switch]$RemoveEol = $true,

    [Parameter(Mandatory=$false)]
    [switch]$CleanupLowerPatches = $true,

    [Parameter(Mandatory=$false)]
    [switch]$AutoInstallUninstallTool = $true,

    [Parameter(Mandatory=$false)]
    [switch]$ForceFileCleanup = $true,

    [Parameter(Mandatory=$false)]
    [switch]$Interactive = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false,

    [Parameter(Mandatory=$false)]
    [string]$UninstallToolMsiUrl,

    [Parameter(Mandatory=$false)]
    [ValidateSet('x64','x86')]
    [string]$Arch,

    [Parameter(Mandatory=$false)]
    [switch]$LtsOnly,

    [Parameter(Mandatory=$false)]
    [string[]]$IncludeChannels,

    [Parameter(Mandatory=$false)]
    [version]$MinVersion,

    [Parameter(Mandatory=$false)]
    [string]$LogPath,

    [Parameter(Mandatory=$false)]
    [string]$ReportPath,

    [Parameter(Mandatory=$false)]
    [string]$JsonSummaryPath
)

#------------------------- Globals --------------------------#

$script:UserAgent = "aspnetcore-runtime-maintainer/1.0 (PowerShell $($PSVersionTable.PSVersion); OS $([Environment]::OSVersion.VersionString))"
# Use a versioned MSI asset to avoid 404
$script:DefaultUninstallMsiUrl = 'https://github.com/dotnet/cli-lab/releases/download/1.7.656206/dotnet-core-uninstall.msi'
$script:ReleaseCache = @{}
$script:ActionLog = @()

function Initialize-NetworkDefaults {
    try {
        $protocols = [System.Net.ServicePointManager]::SecurityProtocol
        if ($protocols -band [System.Net.SecurityProtocolType]::Tls12 -eq 0) {
            [System.Net.ServicePointManager]::SecurityProtocol = $protocols -bor [System.Net.SecurityProtocolType]::Tls12
        }
    } catch {
        Write-Warning "Failed to configure TLS 1.2: $($_.Exception.Message)"
    }
}

#------------------------- Helpers UI + Version parsing -------------#

function Write-Section {
    param(
        [string]$Text,
        [ConsoleColor]$Color='Cyan'
    )
    Write-Host ""
    Write-Host ("=== {0} ===" -f $Text) -ForegroundColor $Color
}

function Show-RainbowBar {
    param([string]$Label)
    $colors = @('Red','Yellow','Green','Cyan','Blue','Magenta')
    Write-Host $Label -ForegroundColor White
    $bar = "████████████████████"
    $i = 0
    foreach ($ch in $bar.ToCharArray()) {
        $color = $colors[$i % $colors.Count]
        Write-Host -NoNewline $ch -ForegroundColor $color
        $i++
        Start-Sleep -Milliseconds 15
    }
    Write-Host ""
}

function Convert-ToSafeVersion {
    param([string]$VersionString)
    if ([string]::IsNullOrWhiteSpace($VersionString)) { return $null }
    $clean = $VersionString.Split('-')[0]
    try {
        return [version]$clean
    } catch {
        Write-Verbose "Failed to parse version: $VersionString"
        return $null
    }
}

function Write-Banner {
    Write-Host ""
    Write-Host "    ██████╗  ██████╗ ████████╗███╗   ██╗███████╗████████╗" -ForegroundColor Cyan
    Write-Host "    ██╔══██╗██╔═══██╗╚══██╔══╝████╗  ██║██╔════╝╚══██╔══╝" -ForegroundColor Cyan
    Write-Host "    ██║  ██║██║   ██║   ██║   ██╔██╗ ██║█████╗     ██║   " -ForegroundColor Cyan
    Write-Host "    ██║  ██║██║   ██║   ██║   ██║╚██╗██║██╔══╝     ██║   " -ForegroundColor Cyan
    Write-Host "    ██████╔╝╚██████╔╝   ██║   ██║ ╚████║███████╗   ██║   " -ForegroundColor Cyan
    Write-Host "    ╚═════╝  ╚═════╝    ╚═╝   ╚═╝  ╚═══╝╚══════╝   ╚═╝   " -ForegroundColor Cyan
    Write-Host ""
    Write-Host "        Runtime Maintenance & EOL Cleanup Tool" -ForegroundColor Magenta
    Write-Host "            ASP.NET Core • WindowsDesktop • Base Runtime" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Status {
    param(
        [string]$Label,
        [ValidateSet('info','ok','warn','error')]
        [string]$Level='info',
        [string]$Detail
    )
    $tag,$color = switch ($Level) {
        'ok'    { '[OK]', 'Green' }
        'warn'  { '[WARN]','Yellow' }
        'error' { '[FAIL]','Red' }
        default { '[INFO]','Cyan' }
    }
    if ($Detail) {
        Write-Host ("{0} {1} - {2}" -f $tag,$Label,$Detail) -ForegroundColor $color
    } else {
        Write-Host ("{0} {1}" -f $tag,$Label) -ForegroundColor $color
    }
}

function Add-Action {
    param(
        [string]$Type,
        [string]$Channel,
        [string]$Arch,
        [string]$Detail
    )
    $script:ActionLog += [PSCustomObject]@{
        Type    = $Type
        Channel = $Channel
        Arch    = $Arch
        Detail  = $Detail
    }
}

function Write-ActionRecap {
    param([object[]]$Actions)
    Write-Section -Text "Action recap" -Color Magenta
    if (-not $Actions -or $Actions.Count -eq 0) {
        Write-Host "No runtime changes were made." -ForegroundColor Yellow
        return
    }
    $fmt = "{0,-12} | {1,-8} | {2,-6} | {3}"
    Write-Host ($fmt -f "Type","Channel","Arch","Detail")
    Write-Host ($fmt -f ("-"*12),("-"*8),("-"*6),("-"*30))
    foreach ($a in $Actions) {
        Write-Host ($fmt -f $a.Type,$a.Channel,$a.Arch,$a.Detail)
    }
}

function Write-UsageTable {
    param(
        [string]$Title,
        [object[]]$Summary
    )
    Write-Section -Text $Title -Color Magenta
    if (-not $Summary -or $Summary.Count -eq 0) {
        Write-Host "No runtimes detected." -ForegroundColor Yellow
        return
    }
    $maxBytes = ($Summary | Measure-Object -Property TotalBytes -Maximum).Maximum
    $fmt = "{0,-28} | {1,-7} | {2,14} | {3}"
    Write-Host ($fmt -f "Product/Root/Channel","Top","Total","Bar")
    Write-Host ($fmt -f ("-"*28),("-"*7),("-"*14),("-"*32))
    foreach ($s in ($Summary | Sort-Object Product,Root,Channel)) {
        $barLen = if ($maxBytes -gt 0) { [math]::Max(1,[math]::Round(($s.TotalBytes/$maxBytes)*32)) } else { 1 }
        $bar = ("#" * $barLen).PadRight(32,".")
        $label = "$($s.Product.Split('.')[-1]) @$($s.Root.Split('\\')[-2]) $($s.Channel)"
        Write-Host ($fmt -f $label,$s.HighestPatch,(Format-Bytes $s.TotalBytes),$bar)
    }
}

function Write-Box {
    param(
        [string]$Title,
        [string[]]$Lines,
        [ConsoleColor]$Color='DarkCyan'
    )
    $all = @($Title) + $Lines
    $width = ($all | Measure-Object -Property Length -Maximum).Maximum + 4
    $top = "╔" + ("═" * ($width-2)) + "╗"
    $bottom = "╚" + ("═" * ($width-2)) + "╝"
    Write-Host $top -ForegroundColor $Color
    $titleLine = "║ " + $Title.PadRight($width-4) + " ║"
    Write-Host $titleLine -ForegroundColor $Color
    foreach ($l in $Lines) {
        $line = "║ " + $l.PadRight($width-4) + " ║"
        Write-Host $line -ForegroundColor $Color
    }
    Write-Host $bottom -ForegroundColor $Color
}

function Get-ActionStats {
    param([object[]]$Actions)
    $stats = @{
        Updated        = 0
        'EOL-Removed'  = 0
        'EOL-Upgraded' = 0
        Current        = 0
        Skipped        = 0
        Cleanup        = 0
    }
    foreach ($a in $Actions) {
        if ($stats.ContainsKey($a.Type)) { $stats[$a.Type]++ }
    }
    return $stats
}

function Write-ActionSummary {
    param(
        [object[]]$Actions,
        [long]$ReclaimedBytes
    )
    $stats = Get-ActionStats -Actions $Actions
    $lines = @(
        ("Updated        : {0}" -f $stats.Updated),
        ("EOL removed    : {0}" -f $stats.'EOL-Removed'),
        ("EOL upgraded   : {0}" -f $stats.'EOL-Upgraded'),
        ("Already current: {0}" -f $stats.Current),
        ("Skipped        : {0}" -f $stats.Skipped),
        ("Cleanup runs   : {0}" -f $stats.Cleanup),
        ("Reclaimed      : {0}" -f (Format-Bytes $ReclaimedBytes))
    )
    Write-Box -Title "Runtime Maintenance Summary" -Lines $lines -Color DarkGreen
}

#------------------------- Helpers General --------------------------#

function Start-TypedTranscript {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $dir = Split-Path -Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Start-Transcript -Path $Path -Append -ErrorAction Stop | Out-Null
        Write-Verbose "Transcript started at: $Path"
    } catch {
        Write-Warning "Failed to start transcript at '$Path': $($_.Exception.Message)"
    }
}

function Stop-TypedTranscript {
    try {
        Stop-Transcript | Out-Null
    } catch {
        Write-Verbose "Transcript stop failed or wasn't running"
    }
}

function Test-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-YesNoDefault {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )
    $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $resp = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($resp)) { return $Default }
        switch -regex ($resp.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default { Write-Host "Please answer Y or N" -ForegroundColor Yellow }
        }
    }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [int]$Attempts=3,
        [int]$DelaySeconds=2
    )
    $last = $null
    for ($i=1; $i -le $Attempts; $i++) {
        try {
            return & $ScriptBlock
        }
        catch {
            $last = $_
            if ($i -lt $Attempts) {
                Write-Verbose "Retry attempt $i/$Attempts failed, waiting $DelaySeconds seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }
    throw $last
}

#------------------------- Helpers Discovery (x64 + x86) ------------#

function Get-InstalledProductByArch {
    param(
        [string]$DotnetPath,
        [string]$ProductRegex,      # e.g. '^Microsoft\.AspNetCore\.App\s+\d+\.\d+\.\d+'
        [string]$ArchLabel          # 'x64' or 'x86'
    )
    if (-not (Test-Path $DotnetPath)) { return @() }

    try {
        $list = & $DotnetPath --list-runtimes 2>$null
    } catch {
        Write-Warning "Failed to list runtimes from $DotnetPath : $($_.Exception.Message)"
        return @()
    }

    if (-not $list) { return @() }

    $lines = $list | Where-Object { $_ -match $ProductRegex }
    $objs = foreach ($line in $lines) {
        $parts = $line -split '\s+'
        if ($parts.Count -lt 2) { continue }
        $version = $parts[1]
        $semver = $version.Split('-')[0]
        if (-not ($semver -match '^\d+\.\d+\.\d+')) { continue }
        $v = Convert-ToSafeVersion -VersionString $version
        if (-not $v) { continue }
        [PSCustomObject]@{
            MajorMinor   = "$($v.Major).$($v.Minor)"
            Patch        = [int]$v.Build
            FullVersion  = $v
            RawVersion   = $version
            Architecture = $ArchLabel
        }
    }

    # Group per channel and tag with architecture
    $groups = @()
    foreach ($g in ($objs | Group-Object MajorMinor)) {
        $groups += [PSCustomObject]@{
            Name         = $g.Name
            Group        = $g.Group
            Architecture = $ArchLabel
        }
    }
    return $groups
}

function Get-AllInstalledAspNetCoreRuntimes {
    $all = @()
    $all += Get-InstalledProductByArch -DotnetPath "C:\Program Files\dotnet\dotnet.exe" -ProductRegex '^Microsoft\.AspNetCore\.App\s+\d+\.\d+\.\d+' -ArchLabel 'x64'
    $all += Get-InstalledProductByArch -DotnetPath "C:\Program Files (x86)\dotnet\dotnet.exe" -ProductRegex '^Microsoft\.AspNetCore\.App\s+\d+\.\d+\.\d+' -ArchLabel 'x86'
    $all
}

function Get-AllInstalledWindowsDesktopRuntimes {
    $all = @()
    $all += Get-InstalledProductByArch -DotnetPath "C:\Program Files\dotnet\dotnet.exe" -ProductRegex '^Microsoft\.WindowsDesktop\.App\s+\d+\.\d+\.\d+' -ArchLabel 'x64'
    $all += Get-InstalledProductByArch -DotnetPath "C:\Program Files (x86)\dotnet\dotnet.exe" -ProductRegex '^Microsoft\.WindowsDesktop\.App\s+\d+\.\d+\.\d+' -ArchLabel 'x86'
    $all
}

function Get-ReleasesIndex {
    $url = "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json"
    Invoke-WithRetry -ScriptBlock {
        Invoke-RestMethod -Uri $url -ErrorAction Stop -Headers @{ 'User-Agent' = $script:UserAgent } -UseBasicParsing
    }
}

function Get-ChannelMetadata {
    param(
        [object]$IndexData,
        [string]$MajorMinor,
        [switch]$LtsOnly
    )
    $channels = $IndexData.'releases-index'
    if ($LtsOnly) {
        $channels = $channels | Where-Object { $_.'release-type' -eq 'lts' -and $_.'support-phase' -ne 'eol' }
    }
    $channels | Where-Object { $_.'channel-version' -eq $MajorMinor } | Select-Object -First 1
}

function Get-ReleaseData {
    param([string]$ReleasesJsonUrl)
    Invoke-WithRetry -ScriptBlock {
        Invoke-RestMethod -Uri $ReleasesJsonUrl -ErrorAction Stop -Headers @{ 'User-Agent' = $script:UserAgent } -UseBasicParsing
    }
}

function Get-OrAddReleaseData {
    param([string]$ReleasesJsonUrl)
    if ($script:ReleaseCache.ContainsKey($ReleasesJsonUrl)) {
        return $script:ReleaseCache[$ReleasesJsonUrl]
    }
    $data = Get-ReleaseData -ReleasesJsonUrl $ReleasesJsonUrl
    $script:ReleaseCache[$ReleasesJsonUrl] = $data
    $data
}

function Get-LatestAspNetCoreVersion {
    param([object]$ReleaseData)
    $latest = $ReleaseData.'latest-aspnetcore-runtime'
    if (-not $latest) { $latest = $ReleaseData.'latest-runtime' }
    if (-not $latest) { return $null }
    $release = $ReleaseData.releases | Where-Object { $_.'release-version' -eq $latest } | Select-Object -First 1
    $verObj = Convert-ToSafeVersion -VersionString $latest
    if ($release -and $verObj) {
        [PSCustomObject]@{ Version=$verObj; Release=$release }
    } else {
        $null
    }
}

function Get-LatestWindowsDesktopVersion {
    param([object]$ReleaseData)
    $latest = $ReleaseData.'latest-windowsdesktop-runtime'
    if (-not $latest) { $latest = $ReleaseData.'latest-runtime' }
    if (-not $latest) { return $null }
    $release = $ReleaseData.releases | Where-Object { $_.'release-version' -eq $latest } | Select-Object -First 1
    $verObj = Convert-ToSafeVersion -VersionString $latest
    if ($release -and $verObj) {
        [PSCustomObject]@{ Version=$verObj; Release=$release }
    } else {
        $null
    }
}

function Get-ReplacementLtsChannel {
    param([object]$IndexData)

    # Get all active LTS channels (not EOL)
    $ltsChannels = $IndexData.'releases-index' | Where-Object {
        $_.'release-type' -eq 'lts' -and $_.'support-phase' -ne 'eol'
    } | Sort-Object { [version]$_.'channel-version' }

    if ($ltsChannels -and $ltsChannels.Count -gt 0) {
        # Return the oldest active LTS (most stable)
        return $ltsChannels[0]
    }
    return $null
}

#------------------------- Helpers Download Install -----------------#

function Get-AspNetCoreDownload {
    param(
        [object]$Release,
        [string]$Arch
    )
    $files = $Release.'aspnetcore-runtime'.files
    if (-not $files) { return $null }
    $rid = "win-$Arch"
    $files | Where-Object { $_.rid -eq $rid -and $_.url -match '\.exe$' } | Select-Object -First 1
}

function Get-DotNetRuntimeDownload {
    param(
        [object]$Release,
        [string]$Arch
    )
    $rid = "win-$Arch"
    $rt = $Release.runtime.files | Where-Object { $_.rid -eq $rid -and $_.url -match '\.exe$' } | Select-Object -First 1
    if ($rt) { return $rt }
    $wd = $Release.windowsdesktop.files | Where-Object { $_.rid -eq $rid -and $_.url -match '\.exe$' } | Select-Object -First 1
    $wd
}

function Get-WindowsDesktopDownload {
    param(
        [object]$Release,
        [string]$Arch
    )
    $files = $Release.windowsdesktop.files
    if (-not $files) { return $null }
    $rid = "win-$Arch"
    $files | Where-Object { $_.rid -eq $rid -and $_.url -match '\.exe$' } | Select-Object -First 1
}

function Save-FileWithRetry {
    param(
        [string]$Url,
        [string]$Destination,
        [int]$MinBytes = 10240
    )
    Invoke-WithRetry -ScriptBlock {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop -Headers @{ 'User-Agent' = $script:UserAgent }
    }
    $file = Get-Item -LiteralPath $Destination -ErrorAction SilentlyContinue
    if (-not $file -or $file.Length -lt $MinBytes) {
        throw "Downloaded file looks invalid (Size: $($file.Length) bytes, Expected: >$MinBytes bytes) at $Destination"
    }
}

function Test-FileHashIfAvailable {
    param(
        [string]$FilePath,
        [string]$Sha512
    )
    if (-not $Sha512) {
        Write-Verbose "No SHA512 hash provided for verification, skipping..."
        return $true
    }
    try {
        $hash = Get-FileHash -Path $FilePath -Algorithm SHA512
        if ($hash.Hash -ieq $Sha512) {
            Write-Verbose "Hash verification successful for $FilePath"
            return $true
        }
        Write-Warning "Hash mismatch for '$FilePath'`nExpected: $Sha512`nGot:      $($hash.Hash)"
        return $false
    } catch {
        Write-Warning "Hash check failed for '$FilePath': $($_.Exception.Message)"
        return $false
    }
}

function Install-Exe {
    param(
        [string]$Path,
        [string]$Arguments="/quiet /norestart"
    )
    if (-not (Test-Path $Path)) {
        throw "Installer not found at: $Path"
    }

    Write-Verbose "Installing: $Path with arguments: $Arguments"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Path
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()

    $exitCode = $proc.ExitCode
    Write-Verbose "Installer exited with code: $exitCode"

    if ($exitCode -ne 0 -and $exitCode -ne 3010) { # 3010 = reboot required
        throw "Installer exited with code $exitCode for $Path"
    }

    # Don't return the exit code to prevent it from being displayed
    # Just succeed silently or throw on error
}

#------------------------- Helpers Uninstall Tool -------------------#

function Get-DotnetUninstallToolPath {
    $candidates = @(
        "C:\Program Files\dotnet-core-uninstall\dotnet-core-uninstall.exe",
        "C:\Program Files (x86)\dotnet-core-uninstall\dotnet-core-uninstall.exe",
        "dotnet-core-uninstall.exe"
    )
    foreach ($p in $candidates) {
        try {
            $cmd = Get-Command $p -ErrorAction Stop
            if ($cmd -and $cmd.Source) { return $cmd.Source }
        } catch {
            Write-Verbose "Uninstall tool not found at: $p"
        }
    }
    return $null
}

function Install-DotnetUninstallTool {
    param([string]$UrlOverride)

    $existing = Get-DotnetUninstallToolPath
    if ($existing) {
        Write-Host "Uninstall tool already present at: $existing" -ForegroundColor Green
        return $true
    }

    $msiUrl = if ($UrlOverride) { $UrlOverride } else { $script:DefaultUninstallMsiUrl }
    Write-Host "Using uninstall tool URL: $msiUrl" -ForegroundColor Cyan

    $temp = Join-Path $env:TEMP ("dotnet-uninstall-tool-" + [Guid]::NewGuid().ToString("N") + ".msi")
    try {
        Write-Host "Downloading uninstall tool MSI..." -ForegroundColor Cyan
        Save-FileWithRetry -Url $msiUrl -Destination $temp -MinBytes 20480

        Write-Host "Installing uninstall tool (quiet mode)..." -ForegroundColor Yellow
        $args = "/i `"$temp`" /quiet /norestart"
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -PassThru -NoNewWindow

        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
            Write-Warning "MSI install returned exit code $($proc.ExitCode)"
            return $false
        }

        # Wait a moment for installation to complete
        Start-Sleep -Seconds 2

        $found = Get-DotnetUninstallToolPath
        if ($found) {
            Write-Host "Uninstall tool installed successfully at: $found" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "Uninstall tool not found after install"
            return $false
        }
    } catch {
        Write-Warning "Failed to install uninstall tool: $($_.Exception.Message)"
        return $false
    } finally {
        try { Remove-Item -Path $temp -Force -ErrorAction SilentlyContinue } catch {}
    }
}

#------------------------- Helpers EOL Removal ----------------------#

function Is-ChannelEol {
    param([object]$Channel)
    return ($Channel.'support-phase' -eq 'eol')
}

function Remove-AspNetCoreChannel {
    param([string]$MajorMinor)

    $tool = Get-DotnetUninstallToolPath
    if ($tool) {
        Write-Host "Using uninstall tool to remove ASP.NET Core $MajorMinor" -ForegroundColor Cyan
        $argsX64 = @("remove","--aspnet-runtime","--major-minor",$MajorMinor,"--yes","--x64")
        $argsX86 = @("remove","--aspnet-runtime","--major-minor",$MajorMinor,"--yes","--x86")

        if ($PSCmdlet.ShouldProcess("ASP.NET Core $MajorMinor","Remove with uninstall tool")) {
            $p1 = Start-Process -FilePath $tool -ArgumentList $argsX64 -Wait -PassThru -NoNewWindow
            if ($p1.ExitCode -ne 0) { Write-Warning "Uninstall tool exit code x64: $($p1.ExitCode)" }

            $p2 = Start-Process -FilePath $tool -ArgumentList $argsX86 -Wait -PassThru -NoNewWindow
            if ($p2.ExitCode -ne 0) { Write-Verbose "Uninstall tool exit code x86: $($p2.ExitCode)" }
        }
        return
    }

    Write-Warning "Uninstall tool not found. Falling back to MSI uninstall via registry..."

    $uninstallKeys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $targets = foreach ($keyPath in $uninstallKeys) {
        if (-not (Test-Path $keyPath)) { continue }
        Get-ChildItem $keyPath | ForEach-Object {
            $props = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
            $dn = $props.DisplayName
            $us = $props.UninstallString
            $dv = $props.DisplayVersion
            if ($dn -and $dn -match "Microsoft ASP.NET Core .*Shared Framework" -and $dv) {
                try {
                    $verObj = Convert-ToSafeVersion -VersionString $dv
                    if (-not $verObj) { continue }
                    $mm = "$($verObj.Major).$($verObj.Minor)"
                    if ($mm -eq $MajorMinor) {
                        [PSCustomObject]@{ Name=$dn; Version=$dv; UninstallString=$us }
                    }
                } catch {
                    Write-Verbose "Failed to process uninstall entry: $($_.Exception.Message)"
                }
            }
        }
    }

    foreach ($t in $targets) {
        Write-Host "Uninstalling $($t.Name) $($t.Version)..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($t.Name,"Uninstall via MSI")) {
            try {
                if ($t.UninstallString -match 'msiexec\.exe') {
                    $cmd = $t.UninstallString
                    if ($cmd -notmatch '/quiet') { $cmd += ' /quiet' }
                    if ($cmd -notmatch '/norestart') { $cmd += ' /norestart' }
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait -NoNewWindow
                } else {
                    Start-Process -FilePath $t.UninstallString -ArgumentList "/quiet /norestart" -Wait -NoNewWindow
                }
            } catch {
                Write-Warning "Failed to uninstall $($t.Name): $($_.Exception.Message)"
            }
        }
    }
}

function Remove-BaseRuntimeChannel {
    param([string]$MajorMinor)

    $tool = Get-DotnetUninstallToolPath
    if ($tool) {
        Write-Host "Using uninstall tool to remove Base .NET Runtime $MajorMinor" -ForegroundColor Cyan
        $argsX64 = @("remove","--runtime","--major-minor",$MajorMinor,"--yes","--x64")
        $argsX86 = @("remove","--runtime","--major-minor",$MajorMinor,"--yes","--x86")

        if ($PSCmdlet.ShouldProcess(".NET Runtime $MajorMinor","Remove with uninstall tool")) {
            $p1 = Start-Process -FilePath $tool -ArgumentList $argsX64 -Wait -PassThru -NoNewWindow
            if ($p1.ExitCode -ne 0) { Write-Warning "Uninstall tool exit code runtime x64: $($p1.ExitCode)" }

            $p2 = Start-Process -FilePath $tool -ArgumentList $argsX86 -Wait -PassThru -NoNewWindow
            if ($p2.ExitCode -ne 0) { Write-Verbose "Uninstall tool exit code runtime x86: $($p2.ExitCode)" }
        }
        return
    }

    Write-Warning "Uninstall tool not found for base runtime. Consider manual removal."
}

#------------------------- Helpers Disk usage -----------------------#

function Get-FolderSizeBytes {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    } catch {
        Write-Verbose "Failed to calculate folder size for $Path : $($_.Exception.Message)"
        0
    }
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    elseif ($Bytes -lt 1MB) { return ("{0:N2} KB" -f ($Bytes/1KB)) }
    elseif ($Bytes -lt 1GB) { return ("{0:N2} MB" -f ($Bytes/1MB)) }
    else { return ("{0:N2} GB" -f ($Bytes/1GB)) }
}

function Get-PatchObjectsFromShared {
    param(
        [string]$SharedRoot,
        [string]$ProductFolderName
    )
    $productPath = Join-Path $SharedRoot $ProductFolderName
    if (-not (Test-Path $productPath)) { return @() }

    $patchFolders = Get-ChildItem -LiteralPath $productPath -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^\d+\.\d+\.\d+$'
    }

    foreach ($pf in $patchFolders) {
        try {
            $v = [version]$pf.Name
            $bytes = Get-FolderSizeBytes -Path $pf.FullName
            [PSCustomObject]@{
                Root       = $SharedRoot
                Product    = $ProductFolderName
                Version    = $pf.Name
                MajorMinor = "$($v.Major).$($v.Minor)"
                Patch      = [int]$v.Build
                Bytes      = [long]$bytes
                Path       = $pf.FullName
            }
        } catch {
            Write-Verbose "Failed to process patch folder $($pf.Name): $($_.Exception.Message)"
        }
    }
}

function Get-DiskUsageSnapshot {
    $roots = @("C:\Program Files\dotnet\shared","C:\Program Files (x86)\dotnet\shared") | Where-Object { Test-Path $_ }
    $products = @("Microsoft.NETCore.App","Microsoft.AspNetCore.App","Microsoft.WindowsDesktop.App")
    $entries = @()
    foreach ($root in $roots) {
        foreach ($prod in $products) {
            $entries += Get-PatchObjectsFromShared -SharedRoot $root -ProductFolderName $prod
        }
    }
    $entries
}

function Summarize-DiskUsage {
    param([object[]]$Entries)
    $grouped = $Entries | Group-Object { "$($_.Product)|$($_.Root)|$($_.MajorMinor)" }
    $summary = foreach ($g in $grouped) {
        $items = $g.Group
        $topPatch = ($items | Sort-Object Patch -Descending | Select-Object -First 1)
        $total = ($items | Measure-Object -Property Bytes -Sum).Sum
        $lower = ($items | Where-Object { $_.Patch -lt $topPatch.Patch } | Measure-Object -Property Bytes -Sum).Sum
        $parts = $g.Name -split '\|'
        [PSCustomObject]@{
            Product      = $parts[0]
            Root         = $parts[1]
            Channel      = $parts[2]
            HighestPatch = $topPatch.Version
            TotalBytes   = [long]$total
            LowerBytes   = [long]$lower
        }
    }
    $summary
}

function Export-UsageCsv {
    param(
        [object[]]$Before,
        [object[]]$After,
        [string]$Path
    )
    try {
        $dir = Split-Path -Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $combined = @()
        foreach ($b in $Before) {
            $match = $After | Where-Object { $_.Product -eq $b.Product -and $_.Root -eq $b.Root -and $_.Channel -eq $b.Channel }
            $afterObj = if ($match) { $match } else {
                [PSCustomObject]@{
                    Product=$b.Product
                    Root=$b.Root
                    Channel=$b.Channel
                    HighestPatch=$b.HighestPatch
                    TotalBytes=0
                    LowerBytes=0
                }
            }
            $combined += [PSCustomObject]@{
                Product       = $b.Product
                Root          = $b.Root
                Channel       = $b.Channel
                BeforeTotal   = $b.TotalBytes
                BeforeLower   = $b.LowerBytes
                AfterTotal    = $afterObj.TotalBytes
                AfterLower    = $afterObj.LowerBytes
                Reclaimed     = $b.TotalBytes - $afterObj.TotalBytes
            }
        }
        $combined | Sort-Object Product,Root,Channel | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        Write-Host "Disk usage report exported to: $Path" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to export report: $($_.Exception.Message)"
    }
}

#------------------------- Helpers Post patch cleanup ---------------#

function Invoke-PostPatchCleanup {
    param([string]$ArchToClean)

    $tool = Get-DotnetUninstallToolPath
    if (-not $tool) {
        Write-Warning "Uninstall tool not found. Skipping patch cleanup. See Microsoft Learn for uninstall tool documentation."
        return
    }

    $targets = @(
        @{ Name="Base .NET Runtime"; Arg="--runtime" },
        @{ Name="ASP.NET Core Runtime"; Arg="--aspnet-runtime" },
        @{ Name="Windows Desktop Runtime"; Arg="--windowsdesktop-runtime" }
    )

    $archArgs = switch ($ArchToClean) {
        'x64' { @('--x64') }
        'x86' { @('--x86') }
        default { @() }
    }

    $results = @()
    foreach ($t in $targets) {
        $args = @('remove', $t.Arg, '--all-lower-patches', '--yes') + $archArgs
        $label = "$($t.Name) $ArchToClean"
        Write-Host "Cleaning lower patches for $label..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($label,"Remove lower patches")) {
            $p = Start-Process -FilePath $tool -ArgumentList $args -Wait -PassThru -NoNewWindow
            $results += [PSCustomObject]@{ Label=$label; ExitCode=$p.ExitCode; Arg=$t.Arg }

            # Exit code interpretation:
            # 0 = success
            # 1 = no matching items found (not an error, just nothing to clean)
            # Other = actual error
            if ($p.ExitCode -eq 0) {
                Write-Host "Cleanup complete for $label" -ForegroundColor Green
            } elseif ($p.ExitCode -eq 1) {
                Write-Verbose "$label cleanup: No lower patches found to remove"
                Write-Host "No lower patches found for $label" -ForegroundColor DarkGray
            } else {
                Write-Warning "$label cleanup returned exit code $($p.ExitCode)"
            }
        }
    }
    return $results
}

function Remove-FolderWithRetry {
    param(
        [string]$Path,
        [int]$MaxAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            # Try to unlock files that might be in use
            if ($attempt -gt 1) {
                Write-Verbose "Retry attempt $attempt for: $Path"
                Start-Sleep -Seconds 2
            }

            # First, try to remove read-only attributes
            Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $_.Attributes = 'Normal'
                } catch {
                    Write-Verbose "Could not normalize attributes for: $($_.FullName)"
                }
            }

            # Now try to remove the folder
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            Write-Verbose "Successfully removed: $Path"
            return $true
        } catch {
            if ($attempt -eq $MaxAttempts) {
                Write-Warning "Failed to remove $Path after $MaxAttempts attempts: $($_.Exception.Message)"
                Write-Host "  → Some files may be in use by running processes. Consider closing .NET applications and rerunning." -ForegroundColor DarkYellow
                return $false
            }
        }
    }
    return $false
}

function Remove-LowerPatchFolders {
    param(
        [object[]]$Entries,
        [string[]]$ProductsToClean
    )
    if (-not $Entries) { return }
    $filtered = $Entries | Where-Object { $_.Product -in $ProductsToClean }
    $groups = $filtered | Group-Object { "$($_.Root)|$($_.Product)|$($_.MajorMinor)" }

    $failedRemovals = 0
    $successfulRemovals = 0

    foreach ($g in $groups) {
        $items = $g.Group | Sort-Object Patch -Descending
        $keep = $items | Select-Object -First 1
        $remove = $items | Select-Object -Skip 1

        foreach ($r in $remove) {
            $target = $r.Path
            $label = "$($r.Product) $($r.MajorMinor) patch $($r.Version)"
            Write-Host "Removing lower patch folder: $label" -ForegroundColor Yellow
            if ($PSCmdlet.ShouldProcess($target,"Remove folder")) {
                $success = Remove-FolderWithRetry -Path $target -MaxAttempts 3
                if ($success) {
                    $successfulRemovals++
                } else {
                    $failedRemovals++
                }
            }
        }
    }

    if ($successfulRemovals -gt 0) {
        Write-Host "Successfully removed $successfulRemovals lower patch folder(s)" -ForegroundColor Green
    }
    if ($failedRemovals -gt 0) {
        Write-Host "Failed to remove $failedRemovals lower patch folder(s) - files may be in use" -ForegroundColor Yellow
    }
}

#------------------------- Main Script Logic ------------------------#

try {
    $ErrorActionPreference = 'Stop'
    $overallFailed = $false

    Initialize-NetworkDefaults
    Write-Banner

    if ($LogPath) {
        Start-TypedTranscript -Path $LogPath
    }

    # Interactive mode
    if ($Interactive) {
        Write-Host "--- Interactive setup ---" -ForegroundColor Magenta
        $Approve = Read-YesNoDefault -Prompt "Auto approve installs and removals" -Default:$Approve
        $RemoveEol = Read-YesNoDefault -Prompt "Remove EOL channels" -Default:$RemoveEol
        $AutoInstallUninstallTool = Read-YesNoDefault -Prompt "Auto install .NET Uninstall Tool if missing" -Default:$AutoInstallUninstallTool
        $LtsOnly = Read-YesNoDefault -Prompt "Limit updates to LTS channels" -Default:$LtsOnly
        Write-Host "Lower patch cleanup is mandatory and will run after updates." -ForegroundColor Yellow

        $archInput = Read-Host "Limit processing to architecture (x64/x86) or leave blank"
        if ($archInput -match '^(x64|x86)$') { $Arch = $archInput }

        $channelsInput = Read-Host "Include specific channels (comma separated, e.g. 8.0,9.0) or leave blank"
        if (-not [string]::IsNullOrWhiteSpace($channelsInput)) {
            $IncludeChannels = $channelsInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }

        $minInput = Read-Host "Minimum runtime version floor (e.g. 8.0.10) or leave blank"
        if (-not [string]::IsNullOrWhiteSpace($minInput)) {
            try { $MinVersion = [version]$minInput }
            catch { Write-Warning "Could not parse version '$minInput', ignoring MinVersion" }
        }

        $reportInput = Read-Host "CSV report path or leave blank"
        if (-not [string]::IsNullOrWhiteSpace($reportInput)) { $ReportPath = $reportInput }
    }

    # Enforce mandatory lower patch cleanup for remediation use
    if (-not $CleanupLowerPatches) {
        Write-Host "Lower patch cleanup cannot be disabled; enabling removal of lower patches." -ForegroundColor Yellow
        $CleanupLowerPatches = $true
    }
    if (-not $ForceFileCleanup) {
        Write-Host "Filesystem fallback cleanup is enabled to ensure lower patches are removed when the uninstall tool is unavailable." -ForegroundColor Yellow
        $ForceFileCleanup = $true
    }

    if ($Approve) { $ConfirmPreference = 'None' }

    # Admin check
    if (-not (Test-Admin)) {
        Write-Warning "Not running elevated. Install or uninstall may fail. Run PowerShell as Administrator."
    }

    # Verify dotnet.exe presence
    $dotnetPaths = @("C:\Program Files\dotnet\dotnet.exe","C:\Program Files (x86)\dotnet\dotnet.exe")
    $missingDotnet = $dotnetPaths | Where-Object { -not (Test-Path $_) }
    if ($missingDotnet.Count -eq $dotnetPaths.Count) {
        Write-Status -Label "dotnet.exe not found in standard locations; discovery will be empty." -Level warn
    }

    if (-not $UninstallToolMsiUrl) { $UninstallToolMsiUrl = $script:DefaultUninstallMsiUrl }

    # Disk usage snapshot before
    Write-Section -Text "Baseline disk usage" -Color Magenta
    $beforeEntries = Get-DiskUsageSnapshot
    $beforeSummary = Summarize-DiskUsage -Entries $beforeEntries
    Write-UsageTable -Title "Baseline disk usage" -Summary $beforeSummary

    # Prepare uninstall tool for cleanup
    if ($AutoInstallUninstallTool -and ($CleanupLowerPatches -or ($Approve -and $RemoveEol)) -and -not $DryRun) {
        Write-Host "Preparing uninstall tool for cleanup actions..." -ForegroundColor Magenta
        $ok = Install-DotnetUninstallTool -UrlOverride $UninstallToolMsiUrl
        if (-not $ok) {
            Write-Warning "Uninstall tool could not be installed. Cleanup actions may be skipped or use filesystem fallback."
        }
    }

    # Discover installed per architecture
    $installedAspGroups = Get-AllInstalledAspNetCoreRuntimes
    $installedDeskGroups = Get-AllInstalledWindowsDesktopRuntimes

    # Optional channel and arch filtering
    if ($IncludeChannels) {
        $installedAspGroups = $installedAspGroups | Where-Object { $_.Name -in $IncludeChannels }
        $installedDeskGroups = $installedDeskGroups | Where-Object { $_.Name -in $IncludeChannels }
    }
    if ($Arch) {
        $installedAspGroups = $installedAspGroups | Where-Object { $_.Architecture -eq $Arch }
        $installedDeskGroups = $installedDeskGroups | Where-Object { $_.Architecture -eq $Arch }
    }

    $index = $null
    if (($installedAspGroups -and $installedAspGroups.Count -gt 0) -or ($installedDeskGroups -and $installedDeskGroups.Count -gt 0)) {
        Write-Host "Fetching .NET releases metadata..." -ForegroundColor Cyan
        try {
            $index = Get-ReleasesIndex
        } catch {
            Write-Error "Failed to fetch releases index: $($_.Exception.Message)"
            throw
        }
    }

    # Process ASP.NET Core runtimes
    foreach ($group in $installedAspGroups) {
        $majorMinor = $group.Name
        $archLabel  = $group.Architecture
        Write-Host "=== ASP.NET Core Channel $majorMinor $archLabel ===" -ForegroundColor Cyan

        $channel = Get-ChannelMetadata -IndexData $index -MajorMinor $majorMinor
        if (-not $channel) {
            Write-Status -Label "No metadata found for .NET $majorMinor. Skipping." -Level warn
            continue
        }

        # EOL handling
        if (Is-ChannelEol -Channel $channel) {
            $versions = ($group.Group | Sort-Object FullVersion) | ForEach-Object { $_.RawVersion }
            $eolDate = $channel.'eol-date'
            Write-Host "EOL channel detected: $majorMinor | End of support: $eolDate | Installed: $($versions -join ', ')" -ForegroundColor Red

            # Suggest LTS replacement
            $replacementChannel = Get-ReplacementLtsChannel -IndexData $index
            if ($replacementChannel) {
                $replacementVersion = $replacementChannel.'channel-version'
                $replacementEol = $replacementChannel.'eol-date'
                Write-Host "  → Recommended replacement: .NET $replacementVersion LTS (supported until $replacementEol)" -ForegroundColor Cyan
            }

            $doRemove = $Approve -and $RemoveEol
            $doInstallReplacement = $false

            if (-not $Approve) {
                $resp = Read-Host "Remove ASP.NET Core $majorMinor $archLabel now? (Y/N)"
                if ($resp -in @('Y','y')) {
                    $doRemove = $true

                    # Ask if user wants to install replacement
                    if ($replacementChannel) {
                        $replResp = Read-Host "Install .NET $replacementVersion LTS as replacement? (Y/N)"
                        if ($replResp -in @('Y','y')) {
                            $doInstallReplacement = $true
                        }
                    }
                }
            } else {
                # In auto-approve mode, offer to install replacement
                if ($replacementChannel -and $RemoveEol) {
                    $doInstallReplacement = $true
                    Write-Host "  → Will install .NET $replacementVersion LTS after removal" -ForegroundColor Green
                }
            }

            if ($doRemove) {
                try {
                    if ($PSCmdlet.ShouldProcess("ASP.NET Core $majorMinor $archLabel","Remove EOL channel")) {
                        Remove-AspNetCoreChannel -MajorMinor $majorMinor
                        Remove-BaseRuntimeChannel -MajorMinor $majorMinor
                        Write-Host "Removal complete for EOL channel $majorMinor $archLabel" -ForegroundColor Green
                        Add-Action -Type 'EOL-Removed' -Channel $majorMinor -Arch $archLabel -Detail "Removed ASP.NET Core + base runtime"

                        # Install replacement if requested
                        if ($doInstallReplacement -and $replacementChannel) {
                            $replacementVersion = $replacementChannel.'channel-version'
                            Write-Host "Installing replacement: .NET $replacementVersion LTS $archLabel..." -ForegroundColor Cyan

                            try {
                                $replacementReleasesUrl = $replacementChannel.'releases.json'
                                $replacementReleaseData = Get-OrAddReleaseData -ReleasesJsonUrl $replacementReleasesUrl

                                $latestRepl = Get-LatestAspNetCoreVersion -ReleaseData $replacementReleaseData
                                if ($latestRepl) {
                                    $latestReplVersion = $latestRepl.Version
                                    $aspFile = Get-AspNetCoreDownload -Release $latestRepl.Release -Arch $archLabel
                                    $rtFile = Get-DotNetRuntimeDownload -Release $latestRepl.Release -Arch $archLabel

                                    if ($aspFile) {
                                        $temp = Join-Path $env:TEMP ("dotnet-updater-" + [Guid]::NewGuid().ToString('N'))
                                        New-Item -ItemType Directory -Path $temp -Force | Out-Null

                                        try {
                                            $aspPath = Join-Path $temp ("aspnetcore-$($latestReplVersion.ToString())-$archLabel.exe")
                                            Write-Host "Downloading ASP.NET Core Runtime $archLabel..." -ForegroundColor Cyan
                                            Save-FileWithRetry -Url $aspFile.url -Destination $aspPath
                                            Test-FileHashIfAvailable -FilePath $aspPath -Sha512 $aspFile.sha512 | Out-Null

                                            $rtPath = $null
                                            if ($rtFile) {
                                                $rtPath = Join-Path $temp ("dotnet-runtime-$($latestReplVersion.ToString())-$archLabel.exe")
                                                Write-Host "Downloading .NET Runtime $archLabel..." -ForegroundColor Cyan
                                                Save-FileWithRetry -Url $rtFile.url -Destination $rtPath
                                                Test-FileHashIfAvailable -FilePath $rtPath -Sha512 $rtFile.sha512 | Out-Null
                                            }

                                            if ($rtPath) {
                                                Write-Host "Installing .NET Runtime $($latestReplVersion.ToString()) $archLabel..." -ForegroundColor Cyan
                                                Install-Exe -Path $rtPath
                                            }

                                            Write-Host "Installing ASP.NET Core Runtime $($latestReplVersion.ToString()) $archLabel..." -ForegroundColor Cyan
                                            Install-Exe -Path $aspPath

                                            Write-Host "Successfully installed .NET $replacementVersion LTS ($latestReplVersion) $archLabel" -ForegroundColor Green
                                            Add-Action -Type 'EOL-Upgraded' -Channel $replacementVersion -Arch $archLabel -Detail "Installed $latestReplVersion as replacement for EOL $majorMinor"
                                        } finally {
                                            try { Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                                        }
                                    } else {
                                        Write-Warning "Could not find ASP.NET Core installer for .NET $replacementVersion $archLabel"
                                    }
                                } else {
                                    Write-Warning "Could not determine latest version for .NET $replacementVersion"
                                }
                            } catch {
                                Write-Warning "Failed to install replacement .NET $replacementVersion : $($_.Exception.Message)"
                            }
                        }
                    }
                } catch {
                    $overallFailed = $true
                    Write-Error "Failed to remove EOL ASP.NET Core $majorMinor : $($_.Exception.Message)"
                }
                continue
            } else {
                Write-Host "Skipped EOL removal for $majorMinor $archLabel" -ForegroundColor Yellow
                continue
            }
        }

        if ($LtsOnly -and $channel.'release-type' -ne 'lts' -and -not (Is-ChannelEol -Channel $channel)) {
            Write-Host "LTS-only mode: skipping updates for non-LTS channel $majorMinor $archLabel (still monitored for EOL)" -ForegroundColor Yellow
            Add-Action -Type 'Skipped' -Channel $majorMinor -Arch $archLabel -Detail "Non-LTS channel; LTS-only mode"
            continue
        }

        # Update path
        $releasesUrl = $channel.'releases.json'
        if (-not $releasesUrl) {
            Write-Host "Channel $majorMinor has no releases.json. Skipping." -ForegroundColor Yellow
            continue
        }

        try {
            $releaseData = Get-OrAddReleaseData -ReleasesJsonUrl $releasesUrl
        } catch {
            Write-Warning "Failed to fetch release data for $majorMinor : $($_.Exception.Message)"
            $overallFailed=$true
            continue
        }

        $latest = Get-LatestAspNetCoreVersion -ReleaseData $releaseData
        if (-not $latest) {
            Write-Host "No latest ASP.NET Core runtime found for $majorMinor. Skipping." -ForegroundColor Yellow
            continue
        }

        $latestVersion = $latest.Version
        $latestPatch = $latestVersion.Build
        $installedPatch = ($group.Group | Sort-Object Patch -Descending | Select-Object -First 1).Patch

        if ($MinVersion -and $latestVersion -lt $MinVersion) {
            Write-Host "Latest $majorMinor $latestVersion is below MinVersion $MinVersion. Skipping." -ForegroundColor Yellow
            Add-Action -Type 'Skipped' -Channel $majorMinor -Arch $archLabel -Detail "Latest $latestVersion below floor $MinVersion"
            continue
        }

        if ($latestPatch -le $installedPatch) {
            Write-Host "Up to date: $majorMinor.$installedPatch | Latest: $latestVersion ($archLabel)" -ForegroundColor Green
            Add-Action -Type 'Current' -Channel $majorMinor -Arch $archLabel -Detail "Latest $latestVersion already installed"
            continue
        }

        Write-Host "Update available: $majorMinor.$installedPatch → $latestVersion ($archLabel)" -ForegroundColor Yellow

        if (-not $Approve -and -not $DryRun) {
            $resp = Read-Host "Install update for $majorMinor $archLabel now? (Y/N)"
            if ($resp -notin @('Y','y')) {
                Write-Host "Skipping $majorMinor $archLabel by user choice" -ForegroundColor Yellow
                continue
            }
        }

        $aspFile = Get-AspNetCoreDownload -Release $latest.Release -Arch $archLabel
        if (-not $aspFile) {
            Write-Host "No ASP.NET Core runtime installer found for win-$archLabel in channel $majorMinor" -ForegroundColor Yellow
            continue
        }

        $rtFile = Get-DotNetRuntimeDownload -Release $latest.Release -Arch $archLabel

        $temp = Join-Path $env:TEMP ("dotnet-updater-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temp -Force | Out-Null

        try {
            $aspPath = Join-Path $temp ("aspnetcore-$($latestVersion.ToString())-$archLabel.exe")
            Write-Host "Downloading ASP.NET Core Runtime $archLabel..." -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess($aspFile.url, "Download to $aspPath")) {
                Save-FileWithRetry -Url $aspFile.url -Destination $aspPath
                if (-not (Test-FileHashIfAvailable -FilePath $aspPath -Sha512 $aspFile.sha512)) {
                    throw "Downloaded ASP.NET Core file failed integrity check"
                }
            }

            $rtPath = $null
            if ($rtFile) {
                $rtPath = Join-Path $temp ("dotnet-runtime-$($latestVersion.ToString())-$archLabel.exe")
                Write-Host "Downloading .NET Runtime $archLabel..." -ForegroundColor Cyan
                if ($PSCmdlet.ShouldProcess($rtFile.url, "Download to $rtPath")) {
                    Save-FileWithRetry -Url $rtFile.url -Destination $rtPath
                    if (-not (Test-FileHashIfAvailable -FilePath $rtPath -Sha512 $rtFile.sha512)) {
                        throw "Downloaded .NET Runtime file failed integrity check"
                    }
                }
            }

            if ($DryRun) {
                Write-Host "[DryRun] Would install ASP.NET Core $($latestVersion.ToString()) $archLabel" -ForegroundColor Yellow
            } elseif ($PSCmdlet.ShouldProcess("Install $majorMinor $archLabel to $($latestVersion.ToString())")) {
                if ($rtPath) {
                    Write-Host "Installing .NET Runtime $($latestVersion.ToString()) $archLabel..." -ForegroundColor Cyan
                    Install-Exe -Path $rtPath
                }

                Write-Host "Installing ASP.NET Core Runtime $($latestVersion.ToString()) $archLabel..." -ForegroundColor Cyan
                Install-Exe -Path $aspPath

                Write-Host "Update complete for $majorMinor $archLabel to $($latestVersion.ToString())" -ForegroundColor Green
                Add-Action -Type 'Updated' -Channel $majorMinor -Arch $archLabel -Detail "Installed $($latestVersion.ToString())"
            }
        } catch {
            $overallFailed = $true
            Write-Error "Failed to update $majorMinor $archLabel : $($_.Exception.Message)"
        } finally {
            try { Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

    # Process WindowsDesktop runtimes
    foreach ($group in $installedDeskGroups) {
        $majorMinor = $group.Name
        $archLabel  = $group.Architecture
        Write-Host "=== WindowsDesktop Channel $majorMinor $archLabel ===" -ForegroundColor Cyan

        $channel = Get-ChannelMetadata -IndexData $index -MajorMinor $majorMinor
        if (-not $channel) {
            Write-Status -Label "No metadata found for .NET $majorMinor. Skipping WindowsDesktop." -Level warn
            continue
        }

        if ($LtsOnly -and $channel.'release-type' -ne 'lts' -and -not (Is-ChannelEol -Channel $channel)) {
            Write-Host "LTS-only mode: skipping WindowsDesktop updates for non-LTS channel $majorMinor $archLabel (still monitored for EOL)" -ForegroundColor Yellow
            Add-Action -Type 'Skipped' -Channel $majorMinor -Arch $archLabel -Detail "WindowsDesktop non-LTS; LTS-only mode"
            continue
        }

        $releasesUrl = $channel.'releases.json'
        if (-not $releasesUrl) {
            Write-Host "Channel $majorMinor has no releases.json. Skipping WindowsDesktop." -ForegroundColor Yellow
            continue
        }

        try {
            $releaseData = Get-OrAddReleaseData -ReleasesJsonUrl $releasesUrl
        } catch {
            Write-Warning "Failed to fetch release data for $majorMinor : $($_.Exception.Message)"
            $overallFailed=$true
            continue
        }

        $latest = Get-LatestWindowsDesktopVersion -ReleaseData $releaseData
        if (-not $latest) {
            Write-Host "No latest WindowsDesktop runtime found for $majorMinor. Skipping." -ForegroundColor Yellow
            continue
        }

        $latestVersion = $latest.Version
        $latestPatch = $latestVersion.Build
        $installedPatch = ($group.Group | Sort-Object Patch -Descending | Select-Object -First 1).Patch

        if ($MinVersion -and $latestVersion -lt $MinVersion) {
            Write-Host "Latest WindowsDesktop $majorMinor $latestVersion is below MinVersion $MinVersion. Skipping." -ForegroundColor Yellow
            Add-Action -Type 'Skipped' -Channel $majorMinor -Arch $archLabel -Detail "WindowsDesktop latest $latestVersion below floor $MinVersion"
            continue
        }

        if ($latestPatch -le $installedPatch) {
            Write-Host "WindowsDesktop up to date: $majorMinor.$installedPatch | Latest: $latestVersion ($archLabel)" -ForegroundColor Green
            Add-Action -Type 'Current' -Channel $majorMinor -Arch $archLabel -Detail "WindowsDesktop latest $latestVersion already installed"
            continue
        }

        Write-Host "WindowsDesktop update available: $majorMinor.$installedPatch → $latestVersion ($archLabel)" -ForegroundColor Yellow

        if (-not $Approve -and -not $DryRun) {
            $resp = Read-Host "Install WindowsDesktop update for $majorMinor $archLabel now? (Y/N)"
            if ($resp -notin @('Y','y')) {
                Write-Host "Skipping WindowsDesktop $majorMinor $archLabel by user choice" -ForegroundColor Yellow
                continue
            }
        }

        $wdFile = Get-WindowsDesktopDownload -Release $latest.Release -Arch $archLabel
        if (-not $wdFile) {
            Write-Host "No WindowsDesktop runtime installer found for win-$archLabel in channel $majorMinor" -ForegroundColor Yellow
            continue
        }

        $temp = Join-Path $env:TEMP ("dotnet-updater-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temp -Force | Out-Null

        try {
            $wdPath = Join-Path $temp ("windowsdesktop-$($latestVersion.ToString())-$archLabel.exe")
            Write-Host "Downloading WindowsDesktop Runtime $archLabel..." -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess($wdFile.url, "Download to $wdPath")) {
                Save-FileWithRetry -Url $wdFile.url -Destination $wdPath
                if (-not (Test-FileHashIfAvailable -FilePath $wdPath -Sha512 $wdFile.sha512)) {
                    throw "Downloaded WindowsDesktop file failed integrity check"
                }
            }

            if ($DryRun) {
                Write-Host "[DryRun] Would install WindowsDesktop Runtime $($latestVersion.ToString()) $archLabel" -ForegroundColor Yellow
            } elseif ($PSCmdlet.ShouldProcess("Install WindowsDesktop $majorMinor $archLabel to $($latestVersion.ToString())")) {
                Write-Host "Installing WindowsDesktop Runtime $($latestVersion.ToString()) $archLabel..." -ForegroundColor Cyan
                Install-Exe -Path $wdPath
                Write-Host "Update complete for WindowsDesktop $majorMinor $archLabel to $($latestVersion.ToString())" -ForegroundColor Green
                Add-Action -Type 'Updated' -Channel $majorMinor -Arch $archLabel -Detail "WindowsDesktop $($latestVersion.ToString())"
            }
        } catch {
            $overallFailed = $true
            Write-Error "Failed to update WindowsDesktop $majorMinor $archLabel : $($_.Exception.Message)"
        } finally {
            try { Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

    # Post install patch cleanup
    Write-Section -Text "Post install patch cleanup" -Color Magenta
    Show-RainbowBar -Label "Removing lower patches (tool or filesystem fallback)"
    $toolPath = Get-DotnetUninstallToolPath

    if ($toolPath) {
        if ($Arch) {
            $cleanupResults = Invoke-PostPatchCleanup -ArchToClean $Arch
        } else {
            $cleanupResults = @()
            $cleanupResults += Invoke-PostPatchCleanup -ArchToClean 'x64'
            $cleanupResults += Invoke-PostPatchCleanup -ArchToClean 'x86'
        }
        # Exit code 1 means "no items found" which is not a failure
        # Only consider exit codes > 1 as failures
        $toolCleanupFailed = $cleanupResults | Where-Object { $_.ExitCode -gt 1 }
        foreach ($c in $cleanupResults) {
            $status = if ($c.ExitCode -eq 0) { "completed" } elseif ($c.ExitCode -eq 1) { "no items" } else { "failed" }
            Add-Action -Type 'Cleanup' -Channel $c.Arg -Arch $Arch -Detail "$($c.Label) - $status"
        }
    } else {
        Write-Warning "Uninstall tool not available. Using filesystem cleanup of lower patches."
        $cleanupEntries = Get-DiskUsageSnapshot
        if ($DryRun) {
            foreach ($c in ($cleanupEntries | Group-Object Product,MajorMinor)) {
                Write-Host "[DryRun] Would remove lower patches for $($c.Name)" -ForegroundColor Yellow
            }
        } else {
            Remove-LowerPatchFolders -Entries $cleanupEntries -ProductsToClean @("Microsoft.NETCore.App","Microsoft.AspNetCore.App","Microsoft.WindowsDesktop.App")
            Add-Action -Type 'Cleanup' -Channel 'filesystem' -Arch $Arch -Detail "Filesystem lower-patch removal"
        }
    }

    if ($toolPath -and $toolCleanupFailed -and -not $DryRun) {
        Write-Warning "Some uninstall tool cleanups failed. Falling back to filesystem cleanup for lower patches."
        $cleanupEntries = Get-DiskUsageSnapshot
        Remove-LowerPatchFolders -Entries $cleanupEntries -ProductsToClean @("Microsoft.NETCore.App","Microsoft.AspNetCore.App","Microsoft.WindowsDesktop.App")
    }

    # Verify cleanup
    Write-Section -Text "Verifying patch cleanup" -Color Magenta
    $verifyEntries = Get-DiskUsageSnapshot
    $verifySummary = Summarize-DiskUsage -Entries $verifyEntries
    $remainingLower = $verifySummary | Where-Object { $_.LowerBytes -gt 0 }
    if ($remainingLower) {
        Write-Host "Lower patch folders still present. Removing via filesystem cleanup..." -ForegroundColor Yellow
        if (-not $DryRun) {
            Remove-LowerPatchFolders -Entries $verifyEntries -ProductsToClean @("Microsoft.NETCore.App","Microsoft.AspNetCore.App","Microsoft.WindowsDesktop.App")
        } else {
            foreach ($r in $remainingLower) {
                Write-Host "[DryRun] Would remove lower patches for $($r.Product) $($r.Channel) under $($r.Root)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "No lower patch folders remain." -ForegroundColor Green
    }

    # Disk usage snapshot after
    Write-Section -Text "Disk usage after" -Color Magenta
    $afterEntries = Get-DiskUsageSnapshot
    $afterSummary = Summarize-DiskUsage -Entries $afterEntries
    Write-UsageTable -Title "Disk usage after" -Summary $afterSummary

    # Reclaimed space summary
    Write-Section -Text "Reclaimed space" -Color Magenta
    $reclaimRows = @()
    $reclaimedTotal = 0
    foreach ($b in $beforeSummary) {
        $a = $afterSummary | Where-Object { $_.Product -eq $b.Product -and $_.Root -eq $b.Root -and $_.Channel -eq $b.Channel }
        $afterBytes = if ($a) { $a.TotalBytes } else { 0 }
        $reclaimed = $b.TotalBytes - $afterBytes
        $reclaimedTotal += $reclaimed
        $reclaimRows += [PSCustomObject]@{
            Product   = $b.Product
            Root      = $b.Root
            Channel   = $b.Channel
            Reclaimed = $reclaimed
        }
    }
    $fmt = "{0,-28} | {1,-40} | {2,-7} | {3,14}"
    Write-Host ($fmt -f "Product","Root","Channel","Reclaimed")
    Write-Host ($fmt -f ("-"*28),("-"*40),("-"*7),("-"*14))
    foreach ($row in ($reclaimRows | Sort-Object Product,Root,Channel)) {
        Write-Output ($fmt -f $row.Product,$row.Root,$row.Channel,(Format-Bytes $row.Reclaimed))
    }
    Write-Host ("TOTAL reclaimed: {0}" -f (Format-Bytes $reclaimedTotal)) -ForegroundColor Green

    Write-ActionRecap -Actions $script:ActionLog
    Write-ActionSummary -Actions $script:ActionLog -ReclaimedBytes $reclaimedTotal

    if ($ReportPath) {
        Export-UsageCsv -Before $beforeSummary -After $afterSummary -Path $ReportPath
    }

    if ($JsonSummaryPath) {
        try {
            $summaryObj = [PSCustomObject]@{
                Timestamp      = (Get-Date).ToString("s")
                Approve        = $Approve.IsPresent
                RemoveEol      = $RemoveEol.IsPresent
                CleanupLower   = $CleanupLowerPatches.IsPresent
                LtsOnly        = $LtsOnly.IsPresent
                ArchLimit      = $Arch
                DryRun         = $DryRun.IsPresent
                DiskBefore     = $beforeSummary
                DiskAfter      = $afterSummary
                Actions        = $script:ActionLog
                ReclaimedBytes = $reclaimedTotal
                Errors         = $overallFailed
            }
            $dir = Split-Path -Path $JsonSummaryPath -Parent
            if ($dir -and -not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $summaryObj | ConvertTo-Json -Depth 6 | Out-File -FilePath $JsonSummaryPath -Encoding utf8
            Write-Host "JSON summary written to: $JsonSummaryPath" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to write JSON summary: $($_.Exception.Message)"
        }
    }

    if ($overallFailed) {
        Write-Host "Completed with some errors. Check the log for details." -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "All updates and cleanup processed successfully!" -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Error "Critical error during execution: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
finally {
    Stop-TypedTranscript
}
