<#
.SYNOPSIS
    Validates and tests Azure Bicep templates for best practices and security.

.DESCRIPTION
    Bicep template validation script that performs:
    - Syntax validation and compilation checks (bicep build)
    - Lint analysis (bicep lint)
    - Heuristic security checks (hardcoded secrets, sensitive parameters without @secure)
    - Basic best-practice checks (location parameter, resource tags)
    - Optional what-if deployment analysis (az deployment group what-if)

.PARAMETER TemplatePath
    Path to Bicep template file or directory containing templates

.PARAMETER ParameterFile
    Optional parameter file for deployment validation

.PARAMETER IncludeWhatIf
    Perform what-if deployment analysis

.PARAMETER SubscriptionId
    Azure subscription ID for what-if analysis

.PARAMETER ResourceGroupName
    Resource group for what-if deployment

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for HTML/JSON output file. Default: MyDocuments\Reports

.EXAMPLE
    .\Test-BicepTemplates.ps1 -TemplatePath ".\main.bicep"

.EXAMPLE
    .\Test-BicepTemplates.ps1 -TemplatePath ".\templates" `
        -IncludeWhatIf `
        -SubscriptionId "sub-id" `
        -ResourceGroupName "rg-test"

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 7.0+, Azure CLI, Bicep CLI

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TemplatePath,

    [Parameter(Mandatory = $false)]
    [string]$ParameterFile,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeWhatIf,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)

# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

$results = @{
    Timestamp = Get-Date
    TemplatePath = $TemplatePath
    ValidationResults = @()
    Summary = @{}
}

Write-Host "Validating Bicep templates..." -ForegroundColor Cyan

# Check Bicep CLI
try {
    $bicepVersion = bicep --version
    Write-Host "Bicep CLI version: $bicepVersion" -ForegroundColor Green
} catch {
    Write-Error "Bicep CLI not found. Install from: https://aka.ms/bicep-install"
    exit 1
}

# Get template files
$templates = @()
if (Test-Path $TemplatePath -PathType Container) {
    $templates = Get-ChildItem -Path $TemplatePath -Filter "*.bicep" -Recurse
} elseif (Test-Path $TemplatePath -PathType Leaf) {
    $templates = @(Get-Item $TemplatePath)
} else {
    Write-Error "Template path not found: $TemplatePath"
    exit 1
}

Write-Host "Found $($templates.Count) Bicep template(s)" -ForegroundColor Yellow

foreach ($template in $templates) {
    Write-Host "`nValidating: $($template.Name)" -ForegroundColor Cyan

    $templateResult = @{
        FileName = $template.Name
        FullPath = $template.FullName
        SyntaxValid = $false
        BestPracticeIssues = @()
        SecurityIssues = @()
        Warnings = @()
        Errors = @()
    }

    # Syntax validation
    try {
        $buildOutput = bicep build $template.FullName 2>&1
        if ($LASTEXITCODE -eq 0) {
            $templateResult.SyntaxValid = $true
            Write-Host "  ✓ Syntax validation passed" -ForegroundColor Green
        } else {
            $templateResult.Errors += "Syntax validation failed: $buildOutput"
            Write-Host "  ✗ Syntax validation failed" -ForegroundColor Red
        }
    } catch {
        $templateResult.Errors += "Build error: $($_.Exception.Message)"
    }

    # Lint analysis (bicep lint)
    try {
        $lintOutput = bicep lint $template.FullName 2>&1
        if ($LASTEXITCODE -eq 0 -and -not $lintOutput) {
            Write-Host "  ✓ Lint analysis passed" -ForegroundColor Green
        } else {
            $templateResult.BestPracticeIssues += [string]$lintOutput
            Write-Host "  ⚠ Lint: $lintOutput" -ForegroundColor Yellow
        }
    } catch {
        $templateResult.BestPracticeIssues += "Lint error: $($_.Exception.Message)"
    }

    # Basic security checks
    $content = Get-Content $template.FullName -Raw

    # Check for hardcoded secrets
    if ($content -match '(?i)(password|secret|key)\s*=\s*[''"](?!@)') {
        $templateResult.SecurityIssues += "Potential hardcoded secret detected"
        Write-Host "  ⚠ Security: Potential hardcoded secrets found" -ForegroundColor Yellow
    }

    # Check for secure parameters
    if ($content -match 'param\s+\w+(Password|Secret|Key)\s+string' -and $content -notmatch '@secure') {
        $templateResult.SecurityIssues += "Sensitive parameter not marked as @secure"
        Write-Host "  ⚠ Security: Sensitive parameters should use @secure" -ForegroundColor Yellow
    }

    # Check naming conventions
    if ($content -notmatch "param\s+location\s+string") {
        $templateResult.Warnings += "Missing location parameter (best practice)"
    }

    # Check for resource tags
    if ($content -match "resource\s+" -and $content -notmatch "tags:") {
        $templateResult.BestPracticeIssues += "Resources should include tags for governance"
    }

    # What-if analysis
    if ($IncludeWhatIf -and $templateResult.SyntaxValid) {
        if ($SubscriptionId -and $ResourceGroupName) {
            Write-Host "  Running what-if deployment..." -ForegroundColor Gray

            try {
                $whatIfCmd = "az deployment group what-if --resource-group $ResourceGroupName --template-file `"$($template.FullName)`""
                if ($ParameterFile) {
                    $whatIfCmd += " --parameters `"$ParameterFile`""
                }

                $whatIfResult = Invoke-Expression $whatIfCmd 2>&1
                $templateResult.WhatIfResult = $whatIfResult
                Write-Host "  ✓ What-if analysis completed" -ForegroundColor Green
            } catch {
                $templateResult.Warnings += "What-if analysis failed: $($_.Exception.Message)"
            }
        } else {
            $templateResult.Warnings += "SubscriptionId and ResourceGroupName required for what-if analysis"
        }
    }

    $results.ValidationResults += $templateResult
}

