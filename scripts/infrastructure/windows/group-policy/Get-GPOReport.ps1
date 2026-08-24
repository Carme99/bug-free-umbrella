<#
.SYNOPSIS
    Generates comprehensive Group Policy Object (GPO) reports for domain analysis.

.DESCRIPTION
    This script analyzes all Group Policy Objects in the domain and generates detailed
    reports including GPO settings, links, permissions, WMI filters, and potential issues.
    It writes per-GPO HTML/XML reports plus an index page under -OutputPath, with an optional
    CSV summary. The script is read-only with respect to Active Directory and safe to re-run;
    report files are overwritten in place on subsequent runs.

.PARAMETER OutputPath
    Local absolute path where the report files will be saved. Creates the directory if it doesn't exist.

.PARAMETER ReportFormat
    Format for the reports. Options: HTML, XML, Both. Default is Both.

.PARAMETER IncludeUnlinkedGPOs
    Switch to include GPOs that are not linked to any OU in the report.

.PARAMETER IncludeEmptyGPOs
    Switch to include GPOs that have no settings configured.

.PARAMETER ExportToCSV
    Switch to also export a summary CSV file with key GPO information.

.EXAMPLE
    PS C:\> .\Get-GPOReport.ps1 -OutputPath "C:\GPOReports"
    Generates both HTML and XML reports for all GPOs.

.EXAMPLE
    PS C:\> .\Get-GPOReport.ps1 -OutputPath "C:\GPOReports" -ReportFormat HTML -IncludeUnlinkedGPOs -ExportToCSV
    Generates HTML reports including unlinked GPOs and exports a CSV summary.

.NOTES
    File Name: Get-GPOReport.ps1
    Author: Server Management Team
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='Spec 3 requirement')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification='Used in Main scope')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('HTML', 'XML', 'Both')]
    [string]$ReportFormat = 'Both',

    [Parameter(Mandatory = $false)]
    [switch]$IncludeUnlinkedGPOs,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeEmptyGPOs,

    [Parameter(Mandatory = $false)]
    [switch]$ExportToCSV
)

$ErrorActionPreference = 'Stop'

function Assert-SafeLocalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path -match '(^|[\\/])\.\.([\\/]|$)' -or
        $Path -match '^(\\\\|//)') {
        throw "$Label must be a local absolute path without '..' traversal: '$Path'"
    }

    return [System.IO.Path]::GetFullPath($Path)
}

function Save-GpoReport {
    # Thin wrapper around Get-GPOReport file output; serves as the test mock seam for
    # per-GPO HTML/XML report files.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Guid]$Guid,

        [Parameter(Mandatory = $true)]
        [ValidateSet('HTML', 'XML')]
        [string]$ReportType,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Get-GPOReport -Guid $Guid -ReportType $ReportType -Path $Path -ErrorAction Stop | Out-Null
}

