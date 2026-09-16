<#
.SYNOPSIS
    Report Microsoft Purview data loss prevention policy posture, modes and coverage gaps.

.DESCRIPTION
    Reads every DLP policy with Get-DlpCompliancePolicy -DistributionDetail and every rule with
    Get-DlpComplianceRule, then reports per policy: the enforcement mode normalised to the four
    documented policy modes (Enforce, TestWithNotifications, TestWithoutNotifications, Disabled),
    the protected locations, the distribution status and the rule count.

    The script flags disabled policies, policies in a simulation mode whose rules configure no
    alert, and policies with zero rules. With -IncludeEndpoints it additionally flags a tenant
    where no enabled policy covers endpoint devices.

    The script is strictly read-only: it never mutates tenant configuration, it only writes the
    optional report file named by -OutputPath, and it is safe to re-run.

    Exit codes: 0 = DLP posture clean; 2 = posture findings present; 1 = error.

    Grounding:
    - DLP policy and rule enforcement modes:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy
    - Get-DlpCompliancePolicy (-DistributionDetail, DistributionStatus):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpcompliancepolicy
    - Get-DlpComplianceRule (rules returned per policy):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpcompliancerule
    - DLP alerts and alert configuration in rules:
      https://learn.microsoft.com/purview/dlp-alerts-get-started

.PARAMETER PolicyName
    One or more DLP policy names to report. Wildcards are allowed. When omitted every DLP policy
    returned by the tenant is reported.

.PARAMETER IncludeEndpoints
    Also assert that at least one enabled policy covers endpoint devices, and flag the tenant when
    no policy is scoped to the endpoint DLP location.

.PARAMETER OutputFormat
    Report format: Table (console only), Json or Csv. Defaults to Table.

.PARAMETER OutputPath
    File to write when -OutputFormat is Json or Csv. When omitted the rendered report is written
    to the console instead.

.EXAMPLE
    PS C:\> .\Get-DlpPolicyPostureReport.ps1
    Reports every DLP policy with its mode, locations, rule count and posture findings.

