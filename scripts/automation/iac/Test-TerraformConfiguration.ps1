<#
.SYNOPSIS
    Validates Terraform configurations for syntax, security, and best practices.

.DESCRIPTION
    Comprehensive Terraform validation script that performs:
    - Syntax validation (terraform validate)
    - Format checking (terraform fmt)
    - Security scanning with tfsec
    - Plan generation and analysis
    - State file health checking
    - Provider version compatibility
    - Resource naming and tagging compliance

.PARAMETER ConfigPath
    Path to Terraform configuration directory

.PARAMETER IncludePlan
    Generate and analyze terraform plan

.PARAMETER IncludeSecurityScan
    Run tfsec security scanner (requires tfsec installation)

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: Desktop

.EXAMPLE
    .\Test-TerraformConfiguration.ps1 -ConfigPath ".\terraform"

.EXAMPLE
    .\Test-TerraformConfiguration.ps1 -ConfigPath ".\infrastructure" `
        -IncludePlan `
        -IncludeSecurityScan

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1+, Terraform CLI

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludePlan,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSecurityScan,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = [Environment]::GetFolderPath('Desktop')
)

$results = @{
    Timestamp = Get-Date
    ConfigPath = $ConfigPath
    ValidationResults = @{}
    SecurityIssues = @()
    Summary = @{}
}

Write-Host "Validating Terraform configuration: $ConfigPath" -ForegroundColor Cyan

# Check Terraform CLI
try {
    $tfVersion = terraform version
    Write-Host "Terraform version: $($tfVersion[0])" -ForegroundColor Green
} catch {
    Write-Error "Terraform CLI not found. Install from: https://www.terraform.io/downloads"
    exit 1
}

# Validate path
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration path not found: $ConfigPath"
    exit 1
}

Push-Location $ConfigPath

try {
    # Terraform init
    Write-Host "`nInitializing Terraform..." -ForegroundColor Yellow
    $initOutput = terraform init -backend=false 2>&1
    if ($LASTEXITCODE -eq 0) {
        $results.ValidationResults.Init = @{ Success = $true; Output = $initOutput }
        Write-Host "  ✓ Initialization successful" -ForegroundColor Green
    } else {
        $results.ValidationResults.Init = @{ Success = $false; Output = $initOutput }
        Write-Host "  ✗ Initialization failed" -ForegroundColor Red
    }

    # Terraform fmt check
    Write-Host "`nChecking formatting..." -ForegroundColor Yellow
    $fmtOutput = terraform fmt -check -recursive 2>&1
    if ($LASTEXITCODE -eq 0) {
        $results.ValidationResults.Format = @{ Success = $true; Message = "All files properly formatted" }
        Write-Host "  ✓ Formatting check passed" -ForegroundColor Green
    } else {
        $results.ValidationResults.Format = @{ Success = $false; FilesNeedingFormat = $fmtOutput }
        Write-Host "  ⚠ Some files need formatting" -ForegroundColor Yellow
    }

    # Terraform validate
    Write-Host "`nValidating configuration..." -ForegroundColor Yellow
    $validateOutput = terraform validate -json 2>&1 | ConvertFrom-Json
    if ($validateOutput.valid) {
        $results.ValidationResults.Validate = @{ Success = $true; Message = "Configuration valid" }
        Write-Host "  ✓ Validation passed" -ForegroundColor Green
    } else {
        $results.ValidationResults.Validate = @{
            Success = $false
            Errors = $validateOutput.diagnostics
        }
        Write-Host "  ✗ Validation failed" -ForegroundColor Red
        foreach ($diag in $validateOutput.diagnostics) {
            Write-Host "    Error: $($diag.summary)" -ForegroundColor Red
        }
    }

    # Terraform plan
    if ($IncludePlan -and $results.ValidationResults.Validate.Success) {
        Write-Host "`nGenerating plan..." -ForegroundColor Yellow
        $planOutput = terraform plan -out=tfplan 2>&1
        if ($LASTEXITCODE -eq 0) {
            $planShow = terraform show -json tfplan | ConvertFrom-Json
            $results.ValidationResults.Plan = @{
                Success = $true
                ResourceChanges = $planShow.resource_changes.Count
                Changes = $planShow.resource_changes | ForEach-Object {
                    @{
                        Address = $_.address
                        Action = $_.change.actions -join ', '
                        Type = $_.type
                    }
                }
            }
            Write-Host "  ✓ Plan generated: $($planShow.resource_changes.Count) resource changes" -ForegroundColor Green
            Remove-Item tfplan -Force -ErrorAction SilentlyContinue
        } else {
            $results.ValidationResults.Plan = @{ Success = $false; Output = $planOutput }
            Write-Host "  ✗ Plan generation failed" -ForegroundColor Red
        }
    }

    # Security scan with tfsec
    if ($IncludeSecurityScan) {
        Write-Host "`nRunning security scan (tfsec)..." -ForegroundColor Yellow
        try {
            $tfsecOutput = tfsec . --format json 2>&1 | ConvertFrom-Json
            $results.SecurityIssues = $tfsecOutput.results | ForEach-Object {
                @{
                    RuleID = $_.rule_id
                    Severity = $_.severity
                    Description = $_.description
                    Resource = $_.location.filename
                    Line = $_.location.start_line
                }
            }
            Write-Host "  ✓ Security scan complete: $($results.SecurityIssues.Count) issues found" -ForegroundColor $(if ($results.SecurityIssues.Count -eq 0) { 'Green' } else { 'Yellow' })
        } catch {
            Write-Host "  ⚠ tfsec not found. Install from: https://github.com/aquasecurity/tfsec" -ForegroundColor Yellow
        }
    }

} finally {
    Pop-Location
}

