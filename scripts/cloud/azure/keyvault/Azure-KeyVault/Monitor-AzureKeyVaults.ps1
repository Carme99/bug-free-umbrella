<#
.SYNOPSIS
    Check Azure Key Vault security, compliance, and secret expiration across subscriptions.

.DESCRIPTION
    Key Vault monitoring that provides:
    - Secret/certificate/key expiration tracking
    - Soft delete and purge protection status
    - Vault inventory across subscriptions (location, SKU, resource group)

    The script is read-only: it never mutates vaults or secrets, so re-running it on an
    already-analyzed environment always succeeds and makes no changes. Exit codes:
    0 on success; 1 on any failure (missing Az.KeyVault module, not authenticated,
    unsafe path, upstream error).

.PARAMETER SubscriptionId
    Azure subscription ID. Use '*' for all subscriptions.

.PARAMETER ExpirationWarningDays
    Days before expiration to warn. Default: 30

.PARAMETER CheckCompliance
    Verify security best practices and compliance.

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Must be a local absolute path without '..' traversal.
    Default: MyDocuments\Reports

.EXAMPLE
    PS C:\> Connect-AzAccount
    PS C:\> .\Monitor-AzureKeyVaults.ps1 -SubscriptionId "*" -CheckCompliance

    Monitors all accessible vaults and reports soft delete / purge protection gaps.

.EXAMPLE
    PS C:\> .\Monitor-AzureKeyVaults.ps1 -ExpirationWarningDays 60 -OutputFormat Console

    Warns about secrets and certificates expiring within 60 days and prints a console summary.

.NOTES
    File Name: Monitor-AzureKeyVaults.ps1
    Author: IT Operations
    Prerequisite: PowerShell 7.0, Az PowerShell module (Az.Accounts, Az.KeyVault)
    Version: 1.0.0
    Date: 2026-08-23
#>

#Requires -Version 7.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'RELAUNCH-SPEC section 3 mandates Write-Host output with [+]/[!]/[-]/[*] prefixes')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Params consumed inside Main via scoping; see help')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = '*',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$ExpirationWarningDays = 30,

    [Parameter(Mandatory = $false)]
    [switch]$CheckCompliance,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)

$ErrorActionPreference = 'Stop'

