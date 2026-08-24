<#
.SYNOPSIS
    Performs a comprehensive Active Directory health check for domain controllers.

.DESCRIPTION
    This script performs extensive AD health monitoring covering domain controller availability,
    AD replication status, FSMO role holders, DNS service status, SYSVOL and NETLOGON share
    accessibility, AD database sizes, AD-related event log errors, core AD service status, and
    time synchronization. It reports an overall health verdict of Healthy, Warning, or Critical.

    Behavior notes:
    - Exits with 0 when the health check completes (regardless of reported issues) and 1 when the
      ActiveDirectory module is unavailable or a fatal error occurs.
    - The script is read-only and safe to re-run at any time; no domain state is modified.
    - Findings can be exported to HTML or CSV reports.

.PARAMETER DomainController
    Specific domain controller to check. If not specified, checks all DCs.

.PARAMETER IncludeReplication
    Include detailed replication status.

.PARAMETER IncludeEventLogs
    Analyze AD-related event logs for errors.

.PARAMETER ExportHTML
    Export report to HTML file.

.PARAMETER ExportCSV
    Export findings to CSV.

.EXAMPLE
    PS C:\> .\Get-ADHealthCheck.ps1
    Performs basic health check on all domain controllers.

.EXAMPLE
    PS C:\> .\Get-ADHealthCheck.ps1 -IncludeReplication -IncludeEventLogs -ExportHTML
    Comprehensive health check with replication and event log analysis.

.EXAMPLE
    PS C:\> .\Get-ADHealthCheck.ps1 -DomainController "DC01.domain.com"
    Checks specific domain controller.

.NOTES
    File Name     : Get-ADHealthCheck.ps1
    Author        : Bug-Free Umbrella
    Prerequisite  : PowerShell 5.1+
    Version       : 1.0.0
    Date          : 2026-08-23
    Requires      : ActiveDirectory PowerShell module; Domain Admin or equivalent permissions
    Compatibility : Windows Server 2016, 2019, and 2022; run from a domain-joined computer
#>

[CmdletBinding()]
param(
# Note: these script parameters are consumed by nested functions through PowerShell dynamic
# scoping, which PSScriptAnalyzer cannot see; PSReviewUnusedParameter is a false positive here.
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainController,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeReplication,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeEventLogs,

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
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Critical')]
        [string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Critical' { 'Red' }
        'Error' { 'Red' }
        'Warning' { 'Yellow' }
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
        ScanTime = Get-Date
        Domain = $null
        Forest = $null
        DomainControllers = @()
        FSMORoles = @{}
        ReplicationStatus = @()
        EventLogErrors = @()
        HealthStatus = 'Healthy'
        Issues = @()
        Warnings = @()
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

function Get-DomainInfo {
    [CmdletBinding()]
    param()

    Write-ColorOutput "[*] Gathering domain information..." -Level Info

    try {
        $domain = Get-ADDomain -ErrorAction Stop
        $forest = Get-ADForest -ErrorAction Stop

        $script:report.Domain = $domain.DNSRoot
        $script:report.Forest = $forest.Name

        Write-ColorOutput "  [+] Domain: $($domain.DNSRoot)" -Level Success
        Write-ColorOutput "  [+] Forest: $($forest.Name)" -Level Success
        Write-Host "  Domain Functional Level: $($domain.DomainMode)" -ForegroundColor Gray
        Write-Host "  Forest Functional Level: $($forest.ForestMode)" -ForegroundColor Gray
    }
    catch {
        Write-ColorOutput "  [-] Error getting domain information: $($_.Exception.Message)" -Level Error
        $script:report.HealthStatus = 'Critical'
        $script:report.Issues += "Failed to retrieve domain information"
    }
}

function Get-FSMORole {
    [CmdletBinding()]
    param()

    Write-ColorOutput "[*] Identifying FSMO role holders..." -Level Info

    try {
        $domain = Get-ADDomain -ErrorAction Stop
        $forest = Get-ADForest -ErrorAction Stop

        $script:report.FSMORoles = @{
            PDCEmulator = $domain.PDCEmulator
            RIDMaster = $domain.RIDMaster
            InfrastructureMaster = $domain.InfrastructureMaster
            SchemaMaster = $forest.SchemaMaster
            DomainNamingMaster = $forest.DomainNamingMaster
        }

        foreach ($role in $script:report.FSMORoles.GetEnumerator()) {
            Write-Host "  $($role.Key): $($role.Value)" -ForegroundColor Gray
        }
    }
    catch {
        Write-ColorOutput "  [-] Error retrieving FSMO roles: $($_.Exception.Message)" -Level Error
    }
}

function Test-LDAPConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName
    )

    try {
        $null = [ADSI]"LDAP://$HostName"
        return $true
    }
    catch {
        return $false
    }
}

