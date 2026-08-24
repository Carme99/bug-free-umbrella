<#
.SYNOPSIS
    Check the system for hardware errors and impending hardware failures.

.DESCRIPTION
    Scans the System event log over the last 14 days for WHEA hardware errors,
    physical disk errors, processor errors, USB controller errors, network
    adapter hardware errors, battery hardware errors, firmware processor
    throttling (Kernel-Processor-Power event 37) and PCI/PCIe bus errors, and
    queries SMART failure-prediction status for every disk via the WMI
    MSStorageDriver_FailurePredict* classes.
    Exit codes: 0 = no hardware errors detected, 1 = hardware errors found (or
    an unexpected error occurred). The script changes no system state, so it is
    safe to re-run at any time (idempotent).
    Intune Context: SYSTEM. Configuration lives inline: $daysToCheck controls
    how many days of event logs are analyzed (default: 14 days).

.EXAMPLE
    PS C:\> .\Test-RemediationCheckHardwareErrors.ps1

    Exits 0 when no hardware errors are detected; exits 1 when hardware errors
    are found.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckHardwareErrors.ps1 -Verbose

    Runs the same hardware error scan with verbose progress information.

.NOTES
    File Name  : Test-RemediationCheckHardwareErrors.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Main {
    try {
        # Configuration
        $daysToCheck = 14

        $issues = @()

        Write-Host "[*] Checking for hardware errors in last $daysToCheck days..." -ForegroundColor Cyan

        # Check WHEA (Windows Hardware Error Architecture) errors
        $wheaErrors = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-WHEA-Logger'
            Level        = 2, 3  # Error and Warning
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        if ($wheaErrors) {
            $wheaCount = $wheaErrors.Count
            Write-Host "[*] WHEA hardware errors: $wheaCount" -ForegroundColor Cyan

            if ($wheaCount -gt 0) {
                $issues += "Hardware errors detected by WHEA: $wheaCount events"

                # Categorize WHEA errors by type
                $wheaTypes = $wheaErrors | Group-Object Id | Select-Object -First 5
                Write-Host "[*] Error types:" -ForegroundColor Cyan
                foreach ($type in $wheaTypes) {
                    Write-Host "[*]   - Event ID $($type.Name): $($type.Count) errors" -ForegroundColor Cyan
                }
            }
        }

        # Check disk SMART status
        Write-Host "[*] Checking disk health..." -ForegroundColor Cyan
        $disks = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue

        if ($disks) {
            foreach ($disk in $disks) {
                if ($disk.PredictFailure -eq $true) {
                    $issues += "SMART failure prediction on disk"
                    Write-Host "[!] WARNING: Disk failure predicted - back up data immediately!" -ForegroundColor Yellow
                }
            }

            # Get SMART data
            $smartData = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictData -ErrorAction SilentlyContinue

            if ($smartData) {
                foreach ($smart in $smartData) {
                    Write-Host "[*] Disk instance: $($smart.InstanceName)" -ForegroundColor Cyan
                    if ($smart.PredictFailure) {
                        Write-Host "[*] Status: FAILING" -ForegroundColor Cyan
                    }
                    else {
                        Write-Host "[*] Status: OK" -ForegroundColor Cyan
                    }
                }
            }
        }

        # Check physical disk errors
        $diskErrors = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'disk'
            Level        = 2, 3
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 20 -ErrorAction SilentlyContinue

        if ($diskErrors) {
            $diskErrorCount = $diskErrors.Count
            Write-Host "[*] Physical disk errors: $diskErrorCount" -ForegroundColor Cyan

            if ($diskErrorCount -gt 3) {
                $issues += "Frequent disk errors detected: $diskErrorCount events"
            }
        }

        # Check CPU/Processor errors
        $cpuErrors = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'
            Level        = 2
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if ($cpuErrors) {
            $cpuErrorCount = $cpuErrors.Count
            Write-Host "[*] Processor errors: $cpuErrorCount" -ForegroundColor Cyan

            if ($cpuErrorCount -gt 0) {
                $issues += "Processor errors detected: $cpuErrorCount events"
            }
        }

        # Check USB controller errors
        $usbErrors = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'USBHUB3', 'USBXHCI'
            Level        = 2
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 20 -ErrorAction SilentlyContinue

        if ($usbErrors) {
            $usbErrorCount = $usbErrors.Count
            Write-Host "[*] USB controller errors: $usbErrorCount" -ForegroundColor Cyan

            if ($usbErrorCount -gt 5) {
                $issues += "USB controller issues detected: $usbErrorCount events"
            }
        }

        # Check network adapter hardware errors
        # Note: FilterHashtable doesn't support wildcards, so query all errors and filter with Where-Object
        $allSystemErrors = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Level     = 2
            StartTime = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 200 -ErrorAction SilentlyContinue

        $netErrors = $allSystemErrors | Where-Object {
            $_.ProviderName -like 'e1*' -or
            $_.ProviderName -like 'NETw*' -or
            $_.ProviderName -like 'Realtek*' -or
            $_.ProviderName -like 'Intel*'
        } | Select-Object -First 20

        if ($netErrors) {
            $netErrorCount = $netErrors.Count
            Write-Host "[*] Network adapter errors: $netErrorCount" -ForegroundColor Cyan

            if ($netErrorCount -gt 5) {
                $issues += "Network adapter hardware issues: $netErrorCount events"
            }
        }

        # Check battery hardware errors (laptops)
        # Reuse $allSystemErrors from above to avoid redundant query
        $batteryErrors = $allSystemErrors | Where-Object {
            $_.ProviderName -like 'Microsoft-Windows-Battery*'
        } | Select-Object -First 10

        if ($batteryErrors) {
            $batteryErrorCount = $batteryErrors.Count
            Write-Host "[*] Battery hardware errors: $batteryErrorCount" -ForegroundColor Cyan

            if ($batteryErrorCount -gt 0) {
                $issues += "Battery hardware issues detected: $batteryErrorCount events"
            }
        }

        # Check for processor speed throttling by firmware (Event 37, Warning level)
        # Documented provider is Microsoft-Windows-Kernel-Processor-Power, not Kernel-Power:
        # "The speed of processor x in group y is being limited by system firmware".
        # See https://learn.microsoft.com/en-us/troubleshoot/windows-server/setup-upgrade-and-drivers/event-id-37-windows-kernel-processor-power
        $throttleEvents = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'
            ID           = 37
            Level        = 3  # Warning
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if ($throttleEvents) {
            $throttleCount = $throttleEvents.Count
            Write-Host "[*] Processor speed limited by firmware: $throttleCount" -ForegroundColor Cyan
            $issues += "Processor speed is being limited by system firmware: $throttleCount event(s) (Warning - check firmware power capping policy)"
        }

        # Check for PCI/PCIe errors
        $pciErrors = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'pci'
            Level        = 2
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if ($pciErrors) {
            $pciErrorCount = $pciErrors.Count
            Write-Host "[*] PCI/PCIe errors: $pciErrorCount" -ForegroundColor Cyan

            if ($pciErrorCount -gt 0) {
                $issues += "PCI/PCIe bus errors detected: $pciErrorCount events"
            }
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Hardware error issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            Write-Host "[!] URGENT: Hardware failures can cause data loss. Immediate action required." -ForegroundColor Yellow
            return 1
        }

        Write-Host "[+] No hardware errors detected - hardware health is good" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking hardware errors: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
