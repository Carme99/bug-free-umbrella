<#
.SYNOPSIS
    Audits a Windows failover cluster for node, quorum, resource and CSV health.

.DESCRIPTION
    Read-only health audit of a Windows failover cluster. The script reads the cluster nodes and
    their states, the quorum configuration and its witness, every cluster resource and every
    Cluster Shared Volume, then prints a per-check summary. Nodes, resources and Cluster Shared
    Volumes are reported whether or not they are findings, so a resource that is deliberately
    offline is visible without being treated as a failure.

    Checks that are not a clean pass are reported as findings (exit code 2):
    - a node whose state is not Up;
    - a NodeMajority quorum on an even node count, where no witness vote can break a tie;
    - a cluster resource in the Failed state, and a Cluster Shared Volume in the Failed state;
    - with -IncludeClusterValidation, a Test-Cluster validation result whose status starts with
      Fail or Error, or a runner that returns no nodes or no cluster at all.

    Cmdlet reference: https://learn.microsoft.com/powershell/module/failoverclusters/

    Side effects: the script is read-only with one exception. With -IncludeClusterValidation it
    calls Test-Cluster -Include Inventory -Force, which writes a cluster validation report as
    Test-Cluster normally does; it never starts, stops or moves a cluster resource.

    Exit codes: 0 = healthy (every check passed); 2 = findings present; 1 = error, meaning the
    FailoverClusters module is unavailable, -OutputPath is unsafe, or a required query failed.

.PARAMETER ClusterName
    Failover cluster to audit. Defaults to $env:COMPUTERNAME, which audits the local cluster.
    Run the script on a cluster node with Failover Cluster administrative rights.

.PARAMETER IncludeClusterValidation
    Switch. When set, the script additionally runs Test-Cluster with the Inventory test category
    and flags validation results whose status starts with Fail or Error. Validation is opt-in
    because it takes time and writes a validation report.

.PARAMETER OutputFormat
    Report format: 'Table' (console detail, the default), 'Json', or 'Csv'.

.PARAMETER OutputPath
    Optional directory for the Json or Csv report. Must be a local absolute path without '..'
    traversal and must not be a UNC path. When omitted, Json output is written to the console
    and Csv output is skipped with a warning.

.EXAMPLE
    PS C:\> .\Test-FailoverClusterHealth.ps1
    Audits the local failover cluster and prints the table report.

.EXAMPLE
    PS C:\> .\Test-FailoverClusterHealth.ps1 -ClusterName cluster1 -IncludeClusterValidation `
        -OutputFormat Json -OutputPath 'C:\Reports'
    Audits a named cluster including the Test-Cluster inventory validation, and writes a JSON
    report into C:\Reports.

.NOTES
    File Name   : Test-FailoverClusterHealth.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Cmdlet reference pages:
    https://learn.microsoft.com/powershell/module/failoverclusters/get-clusternode
    https://learn.microsoft.com/powershell/module/failoverclusters/get-clusterquorum
    https://learn.microsoft.com/powershell/module/failoverclusters/get-clusterresource
    https://learn.microsoft.com/powershell/module/failoverclusters/get-clustersharedvolume
    https://learn.microsoft.com/powershell/module/failoverclusters/test-cluster
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ClusterName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeClusterValidation,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function New-CheckRow {
    param(
        [Parameter()][string]$Category,
        [Parameter()][string]$Item,
        [Parameter()][string]$Status,
        [Parameter()][string]$Finding,
        [Parameter()][string]$Details
    )

    return [pscustomobject]@{
        Category = $Category
        Item     = $Item
        Status   = $Status
        Finding  = $Finding
        Details  = $Details
    }
}

function Get-QuorumWitnessName {
    param([Parameter()][object]$Quorum)

    if ($null -eq $Quorum) { return '<unknown>' }
    $resource = $Quorum.QuorumResource
    if ($null -eq $resource) { return '<none>' }
    if ($resource -is [string]) {
        if ([string]::IsNullOrWhiteSpace($resource)) { return '<none>' }
        return $resource
    }
    if ($resource.PSObject.Properties['Name']) { return [string]$resource.Name }
    return [string]$resource
}

function Get-ValidationStatus {
    param([Parameter()][object]$Result)

    # Test-Cluster returns ClusterTestInfo objects; the status property name varies between
    # builds, so probe the names the report is known to expose.
    foreach ($propertyName in @('Status', 'Result', 'TestResult', 'Outcome')) {
        $property = $Result.PSObject.Properties[$propertyName]
        if ($null -ne $property -and $null -ne $property.Value) { return [string]$property.Value }
    }
    return 'Unknown'
}

function Main {
    try {
        if (-not (Get-Command Get-ClusterNode -ErrorAction SilentlyContinue)) {
            throw "The FailoverClusters module is not available. Add the Failover Clustering Tools."
        }
        Import-Module FailoverClusters -ErrorAction Stop

        Write-Host "[*] Auditing failover cluster '$ClusterName'" -ForegroundColor Cyan
        Write-Host "[*] Cmdlet reference: https://learn.microsoft.com/powershell/module/failoverclusters/" `
            -ForegroundColor Cyan

        if ($OutputPath) {
            if ($OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or $OutputPath -match '^(\\\\|//)') {
                Write-Host "[-] Unsafe OutputPath: $OutputPath." -ForegroundColor Red
                Write-Host "[-] Use a local absolute path without '..' traversal." -ForegroundColor Red
                return 1
            }
            if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
                New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop | Out-Null
            }
        }

        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $rows = @()

        Write-Host "[*] Reading cluster nodes..." -ForegroundColor Cyan
        $nodes = @(Get-ClusterNode -Cluster $ClusterName -ErrorAction Stop)
        Write-Host "[+] Found $($nodes.Count) node(s)" -ForegroundColor Green
        if ($nodes.Count -eq 0) {
            Write-Host "[!] The cluster returned no nodes" -ForegroundColor Yellow
            $rows += New-CheckRow -Category 'Node' -Item $ClusterName -Status 'Fail' `
                -Finding 'No cluster nodes returned' `
                -Details 'Verify the cluster name and Failover Cluster permissions'
        }

        $upNodeCount = 0
        foreach ($node in $nodes) {
            $nodeName = [string]$node.Name
            $nodeState = [string]$node.State
            if ($nodeState -eq 'Up') {
                $upNodeCount++
                Write-Host "[+] Node '$nodeName' is Up" -ForegroundColor Green
                $rows += New-CheckRow -Category 'Node' -Item $nodeName -Status 'Pass' `
                    -Finding 'Node is Up' -Details "Weight: $($node.NodeWeight)"
            }
            else {
                Write-Host "[!] Node '$nodeName' is $nodeState" -ForegroundColor Yellow
                $rows += New-CheckRow -Category 'Node' -Item $nodeName -Status 'Fail' `
                    -Finding "Node state $nodeState" -Details "Weight: $($node.NodeWeight)"
            }
        }

        Write-Host "[*] Reading quorum configuration..." -ForegroundColor Cyan
        $quorum = Get-ClusterQuorum -Cluster $ClusterName -ErrorAction Stop
        $quorumType = [string]$quorum.QuorumType
        $witnessName = Get-QuorumWitnessName -Quorum $quorum
        $evenNodeCount = (($nodes.Count % 2) -eq 0)
        if ($quorumType -eq 'NodeMajority' -and $evenNodeCount -and $nodes.Count -gt 0) {
            Write-Host "[!] Quorum is NodeMajority with an even node count ($($nodes.Count))" `
                -ForegroundColor Yellow
            $rows += New-CheckRow -Category 'Quorum' -Item $ClusterName -Status 'Fail' `
                -Finding 'NodeMajority quorum on an even node count' `
                -Details "Nodes: $($nodes.Count); no witness vote is available to break a tie"
        }
        else {
            Write-Host "[+] Quorum is $quorumType across $($nodes.Count) node(s)" -ForegroundColor Green
            $rows += New-CheckRow -Category 'Quorum' -Item $ClusterName -Status 'Pass' `
                -Finding "Quorum type $quorumType" -Details "Nodes: $($nodes.Count)"
        }

        Write-Host "[*] Quorum witness: $witnessName" -ForegroundColor Cyan
        $rows += New-CheckRow -Category 'Witness' -Item $ClusterName -Status 'Pass' `
            -Finding "Quorum witness: $witnessName" -Details "Quorum type: $quorumType"

        Write-Host "[*] Reading cluster resources..." -ForegroundColor Cyan
        $resources = @(Get-ClusterResource -Cluster $ClusterName -ErrorAction Stop)
        $failedResourceCount = 0
        foreach ($resource in $resources) {
            $resourceName = [string]$resource.Name
            $resourceState = [string]$resource.State
            $resourceDetails = "Type: $($resource.ResourceType); Owner: $($resource.OwnerNode)"
            if ($resourceState -eq 'Failed') {
                $failedResourceCount++
                Write-Host "[!] Resource '$resourceName' is Failed" -ForegroundColor Yellow
                $rows += New-CheckRow -Category 'Resource' -Item $resourceName -Status 'Fail' `
                    -Finding 'Resource is Failed' -Details $resourceDetails
            }
            else {
                $rows += New-CheckRow -Category 'Resource' -Item $resourceName -Status 'Pass' `
                    -Finding "Resource state $resourceState" -Details $resourceDetails
            }
        }
        Write-Host "[+] Resources: $($resources.Count) ($failedResourceCount failed)" `
            -ForegroundColor Green

        Write-Host "[*] Reading Cluster Shared Volumes..." -ForegroundColor Cyan
        $sharedVolumes = @(Get-ClusterSharedVolume -Cluster $ClusterName -ErrorAction Stop)
        foreach ($volume in $sharedVolumes) {
            $volumeName = [string]$volume.Name
            $volumeState = [string]$volume.State
            $volumeDetails = "Owner: $($volume.OwnerNode)"
            if ($volumeState -eq 'Failed') {
                Write-Host "[!] Cluster Shared Volume '$volumeName' is Failed" -ForegroundColor Yellow
                $rows += New-CheckRow -Category 'CSV' -Item $volumeName -Status 'Fail' `
                    -Finding 'Cluster Shared Volume is Failed' -Details $volumeDetails
            }
            else {
                Write-Host "[*] Cluster Shared Volume '$volumeName' is $volumeState" `
                    -ForegroundColor Cyan
                $rows += New-CheckRow -Category 'CSV' -Item $volumeName -Status 'Pass' `
                    -Finding "Cluster Shared Volume state $volumeState" -Details $volumeDetails
            }
        }
        Write-Host "[+] Cluster Shared Volumes: $($sharedVolumes.Count)" -ForegroundColor Green

        if ($IncludeClusterValidation) {
            Write-Host "[*] Running cluster validation (Inventory category)..." -ForegroundColor Cyan
            $validation = @(Test-Cluster -Cluster $ClusterName -Include 'Inventory' -Force `
                -ErrorAction Stop)
            Write-Host "[+] Validation returned $($validation.Count) result object(s)" `
                -ForegroundColor Green
            foreach ($result in $validation) {
                $validationStatus = Get-ValidationStatus -Result $result
                $testName = 'validation test'
                if ($result.PSObject.Properties['Name']) { $testName = [string]$result.Name }
                if ($validationStatus -match '^(Fail|Failed|Error)') {
                    Write-Host "[!] Validation '$testName' reported $validationStatus" `
                        -ForegroundColor Yellow
                    $rows += New-CheckRow -Category 'Validation' -Item $testName -Status 'Fail' `
                        -Finding "Validation reported $validationStatus" `
                        -Details 'Re-run Test-Cluster and read the validation report'
                }
                else {
                    $rows += New-CheckRow -Category 'Validation' -Item $testName -Status 'Pass' `
                        -Finding "Validation reported $validationStatus" `
                        -Details 'Test-Cluster inventory result'
                }
            }
        }

        $findings = @($rows | Where-Object { $_.Status -ne 'Pass' }).Count
        Write-Host ""
        Write-Host "=== Failover Cluster Health Summary ===" -ForegroundColor Cyan
        Write-Host "Cluster : $ClusterName" -ForegroundColor White
        Write-Host "Nodes   : $($nodes.Count) ($upNodeCount up)" -ForegroundColor White
        Write-Host "Checks  : $($rows.Count)" -ForegroundColor White
        $findingsColor = if ($findings -eq 0) { 'Green' } else { 'Red' }
        Write-Host "Findings: $findings" -ForegroundColor $findingsColor

        switch ($OutputFormat) {
            'Table' {
                $rows | Format-Table -AutoSize -Property Category, Item, Status, Finding, Details |
                    Out-String -Width 200 | Write-Host
            }
            'Json' {
                $report = [pscustomobject]@{
                    GeneratedAt       = (Get-Date).ToString('s')
                    ClusterName       = $ClusterName
                    Nodes             = @($nodes | ForEach-Object { [string]$_.Name })
                    NodesUp           = $upNodeCount
                    QuorumType        = $quorumType
                    Witness           = $witnessName
                    Resources         = @($resources | ForEach-Object { [string]$_.Name })
                    SharedVolumes     = @($sharedVolumes | ForEach-Object { [string]$_.Name })
                    ValidationRan     = [bool]$IncludeClusterValidation
                    Findings          = $findings
                    Checks            = @($rows)
                }
                $json = ConvertTo-Json -InputObject $report -Depth 5
                if ($OutputPath) {
                    $jsonFile = Join-Path $OutputPath "FailoverClusterHealth_$stamp.json"
                    Set-Content -LiteralPath $jsonFile -Value $json -Encoding utf8 -ErrorAction Stop
                    Write-Host "[+] JSON report written: $jsonFile" -ForegroundColor Green
                }
                else {
                    Write-Host $json
                }
            }
            'Csv' {
                if ($OutputPath) {
                    $csvFile = Join-Path $OutputPath "FailoverClusterHealth_$stamp.csv"
                    $rows | Export-Csv -LiteralPath $csvFile -NoTypeInformation -Encoding utf8 `
                        -ErrorAction Stop
                    Write-Host "[+] CSV report written: $csvFile" -ForegroundColor Green
                }
                else {
                    Write-Host "[!] -OutputPath is required for CSV output." -ForegroundColor Yellow
                }
            }
        }

        if ($findings -gt 0) {
            Write-Host "[!] $findings finding(s) detected on cluster '$ClusterName'." `
                -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] Failover cluster '$ClusterName' passed every check." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
