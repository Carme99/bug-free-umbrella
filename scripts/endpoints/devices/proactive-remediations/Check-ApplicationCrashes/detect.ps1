<#
.SYNOPSIS
    Monitors application crashes and hangs.

.DESCRIPTION
    Tracks application failures, crashes, and hangs that impact user productivity.
    Identifies problematic applications for troubleshooting or replacement.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: No significant application crashes
    Exit 1: Excessive application crashes detected

.CONFIGURATION
    $daysToCheck: Number of days to analyze (default: 7 days)
    $maxCrashes: Maximum acceptable crash count (default: 10)
#>

try {
    # Configuration
    $daysToCheck = 7
    $maxCrashes = 10

    $issues = @()

    Write-Host "Checking for application crashes in last $daysToCheck days..."

    # Event ID 1000: Application Error (crash)
    $appCrashes = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        ProviderName = 'Application Error'
        ID = 1000
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 100 -ErrorAction SilentlyContinue

    if ($appCrashes) {
        $crashCount = $appCrashes.Count
        Write-Host "  Application crashes: $crashCount"

        if ($crashCount -gt $maxCrashes) {
            $issues += "Excessive application crashes detected: $crashCount events"

            # Identify most problematic applications
            # Use structured properties instead of parsing localized message text
            # For Event ID 1000, Properties[0] contains the application name
            $crashedApps = $appCrashes | ForEach-Object {
                if ($_.Properties -and $_.Properties.Count -gt 0) {
                    $_.Properties[0].Value
                }
            } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5

            Write-Host "  Most frequently crashing applications:"
            foreach ($app in $crashedApps) {
                Write-Host "    - $($app.Name): $($app.Count) crashes"
            }
        }
    }

    # Event ID 1002: Application Hang
    $appHangs = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        ProviderName = 'Application Hang'
        ID = 1002
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 50 -ErrorAction SilentlyContinue

    if ($appHangs) {
        $hangCount = $appHangs.Count
        Write-Host "  Application hangs: $hangCount"

        if ($hangCount -gt 5) {
            $issues += "Frequent application hangs detected: $hangCount events"
        }
    }

    # Event ID 1001: Windows Error Reporting fault bucket
    $werfaults = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        ProviderName = 'Windows Error Reporting'
        ID = 1001
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 50 -ErrorAction SilentlyContinue

    if ($werfaults) {
        $werCount = $werfaults.Count
        Write-Host "  Windows Error Reporting events: $werCount"
    }

    # Check for .NET Runtime errors (common for LOB apps)
    $dotnetErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        ProviderName = '.NET Runtime'
        Level = 2
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 50 -ErrorAction SilentlyContinue

    if ($dotnetErrors) {
        $dotnetCount = $dotnetErrors.Count
        Write-Host "  .NET Runtime errors: $dotnetCount"

        if ($dotnetCount -gt 5) {
            $issues += ".NET application errors detected: $dotnetCount events"
        }
    }

    # Check for Office application crashes
    # Note: FilterHashtable doesn't support wildcards, so query all errors and filter with Where-Object
    $officeErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        Level = 2
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 200 -ErrorAction SilentlyContinue | Where-Object {
        $_.ProviderName -like 'Microsoft Office*'
    } | Select-Object -First 20

    if ($officeErrors) {
        $officeCount = $officeErrors.Count
        Write-Host "  Microsoft Office errors: $officeCount"

        if ($officeCount -gt 5) {
            $issues += "Microsoft Office application errors: $officeCount events"
        }
    }

    # Check WER local dumps directory for recent crash dumps
    $werDumps = @()
    $werPaths = @(
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
    )

    foreach ($path in $werPaths) {
        if (Test-Path $path) {
            $dumps = Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-$daysToCheck) }

            if ($dumps) {
                $werDumps += $dumps
            }
        }
    }

    if ($werDumps.Count -gt 0) {
        Write-Host "  Recent crash dump files: $($werDumps.Count)"
        if ($werDumps.Count -gt 20) {
            $issues += "Excessive crash dump files: $($werDumps.Count) files"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "`nApplication crash issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        Write-Host "`nRecommendation: Update applications, reinstall problematic apps, check compatibility"
        exit 1
    }

    Write-Host "`nNo significant application crashes detected"
    exit 0

}
catch {
    Write-Host "Error checking application crashes: $_"
    exit 1
}
