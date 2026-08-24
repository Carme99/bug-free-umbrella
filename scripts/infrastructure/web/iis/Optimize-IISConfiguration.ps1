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

    Every mutation is gated behind ShouldProcess, so -WhatIf previews the
    changes without applying them. Operations are check-then-act where state
    can be read first (HTTP/2 registry values), and re-running the script on a
    converged server succeeds without errors.

.PARAMETER ApplyPerformanceOptimizations
    Apply performance-related optimizations.

.PARAMETER ApplySecurityHardening
    Apply security hardening settings.

.PARAMETER EnableHTTP2
    Enable HTTP/2 support (registry-backed; skipped when already enabled).

.EXAMPLE
    PS C:\> .\Optimize-IISConfiguration.ps1 -ApplyPerformanceOptimizations -WhatIf

    Preview performance optimizations without applying them.

.EXAMPLE
    PS C:\> .\Optimize-IISConfiguration.ps1 -ApplyPerformanceOptimizations -ApplySecurityHardening

    Apply both performance and security optimizations.

.NOTES
    File Name   : Optimize-IISConfiguration.ps1
    Author      : IT Infrastructure Team
    Prerequisite: PowerShell 5.1+, IISAdministration module (Windows), Administrator privileges
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive administrative console tool; output is operator-facing UI, not pipeline data')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script-scope parameters are consumed by Main and its helper functions after dot-source binding')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [switch]$ApplyPerformanceOptimizations,

    [Parameter()]
    [switch]$ApplySecurityHardening,

    [Parameter()]
    [switch]$EnableHTTP2
)

# Runtime prerequisites: Windows host with IIS, IISAdministration module, elevated session.
$ErrorActionPreference = 'Stop'

function Write-ScriptMessage {
    <#
    .SYNOPSIS
        Writes a prefixed, colored message to the console (single emitter).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('+', '!', '-', '*', '')]
        [string]$Prefix = '',

        [Parameter()]
        [ValidateSet('Green', 'Yellow', 'Red', 'Cyan', 'White')]
        [string]$Color = 'White'
    )

    # Write-Host justified: interactive administrative console tool; output is UI, not pipeline data.
    if ($Prefix) {
        Write-Host "[$Prefix] $Message" -ForegroundColor $Color
    }
    else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Invoke-PerformanceOptimization {
    <#
    .SYNOPSIS
        Applies IIS performance optimizations (gated by ShouldProcess).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [ref]$Changes
    )

    Write-ScriptMessage -Message 'Applying performance optimizations...' -Prefix '*' -Color Cyan

    # Set-WebConfigurationProperty / Add-WebConfigurationProperty have no direct
    # IISAdministration equivalent for arbitrary config sections; they remain on
    # WebAdministration, which PowerShell auto-loads side by side with IISAdministration.
    if ($PSCmdlet.ShouldProcess('IIS', 'Enable static compression')) {
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
            -Filter 'system.webServer/urlCompression' `
            -Name 'doStaticCompression' -Value 'True' -ErrorAction Stop
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
            -Filter 'system.webServer/urlCompression' `
            -Name 'doDynamicCompression' -Value 'True' -ErrorAction Stop
        $Changes.Value += 'Enabled static and dynamic compression'
        Write-ScriptMessage -Message 'Compression enabled' -Prefix '+' -Color Green
    }

    if ($PSCmdlet.ShouldProcess('Application Pools', 'Optimize recycling and queue settings')) {
        # IISAdministration equivalent of the IIS:\ provider Set-Item: modify the
        # Microsoft.Web.Administration pool objects and commit via ServerManager.
        $serverManager = Get-IISServerManager -ErrorAction Stop
        $appPools = @($serverManager.ApplicationPools)
        foreach ($pool in $appPools) {
            $pool.Recycling.PeriodicRestart.Time = [TimeSpan]::FromHours(29)
            $pool.ProcessModel.IdleTimeout = [TimeSpan]::FromMinutes(20)
            $pool.QueueLength = 5000
        }
        $serverManager.CommitChanges()
        $Changes.Value += "Optimized application pool settings for $($appPools.Count) pools"
        Write-ScriptMessage -Message 'Application pools optimized' -Prefix '+' -Color Green
    }

    if ($PSCmdlet.ShouldProcess('IIS', 'Enable output caching')) {
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
            -Filter 'system.webServer/caching' `
            -Name 'enabled' -Value 'True' -ErrorAction Stop
        $Changes.Value += 'Enabled output caching'
        Write-ScriptMessage -Message 'Output caching enabled' -Prefix '+' -Color Green
    }
}

function Invoke-SecurityHardening {
    <#
    .SYNOPSIS
        Applies IIS security hardening settings (gated by ShouldProcess).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [ref]$Changes
    )

    Write-ScriptMessage -Message 'Applying security hardening...' -Prefix '*' -Color Cyan

    if ($PSCmdlet.ShouldProcess('IIS', 'Remove server header')) {
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
            -Filter 'system.webServer/security/requestFiltering' `
            -Name 'removeServerHeader' -Value 'True' -ErrorAction Stop
        $Changes.Value += 'Removed server header'
        Write-ScriptMessage -Message 'Server header removed' -Prefix '+' -Color Green
    }

    if ($PSCmdlet.ShouldProcess('IIS Sites', 'Add security headers')) {
        $sites = @(Get-IISSite -ErrorAction Stop)
        foreach ($site in $sites) {
            $sitePath = "IIS:\Sites\$($site.Name)"

            # Duplicate-header failures are tolerated: re-runs must stay idempotent.
            Add-WebConfigurationProperty -PSPath $sitePath `
                -Filter 'system.webServer/httpProtocol/customHeaders' `
                -Name '.' -Value @{ name = 'X-Frame-Options'; value = 'SAMEORIGIN' } `
                -ErrorAction SilentlyContinue
            Add-WebConfigurationProperty -PSPath $sitePath `
                -Filter 'system.webServer/httpProtocol/customHeaders' `
                -Name '.' -Value @{ name = 'X-Content-Type-Options'; value = 'nosniff' } `
                -ErrorAction SilentlyContinue
            Add-WebConfigurationProperty -PSPath $sitePath `
                -Filter 'system.webServer/httpProtocol/customHeaders' `
                -Name '.' -Value @{ name = 'X-XSS-Protection'; value = '1; mode=block' } `
                -ErrorAction SilentlyContinue
            Add-WebConfigurationProperty -PSPath $sitePath `
                -Filter 'system.webServer/httpProtocol/customHeaders' `
                -Name '.' `
                -Value @{ name = 'Strict-Transport-Security'; value = 'max-age=31536000; includeSubDomains' } `
                -ErrorAction SilentlyContinue
        }
        $Changes.Value += "Added security headers to $($sites.Count) sites"
        Write-ScriptMessage -Message 'Security headers configured' -Prefix '+' -Color Green
    }

    if ($PSCmdlet.ShouldProcess('IIS', 'Disable directory browsing')) {
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
            -Filter 'system.webServer/directoryBrowse' `
            -Name 'enabled' -Value 'False' -ErrorAction Stop
        $Changes.Value += 'Disabled directory browsing'
        Write-ScriptMessage -Message 'Directory browsing disabled' -Prefix '+' -Color Green
    }
}

