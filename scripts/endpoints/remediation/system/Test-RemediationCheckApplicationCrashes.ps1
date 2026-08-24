<#
.SYNOPSIS
    Check for excessive application crashes and hangs in the Windows event logs.

.DESCRIPTION
    Scans the Application event log for application crashes (event ID 1000), hangs
    (1002), Windows Error Reporting fault buckets (1001), .NET Runtime errors and
    Microsoft Office errors over the analysis window, and counts recent files in the
    local WER crash dump folders. Devices whose application crash count exceeds the
    configured maximum are flagged so problematic applications can be updated,
    reinstalled or replaced.
    Exit codes: 0 = no significant application crashes or hangs, 1 = excessive
    application crashes detected (or an unexpected error occurred). The script is
    read-only, changes no system state and is therefore idempotent.
    Configuration: $daysToCheck sets the analysis window (default 7 days) and
    $maxCrashes sets the maximum acceptable crash count (default 10).

.EXAMPLE
    PS C:\> .\Test-RemediationCheckApplicationCrashes.ps1

    Exits 0 when application stability is acceptable; exits 1 when excessive crashes are detected.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckApplicationCrashes.ps1 -Verbose

    Runs the same analysis with verbose progress information.

.NOTES
    File Name  : Test-RemediationCheckApplicationCrashes.ps1
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
        $daysToCheck = 7
        $maxCrashes = 10

        $issues = @()

        Write-Host "[*] Checking for application crashes in last $daysToCheck days..." -ForegroundColor Cyan

        # Event ID 1000: Application Error (crash)
        $appCrashes = Get-WinEvent -FilterHashtable @{
            LogName      = 'Application'
            ProviderName = 'Application Error'
            ID           = 1000
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 100 -ErrorAction SilentlyContinue

        if ($appCrashes) {
            $crashCount = @($appCrashes).Count
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
            LogName      = 'Application'
            ProviderName = 'Application Hang'
            ID           = 1002
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        if ($appHangs) {
            $hangCount = @($appHangs).Count
            Write-Host "  Application hangs: $hangCount"

            if ($hangCount -gt 5) {
                $issues += "Frequent application hangs detected: $hangCount events"
            }
        }

        # Event ID 1001: Windows Error Reporting fault bucket
        $werfaults = Get-WinEvent -FilterHashtable @{
            LogName      = 'Application'
            ProviderName = 'Windows Error Reporting'
            ID           = 1001
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        if ($werfaults) {
            Write-Host "  Windows Error Reporting events: $(@($werfaults).Count)"
        }

        # Check for .NET Runtime errors (common for LOB apps)
        $dotnetErrors = Get-WinEvent -FilterHashtable @{
            LogName      = 'Application'
            ProviderName = '.NET Runtime'
            Level        = 2
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        if ($dotnetErrors) {
            $dotnetCount = @($dotnetErrors).Count
            Write-Host "  .NET Runtime errors: $dotnetCount"

            if ($dotnetCount -gt 5) {
                $issues += ".NET application errors detected: $dotnetCount events"
            }
        }

        # Check for Office application crashes
        # Note: FilterHashtable doesn't support wildcards, so query all errors and filter with Where-Object
        $officeErrors = Get-WinEvent -FilterHashtable @{
            LogName   = 'Application'
            Level     = 2
            StartTime = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 200 -ErrorAction SilentlyContinue | Where-Object {
            $_.ProviderName -like 'Microsoft Office*'
        } | Select-Object -First 20

        if ($officeErrors) {
            $officeCount = @($officeErrors).Count
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

        if (@($werDumps).Count -gt 0) {
            Write-Host "  Recent crash dump files: $(@($werDumps).Count)"
            if (@($werDumps).Count -gt 20) {
                $issues += "Excessive crash dump files: $(@($werDumps).Count) files"
            }
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Application crash issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            Write-Host "[*] Recommendation: update applications, reinstall problematic apps, check compatibility" -ForegroundColor Cyan
            return 1
        }

        Write-Host "[+] No significant application crashes detected" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking application crashes: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