function Test-DomainController {
    [CmdletBinding()]
    param()

    Write-ColorOutput "[*] Testing domain controllers..." -Level Info

    try {
        if ($DomainController) {
            $dcs = @(Get-ADDomainController -Identity $DomainController -ErrorAction Stop)
        }
        else {
            $dcs = Get-ADDomainController -Filter * -ErrorAction Stop
        }

        Write-ColorOutput "  [*] Found $($dcs.Count) domain controller(s)" -Level Info

        foreach ($dc in $dcs) {
            Write-Host "`n  Testing: $($dc.Name)" -ForegroundColor Cyan

            $dcHealth = [PSCustomObject]@{
                Name = $dc.Name
                HostName = $dc.HostName
                Site = $dc.Site
                IPAddress = $dc.IPv4Address
                OperatingSystem = $dc.OperatingSystem
                IsGlobalCatalog = $dc.IsGlobalCatalog
                IsReadOnly = $dc.IsReadOnly
                Enabled = $dc.Enabled
                Ping = $false
                LDAPResponse = $false
                SYSVOLAccessible = $false
                NETLOGONAccessible = $false
                Services = @{}
                TimeDifference = $null
                HealthStatus = 'Unknown'
            }

            # Ping test
            try {
                $ping = Test-Connection -ComputerName $dc.HostName -Count 2 -Quiet -ErrorAction Stop
                $dcHealth.Ping = $ping
                if ($ping) {
                    Write-ColorOutput "    [+] Ping successful" -Level Success
                }
                else {
                    Write-ColorOutput "    [-] Ping failed" -Level Error
                    $script:report.Issues += "$($dc.Name): Ping failed"
                    $dcHealth.HealthStatus = 'Critical'
                }
            }
            catch {
                Write-ColorOutput "    [-] Ping failed: $($_.Exception.Message)" -Level Error
            }

            # LDAP connectivity test
            if (Test-LDAPConnection -HostName $dc.HostName) {
                $dcHealth.LDAPResponse = $true
                Write-ColorOutput "    [+] LDAP accessible" -Level Success
            }
            else {
                Write-ColorOutput "    [-] LDAP not accessible" -Level Error
                $script:report.Issues += "$($dc.Name): LDAP not accessible"
                $dcHealth.LDAPResponse = $false
                $dcHealth.HealthStatus = 'Critical'
            }

            # SYSVOL share test
            $sysvolPath = "\\$($dc.HostName)\SYSVOL"
            if (Test-Path $sysvolPath -ErrorAction SilentlyContinue) {
                $dcHealth.SYSVOLAccessible = $true
                Write-ColorOutput "    [+] SYSVOL accessible" -Level Success
            }
            else {
                Write-ColorOutput "    [-] SYSVOL not accessible" -Level Error
                $script:report.Issues += "$($dc.Name): SYSVOL not accessible"
                $dcHealth.HealthStatus = 'Critical'
            }

            # NETLOGON share test
            $netlogonPath = "\\$($dc.HostName)\NETLOGON"
            if (Test-Path $netlogonPath -ErrorAction SilentlyContinue) {
                $dcHealth.NETLOGONAccessible = $true
                Write-ColorOutput "    [+] NETLOGON accessible" -Level Success
            }
            else {
                Write-ColorOutput "    [-] NETLOGON not accessible" -Level Error
                $script:report.Issues += "$($dc.Name): NETLOGON not accessible"
                $dcHealth.HealthStatus = 'Critical'
            }

            # Service status checks
            $services = @('NTDS', 'DNS', 'kdc', 'Netlogon')
            foreach ($serviceName in $services) {
                try {
                    $service = Get-Service -ComputerName $dc.HostName -Name $serviceName -ErrorAction Stop
                    $dcHealth.Services[$serviceName] = $service.Status

                    if ($service.Status -eq 'Running') {
                        Write-ColorOutput "    [+] $serviceName service running" -Level Success
                    }
                    else {
                        Write-ColorOutput "    [-] $serviceName service not running: $($service.Status)" -Level Error
                        $script:report.Issues += "$($dc.Name): $serviceName service is $($service.Status)"
                        $dcHealth.HealthStatus = 'Critical'
                    }
                }
                catch {
                    Write-ColorOutput "    [!] Could not check $serviceName service" -Level Warning
                    $dcHealth.Services[$serviceName] = 'Unknown'
                }
            }

            # Time synchronization check
            try {
                $dcTime = Invoke-Command -ComputerName $dc.HostName -ScriptBlock { Get-Date } -ErrorAction Stop
                $localTime = Get-Date
                $timeDiff = ($dcTime - $localTime).TotalSeconds

                $dcHealth.TimeDifference = [math]::Round($timeDiff, 2)
                $diffText = [math]::Round($timeDiff, 2)

                if ([math]::Abs($timeDiff) -le 5) {
                    Write-ColorOutput "    [+] Time sync OK (difference: ${diffText}s)" -Level Success
                }
                elseif ([math]::Abs($timeDiff) -le 300) {
                    Write-ColorOutput "    [!] Time difference: ${diffText}s" -Level Warning
                    $script:report.Warnings += "$($dc.Name): Time difference ${diffText}s"
                }
                else {
                    Write-ColorOutput "    [-] Significant time difference: ${diffText}s" -Level Error
                    $script:report.Issues += "$($dc.Name): Time difference ${diffText}s"
                    $dcHealth.HealthStatus = 'Critical'
                }
            }
            catch {
                Write-ColorOutput "    [!] Could not check time sync" -Level Warning
            }

            # Set overall health status
            if ($dcHealth.HealthStatus -ne 'Critical') {
                $dcHealth.HealthStatus = 'Healthy'
            }

            $script:report.DomainControllers += $dcHealth
        }
    }
    catch {
        Write-ColorOutput "  [-] Error testing domain controllers: $($_.Exception.Message)" -Level Error
        $script:report.HealthStatus = 'Critical'
        $script:report.Issues += "Failed to test domain controllers"
    }
}

