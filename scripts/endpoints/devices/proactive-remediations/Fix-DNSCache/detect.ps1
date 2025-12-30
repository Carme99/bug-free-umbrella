<#
.SYNOPSIS
    Detects DNS resolution issues by testing connectivity to common domains.

.DESCRIPTION
    This detection script tests DNS resolution to common domains.
    If DNS resolution fails, triggers cache flush remediation.

.NOTES
    Exit 0: DNS is working correctly
    Exit 1: DNS issues detected (triggers remediation)
#>

$ErrorActionPreference = "SilentlyContinue"

# Test domains
$testDomains = @(
    "microsoft.com",
    "google.com",
    "cloudflare.com"
)

$failedDomains = @()

foreach ($domain in $testDomains) {
    try {
        $result = Resolve-DnsName -Name $domain -ErrorAction Stop -QuickTimeout
        if (-not $result) {
            $failedDomains += $domain
        }
    }
    catch {
        $failedDomains += $domain
    }
}

# If more than 1 domain fails, likely DNS issue
if ($failedDomains.Count -ge 2) {
    Write-Output "DNS resolution failed for $($failedDomains.Count) domain(s): $($failedDomains -join ', ')"
    exit 1  # Triggers remediation
}
else {
    Write-Output "DNS resolution is working correctly"
    exit 0  # Compliant
}
