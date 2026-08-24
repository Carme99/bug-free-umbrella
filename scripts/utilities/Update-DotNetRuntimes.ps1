<#
.SYNOPSIS
    Update installed .NET runtimes, remove EOL channels, and clean lower patches safely.

.DESCRIPTION
    Complete dual-mode .NET runtime management solution:

    INTERACTIVE MODE:
    - Full-featured menu system with 11 options
    - Guided wizards for complex operations
    - Real-time system status and dependency analysis
    - Progress indicators and clear feedback

    AUTOMATED MODE:
    - Complete CLI automation for scripting
    - All parameters fully implemented
    - Plan preview and execution separation
    - Comprehensive reporting (CSV + JSON)

    CORE FEATURES:
    - Discovers installed runtimes (ASP.NET Core, Windows Desktop, Base Runtime)
    - Automatic EOL detection with Microsoft release index
    - Updates to latest patches with hash verification
    - Dependency analysis (IIS, services, scheduled tasks, processes)
    - Safe EOL removal with configurable protection
    - Lower patch cleanup with rollback support
    - Disk usage analysis and reclaim reporting
    - Security: SHA512 hash + Authenticode signature verification
    - Performance: Lazy loading, caching, .NET DirectoryInfo
    - Requires elevation: run from an elevated (Administrator) PowerShell session

.PARAMETER OneShotCleanup
    Preset for full maintenance: update, remove EOL, cleanup patches.

.PARAMETER NonInteractive
    Force non-interactive execution. No menu, no prompts.

.PARAMETER Approve
    Auto-approve all actions (no confirmation prompts).

.PARAMETER RemoveEol
    Allow EOL channel removal when dependencies permit.

.PARAMETER CleanupLowerPatches
    Remove lower patch versions after updates.

.PARAMETER AutoInstallUninstallTool
    Auto-install dotnet-core-uninstall tool if missing.

.PARAMETER ForceFileCleanup
    Use filesystem deletion if uninstall tool unavailable.

.PARAMETER IncludeHostingBundle
    Prefer ASP.NET Core Hosting Bundle when IIS detected.

.PARAMETER DependencyCheck
    EOL removal safety: Warn (default), Block, or Off.

.PARAMETER ForceEolRemoval
    Override DependencyCheck=Block. Use with caution!

.PARAMETER ProtectChannels
    Channels to never auto-remove (e.g., "6.0","3.1").

.PARAMETER PreferOldestLts
    Choose oldest supported LTS for EOL replacement.

.PARAMETER PlanOnly
    Generate execution plan and exit (no changes).

.PARAMETER Quiet
    Minimal console output (errors/warnings only).

.PARAMETER DryRun
    Preview all actions without making changes.

.PARAMETER UninstallToolMsiUrl
    Override URL for dotnet-core-uninstall MSI.

.PARAMETER Arch
    Limit processing to x64 or x86 (default: both).

.PARAMETER LtsOnly
    Only consider LTS channels for updates.

.PARAMETER IncludeChannels
    Restrict to specific channels (e.g., "8.0","9.0").

.PARAMETER MinVersion
    Minimum version floor (e.g., "8.0.10").

.PARAMETER LogPath
    Path to transcript log file.

.PARAMETER ReportPath
    CSV file path for action report export.

.PARAMETER JsonSummaryPath
    JSON file path for structured summary export.

.PARAMETER EnableRollback
    Create system restore point before major changes.
    System Restore is only available on client operating systems; on servers this
    step is skipped with a warning.
.EXAMPLE
    PS C:\> .\Update-DotNetRuntimes.ps1
    Launch the interactive menu system.

.EXAMPLE
    PS C:\> .\Update-DotNetRuntimes.ps1 -OneShotCleanup -LogPath "C:\Logs\dotnet.log"
    Run full automated maintenance with transcript logging.

.EXAMPLE
    PS C:\> .\Update-DotNetRuntimes.ps1 -PlanOnly -RemoveEol
    Preview planned updates and removals without making changes.

.EXAMPLE
    PS C:\> .\Update-DotNetRuntimes.ps1 -DependencyCheck Block -EnableRollback
    Run maximum safety mode with a system restore point before changes.

.NOTES
    File Name      : Update-DotNetRuntimes.ps1
    Author         : Bug-Free Umbrella
    Prerequisite   : PowerShell 5.1+
    Version        : 1.0.0
    Date           : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)][switch]$OneShotCleanup,
    [Parameter(Mandatory = $false)][switch]$NonInteractive,
    [Parameter(Mandatory = $false)][switch]$Approve,
    [Parameter(Mandatory = $false)][switch]$RemoveEol,
    [Parameter(Mandatory = $false)][switch]$CleanupLowerPatches,
    [Parameter(Mandatory = $false)][switch]$AutoInstallUninstallTool,
    [Parameter(Mandatory = $false)][switch]$ForceFileCleanup,
    [Parameter(Mandatory = $false)][switch]$IncludeHostingBundle,
    [Parameter(Mandatory = $false)][ValidateSet('Warn', 'Block', 'Off')][string]$DependencyCheck = 'Warn',
    [Parameter(Mandatory = $false)][switch]$ForceEolRemoval,
    [Parameter(Mandatory = $false)][string[]]$ProtectChannels,
    [Parameter(Mandatory = $false)][switch]$PreferOldestLts,
    [Parameter(Mandatory = $false)][switch]$PlanOnly,
    [Parameter(Mandatory = $false)][switch]$Quiet,
    [Parameter(Mandatory = $false)][switch]$DryRun,
    [Parameter(Mandatory = $false)]
    [ValidateScript({
            if ([string]::IsNullOrWhiteSpace($_)) { return $true }
            $uri = [uri]$_
            if ($uri.Scheme -ne 'https') { throw "URL must use HTTPS protocol" }
            # FIX: Use regex for subdomain protection (e.g., prevents evil-github.com)
            $allowedDomainPatterns = @(
                '^github\.com$',
                '^.*\.github\.com$',
                '^githubusercontent\.com$',
                '^.*\.githubusercontent\.com$',
                '^microsoft\.com$',
                '^.*\.microsoft\.com$',
                '^download\.microsoft\.com$'
            )
            $isAllowed = $false
            foreach ($pattern in $allowedDomainPatterns) {
                if ($uri.Host -match $pattern) {
                    $isAllowed = $true
                    break
                }
            }
            if (-not $isAllowed) {
                throw ("URL must be from trusted domain: *.github.com, *.githubusercontent.com, " +
                    "*.microsoft.com, or download.microsoft.com")
            }
            return $true
        })]
    [string]$UninstallToolMsiUrl,
    [Parameter(Mandatory = $false)][ValidateSet('x64', 'x86')][string]$Arch,
    [Parameter(Mandatory = $false)][switch]$LtsOnly,
    [Parameter(Mandatory = $false)][string[]]$IncludeChannels,
    [Parameter(Mandatory = $false)][version]$MinVersion,
    [Parameter(Mandatory = $false)][string]$LogPath,
    [Parameter(Mandatory = $false)][string]$ReportPath,
    [Parameter(Mandatory = $false)][string]$JsonSummaryPath,
    [Parameter(Mandatory = $false)][switch]$EnableRollback
)

# Captured at dot-source time: $PSBoundParameters is not visible inside function Main.
$script:IsInteractiveInvocation = ($PSBoundParameters.Count -eq 0)

# ========================= SCRIPT GLOBALS ========================= #

$script:Version = "1.0.0"
$script:UserAgent = "dotnet-maintainer/$script:Version (PowerShell $($PSVersionTable.PSVersion))"
$script:DefaultUninstallMsiUrl =
    'https://github.com/dotnet/cli-lab/releases/download/1.7.656206/dotnet-core-uninstall.msi'
$script:ReleaseCache = @{}
$script:ActionLog = @()
$script:LogEntries = @()
$script:RebootRequired = $false
$script:SystemCache = $null
$script:MenuState = @{ LastScanTime = $null; CacheValid = $false }

# Emoji disabled for cross-platform compatibility
$script:UseEmoji = $false

# ========================= LOGGING & OUTPUT ========================= #

