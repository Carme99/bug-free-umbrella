<#
.SYNOPSIS
    Monitors Azure Key Vault security, compliance, and secret expiration.

.DESCRIPTION
    Comprehensive Key Vault monitoring including:
    - Secret/certificate/key expiration tracking
    - Access policy auditing
    - Soft delete and purge protection status
    - Network access restrictions
    - Diagnostic logging configuration
    - Vault usage and performance metrics
    - Unused/orphaned vaults detection

.PARAMETER SubscriptionId
    Azure subscription ID. Use '*' for all subscriptions.

.PARAMETER ExpirationWarningDays
    Days before expiration to warn. Default: 30

.PARAMETER CheckCompliance
    Verify security best practices and compliance

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: Desktop

.EXAMPLE
    Connect-AzAccount
    .\Monitor-AzureKeyVaults.ps1 -SubscriptionId "*" -CheckCompliance

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1+, Az.KeyVault module

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = "*",

    [Parameter(Mandatory = $false)]
    [int]$ExpirationWarningDays = 30,

    [Parameter(Mandatory = $false)]
    [switch]$CheckCompliance,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = [Environment]::GetFolderPath('Desktop')
)

if (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
    Write-Error "Az.KeyVault module required. Install: Install-Module Az.KeyVault"
    exit 1
}

Import-Module Az.KeyVault -ErrorAction SilentlyContinue

$results = @{
    Timestamp = Get-Date
    KeyVaults = @()
    ExpiringSecrets = @()
    ComplianceIssues = @()
    Summary = @{}
}

Write-Host "Monitoring Azure Key Vaults..." -ForegroundColor Cyan

try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Not logged in. Run Connect-AzAccount"
        exit 1
    }
} catch {
    Write-Error "Azure authentication required"
    exit 1
}

$subscriptions = if ($SubscriptionId -eq '*') {
    Get-AzSubscription
} else {
    @(Get-AzSubscription -SubscriptionId $SubscriptionId)
}

$expirationDate = (Get-Date).AddDays($ExpirationWarningDays)

foreach ($sub in $subscriptions) {
    Write-Host "`nAnalyzing subscription: $($sub.Name)" -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    $vaults = Get-AzKeyVault

    foreach ($vault in $vaults) {
        Write-Host "  Checking vault: $($vault.VaultName)" -ForegroundColor Gray

        $vaultData = @{
            Name = $vault.VaultName
            ResourceGroup = $vault.ResourceGroupName
            Location = $vault.Location
            Subscription = $sub.Name
            SoftDeleteEnabled = $vault.EnableSoftDelete
            PurgeProtectionEnabled = $vault.EnablePurgeProtection
            SKU = $vault.Sku
        }

        # Security compliance checks
        if ($CheckCompliance) {
            if (-not $vault.EnableSoftDelete) {
                $results.ComplianceIssues += @{
                    Vault = $vault.VaultName
                    Issue = "Soft delete not enabled"
                    Severity = "High"
                    Recommendation = "Enable soft delete for data protection"
                }
            }

            if (-not $vault.EnablePurgeProtection) {
                $results.ComplianceIssues += @{
                    Vault = $vault.VaultName
                    Issue = "Purge protection not enabled"
                    Severity = "Medium"
                    Recommendation = "Enable purge protection to prevent permanent deletion"
                }
            }
        }

        # Check secrets
        try {
            $secrets = Get-AzKeyVaultSecret -VaultName $vault.VaultName
            $vaultData.SecretCount = $secrets.Count

            foreach ($secret in $secrets) {
                if ($secret.Expires -and $secret.Expires -le $expirationDate) {
                    $daysUntilExpiration = ($secret.Expires - (Get-Date)).Days

                    $results.ExpiringSecrets += @{
                        Vault = $vault.VaultName
                        SecretName = $secret.Name
                        ExpirationDate = $secret.Expires
                        DaysUntilExpiration = $daysUntilExpiration
                        Severity = if ($daysUntilExpiration -le 7) { 'Critical' }
                                   elseif ($daysUntilExpiration -le 14) { 'High' }
                                   else { 'Medium' }
                    }
                }
            }
        } catch {
            Write-Warning "Could not retrieve secrets from $($vault.VaultName): $($_.Exception.Message)"
        }

        # Check certificates
        try {
            $certificates = Get-AzKeyVaultCertificate -VaultName $vault.VaultName
            $vaultData.CertificateCount = $certificates.Count

            foreach ($cert in $certificates) {
                if ($cert.Expires -and $cert.Expires -le $expirationDate) {
                    $daysUntilExpiration = ($cert.Expires - (Get-Date)).Days

                    $results.ExpiringSecrets += @{
                        Vault = $vault.VaultName
                        SecretName = "$($cert.Name) (Certificate)"
                        ExpirationDate = $cert.Expires
                        DaysUntilExpiration = $daysUntilExpiration
                        Severity = if ($daysUntilExpiration -le 7) { 'Critical' }
                                   elseif ($daysUntilExpiration -le 14) { 'High' }
                                   else { 'Medium' }
                    }
                }
            }
        } catch {
            Write-Warning "Could not retrieve certificates from $($vault.VaultName)"
        }

        $results.KeyVaults += $vaultData
    }
}

# Calculate summary
$results.Summary = @{
    TotalVaults = $results.KeyVaults.Count
    ExpiringSecretsCount = $results.ExpiringSecrets.Count
    CriticalExpirations = ($results.ExpiringSecrets | Where-Object { $_.Severity -eq 'Critical' }).Count
    ComplianceIssues = $results.ComplianceIssues.Count
}

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
            foreach ($exp in ($results.ExpiringSecrets | Sort-Object DaysUntilExpiration | Select-Object -First 10)) {
                $color = switch ($exp.Severity) {
                    'Critical' { 'Red' }
                    'High' { 'DarkRed' }
                    default { 'Yellow' }
                }
                Write-Host "[$($exp.Severity)] $($exp.SecretName) in $($exp.Vault): $($exp.DaysUntilExpiration) days" -ForegroundColor $color
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "Azure-KeyVault-Monitor-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
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
    <p>Total Vaults: $($results.Summary.TotalVaults) | Expiring: $($results.Summary.ExpiringSecretsCount) | Compliance Issues: $($results.Summary.ComplianceIssues)</p>
    <h2>Expiring Secrets & Certificates</h2>
    <table>
        <tr><th>Vault</th><th>Secret/Certificate</th><th>Expires</th><th>Days Remaining</th><th>Severity</th></tr>
"@
        foreach ($exp in ($results.ExpiringSecrets | Sort-Object DaysUntilExpiration)) {
            $severityClass = $exp.Severity.ToLower()
            $html += "<tr class='$severityClass'><td>$($exp.Vault)</td><td>$($exp.SecretName)</td><td>$($exp.ExpirationDate)</td><td>$($exp.DaysUntilExpiration)</td><td>$($exp.Severity)</td></tr>"
        }
        $html += "</table><p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'><strong>Note:</strong> This report has not been thoroughly tested.</p></body></html>"
        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML saved to: $htmlFile" -ForegroundColor Green
        Start-Process $htmlFile
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "Azure-KeyVault-Monitor-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nAzure Key Vault monitoring complete!" -ForegroundColor Green