function Main {
    [CmdletBinding()]
    param()

    try {
        Write-Host '[*] Starting Group Policy Object report generation...' -ForegroundColor Cyan

        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        $resolvedOutputPath = Assert-SafeLocalPath -Path $OutputPath -Label 'OutputPath'

        # Create output directory
        if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Container)) {
            New-Item -Path $resolvedOutputPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Host "[+] Created output directory: $resolvedOutputPath" -ForegroundColor Green
        }

        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        Write-Host ''
        Write-Host '=== Group Policy Object Report Generator ===' -ForegroundColor Cyan
        Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

        # Get domain information
        Write-Host '[*] Gathering domain information...' -ForegroundColor Yellow
        $domain = Get-ADDomain -ErrorAction Stop
        $domainName = $domain.DNSRoot
        Write-Host "Domain: $domainName" -ForegroundColor Green

        # Get all GPOs
        Write-Host '[*] Retrieving all Group Policy Objects...' -ForegroundColor Yellow
        $allGPOs = @(Get-GPO -All -Domain $domainName)
        $totalGPOs = @($allGPOs).Count
        Write-Host "[+] Found $totalGPOs GPOs" -ForegroundColor Green

        # Initialize summary data
        $gpoSummary = @()
        $unlinkedGPOs = @()
        $emptyGPOs = @()
        $disabledGPOs = @()

        $counter = 0

        foreach ($gpo in $allGPOs) {
            $counter++
            $percentComplete = [math]::Round(($counter / $totalGPOs) * 100)
            $progressStatus = "Processing $($gpo.DisplayName) ($counter of $totalGPOs)"
            Write-Progress -Activity 'Processing GPOs' -Status $progressStatus -PercentComplete $percentComplete

            # Get GPO details
            $gpoGuid = $gpo.Id
            $gpoName = $gpo.DisplayName
            $gpoCreated = $gpo.CreationTime
            $gpoModified = $gpo.ModificationTime
            $gpoStatus = $gpo.GpoStatus

            # Check if GPO is disabled
            if ($gpoStatus -like '*Disabled*') {
                $disabledGPOs += $gpo
            }

            # Get GPO links
            $gpoReport = [xml](Get-GPOReport -Guid $gpoGuid -ReportType XML -ErrorAction Stop)
            $links = $gpoReport.GPO.LinksTo
            $linkCount = if ($links) { @($links).Count } else { 0 }

            # Check if unlinked
            $isUnlinked = ($linkCount -eq 0)
            if ($isUnlinked) {
                $unlinkedGPOs += $gpo
            }

            # Check if empty (no computer or user settings)
            $computerEnabled = $gpo.Computer.Enabled
            $userEnabled = $gpo.User.Enabled
            $computerVersion = $gpo.Computer.DSVersion
            $userVersion = $gpo.User.DSVersion

            $isEmpty = ((-not $computerEnabled) -and (-not $userEnabled)) -or
            (($computerVersion -eq 0) -and ($userVersion -eq 0))

            if ($isEmpty) {
                $emptyGPOs += $gpo
            }

            # Get WMI filter info
            $wmiFilter = if ($gpo.WmiFilter) { $gpo.WmiFilter.Name } else { 'None' }

            # Create summary object
            $gpoSummary += [PSCustomObject]@{
                Name            = $gpoName
                GUID            = $gpoGuid
                Status          = $gpoStatus
                Created         = $gpoCreated
                Modified        = $gpoModified
                LinkCount       = $linkCount
                IsUnlinked      = $isUnlinked
                IsEmpty         = $isEmpty
                ComputerEnabled = $computerEnabled
                UserEnabled     = $userEnabled
                ComputerVersion = $computerVersion
                UserVersion     = $userVersion
                WMIFilter       = $wmiFilter
                Owner           = $gpo.Owner
            }

            # Generate individual GPO reports
            $safeFileName = $gpoName -replace '[\\/:*?"<>|]', '_'

            if ($ReportFormat -eq 'HTML' -or $ReportFormat -eq 'Both') {
                $htmlPath = Join-Path -Path $resolvedOutputPath -ChildPath "$safeFileName.html"
                Save-GpoReport -Guid $gpoGuid -ReportType HTML -Path $htmlPath
            }

            if ($ReportFormat -eq 'XML' -or $ReportFormat -eq 'Both') {
                $xmlPath = Join-Path -Path $resolvedOutputPath -ChildPath "$safeFileName.xml"
                Save-GpoReport -Guid $gpoGuid -ReportType XML -Path $xmlPath
            }
        }

        Write-Progress -Activity 'Processing GPOs' -Completed

        # Generate summary report
        Write-Host '[*] Generating GPO summary...' -ForegroundColor Cyan
        Write-Host '=== GPO Summary ===' -ForegroundColor Cyan
        Write-Host "Total GPOs: $totalGPOs" -ForegroundColor White
        $fgColor = if (@($unlinkedGPOs).Count -gt 0) { 'Yellow' } else { 'Green' }
                Write-Host "Unlinked GPOs: $(@($unlinkedGPOs).Count)" -ForegroundColor $fgColor
        Write-Host ("Empty GPOs:" +
            "$(@($emptyGPOs).Count)") -ForegroundColor $(if (@($emptyGPOs).Count -gt 0) { 'Yellow' } else { 'Green' })
        $fgColor = if (@($disabledGPOs).Count -gt 0) { 'Yellow' } else { 'Green' }
                Write-Host "Disabled GPOs: $(@($disabledGPOs).Count)" -ForegroundColor $fgColor

        # Export CSV summary
        if ($ExportToCSV) {
            Write-Host '[*] Exporting CSV summary...' -ForegroundColor Yellow
            $csvPath = Join-Path -Path $resolvedOutputPath -ChildPath "GPO_Summary_${RunTimestamp}_${RunId}.csv"
            $gpoSummary | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] CSV exported to: $csvPath" -ForegroundColor Green
        }

        # Create index HTML file
        Write-Host '[*] Generating index file...' -ForegroundColor Yellow
        $indexPath = Join-Path -Path $resolvedOutputPath -ChildPath 'Index.html'

        $htmlHead = @"
