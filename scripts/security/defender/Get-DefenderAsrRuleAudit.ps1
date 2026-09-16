<#
.SYNOPSIS
    Audit Microsoft Defender attack surface reduction (ASR) rule modes per managed device.

.DESCRIPTION
    Reads every onboarded device from the Microsoft Defender for Endpoint API and reports, per
    device, the state of the documented ASR rules against the rule GUIDs published in the ASR
    rules reference.

    Endpoints called (all read-only):
    - GET /api/machines                                         device inventory
    - GET /api/machines/SecureConfigurationsAssessmentByMachine per-device configuration
                                                                assessment

    The secure configuration assessment returns one row per device and configuration together
    with IsApplicable and IsCompliant. A rule the assessment marks as not applicable is reported
    as NotApplicable, an applicable rule that is compliant with the recommended Block
    configuration is reported as Block, an applicable rule that is not compliant is reported as
    Off, and a rule with no assessment row for the device is reported as NotConfigured. The
    portal-only audit-mode and warn-mode distinctions are not exposed by this API.

    Every rule that Microsoft recommends in Block mode (the standard protection rules) that is
    Off or NotConfigured is flagged, as is every device on which no ASR rule is in Block mode.
    -MachineName narrows the audit to devices whose DNS name matches the wildcard pattern; the
    default '*' audits every device.

    The script is strictly read-only: it never mutates tenant or device configuration, it only
    writes the optional report file named by -OutputPath, and it is safe to re-run.

    Exit codes: 0 = ASR posture compliant; 2 = findings present; 1 = error.

    Grounding:
    - ASR rules reference (per-rule GUID values and categories):
      https://learn.microsoft.com/defender-endpoint/attack-surface-reduction-rules-reference
    - ASR rules overview (standard protection rules and rule GUIDs):
      https://learn.microsoft.com/defender-endpoint/attack-surface-reduction-rules-overview
    - Enable and configure ASR rules:
      https://learn.microsoft.com/defender-endpoint/enable-attack-surface-reduction
    - GET /api/machines (Machine.Read.All):
      https://learn.microsoft.com/defender-endpoint/api/get-machines
    - GET /api/machines/SecureConfigurationsAssessmentByMachine (Vulnerability.Read.All):
      https://learn.microsoft.com/defender-endpoint/api/get-assessment-secure-config

.PARAMETER MachineName
    Wildcard pattern matched against each device's DNS name. Defaults to '*', which audits every
    onboarded device.

.PARAMETER OutputFormat
    Report format: Table (console only), Json or Csv. Defaults to Table.

.PARAMETER OutputPath
    File to write when -OutputFormat is Json or Csv. When omitted the rendered report is written
    to the console instead.

.EXAMPLE
    PS C:\> .\Get-DefenderAsrRuleAudit.ps1
    Reports every onboarded device with the state of each documented ASR rule and flags the
    recommended-Block rules that are not enforcing.

