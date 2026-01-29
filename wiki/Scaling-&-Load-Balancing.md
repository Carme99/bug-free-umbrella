# Scaling & Load Balancing

[![Tier 3](https://img.shields.io/badge/Documentation-Tier%203-blue)]()
[![Scaling](https://img.shields.io/badge/Focus-Scaling-brightgreen)]()
[![Performance](https://img.shields.io/badge/Type-Performance-orange)]()

## Table of Contents

- [Overview](#overview)
- [Horizontal Scaling](#horizontal-scaling)
- [Load Distribution](#load-distribution)
- [Job Distribution](#job-distribution)
- [Resource Management](#resource-management)
- [High-Volume Operations](#high-volume-operations)
- [Scaling Best Practices](#scaling-best-practices)

## Overview

Scaling enables scripts to handle large datasets and high-frequency execution without degradation.

## Horizontal Scaling

### Multi-Worker Architecture

```powershell
class WorkerPool {
    [string]$WorkerName
    [int]$WorkerCount
    [hashtable]$WorkerStatus
    [System.Collections.Queue]$TaskQueue
    
    WorkerPool([int]$count) {
        $this.WorkerCount = $count
        $this.WorkerStatus = @{}
        $this.TaskQueue = [System.Collections.Queue]::new()
        $this.InitializeWorkers()
    }
    
    [void]InitializeWorkers() {
        for ($i = 1; $i -le $this.WorkerCount; $i++) {
            $this.WorkerStatus["Worker-$i"] = @{
                Status       = "Ready"
                TasksProcessed = 0
                LastActivity = Get-Date
            }
        }
    }
    
    [void]EnqueueTask([object]$task) {
        $this.TaskQueue.Enqueue($task)
    }
    
    [object]DequeueTask() {
        if ($this.TaskQueue.Count -gt 0) {
            return $this.TaskQueue.Dequeue()
        }
        return $null
    }
    
    [hashtable]GetStatus() {
        return @{
            ActiveWorkers  = ($this.WorkerStatus.Values | Where-Object { $_.Status -eq "Active" }).Count
            IdleWorkers    = ($this.WorkerStatus.Values | Where-Object { $_.Status -eq "Ready" }).Count
            QueuedTasks    = $this.TaskQueue.Count
            TotalProcessed = ($this.WorkerStatus.Values.TasksProcessed | Measure-Object -Sum).Sum
        }
    }
}
```

## Load Distribution

### Round-Robin Load Balancer

```powershell
class LoadBalancer {
    [object[]]$Servers
    [int]$CurrentIndex
    
    LoadBalancer([object[]]$servers) {
        $this.Servers = $servers
        $this.CurrentIndex = 0
    }
    
    [object]GetNextServer() {
        $server = $this.Servers[$this.CurrentIndex]
        $this.CurrentIndex = ($this.CurrentIndex + 1) % $this.Servers.Count
        return $server
    }
    
    [object]GetLeastBusyServer() {
        return $this.Servers | Sort-Object ActiveConnections | Select-Object -First 1
    }
    
    [object]GetByHealth() {
        return $this.Servers | Where-Object { $_.HealthStatus -eq "Healthy" } | 
                Select-Object -First 1
    }
}

# Usage
$servers = @(
    @{ Name = "Server1"; ActiveConnections = 5 },
    @{ Name = "Server2"; ActiveConnections = 3 },
    @{ Name = "Server3"; ActiveConnections = 8 }
)

$lb = [LoadBalancer]::new($servers)
$selectedServer = $lb.GetLeastBusyServer()
```

## Job Distribution

### Distributed Job Scheduler

```powershell
function Invoke-DistributedJob {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,
        
        [Parameter(Mandatory = $true)]
        [string[]]$ComputerNames,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        
        [int]$BatchSize = 100
    )
    
    $itemBatches = @()
    
    # Partition items into batches
    for ($i = 0; $i -lt $Items.Count; $i += $BatchSize) {
        $batch = $Items[$i..([Math]::Min($i + $BatchSize - 1, $Items.Count - 1))]
        $itemBatches += @(, $batch)
    }
    
    # Distribute batches across computers
    $computerIndex = 0
    $jobs = @()
    
    foreach ($batch in $itemBatches) {
        $computer = $ComputerNames[$computerIndex % $ComputerNames.Count]
        $computerIndex++
        
        $job = Invoke-Command -ComputerName $computer -ScriptBlock $Operation `
                             -ArgumentList (,$batch) -AsJob
        $jobs += $job
    }
    
    # Wait for completion
    $jobs | Wait-Job
    
    # Collect results
    return $jobs | ForEach-Object { Receive-Job -Job $_ }
}
```

## Resource Management

### CPU/Memory Scaling Control

```powershell
function Adjust-ProcessingCapacity {
    param(
        [int]$TargetCPUUsage = 70,
        [int]$TargetMemoryUsage = 80
    )
    
    # Using Get-CimInstance instead of deprecated Get-WmiObject (PS 7+ compatible)
    $cpuUsage = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter 'Name="_Total"').PercentProcessorTime
    $os = Get-CimInstance Win32_OperatingSystem
    $memUsage = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100
    
    $adjustments = @{
        ThrottleLimit = 10
        BatchSize     = 100
        ParallelJobs  = [Environment]::ProcessorCount
    }
    
    if ($cpuUsage -gt $TargetCPUUsage) {
        $adjustments.ThrottleLimit = [Math]::Max(1, $adjustments.ThrottleLimit - 2)
        $adjustments.ParallelJobs = [Math]::Max(1, $adjustments.ParallelJobs - 1)
        Write-Verbose "CPU threshold exceeded. Reducing parallelism."
    }
    
    if ($memUsage -gt $TargetMemoryUsage) {
        $adjustments.BatchSize = [Math]::Max(10, $adjustments.BatchSize - 20)
        Write-Verbose "Memory threshold exceeded. Reducing batch size."
    }
    
    if ($cpuUsage -lt ($TargetCPUUsage - 20) -and $memUsage -lt ($TargetMemoryUsage - 20)) {
        $adjustments.ThrottleLimit = [Math]::Min(50, $adjustments.ThrottleLimit + 2)
        $adjustments.ParallelJobs = [Math]::Min([Environment]::ProcessorCount * 2, $adjustments.ParallelJobs + 1)
        Write-Verbose "Resources available. Increasing parallelism."
    }
    
    return $adjustments
}
```

## High-Volume Operations

> ⚠️ **PowerShell Version Requirement:** `ForEach-Object -Parallel` requires **PowerShell 7.0 or later**. If using PowerShell 5.1, use traditional `ForEach-Object` or `Invoke-Command -AsJob` instead.

### Bulk Processing Framework

```powershell
function Invoke-BulkOperation {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Items,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        
        [int]$BatchSize = 1000,
        [int]$MaxDegreeOfParallelism = 4
    )
    
    begin {
        $batch = [System.Collections.Generic.List[object]]::new($BatchSize)
        $totalProcessed = 0
        $startTime = Get-Date
    }
    
    process {
        foreach ($item in $Items) {
            $batch.Add($item)
            
            if ($batch.Count -ge $BatchSize) {
                Write-Progress -Activity "Processing" -Status "Items: $totalProcessed" -PercentComplete 0

                # PS 7.0+ only: ForEach-Object -Parallel. For PS 5.1, use Invoke-Command -AsJob instead
                $batchResults = $batch | ForEach-Object -Parallel $Operation -ThrottleLimit $MaxDegreeOfParallelism
                $batchResults
                
                $totalProcessed += $batch.Count
                $batch.Clear()
            }
        }
    }
    
    end {
        if ($batch.Count -gt 0) {
            # PS 7.0+ only: ForEach-Object -Parallel. For PS 5.1, use Invoke-Command -AsJob instead
            $batch | ForEach-Object -Parallel $Operation -ThrottleLimit $MaxDegreeOfParallelism
            $totalProcessed += $batch.Count
        }
        
        $elapsed = (Get-Date) - $startTime
        $throughput = $totalProcessed / $elapsed.TotalSeconds
        
        Write-Host "\nBulk operation completed:"
        Write-Host "  Total items: $totalProcessed"
        Write-Host "  Duration: $($elapsed.TotalSeconds) seconds"
        Write-Host "  Throughput: $([math]::Round($throughput, 2)) items/sec"
    }
}
```

## Scaling Best Practices

✅ **Do:**
- Monitor resource usage during scaling
- Implement graceful degradation
- Use batch processing for large operations
- Test under realistic load
- Implement backpressure mechanisms
- Use connection pooling
- Cache frequently accessed data

❌ **Don't:**
- Assume unlimited parallelism
- Ignore resource constraints
- Create threads/jobs without throttling
- Process unbounded datasets
- Ignore network bandwidth limits

---

**See Also:** [Performance-Tuning.md](Performance-Tuning.md) | [Advanced-Scripting-Patterns.md](Advanced-Scripting-Patterns.md)