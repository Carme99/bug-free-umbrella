<#
.SYNOPSIS
    Pre-flight a Windows Autopilot hardware hash CSV before it is imported into Intune.

.DESCRIPTION
    Reads the comma-separated-values file named by -CsvPath and validates it against the
    documented Windows Autopilot manual registration rules
    (https://learn.microsoft.com/autopilot/add-devices):

    - the exact header set and order Device Serial Number, Windows Product ID, Hardware Hash,
      Group Tag, Assigned User, matched case-sensitively;
    - no extra columns and no quotation marks anywhere in the file;
    - ANSI-format text only, so a UTF-8 or UTF-16 byte-order mark is a finding;
    - no duplicate serial numbers and no duplicate hardware hashes;
    - a group tag length pre-flight limit (the published guidance does not state a numeric
      maximum, so this script applies a conservative 64-character guard for persona tags);
    - a row count within the documented 500-device manual import batch, or the configured
      -MaxBatchSize when that is lower.

    The script then reports a per-row pre-flight verdict, predicts the Autopilot registration
    error a row would raise (InvalidZtdHardwareHash, ZtdDeviceDuplicated) and lists the errors
    that can only be detected at import time against tenant state (ZtdDeviceAlreadyAssigned,
    ZtdDeviceAssignedToAnotherTenant, StorageError). The CSV is read with Import-Csv
    (https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/import-csv).

    The script never contacts Intune and never registers a device. It only reads the CSV and
    writes the reconciliation CSV named by -OutputPath with Export-Csv
    (https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/export-csv).
    -OutputPath defaults into the system temp directory, so an unqualified run never adds a file
    to the current working directory.
    Exit codes: 0 = file valid; 2 = validation findings; 1 = the file is missing or unreadable.

.PARAMETER CsvPath
    Path to the hardware hash CSV to validate. Required.

.PARAMETER MaxBatchSize
    Maximum number of device rows allowed in one import batch, 1 to 500. Defaults to 500, the
    documented manual import limit.

.PARAMETER OutputPath
    Path of the reconciliation CSV that is always written. Defaults to
    AutopilotHardwareHashReconciliation.csv in the system temp directory ($env:TEMP, or the
    platform temp path when that variable is unset). The script never writes into the current
    working directory unless -OutputPath points there explicitly.

.EXAMPLE
    PS C:\> .\Test-AutopilotHardwareHashCsv.ps1 -CsvPath C:\HWID\AutopilotHWID.csv
    Validates the CSV, prints the per-row verdict and writes the reconciliation CSV.

.EXAMPLE
    PS C:\> .\Test-AutopilotHardwareHashCsv.ps1 -CsvPath .\batch2.csv -MaxBatchSize 100 `
        -OutputPath C:\Reports\batch2-reconciliation.csv
    Validates the CSV against a 100-row batch limit and writes the reconciliation elsewhere.

.EXAMPLE
    PS C:\> .\Test-AutopilotHardwareHashCsv.ps1 -CsvPath .\batch2.csv
    Returns exit code 2 when the file has a header, duplicate or encoding finding.

.NOTES
   File Name   : Test-AutopilotHardwareHashCsv.ps1
   Author      : Bug-Free Umbrella
   Prerequisite: PowerShell 7.0
   Version     : 2.0.0
   Date        : 2026-09-16
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 500)]
    [int]$MaxBatchSize = 500,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([IO.Path]::GetTempPath()) 'AutopilotHardwareHashReconciliation.csv')
)

$ErrorActionPreference = 'Stop'

# The published Autopilot guidance does not state a numeric maximum for the Group Tag column,
# so the script applies a conservative guard: group tags drive Microsoft Entra OrderID dynamic
# membership rules and long values are a common source of typos.
$script:GroupTagMaxLength = 64

# Documented header of the multi-device hardware hash CSV. Order and casing are significant.
$script:ExpectedHeader = @(
    'Device Serial Number'
    'Windows Product ID'
    'Hardware Hash'
    'Group Tag'
    'Assigned User'
)

function Get-FileBomName {
    # Returns the byte-order-mark name of a file, or an empty string for ANSI text.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return 'UTF-8'
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return 'UTF-16 LE' }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) { return 'UTF-16 BE' }

    return ''
}

function Test-CsvHeader {
    # Returns the header findings for a CSV file, and sets $script:HeaderIsValid accordingly.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$HeaderLine)

    $actual = @($HeaderLine -split ',')
    $findings = @()
    $isValid = $true

    for ($i = 0; $i -lt $script:ExpectedHeader.Count; $i++) {
        if ($i -ge $actual.Count) {
            $findings += "Header: the '$($script:ExpectedHeader[$i])' column is missing"
            $isValid = $false
            continue
        }
        if ($actual[$i] -cne $script:ExpectedHeader[$i]) {
            $findings += ("Header: column $($i + 1) is '$($actual[$i])' but must be " +
                "'$($script:ExpectedHeader[$i])' (headers are case-sensitive)")
            $isValid = $false
        }
    }

    if ($actual.Count -gt $script:ExpectedHeader.Count) {
        $extra = @($actual | Select-Object -Skip $script:ExpectedHeader.Count)
        $findings += "Header: extra columns are not allowed: $($extra -join ', ')"
        $isValid = $false
    }

    $script:HeaderIsValid = $isValid

    return $findings
}

function Main {
    try {
        if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
            throw "Hardware hash CSV not found or is not a file: $CsvPath"
        }

        Write-Host "[*] Validating Autopilot hardware hash CSV: $CsvPath" -ForegroundColor Cyan

        $rawBytes = [IO.File]::ReadAllBytes($CsvPath)
        $rawText = [IO.File]::ReadAllText($CsvPath)

        $findings = @()

        # --- Documented file-format rules ------------------------------------------------
        $bom = Get-FileBomName -Bytes $rawBytes
        if ($bom) {
            $findings += "Encoding: a $bom byte-order mark was found; only ANSI text is allowed"
        }

        if ($rawText.Contains('"')) {
            $findings += 'Quoting: quotation marks are not allowed anywhere in the file'
        }

        $lines = @($rawText -split "\r?\n")
        $headerLine = ''
        if ($lines.Count -gt 0) { $headerLine = $lines[0] }

        $findings += Test-CsvHeader -HeaderLine $headerLine
        if ($script:HeaderIsValid) {
            Write-Host "[+] Header matches the documented five-column format" -ForegroundColor Green
        }

        # --- Rows ------------------------------------------------------------------------
        $rows = @()
        if ($script:HeaderIsValid) {
            $rows = @(Import-Csv -LiteralPath $CsvPath -ErrorAction Stop)
            Write-Host "[+] Read $($rows.Count) device row(s)" -ForegroundColor Green
        }
        else {
            Write-Host '[!] Header mismatch; row analysis skipped' -ForegroundColor Yellow
        }

        $serialCounts = @{}
        $hashCounts = @{}
        foreach ($row in $rows) {
            $serial = [string]$row.'Device Serial Number'
            $hash = [string]$row.'Hardware Hash'
            if ($serial) { $serialCounts[$serial] = [int]$serialCounts[$serial] + 1 }
            if ($hash) { $hashCounts[$hash] = [int]$hashCounts[$hash] + 1 }
        }

        $report = @()
        $hashSeen = @{}
        $number = 0
        foreach ($row in $rows) {
            $number++
            $serial = [string]$row.'Device Serial Number'
            $productId = [string]$row.'Windows Product ID'
            $hash = [string]$row.'Hardware Hash'
            $groupTag = [string]$row.'Group Tag'
            $assignedUser = [string]$row.'Assigned User'

            $rowFindings = @()
            $predictedError = ''

            if (-not $serial -or -not $hash) {
                $predictedError = 'InvalidZtdHardwareHash'
                $rowFindings += 'serial number and hardware hash are both required'
            }
            else {
                $hashSeen[$hash] = [int]$hashSeen[$hash] + 1
                if ([int]$hashSeen[$hash] -gt 1) {
                    $predictedError = 'ZtdDeviceDuplicated'
                    $rowFindings += 'duplicate hardware hash in the file'
                }
                elseif ([int]$serialCounts[$serial] -gt 1) {
                    $rowFindings += 'duplicate serial number in the file'
                }
            }

            if ($groupTag.Length -gt $script:GroupTagMaxLength) {
                $rowFindings += "group tag exceeds $($script:GroupTagMaxLength) characters"
            }

            if ($assignedUser -and ($assignedUser -notmatch '@')) {
                $rowFindings += 'assigned user is not a user principal name'
            }

            $verdict = 'Ready'
            if ($rowFindings.Count -gt 0) { $verdict = 'Review' }

            $report += [pscustomobject]@{
                Row                = $number
                DeviceSerialNumber = $serial
                WindowsProductId   = $productId
                HardwareHash       = $hash
                GroupTag           = $groupTag
                AssignedUser       = $assignedUser
                PredictedError     = $predictedError
                Verdict            = $verdict
                Notes              = ($rowFindings -join '; ')
            }
        }

        $reviewRows = @($report | Where-Object { $_.Verdict -ne 'Ready' })
        if ($reviewRows.Count -gt 0) {
            $findings += "Rows: $($reviewRows.Count) row(s) would not import cleanly"
        }

        if ($rows.Count -gt $MaxBatchSize) {
            $findings += ("Batch: $($rows.Count) rows exceed the configured batch limit of " +
                "$MaxBatchSize")
        }

        # --- Report ----------------------------------------------------------------------
        Write-Host ''
        Write-Host '=== Per-row pre-flight verdict ===' -ForegroundColor Cyan
        foreach ($entry in $report) {
            $colour = 'Green'
            if ($entry.Verdict -ne 'Ready') { $colour = 'Yellow' }
            $message = '  Row ' + $entry.Row + ': ' + $entry.DeviceSerialNumber +
                ' [' + $entry.Verdict + ']'
            if ($entry.Notes) { $message = $message + ' ' + $entry.Notes }
            Write-Host $message -ForegroundColor $colour
        }

        Write-Host ''
        Write-Host '=== Documented Autopilot registration errors ===' -ForegroundColor Cyan
        Write-Host '  InvalidZtdHardwareHash          : a hardware hash field is invalid or empty'
        Write-Host '  ZtdDeviceDuplicated             : duplicate hardware hashes in the CSV file'
        Write-Host '  ZtdDeviceAlreadyAssigned        : hash already registered to this tenant'
        Write-Host '  ZtdDeviceAssignedToAnotherTenant: hash registered to another tenant'
        Write-Host '  StorageError                    : generic import failure; retry later'

        Write-Host ''
        Write-Host "  Rows read   : $($rows.Count)" -ForegroundColor White
        Write-Host "  Batch limit : $MaxBatchSize (documented manual import limit: 500)" `
            -ForegroundColor White
        Write-Host "  Ready       : $(@($report | Where-Object { $_.Verdict -eq 'Ready' }).Count)" `
            -ForegroundColor Green
        Write-Host "  Review      : $($reviewRows.Count)" -ForegroundColor Yellow

        $report | Export-Csv -Path $OutputPath -NoTypeInformation -ErrorAction Stop
        Write-Host "[+] Reconciliation CSV written to $OutputPath" -ForegroundColor Green

        if ($findings.Count -gt 0) {
            Write-Host "[!] $($findings.Count) validation finding(s)" -ForegroundColor Yellow
            foreach ($finding in $findings) {
                Write-Host "    $finding" -ForegroundColor Yellow
            }
            return 2
        }

        Write-Host '[+] CSV is valid for Autopilot manual import' -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