.EXAMPLE
    PS C:\> .\Get-DefenderAsrRuleAudit.ps1 -MachineName 'FIN-*' -OutputFormat Csv `
        -OutputPath C:\Reports\asr-audit.csv
    Writes the ASR rule audit for the finance devices to a CSV file; the exit code is 2 when any
    finding is present.

.NOTES
    File Name   : Get-DefenderAsrRuleAudit.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$MachineName = '*',

    [Parameter()]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Defender for Endpoint API base URI, documented in api/exposed-apis-list.
$script:DefenderApiBaseUri = 'https://api.security.microsoft.com'

# Application permissions required by the endpoints this script calls.
$script:DefenderRequiredScopes = @(
    'Vulnerability.Read.All'
    'Machine.Read.All'
)

# Documented page ceilings: 10,000 for /api/machines, 200,000 for the assessment export.
$script:MachinePageSize = 10000
$script:AssessmentPageSize = 200000

# The documented ASR rules from the ASR rules reference: GUID, display name, and whether
# Microsoft recommends enabling the rule in Block mode (the standard protection rules).
$script:AsrRules = @(
    [pscustomobject]@{
        Guid             = '56a863a9-875e-4185-98a7-b882c64b5ce5'
        Name             = 'Block abuse of exploited vulnerable signed drivers'
        RecommendedBlock = $true
    }
    [pscustomobject]@{
        Guid             = '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2'
        Name             = ('Block credential stealing from the Windows local security ' +
            'authority subsystem')
        RecommendedBlock = $true
    }
    [pscustomobject]@{
        Guid             = 'e6db77e5-3df2-4cf1-b95a-636979351e5b'
        Name             = 'Block persistence through WMI event subscription'
        RecommendedBlock = $true
    }
    [pscustomobject]@{
        Guid             = '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c'
        Name             = 'Block Adobe Reader from creating child processes'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = 'd4f940ab-401b-4efc-aadc-ad5f3c50688a'
        Name             = 'Block all Office applications from creating child processes'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = 'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550'
        Name             = 'Block executable content from email client and webmail'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = '01443614-cd74-433a-b99e-2ecdc07bfc25'
        Name             = ('Block executable files from running unless they meet a prevalence, ' +
            'age, or trusted list criterion')
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = '5beb7efe-fd9a-4556-801d-275e5ffc04cc'
        Name             = 'Block execution of potentially obfuscated scripts'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = 'd3e037e1-3eb8-44c8-a917-57927947596d'
        Name             = ('Block JavaScript or VBScript from launching downloaded ' +
            'executable content')
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = '3b576869-a4ec-4529-8536-b80a7769e899'
        Name             = 'Block Office applications from creating executable content'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84'
        Name             = 'Block Office applications from injecting code into other processes'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = '26190899-1602-49e8-8b27-eb1d0a1ce869'
        Name             = 'Block Office communication application from creating child processes'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = 'd1e49aac-8f56-4280-b9ba-993a6d77406c'
        Name             = 'Block process creations originating from PSExec and WMI commands'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = '33ddedf1-c6e0-47cb-833e-de6133960387'
        Name             = 'Block rebooting machine in Safe Mode'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = 'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4'
        Name             = 'Block untrusted and unsigned processes that run from USB'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = 'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb'
        Name             = 'Block use of copied or impersonated system tools'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = 'a8f5898e-1dc8-49a9-9878-85004b8a61e6'
        Name             = 'Block Webshell creation for Servers'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b'
        Name             = 'Block Win32 API calls from Office macros'
        RecommendedBlock = $false
    }
    [pscustomobject]@{
        Guid             = 'c1db55ab-c21a-4637-bb3f-a12568109d35'
        Name             = 'Use advanced protection against ransomware'
        RecommendedBlock = $false
    }
)

function Invoke-DefenderApi {
    # Thin wrapper over Invoke-MgGraphRequest so every API call has a single mockable seam.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('GET', 'POST')]
        [string]$Method = 'GET'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'The Defender for Endpoint API path must not be empty.'
    }

    $uri = $Path
    if (-not $uri.StartsWith('http', [System.StringComparison]::OrdinalIgnoreCase)) {
        $uri = '{0}/{1}' -f $script:DefenderApiBaseUri, $uri.TrimStart('/')
    }

    return Invoke-MgGraphRequest -Method $Method -Uri $uri -OutputType PSObject -ErrorAction Stop
}

function Get-DefenderApiCollection {
    # Resolves a collection endpoint and follows @odata.nextLink until the export is complete.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $items = New-Object System.Collections.Generic.List[object]
    $response = Invoke-DefenderApi -Path $Path
    while ($null -ne $response) {
        $valueProperty = $response.PSObject.Properties['value']
        if ($null -ne $valueProperty -and $null -ne $valueProperty.Value) {
            foreach ($item in @($valueProperty.Value)) { $items.Add($item) }
        }

        $nextLink = $null
        $nextProperty = $response.PSObject.Properties['@odata.nextLink']
        if ($null -ne $nextProperty) { $nextLink = $nextProperty.Value }
        if ([string]::IsNullOrWhiteSpace($nextLink)) { break }

        $response = Invoke-DefenderApi -Path $nextLink
    }

    return $items.ToArray()
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

function Test-MachineNameMatch {
    # Applies the -MachineName wildcard filter; the default '*' matches every device.
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Pattern = '*'
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) { return $true }
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    return ($Name -like $Pattern)
}

function Get-AsrRuleMode {
    # Maps the secure configuration assessment row of a rule onto its reported mode.
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Assessment
    )

    if ($null -eq $Assessment) { return 'NotConfigured' }

    $applicable = $Assessment.PSObject.Properties['IsApplicable']
    if ($null -ne $applicable -and $null -ne $applicable.Value -and -not [bool]$applicable.Value) {
        return 'NotApplicable'
    }

    $compliant = $Assessment.PSObject.Properties['IsCompliant']
    if ($null -ne $compliant -and $null -ne $compliant.Value -and [bool]$compliant.Value) {
        return 'Block'
    }

    return 'Off'
}

function Main {
    try {
        Write-Host '[*] Checking the Microsoft Graph session...' -ForegroundColor Cyan
        if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
            throw ('Microsoft.Graph.Authentication is not available. Install-Module ' +
                'Microsoft.Graph.Authentication and try again.')
        }
        Connect-MgGraph -Scopes $script:DefenderRequiredScopes -NoWelcome -ErrorAction Stop

        Write-Host '[*] Retrieving onboarded devices...' -ForegroundColor Cyan
        $machines = Get-DefenderApiCollection -Path ('/api/machines?$top={0}' -f `
                $script:MachinePageSize)

        Write-Host '[*] Retrieving secure configuration assessments...' -ForegroundColor Cyan
        $assessments = Get-DefenderApiCollection -Path `
            ('/api/machines/SecureConfigurationsAssessmentByMachine?pageSize={0}' -f `
                $script:AssessmentPageSize)

        $assessmentIndex = @{}
        foreach ($row in $assessments) {
            if ($null -eq $row.DeviceId -or $null -eq $row.ConfigurationId) { continue }
            $deviceKey = ([string]$row.DeviceId).ToLowerInvariant()
            $configKey = ([string]$row.ConfigurationId).ToLowerInvariant()
            if (-not $assessmentIndex.ContainsKey($deviceKey)) { $assessmentIndex[$deviceKey] = @{} }
            $assessmentIndex[$deviceKey][$configKey] = $row
        }

        $records = New-Object System.Collections.Generic.List[object]
        foreach ($machine in $machines) {
            if (-not (Test-MachineNameMatch -Name $machine.computerDnsName -Pattern $MachineName)) {
                continue
            }

            $deviceKey = ([string]$machine.id).ToLowerInvariant()
            $ruleStates = New-Object System.Collections.Generic.List[object]
            foreach ($rule in $script:AsrRules) {
                $assessment = $null
                $configKey = $rule.Guid.ToLowerInvariant()
                if ($assessmentIndex.ContainsKey($deviceKey) -and
                    $assessmentIndex[$deviceKey].ContainsKey($configKey)) {
                    $assessment = $assessmentIndex[$deviceKey][$configKey]
                }

                $ruleStates.Add([pscustomobject]@{
                        Rule             = $rule.Name
                        Guid             = $rule.Guid
                        Mode             = (Get-AsrRuleMode -Assessment $assessment)
                        RecommendedBlock = $rule.RecommendedBlock
                    })
            }

            $records.Add([pscustomobject]@{
                    Device       = $machine.computerDnsName
                    DeviceId     = $machine.id
                    HealthStatus = $machine.healthStatus
                    Rules        = $ruleStates.ToArray()
                })
        }

        $findings = New-Object System.Collections.Generic.List[string]
        $totals = @{ Block = 0; Off = 0; NotConfigured = 0; NotApplicable = 0 }
        foreach ($record in $records) {
            foreach ($state in $record.Rules) {
                $totals[$state.Mode] = $totals[$state.Mode] + 1
            }

            $blocked = @($record.Rules | Where-Object { $_.Mode -eq 'Block' })
            if ($blocked.Count -eq 0) {
                $findings.Add(('{0}: no ASR rule is in Block mode' -f $record.Device))
            }

            foreach ($state in $record.Rules) {
                if (-not $state.RecommendedBlock) { continue }
                if ($state.Mode -eq 'Block' -or $state.Mode -eq 'NotApplicable') { continue }
                $findings.Add(('{0}: {1} is {2} (Microsoft recommends Block)' -f `
                            $record.Device, $state.Rule, $state.Mode))
            }
        }

        $summary = [pscustomobject]@{
            DevicesAudited = $records.Count
            RulesEvaluated = @($script:AsrRules).Count
            Block          = $totals['Block']
            Off            = $totals['Off']
            NotConfigured  = $totals['NotConfigured']
            NotApplicable  = $totals['NotApplicable']
            Findings       = $findings.Count
        }

        Write-Host ''
        foreach ($record in $records) {
            $deviceStates = @($record.Rules | Group-Object -Property Mode)
            $modeText = (@($deviceStates | ForEach-Object {
                        '{0}={1}' -f $_.Name, $_.Count
                    }) -join ' ')
            Write-Host ('    {0} health={1} {2}' -f `
                    $record.Device, $record.HealthStatus, $modeText)
            foreach ($state in $record.Rules) {
                if (-not $state.RecommendedBlock) { continue }
                Write-Host ('        recommended {0}: {1}' -f $state.Rule, $state.Mode)
            }
        }
        Write-Host ''
        Write-Host ('Devices audited           : {0}' -f $summary.DevicesAudited) `
            -ForegroundColor Cyan
        Write-Host ('ASR rules evaluated       : {0}' -f $summary.RulesEvaluated) `
            -ForegroundColor Cyan
        Write-Host ('Rules in Block mode       : {0}' -f $summary.Block) -ForegroundColor Cyan
        Write-Host ('Rules off                 : {0}' -f $summary.Off) -ForegroundColor Cyan
        Write-Host ('Rules not configured      : {0}' -f $summary.NotConfigured) `
            -ForegroundColor Cyan
        Write-Host ('Rules not applicable      : {0}' -f $summary.NotApplicable) `
            -ForegroundColor Cyan

        $deviceRows = @($records | ForEach-Object {
                [pscustomobject]@{
                    Device       = $_.Device
                    DeviceId     = $_.DeviceId
                    HealthStatus = $_.HealthStatus
                    Block        = @($_.Rules | Where-Object { $_.Mode -eq 'Block' }).Count
                    Off          = @($_.Rules | Where-Object { $_.Mode -eq 'Off' }).Count
                    NotConfigured = @($_.Rules |
                            Where-Object { $_.Mode -eq 'NotConfigured' }).Count
                    NotApplicable = @($_.Rules |
                            Where-Object { $_.Mode -eq 'NotApplicable' }).Count
                    Rules        = (@($_.Rules | ForEach-Object {
                                '{0} ({1})' -f $_.Rule, $_.Mode
                            }) -join '; ')
                }
            })

        $report = [pscustomobject]@{
            GeneratedAt = (Get-Date).ToString('s')
            Summary     = $summary
            Devices     = $deviceRows
            Findings    = @($findings)
        }

        $rendered = ''
        if ($OutputFormat -eq 'Json') {
            $rendered = $report | ConvertTo-Json -Depth 5
        }
        elseif ($OutputFormat -eq 'Csv') {
            $rendered = (@($deviceRows) | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
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
            Write-Host ('[!] ASR rule findings: {0}' -f $findings.Count) -ForegroundColor Yellow
            return 2
        }

        Write-Host '[+] ASR rule posture is compliant' -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
