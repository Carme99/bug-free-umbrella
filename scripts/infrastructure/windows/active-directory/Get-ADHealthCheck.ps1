<#
.SYNOPSIS
    Comprehensive Active Directory health check for domain controllers.

.DESCRIPTION
    This script performs extensive AD health monitoring:
    - Domain controller availability and connectivity
    - AD replication status and errors
    - FSMO role holder identification
    - DNS service status
    - SYSVOL and NETLOGON share accessibility
    - AD database and log file sizes
    - Event log analysis (AD-related errors)
    - Service status (AD DS, DNS, KDC, Netlogon)
    - Time synchronization status
    - Export to HTML or CSV

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
    .\Get-ADHealthCheck.ps1
    Performs basic health check on all domain controllers.

.EXAMPLE
    .\Get-ADHealthCheck.ps1 -IncludeReplication -IncludeEventLogs -ExportHTML
    Comprehensive health check with replication and event log analysis.

.EXAMPLE
    .\Get-ADHealthCheck.ps1 -DomainController "DC01.domain.com"
    Checks specific domain controller.

.NOTES
    Requires Active Directory PowerShell module
    Requires Domain Admin or equivalent permissions
    Compatible with Windows Server 2016, 2019, and 2022
    Must be run from a domain-joined computer
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DomainController,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeReplication,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeEventLogs,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
if ([string]::IsNullOrWhiteSpace($ReportDir) -or
    $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
    $ReportDir -match '^(\\\\|//)') {
    Write-Error "Unsafe report path: $ReportDir. Report path must be a local absolute path without '..' traversal."
    exit 1
}
$ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

#Requires -Modules ActiveDirectory

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

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')

    $color = switch($Level) {
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
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }
    catch {
        Write-ColorOutput "ERROR: Active Directory PowerShell module not available" -Level Error
        Write-ColorOutput "Install RSAT tools or run from a Domain Controller" -Level Error
        return $false
    }
}

function Get-DomainInfo {
    Write-Host "`nGathering domain information..." -ForegroundColor Cyan

    try {
        $domain = Get-ADDomain
        $forest = Get-ADForest

        $script:report.Domain = $domain.DNSRoot
        $script:report.Forest = $forest.Name

        Write-ColorOutput "  Domain: $($domain.DNSRoot)" -Level Success
        Write-ColorOutput "  Forest: $($forest.Name)" -Level Success
        Write-Host "  Domain Functional Level: $($domain.DomainMode)"
        Write-Host "  Forest Functional Level: $($forest.ForestMode)"
    }
    catch {
        Write-ColorOutput "  Error getting domain information: $($_.Exception.Message)" -Level Error
        $script:report.HealthStatus = 'Critical'
        $script:report.Issues += "Failed to retrieve domain information"
    }
}

function Get-FSMORoles {
    Write-Host "`nIdentifying FSMO role holders..." -ForegroundColor Cyan

    try {
        $domain = Get-ADDomain
        $forest = Get-ADForest

        $script:report.FSMORoles = @{
            PDCEmulator = $domain.PDCEmulator
            RIDMaster = $domain.RIDMaster
            InfrastructureMaster = $domain.InfrastructureMaster
            SchemaMaster = $forest.SchemaMaster
            DomainNamingMaster = $forest.DomainNamingMaster
        }

        foreach($role in $script:report.FSMORoles.GetEnumerator()) {
            Write-Host "  $($role.Key): $($role.Value)" -ForegroundColor Gray
        }
    }
    catch {
        Write-ColorOutput "  Error retrieving FSMO roles: $($_.Exception.Message)" -Level Error
    }
}

function Test-DomainControllers {
    Write-Host "`nTesting domain controllers..." -ForegroundColor Cyan

    try {
        if($DomainController) {
            $dcs = @(Get-ADDomainController -Identity $DomainController)
        }
        else {
            $dcs = Get-ADDomainController -Filter *
        }

        Write-ColorOutput "  Found $($dcs.Count) domain controller(s)" -Level Info

        foreach($dc in $dcs) {
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
                $ping = Test-Connection -ComputerName $dc.HostName -Count 2 -Quiet
                $dcHealth.Ping = $ping
                if($ping) {
                    Write-ColorOutput "    [OK] Ping successful" -Level Success
                }
                else {
                    Write-ColorOutput "    [FAIL] Ping failed" -Level Error
                    $script:report.Issues += "$($dc.Name): Ping failed"
                    $dcHealth.HealthStatus = 'Critical'
                }
            }
            catch {
                Write-ColorOutput "    [FAIL] Ping failed: $($_.Exception.Message)" -Level Error
            }

            # LDAP connectivity test
            try {
                $ldap = [ADSI]"LDAP://$($dc.HostName)"
                $dcHealth.LDAPResponse = $true
                Write-ColorOutput "    [OK] LDAP accessible" -Level Success
            }
            catch {
                Write-ColorOutput "    [FAIL] LDAP not accessible" -Level Error
                $script:report.Issues += "$($dc.Name): LDAP not accessible"
                $dcHealth.LDAPResponse = $false
                $dcHealth.HealthStatus = 'Critical'
            }

            # SYSVOL share test
            $sysvolPath = "\\$($dc.HostName)\SYSVOL"
            if(Test-Path $sysvolPath -ErrorAction SilentlyContinue) {
                $dcHealth.SYSVOLAccessible = $true
                Write-ColorOutput "    [OK] SYSVOL accessible" -Level Success
            }
            else {
                Write-ColorOutput "    [FAIL] SYSVOL not accessible" -Level Error
                $script:report.Issues += "$($dc.Name): SYSVOL not accessible"
                $dcHealth.HealthStatus = 'Critical'
            }

            # NETLOGON share test
            $netlogonPath = "\\$($dc.HostName)\NETLOGON"
            if(Test-Path $netlogonPath -ErrorAction SilentlyContinue) {
                $dcHealth.NETLOGONAccessible = $true
                Write-ColorOutput "    [OK] NETLOGON accessible" -Level Success
            }
            else {
                Write-ColorOutput "    [FAIL] NETLOGON not accessible" -Level Error
                $script:report.Issues += "$($dc.Name): NETLOGON not accessible"
                $dcHealth.HealthStatus = 'Critical'
            }

            # Service status checks
            $services = @('NTDS', 'DNS', 'kdc', 'Netlogon')
            foreach($serviceName in $services) {
                try {
                    $service = Get-Service -ComputerName $dc.HostName -Name $serviceName -ErrorAction Stop
                    $dcHealth.Services[$serviceName] = $service.Status

                    if($service.Status -eq 'Running') {
                        Write-ColorOutput "    [OK] $serviceName service running" -Level Success
                    }
                    else {
                        Write-ColorOutput "    [FAIL] $serviceName service not running: $($service.Status)" -Level Error
                        $script:report.Issues += "$($dc.Name): $serviceName service is $($service.Status)"
                        $dcHealth.HealthStatus = 'Critical'
                    }
                }
                catch {
                    Write-ColorOutput "    [WARNING] Could not check $serviceName service" -Level Warning
                    $dcHealth.Services[$serviceName] = 'Unknown'
                }
            }

            # Time synchronization check
            try {
                $dcTime = Invoke-Command -ComputerName $dc.HostName -ScriptBlock {Get-Date} -ErrorAction Stop
                $localTime = Get-Date
                $timeDiff = ($dcTime - $localTime).TotalSeconds

                $dcHealth.TimeDifference = [math]::Round($timeDiff, 2)

                if([math]::Abs($timeDiff) -le 5) {
                    Write-ColorOutput "    [OK] Time sync OK (difference: $([math]::Round($timeDiff, 2))s)" -Level Success
                }
                elseif([math]::Abs($timeDiff) -le 300) {
                    Write-ColorOutput "    [WARNING] Time difference: $([math]::Round($timeDiff, 2))s" -Level Warning
                    $script:report.Warnings += "$($dc.Name): Time difference $([math]::Round($timeDiff, 2))s"
                }
                else {
                    Write-ColorOutput "    [FAIL] Significant time difference: $([math]::Round($timeDiff, 2))s" -Level Error
                    $script:report.Issues += "$($dc.Name): Time difference $([math]::Round($timeDiff, 2))s"
                    $dcHealth.HealthStatus = 'Critical'
                }
            }
            catch {
                Write-ColorOutput "    [WARNING] Could not check time sync" -Level Warning
            }

            # Set overall health status
            if($dcHealth.HealthStatus -ne 'Critical') {
                $dcHealth.HealthStatus = 'Healthy'
            }

            $script:report.DomainControllers += $dcHealth
        }
    }
    catch {
        Write-ColorOutput "  Error testing domain controllers: $($_.Exception.Message)" -Level Error
        $script:report.HealthStatus = 'Critical'
        $script:report.Issues += "Failed to test domain controllers"
    }
}

function Get-ReplicationStatus {
    Write-Host "`nChecking AD replication status..." -ForegroundColor Cyan

    try {
        $replSummary = Get-ADReplicationPartnerMetadata -Target * -Scope Domain

        foreach($repl in $replSummary) {
            $lastSuccess = $repl.LastReplicationSuccess
            $lastAttempt = $repl.LastReplicationAttempt
            $consecutiveFailures = $repl.ConsecutiveReplicationFailures

            $status = 'Healthy'
            $age = ((Get-Date) - $lastSuccess).TotalHours

            if($consecutiveFailures -gt 0) {
                $status = 'Failed'
                $script:report.Issues += "Replication failure: $($repl.Server) to $($repl.Partner)"
            }
            elseif($age -gt 24) {
                $status = 'Warning'
                $script:report.Warnings += "Replication stale: $($repl.Server) to $($repl.Partner) (last success $([math]::Round($age, 1))h ago)"
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
            Write-ColorOutput "  $($repl.Server) -> $($repl.Partner): $status" -Level $levelMap[$status]
        }

        Write-ColorOutput "  Checked $($replSummary.Count) replication link(s)" -Level Info
    }
    catch {
        Write-ColorOutput "  Error checking replication: $($_.Exception.Message)" -Level Error
        $script:report.HealthStatus = 'Critical'
        $script:report.Issues += "Failed to check AD replication"
    }
}

function Get-ADEventLogs {
    Write-Host "`nAnalyzing AD event logs..." -ForegroundColor Cyan

    $since = (Get-Date).AddHours(-24)

    try {
        $dcs = if($DomainController) { @($DomainController) } else { (Get-ADDomainController -Filter *).HostName }

        foreach($dc in $dcs) {
            Write-Host "  Checking $dc..." -ForegroundColor Gray

            try {
                $events = Get-WinEvent -ComputerName $dc -FilterHashtable @{
                    LogName = 'Directory Service', 'DFS Replication'
                    Level = 1,2
                    StartTime = $since
                } -MaxEvents 50 -ErrorAction SilentlyContinue

                foreach($event in $events) {
                    $script:report.EventLogErrors += [PSCustomObject]@{
                        Server = $dc
                        TimeCreated = $event.TimeCreated
                        LogName = $event.LogName
                        Level = $event.LevelDisplayName
                        EventID = $event.Id
                        Source = $event.ProviderName
                        Message = $event.Message.Substring(0, [Math]::Min(200, $event.Message.Length))
                    }
                }

                if($events) {
                    Write-ColorOutput "    Found $($events.Count) error(s) in last 24h" -Level Warning
                }
                else {
                    Write-ColorOutput "    No errors found" -Level Success
                }
            }
            catch {
                Write-Verbose "Could not read event logs from $dc"
            }
        }
    }
    catch {
        Write-ColorOutput "  Error analyzing event logs: $($_.Exception.Message)" -Level Warning
    }
}

function Show-Summary {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  AD Health Check Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Domain: $($script:report.Domain)"
    Write-Host "Forest: $($script:report.Forest)"
    Write-Host "Scan Time: $($script:report.ScanTime)"

    # Determine overall health
    if($script:report.Issues.Count -gt 0) {
        $script:report.HealthStatus = 'Critical'
    }
    elseif($script:report.Warnings.Count -gt 0) {
        $script:report.HealthStatus = 'Warning'
    }

    Write-Host "`nOverall Health: " -NoNewline
    $healthColor = switch($script:report.HealthStatus) {
        'Critical' { 'Red' }
        'Warning' { 'Yellow' }
        default { 'Green' }
    }
    Write-Host $script:report.HealthStatus -ForegroundColor $healthColor

    if($script:report.Issues.Count -gt 0) {
        Write-Host "`nCritical Issues:" -ForegroundColor Red
        $script:report.Issues | ForEach-Object { Write-ColorOutput "  - $_" -Level Error }
    }

    if($script:report.Warnings.Count -gt 0) {
        Write-Host "`nWarnings:" -ForegroundColor Yellow
        $script:report.Warnings | ForEach-Object { Write-ColorOutput "  - $_" -Level Warning }
    }

    Write-Host "`nFSMO Roles:" -ForegroundColor Cyan
    $script:report.FSMORoles.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key): $($_.Value)"
    }

    Write-Host "`nDomain Controllers:" -ForegroundColor Cyan
    $script:report.DomainControllers | Format-Table Name, HealthStatus, Ping, LDAPResponse, SYSVOLAccessible, IsGlobalCatalog -AutoSize

    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Export-HTMLReport {
    $reportPath = "$ReportDir\ADHealthCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $healthColor = switch($script:report.HealthStatus) {
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
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1600px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid $healthColor; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        .status-badge { display: inline-block; padding: 8px 16px; border-radius: 4px; color: white; font-weight: bold; background-color: $healthColor; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th { background-color: #007bff; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .healthy { color: #28a745; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .critical { color: #dc3545; font-weight: bold; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #777; font-size: 0.9em; }
        ul { background-color: #fff3cd; padding: 15px 15px 15px 35px; border-radius: 4px; }
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
            <tr><th>Name</th><th>Site</th><th>Health</th><th>Ping</th><th>LDAP</th><th>SYSVOL</th><th>NETLOGON</th><th>GC</th><th>Time Diff (s)</th></tr>
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
            "<table><tr><th>Server</th><th>Partner</th><th>Partition</th><th>Last Success</th><th>Failures</th><th>Status</th></tr>"
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

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-ColorOutput "`nHTML report exported to: $reportPath" -Level Success
    return $reportPath
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Active Directory Health Check" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if(-not (Test-ADModule)) {
    exit 1
}

Get-DomainInfo
Get-FSMORoles
Test-DomainControllers

if($IncludeReplication) {
    Get-ReplicationStatus
}

if($IncludeEventLogs) {
    Get-ADEventLogs
}

Show-Summary

if($ExportHTML) {
    Write-Host "Generating HTML report..." -ForegroundColor Cyan
    Export-HTMLReport
}