function Write-ScriptLog {
    param(
        [Parameter(Mandatory)][ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Debug')][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [hashtable]$Context,
        [switch]$NoConsole
    )

    $ts = (Get-Date).ToString('s')
    $entry = [PSCustomObject]@{
        Timestamp = $ts
        Level = $Level
        Message = $Message
        Context = $Context
    }
    $script:LogEntries += $entry

    # Emit to proper PowerShell streams
    $fullMessage = if ($Context -and $Context.Count -gt 0) {
        $ctx = ($Context.Keys | Sort-Object | ForEach-Object { "$_=$($Context[$_])" }) -join ' '
        "$Message ($ctx)"
    }
    else { $Message }

    switch ($Level) {
        'Warn' { Write-Warning $fullMessage }
        'Error' { Write-Error $fullMessage -ErrorAction Continue }
        'Debug' { Write-Verbose $fullMessage }
        'Info' { Write-Information $fullMessage -InformationAction Continue }
        'Ok' { Write-Information $fullMessage -InformationAction Continue }
    }

    # Console output for interactive
    if ($NoConsole) { return }
    if ($Quiet -and $Level -notin @('Warn', 'Error')) { return }

    $prefix = switch ($Level) {
        'Ok' { '[+] ' }
        'Warn' { '[!] ' }
        'Error' { '[-] ' }
        'Debug' { '[DBG] ' }
        default { '[*] ' }
    }

    $color = switch ($Level) {
        'Ok' { 'Green' }
        'Warn' { 'Yellow' }
        'Error' { 'Red' }
        'Debug' { 'DarkGray' }
        default { 'Cyan' }
    }

    Write-Host "$prefix $fullMessage" -ForegroundColor $color
}

function Add-Action {
    param([string]$Type, [string]$Product, [string]$Channel, [string]$Arch,
        [string]$Detail, [int]$ExitCode = -1, [string]$Method)
    $script:ActionLog += [PSCustomObject]@{
        Type = $Type; Product = $Product; Channel = $Channel; Arch = $Arch;
        Detail = $Detail; ExitCode = $ExitCode; Method = $Method
    }
}


# ========================= UI HELPERS ========================= #

function Write-Banner {
    if ($Quiet) { return }
    Write-Host ""
    Write-Host "    ========================================================" -ForegroundColor Cyan
    Write-Host "              .NET RUNTIME MAINTENANCE TOOL" -ForegroundColor Cyan
    Write-Host "    ========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "        Runtime Maintenance Tool v$script:Version (Production-Ready)" -ForegroundColor Magenta
    Write-Host "            ASP.NET Core | WindowsDesktop | Base Runtime" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Section {
    param([string]$Text)
    if ($Quiet) { Write-ScriptLog -Level Info -Message $Text -NoConsole:$false; return }
    Write-Host ""
    Write-Host (("=" * 75)) -ForegroundColor Magenta
    Write-Host " $Text" -ForegroundColor White
    Write-Host (("=" * 75)) -ForegroundColor Magenta
}

function Read-YesNoDefault {
    param([string]$Prompt, [bool]$Default = $true)
    $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $resp = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($resp)) { return $Default }
        switch -regex ($resp.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$' { return $false }
            default { Write-Host "Please answer Y or N" -ForegroundColor Yellow }
        }
    }
}

function Read-MenuChoice {
    param([string]$Prompt = "Select option", [int]$Min = 0, [int]$Max = 99, [string[]]$ValidChoices)
    while ($true) {
        Write-Host ""
        $choice = Read-Host "$Prompt"
        if ($ValidChoices) {
            if ($choice -in $ValidChoices) { return $choice }
            Write-Host "Invalid. Choose from: $($ValidChoices -join ', ')" -ForegroundColor Yellow
        }
        else {
            if ($choice -match '^\d+$' -and [int]$choice -ge $Min -and [int]$choice -le $Max) {
                return [int]$choice
            }
            Write-Host "Invalid. Enter $Min-$Max" -ForegroundColor Yellow
        }
    }
}

# ========================= GENERAL HELPERS ========================= #

function Initialize-NetworkSecurityProtocol {
    try {
        # SECURITY: Enforce TLS 1.2+ only, disable weak protocols (SSL3, TLS 1.0, TLS 1.1)
        $tls12 = [System.Net.SecurityProtocolType]::Tls12

        # Check if TLS 1.3 is available (PowerShell 7+ / .NET Core 3.0+)
        $tls13 = $null
        try {
            $tls13 = [System.Net.SecurityProtocolType]::Tls13
        }
        catch {
            Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
        }

        # Set to TLS 1.2 + TLS 1.3 (if available), explicitly excluding weak protocols
        if ($tls13) {
            [System.Net.ServicePointManager]::SecurityProtocol = $tls12 -bor $tls13
            Write-ScriptLog -Level Info -Message "Enforced TLS 1.2 and TLS 1.3 (weak protocols disabled)"
        }
        else {
            [System.Net.ServicePointManager]::SecurityProtocol = $tls12
            Write-ScriptLog -Level Info -Message "Enforced TLS 1.2 only (weak protocols disabled)"
        }
    }
    catch {
        Write-ScriptLog -Level Warn -Message "TLS configuration failed" -Context @{ Error = $_.Exception.Message }
    }
}

function Start-TypedTranscript {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $dir = Split-Path -Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if ($PSCmdlet.ShouldProcess($Path, 'Start transcript')) {
            Start-Transcript -Path $Path -Append -ErrorAction Stop | Out-Null
        }
        Write-ScriptLog -Level Debug -Message "Transcript started" -Context @{ Path = $Path }
    }
    catch {
        Write-ScriptLog -Level Warn -Message "Transcript start failed" `
            -Context @{ Path = $Path; Error = $_.Exception.Message }
    }
}

function Stop-TypedTranscript {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        if ($PSCmdlet.ShouldProcess('Transcript', 'Stop transcript')) {
            Stop-Transcript | Out-Null
        }
    }
    catch { Write-ScriptLog -Level Debug -Message "Transcript stop failed" -Context @{ Error = $_.Exception.Message } }
}

function Test-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Convert-ToSafeVersion {
    param([string]$VersionString)
    if ([string]::IsNullOrWhiteSpace($VersionString)) { return $null }
    $clean = $VersionString.Split('-')[0]
    try { return [version]$clean } catch { return $null }
}

function Invoke-WithRetry {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock, [int]$Attempts = 3, [int]$DelaySeconds = 2)
    $last = $null
    for ($i = 1; $i -le $Attempts; $i++) {
        try { return & $ScriptBlock }
        catch {
            $last = $_
            if ($i -lt $Attempts) { Start-Sleep -Seconds $DelaySeconds }
        }
    }
    throw $last
}

function Format-ByteSize {
    param([long]$Bytes)
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    elseif ($Bytes -lt 1MB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    elseif ($Bytes -lt 1GB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    else { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
}

# ====================== NATIVE EXECUTABLE WRAPPERS ====================== #
# Thin wrappers are the ONLY place native executables are invoked; they check
# $LASTEXITCODE / process exit codes so Pester tests can mock them (spec §5).

function Invoke-DotnetRuntimeList {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DotnetPath)
    $output = & $DotnetPath --list-runtimes 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-ScriptLog -Level Warn -Message "dotnet --list-runtimes failed" `
            -Context @{ Dotnet = $DotnetPath; ExitCode = $LASTEXITCODE }
        return @()
    }
    return $output
}

function Invoke-AppCmdSiteList {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AppCmdPath)
    $out = & $AppCmdPath list site 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return $out
}

function Invoke-TrackedProcess {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$CommandLineArgs,
        [int]$TimeoutMinutes = 10
    )
    if (-not $PSCmdlet.ShouldProcess("$FilePath $CommandLineArgs", 'Start process')) {
        return [PSCustomObject]@{ ExitCode = -1; TimedOut = $false }
    }
    $p = Start-Process -FilePath $FilePath -ArgumentList $CommandLineArgs -PassThru -NoNewWindow
    $timeoutMs = $TimeoutMinutes * 60 * 1000
    if (-not $p.WaitForExit($timeoutMs)) {
        try { $p.Kill() }
        catch {
            Write-ScriptLog -Level Debug -Message "Process kill failed" -Context @{ Error = $_.Exception.Message }
        }
        return [PSCustomObject]@{ ExitCode = -1; TimedOut = $true }
    }
    return [PSCustomObject]@{ ExitCode = $p.ExitCode; TimedOut = $false }
}

# ========================= DEPENDENCY DETECTION ========================= #

function Test-IisPresent {
    if (Test-Path "$env:windir\System32\inetsrv") { return $true }
    $svc = Get-Service -Name 'W3SVC' -ErrorAction SilentlyContinue
    return ($null -ne $svc)
}

function Test-AncmPresent {
    $paths = @(
        "C:\Program Files\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll",
        "C:\Program Files (x86)\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $true } }
    return $false
}

function Get-IisSiteCount {
    $appcmd = "$env:windir\System32\inetsrv\appcmd.exe"
    if (-not (Test-Path $appcmd)) { return 0 }
    try {
        $out = Invoke-AppCmdSiteList -AppCmdPath $appcmd -ErrorAction Stop
        if (-not $out) { return 0 }
        return ($out | Measure-Object).Count
    }
    catch { return 0 }
}

function Test-DotnetDependency {
    param([string]$Channel)
    $dependencies = @()
    try {
        # Windows Services
        $services = Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue |
            Where-Object { $_.PathName -match 'dotnet' }
        foreach ($svc in $services) {
            $dependencies += [PSCustomObject]@{
                Type = 'Service'; Name = $svc.Name; Path = $svc.PathName; State = $svc.State
            }
        }

        # Scheduled Tasks
        if (Get-Command "Get-ScheduledTask" -ErrorAction SilentlyContinue) {
            $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
                $_.Actions.Execute -match 'dotnet' -or $_.Actions.WorkingDirectory -match 'dotnet'
            }
            foreach ($task in $tasks) {
                $dependencies += [PSCustomObject]@{
                    Type = 'ScheduledTask'; Name = $task.TaskName; Path = $task.TaskPath; State = $task.State
                }
            }
        }

        # Running processes
        $procs = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'dotnet.exe'" -ErrorAction SilentlyContinue
        foreach ($proc in $procs) {
            $dependencies += [PSCustomObject]@{
                Type = 'Process'; Name = "dotnet.exe (PID $($proc.ProcessId))"
                Path = $proc.ExecutablePath; CommandLine = $proc.CommandLine
            }
        }
    }
    catch {
        Write-ScriptLog -Level Debug -Message "Dependency scan failed" `
            -Context @{ Error = $_.Exception.Message; Function = $MyInvocation.MyCommand.Name }
    }
    return $dependencies
}

function Test-EolRemovalRisk {
    param([string]$Channel, [string]$ArchLabel)
    $iis = Test-IisPresent
    $ancm = Test-AncmPresent
    $sites = Get-IisSiteCount
    $deps = Test-DotnetDependency -Channel $Channel
    $reasons = New-Object System.Collections.Generic.List[string]
    $risk = 'None'

    if ($iis) { $reasons.Add("IIS detected"); $risk = 'Medium' }
    if ($ancm) { $reasons.Add("ANCM detected"); $risk = 'High' }
    if ($sites -gt 0) { $reasons.Add("IIS sites: $sites"); if ($risk -ne 'High') { $risk = 'Medium' } }
    if ($deps.Count -gt 0) {
        $reasons.Add("$($deps.Count) .NET dependencies")
        if ($risk -eq 'None') { $risk = 'Medium' }
    }

    [PSCustomObject]@{
        Channel = $Channel; Arch = $ArchLabel; RiskLevel = $risk
        Reasons = $reasons.ToArray(); Dependencies = $deps; BlockRecommended = ($risk -in @('Medium', 'High'))
    }
}

# ========================= DISCOVERY ========================= #

function Get-InstalledProductByArch {
    param([string]$DotnetPath, [string]$ProductRegex, [string]$ArchLabel)
    if (-not (Test-Path $DotnetPath)) { return @() }
    try { $list = Invoke-DotnetRuntimeList -DotnetPath $DotnetPath -ErrorAction Stop }
    catch {
        Write-ScriptLog -Level Warn -Message "List runtimes failed" `
            -Context @{ Dotnet = $DotnetPath; Error = $_.Exception.Message }
        return @()
    }
    if (-not $list) { return @() }

    $lines = $list | Where-Object { $_ -match $ProductRegex }
    $objs = foreach ($line in $lines) {
        $parts = $line -split '\s+'
        if ($parts.Count -lt 2) { continue }
        $v = Convert-ToSafeVersion -VersionString $parts[1]
        if (-not $v) { continue }
        [PSCustomObject]@{
            MajorMinor = "$($v.Major).$($v.Minor)"; Patch = [int]$v.Build; FullVersion = $v
            RawVersion = $parts[1]; Architecture = $ArchLabel
        }
    }

    $groups = @()
    foreach ($g in ($objs | Group-Object MajorMinor)) {
        $groups += [PSCustomObject]@{ Name = $g.Name; Group = $g.Group; Architecture = $ArchLabel }
    }
    return $groups
}

