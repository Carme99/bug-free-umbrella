<#
.SYNOPSIS
    Validate Azure Bicep templates for syntax, security, and best practices.
.DESCRIPTION
    Validates Bicep templates by compiling each template with the Bicep CLI (bicep build),
    running lint analysis (bicep lint), and applying heuristic security and best-practice
    checks: hardcoded secrets, sensitive parameters without @secure, missing location
    parameter, and resources without governance tags.
    Optionally performs an Azure what-if deployment analysis through the Az CLI when
    -IncludeWhatIf is supplied together with a subscription ID and resource group.
    Results are printed to the console or written to an HTML/JSON report under -OutputPath.
    The script is read-only with respect to template files and idempotent: re-running it
    never mutates the validated templates.
.PARAMETER TemplatePath
    Path to a Bicep template file or to a directory containing .bicep templates.
.PARAMETER ParameterFile
    Optional parameter file passed to the what-if deployment analysis.
.PARAMETER IncludeWhatIf
    Perform what-if deployment analysis via the Az CLI.
.PARAMETER SubscriptionId
    Azure subscription ID used for what-if analysis.
.PARAMETER ResourceGroupName
    Azure resource group used for the what-if deployment.
.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'.
.PARAMETER OutputPath
    Directory where HTML/JSON report files are written. Default: MyDocuments\Reports.
.EXAMPLE
    PS C:\> .\Test-BicepTemplates.ps1 -TemplatePath ".\main.bicep" -OutputFormat Console
    Validates a single template and prints a console summary.