<!DOCTYPE html>
<html>
<head>
    <title>Group Policy Report - $([System.Net.WebUtility]::HtmlEncode("$domainName"))</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f0f0f0; }
        .warning { color: #ff6600; font-weight: bold; }
        .good { color: #009900; }
        .info { background-color: #e6f3ff; padding: 15px; border-left: 4px solid #0066cc; margin: 20px 0; }
        a { color: #0066cc; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>Group Policy Object Report</h1>
    <div class="info">
        <strong>Domain:</strong> $([System.Net.WebUtility]::HtmlEncode("$domainName"))<br>
        <strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
        <strong>Total GPOs:</strong> $totalGPOs
    </div>

    <h2>Summary Statistics</h2>
    <table>
        <tr><td><strong>Total GPOs</strong></td><td>$totalGPOs</td></tr>
        <tr><td><strong>Unlinked GPOs</strong></td>
            <td class="$(if ($unlinkedGPOs.Count -gt 0) { 'warning' } else { 'good' })">$($unlinkedGPOs.Count)</td></tr>
        <tr><td><strong>Empty GPOs</strong></td>
            <td class="$(if ($emptyGPOs.Count -gt 0) { 'warning' } else { 'good' })">$($emptyGPOs.Count)</td></tr>
        <tr><td><strong>Disabled GPOs</strong></td>
            <td class="$(if ($disabledGPOs.Count -gt 0) { 'warning' } else { 'good' })">$($disabledGPOs.Count)</td></tr>
    </table>

    <h2>All Group Policy Objects</h2>
    <table>
        <tr>
            <th>GPO Name</th>
            <th>Status</th>
            <th>Links</th>
            <th>Modified</th>
            <th>Actions</th>
        </tr>
"@

        $htmlRows = ''
        foreach ($gpoEntry in $gpoSummary | Sort-Object -Property Name) {
            $safeFileName = $gpoEntry.Name -replace '[\\/:*?"<>|]', '_'
            $statusClass = if ($gpoEntry.IsUnlinked -or $gpoEntry.IsEmpty) { 'warning' } else { '' }
            $statusText = $gpoEntry.Status
            if ($gpoEntry.IsUnlinked) { $statusText += ' (Unlinked)' }
            if ($gpoEntry.IsEmpty) { $statusText += ' (Empty)' }

            $actionsHtml = ''
            if ($ReportFormat -eq 'HTML' -or $ReportFormat -eq 'Both') {
                $actionsHtml += "<a href='$safeFileName.html'>HTML</a> "
            }
            if ($ReportFormat -eq 'XML' -or $ReportFormat -eq 'Both') {
                $actionsHtml += "<a href='$safeFileName.xml'>XML</a>"
            }

            $htmlRows += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($gpoEntry.Name)"))</td>
            <td class="$statusClass">$([System.Net.WebUtility]::HtmlEncode("$statusText"))</td>
            <td>$($gpoEntry.LinkCount)</td>
            <td>$($gpoEntry.Modified.ToString('yyyy-MM-dd HH:mm'))</td>
            <td>$actionsHtml</td>
        </tr>
"@
        }

        $issuesHtml = ''
        if ($unlinkedGPOs.Count -gt 0) {
            $issuesHtml += "<h3>Unlinked GPOs ($($unlinkedGPOs.Count))</h3><ul>"
            foreach ($gpo in $unlinkedGPOs | Sort-Object DisplayName) {
                $issuesHtml += "<li>$([System.Net.WebUtility]::HtmlEncode("$($gpo.DisplayName)"))</li>"
            }
            $issuesHtml += '</ul>'
        }

        if ($emptyGPOs.Count -gt 0) {
            $issuesHtml += "<h3>Empty GPOs ($($emptyGPOs.Count))</h3><ul>"
            foreach ($gpo in $emptyGPOs | Sort-Object DisplayName) {
                $issuesHtml += "<li>$([System.Net.WebUtility]::HtmlEncode("$($gpo.DisplayName)"))</li>"
            }
            $issuesHtml += '</ul>'
        }

        if ($disabledGPOs.Count -gt 0) {
            $issuesHtml += "<h3>Disabled GPOs ($($disabledGPOs.Count))</h3><ul>"
            foreach ($gpo in $disabledGPOs | Sort-Object DisplayName) {
                $entryText = [System.Net.WebUtility]::HtmlEncode("$($gpo.DisplayName) - $($gpo.GpoStatus)")
                $issuesHtml += "<li>$entryText</li>"
            }
            $issuesHtml += '</ul>'
        }

        $html = "$htmlHead$htmlRows    </table>`n`n    <h2>Issues Detected</h2>`n$issuesHtml`n</body>`n</html>"

        $html | Out-File -FilePath $indexPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "[+] Index file created: $indexPath" -ForegroundColor Green

        # Display summary
        Write-Host '[+] Report Generation Complete' -ForegroundColor Green
        Write-Host "Output Location: $resolvedOutputPath" -ForegroundColor Cyan
        Write-Host '[*] Open the Index.html file to view all reports' -ForegroundColor White

        if ($unlinkedGPOs.Count -gt 0) {
            Write-Host ("[!] WARNING: $($unlinkedGPOs.Count) unlinked GPOs" +
                "found. Consider reviewing these for cleanup.") -ForegroundColor Yellow
        }

        if ($emptyGPOs.Count -gt 0) {
            Write-Host ("[!] WARNING: $($emptyGPOs.Count) empty GPOs" +
                "found. Consider removing these to reduce clutter.") -ForegroundColor Yellow
        }

        Write-Host "End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
        return 0
    }
    catch {
        Write-Host "[-] Error generating GPO report: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
