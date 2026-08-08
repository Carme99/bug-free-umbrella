<#
.SYNOPSIS
    Generates comprehensive Group Policy Object (GPO) reports for domain analysis.

.DESCRIPTION
    This script analyzes all Group Policy Objects in the domain and generates detailed
    reports including GPO settings, links, permissions, WMI filters, and potential issues.
    Useful for GPO auditing, troubleshooting, and documentation.

.PARAMETER OutputPath
    Path where the report files will be saved. Creates the directory if it doesn't exist.

.PARAMETER ReportFormat
    Format for the reports. Options: HTML, XML, Both. Default is Both.

.PARAMETER IncludeUnlinkedGPOs
    Switch to include GPOs that are not linked to any OU in the report.

.PARAMETER IncludeEmptyGPOs
    Switch to include GPOs that have no settings configured.

.PARAMETER ExportToCSV
    Switch to also export a summary CSV file with key GPO information.

.EXAMPLE
    .\Get-GPOReport.ps1 -OutputPath "C:\GPOReports"
    Generates both HTML and XML reports for all GPOs.

.EXAMPLE
    .\Get-GPOReport.ps1 -OutputPath "C:\GPOReports" -ReportFormat HTML -IncludeUnlinkedGPOs -ExportToCSV
    Generates HTML reports including unlinked GPOs and exports a CSV summary.

.NOTES
    Author: Server Management Team
    Requires: GroupPolicy PowerShell module, Domain Admin or equivalent permissions
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
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
# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Requires GroupPolicy module
#Requires -Module GroupPolicy

# Create output directory
if (-not (Test-Path -Path $OutputPath)) {
    try {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Host "Created output directory: $OutputPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create output directory: $_"
        exit 1
    }
}

$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

Write-Host "`n=== Group Policy Object Report Generator ===" -ForegroundColor Cyan
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