# Calculate summary
$passedValidation = ($results.ValidationResults | Where-Object { $_.SyntaxValid }).Count
$failedValidation = ($results.ValidationResults | Where-Object { -not $_.SyntaxValid }).Count
$totalSecurityIssues = ($results.ValidationResults.SecurityIssues | Measure-Object).Count
$totalBestPracticeIssues = ($results.ValidationResults.BestPracticeIssues | Measure-Object).Count

$results.Summary = @{
    TotalTemplates = $templates.Count
    PassedValidation = $passedValidation
    FailedValidation = $failedValidation
    SecurityIssues = $totalSecurityIssues
    BestPracticeIssues = $totalBestPracticeIssues
}

# Output
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Bicep Validation Summary ===" -ForegroundColor Cyan
        Write-Host "Total Templates: $($templates.Count)" -ForegroundColor White
        Write-Host "Passed: $passedValidation | Failed: $failedValidation" -ForegroundColor White
        Write-Host "Security Issues: $totalSecurityIssues | Best Practice Issues: $totalBestPracticeIssues" -ForegroundColor White
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "Bicep-Validation-${RunTimestamp}_${RunId}.html"
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Bicep Template Validation Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; }
        table { border-collapse: collapse; width: 100%; background: white; }
        th { background-color: #0078d4; color: white; padding: 10px; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        .pass { color: #107c10; }
        .fail { color: #d13438; }
        .warning { color: #ff8c00; }
    </style>
</head>
<body>
    <h1>Bicep Template Validation Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Run ID:</strong> $RunId</p>
    <h2>Summary</h2>
    <p>Total Templates: $($templates.Count) | Passed: $passedValidation | Failed: $failedValidation</p>
    <p>Security Issues: $totalSecurityIssues | Best Practice Issues: $totalBestPracticeIssues</p>
    <h2>Results</h2>
    <table>
        <tr><th>Template</th><th>Syntax Valid</th><th>Issues</th></tr>
"@
        foreach ($result in $results.ValidationResults) {
            $statusClass = if ($result.SyntaxValid) { 'pass' } else { 'fail' }
            $issues = ($result.SecurityIssues + $result.BestPracticeIssues + $result.Warnings) -join '<br>'
            $html += "<tr><td>$([System.Net.WebUtility]::HtmlEncode("$($result.FileName)"))</td><td class='$statusClass'>$($result.SyntaxValid)</td><td>$([System.Net.WebUtility]::HtmlEncode("$issues"))</td></tr>"
        }
        $html += @"
    </table>
    <p style="margin-top: 30px; text-align: center; color: #666; font-size: 12px;">
        <strong>Note:</strong> This report has not been thoroughly tested. Please validate before deployment.
    </p>
</body>
</html>
"@
        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "Bicep-Validation-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nBicep validation complete!" -ForegroundColor Green
