<#
.SYNOPSIS
    Tests connectivity to all required Intune service endpoints.

.DESCRIPTION
    Validates that the device can reach all necessary Intune, Windows Update,
    and Azure AD endpoints. Useful for troubleshooting enrollment and sync issues.

.PARAMETER Detailed
    Shows detailed connectivity results for each endpoint

.PARAMETER ExportResults
    Export results to CSV file

.EXAMPLE
    .\Test-IntuneConnectivity.ps1

.EXAMPLE
    .\Test-IntuneConnectivity.ps1 -Detailed -ExportResults

.NOTES
    Author: Intune Admin
    Version: 1.0
    Requires: Administrator privileges for some tests
    Can be run on client devices or from admin workstation
#>

param(
    [Parameter(Mandatory = $false)]
    [switch]$Detailed,

    [Parameter(Mandatory = $false)]
    [switch]$ExportResults
)

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

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Intune Connectivity Test                          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

foreach ($category in $intuneEndpoints.Keys) {
    Write-Host "Testing $category..." -ForegroundColor Yellow

    foreach ($endpoint in $intuneEndpoints[$category]) {
        $totalTests++

        try {
            # Test HTTPS connectivity
            $response = Invoke-WebRequest -Uri $endpoint -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop

            $status = "✅ Success"
            $statusCode = $response.StatusCode
            $responseTime = $response.Headers["X-Request-Time"]
            $accessible = $true
            $passedTests++

            if ($Detailed) {
                Write-Host "  ✅ $endpoint - Status: $statusCode" -ForegroundColor Green
            }

        } catch {
            $status = "❌ Failed"
            $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "N/A" }
            $errorMsg = $_.Exception.Message
            $accessible = $false
            $failedTests++

            if ($Detailed) {
                Write-Host "  ❌ $endpoint - Error: $errorMsg" -ForegroundColor Red
            }
        }

        $results += [PSCustomObject]@{
            Category = $category
            Endpoint = $endpoint
            Accessible = $accessible
            Status = $status
            StatusCode = $statusCode
            ErrorMessage = if ($accessible) { "" } else { $errorMsg }
            TestedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }

    if (-not $Detailed) {
        $categoryPassed = ($results | Where-Object { $_.Category -eq $category -and $_.Accessible }).Count
        $categoryTotal = ($results | Where-Object { $_.Category -eq $category }).Count
        Write-Host "  $categoryPassed/$categoryTotal endpoints accessible" -ForegroundColor $(if ($categoryPassed -eq $categoryTotal) { "Green" } else { "Yellow" })
    }
}

# Additional network tests
Write-Host "`nPerforming additional network tests..." -ForegroundColor Yellow

# Test DNS resolution
Write-Host "  Testing DNS resolution..." -ForegroundColor Gray
try {
    $dnsTest = Resolve-DnsName -Name "login.microsoftonline.com" -ErrorAction Stop
    Write-Host "    ✅ DNS resolution working" -ForegroundColor Green
    $dnsWorking = $true
} catch {
    Write-Host "    ❌ DNS resolution failed" -ForegroundColor Red
    $dnsWorking = $false
}

# Test proxy settings
Write-Host "  Checking proxy configuration..." -ForegroundColor Gray
$proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
if ($proxySettings.ProxyEnable -eq 1) {
    Write-Host "    ⚠️  Proxy enabled: $($proxySettings.ProxyServer)" -ForegroundColor Yellow
    $proxyConfigured = $true
} else {
    Write-Host "    ✅ No proxy configured" -ForegroundColor Green
    $proxyConfigured = $false
}

# Check if device is Azure AD joined
Write-Host "  Checking Azure AD join status..." -ForegroundColor Gray
try {
    $dsregStatus = dsregcmd /status 2>&1 | Out-String
    if ($dsregStatus -match "AzureAdJoined\s*:\s*YES") {
        Write-Host "    ✅ Device is Azure AD joined" -ForegroundColor Green
        $azureAdJoined = $true
    } else {
        Write-Host "    ⚠️  Device is not Azure AD joined" -ForegroundColor Yellow
        $azureAdJoined = $false
    }
} catch {
    Write-Host "    ❌ Could not determine Azure AD join status" -ForegroundColor Red
    $azureAdJoined = $false
}

# Summary
Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Test Summary                                       ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Total Endpoints Tested: $totalTests" -ForegroundColor White
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { "Red" } else { "Green" })
Write-Host "Success Rate: $([math]::Round(($passedTests / $totalTests) * 100, 1))%`n" -ForegroundColor $(if ($failedTests -eq 0) { "Green" } else { "Yellow" })

Write-Host "DNS Resolution: $(if ($dnsWorking) { '✅ Working' } else { '❌ Failed' })" -ForegroundColor $(if ($dnsWorking) { "Green" } else { "Red" })
Write-Host "Proxy Configured: $(if ($proxyConfigured) { '⚠️  Yes' } else { '✅ No' })" -ForegroundColor $(if ($proxyConfigured) { "Yellow" } else { "Green" })
Write-Host "Azure AD Joined: $(if ($azureAdJoined) { '✅ Yes' } else { '⚠️  No' })" -ForegroundColor $(if ($azureAdJoined) { "Green" } else { "Yellow" })

# Export results if requested
if ($ExportResults) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $reportPath = "IntuneConnectivityTest-$timestamp.csv"
    $results | Export-Csv -Path $reportPath -NoTypeInformation
    Write-Host "`n✅ Results exported to: $reportPath" -ForegroundColor Green
}

# Recommendations
if ($failedTests -gt 0) {
    Write-Host "`n⚠️  Recommendations:" -ForegroundColor Yellow
    Write-Host "  - Check firewall rules and proxy settings" -ForegroundColor White
    Write-Host "  - Verify network connectivity" -ForegroundColor White
    Write-Host "  - Review required endpoints: https://aka.ms/intune-endpoints" -ForegroundColor White
    Write-Host "  - Contact network administrator if issues persist" -ForegroundColor White
}

exit $(if ($failedTests -eq 0) { 0 } else { 1 })
