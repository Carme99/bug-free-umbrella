<#
.SYNOPSIS
    Test connectivity to all required Intune, Windows Update, and Azure AD service endpoints.

.DESCRIPTION
    Validates that the device can reach all necessary Intune, Windows Update, and Azure AD endpoints via HTTPS
    HEAD requests, then performs additional network checks for DNS resolution, proxy configuration, and Azure AD
    join status. Useful for troubleshooting enrollment and sync issues; results can be exported to CSV.
    Exit code is 0 when every endpoint is reachable and 1 when any endpoint check failed.

.PARAMETER Detailed
    Shows detailed connectivity results for each endpoint.

.PARAMETER ExportResults
    Export results to CSV file.

.EXAMPLE
    PS C:\> .\Test-IntuneConnectivity.ps1
    Tests all required endpoints and prints a per-category summary.

.EXAMPLE
    PS C:\> .\Test-IntuneConnectivity.ps1 -Detailed -ExportResults
    Prints per-endpoint detail and exports the full result set to a timestamped CSV file.

.NOTES
    File Name: Test-IntuneConnectivity.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Detailed,

    [Parameter(Mandatory = $false)]
    [switch]$ExportResults
)

$ErrorActionPreference = 'Stop'

function Invoke-DsRegCmdStatus {
    # Thin wrapper around the native dsregcmd executable (mock seam for offline testing).
    $output = & dsregcmd /status 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "dsregcmd exited with code $LASTEXITCODE"
    }
    return $output
}

function Main {
    [CmdletBinding()]
    param()

    try {
        Write-Host "[*] Starting Intune connectivity test..." -ForegroundColor Cyan

        # Required Intune endpoints
        $intuneEndpoints = @{
            "Intune Enrollment" = @(
                "https://enrollment.manage.microsoft.com",
                "https://enterpriseregistration.windows.net"
            )
            "Intune Management" = @(
                "https://portal.manage.microsoft.com",
                "https://m.manage.microsoft.com",
                "https://fef.msuc03.manage.microsoft.com"
            )
            "Windows Update" = @(
                "https://fe3.delivery.mp.microsoft.com",
                "https://au.download.windowsupdate.com"
            )
            "Azure AD" = @(
                "https://login.microsoftonline.com",
                "https://login.windows.net",
                "https://device.login.microsoftonline.com"
            )
            "Microsoft Graph" = @(
                "https://graph.microsoft.com",
                "https://graph.windows.net"
            )
            "Telemetry & Diagnostics" = @(
                "https://v10.events.data.microsoft.com",
                "https://settings-win.data.microsoft.com"
            )
        }

        $results = @()
        $totalTests = 0
        $passedTests = 0
        $failedTests = 0

        foreach ($category in $intuneEndpoints.Keys) {
            Write-Host "[*] Testing $category..." -ForegroundColor Yellow

            foreach ($endpoint in $intuneEndpoints[$category]) {
                $totalTests++

                try {
                    # Test HTTPS connectivity
                    $response = Invoke-WebRequest -Uri $endpoint `
                        -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop

                    $status = "[+] Success"
                    $statusCode = $response.StatusCode
                    $accessible = $true
                    $passedTests++

                    if ($Detailed) {
                        Write-Host "  [+] $endpoint - Status: $statusCode" -ForegroundColor Green
                    }

                }
                catch {
                    $status = "[-] Failed"
                    $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "N/A" }
                    $errorMsg = $_.Exception.Message
                    $accessible = $false
                    $failedTests++

                    if ($Detailed) {
                        Write-Host "  [-] $endpoint - Error: $errorMsg" -ForegroundColor Red
                    }
                }

                $results += [PSCustomObject]@{
                    Category     = $category
                    Endpoint     = $endpoint
                    Accessible   = $accessible
                    Status       = $status
                    StatusCode   = $statusCode
                    ErrorMessage = if ($accessible) { "" } else { $errorMsg }
                    TestedAt     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
            }

            if (-not $Detailed) {
                $categoryPassed = ($results | Where-Object { $_.Category -eq $category -and $_.Accessible }).Count
                $categoryTotal = ($results | Where-Object { $_.Category -eq $category }).Count
                $categoryColor = if ($categoryPassed -eq $categoryTotal) { "Green" } else { "Yellow" }
                Write-Host "  $categoryPassed/$categoryTotal endpoints accessible" -ForegroundColor $categoryColor
            }
        }

        # Additional network tests
        Write-Host "[*] Performing additional network tests..." -ForegroundColor Yellow

        # Test DNS resolution
        Write-Host "  Testing DNS resolution..." -ForegroundColor Gray
        try {
            $dnsTest = Resolve-DnsName -Name "login.microsoftonline.com" -ErrorAction Stop
            Write-Host "  [+] DNS resolution working" -ForegroundColor Green
            $dnsWorking = $true
        }
        catch {
            Write-Host "  [-] DNS resolution failed" -ForegroundColor Red
            $dnsWorking = $false
        }

        # Test proxy settings
        Write-Host "  Checking proxy configuration..." -ForegroundColor Gray
        $proxyKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        $proxySettings = Get-ItemProperty -Path $proxyKey -ErrorAction SilentlyContinue
        if ($proxySettings.ProxyEnable -eq 1) {
            Write-Host "  [!] Proxy enabled: $($proxySettings.ProxyServer)" -ForegroundColor Yellow
            $proxyConfigured = $true
        }
        else {
            Write-Host "  [+] No proxy configured" -ForegroundColor Green
            $proxyConfigured = $false
        }

        # Check if device is Azure AD joined (native dsregcmd called through its wrapper)
        Write-Host "  Checking Azure AD join status..." -ForegroundColor Gray
        try {
            $dsregStatus = Invoke-DsRegCmdStatus
            if ($dsregStatus -match "AzureAdJoined\s*:\s*YES") {
                Write-Host "  [+] Device is Azure AD joined" -ForegroundColor Green
                $azureAdJoined = $true
            }
            else {
                Write-Host "  [!] Device is not Azure AD joined" -ForegroundColor Yellow
                $azureAdJoined = $false
            }
        }
        catch {
            Write-Host "  [-] Could not determine Azure AD join status" -ForegroundColor Red
            $azureAdJoined = $false
        }

        # Summary
        Write-Host ""
        Write-Host "TEST SUMMARY" -ForegroundColor Cyan

        Write-Host "Total Endpoints Tested: $totalTests" -ForegroundColor White
        Write-Host "Passed: $passedTests" -ForegroundColor Green
        Write-Host "Failed: $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { "Red" } else { "Green" })
        $successRate = [math]::Round(($passedTests / $totalTests) * 100, 1)
        $rateColor = if ($failedTests -eq 0) { "Green" } else { "Yellow" }
        Write-Host "Success Rate: $successRate%" -ForegroundColor $rateColor

        $dnsLabel = if ($dnsWorking) { '[+] Working' } else { '[-] Failed' }
        $dnsColor = if ($dnsWorking) { "Green" } else { "Red" }
        Write-Host "DNS Resolution: $dnsLabel" -ForegroundColor $dnsColor
        $proxyLabel = if ($proxyConfigured) { '[!] Yes' } else { '[+] No' }
        $proxyColor = if ($proxyConfigured) { "Yellow" } else { "Green" }
        Write-Host "Proxy Configured: $proxyLabel" -ForegroundColor $proxyColor
        $aadLabel = if ($azureAdJoined) { '[+] Yes' } else { '[!] No' }
        $aadColor = if ($azureAdJoined) { "Green" } else { "Yellow" }
        Write-Host "Azure AD Joined: $aadLabel" -ForegroundColor $aadColor

        # Export results if requested
        if ($ExportResults) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $reportPath = "IntuneConnectivityTest-$timestamp.csv"
            $results | Export-Csv -Path $reportPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] Results exported to: $reportPath" -ForegroundColor Green
        }

        # Recommendations
        if ($failedTests -gt 0) {
            Write-Host ""
            Write-Host "[!] Recommendations:" -ForegroundColor Yellow
            Write-Host "  - Check firewall rules and proxy settings" -ForegroundColor White
            Write-Host "  - Verify network connectivity" -ForegroundColor White
            Write-Host "  - Review required endpoints: https://aka.ms/intune-endpoints" -ForegroundColor White
            Write-Host "  - Contact network administrator if issues persist" -ForegroundColor White
        }

        if ($failedTests -eq 0) {
            return 0
        }
        return 1
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
