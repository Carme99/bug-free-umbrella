# Performance Diagnostics

[![Tier 3](https://img.shields.io/badge/Documentation-Tier%203-blue)]()
[![Diagnostics](https://img.shields.io/badge/Focus-Diagnostics-red)]()
[![Troubleshooting](https://img.shields.io/badge/Type-Troubleshooting-yellow)]()

## Table of Contents

- [Overview](#overview)
- [Identifying Bottlenecks](#identifying-bottlenecks)
- [Profiling Techniques](#profiling-techniques)
- [Integration Issue Diagnosis](#integration-issue-diagnosis)
- [Resource Bottlenecks](#resource-bottlenecks)
- [Diagnostic Tools](#diagnostic-tools)
- [Common Performance Issues](#common-performance-issues)
- [Troubleshooting Flowchart](#troubleshooting-flowchart)

## Overview

Performance problems are often symptoms of deeper issues. This guide helps you systematically diagnose the root cause.

### Performance Tiers

| Duration | Classification | Action |
|----------|-----------------|--------|
| < 100ms | Excellent | No action needed |
| 100ms - 1s | Acceptable | Monitor for patterns |
| 1s - 10s | Slow | Investigate |
| > 10s | Critical | Immediate action required |

## Identifying Bottlenecks

### The Profiler Script

```powershell
function Get-ExecutionProfile {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [int]$Iterations = 3
    )
    
    $results = @()
    
    for ($run = 1; $run -le $Iterations; $run++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            & $ScriptBlock
            $sw.Stop()
            
            $results += [PSCustomObject]@{
                Run          = $run
                ElapsedMS    = $sw.ElapsedMilliseconds
                ElapsedTicks = $sw.ElapsedTicks
                Status       = "Success"
            }
        }
        catch {
            $sw.Stop()
            $results += [PSCustomObject]@{
                Run    = $run
                Error  = $_.Exception.Message
                Status = "Failed"
            }
        }
    }
    
    $avg = ($results.ElapsedMS | Measure-Object -Average).Average
    $max = ($results.ElapsedMS | Measure-Object -Maximum).Maximum
    $min = ($results.ElapsedMS | Measure-Object -Minimum).Minimum
    
    Write-Host "\nExecution Profile Summary:"
    Write-Host "Average: $avg ms | Min: $min ms | Max: $max ms"
    
    return $results
}
```

### Line-Level Profiling

```powershell
function Measure-PipelinePerformance {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$Items
    )
    
    begin {
        $pipelineMetrics = @{
            StartTime      = Get-Date
            ItemsProcessed = 0
            ItemsPerSecond = 0
        }
    }
    
    process {
        $pipelineMetrics.ItemsProcessed++
        
        if ($pipelineMetrics.ItemsProcessed % 100 -eq 0) {
            $elapsed = ((Get-Date) - $pipelineMetrics.StartTime).TotalSeconds
            $pipelineMetrics.ItemsPerSecond = [math]::Round($pipelineMetrics.ItemsProcessed / $elapsed, 2)
            
            Write-Verbose "Processed: $($pipelineMetrics.ItemsProcessed) items @ $($pipelineMetrics.ItemsPerSecond) items/sec"
        }
        
        $_
    }
}
```

## Profiling Techniques

### API Response Time Analysis

```powershell
function Analyze-APIPerformance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        
        [int]$RequestCount = 10
    )
    
    $results = @()
    
    for ($i = 1; $i -le $RequestCount; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 30
            $sw.Stop()
            
            $results += [PSCustomObject]@{
                RequestNo      = $i
                StatusCode     = $response.StatusCode
                ResponseTimeMS = $sw.ElapsedMilliseconds
                SizeBytes      = $response.Content.Length
                Success        = $true
            }
        }
        catch {
            $sw.Stop()
            $results += [PSCustomObject]@{
                RequestNo      = $i
                StatusCode     = "N/A"
                ResponseTimeMS = $sw.ElapsedMilliseconds
                Error          = $_.Exception.Message
                Success        = $false
            }
        }
        
        Start-Sleep -Milliseconds 500
    }
    
    return $results | Tee-Object -Variable analysis | Format-Table
    
    # Summary
    Write-Host "\nPerformance Summary:"
    Write-Host "Average Response Time: $($analysis.ResponseTimeMS | Measure-Object -Average | Select-Object -ExpandProperty Average) ms"
    Write-Host "P95 Response Time: $($analysis.ResponseTimeMS | Sort-Object | Select-Object -Index ([int]($analysis.Count * 0.95))) ms"
    Write-Host "Success Rate: $(($analysis | Where-Object Success).Count / $analysis.Count * 100)%"
}
```

## Integration Issue Diagnosis

### Azure DevOps Integration Test

```powershell
function Test-AzureDevOpsIntegration {
    param(
        [string]$Organization,
        [string]$Project,
        [string]$PAT
    )
    
    $results = @{
        Authentication = @{}
        Connectivity   = @{}
        Performance    = @{}
        Issues         = @()
    }
    
    # Test 1: Authentication
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $header = @{
            Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
        }
        $response = Invoke-RestMethod -Uri "https://dev.azure.com/$Organization/_apis/projects?api-version=7.0" -Headers $header
        $sw.Stop()
        
        $results.Authentication.Success = $true
        $results.Authentication.ResponseTimeMS = $sw.ElapsedMilliseconds
    }
    catch {
        $results.Authentication.Success = $false
        $results.Authentication.Error = $_.Exception.Message
        $results.Issues += "Azure DevOps authentication failed: $($_.Exception.Message)"
    }
    
    return $results
}
```

## Resource Bottlenecks

### CPU Bottleneck Detection

```powershell
function Detect-CPUBottleneck {
    # CPU consistently > 80%
    $cpuUsage = (Get-WmiObject Win32_PerfFormattedData_PerfOS_Processor -Filter 'Name="_Total"').PercentProcessorTime
    
    if ($cpuUsage -gt 80) {
        Write-Warning "High CPU usage detected: $cpuUsage%"
        
        # Find top processes
        Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 | 
            Format-Table Name, CPU, Memory
        
        return $true
    }
    
    return $false
}

### Memory Bottleneck Detection

function Detect-MemoryBottleneck {
    $os = Get-WmiObject Win32_OperatingSystem
    $memUsage = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100
    
    if ($memUsage -gt 85) {
        Write-Warning "High memory usage detected: $memUsage%"
        
        # Find top memory consumers
        Get-Process | Sort-Object Memory -Descending | Select-Object -First 10 | 
            Format-Table Name, @{Name = "Memory(MB)"; Expression = { $_.Memory / 1MB } }
        
        return $true
    }
    
    return $false
}

### Disk I/O Bottleneck Detection

function Detect-DiskIOBottleneck {
    $disk = Get-WmiObject Win32_PerfFormattedData_PerfDisk_LogicalDisk -Filter "Name != '_Total'"
    
    foreach ($d in $disk) {
        if ($d.PercentDiskTime -gt 80) {
            Write-Warning "High disk I/O on $($d.Name): $($d.PercentDiskTime)%"
            return $true
        }
    }
    
    return $false
}
```

## Diagnostic Tools

### Event Viewer Performance Logs

```powershell
function Get-PerformanceWarnings {
    param(
        [int]$Hours = 24
    )
    
    $startTime = (Get-Date).AddHours(-$Hours)
    
    Get-WinEvent -FilterHashtable @{
        LogName      = "System"
        StartTime    = $startTime
        Level        = 2, 3  # Warnings and errors
    } -ErrorAction SilentlyContinue | 
        Where-Object { $_.Message -match "performance|timeout|bottleneck" } | 
        Format-Table TimeCreated, Id, Message
}

### Task Manager Alternative

function Get-ProcessMetrics {
    $processes = Get-Process
    
    return $processes | Select-Object Name, 
        @{Name = "CPU%"; Expression = { $_.CPU } },
        @{Name = "Memory(MB)"; Expression = { $_.Memory / 1MB } },
        @{Name = "Handles"; Expression = { $_.Handles } } | 
        Sort-Object Memory -Descending | 
        Select-Object -First 20
}
```

## Common Performance Issues

| Issue | Symptom | Diagnosis | Solution |
|-------|---------|-----------|----------|
| Array concatenation | Slow data collection | Check for += in loops | Use ArrayList or pipeline |
| COM marshalling | Slow Excel/Office operations | Monitor CPU during operation | Cache COM objects |
| Network latency | Slow API/DB calls | Use network monitoring tools | Implement connection pooling |
| Disk thrashing | High CPU but low utilization | Check Task Manager Disk % | Increase RAM or optimize I/O |
| Error handling | Script pauses intermittently | Look for nested try-catch blocks | Optimize error handling |

## Troubleshooting Flowchart

```
┌─ Slow Script?
├─ Is it consistent?
│  ├─ Yes → Check for input dependency
│  │         (Data size, environment load, network)
│  └─ No → Check for intermittent issues
│          (Antivirus, background processes)
├─ What's the bottleneck?
│  ├─ CPU > 80%? → Optimize algorithm, parallelize
│  ├─ Memory > 85%? → Reduce dataset size, add streaming
│  ├─ Disk I/O > 80%? → Batch writes, optimize I/O
│  └─ Network latency? → Add connection pooling, cache
└─ Profile the code
   ├─ Function-level timing
   └─ Line-level hotspots
```

---

**See Also:** [Performance-Tuning.md](Performance-Tuning.md) | [Advanced-Scripting-Patterns.md](Advanced-Scripting-Patterns.md)