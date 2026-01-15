<#
.SYNOPSIS
    Creates a cloned virtual machine and an Azure Compute Gallery (ACG) image version from a gold VM.

.DESCRIPTION
    This script automates a complete AVD/Windows image pipeline workflow:
      1) Azure authentication (tenant + subscription context)
      2) Optional pre-flight validation of the Azure Guest Agent on the source VM
      3) Snapshot the source OS disk and materialize a managed disk copy
      4) Create a temporary clone VM from that disk in an isolated resource group
      5) Wait for the VM Agent to be Ready (required for Run Command)
      6) Run Sysprep (generalize) via Run Command on the cloned VM
      7) Generalize VM in Azure, then create a managed image
      8) Publish as an Azure Compute Gallery image version (semantic versioning)
      9) Clean up all temporary resources

    Key design choices:
      - Snapshots and copies the OS disk from the source VM (no mutation)
      - Temporary resource group for all intermediate artifacts (easy cleanup)
      - Semantic versioning with configurable increment strategy (major, minor, patch)
      - Interactive mode with ASCII art and colorful progress indicators
      - Configuration file support for repeatable deployments
      - Source VM can be powered off or on

.PARAMETER ConfigFile
    Path to a JSON configuration file containing all required parameters.
    Use -GenerateConfig to create a template configuration file.

.PARAMETER GenerateConfig
    Generates a template configuration file and exits. Optionally specify output path.

.PARAMETER Interactive
    Run in interactive mode with prompts for all required information.
    This is the default if no ConfigFile is provided.

.PARAMETER TenantId
    Azure Active Directory Tenant ID.

.PARAMETER SubscriptionId
    Azure Subscription ID where resources will be created.

.PARAMETER Location
    Azure region where temporary resources and images will be created.

.PARAMETER SourceVMName
    Name of the source/gold VM to clone and capture.

.PARAMETER SourceVMResourceGroup
    Resource group containing the source VM.

.PARAMETER GalleryResourceGroup
    Resource group containing the Azure Compute Gallery.

.PARAMETER GalleryName
    Name of the Azure Compute Gallery.

.PARAMETER ImageDefinitionName
    Name of the image definition within the gallery.

.PARAMETER VMSize
    Size for the temporary clone VM (e.g., Standard_D2as_v6).

.PARAMETER VNetName
    Name of the virtual network for the temporary VM.

.PARAMETER VNetResourceGroup
    Resource group containing the virtual network.

.PARAMETER SubnetName
    Name of the subnet within the VNet.

.PARAMETER VersioningStrategy
    How to increment the version: Major, Minor, or Patch.
    Default is Major (produces N.0.0 versions).

.PARAMETER SkipAgentCheck
    Skip the pre-flight check of the source VM's guest agent status.

.PARAMETER SkipPreFlightChecks
    Skip all pre-flight validation checks. Useful for advanced users or CI/CD
    pipelines where validation is performed separately.

.PARAMETER SkipCleanup
    Keep temporary resources for debugging. Not recommended for production.

.PARAMETER Force
    Run non-interactively without confirmation prompts.

.PARAMETER WhatIf
    Dry-run mode. Validates configuration and runs pre-flight checks without
    creating any resources. Useful for testing configurations.

.EXAMPLE
    .\New-AzureComputeGalleryImage.ps1

    Auto-discovers JSON configuration files in the script directory and prompts
    for selection. If no JSON files found, runs in interactive mode.

.EXAMPLE
    .\New-AzureComputeGalleryImage.ps1 -Interactive

    Runs in interactive mode with guided prompts for all configuration,
    bypassing JSON auto-discovery.

.EXAMPLE
    .\New-AzureComputeGalleryImage.ps1 -GenerateConfig -ConfigFile ".\my-config.json"

    Generates a template configuration file at the specified path.

.EXAMPLE
    .\New-AzureComputeGalleryImage.ps1 -ConfigFile ".\my-config.json"

    Runs using settings from the specified configuration file.

.EXAMPLE
    .\New-AzureComputeGalleryImage.ps1 -ConfigFile ".\prod-config.json" -WhatIf

    Validates the configuration and runs pre-flight checks without creating any
    resources. Perfect for testing before actual execution.

