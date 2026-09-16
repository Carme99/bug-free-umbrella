<#
.SYNOPSIS
    Audits Microsoft Entra Privileged Identity Management role assignments.

.DESCRIPTION
    Reads the Microsoft Entra role assignment schedule instances and role eligibility schedule
    instances for the tenant through Microsoft Graph and classifies every assignment as
    Permanent-Active, Time-bound Active, or Eligible. It then flags role holders whose directory
    account is a guest, assignments in scope that carry no expiration, and eligible assignments
    that have been in place longer than -StaleDays without a recorded activation.
    Read-only: no assignment, eligibility, or activation is created, extended, or removed, and
    re-running the script is safe. A report file is written only when -OutputPath is supplied.
    Exit codes: 0 = no findings, 2 = findings present, 1 = error (missing module, Microsoft Graph
    failure, or unsafe -OutputPath).
    Microsoft Learn (eligible versus active PIM assignments):
    https://learn.microsoft.com/powershell/microsoftgraph/how-to-assign-microsoft-entra-roles-in-pim
    Microsoft Learn (API family):
    https://learn.microsoft.com/graph/api/rbacapplication-list-roleassignmentscheduleinstances
    Microsoft Learn (eligibility instances):
    https://learn.microsoft.com/graph/api/rbacapplication-list-roleeligibilityscheduleinstances

.PARAMETER TenantId
    Microsoft Entra tenant ID to sign in to. When omitted, the current Microsoft Graph session
    is reused and no sign-in is attempted.

.PARAMETER RoleFilter
    Role scope for the audit. 'Privileged' (the default) audits the built-in privileged role set;
    any other accepted value narrows the audit to that single role.

.PARAMETER IncludeGroups
    Includes role assignments held by groups in the report and in the findings. Without this
    switch, group-held assignments are counted but excluded from the results.

.PARAMETER StaleDays
    Number of days an eligible assignment may remain unactivated before it is reported. Default 90.

.PARAMETER OutputFormat
    Report format: Table (colored console summary, the default), Json, or Csv.

.PARAMETER OutputPath
    File to write the report to. When omitted, Json and Csv reports are written to the pipeline
    and Table output stays on the console.

.EXAMPLE
    PS C:\> .\Get-PimRoleAssignmentAudit.ps1 -TenantId 'contoso.onmicrosoft.com'
    Audits the built-in privileged role set and exits 2 when findings exist.

.EXAMPLE
    PS C:\> .\Get-PimRoleAssignmentAudit.ps1 -RoleFilter 'Global Administrator' -StaleDays 60 -IncludeGroups
    Narrows the audit to Global Administrator, uses a 60-day staleness threshold, and includes
    group-held assignments.

.NOTES
    File Name   : Get-PimRoleAssignmentAudit.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [ValidateSet('Privileged', 'Global Administrator', 'Privileged Role Administrator',
        'Privileged Authentication Administrator', 'Security Administrator',
        'Conditional Access Administrator', 'Exchange Administrator', 'SharePoint Administrator',
        'User Administrator', 'Application Administrator', 'Cloud Application Administrator',
        'Authentication Administrator', 'Helpdesk Administrator', 'Password Administrator',
        'Intune Administrator', 'Groups Administrator', 'Domain Name Administrator',
        'Hybrid Identity Administrator', 'Partner Tier1 Support', 'Partner Tier2 Support',
        'Billing Administrator', 'Directory Synchronization Accounts')]
    [string]$RoleFilter = 'Privileged',

    [Parameter()]
    [switch]$IncludeGroups,

    [Parameter()]
    [ValidateRange(1, 365)]
    [int]$StaleDays = 90,

    [Parameter()]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# PSSA note: Write-Host is mandated for the colorized [+]/[!]/[-]/[*] console status prefixes
# (RELAUNCH-SPEC section 3); PSAvoidUsingWriteHost warnings are accepted by design.

$PrivilegedRoleNames = @(
    'Global Administrator',
    'Privileged Role Administrator',
    'Privileged Authentication Administrator',
    'Security Administrator',
    'Conditional Access Administrator',
    'Exchange Administrator',
    'SharePoint Administrator',
    'User Administrator',
    'Application Administrator',
    'Cloud Application Administrator',
    'Authentication Administrator',
    'Helpdesk Administrator',
    'Password Administrator',
    'Intune Administrator',
    'Groups Administrator',
    'Domain Name Administrator',
    'Hybrid Identity Administrator',
    'Partner Tier1 Support',
    'Partner Tier2 Support',
    'Billing Administrator',
    'Directory Synchronization Accounts'
)

