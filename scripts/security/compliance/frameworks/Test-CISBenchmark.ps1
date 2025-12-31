<#
.SYNOPSIS
    CIS Benchmark compliance testing for Windows Server.

.DESCRIPTION
    Tests system against CIS Windows Server benchmarks including password policies,
    audit settings, and security options. Uses secedit.exe and auditpol.exe to
    retrieve and validate security configurations.

.PARAMETER Level
    CIS Benchmark level to test against. Valid values: "1" (default) or "2".
    Level 1: Essential security requirements
    Level 2: Additional security for high-security environments

.PARAMETER ExportHTML
    Export results to an HTML report on the desktop.

.PARAMETER OutputPath
    Custom output path for HTML report. Default: Desktop

.EXAMPLE
    .\Test-CISBenchmark.ps1
    Runs Level 1 CIS benchmark tests with console output.

.EXAMPLE
    .\Test-CISBenchmark.ps1 -Level 2 -ExportHTML
    Runs Level 2 tests and exports HTML report to desktop.

.NOTES
    Author: IT Security
    Version: 2.0.0
    Requires: Administrator privileges
    Based on: CIS Microsoft Windows Server 2019/2022 Benchmark

    WARNING: This script requires elevation to export security policies.
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("1", "2")]
    [string]$Level = "1",

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = [Environment]::GetFolderPath('Desktop')
)

