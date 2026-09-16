<#
.SYNOPSIS
    Audits Microsoft Entra emergency access (break-glass) accounts against the vendor baseline.

.DESCRIPTION
    Reads the members of the Global Administrator directory role, the tenant user objects, the
    Conditional Access policies, and each account's password authentication methods through
    Microsoft Graph. For every Global Administrator it reports whether the account is cloud-only,
    whether it is excluded from Conditional Access (by role, user, or group rule), whether it is
    a member rather than a guest, and whether a password credential exists, then compares the
    number of qualifying cloud-only accounts with -ExpectedAccountCount.
    Read-only: no account, role assignment, or policy is created, modified, or removed, and
    re-running the script is safe. A report file is written only when -OutputPath is supplied.
    Exit codes: 0 = baseline met, 2 = findings present, 1 = error (missing module, Microsoft Graph
    failure, or unsafe -OutputPath).
    Microsoft Learn (emergency access account requirements):
    https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access
    Microsoft Learn (Conditional Access exclusion guidance):
    https://learn.microsoft.com/entra/identity/conditional-access/plan-conditional-access
    Microsoft Learn (Global Administrator role members):
    https://learn.microsoft.com/graph/api/directoryrole-list-members
    Microsoft Learn (password credential methods):
    https://learn.microsoft.com/graph/api/authentication-list-passwordmethods

.PARAMETER TenantId
    Microsoft Entra tenant ID to sign in to. When omitted, the current Microsoft Graph session
    is reused and no sign-in is attempted.

.PARAMETER ExpectedAccountCount
    Number of cloud-only member Global Administrator accounts required as emergency access
    accounts. Default 2, per the vendor baseline.

.PARAMETER OutputFormat
    Report format: Table (colored console summary, the default), Json, or Csv.

.PARAMETER OutputPath
    File to write the report to. When omitted, Json and Csv reports are written to the pipeline
    and Table output stays on the console.

.EXAMPLE
    PS C:\> .\Get-EntraBreakGlassAccountAudit.ps1 -TenantId 'contoso.onmicrosoft.com'
    Audits every Global Administrator and exits 2 when the baseline is not met.

.EXAMPLE
    PS C:\> .\Get-EntraBreakGlassAccountAudit.ps1 -ExpectedAccountCount 3
    Requires three qualifying cloud-only Global Administrator accounts instead of the default two.

.NOTES
    File Name   : Get-EntraBreakGlassAccountAudit.ps1
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
    [ValidateRange(1, 10)]
    [int]$ExpectedAccountCount = 2,

    [Parameter()]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# PSSA note: Write-Host is mandated for the colorized [+]/[!]/[-]/[*] console status prefixes
# (RELAUNCH-SPEC section 3); PSAvoidUsingWriteHost warnings are accepted by design.

$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
$DirectoryRoleUri = 'https://graph.microsoft.com/v1.0/directoryRoles'
$PolicyUri = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies'
$UserUri = 'https://graph.microsoft.com/v1.0/users?' +
    '$select=id,displayName,userPrincipalName,userType,onPremisesSyncEnabled'
$GlobalAdministratorName = 'Global Administrator'
$GlobalAdministratorTemplateId = '62e90394-69f5-4237-9190-012177145e10'
$EnabledState = 'enabled'
$GraphScopes = @(
    'RoleManagement.Read.Directory',
    'User.Read.All',
    'GroupMember.Read.All',
    'Policy.Read.All',
    'UserAuthenticationMethod.Read.All'
)

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

function Add-GraphIdList {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.ArrayList]$Target,

        [Parameter()]
        [object[]]$Source
    )

    if ($null -eq $Source) { return }
    foreach ($entry in $Source) {
        if ([string]::IsNullOrWhiteSpace([string]$entry)) { continue }
        if (-not $Target.Contains([string]$entry)) { [void]$Target.Add([string]$entry) }
    }
}

function New-Finding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code,

        [Parameter()]
        [string]$Account,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    return [pscustomobject]@{
        Code    = $Code
        Account = $Account
        Detail  = $Detail
    }
}