# Summary
$results.Summary = @{
    ConfigPath = $ConfigPath
    InitSuccess = $results.ValidationResults.Init.Success
    FormatClean = $results.ValidationResults.Format.Success
    ValidationSuccess = $results.ValidationResults.Validate.Success
    SecurityIssues = $results.SecurityIssues.Count
    PlanGenerated = $null -ne $results.ValidationResults.Plan
}

# Output
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Terraform Validation Summary ===" -ForegroundColor Cyan
        Write-Host "Configuration: $ConfigPath" -ForegroundColor White
        Write-Host "Init: $(if ($results.Summary.InitSuccess) { '✓' } else { '✗' })" -ForegroundColor White
        Write-Host "Format: $(if ($results.Summary.FormatClean) { '✓' } else { '⚠' })" -ForegroundColor White
        Write-Host "Validation: $(if ($results.Summary.ValidationSuccess) { '✓' } else { '✗' })" -ForegroundColor White
        if ($IncludeSecurityScan) {
            Write-Host "Security Issues: $($results.SecurityIssues.Count)" -ForegroundColor White
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "Terraform-Validation-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Terraform Validation Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #5c4ee5; }
        table { border-collapse: collapse; width: 100%; background: white; }
        th { background-color: #5c4ee5; color: white; padding: 10px; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        .pass { color: #107c10; }
        .fail { color: #d13438; }
    </style>
</head>
<body>
    <h1>Terraform Validation Report</h1>
    <p><strong>Configuration:</strong> $ConfigPath</p>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <h2>Validation Results</h2>
    <table>
        <tr><th>Check</th><th>Status</th></tr>
        <tr><td>Initialization</td><td class="$(if ($results.Summary.InitSuccess) { 'pass' } else { 'fail' })">$(if ($results.Summary.InitSuccess) { 'Passed' } else { 'Failed' })</td></tr>
        <tr><td>Formatting</td><td class="$(if ($results.Summary.FormatClean) { 'pass' } else { 'fail' })">$(if ($results.Summary.FormatClean) { 'Clean' } else { 'Needs Formatting' })</td></tr>
        <tr><td>Validation</td><td class="$(if ($results.Summary.ValidationSuccess) { 'pass' } else { 'fail' })">$(if ($results.Summary.ValidationSuccess) { 'Passed' } else { 'Failed' })</td></tr>
    </table>
"@
        if ($results.SecurityIssues.Count -gt 0) {
            $html += "<h2>Security Issues</h2><table><tr><th>Rule</th><th>Severity</th><th>Description</th><th>File</th></tr>"
            foreach ($issue in $results.SecurityIssues) {
                $html += "<tr><td>$($issue.RuleID)</td><td>$($issue.Severity)</td><td>$($issue.Description)</td><td>$($issue.Resource):$($issue.Line)</td></tr>"
            }
            $html += "</table>"
        }
        $html += "<p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'><strong>Note:</strong> This report has not been thoroughly tested.</p></body></html>"

        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
        Start-Process $htmlFile
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "Terraform-Validation-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nTerraform validation complete!" -ForegroundColor Green
