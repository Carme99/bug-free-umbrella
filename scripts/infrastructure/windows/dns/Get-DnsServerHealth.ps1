<#
.SYNOPSIS
    Audits a Windows DNS server for zone, forwarder, recursion and scavenging health.

.DESCRIPTION
    Read-only health audit of a Windows DNS server. The script reads the DNS zones and their
    types, Active Directory integration, server level forwarders, recursion settings and the
    aging and scavenging settings, then prints a per-check summary. It never changes DNS state,
    so it is safe to re-run.

    Checks that are not a clean pass are reported as findings (exit code 2):
    - the server scavenging feature is disabled;
    - a primary zone has aging (scavenging) disabled;
    - a zone is not Active Directory integrated and therefore has no AD replication coverage;
    - with -IncludeStaleRecords, a dynamically registered record is older than the threshold;
    - the resource records of a zone could not be read, so the zone cannot be proven clean;
    - the server has neither forwarders nor root hints, so external names cannot be resolved.
    Zones, forwarders and recursion settings are reported whether or not they are findings.

    Cmdlet reference: https://learn.microsoft.com/powershell/module/dnsserver/
    DnsServerZone class (ZoneType, IsDsIntegrated):
    https://learn.microsoft.com/previous-versions/windows/desktop/dnsserverpsprov/dnsserverzone
    DnsServerScavenging class (ScavengingState):
    https://learn.microsoft.com/previous-versions/windows/desktop/dnsserverpsprov/dnsserverscavenging
    DnsServerZoneAging class (AgingEnabled):
    https://learn.microsoft.com/previous-versions/windows/desktop/dnsserverpsprov/dnsserverzoneaging

    Exit codes: 0 = healthy (every check passed); 2 = findings present; 1 = error, meaning the
    DnsServer module is unavailable, -OutputPath is unsafe, or a required query failed.

.PARAMETER ComputerName
    DNS server to audit. Defaults to $env:COMPUTERNAME, which audits the local server.

.PARAMETER ScavengingStaleDays
    Age in days after which a dynamically registered record counts as stale. Valid range 1-90.
    Default: 7. Only used with -IncludeStaleRecords.

.PARAMETER IncludeStaleRecords
    Switch. When set, every primary zone is enumerated for records whose timestamp is older
    than -ScavengingStaleDays. Enumerating records costs one query per zone, so the check is
    opt-in; without the switch the stale record check is skipped.

.PARAMETER OutputFormat
    Report format: 'Table' (console detail, the default), 'Json', or 'Csv'.

.PARAMETER OutputPath
    Optional directory for the Json or Csv report. Must be a local absolute path without '..'
    traversal and must not be a UNC path. When omitted, Json output is written to the console
    and Csv output is skipped with a warning.

.EXAMPLE
    PS C:\> .\Get-DnsServerHealth.ps1
    Audits the local DNS server and prints the table report.

.EXAMPLE
    PS C:\> .\Get-DnsServerHealth.ps1 -ComputerName dns01.contoso.com -IncludeStaleRecords `
        -ScavengingStaleDays 14 -OutputFormat Json -OutputPath 'C:\Reports'
    Audits a remote DNS server, including records older than 14 days, and writes a JSON report
    into C:\Reports.

.NOTES
    File Name   : Get-DnsServerHealth.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Cmdlet reference pages:
    https://learn.microsoft.com/powershell/module/dnsserver/get-dnsserverzone
    https://learn.microsoft.com/powershell/module/dnsserver/get-dnsserverzoneaging
    https://learn.microsoft.com/powershell/module/dnsserver/get-dnsserverscavenging
    https://learn.microsoft.com/powershell/module/dnsserver/get-dnsserverforwarder
    https://learn.microsoft.com/powershell/module/dnsserver/get-dnsserverrecursion
    https://learn.microsoft.com/powershell/module/dnsserver/get-dnsserverresourcerecord
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 90)]
    [int]$ScavengingStaleDays = 7,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeStaleRecords,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function New-CheckRow {
    param(
        [Parameter()][string]$Category,
        [Parameter()][string]$Item,
        [Parameter()][string]$Status,
        [Parameter()][string]$Finding,
        [Parameter()][string]$Details
    )

    return [pscustomobject]@{
        Category = $Category
        Item     = $Item
        Status   = $Status
        Finding  = $Finding
        Details  = $Details
    }
}

function Test-StaleDnsRecord {
    param(
        [Parameter()][object]$Record,
        [Parameter()][int]$StaleDays,
        [Parameter()][datetime]$Now
    )

    # Static records report Timestamp 0 (DateTime.MinValue); only dynamically registered
    # records carry a real timestamp and can be aged.
    $timestamp = $Record.Timestamp
    if ($null -eq $timestamp) { return $false }
    if ($timestamp -isnot [datetime]) { return $false }
    if ($timestamp.Year -lt 1601) { return $false }
    return ((($Now - $timestamp).TotalDays) -gt $StaleDays)
}

function Main {
    try {
        if (-not (Get-Command Get-DnsServerZone -ErrorAction SilentlyContinue)) {
            throw "The DnsServer module is not available. Add the DNS Server Tools feature."
        }
        Import-Module DnsServer -ErrorAction Stop

        Write-Host "[*] Auditing DNS server '$ComputerName'" -ForegroundColor Cyan
        Write-Host "[*] Cmdlet reference: https://learn.microsoft.com/powershell/module/dnsserver/" `
            -ForegroundColor Cyan

        if ($OutputPath) {
            if ($OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or $OutputPath -match '^(\\\\|//)') {
                Write-Host "[-] Unsafe OutputPath: $OutputPath." -ForegroundColor Red
                Write-Host "[-] Use a local absolute path without '..' traversal." -ForegroundColor Red
                return 1
            }
            if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
                New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop | Out-Null
            }
        }

        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $rows = @()

        Write-Host "[*] Reading server scavenging settings..." -ForegroundColor Cyan
        $scavenging = Get-DnsServerScavenging -ComputerName $ComputerName -ErrorAction Stop
        if ($scavenging.ScavengingState) {
            Write-Host "[+] Server scavenging is enabled" -ForegroundColor Green
            $rows += New-CheckRow -Category 'Scavenging' -Item $ComputerName -Status 'Pass' `
                -Finding 'Server scavenging enabled' `
                -Details "Interval: $($scavenging.ScavengingInterval)"
        }
        else {
            Write-Host "[!] Server scavenging is disabled" -ForegroundColor Yellow
            $rows += New-CheckRow -Category 'Scavenging' -Item $ComputerName -Status 'Fail' `
                -Finding 'Server scavenging disabled' `
                -Details 'Fix: Set-DnsServerScavenging -ScavengingState $true'
        }

        Write-Host "[*] Reading DNS zones..." -ForegroundColor Cyan
        $zones = @(Get-DnsServerZone -ComputerName $ComputerName -ErrorAction Stop)
        Write-Host "[+] Found $($zones.Count) zone(s)" -ForegroundColor Green
        if ($zones.Count -eq 0) {
            Write-Host "[!] The DNS server returned no zones" -ForegroundColor Yellow
            $rows += New-CheckRow -Category 'Zone' -Item $ComputerName -Status 'Fail' `
                -Finding 'No zones returned' -Details 'Verify the DNS Server role configuration'
        }

        foreach ($zone in $zones) {
            $zoneName = [string]$zone.ZoneName
            $dsIntegrated = [bool]$zone.IsDsIntegrated
            $zoneDetails = "Type: $($zone.ZoneType); DS-integrated: $dsIntegrated; " +
                "Reverse: $($zone.IsReverseLookupZone)"
            $rows += New-CheckRow -Category 'Zone' -Item $zoneName -Status 'Pass' `
                -Finding "Zone present ($($zone.ZoneType))" -Details $zoneDetails

            Write-Host "[+] Zone '$zoneName' ($($zone.ZoneType)) DS-integrated: $dsIntegrated" `
                -ForegroundColor Green

            if (-not $dsIntegrated) {
                Write-Host "[!] Zone '$zoneName' is not AD-integrated" -ForegroundColor Yellow
                $rows += New-CheckRow -Category 'Replication' -Item $zoneName -Status 'Fail' `
                    -Finding 'Zone is not AD-integrated' `
                    -Details 'No AD replication coverage; file backed or transferred zone'
            }

            if ($zone.ZoneType -ne 'Primary') { continue }

            try {
                $aging = Get-DnsServerZoneAging -Name $zoneName -ComputerName $ComputerName `
                    -ErrorAction Stop
                if ($aging.AgingEnabled) {
                    $rows += New-CheckRow -Category 'Scavenging' -Item $zoneName -Status 'Pass' `
                        -Finding 'Zone aging enabled' `
                        -Details "Avail for scavenge: $($aging.AvailForScavengeTime)"
                }
                else {
                    Write-Host "[!] Zone '$zoneName' aging is disabled" -ForegroundColor Yellow
                    $rows += New-CheckRow -Category 'Scavenging' -Item $zoneName -Status 'Fail' `
                        -Finding 'Zone aging disabled' `
                        -Details 'Fix: Set-DnsServerZoneAging -Name <zone> -Aging $true'
                }
            }
            catch {
                Write-Host "[!] Could not read aging for '$zoneName'" -ForegroundColor Yellow
                $rows += New-CheckRow -Category 'Scavenging' -Item $zoneName -Status 'Warning' `
                    -Finding 'Zone aging could not be read' -Details $_.Exception.Message
            }
        }

        $staleCount = 0
        if ($IncludeStaleRecords) {
            Write-Host "[*] Looking for records older than $ScavengingStaleDays day(s)..." `
                -ForegroundColor Cyan
            $now = Get-Date
            foreach ($zone in @($zones | Where-Object { $_.ZoneType -eq 'Primary' })) {
                $zoneName = [string]$zone.ZoneName
                try {
                    $records = @(Get-DnsServerResourceRecord -ZoneName $zoneName `
                        -ComputerName $ComputerName -ErrorAction Stop)
                }
                catch {
                    Write-Host "[!] Could not read records in '$zoneName'" -ForegroundColor Yellow
                    $rows += New-CheckRow -Category 'Records' -Item $zoneName -Status 'Warning' `
                        -Finding 'Resource records could not be read' -Details $_.Exception.Message
                    continue
                }

                foreach ($record in $records) {
                    if (Test-StaleDnsRecord -Record $record -StaleDays $ScavengingStaleDays -Now $now) {
                        $staleCount++
                        $ageDays = [math]::Round((($now - $record.Timestamp).TotalDays), 1)
                        Write-Host "[!] Stale record '$($record.HostName)' in '$zoneName'" `
                            -ForegroundColor Yellow
                        $rows += New-CheckRow -Category 'Records' -Item $zoneName -Status 'Fail' `
                            -Finding "Stale $($record.RecordType) record '$($record.HostName)'" `
                            -Details "Age: $ageDays day(s)"
                    }
                }
            }
            Write-Host "[+] Stale records found: $staleCount" -ForegroundColor Green
        }

        Write-Host "[*] Reading forwarders and recursion settings..." -ForegroundColor Cyan
        $forwarder = Get-DnsServerForwarder -ComputerName $ComputerName -ErrorAction Stop
        $forwarderList = @($forwarder.IPAddress | Where-Object { $_ })
        $useRootHint = [bool]$forwarder.UseRootHint
        if ($forwarderList.Count -gt 0) {
            Write-Host "[+] Forwarders: $($forwarderList -join ', ')" -ForegroundColor Green
            $rows += New-CheckRow -Category 'Forwarder' -Item $ComputerName -Status 'Pass' `
                -Finding "$($forwarderList.Count) forwarder(s) configured" `
                -Details ($forwarderList -join ', ')
        }
        elseif ($useRootHint) {
            Write-Host "[*] No forwarders configured; the server uses root hints" -ForegroundColor Cyan
            $rows += New-CheckRow -Category 'Forwarder' -Item $ComputerName -Status 'Pass' `
                -Finding 'No forwarders; root hints enabled' -Details 'Resolution uses root hints'
        }
        else {
            Write-Host "[!] No forwarders configured and root hints are disabled" -ForegroundColor Yellow
            $rows += New-CheckRow -Category 'Forwarder' -Item $ComputerName -Status 'Fail' `
                -Finding 'No forwarders and root hints disabled' `
                -Details 'External names cannot be resolved'
        }

        $recursion = Get-DnsServerRecursion -ComputerName $ComputerName -ErrorAction Stop
        $recursionState = if ($recursion.Enable) { 'enabled' } else { 'disabled' }
        Write-Host "[*] Recursion is $recursionState" -ForegroundColor Cyan
        $rows += New-CheckRow -Category 'Recursion' -Item $ComputerName -Status 'Pass' `
            -Finding "Recursion $recursionState" `
            -Details "Timeout: $($recursion.Timeout)s; RetryInterval: $($recursion.RetryInterval)s"

        $findings = @($rows | Where-Object { $_.Status -ne 'Pass' }).Count
        Write-Host ""
        Write-Host "=== DNS Server Health Summary ===" -ForegroundColor Cyan
        Write-Host "Server  : $ComputerName" -ForegroundColor White
        Write-Host "Zones   : $($zones.Count)" -ForegroundColor White
        Write-Host "Checks  : $($rows.Count)" -ForegroundColor White
        $findingsColor = if ($findings -eq 0) { 'Green' } else { 'Red' }
        Write-Host "Findings: $findings" -ForegroundColor $findingsColor

        switch ($OutputFormat) {
            'Table' {
                $rows | Format-Table -AutoSize -Property Category, Item, Status, Finding, Details |
                    Out-String -Width 200 | Write-Host
            }
            'Json' {
                $report = [pscustomobject]@{
                    GeneratedAt  = (Get-Date).ToString('s')
                    ComputerName = $ComputerName
                    Zones        = @($zones | ForEach-Object { [string]$_.ZoneName })
                    Forwarders   = @($forwarderList)
                    Recursion    = [bool]$recursion.Enable
                    Scavenging   = [bool]$scavenging.ScavengingState
                    StaleRecords = $staleCount
                    Findings     = $findings
                    Checks       = @($rows)
                }
                $json = ConvertTo-Json -InputObject $report -Depth 5
                if ($OutputPath) {
                    $jsonFile = Join-Path $OutputPath "DnsServerHealth_$stamp.json"
                    Set-Content -LiteralPath $jsonFile -Value $json -Encoding utf8 -ErrorAction Stop
                    Write-Host "[+] JSON report written: $jsonFile" -ForegroundColor Green
                }
                else {
                    Write-Host $json
                }
            }
            'Csv' {
                if ($OutputPath) {
                    $csvFile = Join-Path $OutputPath "DnsServerHealth_$stamp.csv"
                    $rows | Export-Csv -LiteralPath $csvFile -NoTypeInformation -Encoding utf8 `
                        -ErrorAction Stop
                    Write-Host "[+] CSV report written: $csvFile" -ForegroundColor Green
                }
                else {
                    Write-Host "[!] -OutputPath is required for CSV output." -ForegroundColor Yellow
                }
            }
        }

        if ($findings -gt 0) {
            Write-Host "[!] $findings finding(s) detected on '$ComputerName'." -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] DNS server '$ComputerName' passed every check." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
