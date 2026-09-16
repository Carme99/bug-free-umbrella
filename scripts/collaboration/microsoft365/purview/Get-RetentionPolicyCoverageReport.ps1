<#
.SYNOPSIS
    Report Microsoft Purview retention policy coverage, distribution and configuration gaps.

.DESCRIPTION
    Reads every retention policy with Get-RetentionCompliancePolicy -DistributionDetail
    -RetentionRuleTypes and every rule with Get-RetentionComplianceRule, then reports per policy:
    the workloads it covers, its rule count, each rule's retention duration and retention action,
    and the policy distribution status. With -IncludeAppPolicies the newer app retention
    policies are added with Get-AppRetentionCompliancePolicy, together with their rules read with
    the paired Get-AppRetentionComplianceRule cmdlet; with -IncludeLabels the Get-ComplianceTag
    labels are read and labels that no policy publishes are reported.

    The script flags policies whose distribution status is not Complete, policies with zero rules,
    workloads that no enabled policy covers, and labels that no retention policy publishes. It is
    strictly read-only: it never mutates tenant configuration, it only writes the optional report
    file named by -OutputPath, and it is safe to re-run.

    Exit codes: 0 = report produced and coverage complete; 2 = coverage gaps found; 1 = error.

    Grounding:
    - PowerShell cmdlets for retention policies and labels:
      https://learn.microsoft.com/purview/retention-cmdlets
    - Retention policies, locations and labels:
      https://learn.microsoft.com/purview/create-retention-policies
    - Get-RetentionCompliancePolicy (-DistributionDetail, -RetentionRuleTypes):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancepolicy
    - Get-RetentionComplianceRule (rule duration and action):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancerule
    - Get-AppRetentionCompliancePolicy and Get-AppRetentionComplianceRule (app policies and the
      rules that belong to them):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-appretentioncompliancerule

.PARAMETER PolicyName
    One or more retention policy names to report. Wildcards are allowed. When omitted every
    retention policy returned by the tenant is reported.

.PARAMETER IncludeAppPolicies
    Also report app retention policies read with Get-AppRetentionCompliancePolicy, with the rules
    of those policies read with Get-AppRetentionComplianceRule. App retention policies cover the
    newer locations (Teams chats, Teams channel messages, Viva Engage and the Copilot/AI apps).

.PARAMETER IncludeLabels
    Also read Get-ComplianceTag and report every retention label that no retention policy rule
    publishes. Without this switch labels are not queried.

.PARAMETER OutputFormat
    Report format: Table (console only), Json or Csv. Defaults to Table.

.PARAMETER OutputPath
    File to write when -OutputFormat is Json or Csv. When omitted the rendered report is written
    to the console instead.

.EXAMPLE
    PS C:\> .\Get-RetentionPolicyCoverageReport.ps1
    Reports every retention policy with its rules, distribution status and workload coverage.