function Main {
    try {
        Write-Host "[*] Auditing Microsoft Entra emergency access accounts..." -ForegroundColor Cyan

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

        $directoryRoles = @(Get-GraphCollection -Uri $DirectoryRoleUri)
        $globalAdminRoleId = ''
        foreach ($role in $directoryRoles) {
            $roleName = [string](Get-GraphProperty -InputObject $role -Name 'displayName')
            if ($roleName -eq $GlobalAdministratorName) {
                $globalAdminRoleId = [string](Get-GraphProperty -InputObject $role -Name 'id')
                break
            }
        }

        $members = @()
        if ([string]::IsNullOrWhiteSpace($globalAdminRoleId)) {
            $missingRoleMessage = "[!] The $GlobalAdministratorName directory role is not activated in " +
                'this tenant: no administrator could be enumerated.'
            Write-Host $missingRoleMessage -ForegroundColor Yellow
        }
        else {
            $memberUri = $GraphBaseUri + '/directoryRoles/' + $globalAdminRoleId + '/members'
            $members = @(Get-GraphCollection -Uri $memberUri)
        }

        $users = @(Get-GraphCollection -Uri $UserUri)
        $userIndex = @{}
        foreach ($user in $users) {
            $userId = [string](Get-GraphProperty -InputObject $user -Name 'id')
            if (-not [string]::IsNullOrWhiteSpace($userId)) { $userIndex[$userId] = $user }
        }

        $policies = @(Get-GraphCollection -Uri $PolicyUri)
        $excludedUserIds = New-Object System.Collections.ArrayList
        $excludedGroupIds = New-Object System.Collections.ArrayList
        $excludedRoleIds = New-Object System.Collections.ArrayList
        $enabledPolicyCount = 0
        foreach ($policy in $policies) {
            $state = [string](Get-GraphProperty -InputObject $policy -Name 'state')
            if ($state -ne $EnabledState) { continue }
            $enabledPolicyCount++
            $conditions = Get-GraphProperty -InputObject $policy -Name 'conditions'
            $policyUsers = Get-GraphProperty -InputObject $conditions -Name 'users'
            Add-GraphIdList -Target $excludedUserIds -Source @(
                (Get-GraphProperty -InputObject $policyUsers -Name 'excludeUsers'))
            Add-GraphIdList -Target $excludedGroupIds -Source @(
                (Get-GraphProperty -InputObject $policyUsers -Name 'excludeGroups'))
            Add-GraphIdList -Target $excludedRoleIds -Source @(
                (Get-GraphProperty -InputObject $policyUsers -Name 'excludeRoles'))
        }
        $excludedByRole = $excludedRoleIds -contains $GlobalAdministratorTemplateId

        $accounts = New-Object System.Collections.ArrayList
        $findings = New-Object System.Collections.ArrayList
        $nonUserMemberCount = 0

        foreach ($member in $members) {
            $accountId = [string](Get-GraphProperty -InputObject $member -Name 'id')
            if ([string]::IsNullOrWhiteSpace($accountId)) { continue }
            if (-not $userIndex.ContainsKey($accountId)) {
                $nonUserMemberCount++
                continue
            }

            $user = $userIndex[$accountId]
            $displayName = [string](Get-GraphProperty -InputObject $user -Name 'displayName')
            $upn = [string](Get-GraphProperty -InputObject $user -Name 'userPrincipalName')
            $userType = [string](Get-GraphProperty -InputObject $user -Name 'userType')
            if ([string]::IsNullOrWhiteSpace($userType)) { $userType = 'Member' }

            $synced = [bool](Get-GraphProperty -InputObject $user -Name 'onPremisesSyncEnabled')
            $cloudOnly = -not $synced
            $onMicrosoftUpn = $false
            if ($upn -like '*.onmicrosoft.com') { $onMicrosoftUpn = $true }

            $exclusionKind = 'None'
            if ($excludedByRole) { $exclusionKind = 'Role' }
            elseif ($excludedUserIds -contains $accountId) { $exclusionKind = 'User' }
            else {
                $membershipPath = '/transitiveMemberOf/microsoft.graph.group?$select=id'
                $membershipUri = $GraphBaseUri + '/users/' + $accountId + $membershipPath
                $memberships = @(Get-GraphCollection -Uri $membershipUri)
                foreach ($membership in $memberships) {
                    $membershipId = [string](Get-GraphProperty -InputObject $membership -Name 'id')
                    if ($excludedGroupIds -contains $membershipId) {
                        $exclusionKind = 'Group'
                        break
                    }
                }
            }

            $passwordUri = $GraphBaseUri + '/users/' + $accountId + '/authentication/passwordMethods'
            $passwordMethods = @(Get-GraphCollection -Uri $passwordUri)
            $hasPassword = ($passwordMethods.Count -gt 0)

            $account = [pscustomobject]@{
                DisplayName                   = $displayName
                UserPrincipalName             = $upn
                Id                            = $accountId
                UserType                      = $userType
                CloudOnly                     = $cloudOnly
                OnMicrosoftUpn                = $onMicrosoftUpn
                ExcludedFromConditionalAccess = ($exclusionKind -ne 'None')
                ExclusionKind                 = $exclusionKind
                HasPasswordCredential         = $hasPassword
            }
            [void]$accounts.Add($account)

            if (-not $cloudOnly) {
                $syncedDetail = 'Global Administrator is synchronized from an on-premises directory; ' +
                    'emergency access accounts must be cloud-only.'
                [void]$findings.Add((New-Finding -Code 'GA-SYNCED-FROM-ONPREM' -Account $upn `
                            -Detail $syncedDetail))
            }
            if ($userType -eq 'Guest') {
                $guestDetail = 'Global Administrator is a guest account; emergency access accounts ' +
                    'must be directory members.'
                [void]$findings.Add((New-Finding -Code 'GA-GUEST' -Account $upn -Detail $guestDetail))
            }
            if ($cloudOnly -and -not $onMicrosoftUpn) {
                $upnDetail = 'Cloud-only account does not use the *.onmicrosoft.com domain required ' +
                    'for emergency access accounts.'
                [void]$findings.Add((New-Finding -Code 'GA-NOT-ONMICROSOFT-UPN' -Account $upn `
                            -Detail $upnDetail))
            }
            if ($exclusionKind -eq 'None') {
                $exclusionDetail = 'Account is not excluded from any enabled Conditional Access ' +
                    'policy; an enforced policy can lock it out during an emergency.'
                [void]$findings.Add((New-Finding -Code 'GA-NOT-CA-EXCLUDED' -Account $upn `
                            -Detail $exclusionDetail))
            }
            if (-not $hasPassword) {
                $passwordDetail = 'No password credential exists for this account; verify that a ' +
                    'phishing-resistant method is registered instead.'
                [void]$findings.Add((New-Finding -Code 'GA-NO-PASSWORD-CREDENTIAL' -Account $upn `
                            -Detail $passwordDetail))
            }
        }

        $accountArray = $accounts.ToArray()
        $candidateCount = 0
        foreach ($account in $accountArray) {
            if ($account.CloudOnly -and $account.UserType -eq 'Member') { $candidateCount++ }
        }
        if ($candidateCount -lt $ExpectedAccountCount) {
            $countDetail = "Only $candidateCount cloud-only member Global Administrator account(s) " +
                "found; the baseline requires at least $ExpectedAccountCount."
            [void]$findings.Insert(0, (New-Finding -Code 'GA-COUNT-LOW' -Account '<tenant>' `
                        -Detail $countDetail))
        }

        $findingArray = $findings.ToArray()
        $countMessage = "[*] Global Administrators: $($accountArray.Count) | cloud-only members: " +
            "$candidateCount | expected: $ExpectedAccountCount | enabled policies: $enabledPolicyCount"
        Write-Host $countMessage -ForegroundColor Cyan

        if ($nonUserMemberCount -gt 0) {
            $memberMessage = "[!] $nonUserMemberCount Global Administrator member(s) are not user " +
                'accounts and were skipped.'
            Write-Host $memberMessage -ForegroundColor Yellow
        }

        foreach ($finding in $findingArray) {
            $findingMessage = "[!] $($finding.Code): $($finding.Account) - $($finding.Detail)"
            Write-Host $findingMessage -ForegroundColor Yellow
        }

        $summary = [ordered]@{
            TenantId                  = $TenantId
            GeneratedAtUtc            = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            ExpectedAccountCount      = $ExpectedAccountCount
            GlobalAdministratorCount  = $accountArray.Count
            CloudOnlyAdminCount       = $candidateCount
            EnabledPolicyCount        = $enabledPolicyCount
            ExcludedUnassignedMembers = $nonUserMemberCount
            FindingCount              = $findingArray.Count
            Accounts                  = $accountArray
            Findings                  = $findingArray
        }

        $reportText = ''
        if ($OutputFormat -eq 'Json') {
            $reportText = $summary | ConvertTo-Json -Depth 6
        }
        elseif ($OutputFormat -eq 'Csv') {
            $reportText = (($accountArray | ConvertTo-Csv -NoTypeInformation) -join "`r`n")
        }
        elseif (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            $tableText = $accountArray | Format-Table -AutoSize | Out-String -Width 250
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
            $findingMessage = "[!] Emergency access account findings: $($findingArray.Count)."
            Write-Host $findingMessage -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] Emergency access account baseline met." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