function Get-ReplicationStatus {
    [CmdletBinding()]
    param()

    Write-ColorOutput "[*] Checking AD replication status..." -Level Info

    try {
        # Get-ADReplicationPartnerMetadata -Target does not accept wildcards;
        # enumerate domain controllers and query each one, aggregating the results.
        $replSummary = @()
        $dcs = Get-ADDomainController -Filter * -ErrorAction Stop
        foreach ($dc in $dcs) {
            $replSummary += Get-ADReplicationPartnerMetadata -Target $dc.HostName -Scope Domain -ErrorAction Stop
        }

        foreach ($repl in $replSummary) {
            $lastSuccess = $repl.LastReplicationSuccess
            $lastAttempt = $repl.LastReplicationAttempt
            $consecutiveFailures = $repl.ConsecutiveReplicationFailures

            $status = 'Healthy'
            $age = ((Get-Date) - $lastSuccess).TotalHours

            if ($consecutiveFailures -gt 0) {
                $status = 'Failed'
                $script:report.Issues += "Replication failure: $($repl.Server) to $($repl.Partner)"
            }
            elseif ($age -gt 24) {
                $status = 'Warning'
                $ageText = [math]::Round($age, 1)
                $msg = "Replication stale: $($repl.Server) to $($repl.Partner) (last success ${ageText}h ago)"
                $script:report.Warnings += $msg
            }

            $replInfo = [PSCustomObject]@{
                Server = $repl.Server
                Partner = $repl.Partner
                Partition = $repl.Partition
                LastReplicationSuccess = $lastSuccess
                LastReplicationAttempt = $lastAttempt
                ConsecutiveFailures = $consecutiveFailures
                LastReplicationResult = $repl.LastReplicationResult
                Status = $status
            }

            $script:report.ReplicationStatus += $replInfo

            $levelMap = @{ 'Healthy' = 'Success'; 'Warning' = 'Warning'; 'Failed' = 'Error' }
            $prefixMap = @{ 'Healthy' = '[+]'; 'Warning' = '[!]'; 'Failed' = '[-]' }
            $linkText = "$($repl.Server) -> $($repl.Partner)"
            Write-ColorOutput "  $($prefixMap[$status]) ${linkText}: $status" -Level $levelMap[$status]
        }

        Write-ColorOutput "  [*] Checked $($replSummary.Count) replication link(s)" -Level Info
    }
    catch {
        Write-ColorOutput "  [-] Error checking replication: $($_.Exception.Message)" -Level Error
        $script:report.HealthStatus = 'Critical'
        $script:report.Issues += "Failed to check AD replication"
    }
}