function Get-AllInstalledAspNetCoreRuntime {
    # FIX: Don't use Where-Object { $_ } as it returns $null for empty arrays
    # Get-InstalledProductByArch already returns @() when no runtimes found
    @(
        Get-InstalledProductByArch -DotnetPath "C:\Program Files\dotnet\dotnet.exe" `
            -ProductRegex '^Microsoft\.AspNetCore\.App\s+\d+\.\d+\.\d+' -ArchLabel 'x64'
        Get-InstalledProductByArch -DotnetPath "C:\Program Files (x86)\dotnet\dotnet.exe" `
            -ProductRegex '^Microsoft\.AspNetCore\.App\s+\d+\.\d+\.\d+' -ArchLabel 'x86'
    )
}

function Get-AllInstalledWindowsDesktopRuntime {
    # FIX: Don't use Where-Object { $_ } as it returns $null for empty arrays
    # Get-InstalledProductByArch already returns @() when no runtimes found
    @(
        Get-InstalledProductByArch -DotnetPath "C:\Program Files\dotnet\dotnet.exe" `
            -ProductRegex '^Microsoft\.WindowsDesktop\.App\s+\d+\.\d+\.\d+' -ArchLabel 'x64'
        Get-InstalledProductByArch -DotnetPath "C:\Program Files (x86)\dotnet\dotnet.exe" `
            -ProductRegex '^Microsoft\.WindowsDesktop\.App\s+\d+\.\d+\.\d+' -ArchLabel 'x86'
    )
}

# ========================= RELEASE METADATA ========================= #

function Get-ReleasesIndex {
    $url = "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json"
    Invoke-WithRetry -ScriptBlock {
        Invoke-RestMethod -Uri $url -ErrorAction Stop -Headers @{ 'User-Agent' = $script:UserAgent }
    }
}

function Get-ChannelEntry {
    param([object]$IndexData, [string]$MajorMinor, [switch]$LtsOnly)
    $channels = $IndexData.'releases-index'
    if ($LtsOnly) {
        $channels = $channels | Where-Object { $_.'release-type' -eq 'lts' -and $_.'support-phase' -ne 'eol' }
    }
    $channels | Where-Object { $_.'channel-version' -eq $MajorMinor } | Select-Object -First 1
}

function Get-ReleaseData {
    param([string]$ReleasesJsonUrl)
    Invoke-WithRetry -ScriptBlock {
        Invoke-RestMethod -Uri $ReleasesJsonUrl -ErrorAction Stop -Headers @{ 'User-Agent' = $script:UserAgent }
    }
}

function Get-OrAddReleaseData {
    param([string]$ReleasesJsonUrl)
    if ($script:ReleaseCache.ContainsKey($ReleasesJsonUrl)) { return $script:ReleaseCache[$ReleasesJsonUrl] }
    $data = Get-ReleaseData -ReleasesJsonUrl $ReleasesJsonUrl
    $script:ReleaseCache[$ReleasesJsonUrl] = $data
    return $data
}

function Get-LatestAspNetCoreVersion {
    param([object]$ReleaseData)
    $latest = $ReleaseData.'latest-aspnetcore-runtime'
    if (-not $latest) { $latest = $ReleaseData.'latest-runtime' }
    if (-not $latest) { return $null }
    $release = $ReleaseData.releases | Where-Object { $_.'release-version' -eq $latest } | Select-Object -First 1
    $verObj = Convert-ToSafeVersion -VersionString $latest
    if ($release -and $verObj) { [PSCustomObject]@{ Version = $verObj; Release = $release } } else { $null }
}

function Get-LatestWindowsDesktopVersion {
    param([object]$ReleaseData)
    $latest = $ReleaseData.'latest-windowsdesktop-runtime'
    if (-not $latest) { $latest = $ReleaseData.'latest-runtime' }
    if (-not $latest) { return $null }
    $release = $ReleaseData.releases | Where-Object { $_.'release-version' -eq $latest } | Select-Object -First 1
    $verObj = Convert-ToSafeVersion -VersionString $latest
    if ($release -and $verObj) { [PSCustomObject]@{ Version = $verObj; Release = $release } } else { $null }
}

# ========================= DOWNLOAD & INSTALL (Security Hardened) ========================= #

function Get-AspNetCoreDownload {
    param([object]$Release, [string]$ArchLabel)
    $files = $Release.'aspnetcore-runtime'.files
    if (-not $files) { return $null }
    $rid = "win-$ArchLabel"
    $files | Where-Object { $_.rid -eq $rid -and $_.url -match '\.exe$' } | Select-Object -First 1
}

function Get-WindowsDesktopDownload {
    param([object]$Release, [string]$ArchLabel)
    $files = $Release.windowsdesktop.files
    if (-not $files) { return $null }
    $rid = "win-$ArchLabel"
    $files | Where-Object { $_.rid -eq $rid -and $_.url -match '\.exe$' } | Select-Object -First 1
}

function Get-HostingBundleDownload {
    param([object]$Release)
    $candidates = @()
    try {
        if ($Release.'aspnetcore-runtime' -and $Release.'aspnetcore-runtime'.files) {
            $candidates += $Release.'aspnetcore-runtime'.files
        }
        if ($Release.runtime -and $Release.runtime.files) { $candidates += $Release.runtime.files }
        if ($Release.files) { $candidates += $Release.files }
    }
    catch {
        Write-ScriptLog -Level Debug -Message "Hosting bundle candidates collection failed" `
            -Context @{ Error = $_.Exception.Message }
    }
    $candidates = $candidates | Where-Object { $_ -and $_.url }
    $candidates | Where-Object {
        $_.url -match '\.exe$' -and
        ($_.rid -eq 'win-x64' -or -not $_.rid) -and
        ($_.url -match 'dotnet-hosting' -or $_.url -match 'hosting')
    } | Select-Object -First 1
}

function Save-FileWithRetry {
    [CmdletBinding()]
    param([string]$Url, [string]$Destination, [int]$MinBytes = 10240)
    Invoke-WithRetry -ScriptBlock {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -ErrorAction Stop `
            -Headers @{ 'User-Agent' = $script:UserAgent }
    }
    $file = Get-Item -LiteralPath $Destination -ErrorAction SilentlyContinue
    if (-not $file -or $file.Length -lt $MinBytes) { throw "Downloaded file invalid (Size: $($file.Length) bytes)" }
}

function Test-FileHashIfAvailable {
    param([string]$FilePath, [string]$Sha512)
    if (-not $Sha512) { return $true }
    try {
        $hash = Get-FileHash -Path $FilePath -Algorithm SHA512
        return ($hash.Hash -ieq $Sha512)
    }
    catch { return $false }
}

function Install-Exe {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path, [string]$Arguments = "/quiet /norestart", [int]$TimeoutMinutes = 10)
    if (-not (Test-Path $Path)) { throw "Installer not found: $Path" }
    $result = Invoke-TrackedProcess -FilePath $Path -CommandLineArgs $Arguments -TimeoutMinutes $TimeoutMinutes
    if ($result.TimedOut) { throw "Installer timed out after $TimeoutMinutes minutes" }
    $reboot = ($result.ExitCode -eq 3010)
    if ($result.ExitCode -ne 0 -and $result.ExitCode -ne 3010) {
        throw "Installer failed: exit code $($result.ExitCode)"
    }
    [PSCustomObject]@{ ExitCode = $result.ExitCode; RebootRequired = $reboot }
}

