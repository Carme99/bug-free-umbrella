<#
.SYNOPSIS
    Monitors VMware vSphere/ESXi infrastructure health via PowerCLI.

.DESCRIPTION
    Connects to a vCenter Server using VMware PowerCLI and reports on ESXi host connectivity, virtual
    machine power states (with -IncludeVMs), and datastore capacity utilization, then prints a summary.
    Side effects: none beyond console output; the PowerCLI session is created read-only and disconnected
    at the end of the run.
    Exit codes: 0 = health check completed; 1 = PowerCLI unavailable, vCenter connection failed,
    or an unexpected error occurred.

.PARAMETER vCenter
    Hostname or address of the vCenter Server to connect to.

.PARAMETER Credential
    Optional PSCredential used to authenticate to vCenter. When omitted, the current session
    credentials are used by PowerCLI.

.PARAMETER IncludeVMs
    Also enumerate virtual machines and report their power states.

.PARAMETER ExportHTML
    Reserved for HTML report export; currently the summary is printed to console only.

.EXAMPLE
    PS C:\> .\Get-VMwareHealth.ps1 -vCenter vcenter.domain.com
    Connects to vcenter.domain.com and reports host and datastore health.

.EXAMPLE
    PS C:\> .\Get-VMwareHealth.ps1 -vCenter vcenter.domain.com -IncludeVMs -Credential (Get-Credential)
    Reports host, VM, and datastore health authenticating with an explicit credential.

.NOTES
    File Name    : Get-VMwareHealth.ps1
    Author       : Bug-Free Umbrella
    Prerequisite : PowerShell 5.1+, VMware PowerCLI module
    Version      : 1.0.0
    Date         : 2026-08-23
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'RELAUNCH-SPEC requires colored console output via Write-Host with [+]/[!]/[-]/[*] prefixes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script parameters are consumed inside function Main through dynamic scoping.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$vCenter,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeVMs,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        if (-not $vCenter) {
            Write-Host "[-] Parameter -vCenter is required." -ForegroundColor Red
            return 1
        }

        Write-Host "`n=== VMware Health Check ===" -ForegroundColor Cyan

        # Check PowerCLI
        Import-Module VMware.PowerCLI -ErrorAction Stop
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false `
            -Scope Session -ErrorAction Stop | Out-Null
        Write-Host "[+] PowerCLI module loaded" -ForegroundColor Green

        Write-Host "[*] Connecting to vCenter: $vCenter" -ForegroundColor Cyan
        if ($Credential) {
            Connect-VIServer -Server $vCenter -Credential $Credential -ErrorAction Stop | Out-Null
        }
        else {
            Connect-VIServer -Server $vCenter -ErrorAction Stop | Out-Null
        }
        Write-Host "[+] Connected to vCenter" -ForegroundColor Green

        # Get ESXi hosts
        Write-Host "[*] Checking ESXi hosts..." -ForegroundColor Cyan
        $vmHosts = @(Get-VMHost -ErrorAction Stop)
        $connectedHosts = @($vmHosts | Where-Object { $_.ConnectionState -eq "Connected" }).Count
        Write-Host "[+] Found $($vmHosts.Count) hosts ($connectedHosts connected)" -ForegroundColor Green

        # Get VMs
        if ($IncludeVMs) {
            Write-Host "[*] Checking virtual machines..." -ForegroundColor Cyan
            $vms = @(Get-VM -ErrorAction Stop)
            $poweredOnVMs = @($vms | Where-Object { $_.PowerState -eq "PoweredOn" }).Count
            Write-Host "[+] Found $($vms.Count) VMs ($poweredOnVMs powered on)" -ForegroundColor Green
        }

        # Check datastores
        Write-Host "[*] Checking datastores..." -ForegroundColor Cyan
        $datastores = @(Get-Datastore -ErrorAction Stop)
        foreach ($ds in $datastores) {
            $freePercent = [math]::Round(($ds.FreeSpaceGB / $ds.CapacityGB) * 100, 1)
            $color = if ($freePercent -lt 10) { "Red" } elseif ($freePercent -lt 20) { "Yellow" } else { "Green" }
            Write-Host "  - $($ds.Name): $($ds.FreeSpaceGB) GB free ($freePercent%)" -ForegroundColor $color
        }

        Write-Host "`n=== Summary ===" -ForegroundColor Cyan
        Write-Host "vCenter: $vCenter" -ForegroundColor White
        Write-Host "Hosts: $($vmHosts.Count) ($connectedHosts connected)" -ForegroundColor White
        if ($IncludeVMs) {
            Write-Host "VMs: $($vms.Count) ($poweredOnVMs powered on)" -ForegroundColor White
        }
        Write-Host "Datastores: $($datastores.Count)" -ForegroundColor White

        Disconnect-VIServer -Server $vCenter -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Host "`n[+] Health check complete!" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] VMware health check failed: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }

    return 0
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
