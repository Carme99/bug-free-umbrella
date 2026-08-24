<#
.SYNOPSIS
    Repair Windows Search by resetting the service and rebuilding its index.

.DESCRIPTION
    Fixes a broken Windows Search installation: stops the WSearch service, deletes the
    stale search index database files (*.edb, *.chk, *.log), restores Automatic startup,
    starts the service again and triggers a SystemIndex rebuild via the search catalog
    COM API. Side effects: service restart, deletion of the index cache (Windows Search
    recreates the files automatically) and an index rebuild; every mutation is gated
    behind -WhatIf/-Confirm via SupportsShouldProcess. An already-running service with
    Automatic startup is left untouched (idempotent).
    Exit codes: 0 = remediation complete or already healthy; 1 = remediation failed.
    Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsSearch.ps1

    Resets the Windows Search service, clears its index cache and rebuilds the index.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsSearch.ps1 -WhatIf

    Shows which repair steps would run without stopping the service or deleting files.

.NOTES
    File Name  : Invoke-RemediationFixWindowsSearch.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Starting Windows Search remediation..." -ForegroundColor Cyan

        $searchService = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        if (-not $searchService) {
            throw "Windows Search service (WSearch) not found"
        }

        # Check-then-act: a running service with Automatic startup is healthy.
        if ($searchService.Status -eq 'Running' -and $searchService.StartType -eq 'Automatic') {
            Write-Host "[+] Already healthy: Windows Search is running with Automatic startup" -ForegroundColor Green
            return 0
        }

        # Stop the service before touching its index files.
        if ($searchService.Status -eq 'Running') {
            if ($PSCmdlet.ShouldProcess('WSearch', 'Stop Windows Search service')) {
                Stop-Service -Name 'WSearch' -Force -ErrorAction Stop
                Start-Sleep -Seconds 3
                Write-Host "[+] Windows Search service stopped" -ForegroundColor Green
            }
        }

        # Clear the search index cache; Windows Search recreates the files automatically.
        $searchDataPath = Join-Path $env:ProgramData 'Microsoft\Search\Data'
        if (Test-Path $searchDataPath) {
            $indexFiles = @(Get-ChildItem -Path $searchDataPath -Include '*.edb', '*.chk', '*.log' `
                -Recurse -ErrorAction SilentlyContinue)
            foreach ($indexFile in $indexFiles) {
                if ($PSCmdlet.ShouldProcess($indexFile.FullName, 'Delete stale search index file')) {
                    Remove-Item -LiteralPath $indexFile.FullName -Force -ErrorAction Stop
                }
            }
            Write-Host "[+] Search index cache cleared ($($indexFiles.Count) file(s))" -ForegroundColor Green
        }

        if ($PSCmdlet.ShouldProcess('WSearch', 'Set startup type to Automatic')) {
            Set-Service -Name 'WSearch' -StartupType Automatic -ErrorAction Stop
            Write-Host "[+] Windows Search startup type set to Automatic" -ForegroundColor Green
        }

        if ($PSCmdlet.ShouldProcess('WSearch', 'Start Windows Search service')) {
            Start-Service -Name 'WSearch' -ErrorAction Stop
            Start-Sleep -Seconds 5
        }

        # Verify the service came back up.
        $searchService = Get-Service -Name 'WSearch' -ErrorAction Stop
        if ($searchService.Status -ne 'Running') {
            throw "Failed to start Windows Search service (status: $($searchService.Status))"
        }
        Write-Host "[+] Windows Search service is running" -ForegroundColor Green

        # Trigger an index rebuild; failure here is non-fatal because the index
        # rebuilds automatically over time anyway.
        try {
            if ($PSCmdlet.ShouldProcess('SystemIndex', 'Trigger search index rebuild')) {
                $searchCatalogManager = New-Object -ComObject Search.SearchCatalogManager
                $catalog = $searchCatalogManager.GetCatalog('SystemIndex')
                $catalog.Reindex()
                Write-Host "[+] Search index rebuild initiated" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "[!] Could not trigger index rebuild automatically: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "[!] Index will rebuild automatically over time" -ForegroundColor Yellow
        }

        Write-Host "[+] Windows Search remediation completed successfully" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error during Windows Search remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