# ========================= UNINSTALL TOOL (Dynamic URL) ========================= #

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
        }
        catch {
            Write-ScriptLog -Level Debug -Message "Command lookup failed" `
                -Context @{ Path = $p; Error = $_.Exception.Message }
        }
    }
    return $null
}

function Get-LatestUninstallToolUrl {
    try {
        $api = "https://api.github.com/repos/dotnet/cli-lab/releases/latest"
        $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = $script:UserAgent } -ErrorAction Stop
        $asset = $release.assets | Where-Object { $_.name -match 'dotnet-core-uninstall.*\.msi$' } |
            Select-Object -First 1
        if ($asset) {
            Write-ScriptLog -Level Info -Message "Found latest uninstall tool" -Context @{ Version = $release.tag_name }
            return $asset.browser_download_url
        }
    }
    catch {
        Write-ScriptLog -Level Debug -Message "GitHub API check failed" `
            -Context @{ Error = $_.Exception.Message; Function = $MyInvocation.MyCommand.Name }
    }
    return $script:DefaultUninstallMsiUrl
}

function Install-DotnetUninstallTool {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$UrlOverride)
    $existing = Get-DotnetUninstallToolPath
    if ($existing) {
        Write-ScriptLog -Level Ok -Message "Uninstall tool present" -Context @{ Path = $existing }
        return $true
    }

    $msiUrl = if ($UrlOverride) { $UrlOverride } else { Get-LatestUninstallToolUrl }
    $temp = Join-Path $env:TEMP ("dotnet-uninstall-" + [Guid]::NewGuid().ToString("N") + ".msi")

    try {
        Write-ScriptLog -Level Info -Message "Downloading uninstall tool MSI"
        if ($PSCmdlet.ShouldProcess($msiUrl, "Download uninstall tool")) {
            Save-FileWithRetry -Url $msiUrl -Destination $temp -MinBytes 20480
        }

        # SECURITY FIX: Authenticode verification with publisher validation (always required, no bypass)
        Write-ScriptLog -Level Info -Message "Verifying digital signature and publisher"
        $sig = Get-AuthenticodeSignature -FilePath $temp
        if ($sig.Status -ne 'Valid') {
            Write-ScriptLog -Level Error -Message "MSI signature invalid - installation blocked" `
                -Context @{ Status = $sig.Status; Signer = $sig.SignerCertificate.Subject }
            throw "MSI signature validation failed. The downloaded file may be corrupted or tampered with."
        }

        # Verify publisher is Microsoft
        # FIX: Accept certificates where CN=Microsoft Corporation OR O=Microsoft Corporation
        # Microsoft uses product-specific CNs (like "CN=.NET") with "O=Microsoft Corporation"
        $publisher = $sig.SignerCertificate.Subject
        if ($publisher -notmatch 'CN=Microsoft Corporation' -and $publisher -notmatch 'O=Microsoft Corporation') {
            Write-ScriptLog -Level Error -Message "MSI publisher validation failed - not signed by Microsoft" `
                -Context @{ Publisher = $publisher }
            throw "Publisher validation failed. MSI must be signed by Microsoft Corporation."
        }

        # Check certificate expiration
        if ($sig.SignerCertificate.NotAfter -lt (Get-Date)) {
            Write-ScriptLog -Level Error -Message "Signer certificate has expired" `
                -Context @{ Expired = $sig.SignerCertificate.NotAfter }
            throw "Signer certificate has expired."
        }

        Write-ScriptLog -Level Ok -Message "Signature and publisher validated" -Context @{ Publisher = $publisher }

        Write-ScriptLog -Level Info -Message "Installing uninstall tool"
        if ($PSCmdlet.ShouldProcess($temp, "Install MSI")) {
            $msiArgs = "/i `"$temp`" /quiet /norestart"
            $proc = Invoke-TrackedProcess -FilePath "msiexec.exe" -CommandLineArgs $msiArgs -TimeoutMinutes 10
            if ($proc.TimedOut) {
                Write-ScriptLog -Level Warn -Message "MSI installer timed out after 10 minutes"
                return $false
            }
            if ($proc.ExitCode -eq 3010) { $script:RebootRequired = $true }
            if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
                Write-ScriptLog -Level Warn -Message "MSI install non-zero exit" -Context @{ ExitCode = $proc.ExitCode }
                return $false
            }
        }

        Start-Sleep -Seconds 2
        $found = Get-DotnetUninstallToolPath
        if ($found) {
            Write-ScriptLog -Level Ok -Message "Uninstall tool installed" -Context @{ Path = $found }
            return $true
        }
        Write-ScriptLog -Level Warn -Message "Tool not found after install"; return $false
    }
    catch {
        Write-ScriptLog -Level Warn -Message "Tool install failed" -Context @{ Error = $_.Exception.Message }
        return $false
    }
    finally {
        try {
            Remove-Item -Path $temp -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-ScriptLog -Level Debug -Message "Temp file cleanup failed" `
                -Context @{ Path = $temp; Error = $_.Exception.Message }
        }
    }
}

# ========================= REMOVAL ========================= #

function Remove-AspNetCoreChannel {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$MajorMinor, [ValidateSet('x64', 'x86')][string]$ArchLimit)
    $tool = Get-DotnetUninstallToolPath
    if (-not $tool) { Write-ScriptLog -Level Warn -Message "Uninstall tool not found"; return $false }

    $archs = if ($ArchLimit) { @($ArchLimit) } else { @('x64', 'x86') }
    foreach ($a in $archs) {
        $toolArgs = @("remove", "--aspnet-runtime", "--major-minor", $MajorMinor, "--yes", "--$a")
        $label = "ASP.NET Core $MajorMinor $a"
        Write-ScriptLog -Level Info -Message "Removing EOL channel" -Context @{ Target = $label }
        if ($PSCmdlet.ShouldProcess($label, "Remove ASP.NET Core runtime")) {
            $p = Invoke-TrackedProcess -FilePath $tool -CommandLineArgs ($toolArgs -join ' ') -TimeoutMinutes 10
            if ($p.TimedOut) {
                Write-ScriptLog -Level Warn -Message "Uninstall tool timed out after 10 minutes" -Context @{ Target = $label }
                return $false
            }
            Add-Action -Type 'EOL-Removed' -Product 'AspNetCore' -Channel $MajorMinor -Arch $a `
                -Detail "Removed" -ExitCode $p.ExitCode -Method 'UninstallTool'
            if ($p.ExitCode -gt 1) {
                Write-ScriptLog -Level Warn -Message "Tool error" -Context @{ ExitCode = $p.ExitCode }
                return $false
            }
        }
    }
    return $true
}

# ========================= DISK USAGE (Performance Optimized) ========================= #

function Measure-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }

    # PERFORMANCE FIX: Try .NET DirectoryInfo first with proper error handling
    try {
        $dir = [System.IO.DirectoryInfo]::new($Path)
        $files = $dir.GetFiles("*", [System.IO.SearchOption]::AllDirectories)
        $sum = ($files | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return $sum
    }
    catch {
        Write-ScriptLog -Level Debug -Message "DirectoryInfo failed, using fallback" `
            -Context @{ Path = $Path; Error = $_.Exception.Message }
        # Fallback to PowerShell cmdlets
        try {
            $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sum) { return 0 }
            return $sum
        }
        catch {
            Write-ScriptLog -Level Debug -Message "Folder size calculation failed" `
                -Context @{ Path = $Path; Error = $_.Exception.Message }
            return 0
        }
    }
}

