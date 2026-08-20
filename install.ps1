<#
.SYNOPSIS
    Bootstrap the BugFreeUmbrella module into the current PowerShell session.

.DESCRIPTION
    One-liner bootstrap for a fresh clone of bug-free-umbrella:

        pwsh -NoProfile -File ./install.ps1

    The script verifies PowerShell 7+, warns when execution policy would block
    scripts, imports src/BugFreeUmbrella with -Force (so re-running is
    idempotent), prints how many commands the module exposes, and suggests
    next steps.

    If script execution is blocked by policy, allow local scripts once with:

        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

.EXAMPLE
    ./install.ps1

    Imports the module and prints the available command count plus next steps.

.EXAMPLE
    pwsh -NoProfile -File ./install.ps1

    Non-interactive bootstrap suitable for CI smoke tests; exits non-zero when
    prerequisites are missing.

.NOTES
    File Name   : install.ps1
    Prerequisite: PowerShell 7.0+
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error 'BugFreeUmbrella requires PowerShell 7+. Install it from https://aka.ms/powershell and re-run.'
    exit 1
}

$repoRoot = $PSScriptRoot
$modulePath = Join-Path -Path $repoRoot -ChildPath 'src/BugFreeUmbrella'
if (-not (Test-Path -LiteralPath (Join-Path -Path $modulePath -ChildPath 'BugFreeUmbrella.psd1'))) {
    Write-Error "Module manifest not found under '$modulePath'. Run this script from the repository root of a full clone."
    exit 1
}

$executionPolicy = Get-ExecutionPolicy
if ($executionPolicy -in @('Restricted', 'AllSigned')) {
    Write-Host "Execution policy is '$executionPolicy' and will block local scripts. To allow them, run:" -ForegroundColor Yellow
    Write-Host '    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser' -ForegroundColor Yellow
}

Write-Host "Importing BugFreeUmbrella from '$modulePath'..." -ForegroundColor Cyan
Import-Module -Name $modulePath -Force -ErrorAction Stop

$commandCount = @(Get-Command -Module BugFreeUmbrella).Count
Write-Host "[+] Imported BugFreeUmbrella: $commandCount commands available." -ForegroundColor Green

Write-Host ''
Write-Host 'Next steps:'
Write-Host '  Get-BUScript -Search intune           # discover scripts (35 matches today)'
Write-Host '  Invoke-BUScript -Path <script> -WhatIf # preview any script safely'
Write-Host '  Register-BUCompleter                  # tab completion for -Category / -Name'
Write-Host '  Install-Module BugFreeUmbrella -Scope CurrentUser  # published module on PSGallery'
