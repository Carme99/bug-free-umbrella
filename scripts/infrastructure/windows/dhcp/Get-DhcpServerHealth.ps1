<#
.SYNOPSIS
    Audits a Windows DHCP server for scope, lease, option and failover health.

.DESCRIPTION
    Read-only health audit of a Windows DHCP server. The script reads the IPv4 scopes, their
    lease statistics, the router and DNS options of each scope (including options inherited from
    the server level) and the DHCPv4 failover relationships, then prints a per-check summary. It
    never changes DHCP state, so it is safe to re-run. Remote control requires DHCP Server
    permissions on the target computer.

    Checks that are not a clean pass are reported as findings (exit code 2):
    - a scope whose free address percentage is below -LowFreeAddressThreshold;
    - a failover relationship whose state is not Normal, such as CommunicationInterrupted;
    - a scope with no router (option 3) or no DNS servers (option 6) at the scope level or
      inherited from the server level;
    - a scope with no lease statistics, which therefore cannot be proven to have free addresses;
    - a server that returns no IPv4 scopes. Scopes, leases and failover relationships are
      reported whether or not they are findings.

    Cmdlet reference: https://learn.microsoft.com/powershell/module/dhcpserver/
    DhcpServerv4ScopeStatistics class (AddressesFree, AddressesInUse, PercentageInUse):
    https://learn.microsoft.com/previous-versions/windows/desktop/dhcpserverpsprov/
    dhcpserverv4scopestatistics
    DhcpServerv4Failover class (State, Mode):
    https://learn.microsoft.com/previous-versions/windows/desktop/dhcpserverpsprov/
    dhcpserverv4failover

    Exit codes: 0 = healthy (every check passed); 2 = findings present; 1 = error, meaning the
    DhcpServer module is unavailable, -OutputPath is unsafe, -ScopeId matched no scope, or a
    required query failed.

.PARAMETER ComputerName
    DHCP server to audit. Defaults to $env:COMPUTERNAME, which audits the local server.

.PARAMETER ScopeId
    Optional IPv4 scope identifier, for example 10.10.10.0. When supplied, only that scope is
    audited and the failover relationships are still reported. When omitted, every IPv4 scope
    on the server is audited.

.PARAMETER LowFreeAddressThreshold
    Free address percentage below which a scope is flagged, expressed as a whole percent. Valid
    range 1-100. Default: 20.

.PARAMETER OutputFormat
    Report format: 'Table' (console detail, the default), 'Json', or 'Csv'.

.PARAMETER OutputPath
    Optional directory for the Json or Csv report. Must be a local absolute path without '..'
    traversal and must not be a UNC path. When omitted, Json output is written to the console
    and Csv output is skipped with a warning.

.EXAMPLE
    PS C:\> .\Get-DhcpServerHealth.ps1
    Audits every IPv4 scope on the local DHCP server and prints the table report.

.EXAMPLE
    PS C:\> .\Get-DhcpServerHealth.ps1 -ComputerName dhcp01.contoso.com -ScopeId 10.10.10.0 `
        -LowFreeAddressThreshold 15 -OutputFormat Csv -OutputPath 'C:\Reports'
    Audits one scope of a remote DHCP server and writes a CSV report into C:\Reports.

.NOTES
    File Name   : Get-DhcpServerHealth.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Cmdlet reference pages:
    https://learn.microsoft.com/powershell/module/dhcpserver/get-dhcpserverv4scope
    https://learn.microsoft.com/powershell/module/dhcpserver/get-dhcpserverv4scopestatistics
    https://learn.microsoft.com/powershell/module/dhcpserver/get-dhcpserverv4optionvalue
    https://learn.microsoft.com/powershell/module/dhcpserver/get-dhcpserverv4failover
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')]
    [string]$ScopeId,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$LowFreeAddressThreshold = 20,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# DHCP option identifiers used by the option checks.
$RouterOptionId = [uint32]3
$DnsServersOptionId = [uint32]6

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

function Get-FreeAddressPercent {
    param([Parameter()][object]$Statistics)

    $inUse = 0.0
    if ($null -ne $Statistics.PercentageInUse) {
        $inUse = [double]$Statistics.PercentageInUse
    }

    $free = [math]::Round((100.0 - $inUse), 2)
    if ($free -lt 0) { return 0.0 }
    if ($free -gt 100) { return 100.0 }
    return $free
}

function Test-OptionIdPresent {
    param(
        [Parameter()][uint32]$OptionId,
        [Parameter()][object[]]$OptionValues
    )

    foreach ($option in $OptionValues) {
        if ([uint32]$option.OptionId -eq $OptionId) { return $true }
    }
    return $false
}

function Main {
    try {
        if (-not (Get-Command Get-DhcpServerv4Scope -ErrorAction SilentlyContinue)) {
            throw "The DhcpServer module is not available. Add the DHCP Server Tools feature."
        }
        Import-Module DhcpServer -ErrorAction Stop

        Write-Host "[*] Auditing DHCP server '$ComputerName'" -ForegroundColor Cyan
        Write-Host "[*] Cmdlet reference: https://learn.microsoft.com/powershell/module/dhcpserver/" `
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

        Write-Host "[*] Reading IPv4 scopes..." -ForegroundColor Cyan
        if ($ScopeId) {
            $scopes = @(Get-DhcpServerv4Scope -ComputerName $ComputerName -ScopeId $ScopeId `
                -ErrorAction Stop)
        }
        else {
            $scopes = @(Get-DhcpServerv4Scope -ComputerName $ComputerName -ErrorAction Stop)
        }
        if ($ScopeId -and $scopes.Count -eq 0) {
            throw "No DHCPv4 scope matched -ScopeId '$ScopeId' on '$ComputerName'."
        }
        Write-Host "[+] Found $($scopes.Count) scope(s)" -ForegroundColor Green
        if ($scopes.Count -eq 0) {
            Write-Host "[!] The DHCP server returned no scopes" -ForegroundColor Yellow
            $rows += New-CheckRow -Category 'Scope' -Item $ComputerName -Status 'Fail' `
                -Finding 'No IPv4 scopes configured' `
                -Details 'Verify the DHCP Server role configuration'
        }

        Write-Host "[*] Reading scope statistics..." -ForegroundColor Cyan
        $statistics = @(Get-DhcpServerv4ScopeStatistics -ComputerName $ComputerName -ErrorAction Stop)

        Write-Host "[*] Reading server level options..." -ForegroundColor Cyan
        $serverOptions = @(Get-DhcpServerv4OptionValue -ComputerName $ComputerName -ErrorAction Stop)

        foreach ($scope in $scopes) {
            $currentScopeId = [string]$scope.ScopeId
            $scopeState = [string]$scope.State
            $rows += New-CheckRow -Category 'Scope' -Item $currentScopeId -Status 'Pass' `
                -Finding "Scope '$($scope.Name)' is $scopeState" `
                -Details "Range: $($scope.StartRange)-$($scope.EndRange); Mask: $($scope.SubnetMask)"

            $scopeStatistics = @($statistics | Where-Object { [string]$_.ScopeId -eq $currentScopeId })
            if ($scopeStatistics.Count -eq 0) {
                Write-Host "[!] No lease statistics for scope $currentScopeId" -ForegroundColor Yellow
                $rows += New-CheckRow -Category 'Lease' -Item $currentScopeId -Status 'Warning' `
                    -Finding 'Lease statistics unavailable' `
                    -Details 'The scope cannot be proven to have free addresses'
            }
            else {
                $freePercent = Get-FreeAddressPercent -Statistics $scopeStatistics[0]
                $leaseSummary = "$($scopeStatistics[0].AddressesInUse) in use, " +
                    "$($scopeStatistics[0].AddressesFree) free"
                if ($freePercent -lt $LowFreeAddressThreshold) {
                    Write-Host "[!] Scope $currentScopeId is only $freePercent% free" `
                        -ForegroundColor Yellow
                    $rows += New-CheckRow -Category 'Lease' -Item $currentScopeId -Status 'Fail' `
                        -Finding "Free addresses $freePercent% below the $LowFreeAddressThreshold% threshold" `
                        -Details $leaseSummary
                }
                else {
                    Write-Host "[+] Scope $currentScopeId is $freePercent% free" -ForegroundColor Green
                    $rows += New-CheckRow -Category 'Lease' -Item $currentScopeId -Status 'Pass' `
                        -Finding "Free addresses $freePercent%" -Details $leaseSummary
                }
            }

            $scopeOptions = @()
            try {
                $scopeOptions = @(Get-DhcpServerv4OptionValue -ComputerName $ComputerName `
                    -ScopeId $currentScopeId -ErrorAction Stop)
            }
            catch {
                Write-Host "[!] Could not read options for scope $currentScopeId" -ForegroundColor Yellow
            }

            $missingOptions = @()
            foreach ($required in @(
                    [pscustomobject]@{ Id = $RouterOptionId; Name = 'Router' },
                    [pscustomobject]@{ Id = $DnsServersOptionId; Name = 'DNS Servers' })) {
                $present = (Test-OptionIdPresent -OptionId $required.Id -OptionValues $scopeOptions) -or
                    (Test-OptionIdPresent -OptionId $required.Id -OptionValues $serverOptions)
                if (-not $present) { $missingOptions += $required.Name }
            }

            if ($missingOptions.Count -gt 0) {
                Write-Host "[!] Scope $currentScopeId is missing option(s): $($missingOptions -join ', ')" `
                    -ForegroundColor Yellow
                $rows += New-CheckRow -Category 'Option' -Item $currentScopeId -Status 'Fail' `
                    -Finding "Missing option(s): $($missingOptions -join ', ')" `
                    -Details 'Not set at the scope level and not inherited from the server level'
            }
            else {
                $rows += New-CheckRow -Category 'Option' -Item $currentScopeId -Status 'Pass' `
                    -Finding 'Router and DNS server options configured' `
                    -Details 'Set at the scope level or inherited from the server level'
            }
        }

        Write-Host "[*] Reading failover relationships..." -ForegroundColor Cyan
        $failovers = @(Get-DhcpServerv4Failover -ComputerName $ComputerName -ErrorAction Stop)
        if ($failovers.Count -eq 0) {
            Write-Host "[*] No DHCPv4 failover relationships configured" -ForegroundColor Cyan
            $rows += New-CheckRow -Category 'Failover' -Item $ComputerName -Status 'Pass' `
                -Finding 'No failover relationships' `
                -Details 'This server is not part of a DHCP failover pair'
        }

        foreach ($failover in $failovers) {
            $failoverName = [string]$failover.Name
            $failoverState = [string]$failover.State
            $failoverDetails = "Mode: $($failover.Mode); Partner: $($failover.PartnerServer)"
            if ($failoverState -eq 'Normal') {
                Write-Host "[+] Failover '$failoverName' is Normal" -ForegroundColor Green
                $rows += New-CheckRow -Category 'Failover' -Item $failoverName -Status 'Pass' `
                    -Finding 'Failover state Normal' -Details $failoverDetails
            }
            else {
                Write-Host "[!] Failover '$failoverName' is $failoverState" -ForegroundColor Yellow
                $rows += New-CheckRow -Category 'Failover' -Item $failoverName -Status 'Fail' `
                    -Finding "Failover state $failoverState" -Details $failoverDetails
            }
        }

        $findings = @($rows | Where-Object { $_.Status -ne 'Pass' }).Count
        Write-Host ""
        Write-Host "=== DHCP Server Health Summary ===" -ForegroundColor Cyan
        Write-Host "Server  : $ComputerName" -ForegroundColor White
        Write-Host "Scopes  : $($scopes.Count)" -ForegroundColor White
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
                    GeneratedAt      = (Get-Date).ToString('s')
                    ComputerName     = $ComputerName
                    ScopeId          = $ScopeId
                    Scopes           = @($scopes | ForEach-Object { [string]$_.ScopeId })
                    Failover         = @($failovers | ForEach-Object { [string]$_.Name })
                    FreeThresholdPct = $LowFreeAddressThreshold
                    Findings         = $findings
                    Checks           = @($rows)
                }
                $json = ConvertTo-Json -InputObject $report -Depth 5
                if ($OutputPath) {
                    $jsonFile = Join-Path $OutputPath "DhcpServerHealth_$stamp.json"
                    Set-Content -LiteralPath $jsonFile -Value $json -Encoding utf8 -ErrorAction Stop
                    Write-Host "[+] JSON report written: $jsonFile" -ForegroundColor Green
                }
                else {
                    Write-Host $json
                }
            }
            'Csv' {
                if ($OutputPath) {
                    $csvFile = Join-Path $OutputPath "DhcpServerHealth_$stamp.csv"
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

        Write-Host "[+] DHCP server '$ComputerName' passed every check." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
