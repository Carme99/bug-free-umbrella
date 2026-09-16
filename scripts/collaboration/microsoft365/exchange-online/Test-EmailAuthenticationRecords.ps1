<#
.SYNOPSIS
    Validate SPF, DKIM and DMARC DNS records for a Microsoft 365 domain.

.DESCRIPTION
    Resolves the SPF TXT record, the MX records, the DKIM selector CNAME records and the
    _dmarc TXT record for the domain named by -DomainName, then compares the results with
    the Microsoft 365 email authentication guidance:

    - SPF: https://learn.microsoft.com/microsoft-365/security/office-365-security/email-authentication-spf-configure
    - DKIM: https://learn.microsoft.com/microsoft-365/security/office-365-security/email-authentication-dkim-configure
    - DMARC: https://learn.microsoft.com/microsoft-365/security/office-365-security/email-authentication-dmarc-configure

    Every DNS lookup goes through the Invoke-DnsQuery wrapper, which calls Resolve-DnsName
    (https://learn.microsoft.com/powershell/module/dnsclient/resolve-dnsname). When Exchange
    Online PowerShell is available the script also reads the authoritative DKIM signing state
    with Get-DkimSigningConfig
    (https://learn.microsoft.com/powershell/module/exchangepowershell/get-dkimsigningconfig).

    The checks assert the documented guidance: exactly one SPF record per domain, the expected
    include: mechanism present with a hard-fail enforcement rule, DKIM enabled and CNAME-backed
    for every selector, and a DMARC policy at least as strict as -DmarcPolicy.

    The script is strictly read-only. It never changes DNS, SPF, DKIM or DMARC state; the only
    write it can perform is the optional report file named by -OutputPath.
    Exit codes: 0 = every check passed; 2 = one or more findings; 1 = fatal error.

.PARAMETER DomainName
    The custom domain to audit, for example contoso.com. Required.

.PARAMETER DkimSelector
    The DKIM selectors resolved as <selector>._domainkey.<domain> CNAME records. Defaults to
    the two selectors Microsoft 365 uses, selector1 and selector2.

.PARAMETER ExpectedSpfInclude
    The include: mechanism that must appear in the SPF record. Defaults to
    spf.protection.outlook.com, the documented Microsoft 365 mail source.

.PARAMETER DmarcPolicy
    The minimum acceptable DMARC policy: none, quarantine or reject. Defaults to quarantine.
    A published policy weaker than this value is reported as a finding.

.PARAMETER OutputFormat
    Report format: Table (console only), Json or Csv. Defaults to Table.

.PARAMETER OutputPath
    File to write when -OutputFormat is Json or Csv. When omitted the rendered report is
    written to the console instead.

.EXAMPLE
    PS C:\> .\Test-EmailAuthenticationRecords.ps1 -DomainName contoso.com
    Audits contoso.com and prints the SPF, MX, DKIM and DMARC results to the console.

.EXAMPLE
    PS C:\> .\Test-EmailAuthenticationRecords.ps1 -DomainName contoso.com -DmarcPolicy reject
    Audits contoso.com and requires a DMARC policy of reject.

.EXAMPLE
    PS C:\> .\Test-EmailAuthenticationRecords.ps1 -DomainName contoso.com -OutputFormat Csv `
        -OutputPath C:\Reports\contoso-email-auth.csv
    Writes the per-record check results to a CSV file and returns exit code 2 on any finding.

.NOTES
   File Name   : Test-EmailAuthenticationRecords.ps1
   Author      : Bug-Free Umbrella
   Prerequisite: PowerShell 7.0
   Version     : 2.0.0
   Date        : 2026-09-16
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DomainName,

    [Parameter(Mandatory = $false)]
    [string[]]$DkimSelector = @('selector1', 'selector2'),

    [Parameter(Mandatory = $false)]
    [string]$ExpectedSpfInclude = 'spf.protection.outlook.com',

    [Parameter(Mandatory = $false)]
    [ValidateSet('none', 'quarantine', 'reject')]
    [string]$DmarcPolicy = 'quarantine',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Documented DMARC policy strengths, weakest first. Used to compare the published p= value
# against the -DmarcPolicy floor.
$script:DmarcPolicyRank = @{ none = 0; quarantine = 1; reject = 2 }

function Invoke-DnsQuery {
    # The single seam onto the native resolver: Pester mocks this function, never Resolve-DnsName.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Type
    )

    return @(Resolve-DnsName -Name $Name -Type $Type -ErrorAction Stop)
}

function Get-DnsRecordText {
    # Flattens the Resolve-DnsName record shapes this script queries into a display string.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Record)

    if ($null -ne $Record.Strings) { return ($Record.Strings -join '') }
    if ($null -ne $Record.NameHost) { return [string]$Record.NameHost }
    if ($null -ne $Record.NameExchange) { return [string]$Record.NameExchange }
    if ($null -ne $Record.Data) { return [string]$Record.Data }

    return ''
}

function Get-MatchingRecordText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$RecordPattern
    )

    $texts = @()
    foreach ($record in @(Invoke-DnsQuery -Name $Name -Type $Type)) {
        $text = Get-DnsRecordText -Record $record
        if ($text -match $RecordPattern) { $texts += $text }
    }

    return $texts
}

function Get-SpfMechanism {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$SpfRecord)

    $parts = @($SpfRecord -split '\s+' | Where-Object { $_ -ne '' })

    return @($parts | Select-Object -Skip 1)
}

function Get-DmarcTagValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DmarcRecord,
        [Parameter(Mandatory = $true)][string]$Tag
    )

    $pattern = '(?:^|;\s*)' + [regex]::Escape($Tag) + '=([^;]*)'
    $match = [regex]::Match($DmarcRecord, $pattern)
    if ($match.Success) { return $match.Groups[1].Value.Trim() }

    return ''
}

function New-CheckRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Area,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    return [pscustomobject]@{
        Area   = $Area
        Target = $Target
        Status = $Status
        Detail = $Detail
    }
}

function Main {
    try {
        Write-Host "[*] Auditing email authentication records for $DomainName" -ForegroundColor Cyan

        $findings = @()
        $checks = @()

        # --- SPF -------------------------------------------------------------------------
        Write-Host "[*] SPF: querying the TXT record for $DomainName" -ForegroundColor Cyan
        $spfRecords = @(Get-MatchingRecordText -Name $DomainName -Type 'TXT' `
            -RecordPattern '^v=spf1')

        if ($spfRecords.Count -eq 0) {
            $findings += "SPF: no v=spf1 TXT record is published for $DomainName"
            $checks += New-CheckRow -Area 'SPF' -Target $DomainName -Status 'Fail' `
                -Detail 'No v=spf1 TXT record found'
        }
        elseif ($spfRecords.Count -gt 1) {
            $findings += "SPF: $($spfRecords.Count) SPF records found; only one is allowed per domain"
            $checks += New-CheckRow -Area 'SPF' -Target $DomainName -Status 'Fail' `
                -Detail "$($spfRecords.Count) records published; multiple records cause permerror"
        }
        else {
            $spfText = $spfRecords[0]
            $spfMechanisms = @(Get-SpfMechanism -SpfRecord $spfText)
            Write-Host "[+] SPF: $spfText" -ForegroundColor Green
            Write-Host "[+] SPF mechanisms: $($spfMechanisms -join ', ')" -ForegroundColor Green
            $checks += New-CheckRow -Area 'SPF' -Target $DomainName -Status 'Pass' `
                -Detail $spfText

            $includeMechanism = "include:$ExpectedSpfInclude"
            if ($spfMechanisms -contains $includeMechanism) {
                $checks += New-CheckRow -Area 'SPF include' -Target $includeMechanism `
                    -Status 'Pass' -Detail 'Documented Microsoft 365 include is present'
            }
            else {
                $findings += "SPF: the $includeMechanism mechanism is missing from the record"
                $checks += New-CheckRow -Area 'SPF include' -Target $includeMechanism `
                    -Status 'Fail' -Detail 'Documented Microsoft 365 include is missing'
            }

            if ($spfMechanisms -contains '-all') {
                $checks += New-CheckRow -Area 'SPF enforcement' -Target '-all' -Status 'Pass' `
                    -Detail 'Hard-fail enforcement rule is present'
            }
            else {
                $findings += 'SPF: the recommended -all (hard fail) enforcement rule is missing'
                $checks += New-CheckRow -Area 'SPF enforcement' -Target '-all' -Status 'Fail' `
                    -Detail 'Hard-fail enforcement rule is missing'
            }
        }

        # --- MX --------------------------------------------------------------------------
        Write-Host "[*] MX: querying the MX records for $DomainName" -ForegroundColor Cyan
        $mxRecords = @(Get-MatchingRecordText -Name $DomainName -Type 'MX' -RecordPattern '\S')
        if ($mxRecords.Count -eq 0) {
            $findings += "MX: no MX record is published for $DomainName"
            $checks += New-CheckRow -Area 'MX' -Target $DomainName -Status 'Fail' `
                -Detail 'No MX record found; mail cannot be routed to the domain'
        }
        else {
            $mxHosts = $mxRecords -join ', '
            Write-Host "[+] MX: $($mxRecords.Count) record(s): $mxHosts" -ForegroundColor Green
            $checks += New-CheckRow -Area 'MX' -Target $DomainName -Status 'Pass' `
                -Detail "$($mxRecords.Count) record(s): $mxHosts"
        }

        # --- DKIM ------------------------------------------------------------------------
        foreach ($selector in $DkimSelector) {
            $dkimHost = "$selector._domainkey.$DomainName"
            Write-Host "[*] DKIM: querying the CNAME record for $dkimHost" -ForegroundColor Cyan
            $cnames = @(Get-MatchingRecordText -Name $dkimHost -Type 'CNAME' `
                -RecordPattern '\S')

            if ($cnames.Count -eq 0) {
                $findings += "DKIM: no CNAME record is published for $dkimHost"
                $checks += New-CheckRow -Area 'DKIM' -Target $dkimHost -Status 'Fail' `
                    -Detail 'Selector CNAME record is missing'
            }
            else {
                Write-Host "[+] DKIM: $dkimHost -> $($cnames[0])" -ForegroundColor Green
                $checks += New-CheckRow -Area 'DKIM' -Target $dkimHost -Status 'Pass' `
                    -Detail $cnames[0]
            }
        }

        # Authoritative Exchange Online DKIM state. Best effort: DNS checks still run without it.
        if (Get-Command -Name 'Get-DkimSigningConfig' -ErrorAction SilentlyContinue) {
            Write-Host '[*] DKIM: reading the Exchange Online signing state' -ForegroundColor Cyan
            $dkimConfig = Get-DkimSigningConfig -Identity $DomainName -ErrorAction SilentlyContinue
            if ($null -eq $dkimConfig) {
                $findings += "DKIM: Exchange Online has no signing configuration for $DomainName"
                $checks += New-CheckRow -Area 'DKIM signing' -Target $DomainName -Status 'Fail' `
                    -Detail 'No DKIM signing configuration in Exchange Online'
            }
            elseif (-not $dkimConfig.Enabled) {
                $findings += "DKIM: DKIM signing is disabled for $DomainName in Exchange Online"
                $checks += New-CheckRow -Area 'DKIM signing' -Target $DomainName -Status 'Fail' `
                    -Detail 'DKIM signing is disabled'
            }
            else {
                $detail = "Enabled; status $($dkimConfig.Status)"
                Write-Host "[+] DKIM: $DomainName is signed ($detail)" -ForegroundColor Green
                $checks += New-CheckRow -Area 'DKIM signing' -Target $DomainName -Status 'Pass' `
                    -Detail $detail
            }
        }
        else {
            Write-Host '[!] Exchange Online PowerShell unavailable; DNS checks only' `
                -ForegroundColor Yellow
        }

        # --- DMARC -----------------------------------------------------------------------
        $dmarcHost = "_dmarc.$DomainName"
        Write-Host "[*] DMARC: querying the TXT record for $dmarcHost" -ForegroundColor Cyan
        $dmarcRecords = @(Get-MatchingRecordText -Name $dmarcHost -Type 'TXT' `
            -RecordPattern '^v=DMARC1')

        if ($dmarcRecords.Count -eq 0) {
            $findings += "DMARC: no v=DMARC1 TXT record is published for $dmarcHost"
            $checks += New-CheckRow -Area 'DMARC' -Target $dmarcHost -Status 'Fail' `
                -Detail 'No v=DMARC1 TXT record found'
        }
        elseif ($dmarcRecords.Count -gt 1) {
            $findings += "DMARC: $($dmarcRecords.Count) DMARC records found for $dmarcHost"
            $checks += New-CheckRow -Area 'DMARC' -Target $dmarcHost -Status 'Fail' `
                -Detail 'Only one _dmarc TXT record is allowed per domain'
        }
        else {
            $dmarcText = $dmarcRecords[0]
            $publishedPolicy = Get-DmarcTagValue -DmarcRecord $dmarcText -Tag 'p'
            $aggregateUri = Get-DmarcTagValue -DmarcRecord $dmarcText -Tag 'rua'
            $forensicUri = Get-DmarcTagValue -DmarcRecord $dmarcText -Tag 'ruf'
            Write-Host "[+] DMARC: $dmarcText" -ForegroundColor Green
            Write-Host "[+] DMARC tags: p=$publishedPolicy; rua=$aggregateUri; ruf=$forensicUri" `
                -ForegroundColor Green
            $checks += New-CheckRow -Area 'DMARC' -Target $dmarcHost -Status 'Pass' `
                -Detail $dmarcText

            $policyKey = $publishedPolicy.ToLowerInvariant()
            if (-not $script:DmarcPolicyRank.ContainsKey($policyKey)) {
                $findings += "DMARC: the p= tag is missing or unrecognised (p=$publishedPolicy)"
                $checks += New-CheckRow -Area 'DMARC policy' -Target $dmarcHost -Status 'Fail' `
                    -Detail 'The p= tag is missing or not none/quarantine/reject'
            }
            elseif ($script:DmarcPolicyRank[$policyKey] -lt $script:DmarcPolicyRank[$DmarcPolicy]) {
                $findings += "DMARC: policy p=$publishedPolicy is weaker than the required p=$DmarcPolicy"
                $checks += New-CheckRow -Area 'DMARC policy' -Target $dmarcHost -Status 'Fail' `
                    -Detail "Published p=$publishedPolicy; required at least p=$DmarcPolicy"
            }
            else {
                $checks += New-CheckRow -Area 'DMARC policy' -Target $dmarcHost -Status 'Pass' `
                    -Detail "Published p=$publishedPolicy meets the required p=$DmarcPolicy"
            }

            if ($aggregateUri) {
                $checks += New-CheckRow -Area 'DMARC reporting' -Target 'rua' -Status 'Pass' `
                    -Detail $aggregateUri
            }
            else {
                $findings += 'DMARC: no rua= aggregate report address is published'
                $checks += New-CheckRow -Area 'DMARC reporting' -Target 'rua' -Status 'Fail' `
                    -Detail 'No aggregate report address'
            }
        }

        # --- Report ----------------------------------------------------------------------
        Write-Host ''
        Write-Host '=== Check results ===' -ForegroundColor Cyan
        foreach ($check in $checks) {
            $colour = 'Red'
            if ($check.Status -eq 'Pass') { $colour = 'Green' }
            Write-Host ("  [{0}] {1}: {2}" -f $check.Status, $check.Area, $check.Detail) `
                -ForegroundColor $colour
        }

        if ($OutputFormat -ne 'Table') {
            $payload = [pscustomobject]@{
                Domain    = $DomainName
                Generated = (Get-Date).ToString('s')
                Findings  = $findings
                Checks    = $checks
            }

            if ($OutputFormat -eq 'Json') {
                $rendered = $payload | ConvertTo-Json -Depth 5
            }
            else {
                $rendered = $checks | ConvertTo-Csv -NoTypeInformation
            }

            if ($OutputPath) {
                if ($OutputFormat -eq 'Json') {
                    Set-Content -LiteralPath $OutputPath -Value $rendered -ErrorAction Stop
                }
                else {
                    $checks | Export-Csv -Path $OutputPath -NoTypeInformation -ErrorAction Stop
                }
                Write-Host "[+] Report written to $OutputPath" -ForegroundColor Green
            }
            else {
                Write-Host ($rendered | Out-String) -ForegroundColor Gray
            }
        }

        if ($findings.Count -gt 0) {
            Write-Host "[!] $($findings.Count) finding(s) detected" -ForegroundColor Yellow
            foreach ($finding in $findings) {
                Write-Host "    $finding" -ForegroundColor Yellow
            }
            return 2
        }

        Write-Host '[+] All email authentication checks passed' -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
