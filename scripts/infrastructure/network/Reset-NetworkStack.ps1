<#
.SYNOPSIS
    Resets the Windows network stack to resolve persistent connectivity issues.

.DESCRIPTION
    Performs a comprehensive network stack reset that may include Winsock reset, TCP/IP stack reset,
    IPv6 configuration reset, DNS resolver cache flush, proxy settings reset, Windows Firewall reset,
    network adapter disable/re-enable cycles, and DHCP lease renewal.
    Side effects: makes significant system configuration changes; a system restart is usually required.
    Exit codes: 0 = success (or user-cancelled confirmation); 1 = not elevated, one or more operations
    failed, or an unexpected error occurred.

.PARAMETER ResetFirewall
    Switch to also reset Windows Firewall to defaults.

.PARAMETER ResetProxy
    Switch to reset the WinHTTP proxy settings.

.PARAMETER FlushDNS
    Switch to flush the DNS resolver cache.

.PARAMETER ResetAdapters
    Switch to disable and re-enable network adapters.

.PARAMETER CreateRestorePoint
    Switch to create a system restore point before making changes.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    PS C:\> .\Reset-NetworkStack.ps1
    Performs basic network stack reset with confirmation.

.EXAMPLE
    PS C:\> .\Reset-NetworkStack.ps1 -ResetFirewall -FlushDNS -CreateRestorePoint -Force
    Comprehensive reset including firewall and DNS flush without prompts, creating a restore point first.