function Get-PatchObjectsFromShared {
    param([string]$SharedRoot, [string]$ProductFolderName)
    $productPath = Join-Path $SharedRoot $ProductFolderName
    if (-not (Test-Path $productPath)) { return @() }
    $patchFolders = Get-ChildItem -LiteralPath $productPath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' }
    foreach ($pf in $patchFolders) {
        try {
            $v = [version]$pf.Name
            $bytes = Measure-FolderSize -Path $pf.FullName
            [PSCustomObject]@{
                Root = $SharedRoot; Product = $ProductFolderName; Version = $pf.Name
                MajorMinor = "$($v.Major).$($v.Minor)"; Patch = [int]$v.Build
                Bytes = [long]$bytes; Path = $pf.FullName
            }
        }
        catch {
            Write-ScriptLog -Level Debug -Message "Patch object creation failed" `
                -Context @{ Path = $pf.FullName; Error = $_.Exception.Message }
        }
    }
}

function Get-DiskUsageSnapshot {
    $roots = @("C:\Program Files\dotnet\shared", "C:\Program Files (x86)\dotnet\shared") | Where-Object { Test-Path $_ }
    $products = @("Microsoft.NETCore.App", "Microsoft.AspNetCore.App", "Microsoft.WindowsDesktop.App")
    $entries = @()
    foreach ($root in $roots) {
        foreach ($prod in $products) {
            $entries += Get-PatchObjectsFromShared -SharedRoot $root -ProductFolderName $prod
        }
    }
    $entries
}

function Measure-DiskUsage {
    param([object[]]$Entries)

    # FIX: Handle empty or null entries
    if (-not $Entries -or $Entries.Count -eq 0) {
        return @()
    }

    $grouped = $Entries | Group-Object { "$($_.Product)|$($_.Root)|$($_.MajorMinor)" }

    if (-not $grouped) {
        return @()
    }

    $summary = foreach ($g in $grouped) {
        $items = $g.Group
        $topPatch = ($items | Sort-Object Patch -Descending | Select-Object -First 1)
        $total = ($items | Measure-Object -Property Bytes -Sum).Sum
        $lower = ($items | Where-Object { $_.Patch -lt $topPatch.Patch } | Measure-Object -Property Bytes -Sum).Sum

        # FIX: Handle potential null values
        if ($null -eq $total) { $total = 0 }
        if ($null -eq $lower) { $lower = 0 }

        $parts = $g.Name -split '\|'
        [PSCustomObject]@{
            Product = $parts[0]
            Root = $parts[1]
            Channel = $parts[2]
            HighestPatch = $topPatch.Version
            TotalBytes = [long]$total
            LowerBytes = [long]$lower
        }
    }
    return @($summary)  # Ensure array return
}

function Invoke-PostPatchCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('x64', 'x86')][string]$ArchToClean)
    $tool = Get-DotnetUninstallToolPath
    if (-not $tool) { Write-ScriptLog -Level Warn -Message "Uninstall tool not found"; return @() }

    $targets = @(
        @{ Name = "Base .NET Runtime"; Arg = "--runtime"; Product = "BaseRuntime" },
        @{ Name = "ASP.NET Core Runtime"; Arg = "--aspnet-runtime"; Product = "AspNetCore" },
        @{ Name = "Windows Desktop Runtime"; Arg = "--windowsdesktop-runtime"; Product = "WindowsDesktop" }
    )
    $archArgs = @("--$ArchToClean")
    $results = @()

    foreach ($t in $targets) {
        $toolArgs = @('remove', $t.Arg, '--all-lower-patches', '--yes') + $archArgs
        $label = "$($t.Name) $ArchToClean"
        Write-ScriptLog -Level Info -Message "Cleaning lower patches" -Context @{ Target = $label }
        if ($PSCmdlet.ShouldProcess($label, "Remove lower patches")) {
            $p = Invoke-TrackedProcess -FilePath $tool -CommandLineArgs ($toolArgs -join ' ') -TimeoutMinutes 10
            if ($p.TimedOut) {
                Write-ScriptLog -Level Warn -Message "Cleanup operation timed out after 10 minutes" `
                    -Context @{ Target = $label }
                $results += [PSCustomObject]@{
                    Label = $label; ExitCode = -1; Product = $t.Product; Arch = $ArchToClean
                }
                continue
            }
            $results += [PSCustomObject]@{
                Label = $label; ExitCode = $p.ExitCode; Product = $t.Product; Arch = $ArchToClean
            }
            $status = if ($p.ExitCode -eq 0) { "completed" } elseif ($p.ExitCode -eq 1) { "no items" } else { "failed" }
            Add-Action -Type 'Cleanup' -Product $t.Product -Channel 'lower-patches' -Arch $ArchToClean `
                -Detail "$label $status" -ExitCode $p.ExitCode -Method 'UninstallTool'
        }
    }
    return $results
}


# ========================= EXECUTION ENGINE ========================= #

function Invoke-RuntimeUpdatePlan {
    param(
        [Parameter(Mandatory = $false)][object[]]$AspNetGroups = @(),
        [Parameter(Mandatory = $false)][object[]]$DesktopGroups = @(),
        [Parameter(Mandatory)][object]$ReleaseIndex,
        [switch]$UpdateAspNet,
        [switch]$UpdateDesktop,
        [ValidateSet('x64', 'x86', 'Both')][string]$Architecture = 'Both'
    )

    $plan = @()

    # ASP.NET Core updates
    if ($UpdateAspNet) {
        foreach ($grp in $AspNetGroups) {
            if ($Architecture -ne 'Both' -and $grp.Architecture -ne $Architecture) { continue }
            # FIX: Validate group has items before accessing
            if (-not $grp.Group -or $grp.Group.Count -eq 0) { continue }
            $highest = ($grp.Group | Sort-Object Patch -Descending | Select-Object -First 1)
            if (-not $highest) { continue }
            $channelMeta = Get-ChannelEntry -IndexData $ReleaseIndex -MajorMinor $grp.Name
            if (-not $channelMeta) { continue }

            $releaseData = Get-OrAddReleaseData -ReleasesJsonUrl $channelMeta.'releases.json'
            $latest = Get-LatestAspNetCoreVersion -ReleaseData $releaseData

            if ($latest -and $latest.Version -gt $highest.FullVersion) {
                # Hosting bundle preference
                $download = if ($IncludeHostingBundle -and (Test-IisPresent) -and $grp.Architecture -eq 'x64') {
                    $hb = Get-HostingBundleDownload -Release $latest.Release
                    if ($hb) {
                        $hb
                    }
                    else {
                        Get-AspNetCoreDownload -Release $latest.Release -ArchLabel $grp.Architecture
                    }
                }
                else {
                    Get-AspNetCoreDownload -Release $latest.Release -ArchLabel $grp.Architecture
                }

                if ($download) {
                    $plan += [PSCustomObject]@{
                        Type = 'Update'
                        Product = 'AspNetCore'
                        Channel = $grp.Name
                        Architecture = $grp.Architecture
                        CurrentVersion = $highest.RawVersion
                        TargetVersion = $latest.Version.ToString()
                        DownloadUrl = $download.url
                        DownloadHash = $download.hash
                        DownloadSize = if ($download.size) { $download.size } else { 0 }
                        FileName = Split-Path $download.url -Leaf
                    }
                }
            }
        }
    }

    # Windows Desktop updates
    if ($UpdateDesktop) {
        foreach ($grp in $DesktopGroups) {
            if ($Architecture -ne 'Both' -and $grp.Architecture -ne $Architecture) { continue }
            # FIX: Validate group has items before accessing
            if (-not $grp.Group -or $grp.Group.Count -eq 0) { continue }
            $highest = ($grp.Group | Sort-Object Patch -Descending | Select-Object -First 1)
            if (-not $highest) { continue }
            $channelMeta = Get-ChannelEntry -IndexData $ReleaseIndex -MajorMinor $grp.Name
            if (-not $channelMeta) { continue }

            $releaseData = Get-OrAddReleaseData -ReleasesJsonUrl $channelMeta.'releases.json'
            $latest = Get-LatestWindowsDesktopVersion -ReleaseData $releaseData

            if ($latest -and $latest.Version -gt $highest.FullVersion) {
                $download = Get-WindowsDesktopDownload -Release $latest.Release -ArchLabel $grp.Architecture

                if ($download) {
                    $plan += [PSCustomObject]@{
                        Type = 'Update'
                        Product = 'WindowsDesktop'
                        Channel = $grp.Name
                        Architecture = $grp.Architecture
                        CurrentVersion = $highest.RawVersion
                        TargetVersion = $latest.Version.ToString()
                        DownloadUrl = $download.url
                        DownloadHash = $download.hash
                        DownloadSize = if ($download.size) { $download.size } else { 0 }
                        FileName = Split-Path $download.url -Leaf
                    }
                }
            }
        }
    }

    return $plan
}

function Invoke-ExecutionPlan {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][object[]]$Plan)
    $results = @()

    foreach ($item in $Plan) {
        Write-ScriptLog -Level Info -Message "Processing $($item.Product) $($item.Channel) $($item.Architecture)"

        try {
            switch ($item.Type) {
                'Update' {
                    $tempFile = Join-Path $env:TEMP $item.FileName

                    # Download
                    Write-ScriptLog -Level Info -Message "Downloading $($item.FileName)..."
                    if ($PSCmdlet.ShouldProcess($item.DownloadUrl, "Download $($item.FileName)")) {
                        Save-FileWithRetry -Url $item.DownloadUrl -Destination $tempFile

                        # Hash verification (mandatory with fallback)
                        if ($item.DownloadHash) {
                            if (-not (Test-FileHashIfAvailable -FilePath $tempFile -Sha512 $item.DownloadHash)) {
                                throw "Hash verification failed for $($item.FileName)"
                            }
                            Write-ScriptLog -Level Ok -Message "Hash verified for $($item.FileName)"
                        }
                        else {
                            Write-ScriptLog -Level Warn -Message "No hash available for $($item.FileName), checking signature"
                            $sig = Get-AuthenticodeSignature -FilePath $tempFile
                            if ($sig.Status -ne 'Valid') {
                                throw "No hash AND invalid signature for $($item.FileName)"
                            }
                            Write-ScriptLog -Level Warn -Message "Proceeding based on valid signature (hash unavailable)"
                        }
                    }

                    # Install
                    Write-ScriptLog -Level Info -Message "Installing $($item.TargetVersion)..."
                    if ($PSCmdlet.ShouldProcess($item.TargetVersion, "Install $($item.Product) $($item.Channel)")) {
                        $installResult = Install-Exe -Path $tempFile -Arguments "/quiet /norestart"
                        # FIX: Check if $installResult exists before accessing properties
                        if ($installResult -and $installResult.RebootRequired) { $script:RebootRequired = $true }
                        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
                    }

                    $results += [PSCustomObject]@{
                        Product = $item.Product
                        Channel = $item.Channel
                        Architecture = $item.Architecture
                        Action = 'Updated'
                        Version = $item.TargetVersion
                        Success = $true
                        Message = "Successfully updated to $($item.TargetVersion)"
                    }

                    Add-Action -Type 'Update' -Product $item.Product -Channel $item.Channel -Arch $item.Architecture `
                        -Detail "Updated to $($item.TargetVersion)" -ExitCode 0 -Method 'DirectInstall'
                }

                'Remove' {
                    if ($PSCmdlet.ShouldProcess($item.Channel, "Remove $($item.Product) channel")) {
                        Remove-AspNetCoreChannel -MajorMinor $item.Channel -ArchLimit $item.Architecture
                    }
                    $results += [PSCustomObject]@{
                        Product = $item.Product
                        Channel = $item.Channel
                        Architecture = $item.Architecture
                        Action = 'Removed'
                        Success = $true
                        Message = "Removed EOL channel"
                    }
                }
            }

            Write-ScriptLog -Level Ok -Message "$($item.Product) $($item.Channel) $($item.Architecture) completed"

        }
        catch {
            Write-ScriptLog -Level Error -Message "Failed: $($_.Exception.Message)" `
                -Context @{ Product = $item.Product; Channel = $item.Channel }
            $results += [PSCustomObject]@{
                Product = $item.Product
                Channel = $item.Channel
                Architecture = $item.Architecture
                Action = 'Failed'
                Success = $false
                Message = $_.Exception.Message
            }
        }
    }

    return $results
}

# ========================= SYSTEM STATUS (Cache Fix + Performance) ========================= #

function Get-SystemStatus {
    param([switch]$Force, [switch]$SkipDiskScan)

    # Honor Force parameter and CacheValid flag
    $cacheAge = if ($script:MenuState.LastScanTime) {
        (Get-Date) - $script:MenuState.LastScanTime
    }
    else { [TimeSpan]::MaxValue }
    if (-not $Force -and $script:SystemCache -and $script:MenuState.CacheValid -and $cacheAge.TotalMinutes -lt 5) {
        return $script:SystemCache
    }

    $icon = "[*]"
    Write-Host "`n$icon Scanning system..." -ForegroundColor Cyan

    $status = @{}
    $status.ComputerName = $env:COMPUTERNAME
    $status.IsAdmin = Test-Admin
    $status.HasDotnetX64 = Test-Path "C:\Program Files\dotnet\dotnet.exe"
    $status.HasDotnetX86 = Test-Path "C:\Program Files (x86)\dotnet\dotnet.exe"
    $status.HasUninstallTool = $null -ne (Get-DotnetUninstallToolPath)
    $status.IisInstalled = Test-IisPresent
    $status.AncmInstalled = Test-AncmPresent
    $status.IisSiteCount = Get-IisSiteCount

    # Get installed runtimes (fast)
    $status.AspNetGroups = Get-AllInstalledAspNetCoreRuntime
    $status.DesktopGroups = Get-AllInstalledWindowsDesktopRuntime

    # Disk usage optional (slow operation)
    if (-not $SkipDiskScan) {
        $diskEntries = Get-DiskUsageSnapshot
        $diskSummary = Measure-DiskUsage -Entries $diskEntries
        # FIX: Handle null from Measure-Object when collection is empty
        $totalSum = ($diskSummary | Measure-Object -Property TotalBytes -Sum).Sum
        $reclaimSum = ($diskSummary | Measure-Object -Property LowerBytes -Sum).Sum
        $status.TotalDiskUsage = if ($null -eq $totalSum) { 0 } else { $totalSum }
        $status.ReclaimableDisk = if ($null -eq $reclaimSum) { 0 } else { $reclaimSum }
    }
    else {
        $status.TotalDiskUsage = 0
        $status.ReclaimableDisk = 0
    }

    # EOL detection
    try {
        $index = Get-ReleasesIndex
        $eolChannels = @()
        foreach ($grp in ($status.AspNetGroups + $status.DesktopGroups)) {
            $channelMeta = Get-ChannelEntry -IndexData $index -MajorMinor $grp.Name
            if ($channelMeta -and $channelMeta.'support-phase' -eq 'eol') {
                $eolChannels += "$($grp.Name) ($($grp.Architecture))"
            }
        }
        $status.EolChannels = $eolChannels
    }
    catch {
        Write-ScriptLog -Level Debug -Message "EOL detection failed" `
            -Context @{ Error = $_.Exception.Message; Function = $MyInvocation.MyCommand.Name }
        $status.EolChannels = @()
    }

    $script:SystemCache = $status
    $script:MenuState.LastScanTime = Get-Date
    $script:MenuState.CacheValid = $true

    return $status
}

# ========================= ROLLBACK SUPPORT ========================= #

function New-SystemSnapshot {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$SnapshotLabel = "DotNetMaintainer")

    # Checkpoint-Computer (System Restore) is only available on client operating systems
    $isClientOS = $false
    try {
        $isClientOS = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).ProductType -eq 1
    }
    catch {
        Write-ScriptLog -Level Debug -Message "Could not determine OS type" -Context @{ Error = $_.Exception.Message }
    }

    if ($IsWindows -and $isClientOS -and (Get-Command "Checkpoint-Computer" -ErrorAction SilentlyContinue)) {
        try {
            Write-ScriptLog -Level Info -Message "Creating system restore point"
            if ($PSCmdlet.ShouldProcess($SnapshotLabel, 'Create system restore point')) {
                Checkpoint-Computer -Description $SnapshotLabel -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                Write-ScriptLog -Level Ok -Message "System restore point created"
                return $true
            }
        }
        catch {
            Write-ScriptLog -Level Warn -Message "Restore point creation failed" -Context @{ Error = $_.Exception.Message }
            return $false
        }
    }

    if ($IsWindows -and -not $isClientOS) {
        Write-ScriptLog -Level Warn -Message (
            "System restore points are only supported on client operating systems " +
            "(Win32_OperatingSystem.ProductType -ne 1); skipping rollback snapshot on this server"
        )
    }
    else {
        Write-ScriptLog -Level Debug -Message "Restore point not available on this system"
    }
    return $false
}


# ========================= MENU SYSTEM ========================= #

function Show-StartupScreen {
    Write-Banner
    $icon = "[*]"
    Write-Host "$icon Initializing...`n" -ForegroundColor Cyan

    # Skip slow disk scan on startup
    $status = Get-SystemStatus -SkipDiskScan

    Write-Host "System Information:" -ForegroundColor White
    Write-Host "  Computer         : $($status.ComputerName)" -ForegroundColor Gray
    Write-Host "  Administrator    : $(if ($status.IsAdmin) { '[+] Yes' } else { '[!] No' })" `
        -ForegroundColor $(if ($status.IsAdmin) { 'Green' } else { 'Yellow' })
    Write-Host ""

    Write-Host "Runtime Detection:" -ForegroundColor White
    if ($status.HasDotnetX64) { Write-Host "  [+] dotnet.exe (x64)" -ForegroundColor Green }
    if ($status.HasDotnetX86) { Write-Host "  [+] dotnet.exe (x86)" -ForegroundColor Green }
    if (-not $status.HasDotnetX64 -and -not $status.HasDotnetX86) {
        Write-Host "  [-] No dotnet.exe" -ForegroundColor Red
    }
    $uninstallToolStatus = if ($status.HasUninstallTool) { '[+]' } else { '[!]' }
    $uninstallToolState = if ($status.HasUninstallTool) { 'Installed' } else { 'Not installed' }
    Write-Host "  $uninstallToolStatus Uninstall tool: $uninstallToolState" `
        -ForegroundColor $(if ($status.HasUninstallTool) { 'Green' } else { 'Yellow' })
    Write-Host ""

    $aspCount = ($status.AspNetGroups | Measure-Object).Count
    $deskCount = ($status.DesktopGroups | Measure-Object).Count
    Write-Host "Installed Runtimes:" -ForegroundColor White
    Write-Host "  ASP.NET Core      : $aspCount channels" -ForegroundColor Gray
    Write-Host "  WindowsDesktop    : $deskCount channels" -ForegroundColor Gray
    if ($status.EolChannels.Count -gt 0) {
        Write-Host "  [!]  EOL Detected  : $($status.EolChannels.Count) channels" -ForegroundColor Yellow
    }
    Write-Host ""

    if ($status.IisInstalled) {
        Write-Host "IIS Environment:" -ForegroundColor White
        Write-Host "  [+] IIS Installed" -ForegroundColor Green
        if ($status.IisSiteCount -gt 0) {
            Write-Host "  [!]  Active Sites  : $($status.IisSiteCount)" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    Write-Host "Press any key for main menu..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        $status = Get-SystemStatus  # Use cached version (fast)

        Write-Host ""
        Write-Host "============================================================================" -ForegroundColor Cyan
        Write-Host "  DOTNET MAINTAINER v$script:Version - MAIN MENU" -ForegroundColor Cyan
        Write-Host "============================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [1]  Quick Maintenance (Recommended)" -ForegroundColor White
        Write-Host "  [2]  View System Status (Refresh)" -ForegroundColor White
        Write-Host "  [3]  Update Runtimes (Automated)" -ForegroundColor White
        Write-Host "  [4]  Update Runtimes (Interactive)" -ForegroundColor White
        if ($status.EolChannels.Count -gt 0) {
            Write-Host "  [5]  EOL Removal Wizard" -NoNewline -ForegroundColor White
            Write-Host "                       [$($status.EolChannels.Count) EOL!]" -ForegroundColor Red
        }
        else {
            Write-Host "  [5]  EOL Removal Wizard" -ForegroundColor White
        }
        Write-Host "  [6]  Cleanup Lower Patches" -ForegroundColor White
        Write-Host "  [7]  Disk Usage Analyzer" -ForegroundColor White
        Write-Host "  [8]  Generate Compliance Report" -ForegroundColor White
        Write-Host "  [0]  Exit" -ForegroundColor White
        Write-Host ""

        $choice = Read-MenuChoice -Prompt "Select [0-8]" -Min 0 -Max 8

        switch ($choice) {
            1 { Invoke-QuickMaintenance }
            2 { Show-SystemStatusDetailed }
            3 { Invoke-AutomatedUpdate }
            4 { Invoke-InteractiveUpdate }
            5 { Invoke-EolRemovalWizard }
            6 { Invoke-CleanupWizard }
            7 { Show-DiskUsageAnalyzer }
            8 { Export-ComplianceReport }
            0 { return }
        }

        if ($choice -ne 0) {
            Write-Host "`nPress any key to continue..." -ForegroundColor Cyan
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
}

function Invoke-QuickMaintenance {
    Write-Section "Quick Maintenance"
    $confirm = Read-YesNoDefault -Prompt "Proceed with full maintenance (update, remove EOL, cleanup)?" -Default $false
    if (-not $confirm) { Write-Host "Cancelled." -ForegroundColor Yellow; return }

    $icon = "[*]"
    Write-Host "`n$icon Building plan..." -ForegroundColor Cyan

    $status = Get-SystemStatus -Force
    $index = Get-ReleasesIndex

    $updatePlan = Invoke-RuntimeUpdatePlan -AspNetGroups $status.AspNetGroups -DesktopGroups $status.DesktopGroups `
        -ReleaseIndex $index -UpdateAspNet -UpdateDesktop

    if ($updatePlan.Count -gt 0) {
        Write-Host "`nUpdates available:" -ForegroundColor Yellow
        foreach ($p in $updatePlan) {
            Write-Host ("  - $($p.Product) $($p.Channel) ($($p.Architecture)): " +
                "$($p.CurrentVersion) -> $($p.TargetVersion)") -ForegroundColor White
        }

        Write-Host "`n[*] Installing..." -ForegroundColor Cyan
        $results = Invoke-ExecutionPlan -Plan $updatePlan
        $successCount = ($results | Where-Object { $_.Success }).Count
        Write-Host "[+] Updates: $successCount/$($results.Count) successful" -ForegroundColor Green
    }
    else {
        Write-Host "[+] All runtimes up to date" -ForegroundColor Green
    }

    if ($status.ReclaimableDisk -gt 0) {
        Write-Host "`n[*] Cleaning lower patches..." -ForegroundColor Cyan
        Invoke-PostPatchCleanup -ArchToClean 'x64'
        Invoke-PostPatchCleanup -ArchToClean 'x86'
        Write-Host "[+] Cleanup complete" -ForegroundColor Green
    }

    $script:MenuState.CacheValid = $false
}

function Show-SystemStatusDetailed {
    Write-Section "System Status (Detailed)"
    $status = Get-SystemStatus -Force  # Force refresh

    Write-Host "`nASP.NET Core Runtimes:" -ForegroundColor Yellow
    if ($status.AspNetGroups.Count -eq 0) { Write-Host "  None" -ForegroundColor Gray } else {
        foreach ($grp in $status.AspNetGroups) {
            # FIX: Validate group has items before accessing
            if (-not $grp.Group -or $grp.Group.Count -eq 0) { continue }
            $highest = ($grp.Group | Sort-Object Patch -Descending | Select-Object -First 1)
            if (-not $highest) { continue }
            Write-Host "  - $($grp.Name) ($($grp.Architecture)) - $($highest.RawVersion)" -ForegroundColor White
        }
    }

    Write-Host "`nWindows Desktop Runtimes:" -ForegroundColor Yellow
    if ($status.DesktopGroups.Count -eq 0) { Write-Host "  None" -ForegroundColor Gray } else {
        foreach ($grp in $status.DesktopGroups) {
            # FIX: Validate group has items before accessing
            if (-not $grp.Group -or $grp.Group.Count -eq 0) { continue }
            $highest = ($grp.Group | Sort-Object Patch -Descending | Select-Object -First 1)
            if (-not $highest) { continue }
            Write-Host "  - $($grp.Name) ($($grp.Architecture)) - $($highest.RawVersion)" -ForegroundColor White
        }
    }

    Write-Host "`nEOL Status:" -ForegroundColor Yellow
    if ($status.EolChannels.Count -eq 0) {
        Write-Host "  [+] No EOL channels" -ForegroundColor Green
    }
    else {
        Write-Host "  [!]  EOL found:" -ForegroundColor Red
        foreach ($eol in $status.EolChannels) { Write-Host "     - $eol" -ForegroundColor DarkYellow }
    }
}

function Invoke-AutomatedUpdate {
    Write-Section "Automated Update"
    $confirm = Read-YesNoDefault -Prompt "Update ALL runtimes to latest patches?" -Default $false
    if (-not $confirm) { Write-Host "Cancelled." -ForegroundColor Yellow; return }

    $status = Get-SystemStatus
    $index = Get-ReleasesIndex
    $plan = Invoke-RuntimeUpdatePlan -AspNetGroups $status.AspNetGroups -DesktopGroups $status.DesktopGroups `
        -ReleaseIndex $index -UpdateAspNet -UpdateDesktop

    if ($plan.Count -eq 0) { Write-Host "[+] All up to date" -ForegroundColor Green; return }

    Write-Host "`n[*] Installing $($plan.Count) update(s)..." -ForegroundColor Cyan
    $results = Invoke-ExecutionPlan -Plan $plan
    $successCount = ($results | Where-Object { $_.Success }).Count
    Write-Host "`n[+] Completed: $successCount/$($results.Count)" -ForegroundColor Green

    $script:MenuState.CacheValid = $false
}

function Invoke-InteractiveUpdate {
    Write-Section "Interactive Update"
    $status = Get-SystemStatus
    $index = Get-ReleasesIndex
    $allUpdates = Invoke-RuntimeUpdatePlan -AspNetGroups $status.AspNetGroups -DesktopGroups $status.DesktopGroups `
        -ReleaseIndex $index -UpdateAspNet -UpdateDesktop

    if ($allUpdates.Count -eq 0) { Write-Host "[+] All up to date" -ForegroundColor Green; return }

    Write-Host "Available updates:`n" -ForegroundColor Yellow
    for ($i = 0; $i -lt $allUpdates.Count; $i++) {
        $u = $allUpdates[$i]
        Write-Host ("[$($i+1)] $($u.Product) $($u.Channel) ($($u.Architecture)): " +
            "$($u.CurrentVersion) -> $($u.TargetVersion)") -ForegroundColor White
    }

    Write-Host "`nEnter numbers (comma-separated), 'all', or 'none':" -ForegroundColor Cyan
    $choice = Read-Host "Selection"

    $selected = @()
    if ($choice -eq 'none') { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    if ($choice -eq 'all') { $selected = $allUpdates } else {
        try {
            $indices = $choice -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
            $selected = $indices | ForEach-Object { if ($_ -ge 0 -and $_ -lt $allUpdates.Count) { $allUpdates[$_] } }
        }
        catch { Write-Host "Invalid selection" -ForegroundColor Red; return }
    }

    if ($selected.Count -eq 0) { Write-Host "None selected" -ForegroundColor Yellow; return }

    Write-Host "`n[*] Installing..." -ForegroundColor Cyan
    $results = Invoke-ExecutionPlan -Plan $selected
    Write-Host "[+] Done: $(($results | Where-Object { $_.Success }).Count)/$($results.Count)" -ForegroundColor Green
    $script:MenuState.CacheValid = $false
}

function Invoke-EolRemovalWizard {
    Write-Section "EOL Removal Wizard"
    $status = Get-SystemStatus
    if ($status.EolChannels.Count -eq 0) {
        Write-Host "[+] No EOL channels detected" -ForegroundColor Green
        return
    }

    Write-Host "[!]  EOL Channels:" -ForegroundColor Yellow
    foreach ($eol in $status.EolChannels) { Write-Host "  - $eol" -ForegroundColor DarkYellow }
    Write-Host ""

    # Risk assessment
    foreach ($eol in $status.EolChannels) {
        $parts = $eol -split ' '
        # FIX: Validate split results before accessing array elements
        if ($parts.Count -lt 2) {
            Write-ScriptLog -Level Warn -Message "Invalid EOL format, skipping risk assessment" -Context @{ EOL = $eol }
            continue
        }
        $channel = $parts[0]
        $arch = $parts[1].Trim('()')
        $risk = Test-EolRemovalRisk -Channel $channel -ArchLabel $arch
        if ($risk.RiskLevel -ne 'None') {
            Write-Host "Risk for $eol : $($risk.RiskLevel)" -ForegroundColor Yellow
            foreach ($r in $risk.Reasons) { Write-Host "  - $r" -ForegroundColor Gray }
        }
    }

    if ($DependencyCheck -eq 'Block' -and $status.IisInstalled) {
        Write-Host "`n[-] BLOCKED: IIS detected. Migrate apps first." -ForegroundColor Red
        return
    }

    $confirm = Read-YesNoDefault -Prompt "`nProceed with EOL removal?" -Default $false
    if (-not $confirm) { Write-Host "Cancelled." -ForegroundColor Yellow; return }

    if (-not (Get-DotnetUninstallToolPath)) {
        Write-Host "Installing uninstall tool..." -ForegroundColor Cyan
        $installed = Install-DotnetUninstallTool -UrlOverride $UninstallToolMsiUrl
        if (-not $installed) { Write-Host "[-] Tool install failed" -ForegroundColor Red; return }
    }

    $removed = 0
    foreach ($eol in $status.EolChannels) {
        $parts = $eol -split ' '
        # FIX: Validate split results before accessing array elements
        if ($parts.Count -lt 2) {
            Write-ScriptLog -Level Warn -Message "Invalid EOL format, skipping removal" -Context @{ EOL = $eol }
            Write-Host "  [-] Skipped $eol (invalid format)" -ForegroundColor Red
            continue
        }
        $success = Remove-AspNetCoreChannel -MajorMinor $parts[0] -ArchLimit $parts[1].Trim('()')
        if ($success) { $removed++; Write-Host "  [+] Removed $eol" -ForegroundColor Green }
        else { Write-Host "  [-] Failed $eol" -ForegroundColor Red }
    }

    Write-Host "`n[+] Removed: $removed/$($status.EolChannels.Count)" -ForegroundColor Green
    $script:MenuState.CacheValid = $false
}

function Invoke-CleanupWizard {
    Write-Section "Cleanup Lower Patches"
    $status = Get-SystemStatus  # Full scan with disk usage
    if ($status.ReclaimableDisk -eq 0) {
        Write-Host "[+] No lower patches to clean" -ForegroundColor Green
        return
    }

    Write-Host "Reclaimable: $(Format-ByteSize $status.ReclaimableDisk)" -ForegroundColor Yellow
    $confirm = Read-YesNoDefault -Prompt "Proceed with cleanup?" -Default $false
    if (-not $confirm) { Write-Host "Cancelled." -ForegroundColor Yellow; return }

    Write-Host "`n[*] Cleaning..." -ForegroundColor Cyan
    Invoke-PostPatchCleanup -ArchToClean 'x64'
    Invoke-PostPatchCleanup -ArchToClean 'x86'
    Write-Host "[+] Cleanup complete" -ForegroundColor Green
    $script:MenuState.CacheValid = $false
}

function Show-DiskUsageAnalyzer {
    Write-Section "Disk Usage Analyzer"
    Write-Host "[*] Analyzing..." -ForegroundColor Cyan

    try {
        $entries = Get-DiskUsageSnapshot

        if (-not $entries -or $entries.Count -eq 0) {
            Write-Host "`n[!] No .NET runtime directories found or no disk usage data available" `
                -ForegroundColor Yellow
            return
        }

        $summary = Measure-DiskUsage -Entries $entries

        if (-not $summary -or $summary.Count -eq 0) {
            Write-Host "`n[!] No summary data available" -ForegroundColor Yellow
            return
        }

        foreach ($s in ($summary | Sort-Object Product, Channel)) {
            Write-Host "`n$($s.Product) $($s.Channel):" -ForegroundColor Yellow
            Write-Host "  Total: $(Format-ByteSize $s.TotalBytes)" -ForegroundColor White
            Write-Host "  Lower patches: $(Format-ByteSize $s.LowerBytes)" -ForegroundColor Gray
        }

        Write-Host "`n[+] Analysis complete" -ForegroundColor Green
    }
    catch {
        Write-ScriptLog -Level Error -Message "Disk analysis failed: $($_.Exception.Message)"
        Write-Host "`n[-] Disk analysis failed. See logs for details." -ForegroundColor Red
    }
}

function Export-ComplianceReport {
    Write-Section "Compliance Report"
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $reportPath = Join-Path $env:TEMP "dotnet-compliance-$timestamp.json"

    $status = Get-SystemStatus
    $report = @{
        Timestamp = (Get-Date).ToString('o')
        Computer = $status.ComputerName
        AspNetChannels = $status.AspNetGroups.Count
        DesktopChannels = $status.DesktopGroups.Count
        EolChannels = $status.EolChannels
        IisInstalled = $status.IisInstalled
    }

    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "[+] Exported: $reportPath" -ForegroundColor Green
}

# ========================= MAIN EXECUTION ========================= #
$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Starting .NET runtime maintenance v$script:Version..." -ForegroundColor Cyan
        Initialize-NetworkSecurityProtocol

        $isInteractiveMode = $script:IsInteractiveInvocation

        # Admin enforcement
        if (-not (Test-Admin)) {
            if ($isInteractiveMode -and -not $NonInteractive) {
                Write-Host ""
                Write-Host "[-] Administrator privileges required" -ForegroundColor Red
                Write-Host ""
                Write-Host "Right-click the script and select 'Run as Administrator'" -ForegroundColor Yellow
                Read-Host "Press Enter to exit" | Out-Null
                return 1
            }
            else {
                Write-ScriptLog -Level Error -Message "Administrator privileges required"
                throw "Run PowerShell as Administrator"
            }
        }

        if ($isInteractiveMode -and -not $NonInteractive) {
            # INTERACTIVE MENU MODE
            Show-StartupScreen
            Show-MainMenu
            Write-Host "`n[+] Session complete`n" -ForegroundColor Green
            return 0
        }

        # AUTOMATED CLI MODE
        Write-Banner

        try {
            if ($LogPath) { Start-TypedTranscript -Path $LogPath }

            # OneShotCleanup preset
            if ($OneShotCleanup) {
                $NonInteractive = $true; $Approve = $true; $RemoveEol = $true
                $CleanupLowerPatches = $true; $AutoInstallUninstallTool = $true
                Write-ScriptLog -Level Info -Message "OneShotCleanup preset enabled"
            }

            if ($DryRun) { $WhatIfPreference = $true; Write-ScriptLog -Level Info -Message "DryRun mode (no changes)" }
            if ($Approve) { $ConfirmPreference = 'None' }

            Write-Section "Automated Execution"

            $status = Get-SystemStatus
            $index = Get-ReleasesIndex

            # Architecture limiter
            $archToProcess = if ($Arch) { $Arch } else { 'Both' }

            # PlanOnly mode
            if ($PlanOnly) {
                Write-Section "Execution Plan (Preview)"

                $updatePlan = Invoke-RuntimeUpdatePlan -AspNetGroups $status.AspNetGroups `
                    -DesktopGroups $status.DesktopGroups -ReleaseIndex $index `
                    -UpdateAspNet -UpdateDesktop -Architecture $archToProcess

                if ($updatePlan.Count -gt 0) {
                    Write-Host "`n[*] Planned Updates:" -ForegroundColor Cyan
                    foreach ($p in $updatePlan) {
                        Write-Host ("  [*] $($p.Product) $($p.Channel) ($($p.Architecture)): " +
                            "$($p.CurrentVersion) -> $($p.TargetVersion)") -ForegroundColor Cyan
                    }
                }

                if ($RemoveEol -and $status.EolChannels.Count -gt 0) {
                    Write-Host "`n[*] Planned Removals:" -ForegroundColor Cyan
                    foreach ($eol in $status.EolChannels) {
                        Write-Host "  [-] $eol" -ForegroundColor Red
                    }
                }

                Write-Host "`n[+] Plan complete (no changes - PlanOnly mode)" -ForegroundColor Green
                return 0
            }

            # Rollback support
            if ($EnableRollback) {
                Write-ScriptLog -Level Info -Message "Creating restore point"
                $snapshotLabel = "DotNetMaintainer-v$script:Version-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                $null = New-SystemSnapshot -SnapshotLabel $snapshotLabel
            }

            # Execute updates
            $updatePlan = Invoke-RuntimeUpdatePlan -AspNetGroups $status.AspNetGroups `
                -DesktopGroups $status.DesktopGroups -ReleaseIndex $index `
                -UpdateAspNet -UpdateDesktop -Architecture $archToProcess

            if ($updatePlan.Count -gt 0) {
                Write-ScriptLog -Level Info -Message "Executing $($updatePlan.Count) update(s)"
                $results = Invoke-ExecutionPlan -Plan $updatePlan -WhatIf:$DryRun
                $successCount = ($results | Where-Object { $_.Success }).Count
                Write-ScriptLog -Level Ok -Message "Updates: $successCount/$($results.Count) successful"
            }

            # Cleanup
            if ($CleanupLowerPatches) {
                Write-ScriptLog -Level Info -Message "Cleaning lower patches"
                $null = Invoke-PostPatchCleanup -ArchToClean 'x64'
                $null = Invoke-PostPatchCleanup -ArchToClean 'x86'
            }

            # CSV Report
            if ($ReportPath) {
                Write-ScriptLog -Level Info -Message "Exporting CSV report"
                try {
                    $reportData = foreach ($action in $script:ActionLog) {
                        [PSCustomObject]@{
                            Timestamp = (Get-Date).ToString('o')
                            Type = $action.Type
                            Product = $action.Product
                            Channel = $action.Channel
                            Architecture = $action.Arch
                            Detail = $action.Detail
                            ExitCode = $action.ExitCode
                        }
                    }
                    $reportData | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
                    Write-ScriptLog -Level Ok -Message "Report exported" -Context @{ Path = $ReportPath }
                }
                catch {
                    Write-ScriptLog -Level Warn -Message "Report export failed" -Context @{ Error = $_.Exception.Message }
                }
            }

            # JSON Summary
            if ($JsonSummaryPath) {
                Write-ScriptLog -Level Info -Message "Exporting JSON summary"
                try {
                    $summary = @{
                        Timestamp = (Get-Date).ToString('o')
                        ComputerName = $env:COMPUTERNAME
                        ScriptVersion = $script:Version
                        Actions = $script:ActionLog
                        RebootRequired = $script:RebootRequired
                    }
                    $summary | ConvertTo-Json -Depth 10 | Out-File -FilePath $JsonSummaryPath -Encoding UTF8
                    Write-ScriptLog -Level Ok -Message "JSON exported" -Context @{ Path = $JsonSummaryPath }
                }
                catch {
                    Write-ScriptLog -Level Warn -Message "JSON export failed" -Context @{ Error = $_.Exception.Message }
                }
            }

            Write-Section "Execution Complete"
            Write-Host "[+] Automated maintenance completed" -ForegroundColor Green
            if ($script:RebootRequired) {
                Write-Host "[!]  System reboot recommended" -ForegroundColor Yellow
            }

            return 0
        }
        finally {
            if ($LogPath) { Stop-TypedTranscript }
        }
    }
    catch {
        Write-ScriptLog -Level Error -Message "Fatal error: $($_.Exception.Message)"
        Write-Host "`n[-] Fatal error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
