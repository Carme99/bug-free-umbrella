<#
.SYNOPSIS
    Resets Windows network stack to resolve connectivity issues.

.DESCRIPTION
    This script performs a comprehensive network stack reset including:
    - Winsock reset
    - TCP/IP stack reset
    - DNS cache flush
    - Network adapter reset
    - Proxy settings reset
    - Windows Firewall reset (optional)

    Useful for resolving persistent network connectivity issues.

.PARAMETER ResetFirewall
    Switch to also reset Windows Firewall to defaults.

.PARAMETER ResetProxy
    Switch to reset Internet Explorer/Edge proxy settings.

.PARAMETER FlushDNS
    Switch to flush DNS resolver cache.

.PARAMETER ResetAdapters
    Switch to disable and re-enable network adapters.

.PARAMETER CreateRestorePoint
    Switch to create a system restore point before making changes.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Reset-NetworkStack.ps1
    Performs basic network stack reset with confirmation.

.EXAMPLE
    .\Reset-NetworkStack.ps1 -ResetFirewall -FlushDNS -CreateRestorePoint
    Comprehensive reset including firewall, DNS, and creates restore point.

.NOTES
    Author: Server Management Team
    Requires: Administrator privileges, may require system restart
    Version: 1.0
    WARNING: This script makes significant system changes. Create a restore point first!
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$ResetFirewall,

    [Parameter(Mandatory = $false)]
    [switch]$ResetProxy,

    [Parameter(Mandatory = $false)]
    [switch]$FlushDNS,

    [Parameter(Mandatory = $false)]
    [switch]$ResetAdapters,

    [Parameter(Mandatory = $false)]
    [switch]$CreateRestorePoint,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Check for administrator privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

Write-Host "`n=== Network Stack Reset Tool ===" -ForegroundColor Cyan
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

Write-Host "`nWARNING: This script will make significant changes to network configuration!" -ForegroundColor Yellow
Write-Host "A system restart may be required after completion." -ForegroundColor Yellow

