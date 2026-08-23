<#
.SYNOPSIS
    Deprecated shim — forwards to scripts/endpoints/remediation/system/Test-RemediationFixStaleProfiles.ps1.

.DESCRIPTION
    Deprecated wrapper retained for compatibility. Forwards execution to the canonical script at scripts/endpoints/remediation/system/Test-RemediationFixStaleProfiles.ps1. Update Intune assignments to the canonical path. Shim will be removed in 6.0.0.

.NOTES
    Deprecated: moved to scripts/endpoints/remediation/system/Test-RemediationFixStaleProfiles.ps1 — shim will be removed in 6.0.0.
    Intune: exit 0 = healthy, exit 1 = needs remediation (preserved via $LASTEXITCODE).
    Context: runs as SYSTEM in Proactive Remediations — uses Win32_UserProfile / Win32_Battery / Microsoft.WinGet.Client as applicable.
#>
Write-Warning 'Deprecated: moved to scripts/endpoints/remediation/system/Test-RemediationFixStaleProfiles.ps1 — shim will be removed in 6.0.0.'
$null = & "$PSScriptRoot/../../../remediation/system/Test-RemediationFixStaleProfiles.ps1" @args
exit $LASTEXITCODE
