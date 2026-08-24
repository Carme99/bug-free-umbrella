<#
.SYNOPSIS
    Validate Terraform configurations for syntax, security, and best practices.
.DESCRIPTION
    Performs a comprehensive Terraform validation: CLI availability check, terraform init,
    format checking (terraform fmt -check), configuration validation (terraform validate),
    optional plan generation and analysis, and an optional tfsec security scan.
    Results are printed to the console or written to an HTML/JSON report under -OutputPath.
    The script is read-only with respect to the validated configuration (the transient plan
    file is deleted after analysis) and idempotent: re-running it never mutates the
    configuration files.
.PARAMETER ConfigPath
    Path to the Terraform configuration directory.
.PARAMETER IncludePlan
    Generate and analyze a terraform plan after successful validation.
.PARAMETER IncludeSecurityScan
    Run the tfsec security scanner (requires tfsec installation).
.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'.
.PARAMETER OutputPath
    Directory where HTML/JSON report files are written. Default: MyDocuments\Reports.
.EXAMPLE
    PS C:\> .\Test-TerraformConfiguration.ps1 -ConfigPath ".\terraform" -OutputFormat Console
    Validates the configuration in .\terraform and prints a console summary.
.EXAMPLE
    PS C:\> .\Test-TerraformConfiguration.ps1 -ConfigPath ".\infrastructure" `
        -IncludePlan -IncludeSecurityScan
    Validates the configuration, generates a plan, and runs a tfsec security scan.
.NOTES
    File Name   : Test-TerraformConfiguration.ps1
    Author      : IT Operations
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludePlan,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSecurityScan,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)

$ErrorActionPreference = 'Stop'

function Invoke-TerraformCli {
    # Thin wrapper around the native terraform executable; the mock seam for Pester tests.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$ArgumentList)

    $output = & terraform @ArgumentList 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}

function Invoke-TfsecCli {
    # Thin wrapper around the native tfsec executable; the mock seam for Pester tests.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$ArgumentList)

    $output = & tfsec @ArgumentList 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}

function Main {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only creates fresh timestamped report files and removes its own transient tfplan artifact.')]
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
            ConfigPath = $ConfigPath
            ValidationResults = @{}
            SecurityIssues = @()
            Summary = @{}
        }

        Write-Host "[*] Validating Terraform configuration: $ConfigPath" -ForegroundColor Cyan

        # Check Terraform CLI
        $tfVersionRun = Invoke-TerraformCli -ArgumentList @('version')
        if ($tfVersionRun.ExitCode -ne 0) {
            throw "Terraform CLI not found. Install from: https://www.terraform.io/downloads"
        }
        Write-Host "[+] Terraform version: $($tfVersionRun.Output[0])" -ForegroundColor Green

        # Validate path
        if (-not (Test-Path $ConfigPath)) {
            throw "Configuration path not found: $ConfigPath"
        }

        Push-Location $ConfigPath

        try {
            # Terraform init
            Write-Host "[*] Initializing Terraform..." -ForegroundColor Cyan
            $initRun = Invoke-TerraformCli -ArgumentList @('init', '-backend=false')
            if ($initRun.ExitCode -eq 0) {
                $results.ValidationResults.Init = @{ Success = $true; Output = $initRun.Output }
                Write-Host "  [+] Initialization successful" -ForegroundColor Green
            }
            else {
                $results.ValidationResults.Init = @{ Success = $false; Output = $initRun.Output }
                Write-Host "  [-] Initialization failed" -ForegroundColor Red
            }

            # Terraform fmt check
            Write-Host "[*] Checking formatting..." -ForegroundColor Cyan
            $fmtRun = Invoke-TerraformCli -ArgumentList @('fmt', '-check', '-recursive')
            if ($fmtRun.ExitCode -eq 0) {
                $results.ValidationResults.Format = @{ Success = $true; Message = "All files properly formatted" }
                Write-Host "  [+] Formatting check passed" -ForegroundColor Green
            }
            else {
                $results.ValidationResults.Format = @{ Success = $false; FilesNeedingFormat = $fmtRun.Output }
                Write-Host "  [!] Some files need formatting" -ForegroundColor Yellow
            }

            # Terraform validate
            Write-Host "[*] Validating configuration..." -ForegroundColor Cyan
            $validateOutput = (Invoke-TerraformCli -ArgumentList @('validate', '-json')).Output |
                ConvertFrom-Json
            if ($validateOutput.valid) {
                $results.ValidationResults.Validate = @{ Success = $true; Message = "Configuration valid" }
                Write-Host "  [+] Validation passed" -ForegroundColor Green
            }
            else {
                $results.ValidationResults.Validate = @{
                    Success = $false
                    Errors = $validateOutput.diagnostics
                }
                Write-Host "  [-] Validation failed" -ForegroundColor Red
                foreach ($diag in $validateOutput.diagnostics) {
                    Write-Host "    Error: $($diag.summary)" -ForegroundColor Red
                }
            }

            # Terraform plan
            if ($IncludePlan -and $results.ValidationResults.Validate.Success) {
                Write-Host "[*] Generating plan..." -ForegroundColor Cyan
                $planRun = Invoke-TerraformCli -ArgumentList @('plan', '-out=tfplan')
                if ($planRun.ExitCode -eq 0) {
                    $planShow = (Invoke-TerraformCli -ArgumentList @('show', '-json', 'tfplan')).Output |
                        ConvertFrom-Json
                    $results.ValidationResults.Plan = @{
                        Success = $true
                        ResourceChanges = @($planShow.resource_changes).Count
                        Changes = $planShow.resource_changes | ForEach-Object {
                            @{
                                Address = $_.address
                                Action = $_.change.actions -join ', '
                                Type = $_.type
                            }
                        }
                    }
                    $changeCount = @($planShow.resource_changes).Count
                    Write-Host "  [+] Plan generated: $changeCount resource changes" -ForegroundColor Green
                    Remove-Item tfplan -Force -ErrorAction SilentlyContinue
                }
                else {
                    $results.ValidationResults.Plan = @{ Success = $false; Output = $planRun.Output }
                    Write-Host "  [-] Plan generation failed" -ForegroundColor Red
                }
            }

            # Security scan with tfsec
            if ($IncludeSecurityScan) {
                Write-Host "[*] Running security scan (tfsec)..." -ForegroundColor Cyan
                try {
                    $tfsecRun = Invoke-TfsecCli -ArgumentList @('.', '--format', 'json')
                    $tfsecOutput = $tfsecRun.Output | ConvertFrom-Json
                    $results.SecurityIssues = @($tfsecOutput.results | ForEach-Object {
                        @{
                            RuleID = $_.rule_id
                            Severity = $_.severity
                            Description = $_.description
                            Resource = $_.location.filename
                            Line = $_.location.start_line
                        }
                    })
                    $issueColor = if (@($results.SecurityIssues).Count -eq 0) { 'Green' } else { 'Yellow' }
                    $issueCount = @($results.SecurityIssues).Count
                    Write-Host "  [+] Security scan complete: $issueCount issues found" -ForegroundColor $issueColor
                }
                catch {
                    Write-Host "  [!] tfsec not found. Install from:" `
                        "https://github.com/aquasecurity/tfsec" -ForegroundColor Yellow
                }
            }
        }
        finally {
            Pop-Location
        }

        # Summary
        $results.Summary = @{
            ConfigPath = $ConfigPath
            InitSuccess = $results.ValidationResults.Init.Success
            FormatClean = $results.ValidationResults.Format.Success
            ValidationSuccess = $results.ValidationResults.Validate.Success
            SecurityIssues = @($results.SecurityIssues).Count
            PlanGenerated = $null -ne $results.ValidationResults.Plan
        }

        # Output
        switch ($OutputFormat) {
            'Console' {
                Write-Host ""
                Write-Host "=== Terraform Validation Summary ===" -ForegroundColor Cyan
                Write-Host "Configuration: $ConfigPath" -ForegroundColor White
                $initMark = if ($results.Summary.InitSuccess) { '[+]' } else { '[-]' }
                $formatMark = if ($results.Summary.FormatClean) { '[+]' } else { '[!]' }
                $validateMark = if ($results.Summary.ValidationSuccess) { '[+]' } else { '[-]' }
                Write-Host "Init: $initMark" -ForegroundColor White
                Write-Host "Format: $formatMark" -ForegroundColor White
                Write-Host "Validation: $validateMark" -ForegroundColor White
                if ($IncludeSecurityScan) {
                    Write-Host "Security Issues: $(@($results.SecurityIssues).Count)" -ForegroundColor White
                }
            }

            'HTML' {
                $htmlFile = Join-Path $OutputPath "Terraform-Validation-${RunTimestamp}_${RunId}.html"
                $encodedConfigPath = [System.Net.WebUtility]::HtmlEncode("$ConfigPath")
                $initCellClass = if ($results.Summary.InitSuccess) { 'pass' } else { 'fail' }
                $initCellText = if ($results.Summary.InitSuccess) { 'Passed' } else { 'Failed' }
                $formatCellClass = if ($results.Summary.FormatClean) { 'pass' } else { 'fail' }
                $formatCellText = if ($results.Summary.FormatClean) { 'Clean' } else { 'Needs Formatting' }
                $validateCellClass = if ($results.Summary.ValidationSuccess) { 'pass' } else { 'fail' }
                $validateCellText = if ($results.Summary.ValidationSuccess) { 'Passed' } else { 'Failed' }
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
    <p><strong>Configuration:</strong> $encodedConfigPath</p>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Run ID:</strong> $RunId</p>
    <h2>Validation Results</h2>
    <table>
        <tr><th>Check</th><th>Status</th></tr>
        <tr><td>Initialization</td><td class="$initCellClass">$initCellText</td></tr>
        <tr><td>Formatting</td><td class="$formatCellClass">$formatCellText</td></tr>
        <tr><td>Validation</td><td class="$validateCellClass">$validateCellText</td></tr>
    </table>
"@
                if (@($results.SecurityIssues).Count -gt 0) {
                    $html += "<h2>Security Issues</h2>"
                    $html += "<table><tr><th>Rule</th><th>Severity</th><th>Description</th><th>File</th></tr>"
                    foreach ($issue in $results.SecurityIssues) {
                        $encRule = [System.Net.WebUtility]::HtmlEncode("$($issue.RuleID)")
                        $encSeverity = [System.Net.WebUtility]::HtmlEncode("$($issue.Severity)")
                        $encDescription = [System.Net.WebUtility]::HtmlEncode("$($issue.Description)")
                        $encResource = [System.Net.WebUtility]::HtmlEncode("$($issue.Resource)")
                        $encLine = [System.Net.WebUtility]::HtmlEncode("$($issue.Line)")
                        $html += "<tr><td>$encRule</td><td>$encSeverity</td><td>$encDescription</td>"
                        $html += "<td>${encResource}:$encLine</td></tr>"
                    }
                    $html += "</table>"
                }
                $html += @"
    <p style="margin-top: 30px; text-align: center; color: #666; font-size: 12px;">
        <strong>Note:</strong> This report has not been thoroughly tested.
    </p>
</body>
</html>
"@
                $html | Out-File -FilePath $htmlFile -Encoding UTF8
                Write-Host "[+] HTML report saved to: $htmlFile" -ForegroundColor Green
            }

            'JSON' {
                $jsonFile = Join-Path $OutputPath "Terraform-Validation-${RunTimestamp}_${RunId}.json"
                $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
                Write-Host "[+] JSON saved to: $jsonFile" -ForegroundColor Green
            }
        }

        Write-Host "[+] Terraform validation complete!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