.EXAMPLE
    .\New-AzureComputeGalleryImage.ps1 -SourceVMName "WIN11-GOLD" -SourceVMResourceGroup "rg-images" `
        -GalleryName "MyGallery" -GalleryResourceGroup "rg-images" -ImageDefinitionName "Win11-Enterprise" `
        -TenantId "..." -SubscriptionId "..." -Location "East US" -VMSize "Standard_D2s_v3" `
        -VNetName "vnet-prod" -VNetResourceGroup "rg-network" -SubnetName "snet-images"

    Runs with all parameters specified on command line.

.NOTES
    Requirements:
      - Az PowerShell modules (Az.Accounts, Az.Compute, Az.Network, Az.Resources)
      - RBAC permissions to create resources and publish to the gallery
      - Outbound network connectivity to Azure platform (168.63.129.16) and HTTPS
      - Gallery and image definition must already exist
      - Source VM must have Azure Windows Guest Agent installed

    New in v3.5:
      - JSON configuration auto-discovery from script directory
      - Configuration schema validation with detailed error messages
      - Configuration preview before execution
      - Pre-flight validation checks (7 checks before resource creation)
      - Dry-run mode (-WhatIf) for testing without creating resources
      - Execution time tracking and detailed logging to file
      - Step-by-step timing breakdowns in final summary

    Author: Jack Lee
    Version: 3.5
    Last Updated: 15/01/2026
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'ConfigFile', Mandatory)]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Leaf)) {
            throw "Configuration file not found: $_"
        }
        if ($_ -notmatch '\.json$') {
            throw "Configuration file must be a JSON file: $_"
        }
        return $true
    })]
    [string]$ConfigFile,

    [Parameter(ParameterSetName = 'GenerateConfig')]
    [switch]$GenerateConfig,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$SubscriptionId,

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$Location,

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$SourceVMName,

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$SourceVMResourceGroup,

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$GalleryResourceGroup,

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$GalleryName,

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$ImageDefinitionName,

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$VMSize = 'Standard_D2s_v3',

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$VNetName,

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$VNetResourceGroup,

    [Parameter(ParameterSetName = 'Explicit')]
    [string]$SubnetName,

    [ValidateSet('Major', 'Minor', 'Patch')]
    [string]$VersioningStrategy = 'Major',

    [switch]$SkipAgentCheck,

    [switch]$SkipCleanup,

    [switch]$SkipPreFlightChecks,

    [switch]$Force,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Suppress default progress bars
$ScriptVersion = "3.5"

# ==========================
# ASCII Art & Branding
# ==========================
function Show-Banner {
    $border = @"
    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄  ║
    ║  █┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼█  ║
    ║  █┼                                                                      ┼█  ║
"@

    $azureText = @"
    ║  █┼    █████╗ ███████╗██╗   ██╗██████╗ ███████╗                          ┼█  ║
    ║  █┼   ██╔══██╗╚══███╔╝██║   ██║██╔══██╗██╔════╝                          ┼█  ║
    ║  █┼   ███████║  ███╔╝ ██║   ██║██████╔╝█████╗                            ┼█  ║
    ║  █┼   ██╔══██║ ███╔╝  ██║   ██║██╔══██╗██╔══╝                            ┼█  ║
    ║  █┼   ██║  ██║███████╗╚██████╔╝██║  ██║███████╗                          ┼█  ║
    ║  █┼   ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝                          ┼█  ║
"@

    $divider = @"
    ║  █┼                                                                      ┼█  ║
    ║  █┼   ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀            ┼█  ║
"@

    $computeText = @"
    ║  █┼    ██████╗ ██████╗ ███╗   ███╗██████╗ ██╗   ██╗████████╗███████╗     ┼█  ║
    ║  █┼   ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██║   ██║╚══██╔══╝██╔════╝     ┼█  ║
    ║  █┼   ██║     ██║   ██║██╔████╔██║██████╔╝██║   ██║   ██║   █████╗       ┼█  ║
    ║  █┼   ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██║   ██║   ██║   ██╔══╝       ┼█  ║
    ║  █┼   ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ╚██████╔╝   ██║   ███████╗     ┼█  ║
    ║  █┼    ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝      ╚═════╝    ╚═╝   ╚══════╝     ┼█  ║
"@

    $titleBox = @"
    ║  █┼                                                                      ┼█  ║
    ║  █┼   ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓  ┼█  ║
"@

    $titleText = @"
    ║  █┼   ┃   « GALLERY IMAGE BUILDER v$ScriptVersion »    ░▒▓█ PIPELINE █▓▒░        ┃  ┼█  ║
"@

    $titleBoxClose = @"
    ║  █┼   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛  ┼█  ║
    ║  █┼                                                                      ┼█  ║
"@

    $pipeline = @"
    ║  █┼     [VM]═════►[SYSPREP]═════►[CAPTURE]═════►[PUBLISH]                ┼█  ║
"@

    $pipelineProgress = @"
    ║  █┼      ░░          ▒▒▒           ▓▓▓▓           ████                   ┼█  ║
"@

    $author = @"
    ║  █┼                                                                      ┼█  ║
    ║  █┼        Crafted with ♥ and mass quantities of caffeine by:            ┼█  ║
    ║  █┼                          ★ Jack Lee ★                                ┼█  ║
"@

    $footer = @"
    ║  █┼                                                                      ┼█  ║
    ║  █┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼█  ║
    ║  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀  ║
    ╚══════════════════════════════════════════════════════════════════════════════╝
"@

    # Display with colours
    Write-Host $border -ForegroundColor DarkCyan
    Write-Host $azureText -ForegroundColor Cyan
    Write-Host $divider -ForegroundColor DarkCyan
    Write-Host $computeText -ForegroundColor Blue
    Write-Host $titleBox -ForegroundColor DarkCyan
    Write-Host $titleText -ForegroundColor Yellow
    Write-Host $titleBoxClose -ForegroundColor DarkCyan
    Write-Host $pipeline -ForegroundColor Green
    Write-Host $pipelineProgress -ForegroundColor Magenta
    Write-Host $author -ForegroundColor White
    Write-Host $footer -ForegroundColor DarkCyan
}
# ==========================
# Enhanced Console Output Functions
# ==========================
function Write-Success {
    param([string]$Message)
    Write-Host "✓ " -ForegroundColor Green -NoNewline
    Write-Host $Message -ForegroundColor White
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ " -ForegroundColor Blue -NoNewline
    Write-Host $Message -ForegroundColor White
}

function Write-Warning2 {
    param([string]$Message)
    Write-Host "⚠ " -ForegroundColor Yellow -NoNewline
    Write-Host $Message -ForegroundColor White
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "✗ " -ForegroundColor Red -NoNewline
    Write-Host $Message -ForegroundColor White
}

function Write-Header {
    param([string]$Message)
    $border = "═" * ($Message.Length + 4)
    Write-Host ""
    Write-Host "╔$border╗" -ForegroundColor Magenta
    Write-Host "║  $Message  ║" -ForegroundColor Magenta
    Write-Host "╚$border╝" -ForegroundColor Magenta
    Write-Host ""
}

function Write-Step {
    param(
        [int]$Step,
        [int]$TotalSteps,
        [string]$Message
    )
    Write-Host ""
    Write-Host "┌─ Step $Step of $TotalSteps " -ForegroundColor Cyan -NoNewline
    Write-Host ("─" * (60 - "┌─ Step $Step of $TotalSteps ".Length))  -ForegroundColor Cyan
    Write-Host "│ " -ForegroundColor Cyan -NoNewline
    Write-Host $Message -ForegroundColor White
    Write-Host "└" -ForegroundColor Cyan -NoNewline
    Write-Host ("─" * 70) -ForegroundColor Cyan
}

function Write-ProgressBar {
    param(
        [int]$Percent,
        [string]$Activity,
        [string]$Status = ""
    )

    $width = 50
    $completed = [math]::Floor($width * $Percent / 100)
    $remaining = $width - $completed

    $bar = "█" * $completed + "░" * $remaining

    Write-Host "`r" -NoNewline
    Write-Host "  $Activity : [" -NoNewline -ForegroundColor Cyan
    Write-Host $bar -NoNewline -ForegroundColor Green
    Write-Host "] $Percent% " -NoNewline -ForegroundColor Cyan
    if ($Status) {
        Write-Host "- $Status" -NoNewline -ForegroundColor Gray
    }
}

# ==========================
# Configuration Management
# ==========================
function New-ConfigTemplate {
    param([string]$Path)

    $template = @{
        TenantId = "00000000-0000-0000-0000-000000000000"
        SubscriptionId = "00000000-0000-0000-0000-000000000000"
        Location = "East US"
        SourceVM = @{
            Name = "YourGoldVM"
            ResourceGroup = "rg-images"
        }
        Gallery = @{
            ResourceGroup = "rg-images"
            Name = "MyComputeGallery"
            ImageDefinitionName = "Windows11-Enterprise"
        }
        Network = @{
            VNetName = "vnet-prod"
            VNetResourceGroup = "rg-network"
            SubnetName = "snet-default"
        }
        TempVM = @{
            Size = "Standard_D2s_v3"
        }
        Options = @{
            VersioningStrategy = "Major"
            SkipAgentCheck = $false
            SkipCleanup = $false
        }
    } | ConvertTo-Json -Depth 10

    $template | Out-File -FilePath $Path -Encoding UTF8
    Write-Success "Configuration template created: $Path"
    Write-Info "Edit this file with your Azure environment details, then run:"
    Write-Host "  .\New-AzureComputeGalleryImage.ps1 -ConfigFile '$Path'" -ForegroundColor Yellow
}

function Read-Configuration {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-ErrorMsg "Configuration file not found: $Path"
        exit 1
    }

    try {
        $config = Get-Content $Path -Raw | ConvertFrom-Json
        return $config
    } catch {
        Write-ErrorMsg "Failed to parse configuration file: $($_.Exception.Message)"
        exit 1
    }
}

function Test-ConfigurationSchema {
    param([object]$Config)

    $requiredFields = @{
        'TenantId' = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
        'SubscriptionId' = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
        'Location' = '.+'
        'SourceVM.Name' = '.+'
        'SourceVM.ResourceGroup' = '.+'
        'Gallery.ResourceGroup' = '.+'
        'Gallery.Name' = '.+'
        'Gallery.ImageDefinitionName' = '.+'
        'Network.VNetName' = '.+'
        'Network.VNetResourceGroup' = '.+'
        'Network.SubnetName' = '.+'
        'TempVM.Size' = '^Standard_[A-Za-z0-9_]+'
    }

    $validStrategies = @('Major', 'Minor', 'Patch')

    $errors = @()

    foreach ($field in $requiredFields.Keys) {
        $value = $Config
        foreach ($part in $field.Split('.')) {
            $value = $value.$part
        }
        if (-not $value) {
            $errors += "Missing required field: $field"
        } elseif ($value -notmatch $requiredFields[$field]) {
            $errors += "Invalid format for $field : $value"
        }
    }

    if ($Config.Options.VersioningStrategy -and $Config.Options.VersioningStrategy -notin $validStrategies) {
        $errors += "Invalid VersioningStrategy. Must be: $($validStrategies -join ', ')"
    }

    return $errors
}

function Show-ConfigPreview {
    param(
        [hashtable]$Config,
        [string]$Strategy
    )

    Write-Header "Configuration Preview"
    Write-Host "Source VM:" -ForegroundColor Cyan
    Write-Host "  $($Config.SourceVMName) " -NoNewline -ForegroundColor Yellow
    Write-Host "($($Config.SourceVMResourceGroup))" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Target Gallery:" -ForegroundColor Cyan
    Write-Host "  $($Config.GalleryName)/$($Config.ImageDefinitionName)" -ForegroundColor Yellow
    Write-Host "  Location: " -NoNewline -ForegroundColor Gray
    Write-Host $Config.Location -ForegroundColor White
    Write-Host "  Strategy: " -NoNewline -ForegroundColor Gray
    Write-Host $Strategy -ForegroundColor White
    Write-Host ""

    if (-not $Force) {
        $confirm = Read-Host "Use this configuration? (Y/N)"
        if ($confirm -ne 'Y' -and $confirm -ne 'y') {
            Write-Warning2 "Configuration declined"
            exit 0
        }
    }
}

function Test-PreFlightChecks {
    param([hashtable]$Config)

    Write-Header "Pre-Flight Validation"
    $checks = @()

    # Check 1: Source VM exists and accessible
    Write-Host "  [1/7] Checking source VM..." -NoNewline -ForegroundColor Cyan
    try {
        $vm = Get-AzVM -ResourceGroupName $Config.SourceVMResourceGroup -Name $Config.SourceVMName -ErrorAction Stop
        Write-Host " ✓" -ForegroundColor Green
        $checks += @{Name="Source VM"; Status="Pass"; Details="Found"}
    } catch {
        Write-Host " ✗" -ForegroundColor Red
        $checks += @{Name="Source VM"; Status="Fail"; Details=$_.Exception.Message}
    }

    # Check 2: Gallery exists
    Write-Host "  [2/7] Checking gallery..." -NoNewline -ForegroundColor Cyan
    try {
        $gallery = Get-AzGallery -ResourceGroupName $Config.GalleryResourceGroup -Name $Config.GalleryName -ErrorAction Stop
        Write-Host " ✓" -ForegroundColor Green
        $checks += @{Name="Gallery"; Status="Pass"; Details="Found"}
    } catch {
        Write-Host " ✗" -ForegroundColor Red
        $checks += @{Name="Gallery"; Status="Fail"; Details=$_.Exception.Message}
    }

    # Check 3: Image Definition exists
    Write-Host "  [3/7] Checking image definition..." -NoNewline -ForegroundColor Cyan
    try {
        $imageDef = Get-AzGalleryImageDefinition -ResourceGroupName $Config.GalleryResourceGroup -GalleryName $Config.GalleryName -Name $Config.ImageDefinitionName -ErrorAction Stop
        Write-Host " ✓" -ForegroundColor Green
        $checks += @{Name="Image Definition"; Status="Pass"; Details="Found"}
    } catch {
        Write-Host " ✗" -ForegroundColor Red
        $checks += @{Name="Image Definition"; Status="Fail"; Details=$_.Exception.Message}
    }

    # Check 4: VNet and Subnet exist
    Write-Host "  [4/7] Checking network..." -NoNewline -ForegroundColor Cyan
    try {
        $vnet = Get-AzVirtualNetwork -Name $Config.VNetName -ResourceGroupName $Config.VNetResourceGroup -ErrorAction Stop
        $subnet = Get-AzVirtualNetworkSubnetConfig -Name $Config.SubnetName -VirtualNetwork $vnet -ErrorAction Stop
        Write-Host " ✓" -ForegroundColor Green
        $checks += @{Name="Network"; Status="Pass"; Details="VNet and Subnet found"}
    } catch {
        Write-Host " ✗" -ForegroundColor Red
        $checks += @{Name="Network"; Status="Fail"; Details=$_.Exception.Message}
    }

    # Check 5: RBAC permissions (basic)
    Write-Host "  [5/7] Checking permissions..." -NoNewline -ForegroundColor Cyan
    try {
        $context = Get-AzContext
        $sub = Get-AzSubscription -SubscriptionId $Config.SubscriptionId -ErrorAction Stop
        Write-Host " ✓" -ForegroundColor Green
        $checks += @{Name="Permissions"; Status="Pass"; Details="Subscription accessible"}
    } catch {
        Write-Host " ✗" -ForegroundColor Red
        $checks += @{Name="Permissions"; Status="Fail"; Details="Cannot access subscription"}
    }

    # Check 6: VM Size available in region
    Write-Host "  [6/7] Checking VM size availability..." -NoNewline -ForegroundColor Cyan
    try {
        $vmSizes = Get-AzVMSize -Location $Config.Location | Where-Object { $_.Name -eq $Config.VMSize }
        if ($vmSizes) {
            Write-Host " ✓" -ForegroundColor Green
            $checks += @{Name="VM Size"; Status="Pass"; Details="$($Config.VMSize) available"}
        } else {
            Write-Host " ✗" -ForegroundColor Red
            $checks += @{Name="VM Size"; Status="Fail"; Details="$($Config.VMSize) not available in $($Config.Location)"}
        }
    } catch {
        Write-Host " ⚠" -ForegroundColor Yellow
        $checks += @{Name="VM Size"; Status="Warning"; Details="Could not verify"}
    }

    # Check 7: Disk encryption status
    Write-Host "  [7/7] Checking disk encryption..." -NoNewline -ForegroundColor Cyan
    try {
        $vmForEncryption = Get-AzVM -ResourceGroupName $Config.SourceVMResourceGroup -Name $Config.SourceVMName -ErrorAction SilentlyContinue
        if ($vmForEncryption -and $vmForEncryption.StorageProfile.OsDisk.EncryptionSettings.Enabled) {
            Write-Host " ⚠" -ForegroundColor Yellow
            $checks += @{Name="Disk Encryption"; Status="Warning"; Details="OS disk is encrypted - may cause issues"}
        } else {
            Write-Host " ✓" -ForegroundColor Green
            $checks += @{Name="Disk Encryption"; Status="Pass"; Details="Not encrypted"}
        }
    } catch {
        Write-Host " ⚠" -ForegroundColor Yellow
        $checks += @{Name="Disk Encryption"; Status="Warning"; Details="Could not verify"}
    }

    Write-Host ""

    # Summary
    $failures = $checks | Where-Object { $_.Status -eq "Fail" }
    $warnings = $checks | Where-Object { $_.Status -eq "Warning" }

    if ($failures) {
        Write-ErrorMsg "Pre-flight checks failed ($($failures.Count) failures):"
        foreach ($failure in $failures) {
            Write-Host "  • $($failure.Name): " -NoNewline -ForegroundColor Red
            Write-Host $failure.Details -ForegroundColor Gray
        }
        return $false
    }

    if ($warnings) {
        Write-Warning2 "Pre-flight checks passed with warnings ($($warnings.Count) warnings):"
        foreach ($warning in $warnings) {
            Write-Host "  • $($warning.Name): " -NoNewline -ForegroundColor Yellow
            Write-Host $warning.Details -ForegroundColor Gray
        }
    } else {
        Write-Success "All pre-flight checks passed!"
    }

    return $true
}

function Get-InteractiveConfiguration {
    Write-Header "Interactive Configuration Wizard"
    Write-Info "Let's gather the information needed to build your Azure Compute Gallery image."
    Write-Host ""

    $config = @{}

    # Azure Authentication
    Write-Host "Azure Authentication" -ForegroundColor Cyan
    Write-Host ("─" * 70) -ForegroundColor DarkGray
    $config.TenantId = Read-Host "  Enter Azure Tenant ID"
    $config.SubscriptionId = Read-Host "  Enter Azure Subscription ID"
    $config.Location = Read-Host "  Enter Azure Location (e.g., 'East US', 'UK South')"
    Write-Host ""

    # Source VM
    Write-Host "Source VM (Gold Image)" -ForegroundColor Cyan
    Write-Host ("─" * 70) -ForegroundColor DarkGray
    $config.SourceVMName = Read-Host "  Enter source VM name"
    $config.SourceVMResourceGroup = Read-Host "  Enter source VM resource group"
    Write-Host ""

    # Gallery Configuration
    Write-Host "Azure Compute Gallery" -ForegroundColor Cyan
    Write-Host ("─" * 70) -ForegroundColor DarkGray
    $config.GalleryResourceGroup = Read-Host "  Enter gallery resource group"
    $config.GalleryName = Read-Host "  Enter gallery name"
    $config.ImageDefinitionName = Read-Host "  Enter image definition name"
    Write-Host ""

    # Network Configuration
    Write-Host "Network Configuration (for temporary VM)" -ForegroundColor Cyan
    Write-Host ("─" * 70) -ForegroundColor DarkGray
    $config.VNetResourceGroup = Read-Host "  Enter VNet resource group"
    $config.VNetName = Read-Host "  Enter VNet name"
    $config.SubnetName = Read-Host "  Enter subnet name"
    Write-Host ""

    # VM Size
    Write-Host "Temporary VM Configuration" -ForegroundColor Cyan
    Write-Host ("─" * 70) -ForegroundColor DarkGray
    $defaultSize = "Standard_D2s_v3"
    $vmSize = Read-Host "  Enter VM size (default: $defaultSize)"
    $config.VMSize = if ($vmSize) { $vmSize } else { $defaultSize }
    Write-Host ""

    # Versioning Strategy
    Write-Host "Versioning Strategy" -ForegroundColor Cyan
    Write-Host ("─" * 70) -ForegroundColor DarkGray
    Write-Host "  1. Major (N.0.0) - Recommended for significant changes" -ForegroundColor Gray
    Write-Host "  2. Minor (N.M.0) - For feature additions" -ForegroundColor Gray
    Write-Host "  3. Patch (N.M.P) - For bug fixes" -ForegroundColor Gray
    $versionChoice = Read-Host "  Select versioning strategy (1-3, default: 1)"
    $config.VersioningStrategy = switch ($versionChoice) {
        "2" { "Minor" }
        "3" { "Patch" }
        default { "Major" }
    }
    Write-Host ""

    # Save Configuration Option
    Write-Host "Configuration Complete!" -ForegroundColor Green
    $saveConfig = Read-Host "  Would you like to save this configuration for future use? (Y/N)"
    if ($saveConfig -eq 'Y' -or $saveConfig -eq 'y') {
        $configPath = Read-Host "  Enter path for config file (e.g., .\my-config.json)"
        if ($configPath) {
            $configObj = @{
                TenantId = $config.TenantId
                SubscriptionId = $config.SubscriptionId
                Location = $config.Location
                SourceVM = @{
                    Name = $config.SourceVMName
                    ResourceGroup = $config.SourceVMResourceGroup
                }
                Gallery = @{
                    ResourceGroup = $config.GalleryResourceGroup
                    Name = $config.GalleryName
                    ImageDefinitionName = $config.ImageDefinitionName
                }
                Network = @{
                    VNetName = $config.VNetName
                    VNetResourceGroup = $config.VNetResourceGroup
                    SubnetName = $config.SubnetName
                }
                TempVM = @{
                    Size = $config.VMSize
                }
                Options = @{
                    VersioningStrategy = $config.VersioningStrategy
                    SkipAgentCheck = $false
                    SkipCleanup = $false
                }
            }

            $configObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8
            Write-Success "Configuration saved to: $configPath"
        }
    }
    Write-Host ""

    return $config
}

# ==========================
# Azure Authentication
# ==========================
function Connect-AzureEnvironment {
    param(
        [string]$TenantId,
        [string]$SubscriptionId
    )

    try {
        Write-Info "Authenticating to Azure..."
        Connect-AzAccount -Tenant $TenantId -Subscription $SubscriptionId -ErrorAction Stop | Out-Null

        $context = Get-AzContext
        Write-Success "Authenticated to Azure"
        Write-Host "  Subscription: " -NoNewline -ForegroundColor Gray
        Write-Host $context.Subscription.Name -ForegroundColor White
        Write-Host "  Tenant: " -NoNewline -ForegroundColor Gray
        Write-Host $context.Tenant.Id -ForegroundColor White
        return $true
    } catch {
        Write-ErrorMsg "Failed to authenticate to Azure: $($_.Exception.Message)"
        return $false
    }
}

# ==========================
# VM Agent Status Functions
# ==========================
function Get-GuestAgentStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $Name -Status -ErrorAction Stop
        $agentStatus = ($vm.VMAgent.Statuses | Where-Object Code -like 'ProvisioningState/*').DisplayStatus
        return $agentStatus
    } catch {
        return $null
    }
}

function Wait-ForVMAgent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$Name,

        [int]$TimeoutMinutes = 15
    )

    $startTime = Get-Date
    $deadline = $startTime.AddMinutes($TimeoutMinutes)
    $iteration = 0

    while ((Get-Date) -lt $deadline) {
        $iteration++
        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
        $percent = [math]::Min(100, [math]::Max(0, ($elapsed / ($TimeoutMinutes * 60)) * 100))

        try {
            $status = Get-GuestAgentStatus -ResourceGroupName $ResourceGroupName -Name $Name

            if ($status -eq 'Ready') {
                Write-ProgressBar -Percent 100 -Activity "VM Agent Check" -Status "Ready!"
                Write-Host ""
                Write-Success "VM Agent is ready on '$Name'"
                return $true
            }

            $displayStatus = if ($status) { $status } else { "Waiting for status..." }
            Write-ProgressBar -Percent $percent -Activity "VM Agent Check" -Status $displayStatus

        } catch {
            Write-ProgressBar -Percent $percent -Activity "VM Agent Check" -Status "Checking..."
        }

        Start-Sleep -Seconds 15
    }

    Write-Host ""
    Write-ErrorMsg "VM Agent did not become ready within $TimeoutMinutes minutes"
    return $false
}

# ==========================
# Version Management
# ==========================
function Get-NextImageVersion {
    param(
        [string]$ResourceGroupName,
        [string]$GalleryName,
        [string]$ImageDefinitionName,
        [ValidateSet('Major', 'Minor', 'Patch')]
        [string]$Strategy = 'Major'
    )

    $versions = Get-AzGalleryImageVersion `
        -ResourceGroupName $ResourceGroupName `
        -GalleryName $GalleryName `
        -GalleryImageDefinitionName $ImageDefinitionName `
        -ErrorAction SilentlyContinue

    if ($versions) {
        $latest = $versions |
            ForEach-Object { [version]$_.Name } |
            Sort-Object -Descending |
            Select-Object -First 1

        switch ($Strategy) {
            'Major' {
                $newVersion = "$([int]$latest.Major + 1).0.0"
            }
            'Minor' {
                $newVersion = "$($latest.Major).$([int]$latest.Minor + 1).0"
            }
            'Patch' {
                $newVersion = "$($latest.Major).$($latest.Minor).$([int]$latest.Build + 1)"
            }
        }
    } else {
        $newVersion = "1.0.0"
    }

    return $newVersion
}

# ==========================
# Main Execution
# ==========================

# Handle special parameter sets
if ($GenerateConfig) {
    $outputPath = if ($ConfigFile) { $ConfigFile } else { ".\acg-config.json" }
    New-ConfigTemplate -Path $outputPath
    exit 0
}

Show-Banner

# ==========================
# Execution Time Tracking
# ==========================
$scriptStartTime = Get-Date
$stepTimes = @{}

# Placeholder for log file (created after authentication)
$logFile = $null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if ($logFile) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        Add-Content -Path $logFile -Value $logMessage
    }
}

Write-Host ""

# ==========================
# JSON File Auto-Discovery
# ==========================
# If no ConfigFile was specified, check for JSON files in the script directory
if ($PSCmdlet.ParameterSetName -ne 'ConfigFile' -and $PSCmdlet.ParameterSetName -ne 'Explicit') {
    $jsonFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*-config.json" -File -ErrorAction SilentlyContinue

    if ($jsonFiles) {
        Write-Header "Configuration Files Detected"
        Write-Info "Found $($jsonFiles.Count) JSON configuration file(s) in the script directory:"
        Write-Host ""

        $index = 1
        foreach ($file in $jsonFiles) {
            Write-Host "  [$index] " -NoNewline -ForegroundColor Cyan
            Write-Host $file.Name -ForegroundColor White
            $index++
        }

        Write-Host ""
        Write-Host "  [0] " -NoNewline -ForegroundColor Cyan
        Write-Host "Enter configuration manually (Interactive Mode)" -ForegroundColor Gray
        Write-Host ""

        $selection = Read-Host "Select a configuration file (0-$($jsonFiles.Count))"

        if ($selection -match '^\d+$' -and [int]$selection -gt 0 -and [int]$selection -le $jsonFiles.Count) {
            $selectedFile = $jsonFiles[[int]$selection - 1]
            $ConfigFile = $selectedFile.FullName
            Write-Success "Using configuration file: $($selectedFile.Name)"
            Write-Host ""
            # Override parameter set to use ConfigFile
            $PSCmdlet.ParameterSetName = 'ConfigFile'
        } elseif ($selection -eq '0') {
            Write-Info "Proceeding with interactive mode"
            Write-Host ""
        } else {
            Write-Warning2 "Invalid selection. Proceeding with interactive mode"
            Write-Host ""
        }
    }
}

# Load configuration based on parameter set
$config = @{}

if ($PSCmdlet.ParameterSetName -eq 'ConfigFile') {
    Write-Info "Loading configuration from file: $ConfigFile"
    $configData = Read-Configuration -Path $ConfigFile

    # Validate configuration schema
    Write-Info "Validating configuration..."
    $validationErrors = Test-ConfigurationSchema -Config $configData
    if ($validationErrors) {
        Write-ErrorMsg "Configuration validation failed:"
        foreach ($error in $validationErrors) {
            Write-Host "  • $error" -ForegroundColor Red
        }
        Write-Log "Configuration validation failed: $($validationErrors -join '; ')" "ERROR"
        exit 1
    }
    Write-Success "Configuration validated"
    Write-Log "Configuration validated successfully"

    $config.TenantId = $configData.TenantId
    $config.SubscriptionId = $configData.SubscriptionId
    $config.Location = $configData.Location
    $config.SourceVMName = $configData.SourceVM.Name
    $config.SourceVMResourceGroup = $configData.SourceVM.ResourceGroup
    $config.GalleryResourceGroup = $configData.Gallery.ResourceGroup
    $config.GalleryName = $configData.Gallery.Name
    $config.ImageDefinitionName = $configData.Gallery.ImageDefinitionName
    $config.VNetName = $configData.Network.VNetName
    $config.VNetResourceGroup = $configData.Network.VNetResourceGroup
    $config.SubnetName = $configData.Network.SubnetName
    $config.VMSize = $configData.TempVM.Size
    $VersioningStrategy = $configData.Options.VersioningStrategy
    $SkipAgentCheck = $configData.Options.SkipAgentCheck
    $SkipCleanup = $configData.Options.SkipCleanup

    # Show config preview before continuing
    Show-ConfigPreview -Config $config -Strategy $VersioningStrategy

} elseif ($PSCmdlet.ParameterSetName -eq 'Interactive' -or -not $TenantId) {
    $config = Get-InteractiveConfiguration

} else {
    # Explicit parameters
    $config.TenantId = $TenantId
    $config.SubscriptionId = $SubscriptionId
    $config.Location = $Location
    $config.SourceVMName = $SourceVMName
    $config.SourceVMResourceGroup = $SourceVMResourceGroup
    $config.GalleryResourceGroup = $GalleryResourceGroup
    $config.GalleryName = $GalleryName
    $config.ImageDefinitionName = $ImageDefinitionName
    $config.VNetName = $VNetName
    $config.VNetResourceGroup = $VNetResourceGroup
    $config.SubnetName = $SubnetName
    $config.VMSize = $VMSize
}

# Validate required fields
$requiredFields = @(
    'TenantId', 'SubscriptionId', 'Location', 'SourceVMName', 'SourceVMResourceGroup',
    'GalleryResourceGroup', 'GalleryName', 'ImageDefinitionName',
    'VNetName', 'VNetResourceGroup', 'SubnetName', 'VMSize'
)

$missing = $requiredFields | Where-Object { -not $config[$_] }
if ($missing) {
    Write-ErrorMsg "Missing required configuration fields: $($missing -join ', ')"
    exit 1
}

# Generate unique temporary resource group name
$tempRG = "acg-temp-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(Get-Random -Maximum 9999)"

# Summary and confirmation
Write-Header "Configuration Summary"
Write-Host "Azure Environment:" -ForegroundColor Cyan
Write-Host "  Subscription ID : " -NoNewline -ForegroundColor Gray
Write-Host $config.SubscriptionId -ForegroundColor White
Write-Host "  Location        : " -NoNewline -ForegroundColor Gray
Write-Host $config.Location -ForegroundColor White
Write-Host ""
Write-Host "Source VM:" -ForegroundColor Cyan
Write-Host "  Name            : " -NoNewline -ForegroundColor Gray
Write-Host $config.SourceVMName -ForegroundColor White
Write-Host "  Resource Group  : " -NoNewline -ForegroundColor Gray
Write-Host $config.SourceVMResourceGroup -ForegroundColor White
Write-Host ""
Write-Host "Target Gallery:" -ForegroundColor Cyan
Write-Host "  Gallery Name    : " -NoNewline -ForegroundColor Gray
Write-Host $config.GalleryName -ForegroundColor White
Write-Host "  Image Definition: " -NoNewline -ForegroundColor Gray
Write-Host $config.ImageDefinitionName -ForegroundColor White
Write-Host "  Resource Group  : " -NoNewline -ForegroundColor Gray
Write-Host $config.GalleryResourceGroup -ForegroundColor White
Write-Host ""
Write-Host "Network:" -ForegroundColor Cyan
Write-Host "  VNet            : " -NoNewline -ForegroundColor Gray
Write-Host "$($config.VNetName) ($($config.VNetResourceGroup))" -ForegroundColor White
Write-Host "  Subnet          : " -NoNewline -ForegroundColor Gray
Write-Host $config.SubnetName -ForegroundColor White
Write-Host ""
Write-Host "Options:" -ForegroundColor Cyan
Write-Host "  VM Size         : " -NoNewline -ForegroundColor Gray
Write-Host $config.VMSize -ForegroundColor White
Write-Host "  Versioning      : " -NoNewline -ForegroundColor Gray
Write-Host $VersioningStrategy -ForegroundColor White
Write-Host "  Temp RG         : " -NoNewline -ForegroundColor Gray
Write-Host $tempRG -ForegroundColor White
Write-Host ""

if (-not $Force) {
    $confirmation = Read-Host "Proceed with image creation? (Y/N)"
    if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
        Write-Warning2 "Operation cancelled by user"
        exit 0
    }
}

Write-Host ""
$totalSteps = 12
$currentStep = 0

# ==========================
# Step 1: Azure Authentication
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Authenticating to Azure"
Write-Log "Step $currentStep : Authenticating to Azure"
if (-not (Connect-AzureEnvironment -TenantId $config.TenantId -SubscriptionId $config.SubscriptionId)) {
    Write-Log "Authentication failed" "ERROR"
    exit 1
}
$stepTimes["Authentication"] = ((Get-Date) - $stepStart).TotalSeconds
Write-Log "Authentication completed in $($stepTimes["Authentication"]) seconds"

# ==========================
# Initialize Logging (After Authentication)
# ==========================
$logFile = Join-Path $PSScriptRoot "image-build-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Write-Log "Script started"
Write-Info "Execution log: $logFile"

# ==========================
# Pre-Flight Validation Checks
# ==========================
if (-not $SkipPreFlightChecks) {
    Write-Host ""
    Write-Log "Starting pre-flight validation checks"
    if (-not (Test-PreFlightChecks -Config $config)) {
        Write-Log "Pre-flight checks failed" "ERROR"
        if (-not $Force) {
            $continue = Read-Host "Pre-flight checks failed. Continue anyway? (Y/N)"
            if ($continue -ne 'Y' -and $continue -ne 'y') {
                Write-Warning2 "Operation cancelled"
                Write-Log "Operation cancelled by user after pre-flight failure"
                exit 1
            }
            Write-Log "User chose to continue despite pre-flight failures"
        }
    }
    Write-Log "Pre-flight checks completed"
} else {
    Write-Log "Pre-flight checks skipped by user"
}

# WhatIf Mode - Exit after validation
if ($WhatIf) {
    Write-Host ""
    Write-Header "Dry-Run Mode (WhatIf)"
    Write-Success "All validations passed!"
    Write-Info "The following resources would be created:"
    Write-Host "  • Temporary RG: " -NoNewline -ForegroundColor Gray
    Write-Host $tempRG -ForegroundColor Yellow
    Write-Host "  • Snapshot: " -NoNewline -ForegroundColor Gray
    Write-Host "$($config.SourceVMName)-snapshot-*" -ForegroundColor Yellow
    Write-Host "  • Managed Disk: " -NoNewline -ForegroundColor Gray
    Write-Host "$($config.SourceVMName)-disk-*" -ForegroundColor Yellow
    Write-Host "  • Clone VM: " -NoNewline -ForegroundColor Gray
    Write-Host "$($config.SourceVMName)-clone-*" -ForegroundColor Yellow
    Write-Host "  • Gallery Image Version: " -NoNewline -ForegroundColor Gray
    $nextVersionPreview = Get-NextImageVersion -ResourceGroupName $config.GalleryResourceGroup -GalleryName $config.GalleryName -ImageDefinitionName $config.ImageDefinitionName -Strategy $VersioningStrategy
    Write-Host $nextVersionPreview -ForegroundColor Green
    Write-Host ""
    Write-Success "Dry-run completed successfully. No resources were created."
    Write-Log "Dry-run completed successfully"
    exit 0
}

# ==========================
# Step 2: Validate Source VM
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Validating source VM"
Write-Log "Step $currentStep : Validating source VM"
$sourceVM = Get-AzVM -ResourceGroupName $config.SourceVMResourceGroup -Name $config.SourceVMName -ErrorAction SilentlyContinue
if (-not $sourceVM) {
    Write-ErrorMsg "Source VM '$($config.SourceVMName)' not found in resource group '$($config.SourceVMResourceGroup)'"
    exit 1
}
Write-Success "Source VM found: $($config.SourceVMName)"

# Check VM power state
$vmStatus = Get-AzVM -ResourceGroupName $config.SourceVMResourceGroup -Name $config.SourceVMName -Status
$powerState = ($vmStatus.Statuses | Where-Object Code -like 'PowerState/*').DisplayStatus
Write-Info "Source VM power state: $powerState"

# Optional agent check (only if VM is running)
if (-not $SkipAgentCheck -and $powerState -eq 'VM running') {
    Write-Info "Checking guest agent status on source VM..."
    $agentStatus = Get-GuestAgentStatus -ResourceGroupName $config.SourceVMResourceGroup -Name $config.SourceVMName
    if ($agentStatus -eq 'Ready') {
        Write-Success "Guest agent is ready on source VM"
    } else {
        Write-Warning2 "Guest agent status: $agentStatus (continuing anyway)"
    }
}
$stepTimes["Validate Source VM"] = ((Get-Date) - $stepStart).TotalSeconds
Write-Log "Step $currentStep completed in $($stepTimes["Validate Source VM"]) seconds"

# ==========================
# Step 3: Validate Gallery
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Validating Azure Compute Gallery"
Write-Log "Step $currentStep : Validating Azure Compute Gallery"

$gallery = Get-AzGallery -ResourceGroupName $config.GalleryResourceGroup -Name $config.GalleryName -ErrorAction SilentlyContinue
if (-not $gallery) {
    Write-ErrorMsg "Gallery '$($config.GalleryName)' not found in resource group '$($config.GalleryResourceGroup)'"
    exit 1
}
Write-Success "Gallery found: $($config.GalleryName)"

$imageDef = Get-AzGalleryImageDefinition `
    -ResourceGroupName $config.GalleryResourceGroup `
    -GalleryName $config.GalleryName `
    -Name $config.ImageDefinitionName `
    -ErrorAction SilentlyContinue

if (-not $imageDef) {
    Write-ErrorMsg "Image definition '$($config.ImageDefinitionName)' not found in gallery '$($config.GalleryName)'"
    exit 1
}
Write-Success "Image definition found: $($config.ImageDefinitionName)"
$stepTimes["Validate Gallery"] = ((Get-Date) - $stepStart).TotalSeconds
Write-Log "Step $currentStep completed in $($stepTimes["Validate Gallery"]) seconds"

# ==========================
# Step 4: Calculate Next Version
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Calculating next image version"
Write-Log "Step $currentStep : Calculating next image version"

$nextVersion = Get-NextImageVersion `
    -ResourceGroupName $config.GalleryResourceGroup `
    -GalleryName $config.GalleryName `
    -ImageDefinitionName $config.ImageDefinitionName `
    -Strategy $VersioningStrategy

Write-Success "Next image version: $nextVersion (strategy: $VersioningStrategy)"
$stepTimes["Calculate Version"] = ((Get-Date) - $stepStart).TotalSeconds
Write-Log "Step $currentStep completed in $($stepTimes["Calculate Version"]) seconds"

# ==========================
# Step 5: Validate Network
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Validating network configuration"
Write-Log "Step $currentStep : Validating network configuration"

$vnet = Get-AzVirtualNetwork -Name $config.VNetName -ResourceGroupName $config.VNetResourceGroup -ErrorAction SilentlyContinue
if (-not $vnet) {
    Write-ErrorMsg "VNet '$($config.VNetName)' not found in resource group '$($config.VNetResourceGroup)'"
    exit 1
}

$subnet = Get-AzVirtualNetworkSubnetConfig -Name $config.SubnetName -VirtualNetwork $vnet -ErrorAction SilentlyContinue
if (-not $subnet) {
    Write-ErrorMsg "Subnet '$($config.SubnetName)' not found in VNet '$($config.VNetName)'"
    exit 1
}
Write-Success "Network validated: $($config.VNetName)/$($config.SubnetName)"
$stepTimes["Validate Network"] = ((Get-Date) - $stepStart).TotalSeconds
Write-Log "Step $currentStep completed in $($stepTimes["Validate Network"]) seconds"

# ==========================
# Step 6: Create Temporary Resource Group
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Creating temporary resource group"
Write-Log "Step $currentStep : Creating temporary resource group"

$tempRGObj = New-AzResourceGroup -Name $tempRG -Location $config.Location -Force
Write-Success "Temporary resource group created: $tempRG"
$stepTimes["Create Temp RG"] = ((Get-Date) - $stepStart).TotalSeconds
Write-Log "Step $currentStep completed in $($stepTimes["Create Temp RG"]) seconds"

# Define temporary resource names
$snapshotName = "$($config.SourceVMName)-snapshot-v$($nextVersion.Replace('.', '-'))"
$diskName = "$($config.SourceVMName)-disk-v$($nextVersion.Replace('.', '-'))"
$cloneVMName = "$($config.SourceVMName)-clone-v$($nextVersion.Replace('.', '-'))"
$managedImageName = "$($config.SourceVMName)-image-v$($nextVersion.Replace('.', '-'))"

# ==========================
# Step 7: Create Snapshot
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Creating snapshot from source OS disk"
Write-Log "Step $currentStep : Creating snapshot from source OS disk"

$sourceOSDisk = $sourceVM.StorageProfile.OsDisk.Name
$sourceDisk = Get-AzDisk -ResourceGroupName $config.SourceVMResourceGroup -DiskName $sourceOSDisk

Write-Info "Source OS disk: $sourceOSDisk"
$snapshotConfig = New-AzSnapshotConfig -SourceUri $sourceDisk.Id -CreateOption Copy -Location $config.Location
$snapshot = New-AzSnapshot -Snapshot $snapshotConfig -SnapshotName $snapshotName -ResourceGroupName $tempRG
Write-Success "Snapshot created: $snapshotName"
$stepTimes["Create Snapshot"] = ((Get-Date) - $stepStart).TotalSeconds
Write-Log "Step $currentStep completed in $($stepTimes["Create Snapshot"]) seconds"

# ==========================
# Step 8: Create Managed Disk
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Creating managed disk from snapshot"
Write-Log "Step $currentStep : Creating managed disk from snapshot"

$diskConfig = New-AzDiskConfig -Location $snapshot.Location -SourceResourceId $snapshot.Id -CreateOption Copy
$disk = New-AzDisk -Disk $diskConfig -ResourceGroupName $tempRG -DiskName $diskName
Write-Success "Managed disk created: $diskName"
$stepTimes["Create Disk"] = ((Get-Date) - $stepStart).TotalSeconds
Write-Log "Step $currentStep completed in $($stepTimes["Create Disk"]) seconds"

# ==========================
# Step 9: Create Clone VM
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Creating clone VM"
Write-Log "Step $currentStep : Creating clone VM"

Write-Info "Initializing VM configuration..."
$vmConfig = New-AzVMConfig -VMName $cloneVMName -VMSize $config.VMSize | Set-AzVMBootDiagnostic -Disable
$vmConfig = Set-AzVMOSDisk -VM $vmConfig -ManagedDiskId $disk.Id -CreateOption Attach -Windows

Write-Info "Creating network interface..."
$nicName = "$($cloneVMName.ToLower())-nic"
$nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $tempRG -Location $config.Location -SubnetId $subnet.Id
$vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id

Write-Info "Provisioning VM (this may take several minutes)..."
New-AzVM -VM $vmConfig -ResourceGroupName $tempRG -Location $config.Location -DisableBginfoExtension | Out-Null
Write-Success "Clone VM created: $cloneVMName"
$stepTimes["Create Clone VM"] = ((Get-Date) - $stepStart).TotalSeconds
Write-Log "Step $currentStep completed in $($stepTimes["Create Clone VM"]) seconds"

# ==========================
# Step 10: Wait for VM Agent & Run Sysprep
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Waiting for VM agent and running Sysprep"
Write-Log "Step $currentStep : Waiting for VM agent and running Sysprep"

Write-Info "Waiting for VM agent to be ready..."
if (-not (Wait-ForVMAgent -ResourceGroupName $tempRG -Name $cloneVMName -TimeoutMinutes 15)) {
    Write-ErrorMsg "VM agent did not become ready. Check network connectivity and firewall rules."
    if (-not $SkipCleanup) {
        Write-Info "Cleaning up temporary resources..."
        Remove-AzResourceGroup -Name $tempRG -Force | Out-Null
    }
    exit 1
}

Write-Info "Running Sysprep on clone VM..."
$sysprepScript = @'
Start-Process -FilePath "C:\Windows\System32\Sysprep\Sysprep.exe" -ArgumentList "/generalize /oobe /mode:vm /quit" -Wait
'@

try {
    Invoke-AzVMRunCommand -ResourceGroupName $tempRG -Name $cloneVMName -CommandId 'RunPowerShellScript' -ScriptString $sysprepScript -ErrorAction Stop | Out-Null
    Write-Success "Sysprep completed successfully"
} catch {
    Write-ErrorMsg "Sysprep failed: $($_.Exception.Message)"
    if (-not $SkipCleanup) {
        Write-Info "Cleaning up temporary resources..."
        Remove-AzResourceGroup -Name $tempRG -Force | Out-Null
    }
    exit 1
}

Write-Info "Stopping clone VM..."
Stop-AzVM -Name $cloneVMName -ResourceGroupName $tempRG -Force | Out-Null

Write-Info "Marking VM as generalized..."
Set-AzVM -ResourceGroupName $tempRG -Name $cloneVMName -Generalized | Out-Null
Write-Success "VM generalized successfully"
$stepTimes["Sysprep & Generalize"] = ((Get-Date) - $stepStart).TotalSeconds
Write-Log "Step $currentStep completed in $($stepTimes["Sysprep & Generalize"]) seconds"

# ==========================
# Step 11: Create Managed Image
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Creating managed image"
Write-Log "Step $currentStep : Creating managed image"

$vmForGen = Get-AzVM -Name $cloneVMName -ResourceGroupName $tempRG
$imageConfig = New-AzImageConfig -Location $config.Location -HyperVGeneration $vmForGen.StorageProfile.OsDisk.HyperVGeneration
$imageConfig = Set-AzImageOsDisk -Image $imageConfig -OsState Generalized -OsType Windows -ManagedDiskId $disk.Id
$managedImage = New-AzImage -ImageName $managedImageName -ResourceGroupName $tempRG -Image $imageConfig
Write-Success "Managed image created: $managedImageName"
$stepTimes["Create Managed Image"] = ((Get-Date) - $stepStart).TotalSeconds
Write-Log "Step $currentStep completed in $($stepTimes["Create Managed Image"]) seconds"

# ==========================
# Step 12: Publish to Gallery
# ==========================
$currentStep++
$stepStart = Get-Date
Write-Step -Step $currentStep -TotalSteps $totalSteps -Message "Publishing to Azure Compute Gallery"
Write-Log "Step $currentStep : Publishing to Azure Compute Gallery"

Write-Info "Creating gallery image version: $nextVersion"
Write-Info "This operation may take 10-20 minutes depending on image size..."

try {
    New-AzGalleryImageVersion `
        -ResourceGroupName $config.GalleryResourceGroup `
        -GalleryName $config.GalleryName `
        -GalleryImageDefinitionName $config.ImageDefinitionName `
        -Name $nextVersion `
        -Location $config.Location `
        -SourceImageId $managedImage.Id `
        -ErrorAction Stop | Out-Null

    Write-Success "Gallery image version created: $nextVersion"
    $stepTimes["Publish to Gallery"] = ((Get-Date) - $stepStart).TotalSeconds
    Write-Log "Step $currentStep completed in $($stepTimes["Publish to Gallery"]) seconds"
} catch {
    Write-ErrorMsg "Failed to create gallery image version: $($_.Exception.Message)"
    if (-not $SkipCleanup) {
        Write-Info "Cleaning up temporary resources..."
        Remove-AzResourceGroup -Name $tempRG -Force | Out-Null
    }
    exit 1
}

# ==========================
# Cleanup
# ==========================
if (-not $SkipCleanup) {
    Write-Host ""
    Write-Header "Cleanup"
    Write-Info "Removing temporary resource group: $tempRG"
    Remove-AzResourceGroup -Name $tempRG -Force | Out-Null
    Write-Success "Temporary resources cleaned up"
} else {
    Write-Warning2 "Temporary resources kept for debugging: $tempRG"
}

# ==========================
# Final Summary
# ==========================
$scriptEndTime = Get-Date
$totalDuration = ($scriptEndTime - $scriptStartTime).TotalMinutes

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                                                                           ║" -ForegroundColor Green
Write-Host "║                     ✓ IMAGE CREATION SUCCESSFUL ✓                         ║" -ForegroundColor Green
Write-Host "║                                                                           ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "Execution Summary:" -ForegroundColor Cyan
Write-Host "  Total Duration       : " -NoNewline -ForegroundColor Gray
Write-Host "$([math]::Round($totalDuration, 2)) minutes" -ForegroundColor White
Write-Host "  Start Time           : " -NoNewline -ForegroundColor Gray
Write-Host $scriptStartTime.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor White
Write-Host "  End Time             : " -NoNewline -ForegroundColor Gray
Write-Host $scriptEndTime.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor White
Write-Host "  Log File             : " -NoNewline -ForegroundColor Gray
Write-Host $logFile -ForegroundColor White
Write-Host ""

Write-Host "Gallery Image Details:" -ForegroundColor Cyan
Write-Host "  Gallery              : " -NoNewline -ForegroundColor Gray
Write-Host $config.GalleryName -ForegroundColor White
Write-Host "  Image Definition     : " -NoNewline -ForegroundColor Gray
Write-Host $config.ImageDefinitionName -ForegroundColor White
Write-Host "  Version              : " -NoNewline -ForegroundColor Gray
Write-Host $nextVersion -ForegroundColor Green
Write-Host "  Resource Group       : " -NoNewline -ForegroundColor Gray
Write-Host $config.GalleryResourceGroup -ForegroundColor White
Write-Host ""

if ($stepTimes.Count -gt 0) {
    Write-Host "Step Timings:" -ForegroundColor Cyan
    foreach ($step in $stepTimes.Keys | Sort-Object) {
        Write-Host "  $step : " -NoNewline -ForegroundColor Gray
        Write-Host "$([math]::Round($stepTimes[$step], 1))s" -ForegroundColor White
    }
    Write-Host ""
}

Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  • Use this image to create AVD session hosts" -ForegroundColor Gray
Write-Host "  • Deploy VMs from the gallery image" -ForegroundColor Gray
Write-Host "  • Configure your host pools to use version: $nextVersion" -ForegroundColor Gray
Write-Host ""
Write-Success "Script completed successfully!"

Write-Log "Script completed successfully in $([math]::Round($totalDuration, 2)) minutes"
Write-Log "Image version $nextVersion created in gallery $($config.GalleryName)"