if (-not $Force) {
    $confirmation = Read-Host "`nDo you want to continue? (Y/N)"
    if ($confirmation -ne 'Y') {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

$restartRequired = $false
$successCount = 0
$failCount = 0
$operations = @()

try {
    # Create restore point
    if ($CreateRestorePoint) {
        Write-Host "`nCreating system restore point..." -ForegroundColor Yellow

        try {
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "Before Network Stack Reset" -RestorePointType ModifySettings
            Write-Host "✓ Restore point created" -ForegroundColor Green
            $operations += [PSCustomObject]@{
                Operation = "Create Restore Point"
                Status = "Success"
                Message = "Restore point created successfully"
            }
            $successCount++
        }
        catch {
            Write-Warning "Failed to create restore point: $_"
            $operations += [PSCustomObject]@{
                Operation = "Create Restore Point"
                Status = "Failed"
                Message = $_.Exception.Message
            }
            $failCount++

            if (-not $Force) {
                $continue = Read-Host "Continue without restore point? (Y/N)"
                if ($continue -ne 'Y') {
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                    exit 0
                }
            }
        }
    }

    # Reset Winsock
    Write-Host "`nResetting Winsock catalog..." -ForegroundColor Yellow

    if ($PSCmdlet.ShouldProcess("Winsock catalog", "Reset")) {
    try {
        $winsockReset = netsh winsock reset 2>&1
        Write-Host "✓ Winsock reset successful" -ForegroundColor Green
        $operations += [PSCustomObject]@{
            Operation = "Winsock Reset"
            Status = "Success"
            Message = "Winsock catalog reset successfully"
        }
        $successCount++
        $restartRequired = $true
    }
    catch {
        Write-Warning "Winsock reset failed: $_"
        $operations += [PSCustomObject]@{
            Operation = "Winsock Reset"
            Status = "Failed"
            Message = $_.Exception.Message
        }
        $failCount++
    }
    }

    # Reset TCP/IP stack
    Write-Host "`nResetting TCP/IP stack..." -ForegroundColor Yellow

    if ($PSCmdlet.ShouldProcess("TCP/IP stack", "Reset")) {
    try {
        $tcpipReset = netsh int ip reset 2>&1
        Write-Host "✓ TCP/IP stack reset successful" -ForegroundColor Green
        $operations += [PSCustomObject]@{
            Operation = "TCP/IP Reset"
            Status = "Success"
            Message = "TCP/IP stack reset successfully"
        }
        $successCount++
        $restartRequired = $true
    }
    catch {
        Write-Warning "TCP/IP reset failed: $_"
        $operations += [PSCustomObject]@{
            Operation = "TCP/IP Reset"
            Status = "Failed"
            Message = $_.Exception.Message
        }
        $failCount++
    }
    }

    # Reset IPv6
    Write-Host "`nResetting IPv6 configuration..." -ForegroundColor Yellow

    if ($PSCmdlet.ShouldProcess("IPv6 configuration", "Reset")) {
    try {
        $ipv6Reset = netsh int ipv6 reset 2>&1
        Write-Host "✓ IPv6 reset successful" -ForegroundColor Green
        $operations += [PSCustomObject]@{
            Operation = "IPv6 Reset"
            Status = "Success"
            Message = "IPv6 configuration reset successfully"
        }
        $successCount++
    }
    catch {
        Write-Warning "IPv6 reset failed: $_"
        $operations += [PSCustomObject]@{
            Operation = "IPv6 Reset"
            Status = "Failed"
            Message = $_.Exception.Message
        }
        $failCount++
    }
    }

    # Flush DNS cache
    if ($FlushDNS -and $PSCmdlet.ShouldProcess("DNS resolver cache", "Flush")) {
        Write-Host "`nFlushing DNS resolver cache..." -ForegroundColor Yellow

        try {
            Clear-DnsClientCache
            Write-Host "✓ DNS cache flushed" -ForegroundColor Green
            $operations += [PSCustomObject]@{
                Operation = "Flush DNS Cache"
                Status = "Success"
                Message = "DNS resolver cache cleared successfully"
            }
            $successCount++
        }
        catch {
            Write-Warning "DNS flush failed: $_"
            $operations += [PSCustomObject]@{
                Operation = "Flush DNS Cache"
                Status = "Failed"
                Message = $_.Exception.Message
            }
            $failCount++
        }
    }

    # Reset proxy settings
    if ($ResetProxy -and $PSCmdlet.ShouldProcess("Proxy settings", "Reset")) {
        Write-Host "`nResetting proxy settings..." -ForegroundColor Yellow

        try {
            $proxyReset = netsh winhttp reset proxy 2>&1
            Write-Host "✓ Proxy settings reset" -ForegroundColor Green
            $operations += [PSCustomObject]@{
                Operation = "Reset Proxy"
                Status = "Success"
                Message = "Proxy settings reset successfully"
            }
            $successCount++
        }
        catch {
            Write-Warning "Proxy reset failed: $_"
            $operations += [PSCustomObject]@{
                Operation = "Reset Proxy"
                Status = "Failed"
                Message = $_.Exception.Message
            }
            $failCount++
        }
    }

    # Reset Windows Firewall
    if ($ResetFirewall) {
        Write-Host "`nResetting Windows Firewall..." -ForegroundColor Yellow
        Write-Host "WARNING: This will reset all firewall rules to defaults!" -ForegroundColor Red

        if (-not $Force) {
            $fwConfirm = Read-Host "Continue with firewall reset? (Y/N)"
            if ($fwConfirm -ne 'Y') {
                Write-Host "Skipping firewall reset" -ForegroundColor Yellow
            }
            else {
                try {
                    $fwReset = netsh advfirewall reset 2>&1
                    Write-Host "✓ Firewall reset successful" -ForegroundColor Green
                    $operations += [PSCustomObject]@{
                        Operation = "Reset Firewall"
                        Status = "Success"
                        Message = "Windows Firewall reset to defaults"
                    }
                    $successCount++
                }
                catch {
                    Write-Warning "Firewall reset failed: $_"
                    $operations += [PSCustomObject]@{
                        Operation = "Reset Firewall"
                        Status = "Failed"
                        Message = $_.Exception.Message
                    }
                    $failCount++
                }
            }
        }
        else {
            try {
                $fwReset = netsh advfirewall reset 2>&1
                Write-Host "✓ Firewall reset successful" -ForegroundColor Green
                $operations += [PSCustomObject]@{
                    Operation = "Reset Firewall"
                    Status = "Success"
                    Message = "Windows Firewall reset to defaults"
                }
                $successCount++
            }
            catch {
                Write-Warning "Firewall reset failed: $_"
                $operations += [PSCustomObject]@{
                    Operation = "Reset Firewall"
                    Status = "Failed"
                    Message = $_.Exception.Message
                }
                $failCount++
            }
        }
    }

    # Reset network adapters
    if ($ResetAdapters -and $PSCmdlet.ShouldProcess("Network adapters", "Reset")) {
        Write-Host "`nResetting network adapters..." -ForegroundColor Yellow

        $adapters = Get-NetAdapter | Where-Object { $_.Status -ne 'Disabled' }

        foreach ($adapter in $adapters) {
            Write-Host "  Resetting $($adapter.Name)..." -ForegroundColor Gray

            try {
                Disable-NetAdapter -Name $adapter.Name -Confirm:$false
                Start-Sleep -Seconds 2
                Enable-NetAdapter -Name $adapter.Name -Confirm:$false
                Write-Host "  ✓ $($adapter.Name) reset successful" -ForegroundColor Green

                $operations += [PSCustomObject]@{
                    Operation = "Reset Adapter: $($adapter.Name)"
                    Status = "Success"
                    Message = "Adapter disabled and re-enabled"
                }
                $successCount++
            }
            catch {
                Write-Warning "  Failed to reset $($adapter.Name): $_"
                $operations += [PSCustomObject]@{
                    Operation = "Reset Adapter: $($adapter.Name)"
                    Status = "Failed"
                    Message = $_.Exception.Message
                }
                $failCount++
            }
        }
    }

    # Release and renew DHCP
    if ($PSCmdlet.ShouldProcess("DHCP leases", "Renew")) {
    Write-Host "`nRenewing DHCP leases..." -ForegroundColor Yellow

    try {
        $releaseResult = ipconfig /release 2>&1
        Start-Sleep -Seconds 2
        $renewResult = ipconfig /renew 2>&1
        Write-Host "✓ DHCP lease renewed" -ForegroundColor Green
        $operations += [PSCustomObject]@{
            Operation = "Renew DHCP"
            Status = "Success"
            Message = "DHCP lease released and renewed"
        }
        $successCount++
    }
    catch {
        Write-Warning "DHCP renewal failed: $_"
        $operations += [PSCustomObject]@{
            Operation = "Renew DHCP"
            Status = "Failed"
            Message = $_.Exception.Message
        }
        $failCount++
    }
    }

    # Display summary
    Write-Host "`n=== Reset Summary ===" -ForegroundColor Cyan
    Write-Host "Successful Operations: $successCount" -ForegroundColor Green
    Write-Host "Failed Operations: $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })

    Write-Host "`n=== Operations Performed ===" -ForegroundColor Cyan
    $operations | Format-Table -AutoSize

    # Export log
    $logPath = "$env:TEMP\NetworkReset_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $operations | Export-Csv -Path $logPath -NoTypeInformation
    Write-Host "`nOperation log saved to: $logPath" -ForegroundColor Green

    # Restart prompt
    if ($restartRequired) {
        Write-Host "`nRESTART REQUIRED: Some changes require a system restart to take effect." -ForegroundColor Yellow

        if (-not $Force) {
            $restartNow = Read-Host "Restart computer now? (Y/N)"
            if ($restartNow -eq 'Y') {
                Write-Host "`nRestarting computer in 10 seconds..." -ForegroundColor Yellow
                Write-Host "Press Ctrl+C to cancel" -ForegroundColor Gray
                Start-Sleep -Seconds 10
                Restart-Computer -Force
            }
            else {
                Write-Host "`nPlease restart your computer manually to complete the network reset." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "`nPlease restart your computer to complete the network reset." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "`nNetwork stack reset complete. No restart required." -ForegroundColor Green
    }

}
catch {
    Write-Error "Error during network stack reset: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host "`nEnd Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
