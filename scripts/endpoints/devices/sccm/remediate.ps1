# Remediation script for SCCM

<#
.SYNOPSIS
    Remediation script for the SCCM client Proactive Remediation.

.DESCRIPTION
    Installs the Configuration Manager (SCCM) client from a local or UNC source
    path when the client is not already installed. Uses the secure
    ProcessStartInfo pattern (no shell, no window) to run ccmsetup.exe against
    the supplied source tree and reports the actual install outcome.

.PARAMETER SourcePath
    Local or UNC path containing ccmsetup.exe and the client source
    (e.g. \\SCCM-SERVER\SCCMContentLib\Client or C:\SCCM).
    Required when the client is not already installed.

.PARAMETER ManagementPoint
    (Optional) FQDN of the management point to pass to ccmsetup via /MP:.
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$SourcePath,

    [Parameter(Mandatory = $false)]
    [string]$ManagementPoint
)

# Define the path to an already-installed ccmsetup.exe
$ccmSetupPath = "$env:windir\ccmsetup\ccmsetup.exe"

# Already installed - nothing to remediate.
if (Test-Path $ccmSetupPath) {
    Write-Output " SCCM client is installed."
    exit 0
}

# Client not installed. A source path is required to install it.
if (-not $SourcePath -or -not (Test-Path $SourcePath)) {
    Write-Error " SCCM client is NOT installed and no valid -SourcePath was provided. Supply a local/UNC path containing ccmsetup.exe (e.g. \\SCCM-SERVER\SCCMContentLib\Client or C:\SCCM)."
    exit 1
}

# Locate ccmsetup.exe in the source tree (source root or ccmsetup subfolder).
$sourceCcmSetup = Join-Path $SourcePath "ccmsetup.exe"
if (-not (Test-Path $sourceCcmSetup)) {
    $subPath = Join-Path $SourcePath "ccmsetup\ccmsetup.exe"
    if (Test-Path $subPath) {
        $sourceCcmSetup = $subPath
    }
}

if (-not (Test-Path $sourceCcmSetup)) {
    Write-Error " ccmsetup.exe was not found under -SourcePath '$SourcePath'. Verify the source tree."
    exit 1
}

# Build argument list for ccmsetup.exe.
$arguments = "/Source:$SourcePath"
if ($ManagementPoint) {
    $arguments = "$arguments /MP:$ManagementPoint"
}

Write-Output " SCCM client not installed. Installing from '$SourcePath' using ccmsetup.exe."

# Launch ccmsetup.exe with the secure ProcessStartInfo pattern.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $sourceCcmSetup
$psi.Arguments = $arguments
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi
$process.Start() | Out-Null

# Drain output/error streams before waiting, then read the exit code only
# after the process has exited (ExitCode throws if read too early).
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()
$exitCode = $process.ExitCode

Write-Output " ccmsetup.exe exit code: $exitCode"
if ($stdout) {
    $stdout -split "`r?`n" | ForEach-Object { if ($_) { Write-Output " $_" } }
}
if ($stderr) {
    $stderr -split "`r?`n" | ForEach-Object { if ($_) { Write-Output " $_" } }
}

# ccmsetup returns 0 on success and 7 when a reboot is required (still success).
$installSucceeded = ($exitCode -eq 0 -or $exitCode -eq 7)
if ($installSucceeded -and (Test-Path $ccmSetupPath)) {
    if ($exitCode -eq 7) {
        Write-Output " SCCM client installed successfully; a reboot is required."
    }
    else {
        Write-Output " SCCM client installed successfully."
    }
    exit 0
}

Write-Error " SCCM client installation did not succeed (ccmsetup exit code: $exitCode)."
exit 1