# Helper function to parse secedit output
function Get-SecurityPolicy {
    [CmdletBinding()]
    param()

    $tempFile = Join-Path $env:TEMP "secpol_$(Get-Date -Format 'yyyyMMddHHmmss').cfg"

    try {
        # Export security policy
        $null = secedit /export /cfg $tempFile /quiet

        if (-not (Test-Path $tempFile)) {
            throw "Failed to export security policy"
        }

        # Read and parse the INI-format file
        $content = Get-Content $tempFile -ErrorAction Stop
        $policy = @{}
        $currentSection = ""

        foreach ($line in $content) {
            if ($line -match '^\[(.+)\]$') {
                $currentSection = $matches[1]
                $policy[$currentSection] = @{}
            }
            elseif ($line -match '^(.+?)\s*=\s*(.*)$' -and $currentSection) {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                $policy[$currentSection][$key] = $value
            }
        }

        return $policy
    }
    catch {
        Write-Error "Failed to retrieve security policy: $($_.Exception.Message)"
        return $null
    }
    finally {
        # Cleanup temp file
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# Helper function to test a control
function Test-CISControl {
    [CmdletBinding()]
    param(
        [string]$ControlID,
        [string]$Description,
        [scriptblock]$TestScript,
        [string]$Recommendation,
        [int]$RequiredLevel = 1
    )

    if ([int]$Level -lt $RequiredLevel) {
        return $null
    }

    try {
        $result = & $TestScript

        return [PSCustomObject]@{
            ControlID = $ControlID
            Description = $Description
            Status = if ($result) { "Pass" } else { "Fail" }
            Recommendation = $Recommendation
            Level = $RequiredLevel
        }
    }
    catch {
        return [PSCustomObject]@{
            ControlID = $ControlID
            Description = $Description
            Status = "Error"
            Recommendation = "Error during test: $($_.Exception.Message)"
            Level = $RequiredLevel
        }
    }
}

# Main execution
Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host "   CIS Microsoft Windows Server Benchmark Compliance Test" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "Testing Level: $Level" -ForegroundColor Yellow
Write-Host "System: $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "==================================================================`n" -ForegroundColor Cyan

# Retrieve security policies
Write-Host "[*] Exporting security policies..." -ForegroundColor Cyan
$secPolicy = Get-SecurityPolicy

if (-not $secPolicy) {
    Write-Error "Failed to retrieve security policies. Exiting."
    exit 1
}

Write-Host "[+] Security policies retrieved successfully`n" -ForegroundColor Green

# Retrieve audit policies
Write-Host "[*] Retrieving audit policies..." -ForegroundColor Cyan
try {
    $auditOutput = auditpol /get /category:* 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "auditpol command failed"
    }
    Write-Host "[+] Audit policies retrieved successfully`n" -ForegroundColor Green
}
catch {
    Write-Warning "Failed to retrieve audit policies: $($_.Exception.Message)"
    $auditOutput = @()
}

# Initialize results collection
$testResults = @()
$passed = 0
$failed = 0
$errors = 0

# ==================================================================
# PASSWORD POLICIES (CIS Section 1.1)
# ==================================================================
Write-Host "[*] Testing Password Policies..." -ForegroundColor Cyan

# 1.1.1 Enforce password history
$testResults += Test-CISControl -ControlID "1.1.1" -Description "Enforce password history" `
    -TestScript {
        $value = $secPolicy['System Access']['PasswordHistorySize']
        [int]$value -ge 24
    } -Recommendation "Set to 24 or more passwords remembered"

# 1.1.2 Maximum password age
$testResults += Test-CISControl -ControlID "1.1.2" -Description "Maximum password age" `
    -TestScript {
        $value = $secPolicy['System Access']['MaximumPasswordAge']
        [int]$value -le 365 -and [int]$value -gt 0
    } -Recommendation "Set to 365 or fewer days (but not 0)"

# 1.1.3 Minimum password age
$testResults += Test-CISControl -ControlID "1.1.3" -Description "Minimum password age" `
    -TestScript {
        $value = $secPolicy['System Access']['MinimumPasswordAge']
        [int]$value -ge 1
    } -Recommendation "Set to 1 or more days"

# 1.1.4 Minimum password length
$testResults += Test-CISControl -ControlID "1.1.4" -Description "Minimum password length" `
    -TestScript {
        $value = $secPolicy['System Access']['MinimumPasswordLength']
        [int]$value -ge 14
    } -Recommendation "Set to 14 or more characters"

# 1.1.5 Password complexity
$testResults += Test-CISControl -ControlID "1.1.5" -Description "Password must meet complexity requirements" `
    -TestScript {
        $value = $secPolicy['System Access']['PasswordComplexity']
        [int]$value -eq 1
    } -Recommendation "Set to Enabled"

# 1.1.6 Reversible encryption
$testResults += Test-CISControl -ControlID "1.1.6" -Description "Store passwords using reversible encryption" `
    -TestScript {
        $value = $secPolicy['System Access']['ClearTextPassword']
        [int]$value -eq 0
    } -Recommendation "Set to Disabled"

# ==================================================================
# ACCOUNT LOCKOUT POLICY (CIS Section 1.2)
# ==================================================================
Write-Host "[*] Testing Account Lockout Policies..." -ForegroundColor Cyan

# 1.2.1 Account lockout duration
$testResults += Test-CISControl -ControlID "1.2.1" -Description "Account lockout duration" `
    -TestScript {
        $value = $secPolicy['System Access']['LockoutDuration']
        [int]$value -ge 15
    } -Recommendation "Set to 15 or more minutes"

# 1.2.2 Account lockout threshold
$testResults += Test-CISControl -ControlID "1.2.2" -Description "Account lockout threshold" `
    -TestScript {
        $value = $secPolicy['System Access']['LockoutBadCount']
        [int]$value -le 5 -and [int]$value -gt 0
    } -Recommendation "Set to 5 or fewer invalid logon attempts (but not 0)"

# 1.2.3 Reset account lockout counter
$testResults += Test-CISControl -ControlID "1.2.3" -Description "Reset account lockout counter after" `
    -TestScript {
        $value = $secPolicy['System Access']['ResetLockoutCount']
        [int]$value -ge 15
    } -Recommendation "Set to 15 or more minutes"

# ==================================================================
# AUDIT POLICIES (CIS Section 17.1-17.9)
# ==================================================================
Write-Host "[*] Testing Audit Policies..." -ForegroundColor Cyan

# Helper to check audit policy
function Test-AuditPolicy {
    param([string]$Category, [string]$Subcategory, [string]$Expected)

    if ($auditOutput) {
        $auditLine = $auditOutput | Where-Object { $_ -match $Subcategory }
        if ($auditLine -and $auditLine -match $Expected) {
            return $true
        }
    }
    return $false
}

# 17.1.1 Audit Credential Validation
$testResults += Test-CISControl -ControlID "17.1.1" -Description "Audit Credential Validation" `
    -TestScript {
        Test-AuditPolicy -Subcategory "Credential Validation" -Expected "Success and Failure"
    } -Recommendation "Set to 'Success and Failure'"

# 17.2.1 Audit Application Group Management
$testResults += Test-CISControl -ControlID "17.2.1" -Description "Audit Application Group Management" `
    -TestScript {
        Test-AuditPolicy -Subcategory "Application Group Management" -Expected "Success and Failure"
    } -Recommendation "Set to 'Success and Failure'" -RequiredLevel 2

# 17.3.1 Audit Process Creation
$testResults += Test-CISControl -ControlID "17.3.1" -Description "Audit Process Creation" `
    -TestScript {
        Test-AuditPolicy -Subcategory "Process Creation" -Expected "Success"
    } -Recommendation "Set to 'Success'"

# 17.5.1 Audit Account Lockout
$testResults += Test-CISControl -ControlID "17.5.1" -Description "Audit Account Lockout" `
    -TestScript {
        Test-AuditPolicy -Subcategory "Account Lockout" -Expected "Failure"
    } -Recommendation "Set to 'Failure'"

# 17.5.2 Audit Logoff
$testResults += Test-CISControl -ControlID "17.5.2" -Description "Audit Logoff" `
    -TestScript {
        Test-AuditPolicy -Subcategory "Logoff" -Expected "Success"
    } -Recommendation "Set to 'Success'"

# 17.5.3 Audit Logon
$testResults += Test-CISControl -ControlID "17.5.3" -Description "Audit Logon" `
    -TestScript {
        Test-AuditPolicy -Subcategory "Logon" -Expected "Success and Failure"
    } -Recommendation "Set to 'Success and Failure'"

# 17.6.1 Audit Sensitive Privilege Use
$testResults += Test-CISControl -ControlID "17.6.1" -Description "Audit Sensitive Privilege Use" `
    -TestScript {
        Test-AuditPolicy -Subcategory "Sensitive Privilege Use" -Expected "Success and Failure"
    } -Recommendation "Set to 'Success and Failure'" -RequiredLevel 2

# 17.9.1 Audit Security System Extension
$testResults += Test-CISControl -ControlID "17.9.1" -Description "Audit Security System Extension" `
    -TestScript {
        Test-AuditPolicy -Subcategory "Security System Extension" -Expected "Success"
    } -Recommendation "Set to 'Success'"

# Filter out null results (controls not applicable to current level)
$testResults = $testResults | Where-Object { $null -ne $_ }

# Calculate statistics
foreach ($result in $testResults) {
    switch ($result.Status) {
        "Pass" { $passed++ }
        "Fail" { $failed++ }
        "Error" { $errors++ }
    }
}

# Display individual results
Write-Host "`n=== Test Results ===" -ForegroundColor Cyan
foreach ($result in $testResults) {
    $color = switch ($result.Status) {
        "Pass" { "Green" }
        "Fail" { "Red" }
        "Error" { "Yellow" }
    }

    $statusSymbol = switch ($result.Status) {
        "Pass" { "[+]" }
        "Fail" { "[!]" }
        "Error" { "[?]" }
    }

    Write-Host "$statusSymbol $($result.ControlID): $($result.Description) - " -NoNewline
    Write-Host $result.Status -ForegroundColor $color

    if ($result.Status -ne "Pass") {
        Write-Host "    Recommendation: $($result.Recommendation)" -ForegroundColor Gray
    }
}

# Display summary
$total = $testResults.Count
$compliancePercent = if ($total -gt 0) { [math]::Round(($passed / $total) * 100, 1) } else { 0 }

Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host "   CIS Compliance Summary" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "Level Tested:        $Level" -ForegroundColor White
Write-Host "Total Controls:      $total" -ForegroundColor White
Write-Host "Passed:              $passed" -ForegroundColor Green
Write-Host "Failed:              $failed" -ForegroundColor Red
Write-Host "Errors:              $errors" -ForegroundColor Yellow
Write-Host "Compliance Rate:     $compliancePercent%" -ForegroundColor $(if ($compliancePercent -ge 80) {"Green"} elseif ($compliancePercent -ge 60) {"Yellow"} else {"Red"})
Write-Host "==================================================================`n" -ForegroundColor Cyan

# Export HTML report if requested
if ($ExportHTML) {
    $htmlFile = Join-Path $OutputPath "CIS-Benchmark-Report_Level$($Level)_$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>CIS Benchmark Compliance Report - Level $Level</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); max-width: 1200px; margin: 0 auto; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 15px; }
        .summary { background: #e7f3ff; padding: 20px; border-radius: 5px; margin: 20px 0; border-left: 4px solid #0078d4; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-top: 15px; }
        .summary-item { background: white; padding: 15px; border-radius: 5px; text-align: center; }
        .summary-item .value { font-size: 28px; font-weight: bold; }
        .summary-item .label { font-size: 12px; color: #666; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .pass { color: #107c10; font-weight: bold; }
        .fail { color: #d13438; font-weight: bold; }
        .error { color: #ff8c00; font-weight: bold; }
        .footer { margin-top: 30px; padding-top: 15px; border-top: 1px solid #ddd; color: #666; font-size: 12px; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h1>CIS Microsoft Windows Server Benchmark Report</h1>
        <div class="summary">
            <strong>System:</strong> $env:COMPUTERNAME<br>
            <strong>Level:</strong> $Level<br>
            <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

            <div class="summary-grid">
                <div class="summary-item">
                    <div class="value">$total</div>
                    <div class="label">Total Controls</div>
                </div>
                <div class="summary-item">
                    <div class="value" style="color: #107c10;">$passed</div>
                    <div class="label">Passed</div>
                </div>
                <div class="summary-item">
                    <div class="value" style="color: #d13438;">$failed</div>
                    <div class="label">Failed</div>
                </div>
                <div class="summary-item">
                    <div class="value" style="color: #ff8c00;">$errors</div>
                    <div class="label">Errors</div>
                </div>
                <div class="summary-item">
                    <div class="value">$compliancePercent%</div>
                    <div class="label">Compliance</div>
                </div>
            </div>
        </div>

        <h2>Test Results</h2>
        <table>
            <tr>
                <th>Control ID</th>
                <th>Description</th>
                <th>Status</th>
                <th>Recommendation</th>
            </tr>
"@

    foreach ($result in $testResults | Sort-Object ControlID) {
        $statusClass = $result.Status.ToLower()
        $html += @"
            <tr>
                <td>$($result.ControlID)</td>
                <td>$($result.Description)</td>
                <td class="$statusClass">$($result.Status)</td>
                <td>$($result.Recommendation)</td>
            </tr>
"@
    }

    $html += @"
        </table>

        <div class="footer">
            <strong>CIS Microsoft Windows Server 2019/2022 Benchmark v2.0.0</strong><br>
            Generated by Test-CISBenchmark.ps1 | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        </div>
    </div>
</body>
</html>
"@

    try {
        $html | Out-File -FilePath $htmlFile -Encoding UTF8 -ErrorAction Stop
        Write-Host "HTML report saved to: $htmlFile" -ForegroundColor Green

        # Open report in browser
        if (Test-Path $htmlFile) {
            Start-Process $htmlFile
        }
    }
    catch {
        Write-Warning "Failed to save HTML report: $($_.Exception.Message)"
    }
}

Write-Host "Compliance test complete!`n" -ForegroundColor Green

# Exit with appropriate code
if ($failed -gt 0) {
    exit 1
} else {
    exit 0
}