.EXAMPLE
    PS C:\> .\Get-DlpPolicyPostureReport.ps1 -IncludeEndpoints -OutputFormat Csv `
        -OutputPath C:\Reports\dlp-posture.csv
    Writes the DLP posture report, including endpoint coverage, to a CSV file; the exit code is 2
    when any finding is present.

.NOTES
    File Name   : Get-DlpPolicyPostureReport.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$PolicyName,

    [Parameter()]
    [switch]$IncludeEndpoints,

    [Parameter()]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# DLP location name -> the *Location property the DLP policy object exposes for that location.
$script:DlpLocationMap = [ordered]@{
    Exchange          = 'ExchangeLocation'
    SharePoint        = 'SharePointLocation'
    OneDriveForBusiness = 'OneDriveLocation'
    Teams             = 'TeamsLocation'
    Endpoint          = 'EndpointDlpLocation'
    OnPremisesScanner = 'OnPremisesScannerDlpLocation'
    PowerBI           = 'PowerBIDlpLocation'
    ThirdPartyApp     = 'ThirdPartyAppDlpLocation'
}

function Write-ReportFile {
    # Thin wrapper around Out-File so report writes can be intercepted by callers and tests.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $Content | Out-File -FilePath $Path -Encoding UTF8
}

function Get-DlpPolicyLocations {
    # Maps the *Location properties of a DLP policy onto location names.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy
    )

    $covered = New-Object System.Collections.Generic.List[string]
    foreach ($location in $script:DlpLocationMap.Keys) {
        $propertyName = $script:DlpLocationMap[$location]
        $property = $Policy.PSObject.Properties[$propertyName]
        if ($null -eq $property) { continue }
        $value = $property.Value
        if ($null -eq $value) { continue }
        if (@($value).Count -eq 0) { continue }
        if ([string]::IsNullOrWhiteSpace((@($value) -join ''))) { continue }
        $covered.Add($location)
    }

    return $covered.ToArray()
}

function Get-NormalizedDlpMode {
    # Collapses the tenant Mode values onto the four documented policy modes.
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Mode
    )

    if ([string]::IsNullOrWhiteSpace($Mode)) { return 'Unknown' }
    switch ($Mode) {
        'Enable' { return 'Enforce' }
        'Enforce' { return 'Enforce' }
        'TestWithNotifications' { return 'TestWithNotifications' }
        'TestWithoutNotifications' { return 'TestWithoutNotifications' }
        'Disable' { return 'Disabled' }
        'Disabled' { return 'Disabled' }
        default { return $Mode }
    }
}

function Test-AlertConfigured {
    # True when at least one rule of the policy configures an alert recipient.
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Rule
    )

    foreach ($candidate in $Rule) {
        $property = $candidate.PSObject.Properties['GenerateAlert']
        if ($null -eq $property) { continue }
        $value = $property.Value
        if ($null -eq $value) { continue }
        if (@($value).Count -eq 0) { continue }
        if ([string]::IsNullOrWhiteSpace((@($value) -join ''))) { continue }
        return $true
    }

    return $false
}

function Test-PolicyNameMatch {
    # Applies the -PolicyName wildcard filters; an empty filter matches every policy.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [string[]]$Pattern
    )

    if ($null -eq $Pattern -or @($Pattern).Count -eq 0) { return $true }
    foreach ($candidate in $Pattern) {
        if ($Name -like $candidate) { return $true }
    }

    return $false
}

function New-DlpPolicyRecord {
    # Collapses a DLP policy and its rules into the row shape the report renders.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy,

        [Parameter()]
        [object[]]$Rule
    )

    [pscustomobject]@{
        Name               = $Policy.Name
        Mode               = Get-NormalizedDlpMode -Mode $Policy.Mode
        Enabled            = [bool]$Policy.Enabled
        DistributionStatus = $Policy.DistributionStatus
        Locations          = (Get-DlpPolicyLocations -Policy $Policy)
        RuleCount          = @($Rule).Count
        AlertConfigured    = (Test-AlertConfigured -Rule $Rule)
        Rules              = @($Rule)
    }
}

function Main {
    try {
        Write-Host "[*] Checking the Security & Compliance PowerShell session..." -ForegroundColor Cyan
        if (-not (Get-Command Connect-IPPSSession -ErrorAction SilentlyContinue)) {
            throw ('Connect-IPPSSession is not available. Install the ExchangeOnlineManagement ' +
                'module and try again.')
        }
        Connect-IPPSSession -ErrorAction Stop | Out-Null

        Write-Host "[*] Retrieving DLP policies..." -ForegroundColor Cyan
        $policies = @(Get-DlpCompliancePolicy -DistributionDetail -ErrorAction Stop)

        Write-Host "[*] Retrieving DLP rules..." -ForegroundColor Cyan
        $rules = @(Get-DlpComplianceRule -ErrorAction Stop)

        $records = New-Object System.Collections.Generic.List[object]
        foreach ($policy in $policies) {
            if (-not (Test-PolicyNameMatch -Name $policy.Name -Pattern $PolicyName)) { continue }
            $policyRules = @($rules | Where-Object { $_.Policy -eq $policy.Name })
            $records.Add((New-DlpPolicyRecord -Policy $policy -Rule $policyRules))
        }

        $disabled = @($records |
            Where-Object { $_.Mode -eq 'Disabled' -or -not $_.Enabled })
        $silentTestMode = @($records |
            Where-Object { $_.Mode -in @('TestWithNotifications', 'TestWithoutNotifications') } |
            Where-Object { -not $_.AlertConfigured })
        $zeroRulePolicies = @($records | Where-Object { $_.RuleCount -eq 0 })

        $endpointCovered = $false
        foreach ($record in $records) {
            if (-not $record.Enabled) { continue }
            if (@($record.Locations) -contains 'Endpoint') { $endpointCovered = $true }
        }

        $findings = New-Object System.Collections.Generic.List[string]
        foreach ($record in $disabled) {
            $findings.Add(('{0}: policy is disabled' -f $record.Name))
        }
        foreach ($record in $silentTestMode) {
            $findings.Add(('{0}: test mode with no alerting rules' -f $record.Name))
        }
        foreach ($record in $zeroRulePolicies) {
            $findings.Add(('{0}: no DLP rules' -f $record.Name))
        }
        if ($IncludeEndpoints -and -not $endpointCovered) {
            $findings.Add('endpoint devices: no enabled DLP policy covers them')
        }

        $summary = [pscustomobject]@{
            Matched         = $records.Count
            Disabled        = $disabled.Count
            SilentTestMode  = $silentTestMode.Count
            ZeroRules       = $zeroRulePolicies.Count
            EndpointCovered = $endpointCovered
            Findings        = $findings.Count
        }

        Write-Host ''
        foreach ($record in $records) {
            Write-Host ('    {0} mode={1} enabled={2} distribution={3} rules={4} locations={5}' -f `
                    $record.Name, $record.Mode, $record.Enabled, $record.DistributionStatus, `
                    $record.RuleCount, ((@($record.Locations)) -join ';'))
            foreach ($rule in $record.Rules) {
                Write-Host ('        rule {0}: disabled={1} mode={2}' -f `
                        $rule.Name, $rule.Disabled, $rule.Mode)
            }
        }
        Write-Host ''
        Write-Host ('Policies matched                  : {0}' -f $summary.Matched) `
            -ForegroundColor Cyan
        Write-Host ('Disabled policies                 : {0}' -f $summary.Disabled) `
            -ForegroundColor Cyan
        Write-Host ('Test-mode policies without alerts : {0}' -f $summary.SilentTestMode) `
            -ForegroundColor Cyan
        Write-Host ('Policies with zero rules          : {0}' -f $summary.ZeroRules) `
            -ForegroundColor Cyan
        if ($IncludeEndpoints) {
            $endpointText = 'Not covered'
            if ($endpointCovered) { $endpointText = 'Covered' }
            Write-Host ('Endpoint coverage                 : {0}' -f $endpointText) `
                -ForegroundColor Cyan
        }

        $policyRows = @($records | ForEach-Object {
                [pscustomobject]@{
                    Name               = $_.Name
                    Mode               = $_.Mode
                    Enabled            = $_.Enabled
                    DistributionStatus = $_.DistributionStatus
                    RuleCount          = $_.RuleCount
                    AlertConfigured    = $_.AlertConfigured
                    Locations          = (@($_.Locations) -join ';')
                    Rules              = (@($_.Rules | ForEach-Object {
                                '{0} (disabled={1}/mode={2})' -f $_.Name, $_.Disabled, $_.Mode
                            }) -join '; ')
                }
            })
        $report = [pscustomobject]@{
            GeneratedAt = (Get-Date).ToString('s')
            Summary     = $summary
            Policies    = $policyRows
            Findings    = @($findings)
        }

        $rendered = ''
        if ($OutputFormat -eq 'Json') {
            $rendered = $report | ConvertTo-Json -Depth 5
        }
        elseif ($OutputFormat -eq 'Csv') {
            $rendered = (@($policyRows) | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
        }

        if (-not [string]::IsNullOrWhiteSpace($rendered)) {
            if ([string]::IsNullOrWhiteSpace($OutputPath)) {
                Write-Host $rendered
            }
            else {
                Write-ReportFile -Path $OutputPath -Content $rendered
                Write-Host ('[+] Report written to {0}' -f $OutputPath) -ForegroundColor Green
            }
        }

        if ($findings.Count -gt 0) {
            Write-Host ''
            foreach ($finding in $findings) {
                Write-Host "[!] $finding" -ForegroundColor Yellow
            }
            Write-Host ('[!] DLP posture findings: {0}' -f $findings.Count) -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] DLP policy posture is clean" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }