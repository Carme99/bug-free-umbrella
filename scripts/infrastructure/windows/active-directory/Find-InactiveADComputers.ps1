<#
.SYNOPSIS
    Identifies and reports inactive computer accounts in Active Directory.

.DESCRIPTION
    This script finds stale computer accounts in Active Directory based on last logon timestamp,
    password last set date, account enabled/disabled status, and operating system version. It
    supports a custom inactivity threshold, an optional search base, filtering by operating system,
    automatic disabling of stale accounts (gated by ShouldProcess, honoring -WhatIf/-Confirm), and
    export of results to HTML or CSV reports.

    Behavior notes:
    - Exits with 0 on success and 1 when the ActiveDirectory module is unavailable or a fatal error occurs.
    - Re-running the script is safe: disabling only targets accounts still reported as enabled, so a
      converged domain yields no further changes.
    - LastLogonTimestamp may be up to 14 days behind actual logon.

.PARAMETER InactiveDays
    Number of days of inactivity to consider a computer stale (default: 90).

.PARAMETER SearchBase
    AD search base (OU) to limit scope. If not specified, searches entire domain.

.PARAMETER IncludeDisabled
    Include already disabled computer accounts in the report.

.PARAMETER OperatingSystem
    Filter by operating system (e.g., "Windows Server*", "Windows 10*").

.PARAMETER DisableInactive
    Automatically disable inactive computer accounts.

.PARAMETER ExportHTML
    Export report to HTML file.

.PARAMETER ExportCSV
    Export computer list to CSV.

.EXAMPLE
    PS C:\> .\Find-InactiveADComputers.ps1
    Finds computers inactive for more than 90 days.

.EXAMPLE
    PS C:\> .\Find-InactiveADComputers.ps1 -InactiveDays 180 -ExportHTML
    Finds computers inactive for 180+ days and exports an HTML report.

.EXAMPLE
    PS C:\> .\Find-InactiveADComputers.ps1 -InactiveDays 90 -DisableInactive -WhatIf
    Shows which computers would be disabled without making changes.

.EXAMPLE
    PS C:\> .\Find-InactiveADComputers.ps1 -SearchBase "OU=Workstations,DC=contoso,DC=com" \
        -OperatingSystem "Windows 10*"
    Finds inactive Windows 10 computers in a specific organizational unit.

.NOTES
    File Name     : Find-InactiveADComputers.ps1
    Author        : Bug-Free Umbrella
    Prerequisite  : PowerShell 5.1+
    Version       : 1.0.0
    Date          : 2026-08-23
    Requires      : ActiveDirectory PowerShell module and appropriate AD permissions (modify if using -DisableInactive)
    Compatibility : Windows Server 2016, 2019, and 2022
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
# Note: these script parameters are consumed by nested functions through PowerShell dynamic
# scoping, which PSScriptAnalyzer cannot see; PSReviewUnusedParameter is a false positive here.
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$InactiveDays = 90,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchBase,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDisabled,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OperatingSystem,

    [Parameter(Mandatory = $false)]
    [switch]$DisableInactive,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Stop'

# Write-Host is intentional: interactive console reporting with the color/prefix convention
# mandated by RELAUNCH-SPEC §3 (justifies PSAvoidUsingWriteHost).
function Write-ColorOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
        'Info' { 'Cyan' }
        default { 'White' }
    }
    Write-Host $Message -ForegroundColor $color
}

function Test-ADModule {
    [CmdletBinding()]
    param()

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }
    catch {
        Write-ColorOutput "[-] ERROR: Active Directory PowerShell module not available" -Level Error
        Write-ColorOutput "[-] Install RSAT tools or run from a Domain Controller" -Level Error
        return $false
    }
}

function Initialize-Report {
    [CmdletBinding()]
    param()

    $script:report = @{
        Domain = $null
        ScanTime = Get-Date
        InactiveDays = $InactiveDays
        SearchBase = $SearchBase
        InactiveComputers = @()
        Summary = @{
            TotalInactive = 0
            Enabled = 0
            Disabled = 0
            Servers = 0
            Workstations = 0
            AccountsDisabled = 0
        }
        OperatingSystems = @{}
    }
}