try {
    # Get domain information
    Write-Host "`nGathering domain information..." -ForegroundColor Yellow
    $domain = Get-ADDomain
    $domainName = $domain.DNSRoot
    Write-Host "Domain: $domainName" -ForegroundColor Green

    # Get all GPOs
    Write-Host "`nRetrieving all Group Policy Objects..." -ForegroundColor Yellow
    $allGPOs = Get-GPO -All -Domain $domainName
    $totalGPOs = $allGPOs.Count
    Write-Host "Found $totalGPOs GPOs" -ForegroundColor Green

    # Initialize summary data
    $gpoSummary = @()
    $unlinkedGPOs = @()
    $emptyGPOs = @()
    $disabledGPOs = @()

    $counter = 0

    foreach ($gpo in $allGPOs) {
        $counter++
        $percentComplete = [math]::Round(($counter / $totalGPOs) * 100)
        Write-Progress -Activity "Processing GPOs" -Status "Processing $($gpo.DisplayName) ($counter of $totalGPOs)" -PercentComplete $percentComplete

        # Get GPO details
        $gpoGuid = $gpo.Id
        $gpoName = $gpo.DisplayName
        $gpoCreated = $gpo.CreationTime
        $gpoModified = $gpo.ModificationTime
        $gpoStatus = $gpo.GpoStatus

        # Check if GPO is disabled
        if ($gpoStatus -like "*Disabled*") {
            $disabledGPOs += $gpo
        }

        # Get GPO links
        $gpoReport = [xml](Get-GPOReport -Guid $gpoGuid -ReportType XML)
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
        $wmiFilter = if ($gpo.WmiFilter) { $gpo.WmiFilter.Name } else { "None" }

        # Create summary object
        $gpoSummary += [PSCustomObject]@{
            Name = $gpoName
            GUID = $gpoGuid
            Status = $gpoStatus
            Created = $gpoCreated
            Modified = $gpoModified
            LinkCount = $linkCount
            IsUnlinked = $isUnlinked
            IsEmpty = $isEmpty
            ComputerEnabled = $computerEnabled
            UserEnabled = $userEnabled
            ComputerVersion = $computerVersion
            UserVersion = $userVersion
            WMIFilter = $wmiFilter
            Owner = $gpo.Owner
        }

        # Generate individual GPO reports
        $safeFileName = $gpoName -replace '[\\/:*?"<>|]', '_'

        if ($ReportFormat -eq 'HTML' -or $ReportFormat -eq 'Both') {
            $htmlPath = Join-Path -Path $OutputPath -ChildPath "$safeFileName.html"
            Get-GPOReport -Guid $gpoGuid -ReportType HTML -Path $htmlPath
        }

        if ($ReportFormat -eq 'XML' -or $ReportFormat -eq 'Both') {
            $xmlPath = Join-Path -Path $OutputPath -ChildPath "$safeFileName.xml"
            Get-GPOReport -Guid $gpoGuid -ReportType XML -Path $xmlPath
        }
    }

    Write-Progress -Activity "Processing GPOs" -Completed

    # Generate summary report
    Write-Host "`n=== GPO Summary ===" -ForegroundColor Cyan
    Write-Host "Total GPOs: $totalGPOs" -ForegroundColor White
    Write-Host "Unlinked GPOs: $($unlinkedGPOs.Count)" -ForegroundColor $(if ($unlinkedGPOs.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "Empty GPOs: $($emptyGPOs.Count)" -ForegroundColor $(if ($emptyGPOs.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "Disabled GPOs: $($disabledGPOs.Count)" -ForegroundColor $(if ($disabledGPOs.Count -gt 0) { 'Yellow' } else { 'Green' })

    # Export CSV summary
    if ($ExportToCSV) {
        Write-Host "`nExporting CSV summary..." -ForegroundColor Yellow
        $csvPath = Join-Path -Path $OutputPath -ChildPath "GPO_Summary_${RunTimestamp}_${RunId}.csv"
        $gpoSummary | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "CSV exported to: $csvPath" -ForegroundColor Green
    }

    # Create index HTML file
    Write-Host "`nGenerating index file..." -ForegroundColor Yellow
    $indexPath = Join-Path -Path $OutputPath -ChildPath "Index.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Group Policy Report - $([System.Net.WebUtility]::HtmlEncode("$domainName"))</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
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
        <tr><td><strong>Unlinked GPOs</strong></td><td class="$(if ($unlinkedGPOs.Count -gt 0) { 'warning' } else { 'good' })">$($unlinkedGPOs.Count)</td></tr>
        <tr><td><strong>Empty GPOs</strong></td><td class="$(if ($emptyGPOs.Count -gt 0) { 'warning' } else { 'good' })">$($emptyGPOs.Count)</td></tr>
        <tr><td><strong>Disabled GPOs</strong></td><td class="$(if ($disabledGPOs.Count -gt 0) { 'warning' } else { 'good' })">$($disabledGPOs.Count)</td></tr>
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

    foreach ($gpo in $gpoSummary | Sort-Object -Property Name) {
        $safeFileName = $gpo.Name -replace '[\\/:*?"<>|]', '_'
        $statusClass = if ($gpo.IsUnlinked -or $gpo.IsEmpty) { 'warning' } else { '' }
        $statusText = $gpo.Status
        if ($gpo.IsUnlinked) { $statusText += " (Unlinked)" }
        if ($gpo.IsEmpty) { $statusText += " (Empty)" }

        $html += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($gpo.Name)"))</td>
            <td class="$statusClass">$([System.Net.WebUtility]::HtmlEncode("$statusText"))</td>
            <td>$($gpo.LinkCount)</td>
            <td>$($gpo.Modified.ToString('yyyy-MM-dd HH:mm'))</td>
            <td>
"@
        if ($ReportFormat -eq 'HTML' -or $ReportFormat -eq 'Both') {
            $html += "<a href='$safeFileName.html'>HTML</a> "
        }
        if ($ReportFormat -eq 'XML' -or $ReportFormat -eq 'Both') {
            $html += "<a href='$safeFileName.xml'>XML</a>"
        }
        $html += @"
            </td>
        </tr>
"@
    }

    $html += @"
    </table>

    <h2>Issues Detected</h2>
"@

    if ($unlinkedGPOs.Count -gt 0) {
        $html += "<h3>Unlinked GPOs ($($unlinkedGPOs.Count))</h3><ul>"
        foreach ($gpo in $unlinkedGPOs | Sort-Object DisplayName) {
            $html += "<li>$([System.Net.WebUtility]::HtmlEncode("$($gpo.DisplayName)"))</li>"
        }
        $html += "</ul>"
    }

    if ($emptyGPOs.Count -gt 0) {
        $html += "<h3>Empty GPOs ($($emptyGPOs.Count))</h3><ul>"
        foreach ($gpo in $emptyGPOs | Sort-Object DisplayName) {
            $html += "<li>$([System.Net.WebUtility]::HtmlEncode("$($gpo.DisplayName)"))</li>"
        }
        $html += "</ul>"
    }

    if ($disabledGPOs.Count -gt 0) {
        $html += "<h3>Disabled GPOs ($($disabledGPOs.Count))</h3><ul>"
        foreach ($gpo in $disabledGPOs | Sort-Object DisplayName) {
            $html += "<li>$([System.Net.WebUtility]::HtmlEncode("$($gpo.DisplayName) - $($gpo.GpoStatus)"))</li>"
        }
        $html += "</ul>"
    }

    $html += @"
</body>
</html>
"@

    $html | Out-File -FilePath $indexPath -Encoding UTF8
    Write-Host "Index file created: $indexPath" -ForegroundColor Green

    # Display summary
    Write-Host "`n=== Report Generation Complete ===" -ForegroundColor Green
    Write-Host "Output Location: $OutputPath" -ForegroundColor Cyan
    Write-Host "Open the Index.html file to view all reports" -ForegroundColor White

    if ($unlinkedGPOs.Count -gt 0) {
        Write-Host "`nWARNING: $($unlinkedGPOs.Count) unlinked GPOs found. Consider reviewing these for cleanup." -ForegroundColor Yellow
    }

    if ($emptyGPOs.Count -gt 0) {
        Write-Host "WARNING: $($emptyGPOs.Count) empty GPOs found. Consider removing these to reduce clutter." -ForegroundColor Yellow
    }

}
catch {
    Write-Error "Error generating GPO report: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host "`nEnd Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
