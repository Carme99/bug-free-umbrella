<#
.SYNOPSIS
    DEPRECATED: use detect_v3.ps1. Thin shim over detect_v1_legacy.ps1 (V1 detection).

.DESCRIPTION
    Historical entry-point name for the V1 detection template. The body lives in detect_v1_legacy.ps1;
    this file carries no logic of its own, it only loads that file so the original name keeps working.
    Superseded by the V3 templates - use detect_v3.ps1 instead.

.EXAMPLE
    PS C:\> .\detect.ps1

    Runs the V1 (deprecated) detection flow.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\detect.ps1

    Non-interactive invocation.

.NOTES
    File Name  : detect.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 2.0.0
    Date       : 2026-09-16
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Single source of truth: the V1 body lives in detect_v1_legacy.ps1. Apart from filename strings the two files
# were identical, so keeping both copies only guaranteed they would drift.
# Loaded at top level (not inside a function) so the template's helpers and state are defined for
# callers exactly as before; the loaded file's own guard does not fire on a dot-source.
. (Join-Path $PSScriptRoot 'detect_v1_legacy.ps1')

# The loaded template defines Main. Capture it before shadowing the name, so this shim can expose
# its own Main (the standards contract requires one) without losing the real implementation.
$shimLegacyMain = ${function:Main}

function Main {
    <#
    .SYNOPSIS
        Runs the V1 detection flow implemented in detect_v1_legacy.ps1.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    return (& $shimLegacyMain)
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
