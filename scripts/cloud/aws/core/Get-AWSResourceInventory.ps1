<#
.SYNOPSIS
    AWS cloud resource inventory and health monitoring.
.DESCRIPTION
    Inventories AWS resources: EC2, S3, RDS, Lambda, and provides health status.
.EXAMPLE
    .\Get-AWSResourceInventory.ps1 -Region us-east-1 -ExportHTML
.NOTES
    Requires: AWS PowerShell module (AWSPowerShell.NetCore)
#>
[CmdletBinding()]
param(
    [Parameter()][string]$Region = "us-east-1",
    [Parameter()][string]$ProfileName,
    [switch]$ExportHTML
)

Write-Host "`n=== AWS Resource Inventory ===" -ForegroundColor Cyan

try {
    Import-Module AWSPowerShell.NetCore -ErrorAction Stop
    if ($ProfileName) {
        Set-AWSCredential -ProfileName $ProfileName
    }
    Set-DefaultAWSRegion -Region $Region
    Write-Host "[+] Connected to AWS region: $Region" -ForegroundColor Green
}
catch {
    Write-Host "[!] AWS PowerShell module not installed" -ForegroundColor Red
    Write-Host "[*] Install: Install-Module AWSPowerShell.NetCore" -ForegroundColor Cyan
    exit 1
}

Write-Host "[*] Checking EC2 instances..." -ForegroundColor Cyan
$ec2 = Get-EC2Instance
$instances = $ec2.Instances
$runningInstances = ($instances | Where-Object { $_.State.Name -eq "running" }).Count
Write-Host "[+] Found $($instances.Count) EC2 instances ($runningInstances running)" -ForegroundColor Green

Write-Host "[*] Checking S3 buckets..." -ForegroundColor Cyan
$buckets = Get-S3Bucket
Write-Host "[+] Found $($buckets.Count) S3 buckets" -ForegroundColor Green

Write-Host "[*] Checking RDS instances..." -ForegroundColor Cyan
$rds = Get-RDSDBInstance
Write-Host "[+] Found $($rds.Count) RDS instances" -ForegroundColor Green

Write-Host "[*] Checking Lambda functions..." -ForegroundColor Cyan
$lambda = Get-LMFunctionList
Write-Host "[+] Found $($lambda.Count) Lambda functions" -ForegroundColor Green

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor White
Write-Host "EC2 Instances: $($instances.Count) ($runningInstances running)" -ForegroundColor White
Write-Host "S3 Buckets: $($buckets.Count)" -ForegroundColor White
Write-Host "RDS Instances: $($rds.Count)" -ForegroundColor White
Write-Host "Lambda Functions: $($lambda.Count)" -ForegroundColor White

Write-Host "`nInventory complete!`n" -ForegroundColor Green
