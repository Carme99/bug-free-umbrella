<#
.SYNOPSIS
    Monitors hardware errors and failures.

.DESCRIPTION
    Detects hardware-related errors from WHEA (Windows Hardware Error Architecture),
    disk SMART status, and other hardware monitoring sources. Early detection
    prevents data loss and unexpected hardware failures.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: No hardware errors detected
    Exit 1: Hardware errors found

.CONFIGURATION
    $daysToCheck: Number of days to analyze logs (default: 14 days)
#>

try {
    # Configuration
    $daysToCheck = 14

    $issues = @()

    Write-Host "Checking for hardware errors in last $daysToCheck days..."

    # Check WHEA (Windows Hardware Error Architecture) errors
    $wheaErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-WHEA-Logger'
        Level = 2, 3  # Error and Warning
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 50 -ErrorAction SilentlyContinue

    if ($wheaErrors) {
        $wheaCount = $wheaErrors.Count
        Write-Host "  WHEA hardware errors: $wheaCount"

        if ($wheaCount -gt 0) {
            $issues += "Hardware errors detected by WHEA: $wheaCount events"

            # Categorize WHEA errors by type
            $wheaTypes = $wheaErrors | Group-Object Id | Select-Object -First 5
            Write-Host "  Error types:"
            foreach ($type in $wheaTypes) {
                Write-Host "    - Event ID $($type.Name): $($type.Count) errors"
            }
        }
    }

    # Check disk SMART status
    Write-Host "`nChecking disk health..."
    $disks = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue

    if ($disks) {
        foreach ($disk in $disks) {
            if ($disk.PredictFailure -eq $true) {
                $issues += "SMART failure prediction on disk"
                Write-Host "  WARNING: Disk failure predicted - back up data immediately!"
            }
        }

        # Get SMART data
        $smartData = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictData -ErrorAction SilentlyContinue

        foreach ($smart in $smartData) {
            Write-Host "  Disk instance: $($smart.InstanceName)"
            Write-Host "  Status: $(if ($smart.PredictFailure) {'FAILING'} else {'OK'})"
        }
    }

    # Check physical disk errors
    $diskErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'disk'
        Level = 2, 3
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 20 -ErrorAction SilentlyContinue

    if ($diskErrors) {
        $diskErrorCount = $diskErrors.Count
        Write-Host "`n  Physical disk errors: $diskErrorCount"

        if ($diskErrorCount -gt 3) {
            $issues += "Frequent disk errors detected: $diskErrorCount events"
        }
    }

    # Check CPU/Processor errors
    $cpuErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'
        Level = 2
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    if ($cpuErrors) {
        $cpuErrorCount = $cpuErrors.Count
        Write-Host "  Processor errors: $cpuErrorCount"

        if ($cpuErrorCount -gt 0) {
            $issues += "Processor errors detected: $cpuErrorCount events"
        }
    }

    # Check USB controller errors
    $usbErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'USBHUB3', 'USBXHCI'
        Level = 2
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 20 -ErrorAction SilentlyContinue

    if ($usbErrors) {
        $usbErrorCount = $usbErrors.Count
        Write-Host "  USB controller errors: $usbErrorCount"

        if ($usbErrorCount -gt 5) {
            $issues += "USB controller issues detected: $usbErrorCount events"
        }
    }

    # Check network adapter hardware errors
    $netErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'e1*', 'NETw*', 'Realtek*', 'Intel*'
        Level = 2
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 20 -ErrorAction SilentlyContinue

    if ($netErrors) {
        $netErrorCount = $netErrors.Count
        Write-Host "  Network adapter errors: $netErrorCount"

        if ($netErrorCount -gt 5) {
            $issues += "Network adapter hardware issues: $netErrorCount events"
        }
    }

    # Check battery hardware errors (laptops)
    $batteryErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-Battery*'
        Level = 2
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    if ($batteryErrors) {
        $batteryErrorCount = $batteryErrors.Count
        Write-Host "  Battery hardware errors: $batteryErrorCount"

        if ($batteryErrorCount -gt 0) {
            $issues += "Battery hardware issues detected: $batteryErrorCount events"
        }
    }

    # Check for thermal/overheating issues
    $thermalEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-Kernel-Power'
        ID = 37  # Thermal event
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    if ($thermalEvents) {
        $thermalCount = $thermalEvents.Count
        Write-Host "  Thermal/overheating events: $thermalCount"
        $issues += "System overheating detected: $thermalCount thermal events"
    }

    # Check for PCI/PCIe errors
    $pciErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'pci'
        Level = 2
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    if ($pciErrors) {
        $pciErrorCount = $pciErrors.Count
        Write-Host "  PCI/PCIe errors: $pciErrorCount"

        if ($pciErrorCount -gt 0) {
            $issues += "PCI/PCIe bus errors detected: $pciErrorCount events"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "`nHardware error issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        Write-Host "`nURGENT: Hardware failures can cause data loss. Immediate action required."
        exit 1
    }

    Write-Host "`nNo hardware errors detected - hardware health is good"
    exit 0

} catch {
    Write-Host "Error checking hardware errors: $_"
    exit 1
}
