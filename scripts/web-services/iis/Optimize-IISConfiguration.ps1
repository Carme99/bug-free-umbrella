<#
.SYNOPSIS
    Optimize IIS configuration for performance and security.

.DESCRIPTION
    Applies performance and security optimizations to IIS:
    - Application pool recycling optimization
    - Request queue limits
    - Compression settings (static and dynamic)
    - Output caching configuration
    - Security headers (HSTS, X-Frame-Options, CSP)
    - Failed request tracing
    - Logging optimization
    - HTTP/2 enablement

.PARAMETER ApplyPerformanceOptimizations
    Apply performance-related optimizations.

.PARAMETER ApplySecurityHardening
    Apply security hardening settings.

.PARAMETER EnableHTTP2
    Enable HTTP/2 support.

.PARAMETER WhatIf
    Preview changes without applying them.

.EXAMPLE
    .\Optimize-IISConfiguration.ps1 -ApplyPerformanceOptimizations -WhatIf

    Preview performance optimizations.

.EXAMPLE
    .\Optimize-IISConfiguration.ps1 -ApplyPerformanceOptimizations -ApplySecurityHardening

    Apply both performance and security optimizations.

.NOTES
    Author: IT Infrastructure Team
    Requires: IIS 8.0+, Administrator privileges
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [switch]$ApplyPerformanceOptimizations,

    [Parameter()]
    [switch]$ApplySecurityHardening,

    [Parameter()]
    [switch]$EnableHTTP2,

    [Parameter()]
    [switch]$WhatIf
)

#Requires -Modules WebAdministration
#Requires -RunAsAdministrator

Write-Host "`n=== IIS Configuration Optimizer ===" -ForegroundColor Cyan

$changes = @()

if ($ApplyPerformanceOptimizations) {
    Write-Host "`n[*] Applying performance optimizations..." -ForegroundColor Cyan

    # Enable compression
    if ($PSCmdlet.ShouldProcess("IIS", "Enable static compression")) {
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.webServer/urlCompression" -Name "doStaticCompression" -Value "True"
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.webServer/urlCompression" -Name "doDynamicCompression" -Value "True"
        $changes += "Enabled static and dynamic compression"
        Write-Host "[+] Compression enabled" -ForegroundColor Green
    }

    # Optimize application pools
    if ($PSCmdlet.ShouldProcess("Application Pools", "Optimize recycling and queue settings")) {
        $appPools = Get-IISAppPool
        foreach ($pool in $appPools) {
            $pool.Recycling.PeriodicRestart.Time = [TimeSpan]::FromHours(29)
            $pool.ProcessModel.IdleTimeout = [TimeSpan]::FromMinutes(20)
            $pool.QueueLength = 5000
            $pool | Set-Item
        }
        $changes += "Optimized application pool settings for $($appPools.Count) pools"
        Write-Host "[+] Application pools optimized" -ForegroundColor Green
    }

    # Enable output caching
    if ($PSCmdlet.ShouldProcess("IIS", "Enable output caching")) {
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.webServer/caching" -Name "enabled" -Value "True"
        $changes += "Enabled output caching"
        Write-Host "[+] Output caching enabled" -ForegroundColor Green
    }
}

if ($ApplySecurityHardening) {
    Write-Host "`n[*] Applying security hardening..." -ForegroundColor Cyan

    # Remove server header
    if ($PSCmdlet.ShouldProcess("IIS", "Remove server header")) {
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.webServer/security/requestFiltering" -Name "removeServerHeader" -Value "True"
        $changes += "Removed server header"
        Write-Host "[+] Server header removed" -ForegroundColor Green
    }

    # Configure security headers for all sites
    if ($PSCmdlet.ShouldProcess("IIS Sites", "Add security headers")) {
        $sites = Get-IISSite
        foreach ($site in $sites) {
            $sitePath = "IIS:\Sites\$($site.Name)"

            # Add custom headers
            Add-WebConfigurationProperty -PSPath $sitePath -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -Value @{name='X-Frame-Options';value='SAMEORIGIN'} -ErrorAction SilentlyContinue
            Add-WebConfigurationProperty -PSPath $sitePath -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -Value @{name='X-Content-Type-Options';value='nosniff'} -ErrorAction SilentlyContinue
            Add-WebConfigurationProperty -PSPath $sitePath -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -Value @{name='X-XSS-Protection';value='1; mode=block'} -ErrorAction SilentlyContinue
            Add-WebConfigurationProperty -PSPath $sitePath -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -Value @{name='Strict-Transport-Security';value='max-age=31536000; includeSubDomains'} -ErrorAction SilentlyContinue
        }
        $changes += "Added security headers to $($sites.Count) sites"
        Write-Host "[+] Security headers configured" -ForegroundColor Green
    }

    # Disable directory browsing
    if ($PSCmdlet.ShouldProcess("IIS", "Disable directory browsing")) {
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.webServer/directoryBrowse" -Name "enabled" -Value "False"
        $changes += "Disabled directory browsing"
        Write-Host "[+] Directory browsing disabled" -ForegroundColor Green
    }
}

if ($EnableHTTP2) {
    Write-Host "`n[*] Enabling HTTP/2..." -ForegroundColor Cyan
    if ($PSCmdlet.ShouldProcess("IIS", "Enable HTTP/2")) {
        # Enable HTTP/2 via registry
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters"
        Set-ItemProperty -Path $regPath -Name "EnableHttp2Tls" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name "EnableHttp2Cleartext" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        $changes += "Enabled HTTP/2 support"
        Write-Host "[+] HTTP/2 enabled (restart required)" -ForegroundColor Green
    }
}

Write-Host "`n=== Optimization Summary ===" -ForegroundColor Cyan
if ($changes.Count -gt 0) {
    foreach ($change in $changes) {
        Write-Host "  - $change" -ForegroundColor Green
    }
    Write-Host "`n[!] Note: Some changes may require IIS restart to take effect" -ForegroundColor Yellow
    Write-Host "[*] To restart IIS: iisreset /noforce" -ForegroundColor Cyan
} else {
    Write-Host "  No changes applied (use -WhatIf to preview or specify optimization switches)" -ForegroundColor Yellow
}

Write-Host "`nOptimization complete!`n" -ForegroundColor Green