$GraphScopes = @('RoleManagement.Read.Directory', 'User.Read.All', 'Group.Read.All')
$RoleDefinitionUri = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions'
$ActiveUri = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances'
$EligibleUri = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilityScheduleInstances'
$UserUri = 'https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,userType'
$GroupUri = 'https://graph.microsoft.com/v1.0/groups?$select=id,displayName'

function Get-GraphProperty {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-GraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $items = New-Object System.Collections.ArrayList
    $nextLink = $Uri
    while (-not [string]::IsNullOrWhiteSpace($nextLink)) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink -ErrorAction Stop
        $page = Get-GraphProperty -InputObject $response -Name 'value'
        if ($page) {
            foreach ($item in $page) { [void]$items.Add($item) }
        }
        $nextLink = Get-GraphProperty -InputObject $response -Name '@odata.nextLink'
    }
    return $items.ToArray()
}

function ConvertTo-IsoText {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Value
    )

    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    return [string]$Value
}

function Get-AgeInDays {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$IsoText
    )

    if ([string]::IsNullOrWhiteSpace($IsoText)) { return 0 }
    $parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if (-not [datetime]::TryParse($IsoText, $culture, $styles, [ref]$parsed)) { return 0 }
    $span = (Get-Date).ToUniversalTime() - $parsed.ToUniversalTime()
    return [int][math]::Floor($span.TotalDays)
}

function Test-RoleInScope {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RoleName
    )

    if ($RoleFilter -eq 'Privileged') {
        if ($PrivilegedRoleNames -contains $RoleName) { return $true }
        return $false
    }
    if ($RoleName -eq $RoleFilter) { return $true }
    return $false
}

function Get-PrincipalRoleKey {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Instance
    )

    $principalId = [string](Get-GraphProperty -InputObject $Instance -Name 'principalId')
    $roleDefinitionId = [string](Get-GraphProperty -InputObject $Instance -Name 'roleDefinitionId')
    return "$principalId|$roleDefinitionId"
}

function New-AssignmentRow {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Instance,

        [Parameter(Mandatory = $true)]
        [string]$Classification,

        [Parameter()]
        [hashtable]$RoleNames,

        [Parameter()]
        [hashtable]$UserIndex,

        [Parameter()]
        [hashtable]$GroupIndex
    )

    $roleDefinitionId = [string](Get-GraphProperty -InputObject $Instance -Name 'roleDefinitionId')
    $roleName = '<unknown role>'
    if ($RoleNames.ContainsKey($roleDefinitionId)) { $roleName = [string]$RoleNames[$roleDefinitionId] }

    $principalId = [string](Get-GraphProperty -InputObject $Instance -Name 'principalId')
    $principalName = '<unresolved principal>'
    $principalType = 'Unknown'
    $userType = ''
    if ($UserIndex.ContainsKey($principalId)) {
        $principalType = 'User'
        $principalName = [string](Get-GraphProperty -InputObject $UserIndex[$principalId] -Name 'displayName')
        $userType = [string](Get-GraphProperty -InputObject $UserIndex[$principalId] -Name 'userType')
        if ([string]::IsNullOrWhiteSpace($userType)) { $userType = 'Member' }
    }
    elseif ($GroupIndex.ContainsKey($principalId)) {
        $principalType = 'Group'
        $principalName = [string](Get-GraphProperty -InputObject $GroupIndex[$principalId] -Name 'displayName')
    }

    return [pscustomobject]@{
        Role             = $roleName
        RoleDefinitionId = $roleDefinitionId
        Principal        = $principalName
        PrincipalId      = $principalId
        PrincipalType    = $principalType
        UserType         = $userType
        Classification   = $Classification
        AssignmentType   = [string](Get-GraphProperty -InputObject $Instance -Name 'assignmentType')
        StartDateTime    = ConvertTo-IsoText -Value (Get-GraphProperty -InputObject $Instance `
                -Name 'startDateTime')
        EndDateTime      = ConvertTo-IsoText -Value (Get-GraphProperty -InputObject $Instance `
                -Name 'endDateTime')
    }
}

function New-Finding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code,

        [Parameter()]
        [string]$Role,

        [Parameter()]
        [string]$Principal,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    return [pscustomobject]@{
        Code      = $Code
        Role      = $Role
        Principal = $Principal
        Detail    = $Detail
    }
}