.NOTES
    File Name    : Reset-NetworkStack.ps1
    Author       : Server Management Team
    Prerequisite : PowerShell 5.1+, Administrator privileges, may require system restart
    Version      : 1.0.0
    Date         : 2026-08-23
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'RELAUNCH-SPEC requires colored console output via Write-Host with [+]/[!]/[-]/[*] prefixes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script parameters are consumed inside function Main through dynamic scoping.')]
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

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    # Returns $true when the current user holds local Administrator rights.
    try {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
            [Security.Principal.WindowsIdentity]::GetCurrent())
        return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Invoke-Netsh {
    # Thin wrapper around netsh.exe so tests can mock native calls (returns $LASTEXITCODE).
    & netsh.exe @Args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Invoke-Ipconfig {
    # Thin wrapper around ipconfig.exe so tests can mock native calls (returns $LASTEXITCODE).
    & ipconfig.exe @Args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Add-OperationResult {
    # Records a completed (or failed) operation in the shared results collection.
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Success', 'Failed')]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $script:Operations += [PSCustomObject]@{
        Operation = $Name
        Status    = $Status
        Message   = $Message
    }
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        if (-not (Test-Administrator)) {
            Write-Host "[-] This script requires Administrator privileges. Please run as Administrator." `
                -ForegroundColor Red
            return 1
        }

        Write-Host "`n=== Network Stack Reset Tool ===" -ForegroundColor Cyan
        Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Gray
        Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

        Write-Host "`nWARNING: This script will make significant changes to network configuration!" `
            -ForegroundColor Yellow
        Write-Host "A system restart may be required after completion." -ForegroundColor Yellow

        if (-not $Force) {
            $confirmation = Read-Host "`nDo you want to continue? (Y/N)"
            if ($confirmation -ne 'Y') {
                Write-Host "[!] Operation cancelled." -ForegroundColor Yellow
                return 0
            }
        }

        $script:RestartRequired = $false
        $script:SuccessCount = 0
        $script:FailCount = 0
        $script:Operations = @()

        # Create restore point
        if ($CreateRestorePoint) {
            Write-Host "`nCreating system restore point..." -ForegroundColor Yellow

            try {
                Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
                Checkpoint-Computer -Description "Before Network Stack Reset" -RestorePointType ModifySettings `
                    -ErrorAction Stop
                Write-Host "[+] Restore point created" -ForegroundColor Green
                Add-OperationResult -Name "Create Restore Point" -Status "Success" `
                    -Message "Restore point created successfully"
                $script:SuccessCount++
            }
            catch {
                Write-Host "[!] Failed to create restore point: $($_.Exception.Message)" -ForegroundColor Yellow
                Add-OperationResult -Name "Create Restore Point" -Status "Failed" -Message $_.Exception.Message
                $script:FailCount++

                if (-not $Force) {
                    $continue = Read-Host "Continue without restore point? (Y/N)"
                    if ($continue -ne 'Y') {
                        Write-Host "[!] Operation cancelled." -ForegroundColor Yellow
                        return 0
                    }
                }
            }
        }

        # Reset Winsock
        Write-Host "`nResetting Winsock catalog..." -ForegroundColor Yellow

        if ($PSCmdlet.ShouldProcess("Winsock catalog", "Reset")) {
            $winsockResult = Invoke-Netsh winsock reset
            if ($winsockResult -eq 0) {
                Write-Host "[+] Winsock reset successful" -ForegroundColor Green
                Add-OperationResult -Name "Winsock Reset" -Status "Success" `
                    -Message "Winsock catalog reset successfully"
                $script:SuccessCount++
                $script:RestartRequired = $true
            }
            else {
                Write-Host "[!] Winsock reset failed (netsh exit code: $winsockResult)" -ForegroundColor Yellow
                Add-OperationResult -Name "Winsock Reset" -Status "Failed" -Message "netsh winsock reset failed"
                $script:FailCount++
            }
        }

        # Reset TCP/IP stack
        Write-Host "`nResetting TCP/IP stack..." -ForegroundColor Yellow

        if ($PSCmdlet.ShouldProcess("TCP/IP stack", "Reset")) {
            $tcpipResult = Invoke-Netsh int ip reset
            if ($tcpipResult -eq 0) {
                Write-Host "[+] TCP/IP stack reset successful" -ForegroundColor Green
                Add-OperationResult -Name "TCP/IP Reset" -Status "Success" -Message "TCP/IP stack reset successfully"
                $script:SuccessCount++
                $script:RestartRequired = $true
            }
            else {
                Write-Host "[!] TCP/IP reset failed (netsh exit code: $tcpipResult)" -ForegroundColor Yellow
                Add-OperationResult -Name "TCP/IP Reset" -Status "Failed" -Message "netsh int ip reset failed"
                $script:FailCount++
            }
        }

        # Reset IPv6
        Write-Host "`nResetting IPv6 configuration..." -ForegroundColor Yellow

        if ($PSCmdlet.ShouldProcess("IPv6 configuration", "Reset")) {
            $ipv6Result = Invoke-Netsh int ipv6 reset
            if ($ipv6Result -eq 0) {
                Write-Host "[+] IPv6 reset successful" -ForegroundColor Green
                Add-OperationResult -Name "IPv6 Reset" -Status "Success" `
                    -Message "IPv6 configuration reset successfully"
                $script:SuccessCount++
            }
            else {
                Write-Host "[!] IPv6 reset failed (netsh exit code: $ipv6Result)" -ForegroundColor Yellow
                Add-OperationResult -Name "IPv6 Reset" -Status "Failed" -Message "netsh int ipv6 reset failed"
                $script:FailCount++
            }
        }

        # Flush DNS cache
        if ($FlushDNS) {
            Write-Host "`nFlushing DNS resolver cache..." -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess("DNS resolver cache", "Flush")) {
                try {
                    Clear-DnsClientCache -ErrorAction Stop
                    Write-Host "[+] DNS cache flushed" -ForegroundColor Green
                    Add-OperationResult -Name "Flush DNS Cache" -Status "Success" `
                        -Message "DNS resolver cache cleared successfully"
                    $script:SuccessCount++
                }
                catch {
                    Write-Host "[!] DNS flush failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    Add-OperationResult -Name "Flush DNS Cache" -Status "Failed" -Message $_.Exception.Message
                    $script:FailCount++
                }
            }
        }

        # Reset proxy settings
        if ($ResetProxy) {
            Write-Host "`nResetting proxy settings..." -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess("Proxy settings", "Reset")) {
                $proxyResult = Invoke-Netsh winhttp reset proxy
                if ($proxyResult -eq 0) {
                    Write-Host "[+] Proxy settings reset" -ForegroundColor Green
                    Add-OperationResult -Name "Reset Proxy" -Status "Success" `
                        -Message "Proxy settings reset successfully"
                    $script:SuccessCount++
                }
                else {
                    Write-Host "[!] Proxy reset failed (netsh exit code: $proxyResult)" -ForegroundColor Yellow
                    Add-OperationResult -Name "Reset Proxy" -Status "Failed" `
                        -Message "netsh winhttp reset proxy failed"
                    $script:FailCount++
                }
            }
        }

        # Reset Windows Firewall
        if ($ResetFirewall) {
            Write-Host "`nResetting Windows Firewall..." -ForegroundColor Yellow
            Write-Host "WARNING: This will reset all firewall rules to defaults!" -ForegroundColor Red

            $proceedFirewall = $true
            if (-not $Force) {
                $fwConfirm = Read-Host "Continue with firewall reset? (Y/N)"
                if ($fwConfirm -ne 'Y') {
                    $proceedFirewall = $false
                    Write-Host "[!] Skipping firewall reset" -ForegroundColor Yellow
                }
            }

            if ($proceedFirewall -and $PSCmdlet.ShouldProcess("Windows Firewall", "Reset")) {
                $fwResult = Invoke-Netsh advfirewall reset
                if ($fwResult -eq 0) {
                    Write-Host "[+] Firewall reset successful" -ForegroundColor Green
                    Add-OperationResult -Name "Reset Firewall" -Status "Success" `
                        -Message "Windows Firewall reset to defaults"
                    $script:SuccessCount++
                }
                else {
                    Write-Host "[!] Firewall reset failed (netsh exit code: $fwResult)" -ForegroundColor Yellow
                    Add-OperationResult -Name "Reset Firewall" -Status "Failed" `
                        -Message "netsh advfirewall reset failed"
                    $script:FailCount++
                }
            }
        }

        # Reset network adapters
        if ($ResetAdapters) {
            Write-Host "`nResetting network adapters..." -ForegroundColor Yellow

            if ($PSCmdlet.ShouldProcess("Network adapters", "Reset")) {
                $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -ne 'Disabled' }

                foreach ($adapter in $adapters) {
                    Write-Host "  Resetting $($adapter.Name)..." -ForegroundColor Gray

                    try {
                        Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                        Start-Sleep -Seconds 2
                        Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                        Write-Host "  [+] $($adapter.Name) reset successful" -ForegroundColor Green

                        Add-OperationResult -Name "Reset Adapter: $($adapter.Name)" -Status "Success" `
                            -Message "Adapter disabled and re-enabled"
                        $script:SuccessCount++
                    }
                    catch {
                        Write-Host "[!]   Failed to reset $($adapter.Name): $($_.Exception.Message)" `
                            -ForegroundColor Yellow
                        Add-OperationResult -Name "Reset Adapter: $($adapter.Name)" -Status "Failed" `
                            -Message $_.Exception.Message
                        $script:FailCount++
                    }
                }
            }
        }

        # Release and renew DHCP
        if ($PSCmdlet.ShouldProcess("DHCP leases", "Renew")) {
            Write-Host "`nRenewing DHCP leases..." -ForegroundColor Yellow

            Invoke-Ipconfig /release | Out-Null
            Start-Sleep -Seconds 2
            $renewResult = Invoke-Ipconfig /renew

            if ($renewResult -eq 0) {
                Write-Host "[+] DHCP lease renewed" -ForegroundColor Green
                Add-OperationResult -Name "Renew DHCP" -Status "Success" -Message "DHCP lease released and renewed"
                $script:SuccessCount++
            }
            else {
                Write-Host "[!] DHCP renewal failed (ipconfig exit code: $renewResult)" -ForegroundColor Yellow
                Add-OperationResult -Name "Renew DHCP" -Status "Failed" -Message "ipconfig /renew failed"
                $script:FailCount++
            }
        }

        # Display summary
        Write-Host "`n=== Reset Summary ===" -ForegroundColor Cyan
        Write-Host "Successful Operations: $($script:SuccessCount)" -ForegroundColor Green
        Write-Host "Failed Operations: $($script:FailCount)" `
            -ForegroundColor $(if ($script:FailCount -gt 0) { 'Red' } else { 'Green' })

        Write-Host "`n=== Operations Performed ===" -ForegroundColor Cyan
        $script:Operations | Format-Table -AutoSize

        # Export log
        $logPath = "$env:TEMP\NetworkReset_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $script:Operations | Export-Csv -Path $logPath -NoTypeInformation -ErrorAction Stop
        Write-Host "`n[+] Operation log saved to: $logPath" -ForegroundColor Green

        # Restart prompt
        if ($script:RestartRequired) {
            Write-Host "`nRESTART REQUIRED: Some changes require a system restart to take effect." `
                -ForegroundColor Yellow

            if (-not $Force) {
                $restartNow = Read-Host "Restart computer now? (Y/N)"
                if ($restartNow -eq 'Y' -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Restart computer")) {
                    Write-Host "`nRestarting computer in 10 seconds..." -ForegroundColor Yellow
                    Write-Host "Press Ctrl+C to cancel" -ForegroundColor Gray
                    Start-Sleep -Seconds 10
                    Restart-Computer -Force -ErrorAction Stop
                }
                else {
                    Write-Host "`nPlease restart your computer manually to complete the network reset." `
                        -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "`nPlease restart your computer to complete the network reset." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "`n[+] Network stack reset complete. No restart required." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[-] Error during network stack reset: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }

    Write-Host "`nEnd Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

    if ($script:FailCount -gt 0) {
        Write-Host "[-] Network stack reset completed with $($script:FailCount) failed operation(s)." `
            -ForegroundColor Red
        return 1
    }

    return 0
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