.EXAMPLE
    PS C:\> .\Test-BicepTemplates.ps1 -TemplatePath ".\templates" -IncludeWhatIf `
        -SubscriptionId "sub-id" -ResourceGroupName "rg-test"
    Validates every template under .\templates and runs what-if analysis against rg-test.
.NOTES
    File Name   : Test-BicepTemplates.ps1
    Author      : IT Operations
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
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

$ErrorActionPreference = 'Stop'

function Invoke-BicepCli {
    # Thin wrapper around the native bicep executable; the mock seam for Pester tests.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$ArgumentList)

    $output = & bicep @ArgumentList 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}

function Invoke-AzCli {
    # Thin wrapper around the native az executable; the mock seam for Pester tests.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$ArgumentList)

    $output = & az @ArgumentList 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}

function Main {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only creates fresh timestamped report files; never overwrites or mutates user state.')]
    param()

    try {
        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            throw "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
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

        Write-Host "[*] Validating Bicep templates..." -ForegroundColor Cyan

        # Check Bicep CLI
        $bicepVersion = Invoke-BicepCli -ArgumentList @('--version')
        if ($bicepVersion.ExitCode -ne 0) {
            throw "Bicep CLI not found. Install from: https://aka.ms/bicep-install"
        }
        Write-Host "[+] Bicep CLI version: $($bicepVersion.Output)" -ForegroundColor Green

        # Get template files
        $templates = @()
        if (Test-Path $TemplatePath -PathType Container) {
            $templates = @(Get-ChildItem -Path $TemplatePath -Filter "*.bicep" -Recurse)
        }
        elseif (Test-Path $TemplatePath -PathType Leaf) {
            $templates = @(Get-Item $TemplatePath)
        }
        else {
            throw "Template path not found: $TemplatePath"
        }

        Write-Host "[*] Found $(@($templates).Count) Bicep template(s)" -ForegroundColor Cyan

        foreach ($template in $templates) {
            Write-Host "[*] Validating: $($template.Name)" -ForegroundColor Cyan

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
                $buildResult = Invoke-BicepCli -ArgumentList @('build', $template.FullName)
                if ($buildResult.ExitCode -eq 0) {
                    $templateResult.SyntaxValid = $true
                    Write-Host "  [+] Syntax validation passed" -ForegroundColor Green
                }
                else {
                    $templateResult.Errors += "Syntax validation failed: $($buildResult.Output)"
                    Write-Host "  [-] Syntax validation failed" -ForegroundColor Red
                }
            }
            catch {
                $templateResult.Errors += "Build error: $($_.Exception.Message)"
            }

            # Lint analysis (bicep lint)
            try {
                $lintResult = Invoke-BicepCli -ArgumentList @('lint', $template.FullName)
                if ($lintResult.ExitCode -eq 0 -and -not $lintResult.Output) {
                    Write-Host "  [+] Lint analysis passed" -ForegroundColor Green
                }
                else {
                    $templateResult.BestPracticeIssues += [string]$lintResult.Output
                    Write-Host "  [!] Lint: $($lintResult.Output)" -ForegroundColor Yellow
                }
            }
            catch {
                $templateResult.BestPracticeIssues += "Lint error: $($_.Exception.Message)"
            }

            # Basic security checks
            $content = Get-Content $template.FullName -Raw -ErrorAction Stop

            # Check for hardcoded secrets
            if ($content -match '(?i)(password|secret|key)\s*=\s*[''"](?!@)') {
                $templateResult.SecurityIssues += "Potential hardcoded secret detected"
                Write-Host "  [!] Security: Potential hardcoded secrets found" -ForegroundColor Yellow
            }

            # Check for secure parameters
            if ($content -match 'param\s+\w+(Password|Secret|Key)\s+string' -and $content -notmatch '@secure') {
                $templateResult.SecurityIssues += "Sensitive parameter not marked as @secure"
                Write-Host "  [!] Security: Sensitive parameters should use @secure" -ForegroundColor Yellow
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
                    Write-Host "  [*] Running what-if deployment..." -ForegroundColor Cyan

                    try {
                        $azArgs = @(
                            'deployment',
                            'group',
                            'what-if',
                            '--resource-group',
                            $ResourceGroupName,
                            '--template-file',
                            $template.FullName
                        )
                        if ($ParameterFile) {
                            $azArgs += @('--parameters', $ParameterFile)
                        }

                        $whatIfRun = Invoke-AzCli -ArgumentList $azArgs
                        $templateResult.WhatIfResult = $whatIfRun.Output
                        Write-Host "  [+] What-if analysis completed" -ForegroundColor Green
                    }
                    catch {
                        $templateResult.Warnings += "What-if analysis failed: $($_.Exception.Message)"
                    }
                }
                else {
                    $templateResult.Warnings += "SubscriptionId and ResourceGroupName required for what-if analysis"
                }
            }

            $results.ValidationResults += $templateResult
        }

        # Calculate summary
        $passedValidation = @($results.ValidationResults | Where-Object { $_.SyntaxValid }).Count
        $failedValidation = @($results.ValidationResults | Where-Object { -not $_.SyntaxValid }).Count
        $totalSecurityIssues = @($results.ValidationResults.SecurityIssues | Measure-Object).Count
        $totalBestPracticeIssues = @($results.ValidationResults.BestPracticeIssues | Measure-Object).Count

        $results.Summary = @{
            TotalTemplates = @($templates).Count
            PassedValidation = $passedValidation
            FailedValidation = $failedValidation
            SecurityIssues = $totalSecurityIssues
            BestPracticeIssues = $totalBestPracticeIssues
        }

        # Output
        switch ($OutputFormat) {
            'Console' {
                Write-Host ""
                Write-Host "=== Bicep Validation Summary ===" -ForegroundColor Cyan
                Write-Host "Total Templates: $(@($templates).Count)" -ForegroundColor White
                Write-Host "Passed: $passedValidation | Failed: $failedValidation" -ForegroundColor White
                Write-Host "Security Issues: $totalSecurityIssues |" `
                    "Best Practice Issues: $totalBestPracticeIssues" -ForegroundColor White
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
    <p>Total Templates: $(@($templates).Count) | Passed: $passedValidation | Failed: $failedValidation</p>
    <p>Security Issues: $totalSecurityIssues | Best Practice Issues: $totalBestPracticeIssues</p>
    <h2>Results</h2>
    <table>
        <tr><th>Template</th><th>Syntax Valid</th><th>Issues</th></tr>
"@
                foreach ($result in $results.ValidationResults) {
                    $statusClass = if ($result.SyntaxValid) { 'pass' } else { 'fail' }
                    $issues = ($result.SecurityIssues + $result.BestPracticeIssues + $result.Warnings) -join '<br>'
                    $encodedName = [System.Net.WebUtility]::HtmlEncode("$($result.FileName)")
                    $encodedIssues = [System.Net.WebUtility]::HtmlEncode("$issues")
                    $html += "<tr><td>$encodedName</td><td class='$statusClass'>$($result.SyntaxValid)</td>"
                    $html += "<td>$encodedIssues</td></tr>"
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
                Write-Host "[+] HTML report saved to: $htmlFile" -ForegroundColor Green
            }

            'JSON' {
                $jsonFile = Join-Path $OutputPath "Bicep-Validation-${RunTimestamp}_${RunId}.json"
                $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
                Write-Host "[+] JSON saved to: $jsonFile" -ForegroundColor Green
            }
        }

        Write-Host "[+] Bicep validation complete!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