function Main {
    try {
        Write-Host "[*] Auditing Microsoft Entra PIM role assignments..." -ForegroundColor Cyan

        # Validate the report destination before any Microsoft Graph call is made.
        if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            if ($OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or $OutputPath -match '^(\\\\|//)') {
                throw "Unsafe OutputPath: $OutputPath. Use a local path without '..' traversal."
            }
        }

        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            Write-Host "[*] Connecting to Microsoft Graph for tenant $TenantId..." -ForegroundColor Cyan
            Connect-MgGraph -TenantId $TenantId -Scopes $GraphScopes -NoWelcome -ErrorAction Stop
        }
        else {
            Write-Host "[*] Reusing the current Microsoft Graph session." -ForegroundColor Cyan
        }

        $includeGroupPrincipals = $false
        if ($IncludeGroups) { $includeGroupPrincipals = $true }

        $roleDefinitions = @(Get-GraphCollection -Uri $RoleDefinitionUri)
        $roleNames = @{}
        foreach ($definition in $roleDefinitions) {
            $definitionId = [string](Get-GraphProperty -InputObject $definition -Name 'id')
            if ([string]::IsNullOrWhiteSpace($definitionId)) { continue }
            if (-not $roleNames.ContainsKey($definitionId)) {
                $roleNames[$definitionId] = [string](Get-GraphProperty -InputObject $definition `
                        -Name 'displayName')
            }
        }

        $users = @(Get-GraphCollection -Uri $UserUri)
        $userIndex = @{}
        foreach ($user in $users) {
            $userId = [string](Get-GraphProperty -InputObject $user -Name 'id')
            if (-not [string]::IsNullOrWhiteSpace($userId)) { $userIndex[$userId] = $user }
        }

        $groups = @(Get-GraphCollection -Uri $GroupUri)
        $groupIndex = @{}
        foreach ($group in $groups) {
            $groupId = [string](Get-GraphProperty -InputObject $group -Name 'id')
            if (-not [string]::IsNullOrWhiteSpace($groupId)) { $groupIndex[$groupId] = $group }
        }

        $activeInstances = @(Get-GraphCollection -Uri $ActiveUri)
        $eligibleInstances = @(Get-GraphCollection -Uri $EligibleUri)

        $activatedKeys = @{}
        foreach ($instance in $activeInstances) {
            $assignmentType = [string](Get-GraphProperty -InputObject $instance -Name 'assignmentType')
            if ($assignmentType -ne 'Activated') { continue }
            $key = Get-PrincipalRoleKey -Instance $instance
            if (-not $activatedKeys.ContainsKey($key)) { $activatedKeys[$key] = $true }
        }

        $rows = New-Object System.Collections.ArrayList
        $findings = New-Object System.Collections.ArrayList
        $rowArguments = @{
            RoleNames  = $roleNames
            UserIndex  = $userIndex
            GroupIndex = $groupIndex
        }
        $permanentCount = 0
        $timeBoundCount = 0
        $eligibleCount = 0
        $groupExcludedCount = 0
        $unresolvedCount = 0

        foreach ($instance in $activeInstances) {
            $endText = ConvertTo-IsoText -Value (Get-GraphProperty -InputObject $instance -Name 'endDateTime')
            $classification = 'Time-bound Active'
            if ([string]::IsNullOrWhiteSpace($endText) -or $endText -like '9999-*') {
                $classification = 'Permanent-Active'
            }

            $rowArguments['Instance'] = $instance
            $rowArguments['Classification'] = $classification
            $row = New-AssignmentRow @rowArguments

            if (-not (Test-RoleInScope -RoleName $row.Role)) { continue }
            if ($row.PrincipalType -eq 'Group' -and -not $includeGroupPrincipals) {
                $groupExcludedCount++
                continue
            }
            if ($row.PrincipalType -eq 'Unknown') {
                $unresolvedCount++
                continue
            }

            [void]$rows.Add($row)
            if ($classification -eq 'Permanent-Active') { $permanentCount++ }
            else { $timeBoundCount++ }

            if ($classification -eq 'Permanent-Active') {
                $permanentDetail = 'Active assignment has no expiration; make it eligible or time-bound.'
                [void]$findings.Add((New-Finding -Code 'PERMANENT-ACTIVE' -Role $row.Role `
                            -Principal $row.Principal -Detail $permanentDetail))
            }
            if ($row.UserType -eq 'Guest') {
                $guestDetail = "Guest principal holds the $($row.Role) role."
                [void]$findings.Add((New-Finding -Code 'GUEST-ROLE-HOLDER' -Role $row.Role `
                            -Principal $row.Principal -Detail $guestDetail))
            }
        }

        foreach ($instance in $eligibleInstances) {
            $rowArguments['Instance'] = $instance
            $rowArguments['Classification'] = 'Eligible'
            $row = New-AssignmentRow @rowArguments

            if (-not (Test-RoleInScope -RoleName $row.Role)) { continue }
            if ($row.PrincipalType -eq 'Group' -and -not $includeGroupPrincipals) {
                $groupExcludedCount++
                continue
            }
            if ($row.PrincipalType -eq 'Unknown') {
                $unresolvedCount++
                continue
            }

            [void]$rows.Add($row)
            $eligibleCount++

            if ($row.UserType -eq 'Guest') {
                $guestDetail = "Guest principal is eligible for the $($row.Role) role."
                [void]$findings.Add((New-Finding -Code 'GUEST-ROLE-HOLDER' -Role $row.Role `
                            -Principal $row.Principal -Detail $guestDetail))
            }

            $key = "$($row.PrincipalId)|$($row.RoleDefinitionId)"
            $ageDays = Get-AgeInDays -IsoText $row.StartDateTime
            if ($ageDays -ge $StaleDays -and -not $activatedKeys.ContainsKey($key)) {
                $staleDetail = "Eligible for $ageDays days (threshold $StaleDays) with no activation " +
                    'instance recorded.'
                [void]$findings.Add((New-Finding -Code 'ELIGIBLE-NEVER-ACTIVATED' -Role $row.Role `
                            -Principal $row.Principal -Detail $staleDetail))
            }
        }

        $rowArray = $rows.ToArray()
        $findingArray = $findings.ToArray()

        $countMessage = "[*] Assignments audited: $($rowArray.Count) | permanent-active: " +
            "$permanentCount | time-bound active: $timeBoundCount | eligible: $eligibleCount"
        Write-Host $countMessage -ForegroundColor Cyan

        if ($groupExcludedCount -gt 0) {
            $groupMessage = "[!] $groupExcludedCount group-held assignment(s) excluded; rerun with " +
                '-IncludeGroups to include them.'
            Write-Host $groupMessage -ForegroundColor Yellow
        }
        if ($unresolvedCount -gt 0) {
            $unresolvedMessage = "[!] $unresolvedCount assignment(s) had no resolvable user or group " +
                'principal and were skipped.'
            Write-Host $unresolvedMessage -ForegroundColor Yellow
        }

        foreach ($finding in $findingArray) {
            $findingMessage = "[!] $($finding.Code): $($finding.Role) - $($finding.Principal) - " +
                "$($finding.Detail)"
            Write-Host $findingMessage -ForegroundColor Yellow
        }

        $summary = [ordered]@{
            TenantId                 = $TenantId
            GeneratedAtUtc           = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            RoleFilter               = $RoleFilter
            StaleDays                = $StaleDays
            IncludeGroups            = $includeGroupPrincipals
            AssignmentCount          = $rowArray.Count
            PermanentActiveCount     = $permanentCount
            TimeBoundActiveCount     = $timeBoundCount
            EligibleCount            = $eligibleCount
            ExcludedGroupAssignments = $groupExcludedCount
            UnresolvedAssignments    = $unresolvedCount
            FindingCount             = $findingArray.Count
            Assignments              = $rowArray
            Findings                 = $findingArray
        }

        $reportText = ''
        if ($OutputFormat -eq 'Json') {
            $reportText = $summary | ConvertTo-Json -Depth 6
        }
        elseif ($OutputFormat -eq 'Csv') {
            $reportText = (($rowArray | ConvertTo-Csv -NoTypeInformation) -join "`r`n")
        }
        elseif (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            $tableText = $rowArray | Format-Table -AutoSize | Out-String -Width 250
            $reportText = $tableText.TrimEnd()
        }

        if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            Set-Content -LiteralPath $OutputPath -Value $reportText -Encoding UTF8 -ErrorAction Stop
            Write-Host "[+] Report written to $OutputPath" -ForegroundColor Green
        }
        elseif ($OutputFormat -ne 'Table') {
            Write-Output $reportText
        }

        if ($findingArray.Count -gt 0) {
            $findingMessage = "[!] PIM role assignment findings: $($findingArray.Count)."
            Write-Host $findingMessage -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] PIM role assignment audit found no findings." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