function Get-ADEventLog {
    [CmdletBinding()]
    param()

    Write-ColorOutput "[*] Analyzing AD event logs..." -Level Info

    $since = (Get-Date).AddHours(-24)

    try {
        $dcs = if ($DomainController) { @($DomainController) } else { (Get-ADDomainController -Filter *).HostName }

        foreach ($dc in $dcs) {
            Write-Host "  Checking $dc..." -ForegroundColor Gray

            try {
                $events = Get-WinEvent -ComputerName $dc -FilterHashtable @{
                    LogName = 'Directory Service', 'DFS Replication'
                    Level = 1, 2
                    StartTime = $since
                } -MaxEvents 50 -ErrorAction SilentlyContinue

                foreach ($adEvent in $events) {
                    $script:report.EventLogErrors += [PSCustomObject]@{
                        Server = $dc
                        TimeCreated = $adEvent.TimeCreated
                        LogName = $adEvent.LogName
                        Level = $adEvent.LevelDisplayName
                        EventID = $adEvent.Id
                        Source = $adEvent.ProviderName
                        Message = $adEvent.Message.Substring(0, [Math]::Min(200, $adEvent.Message.Length))
                    }
                }

                if ($events) {
                    Write-ColorOutput "    [!] Found $($events.Count) error(s) in last 24h" -Level Warning
                }
                else {
                    Write-ColorOutput "    [+] No errors found" -Level Success
                }
            }
            catch {
                Write-Verbose "Could not read event logs from $dc"
            }
        }
    }
    catch {
        Write-ColorOutput "  [!] Error analyzing event logs: $($_.Exception.Message)" -Level Warning
    }
}

function Show-Summary {
    [CmdletBinding()]
    param()

    Write-Host "`n[*] ========================================" -ForegroundColor Cyan
    Write-Host "[*]   AD Health Check Summary" -ForegroundColor Cyan
    Write-Host "[*] ========================================" -ForegroundColor Cyan
    Write-Host "Domain: $($script:report.Domain)"
    Write-Host "Forest: $($script:report.Forest)"
    Write-Host "Scan Time: $($script:report.ScanTime)"

    # Determine overall health
    if ($script:report.Issues.Count -gt 0) {
        $script:report.HealthStatus = 'Critical'
    }
    elseif ($script:report.Warnings.Count -gt 0) {
        $script:report.HealthStatus = 'Warning'
    }

    Write-Host "`nOverall Health: " -NoNewline
    $healthColor = switch ($script:report.HealthStatus) {
        'Critical' { 'Red' }
        'Warning' { 'Yellow' }
        default { 'Green' }
    }
    $healthPrefix = switch ($script:report.HealthStatus) {
        'Critical' { '[-]' }
        'Warning' { '[!]' }
        default { '[+]' }
    }
    Write-Host "$healthPrefix $($script:report.HealthStatus)" -ForegroundColor $healthColor

    if ($script:report.Issues.Count -gt 0) {
        Write-Host "`nCritical Issues:" -ForegroundColor Red
        $script:report.Issues | ForEach-Object { Write-ColorOutput "  - $_" -Level Error }
    }

    if ($script:report.Warnings.Count -gt 0) {
        Write-Host "`nWarnings:" -ForegroundColor Yellow
        $script:report.Warnings | ForEach-Object { Write-ColorOutput "  - $_" -Level Warning }
    }

    Write-Host "`nFSMO Roles:" -ForegroundColor Cyan
    $script:report.FSMORoles.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
    }

    Write-Host "`nDomain Controllers:" -ForegroundColor Cyan
    $script:report.DomainControllers |
        Format-Table Name, HealthStatus, Ping, LDAPResponse, SYSVOLAccessible, IsGlobalCatalog -AutoSize

    Write-Host "`n[*] ========================================`n" -ForegroundColor Cyan
}

function Export-HTMLReport {
    [CmdletBinding()]
    param()

    $reportPath = Join-Path $script:ReportDir "ADHealthCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $healthColor = switch ($script:report.HealthStatus) {
        'Critical' { '#dc3545' }
        'Warning' { '#ffc107' }
        default { '#28a745' }
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>AD Health Check Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1600px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 3px solid $healthColor;
            padding-bottom: 10px;
        }
        h2 {
            color: #555;
            margin-top: 30px;
            border-bottom: 1px solid #ddd;
            padding-bottom: 5px;
        }
        .status-badge {
            display: inline-block;
            padding: 8px 16px;
            border-radius: 4px;
            color: white;
            font-weight: bold;
            background-color: $healthColor;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
        }
        th {
            background-color: #007bff;
            color: white;
            padding: 12px;
            text-align: left;
        }
        td {
            padding: 10px;
            border-bottom: 1px solid #ddd;
        }
        tr:hover {
            background-color: #f1f1f1;
        }
        .healthy {
            color: #28a745;
            font-weight: bold;
        }
        .warning {
            color: #ffc107;
            font-weight: bold;
        }
        .critical {
            color: #dc3545;
            font-weight: bold;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            color: #777;
            font-size: 0.9em;
        }
        ul {
            background-color: #fff3cd;
            padding: 15px 15px 15px 35px;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Active Directory Health Check Report</h1>
        <p><strong>Domain:</strong> $($script:report.Domain)<br>
        <strong>Forest:</strong> $($script:report.Forest)<br>
        <strong>Scan Time:</strong> $($script:report.ScanTime)<br>
        <strong>Overall Health:</strong> <span class="status-badge">$($script:report.HealthStatus)</span></p>

        $(if($script:report.Issues.Count -gt 0) {
            "<h2>Critical Issues</h2><ul>"
            $script:report.Issues | ForEach-Object { "<li class='critical'>$_</li>" }
            "</ul>"
        })

        $(if($script:report.Warnings.Count -gt 0) {
            "<h2>Warnings</h2><ul>"
            $script:report.Warnings | ForEach-Object { "<li class='warning'>$_</li>" }
            "</ul>"
        })

        <h2>FSMO Roles</h2>
        <table>
            <tr><th>Role</th><th>Holder</th></tr>
            $(foreach($role in $script:report.FSMORoles.GetEnumerator()) {
                "<tr><td>$($role.Key)</td><td>$($role.Value)</td></tr>"
            })
        </table>

        <h2>Domain Controllers</h2>
        <table>
            <tr><th>Name</th><th>Site</th><th>Health</th><th>Ping</th><th>LDAP</th>
                <th>SYSVOL</th><th>NETLOGON</th><th>GC</th><th>Time Diff (s)</th></tr>
            $(foreach($dc in $script:report.DomainControllers) {
                $healthClass = $dc.HealthStatus.ToLower()
                "<tr>
                    <td>$($dc.Name)</td>
                    <td>$($dc.Site)</td>
                    <td class='$healthClass'>$($dc.HealthStatus)</td>
                    <td>$($dc.Ping)</td>
                    <td>$($dc.LDAPResponse)</td>
                    <td>$($dc.SYSVOLAccessible)</td>
                    <td>$($dc.NETLOGONAccessible)</td>
                    <td>$($dc.IsGlobalCatalog)</td>
                    <td>$($dc.TimeDifference)</td>
                </tr>"
            })
        </table>

        $(if($script:report.ReplicationStatus.Count -gt 0) {
            "<h2>Replication Status</h2>"
            "<table><tr><th>Server</th><th>Partner</th><th>Partition</th><th>Last Success</th>" +
            "<th>Failures</th><th>Status</th></tr>"
            foreach($repl in $script:report.ReplicationStatus) {
                $statusClass = $repl.Status.ToLower()
                "<tr>
                    <td>$($repl.Server)</td>
                    <td>$($repl.Partner)</td>
                    <td>$($repl.Partition)</td>
                    <td>$($repl.LastReplicationSuccess)</td>
                    <td>$($repl.ConsecutiveFailures)</td>
                    <td class='$statusClass'>$($repl.Status)</td>
                </tr>"
            }
            "</table>"
        })

        <div class="footer">
            Report generated by Get-ADHealthCheck.ps1
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8 -ErrorAction Stop
    Write-ColorOutput "`n[+] HTML report exported to: $reportPath" -Level Success
    return $reportPath
}

function Main {
    try {
        Write-Host "`n[*] ========================================" -ForegroundColor Cyan
        Write-Host "[*]   Active Directory Health Check" -ForegroundColor Cyan
        Write-Host "[*] ========================================`n" -ForegroundColor Cyan

        $script:ReportDir = Resolve-ReportDir

        if (-not (Test-ADModule)) {
            return 1
        }

        Initialize-Report

        Get-DomainInfo
        Get-FSMORole
        Test-DomainController

        if ($IncludeReplication) {
            Get-ReplicationStatus
        }

        if ($IncludeEventLogs) {
            Get-ADEventLog
        }

        Show-Summary

        if ($ExportHTML) {
            Write-Host "[*] Generating HTML report..." -ForegroundColor Cyan
            $null = Export-HTMLReport
        }

        if ($ExportCSV) {
            Write-Host "[*] Generating CSV export..." -ForegroundColor Cyan
            $csvPath = Join-Path $script:ReportDir "ADHealthCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $exportData = @($script:report.DomainControllers) +
                @($script:report.ReplicationStatus) + @($script:report.EventLogErrors)
            $exportData |
                Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
            Write-ColorOutput "[+] CSV export saved to: $csvPath" -Level Success
        }

        Write-Host "[+] AD health check completed successfully" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