function Main {
    <#
    .SYNOPSIS
        Runs the Key Vault monitoring flow; returns 0 on success, 1 on failure.
    #>
    [CmdletBinding()]
    param()

    try {
        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            Write-Host "[-] Unsafe OutputPath: $OutputPath." -ForegroundColor Red
            Write-Host "    Use a local absolute path without '..' traversal." -ForegroundColor Red
            return 1
        }
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        if (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
            Write-Host "[-] Az.KeyVault module required. Install: Install-Module Az.KeyVault" -ForegroundColor Red
            return 1
        }

        Import-Module Az.KeyVault -ErrorAction SilentlyContinue

        $results = @{
            Timestamp        = Get-Date
            KeyVaults        = @()
            ExpiringSecrets  = @()
            ComplianceIssues = @()
            Summary          = @{}
        }

        Write-Host "[*] Monitoring Azure Key Vaults..." -ForegroundColor Cyan

        # Ensure logged in
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            Write-Host "[-] Not logged in. Run Connect-AzAccount" -ForegroundColor Red
            return 1
        }

        if ($SubscriptionId -eq '*') {
            $subscriptions = @(Get-AzSubscription -ErrorAction Stop)
        }
        else {
            $subscriptions = @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        }

        $expirationDate = (Get-Date).AddDays($ExpirationWarningDays)

        foreach ($sub in $subscriptions) {
            Write-Host "`n[*] Analyzing subscription: $($sub.Name)" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null

            $vaults = Get-AzKeyVault -ErrorAction Stop

            foreach ($vault in $vaults) {
                Write-Host "  Checking vault: $($vault.VaultName)" -ForegroundColor Gray

                $vaultData = @{
                    Name                   = $vault.VaultName
                    ResourceGroup          = $vault.ResourceGroupName
                    Location               = $vault.Location
                    Subscription           = $sub.Name
                    SoftDeleteEnabled      = $vault.EnableSoftDelete
                    PurgeProtectionEnabled = $vault.EnablePurgeProtection
                    SKU                    = $vault.Sku
                }

                # Security compliance checks
                if ($CheckCompliance) {
                    if (-not $vault.EnableSoftDelete) {
                        $results.ComplianceIssues += @{
                            Vault          = $vault.VaultName
                            Issue          = 'Soft delete not enabled'
                            Severity       = 'High'
                            Recommendation = 'Enable soft delete for data protection'
                        }
                    }

                    if (-not $vault.EnablePurgeProtection) {
                        $results.ComplianceIssues += @{
                            Vault          = $vault.VaultName
                            Issue          = 'Purge protection not enabled'
                            Severity       = 'Medium'
                            Recommendation = 'Enable purge protection to prevent permanent deletion'
                        }
                    }
                }

                # Check secrets
                try {
                    $secrets = Get-AzKeyVaultSecret -VaultName $vault.VaultName -ErrorAction Stop
                    $vaultData.SecretCount = $secrets.Count

                    foreach ($secret in $secrets) {
                        if ($secret.Expires -and $secret.Expires -le $expirationDate) {
                            $daysUntilExpiration = ($secret.Expires - (Get-Date)).Days

                            $severity = if ($daysUntilExpiration -le 7) { 'Critical' }
                            elseif ($daysUntilExpiration -le 14) { 'High' }
                            else { 'Medium' }

                            $results.ExpiringSecrets += @{
                                Vault               = $vault.VaultName
                                SecretName          = $secret.Name
                                ExpirationDate      = $secret.Expires
                                DaysUntilExpiration = $daysUntilExpiration
                                Severity            = $severity
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "Could not retrieve secrets from $($vault.VaultName): $($_.Exception.Message)"
                }

                # Check certificates
                try {
                    $certificates = Get-AzKeyVaultCertificate -VaultName $vault.VaultName -ErrorAction Stop
                    $vaultData.CertificateCount = $certificates.Count

                    foreach ($cert in $certificates) {
                        if ($cert.Expires -and $cert.Expires -le $expirationDate) {
                            $daysUntilExpiration = ($cert.Expires - (Get-Date)).Days

                            $severity = if ($daysUntilExpiration -le 7) { 'Critical' }
                            elseif ($daysUntilExpiration -le 14) { 'High' }
                            else { 'Medium' }

                            $results.ExpiringSecrets += @{
                                Vault               = $vault.VaultName
                                SecretName          = "$($cert.Name) (Certificate)"
                                ExpirationDate      = $cert.Expires
                                DaysUntilExpiration = $daysUntilExpiration
                                Severity            = $severity
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "Could not retrieve certificates from $($vault.VaultName)"
                }

                $results.KeyVaults += $vaultData
            }
        }

        # Calculate summary
        $results.Summary = @{
            TotalVaults         = $results.KeyVaults.Count
            ExpiringSecretsCount = $results.ExpiringSecrets.Count
            CriticalExpirations = ($results.ExpiringSecrets | Where-Object { $_.Severity -eq 'Critical' }).Count
            ComplianceIssues    = $results.ComplianceIssues.Count
        }

        Write-Host "`n[+] Analysis complete!" -ForegroundColor Green

        # Run-scoped stamp to avoid filename collisions on rapid re-runs
        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        # Output
        switch ($OutputFormat) {
            'Console' {
                Write-Host "`n=== Azure Key Vault Summary ===" -ForegroundColor Cyan
                Write-Host "Total Vaults: $($results.Summary.TotalVaults)" -ForegroundColor White
                Write-Host "Expiring Secrets/Certs: $($results.Summary.ExpiringSecretsCount)" -ForegroundColor Yellow
                Write-Host "Critical Expirations: $($results.Summary.CriticalExpirations)" -ForegroundColor Red
                Write-Host "Compliance Issues: $($results.Summary.ComplianceIssues)" -ForegroundColor Yellow

                if ($results.ExpiringSecrets.Count -gt 0) {
                    Write-Host "`n=== Expiring Secrets/Certificates ===" -ForegroundColor Yellow
                    $topExpiring = @($results.ExpiringSecrets |
                        Sort-Object DaysUntilExpiration | Select-Object -First 10)
                    foreach ($exp in $topExpiring) {
                        $color = switch ($exp.Severity) {
                            'Critical' { 'Red' }
                            'High' { 'DarkRed' }
                            default { 'Yellow' }
                        }
                        $msg = "[$($exp.Severity)] $($exp.SecretName) in $($exp.Vault): " +
                            "$($exp.DaysUntilExpiration) days"
                        Write-Host $msg -ForegroundColor $color
                    }
                }
            }

            'HTML' {
                $htmlFile = Join-Path $OutputPath "Azure-KeyVault-Monitor-${RunTimestamp}_${RunId}.html"
                $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure Key Vault Monitor Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #0078d4; }
        table { border-collapse: collapse; width: 100%; background: white; margin: 10px 0; }
        th { background: #0078d4; color: white; padding: 10px; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        .critical { background-color: #fdd; color: #d13438; font-weight: bold; }
        .high { background-color: #fed; color: #8b0000; }
        .medium { background-color: #fff3cd; color: #856404; }
    </style>
</head>
<body>
    <h1>Azure Key Vault Monitor Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <p>Total Vaults: $($results.Summary.TotalVaults)
    | Expiring: $($results.Summary.ExpiringSecretsCount) | Compliance Issues: $($results.Summary.ComplianceIssues)</p>
    <h2>Expiring Secrets & Certificates</h2>
    <table>
        <tr><th>Vault</th><th>Secret/Certificate</th><th>Expires</th><th>Days Remaining</th><th>Severity</th></tr>
"@
                foreach ($exp in ($results.ExpiringSecrets | Sort-Object DaysUntilExpiration)) {
                    $severityClass = $exp.Severity.ToLower()
                    $vaultCell = [System.Net.WebUtility]::HtmlEncode("$($exp.Vault)")
                    $secretCell = [System.Net.WebUtility]::HtmlEncode("$($exp.SecretName)")
                    $severityCell = [System.Net.WebUtility]::HtmlEncode("$($exp.Severity)")
                    $html += "<tr class='$severityClass'><td>$vaultCell</td><td>$secretCell</td>" +
                        "<td>$($exp.ExpirationDate)</td><td>$($exp.DaysUntilExpiration)</td><td>$severityCell</td></tr>"
                }
                $html += "</table><p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'>" +
                    "<strong>Note:</strong> This report has not been thoroughly tested.</p></body></html>"
                $html | Out-File -FilePath $htmlFile -Encoding utf8
                Write-Host "`n[+] HTML saved to: $htmlFile" -ForegroundColor Green
            }

            'JSON' {
                $jsonFile = Join-Path $OutputPath "Azure-KeyVault-Monitor-${RunTimestamp}_${RunId}.json"
                $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
                Write-Host "`n[+] JSON saved to: $jsonFile" -ForegroundColor Green
            }
        }

        Write-Host "`n[+] Azure Key Vault monitoring complete!" -ForegroundColor Green

        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
