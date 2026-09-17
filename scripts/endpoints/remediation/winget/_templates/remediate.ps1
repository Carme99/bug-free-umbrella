<#
.SYNOPSIS
    DEPRECATED V1 winget remediation template - thin shim over remediate_v1_legacy.ps1.

.DESCRIPTION
    Historical entry-point name for the V1 remediation template. The body lives in remediate_v1_legacy.ps1;
    this file carries no logic of its own, it only loads that file so the original name keeps working.
    Superseded by the V3 templates - use remediate_v3_standard.ps1 instead.

.EXAMPLE
    PS C:\> .\remediate.ps1

    Runs the V1 (deprecated) remediation flow.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\remediate.ps1

    Non-interactive invocation.

.NOTES
    File Name  : remediate.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 2.0.0
    Date       : 2026-09-16
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Single source of truth: the V1 body lives in remediate_v1_legacy.ps1. Apart from filename strings the two files
# were identical, so keeping both copies only guaranteed they would drift.
# Loaded at top level (not inside a function) so the template's helpers and state are defined for
# callers exactly as before; the loaded file's own guard does not fire on a dot-source.
. (Join-Path $PSScriptRoot 'remediate_v1_legacy.ps1')

# The loaded template defines Main. Capture it before shadowing the name, so this shim can expose
# its own Main (the standards contract requires one) without losing the real implementation.
$shimLegacyMain = ${function:Main}

function Main {
    <#
    .SYNOPSIS
        Runs the V1 remediation flow implemented in remediate_v1_legacy.ps1.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    return (& $shimLegacyMain)
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
