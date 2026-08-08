# Performance Tuning

[![Tier 3](https://img.shields.io/badge/Documentation-Tier%203-blue)]()
[![Optimization](https://img.shields.io/badge/Focus-Optimization-orange)]()
[![Performance](https://img.shields.io/badge/Category-Performance-brightgreen)]()

## Table of Contents

- [Overview](#overview)
- [Script Optimization](#script-optimization)
- [Resource Management](#resource-management)
- [Batch Processing](#batch-processing)
- [Monitoring & Profiling](#monitoring--profiling)
- [Memory Management](#memory-management)
- [Benchmarking](#benchmarking)
- [Troubleshooting Performance](#troubleshooting-performance)

## Overview

Performance optimization is critical for scripts that process large datasets or run frequently. This guide covers techniques to identify bottlenecks and improve throughput.

### Expected Performance Baselines

- **User enumeration**: 100-500 users/second (AD)
- **File operations**: 1000-5000 files/second (local disk)
- **API calls**: 10-100 requests/second (depends on latency)
- **Database queries**: 100-1000 rows/second (depends on complexity)

## Script Optimization

### Avoid Common Performance Pitfalls

```powershell
# ❌ SLOW: Creating objects in loop
$results = @()
foreach ($item in $largeArray) {
    $obj = [PSCustomObject]@{
        Name = $item.Name
        Value = $item.Value
    }
    $results += $obj  # Array concatenation is O(n²)
}

# ✅ FAST: Use ArrayList
$results = [System.Collections.ArrayList]::new()
foreach ($item in $largeArray) {
    $obj = [PSCustomObject]@{
        Name = $item.Name
        Value = $item.Value
    }
    [void]$results.Add($obj)  # ArrayList.Add is O(1) amortized
}

# ✅ FASTEST: Pipeline-based processing
$results = $largeArray | Select-Object @{
    Name = "Name"; Expression = { $_.Name }
}, @{
    Name = "Value"; Expression = { $_.Value }
}
```

### Method Selection Performance

```powershell
# Performance comparison test
$testArray = 1..10000

# Method 1: For loop with += (SLOWEST)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$result = @()
for ($i = 0; $i -lt $testArray.Count; $i++) {
    $result += $testArray[$i]
}
$sw.Stop()
Write-Host "Array += method: $($sw.ElapsedMilliseconds)ms"

# Method 2: ArrayList (FAST)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$result = [System.Collections.ArrayList]::new()
foreach ($item in $testArray) {
    [void]$result.Add($item)
}
$sw.Stop()
Write-Host "ArrayList method: $($sw.ElapsedMilliseconds)ms"

# Method 3: Generic List (FASTEST)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$result = [System.Collections.Generic.List[object]]::new()
foreach ($item in $testArray) {
    $result.Add($item)
}
$sw.Stop()
Write-Host "Generic List method: $($sw.ElapsedMilliseconds)ms"

# Method 4: Streaming (MEMORY EFFICIENT)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$result = $testArray | Where-Object { $_ -gt 0 }
$sw.Stop()
Write-Host "Pipeline method: $($sw.ElapsedMilliseconds)ms"
```

## Resource Management

### CPU Optimization

```powershell
# Reduce unnecessary COM object creation
# ❌ SLOW
$excel = New-Object -ComObject Excel.Application
for ($i = 1; $i -le 10000; $i++) {
    $excel.ActiveSheet.Cells($i, 1) = "Value $i"  # Marshaling overhead per call
}

# ✅ FAST
$excel = New-Object -ComObject Excel.Application
$worksheet = $excel.ActiveSheet
for ($i = 1; $i -le 10000; $i++) {
    $worksheet.Cells($i, 1) = "Value $i"  # Fewer object crossings
}

# ✅ FASTEST
$excel = New-Object -ComObject Excel.Application
$range = $excel.ActiveSheet.Range("A1:A10000")
$range.Value = (1..10000 | ForEach-Object { "Value $_" })
```

### Disk I/O Optimization

```powershell
function Write-BatchedLog {
    param(
        [string]$LogPath,
        [string[]]$Messages,
        [int]$BatchSize = 1000
    )
    
    # ❌ SLOW: Write one line at a time
    foreach ($message in $Messages) {
        Add-Content -Path $LogPath -Value $message
    }
    
    # ✅ FAST: Batch writes
    for ($i = 0; $i -lt $Messages.Count; $i += $BatchSize) {
        $batch = $Messages[$i..([Math]::Min($i + $BatchSize - 1, $Messages.Count - 1))]
        $batch | Add-Content -Path $LogPath
    }
    
    # ✅ FASTEST: Single write operation
    [System.IO.File]::WriteAllLines($LogPath, $Messages)
}
```

## Batch Processing

### Chunking Large Operations

```powershell
function Process-InBatches {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$Items,
        
        [int]$BatchSize = 1000,
        [scriptblock]$Operation
    )
    
    $batch = [System.Collections.Generic.List[object]]::new($BatchSize)
    
    process {
        $batch.Add($_)
        
        if ($batch.Count -ge $BatchSize) {
            Write-Verbose "Processing batch of $($batch.Count) items"
            & $Operation -Items $batch.ToArray()
            $batch.Clear()
        }
    }
    
    end {
        if ($batch.Count -gt 0) {
            Write-Verbose "Processing final batch of $($batch.Count) items"
            & $Operation -Items $batch.ToArray()
        }
    }
}

# Usage
$users | Process-InBatches -BatchSize 100 -Operation {
    param([object[]]$Items)
    # Bulk update operation
    Update-ADUsers -Users $Items
}
```

## Monitoring & Profiling

### Built-in Profiling

```powershell
function Measure-ScriptPerformance {
    param(
        [scriptblock]$ScriptBlock,
        [int]$Iterations = 1
    )
    
    $measurements = @()
    
    for ($i = 0; $i -lt $Iterations; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = & $ScriptBlock
        $sw.Stop()
        
        $measurements += $sw.ElapsedMilliseconds
    }
    
    return [PSCustomObject]@{
        Count       = $measurements.Count
        Total       = ($measurements | Measure-Object -Sum).Sum
        Average     = ($measurements | Measure-Object -Average).Average
        Minimum     = ($measurements | Measure-Object -Minimum).Minimum
        Maximum     = ($measurements | Measure-Object -Maximum).Maximum
        StdDev      = $null
    }
}

# Usage
$result = Measure-ScriptPerformance -ScriptBlock {
    Get-Process | Where-Object { $_.CPU -gt 100 }
} -Iterations 10

Write-Output "Performance Results:`n$($result | Format-Table -AutoSize)"
```

### Real-time CPU Monitoring

```powershell
function Monitor-ProcessMetrics {
    param(
        [int]$IntervalSeconds = 5,
        [int]$DurationSeconds = 60
    )
    
    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($DurationSeconds)
    $metrics = @()
    
    while ((Get-Date) -lt $endTime) {
        $cpuUsage = Get-WmiObject Win32_PerfFormattedData_PerfOS_Processor -Filter 'Name="_Total"' | 
                    Select-Object -ExpandProperty PercentProcessorTime
        
        $memUsage = Get-WmiObject Win32_OperatingSystem | 
                    ForEach-Object { [math]::Round(($_.TotalVisibleMemorySize - $_.FreePhysicalMemory) / $_.TotalVisibleMemorySize * 100, 2) }
        
        $metrics += [PSCustomObject]@{
            Timestamp = Get-Date
            CPUPercent = $cpuUsage
            MemPercent = $memUsage
        }
        
        Write-Host "CPU: $cpuUsage% | Memory: $memUsage%"
        Start-Sleep -Seconds $IntervalSeconds
    }
    
    return $metrics
}
```

## Memory Management

### Detecting Memory Leaks

```powershell
function Test-MemoryLeak {
    param(
        [scriptblock]$Operation,
        [int]$Iterations = 100
    )
    
    # Get baseline
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    $baselineMemory = [System.Diagnostics.Process]::GetCurrentProcess().WorkingSet64
    
    # Run operations
    for ($i = 0; $i -lt $Iterations; $i++) {
        & $Operation | Out-Null
        
        if (($i + 1) % 10 -eq 0) {
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            
            $currentMemory = [System.Diagnostics.Process]::GetCurrentProcess().WorkingSet64
            $increase = ($currentMemory - $baselineMemory) / 1MB
            
            Write-Host "Iteration $($i + 1): Memory increase: $increase MB"
        }
    }
}

# Usage
Test-MemoryLeak -Operation {
    Get-Process | Select-Object Name, CPU, Memory
} -Iterations 100
```

## Benchmarking

### Performance Baselines

| Operation | Time | Notes |
|-----------|------|-------|
| Get-Process (1 call) | 50-100ms | First call slower due to snap-in loading |
| Get-ADUser (1000 results) | 1-2s | Depends on domain size and network |
| Invoke-RestMethod (single) | 100-500ms | Depends on API latency |
| Invoke-SqlCmd (query) | 50-200ms | Depends on query complexity |

## Troubleshooting Performance

### Diagnostic Checklist

- [ ] Is the script waiting on I/O (disk/network)?
- [ ] Are there unnecessary COM object creations?
- [ ] Is the script using pipeline correctly?
- [ ] Are there unneeded object conversions?
- [ ] Is memory being released properly?
- [ ] Are error handling overheads affecting performance?

---

**See Also:** [Performance-Diagnostics.md](Performance-Diagnostics.md) | [Advanced-Scripting-Patterns.md](Advanced-Scripting-Patterns.md)
