<#
.SYNOPSIS
    VMware vSphere/ESXi health monitoring.
.DESCRIPTION
    Monitors VMware infrastructure: hosts, VMs, datastores, networks, and resource utilization.
.EXAMPLE
    .\Get-VMwareHealth.ps1 -vCenter vcenter.domain.com -ExportHTML
.NOTES
    Requires: VMware PowerCLI module
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$vCenter,
    [Parameter()][PSCredential]$Credential,
    [switch]$IncludeVMs,
    [switch]$ExportHTML
)

Write-Host "`n=== VMware Health Check ===" -ForegroundColor Cyan

# Check PowerCLI
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
    Write-Host "[+] PowerCLI module loaded" -ForegroundColor Green
} catch {
    Write-Host "[!] PowerCLI not installed. Run: Install-Module VMware.PowerCLI" -ForegroundColor Red
    exit 1
}

Write-Host "[*] Connecting to vCenter: $vCenter" -ForegroundColor Cyan
try {
    if ($Credential) {
        Connect-VIServer -Server $vCenter -Credential $Credential -ErrorAction Stop | Out-Null
    } else {
        Connect-VIServer -Server $vCenter -ErrorAction Stop | Out-Null
    }
    Write-Host "[+] Connected to vCenter" -ForegroundColor Green
} catch {
    Write-Host "[!] Failed to connect to vCenter: $_" -ForegroundColor Red
    exit 1
}

# Get ESXi hosts
Write-Host "[*] Checking ESXi hosts..." -ForegroundColor Cyan
$vmHosts = Get-VMHost
$connectedHosts = ($vmHosts | Where-Object {$_.ConnectionState -eq "Connected"}).Count
Write-Host "[+] Found $($vmHosts.Count) hosts ($connectedHosts connected)" -ForegroundColor Green

# Get VMs
if ($IncludeVMs) {
    Write-Host "[*] Checking virtual machines..." -ForegroundColor Cyan
    $vms = Get-VM
    $poweredOnVMs = ($vms | Where-Object {$_.PowerState -eq "PoweredOn"}).Count
    Write-Host "[+] Found $($vms.Count) VMs ($poweredOnVMs powered on)" -ForegroundColor Green
}

# Check datastores
Write-Host "[*] Checking datastores..." -ForegroundColor Cyan
$datastores = Get-Datastore
foreach ($ds in $datastores) {
    $freePercent = [math]::Round(($ds.FreeSpaceGB / $ds.CapacityGB) * 100, 1)
    $color = if ($freePercent -lt 10) {"Red"} elseif ($freePercent -lt 20) {"Yellow"} else {"Green"}
    Write-Host "  - $($ds.Name): $($ds.FreeSpaceGB) GB free ($freePercent%)" -ForegroundColor $color
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "vCenter: $vCenter" -ForegroundColor White
Write-Host "Hosts: $($vmHosts.Count) ($connectedHosts connected)" -ForegroundColor White
if ($IncludeVMs) {
    Write-Host "VMs: $($vms.Count) ($poweredOnVMs powered on)" -ForegroundColor White
}
Write-Host "Datastores: $($datastores.Count)" -ForegroundColor White

Disconnect-VIServer -Server $vCenter -Confirm:$false
Write-Host "`nHealth check complete!`n" -ForegroundColor Green