function Resolve-ReportDir {
    [CmdletBinding()]
    param()

    # Fall back to a temp base on hosts where MyDocuments is not resolvable (e.g. Linux CI).
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $base = if (-not [string]::IsNullOrWhiteSpace($docs)) { $docs } else { [System.IO.Path]::GetTempPath() }
    $dir = Join-Path $base 'Reports'
    if ([string]::IsNullOrWhiteSpace($dir) -or
        $dir -match '(^|[\\/])\.\.([\\/]|$)' -or
        $dir -match '^(\\\\|//)') {
        throw "Unsafe report path: $dir. Report path must be a local absolute path without '..' traversal."
    }
    $fullPath = [System.IO.Path]::GetFullPath($dir)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        New-Item -ItemType Directory -Path $fullPath -Force -ErrorAction Stop | Out-Null
    }
    return $fullPath
}

function Find-InactiveComputer {
    [CmdletBinding()]
    param()

    Write-ColorOutput "[*] Searching for inactive computer accounts..." -Level Info

    try {
        $domain = Get-ADDomain -ErrorAction Stop
        $script:report.Domain = $domain.DNSRoot
        Write-Host "  Domain: $($domain.DNSRoot)" -ForegroundColor Gray

        # Calculate cutoff date
        $cutoffDate = (Get-Date).AddDays(-$InactiveDays)
        $thresholdText = $cutoffDate.ToString('yyyy-MM-dd')
        Write-Host "  Inactivity threshold: $InactiveDays days (before $thresholdText)" -ForegroundColor Gray

        # Build filter
        $filter = "LastLogonTimeStamp -lt '$cutoffDate' -or LastLogonTimeStamp -notlike '*'"

        if (-not $IncludeDisabled) {
            $filter = "($filter) -and Enabled -eq 'True'"
        }

        if ($OperatingSystem) {
            $filter = "($filter) -and OperatingSystem -like '$OperatingSystem'"
        }

        # Set search parameters
        $searchParams = @{
            Filter = $filter
            Properties = 'Name', 'DNSHostName', 'OperatingSystem', 'OperatingSystemVersion',
                'LastLogonTimeStamp', 'PasswordLastSet', 'Enabled', 'Description',
                'Created', 'Modified', 'DistinguishedName'
        }

        if ($SearchBase) {
            $searchParams['SearchBase'] = $SearchBase
            Write-Host "  Search Base: $SearchBase" -ForegroundColor Gray
        }

        # Search for computers
        $computers = Get-ADComputer @searchParams -ErrorAction Stop

        Write-ColorOutput "  [*] Found $($computers.Count) inactive computer account(s)" -Level Info

        foreach ($computer in $computers) {
            # Convert LastLogonTimestamp
            $lastLogon = if ($computer.LastLogonTimeStamp) {
                [DateTime]::FromFileTime($computer.LastLogonTimeStamp)
            }
            else {
                $null
            }

            $inactiveDayCount = if ($lastLogon) {
                [math]::Round(((Get-Date) - $lastLogon).TotalDays, 0)
            }
            else {
                [math]::Round(((Get-Date) - $computer.Created).TotalDays, 0)
            }

            $computerInfo = [PSCustomObject]@{
                Name = $computer.Name
                DNSHostName = $computer.DNSHostName
                OperatingSystem = $computer.OperatingSystem
                OSVersion = $computer.OperatingSystemVersion
                Enabled = $computer.Enabled
                LastLogon = $lastLogon
                PasswordLastSet = $computer.PasswordLastSet
                Created = $computer.Created
                Modified = $computer.Modified
                InactiveDays = $inactiveDayCount
                Description = $computer.Description
                DistinguishedName = $computer.DistinguishedName
            }

            $script:report.InactiveComputers += $computerInfo
            $script:report.Summary.TotalInactive++

            if ($computer.Enabled) {
                $script:report.Summary.Enabled++
            }
            else {
                $script:report.Summary.Disabled++
            }

            # Categorize by OS
            if ($computer.OperatingSystem -like "*Server*") {
                $script:report.Summary.Servers++
            }
            else {
                $script:report.Summary.Workstations++
            }

            # Track OS distribution
            $os = if ($computer.OperatingSystem) { $computer.OperatingSystem } else { 'Unknown' }
            if ($script:report.OperatingSystems.ContainsKey($os)) {
                $script:report.OperatingSystems[$os]++
            }
            else {
                $script:report.OperatingSystems[$os] = 1
            }
        }
    }
    catch {
        Write-ColorOutput "  [-] Error searching for computers: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Disable-InactiveComputerAccount {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-ColorOutput "[!] Disabling inactive computer accounts..." -Level Warning

    $toDisable = @($script:report.InactiveComputers | Where-Object { $_.Enabled -eq $true })

    if ($toDisable.Count -eq 0) {
        Write-Host "  [+] No enabled inactive accounts to disable" -ForegroundColor Gray
        return
    }

    Write-ColorOutput "  [!] $($toDisable.Count) account(s) will be disabled" -Level Warning

    foreach ($computer in $toDisable) {
        if ($PSCmdlet.ShouldProcess($computer.Name, "Disable computer account")) {
            try {
                Disable-ADAccount -Identity $computer.DistinguishedName -ErrorAction Stop
                $script:report.Summary.AccountsDisabled++
                Write-ColorOutput "    [+] Disabled: $($computer.Name)" -Level Success
            }
            catch {
                Write-ColorOutput "    [-] Could not disable $($computer.Name): $($_.Exception.Message)" -Level Error
            }
        }
        else {
            Write-Host "    [WHATIF] Would disable: $($computer.Name)" -ForegroundColor Yellow
        }
    }

    if (-not $WhatIfPreference) {
        Write-ColorOutput "`n  [+] Disabled $($script:report.Summary.AccountsDisabled) account(s)" -Level Success
    }
}

function Show-Summary {
    [CmdletBinding()]
    param()

    Write-Host "`n[*] ========================================" -ForegroundColor Cyan
    Write-Host "[*]   Inactive Computer Accounts Report" -ForegroundColor Cyan
    Write-Host "[*] ========================================" -ForegroundColor Cyan
    Write-Host "Domain: $($script:report.Domain)"
    Write-Host "Scan Time: $($script:report.ScanTime)"
    Write-Host "Inactivity Threshold: $($script:report.InactiveDays) days"

    if ($script:report.SearchBase) {
        Write-Host "Search Base: $($script:report.SearchBase)"
    }

    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  Total Inactive: $($script:report.Summary.TotalInactive)"
    Write-Host "  Enabled: $($script:report.Summary.Enabled)"
    Write-Host "  Disabled: $($script:report.Summary.Disabled)"
    Write-Host "  Servers: $($script:report.Summary.Servers)"
    Write-Host "  Workstations: $($script:report.Summary.Workstations)"

    if ($script:report.Summary.AccountsDisabled -gt 0) {
        Write-ColorOutput "  [+] Accounts Disabled: $($script:report.Summary.AccountsDisabled)" -Level Success
    }

    Write-Host "`nTop Inactive Computers:" -ForegroundColor Cyan
    $script:report.InactiveComputers |
        Sort-Object InactiveDays -Descending |
        Select-Object -First 15 |
        Select-Object Name, OperatingSystem, Enabled, InactiveDays, LastLogon |
        Format-Table -AutoSize

    if ($script:report.OperatingSystems.Count -gt 0) {
        Write-Host "`nOperating System Distribution:" -ForegroundColor Cyan
        $script:report.OperatingSystems.GetEnumerator() |
            Sort-Object Value -Descending |
            ForEach-Object {
                Write-Host "  $($_.Key): $($_.Value)"
            }
    }

    Write-Host "`n[*] ========================================`n" -ForegroundColor Cyan
}

function Export-HTMLReport {
    [CmdletBinding()]
    param()

    $reportPath = Join-Path $script:ReportDir "InactiveComputers_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Inactive Computer Accounts Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1800px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 3px solid #007bff;
            padding-bottom: 10px;
        }
        h2 {
            color: #555;
            margin-top: 30px;
            border-bottom: 1px solid #ddd;
            padding-bottom: 5px;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .metric {
            background-color: #f8f9fa;
            padding: 20px;
            border-radius: 4px;
            border-left: 4px solid #007bff;
            text-align: center;
        }
        .metric.warning {
            border-left-color: #ffc107;
        }
        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: #007bff;
        }
        .metric.warning .metric-value {
            color: #ffc107;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
            font-size: 0.85em;
        }
        th {
            background-color: #007bff;
            color: white;
            padding: 10px;
            text-align: left;
            position: sticky;
            top: 0;
        }
        td {
            padding: 8px;
            border-bottom: 1px solid #ddd;
        }
        tr:hover {
            background-color: #f1f1f1;
        }
        .enabled {
            color: #ffc107;
            font-weight: bold;
        }
        .disabled {
            color: #6c757d;
        }
        .very-old {
            background-color: #fff3cd;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            color: #777;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Inactive Computer Accounts Report</h1>
        <p><strong>Domain:</strong> $($script:report.Domain)<br>
        <strong>Report Date:</strong> $($script:report.ScanTime)<br>
        <strong>Inactivity Threshold:</strong> $($script:report.InactiveDays) days
        $(if($script:report.SearchBase) { "<br><strong>Search Base:</strong> $($script:report.SearchBase)" })
        </p>

        <div class="summary">
            <div class="metric warning">
                <div class="metric-value">$($script:report.Summary.TotalInactive)</div>
                <div>Total Inactive</div>
            </div>
            <div class="metric warning">
                <div class="metric-value">$($script:report.Summary.Enabled)</div>
                <div>Enabled</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.Disabled)</div>
                <div>Already Disabled</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.Servers)</div>
                <div>Servers</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.Workstations)</div>
                <div>Workstations</div>
            </div>
            $(if($script:report.Summary.AccountsDisabled -gt 0) {
                "<div class='metric'><div class='metric-value'>$($script:report.Summary.AccountsDisabled)</div>" +
                "<div>Accounts Disabled</div></div>"
            })
        </div>

        <h2>Operating System Distribution</h2>
        <table>
            <tr><th>Operating System</th><th>Count</th></tr>
            $(foreach($osEntry in ($script:report.OperatingSystems.GetEnumerator() | Sort-Object Value -Descending)) {
                "<tr><td>$($osEntry.Key)</td><td>$($osEntry.Value)</td></tr>"
            })
        </table>

        <h2>Inactive Computer Accounts</h2>
        <table>
            <tr>
                <th>Computer Name</th>
                <th>Operating System</th>
                <th>Status</th>
                <th>Inactive Days</th>
                <th>Last Logon</th>
                <th>Password Last Set</th>
                <th>Created</th>
                <th>Description</th>
            </tr>
            $(foreach($computer in ($script:report.InactiveComputers | Sort-Object InactiveDays -Descending)) {
                $enabledClass = if($computer.Enabled) { 'enabled' } else { 'disabled' }
                $enabledText = if($computer.Enabled) { 'Enabled' } else { 'Disabled' }
                $rowClass = if($computer.InactiveDays -gt 365) { 'very-old' } else { '' }
                $lastLogonText = if($computer.LastLogon) {
                    $computer.LastLogon.ToString('yyyy-MM-dd')
                }
                else {
                    'Never'
                }

                "<tr class='$rowClass'>
                    <td>$($computer.Name)</td>
                    <td>$($computer.OperatingSystem)</td>
                    <td class='$enabledClass'>$enabledText</td>
                    <td>$($computer.InactiveDays)</td>
                    <td>$lastLogonText</td>
                    <td>$($computer.PasswordLastSet.ToString('yyyy-MM-dd'))</td>
                    <td>$($computer.Created.ToString('yyyy-MM-dd'))</td>
                    <td>$($computer.Description)</td>
                </tr>"
            })
        </table>

        <div class="footer">
            Report generated by Find-InactiveADComputers.ps1
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8 -ErrorAction Stop
    Write-ColorOutput "`n[+] HTML report exported to: $reportPath" -Level Success
    return $reportPath
}

function Export-CSVReport {
    [CmdletBinding()]
    param()

    $reportPath = Join-Path $script:ReportDir "InactiveComputers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    $script:report.InactiveComputers |
        Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    Write-ColorOutput "[+] CSV report exported to: $reportPath" -Level Success
    return $reportPath
}

function Main {
    try {
        Write-Host "`n[*] ========================================" -ForegroundColor Cyan
        Write-Host "[*]   Inactive Computer Accounts Finder" -ForegroundColor Cyan
        Write-Host "[*] ========================================`n" -ForegroundColor Cyan

        $script:ReportDir = Resolve-ReportDir

        if (-not (Test-ADModule)) {
            return 1
        }

        Initialize-Report

        Find-InactiveComputer

        if ($DisableInactive) {
            Disable-InactiveComputerAccount
        }

        Show-Summary

        if ($ExportHTML) {
            Write-Host "[*] Generating HTML report..." -ForegroundColor Cyan
            $null = Export-HTMLReport
        }

        if ($ExportCSV) {
            Write-Host "[*] Generating CSV report..." -ForegroundColor Cyan
            $null = Export-CSVReport
        }

        Write-Host "[+] Inactive computer account scan completed successfully" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