.EXAMPLE
    PS C:\> .\Get-RetentionPolicyCoverageReport.ps1 -IncludeAppPolicies -IncludeLabels `
        -OutputFormat Csv -OutputPath C:\Reports\retention-coverage.csv
    Writes the full coverage report, including app policies and unpublished labels, to a CSV
    file; the exit code is 2 when any coverage gap is found.

.NOTES
    File Name   : Get-RetentionPolicyCoverageReport.ps1
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
    [switch]$IncludeAppPolicies,

    [Parameter()]
    [switch]$IncludeLabels,

    [Parameter()]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Workload name -> the *Location property the retention policy object exposes for that workload.
$script:WorkloadLocationMap = [ordered]@{
    Exchange             = 'ExchangeLocation'
    SharePoint           = 'SharePointLocation'
    OneDriveForBusiness  = 'OneDriveLocation'
    ModernGroup          = 'ModernGroupLocation'
    Skype                = 'SkypeLocation'
    ExchangePublicFolder = 'PublicFolderLocation'
    TeamsChannel         = 'TeamsChannelLocation'
    TeamsChat            = 'TeamsChatLocation'
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

function Get-PolicyWorkloads {
    # Maps the *Location properties of a retention policy onto workload names.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy
    )

    $covered = New-Object System.Collections.Generic.List[string]
    foreach ($workload in $script:WorkloadLocationMap.Keys) {
        $propertyName = $script:WorkloadLocationMap[$workload]
        $property = $Policy.PSObject.Properties[$propertyName]
        if ($null -eq $property) { continue }
        $value = $property.Value
        if ($null -eq $value) { continue }
        if (@($value).Count -eq 0) { continue }
        if ([string]::IsNullOrWhiteSpace((@($value) -join ''))) { continue }
        $covered.Add($workload)
    }

    return $covered.ToArray()
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

function New-PolicyRecord {
    # Collapses a policy and its rules into the row shape the report renders.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter()]
        [object[]]$Rule
    )

    [pscustomobject]@{
        Name               = $Policy.Name
        Source             = $Source
        Enabled            = [bool]$Policy.Enabled
        Mode               = $Policy.Mode
        DistributionStatus = $Policy.DistributionStatus
        Workloads          = (Get-PolicyWorkloads -Policy $Policy)
        RuleCount          = @($Rule).Count
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

        Write-Host "[*] Retrieving retention policies..." -ForegroundColor Cyan
        $policies = @(Get-RetentionCompliancePolicy -DistributionDetail -RetentionRuleTypes `
                -ErrorAction Stop)

        Write-Host "[*] Retrieving retention rules..." -ForegroundColor Cyan
        $rules = @(Get-RetentionComplianceRule -ErrorAction Stop)

        $appPolicies = @()
        $appRules = @()
        if ($IncludeAppPolicies) {
            Write-Host "[*] Retrieving app retention policies..." -ForegroundColor Cyan
            $appPolicies = @(Get-AppRetentionCompliancePolicy -DistributionDetail `
                    -RetentionRuleTypes -ErrorAction Stop)
            Write-Host "[*] Retrieving app retention rules..." -ForegroundColor Cyan
            $appRules = @(Get-AppRetentionComplianceRule -ErrorAction Stop)
        }
        $allRules = @($rules) + @($appRules)

        $records = New-Object System.Collections.Generic.List[object]
        foreach ($policy in $policies) {
            if (-not (Test-PolicyNameMatch -Name $policy.Name -Pattern $PolicyName)) { continue }
            $policyRules = @($rules | Where-Object { $_.Policy -eq $policy.Name })
            $records.Add((New-PolicyRecord -Policy $policy -Source 'Retention' -Rule $policyRules))
        }
        foreach ($policy in $appPolicies) {
            if (-not (Test-PolicyNameMatch -Name $policy.Name -Pattern $PolicyName)) { continue }
            $policyRules = @($appRules | Where-Object { $_.Policy -eq $policy.Name })
            $records.Add((New-PolicyRecord -Policy $policy -Source 'App' -Rule $policyRules))
        }

        $unpublishedLabels = @()
        if ($IncludeLabels) {
            Write-Host "[*] Retrieving retention labels..." -ForegroundColor Cyan
            $labels = @(Get-ComplianceTag -ErrorAction Stop)
            foreach ($label in $labels) {
                $published = $false
                foreach ($rule in $allRules) {
                    $property = $rule.PSObject.Properties['PublishComplianceTag']
                    if ($null -eq $property) { continue }
                    if (@($property.Value) -contains $label.Name) {
                        $published = $true
                        break
                    }
                }
                if (-not $published) { $unpublishedLabels += $label.Name }
            }
        }

        $coveredWorkloads = New-Object System.Collections.Generic.HashSet[string]
        foreach ($record in $records) {
            if (-not $record.Enabled) { continue }
            foreach ($workload in $record.Workloads) { [void]$coveredWorkloads.Add($workload) }
        }
        $uncovered = @($script:WorkloadLocationMap.Keys |
            Where-Object { -not $coveredWorkloads.Contains($_) })
        $notDistributed = @($records |
            Where-Object { $_.DistributionStatus -and $_.DistributionStatus -ne 'Complete' })
        $zeroRulePolicies = @($records | Where-Object { $_.RuleCount -eq 0 })

        $findings = New-Object System.Collections.Generic.List[string]
        foreach ($record in $notDistributed) {
            $findings.Add(('{0}: distribution status {1}' -f $record.Name, $record.DistributionStatus))
        }
        foreach ($record in $zeroRulePolicies) {
            $findings.Add(('{0}: no retention rules' -f $record.Name))
        }
        foreach ($workload in $uncovered) {
            $findings.Add(('uncovered workload: {0}' -f $workload))
        }
        foreach ($label in $unpublishedLabels) {
            $findings.Add(('{0}: label published to no retention policy' -f $label))
        }

        $summary = [pscustomobject]@{
            Matched            = $records.Count
            NotDistributed     = $notDistributed.Count
            ZeroRules          = $zeroRulePolicies.Count
            UncoveredWorkloads = $uncovered.Count
            UnpublishedLabels  = $unpublishedLabels.Count
            Gaps               = $findings.Count
        }

        Write-Host ''
        foreach ($record in $records) {
            Write-Host ('    {0} [{1}] mode={2} enabled={3} distribution={4} rules={5}' -f `
                    $record.Name, $record.Source, $record.Mode, $record.Enabled, `
                    $record.DistributionStatus, $record.RuleCount)
            foreach ($rule in $record.Rules) {
                Write-Host ('        rule {0}: duration={1} action={2}' -f `
                        $rule.Name, $rule.RetentionDuration, $rule.RetentionComplianceAction)
            }
        }
        Write-Host ''
        Write-Host ('Policies matched             : {0}' -f $summary.Matched) -ForegroundColor Cyan
        Write-Host ('Policies not distributed     : {0}' -f $summary.NotDistributed) `
            -ForegroundColor Cyan
        Write-Host ('Policies with zero rules     : {0}' -f $summary.ZeroRules) -ForegroundColor Cyan
        Write-Host ('Uncovered workloads          : {0}' -f $summary.UncoveredWorkloads) `
            -ForegroundColor Cyan
        if ($IncludeLabels) {
            Write-Host ('Labels published to no policy: {0}' -f $summary.UnpublishedLabels) `
                -ForegroundColor Cyan
        }

        $policyRows = @($records | ForEach-Object {
                [pscustomobject]@{
                    Name               = $_.Name
                    Source             = $_.Source
                    Mode               = $_.Mode
                    Enabled            = $_.Enabled
                    DistributionStatus = $_.DistributionStatus
                    RuleCount          = $_.RuleCount
                    Workloads          = (@($_.Workloads) -join ';')
                    Rules              = (@($_.Rules | ForEach-Object {
                                '{0} ({1}/{2})' -f $_.Name, $_.RetentionDuration,
                                $_.RetentionComplianceAction
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
            Write-Host ('[!] Retention coverage gaps: {0}' -f $findings.Count) -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] Retention policy coverage is complete" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }