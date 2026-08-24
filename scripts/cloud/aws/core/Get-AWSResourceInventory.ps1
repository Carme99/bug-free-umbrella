<#
.SYNOPSIS
    Inventories AWS resources across EC2, S3, RDS, and Lambda.
.DESCRIPTION
    Loads the AWS PowerShell module, connects to the target region (optionally using a
    named credential profile), and inventories EC2 instances, S3 buckets, RDS DB instances,
    and Lambda functions. Prints per-service counts plus a final summary to the console.
    The script is read-only and idempotent: re-running it never mutates AWS resources.
.PARAMETER Region
    AWS region to query. Defaults to us-east-1.
.PARAMETER ProfileName
    Optional named AWS credential profile used to authenticate.
.PARAMETER ExportHTML
    Reserved switch for future HTML report export; currently has no effect.
.EXAMPLE
    PS C:\> .\Get-AWSResourceInventory.ps1 -Region us-east-1
    Inventories resources in the us-east-1 region using default credentials.
.EXAMPLE
    PS C:\> .\Get-AWSResourceInventory.ps1 -Region eu-west-1 -ProfileName prod -ExportHTML
    Inventories the eu-west-1 region using the 'prod' credential profile.
.NOTES
    File Name   : Get-AWSResourceInventory.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>
[CmdletBinding()]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string]$Region = 'us-east-1',
    [Parameter()][string]$ProfileName,
    [switch]$ExportHTML
)
$ErrorActionPreference = 'Stop'
# Analyzer warnings accepted: PSAvoidUsingWriteHost (spec section 3 mandates Write-Host prefix output)

# and PSReviewUnusedParameter (script params are consumed by Main via parent scope).
function Main {
    try {
        Write-Host "[*] Loading AWS PowerShell module..." -ForegroundColor Cyan
        Import-Module AWSPowerShell.NetCore -ErrorAction Stop
        if ($ProfileName) {
            Set-AWSCredential -ProfileName $ProfileName -ErrorAction Stop
        }
        Set-DefaultAWSRegion -Region $Region -ErrorAction Stop
        Write-Host "[+] Connected to AWS region: $Region" -ForegroundColor Green

        Write-Host "[*] Checking EC2 instances..." -ForegroundColor Cyan
        $ec2 = Get-EC2Instance -ErrorAction Stop
        $instances = @($ec2.Instances)
        $runningInstances = @($instances | Where-Object { $_.State.Name -eq 'running' }).Count
        Write-Host "[+] Found $($instances.Count) EC2 instances ($runningInstances running)" -ForegroundColor Green

        Write-Host "[*] Checking S3 buckets..." -ForegroundColor Cyan
        $buckets = @(Get-S3Bucket -ErrorAction Stop)
        Write-Host "[+] Found $($buckets.Count) S3 buckets" -ForegroundColor Green

        Write-Host "[*] Checking RDS instances..." -ForegroundColor Cyan
        $rds = @(Get-RDSDBInstance -ErrorAction Stop)
        Write-Host "[+] Found $($rds.Count) RDS instances" -ForegroundColor Green

        Write-Host "[*] Checking Lambda functions..." -ForegroundColor Cyan
        $lambda = @(Get-LMFunctionList -ErrorAction Stop)
        Write-Host "[+] Found $($lambda.Count) Lambda functions" -ForegroundColor Green

        Write-Host ""
        Write-Host "=== Summary ===" -ForegroundColor Cyan
        Write-Host "Region: $Region" -ForegroundColor White
        Write-Host "EC2 Instances: $($instances.Count) ($runningInstances running)" -ForegroundColor White
        Write-Host "S3 Buckets: $($buckets.Count)" -ForegroundColor White
        Write-Host "RDS Instances: $($rds.Count)" -ForegroundColor White
        Write-Host "Lambda Functions: $($lambda.Count)" -ForegroundColor White
        Write-Host "[+] Inventory complete" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[!] AWS PowerShell module missing" -ForegroundColor Yellow
        Write-Host "[*] Install with: Install-Module AWSPowerShell.NetCore" -ForegroundColor Cyan
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