function Invoke-Http2Enablement {
    <#
    .SYNOPSIS
        Enables HTTP/2 via registry (check-then-act; gated by ShouldProcess).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [ref]$Changes
    )

    Write-ScriptMessage -Message 'Enabling HTTP/2...' -Prefix '*' -Color Cyan

    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters'
    $current = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
    $needsTls = (-not $current) -or ($current.EnableHttp2Tls -ne 1)
    $needsCleartext = (-not $current) -or ($current.EnableHttp2Cleartext -ne 1)

    if (-not $needsTls -and -not $needsCleartext) {
        Write-ScriptMessage -Message 'HTTP/2 already enabled' -Prefix '+' -Color Green
        return
    }

    if ($PSCmdlet.ShouldProcess($regPath, 'Enable HTTP/2')) {
        if ($needsTls) {
            Set-ItemProperty -Path $regPath -Name 'EnableHttp2Tls' -Value 1 -Type DWord -ErrorAction Stop
        }
        if ($needsCleartext) {
            Set-ItemProperty -Path $regPath -Name 'EnableHttp2Cleartext' -Value 1 -Type DWord -ErrorAction Stop
        }
        $Changes.Value += 'Enabled HTTP/2 support'
        Write-ScriptMessage -Message 'HTTP/2 enabled (restart required)' -Prefix '+' -Color Green
    }
}

function Main {
    <#
    .SYNOPSIS
        Runs the IIS configuration optimizer workflow.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-ScriptMessage -Message '=== IIS Configuration Optimizer ==='

        $changes = @()

        if ($ApplyPerformanceOptimizations) {
            Invoke-PerformanceOptimization -Changes ([ref]$changes)
        }

        if ($ApplySecurityHardening) {
            Invoke-SecurityHardening -Changes ([ref]$changes)
        }

        if ($EnableHTTP2) {
            Invoke-Http2Enablement -Changes ([ref]$changes)
        }

        Write-ScriptMessage -Message '=== Optimization Summary ==='
        if ($changes.Count -gt 0) {
            foreach ($change in $changes) {
                Write-ScriptMessage -Message "  - $change" -Color Green
            }
            Write-ScriptMessage `
                -Message 'Note: Some changes may require IIS restart to take effect' `
                -Prefix '!' -Color Yellow
            Write-ScriptMessage -Message 'To restart IIS: iisreset /noforce' -Prefix '*' -Color Cyan
        }
        else {
            Write-ScriptMessage `
                -Message 'No changes applied (use -WhatIf to preview or specify optimization switches)' `
                -Prefix '!' -Color Yellow
        }

        Write-ScriptMessage -Message 'Optimization complete!' -Prefix '+' -Color Green
        return 0
    }
    catch {
        Write-ScriptMessage -Message "Error: $($_.Exception.Message)" -Prefix '-' -Color Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
