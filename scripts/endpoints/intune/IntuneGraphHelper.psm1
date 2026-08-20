<#
.SYNOPSIS
    Common helper module for Microsoft Graph API authentication and Intune operations.

.DESCRIPTION
    Provides reusable functions for connecting to Microsoft Graph API and performing
    common Intune operations. Used by all Intune Management Scripts.

.NOTES
    Author: IT Administration
    Requires: Microsoft.Graph PowerShell module
#>

function Connect-IntuneGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph API with required Intune permissions.

    .PARAMETER Scopes
        Array of permission scopes required for the operation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Scopes = @(
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementConfiguration.Read.All",
            "DeviceManagementApps.Read.All"
        )
    )

    try {
        # Check if Microsoft.Graph module is installed
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
            Write-Host "Microsoft.Graph module not found. Installing..." -ForegroundColor Yellow
            Install-Module Microsoft.Graph -Scope CurrentUser -Force
        }

        # Import required modules
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

        # Connect to Microsoft Graph
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
        Connect-MgGraph -Scopes $Scopes -NoWelcome

        $context = Get-MgContext
        if ($context) {
            Write-Host "✓ Connected to tenant: $($context.TenantId)" -ForegroundColor Green
            Write-Host "✓ Authenticated as: $($context.Account)" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "✗ Failed to connect to Microsoft Graph" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ Error connecting to Graph: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Disconnect-IntuneGraph {
    <#
    .SYNOPSIS
        Disconnects from Microsoft Graph API.
    #>
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Gray
    }
    catch {
        Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
    }
}

function Get-AllIntuneDevices {
    <#
    .SYNOPSIS
        Retrieves all managed devices from Intune with pagination support.
    #>
    try {
        Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop

        Write-Host "Retrieving all managed devices..." -ForegroundColor Cyan
        $devices = Get-MgDeviceManagementManagedDevice -All

        Write-Host "✓ Retrieved $($devices.Count) devices" -ForegroundColor Green
        return $devices
    }
    catch {
        Write-Host "✗ Error retrieving devices: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Export-IntuneReportToHTML {
    <#
    .SYNOPSIS
        Exports data to a formatted HTML report.

    .PARAMETER Data
        The data to export.

    .PARAMETER Title
        Report title.

    .PARAMETER FilePath
        Output file path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Data,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [string]$FilePath
    )

    if (-not $FilePath) {
        $FilePath = "$env:USERPROFILE\Desktop\$($Title.Replace(' ', '_'))_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$Title</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 15px; margin-bottom: 25px; }
        .summary { background-color: #e7f3ff; padding: 15px; border-radius: 5px; margin-bottom: 25px; border-left: 4px solid #0078d4; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; font-size: 14px; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .compliant { color: green; font-weight: bold; }
        .non-compliant { color: red; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
        .footer { margin-top: 30px; padding-top: 15px; border-top: 1px solid #ddd; color: #666; font-size: 12px; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h1>$Title</h1>
        <div class="summary">
            <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
            <p><strong>Total Records:</strong> $($Data.Count)</p>
        </div>
        <table>
"@

    if ($Data.Count -gt 0) {
        # Get properties for table headers
        $properties = $Data[0].PSObject.Properties.Name

        # Add headers
        $html += "<tr>"
        foreach ($prop in $properties) {
            $html += "<th>$prop</th>"
        }
        $html += "</tr>"

        # Add data rows
        foreach ($item in $Data) {
            $html += "<tr>"
            foreach ($prop in $properties) {
                $value = $item.$prop
                $class = ""

                # Apply styling based on content
                if ($value -match "compliant|success|healthy|encrypted" -and $value -notmatch "non") {
                    $class = "compliant"
                }
                elseif ($value -match "non-compliant|failed|error|not encrypted") {
                    $class = "non-compliant"
                }
                elseif ($value -match "warning|pending") {
                    $class = "warning"
                }

                $html += "<td class='$class'>$value</td>"
            }
            $html += "</tr>"
        }
    }
    else {
        $html += "<tr><td colspan='10' style='text-align:center; padding:30px; color:#666;'>No data available</td></tr>"
    }

    $html += @"
        </table>
        <div class="footer">
            Generated by Intune Management Scripts | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $FilePath -Encoding UTF8
    Write-Host "✓ Report exported to: $FilePath" -ForegroundColor Green

    # Open in browser
    Start-Process $FilePath

    return $FilePath
}

function Export-IntuneReportToCSV {
    <#
    .SYNOPSIS
        Exports data to CSV format.

    .PARAMETER Data
        The data to export.

    .PARAMETER Title
        Report title (used for filename).

    .PARAMETER FilePath
        Output file path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Data,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [string]$FilePath
    )

    if (-not $FilePath) {
        $FilePath = "$env:USERPROFILE\Desktop\$($Title.Replace(' ', '_'))_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    }

    $Data | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
    Write-Host "✓ CSV exported to: $FilePath" -ForegroundColor Green

    return $FilePath
}

# Export module functions
Export-ModuleMember -Function @(
    'Connect-IntuneGraph',
    'Disconnect-IntuneGraph',
    'Get-AllIntuneDevices',
    'Export-IntuneReportToHTML',
    'Export-IntuneReportToCSV'
)
