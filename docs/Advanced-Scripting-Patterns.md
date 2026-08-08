# Advanced Scripting Patterns

[![Tier 3](https://img.shields.io/badge/Documentation-Tier%203-blue)]()
[![Advanced](https://img.shields.io/badge/Level-Advanced-red)]()
[![PowerShell](https://img.shields.io/badge/Language-PowerShell-blue?logo=powershell)]()
[![Patterns](https://img.shields.io/badge/Category-Design%20Patterns-green)]()

## Table of Contents

- [Overview](#overview)
- [Error Handling Strategies](#error-handling-strategies)
- [Retry Logic Patterns](#retry-logic-patterns)
- [Logging Frameworks](#logging-frameworks)
- [Parallel Execution](#parallel-execution)
- [State Management](#state-management)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

This guide covers advanced PowerShell scripting patterns for building robust, maintainable, and scalable automation solutions. These patterns are essential for production-grade scripts that handle complex scenarios and failures gracefully.

### Why Advanced Patterns Matter

- **Reliability**: Proper error handling prevents cascading failures
- **Maintainability**: Consistent patterns make code easier to debug and modify
- **Performance**: Parallel execution and batching improve throughput
- **Observability**: Comprehensive logging enables troubleshooting
- **Resilience**: Retry logic and exponential backoff handle transient failures

## Error Handling Strategies

### Comprehensive Try-Catch-Finally

```powershell
try {
    # Operation that might fail
    $result = Invoke-RestMethod -Uri "https://api.example.com/resource" -ErrorAction Stop
    
    # Process result
    if ($result.Count -eq 0) {
        Write-Warning "No resources found"
    }
}
catch [System.Net.HttpRequestException] {
    # Handle network-specific errors
    Write-Error "Network error occurred: $_" -ErrorAction Stop
    exit 1
}
catch [System.InvalidOperationException] {
    # Handle invalid operations
    Write-Error "Invalid operation: $_" -ErrorAction Stop
    exit 2
}
catch {
    # Handle all other errors
    Write-Error "Unexpected error: $_" -ErrorAction Stop
    exit 99
}
finally {
    # Cleanup code (always executes)
    Write-Verbose "Cleanup: Releasing resources"
    if ($null -ne $connection) {
        $connection.Close()
    }
}
```

### Error Context Preservation

```powershell
function Invoke-OperationWithContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperationName,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation
    )
    
    try {
        Write-Verbose "Starting operation: $OperationName"
        $startTime = Get-Date
        
        $result = & $Operation
        
        $duration = (Get-Date) - $startTime
        Write-Verbose "Completed operation: $OperationName (Duration: $($duration.TotalSeconds)s)"
        
        return $result
    }
    catch {
        $errorContext = @{
            Operation   = $OperationName
            Error       = $_.Exception.Message
            ErrorCode   = $_.Exception.HResult
            ScriptLine  = $_.InvocationInfo.ScriptLineNumber
            Timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        Write-Error ("Operation '$OperationName' failed: $($_.Exception.Message) " +
                    "(Line: $($_.InvocationInfo.ScriptLineNumber))") -ErrorAction Stop
    }
}

# Usage
Invoke-OperationWithContext -OperationName "FetchUserData" -Operation {
    Get-ADUser -Identity "user@domain.com"
}
```

## Retry Logic Patterns

### Exponential Backoff Retry

```powershell
function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        
        [int]$MaxAttempts = 3,
        [int]$InitialDelaySeconds = 1,
        [double]$BackoffMultiplier = 2.0,
        [int]$MaxDelaySeconds = 60
    )
    
    $attempt = 0
    $delay = $InitialDelaySeconds
    
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        
        try {
            Write-Verbose "Attempt $attempt of $MaxAttempts"
            return & $Operation
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                Write-Error "Operation failed after $MaxAttempts attempts: $_" -ErrorAction Stop
            }
            
            Write-Warning "Attempt $attempt failed: $_. Retrying in $delay seconds..."
            Start-Sleep -Seconds $delay
            
            # Calculate next delay with exponential backoff
            $delay = [math]::Min([math]::Floor($delay * $BackoffMultiplier), $MaxDelaySeconds)
        }
    }
}

# Usage
$result = Invoke-WithRetry -Operation {
    Invoke-RestMethod -Uri "https://api.example.com/endpoint" -ErrorAction Stop
} -MaxAttempts 5 -InitialDelaySeconds 2 -BackoffMultiplier 2
```

### Conditional Retry Logic

```powershell
function Invoke-ConditionalRetry {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        
        [scriptblock]$RetryPredicate = { $true },
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 5
    )
    
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $result = & $Operation
            return $result
        }
        catch {
            # Check if we should retry based on predicate
            $shouldRetry = & $RetryPredicate -Exception $_.Exception -Attempt $attempt -MaxAttempts $MaxAttempts
            
            if (-not $shouldRetry -or $attempt -eq $MaxAttempts) {
                throw $_
            }
            
            Write-Warning "Attempt $attempt failed (retryable). Waiting $DelaySeconds seconds..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

# Usage with custom predicate
$predicate = {
    param($Exception, $Attempt, $MaxAttempts)
    
    # Retry on transient errors
    return $Exception.Message -match "timeout|connection" -and $Attempt -lt $MaxAttempts
}

Invoke-ConditionalRetry -Operation { Get-Service } -RetryPredicate $predicate
```

## Logging Frameworks

### Structured Logging Implementation

```powershell
class StructuredLogger {
    [string]$LogPath
    [string]$ScriptName
    [string]$ExecutionId
    
    StructuredLogger([string]$logPath, [string]$scriptName) {
        $this.LogPath = $logPath
        $this.ScriptName = $scriptName
        $this.ExecutionId = [guid]::NewGuid().ToString()
        
        # Create log directory if needed
        if (-not (Test-Path $logPath)) {
            New-Item -ItemType Directory -Path $logPath -Force | Out-Null
        }
    }
    
    [void]LogInfo([string]$message, [hashtable]$context = @{}) {
        $this.WriteLog("INFO", $message, $context)
    }
    
    [void]LogWarning([string]$message, [hashtable]$context = @{}) {
        $this.WriteLog("WARN", $message, $context)
    }
    
    [void]LogError([string]$message, [Exception]$exception, [hashtable]$context = @{}) {
        if ($exception) {
            $context["Exception"] = $exception.Message
            $context["StackTrace"] = $exception.StackTrace
        }
        $this.WriteLog("ERROR", $message, $context)
    }
    
    [void]LogDebug([string]$message, [hashtable]$context = @{}) {
        $this.WriteLog("DEBUG", $message, $context)
    }
    
    hidden [void]WriteLog([string]$level, [string]$message, [hashtable]$context) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $logEntry = @{
            Timestamp    = $timestamp
            Level        = $level
            ExecutionId  = $this.ExecutionId
            Script       = $this.ScriptName
            Message      = $message
            Context      = $context
        }
        
        $jsonEntry = $logEntry | ConvertTo-Json -Compress
        $logFile = Join-Path $this.LogPath "$($this.ScriptName)-$(Get-Date -Format 'yyyy-MM-dd').log"
        
        Add-Content -Path $logFile -Value $jsonEntry -Encoding UTF8
        
        # Also write to console
        Write-Host "[$timestamp][$level] $message" -ForegroundColor $this.GetColorForLevel($level)
    }
    
    hidden [ConsoleColor]GetColorForLevel([string]$level) {
        switch ($level) {
            "ERROR"   { return "Red" }
            "WARN"    { return "Yellow" }
            "INFO"    { return "Green" }
            "DEBUG"   { return "Gray" }
            default   { return "White" }
        }
    }
}

# Usage
$logger = [StructuredLogger]::new("C:\Logs", "MyScript.ps1")
$logger.LogInfo("Script started")
$logger.LogInfo("Processing users", @{ "Count" = 100; "Filter" = "Active" })
$logger.LogError("User processing failed", $exception, @{ "UserId" = "user123" })
```

## Parallel Execution

### Parallel Processing with Foreach-Object

```powershell
# Sequential processing (slow)
$users = Get-ADUser -Filter * | Select-Object -First 100
$results = $users | ForEach-Object {
    Get-ADUserMemberOf -Identity $_ | Measure-Object
}

# Parallel processing (fast)
$results = $users | ForEach-Object -Parallel {
    Get-ADUserMemberOf -Identity $_ | Measure-Object
} -ThrottleLimit 10
```

### Advanced Parallel Job Management

```powershell
function Invoke-ParallelOperation {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Items,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        
        [int]$ThrottleLimit = [Environment]::ProcessorCount,
        [int]$TimeoutSeconds = 600
    )
    
    $jobs = @()
    $processedItems = 0
    $itemCount = $Items.Count
    
    try {
        foreach ($item in $Items) {
            # Wait if we've reached throttle limit
            while ((Get-Job -State Running | Measure-Object).Count -ge $ThrottleLimit) {
                Start-Sleep -Milliseconds 100
            }
            
            # Start job
            $job = Start-Job -ScriptBlock $Operation -ArgumentList $item
            $jobs += $job
        }
        
        # Wait for all jobs with timeout
        $startTime = Get-Date
        while ((Get-Job -State Running | Measure-Object).Count -gt 0) {
            $elapsed = (Get-Date) - $startTime
            
            if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
                Write-Warning "Operation timeout after $TimeoutSeconds seconds"
                Get-Job | Stop-Job
                throw "Operation timeout"
            }
            
            Start-Sleep -Milliseconds 500
        }
        
        # Collect results
        $results = @()
        foreach ($job in $jobs) {
            $result = Receive-Job -Job $job -ErrorAction Continue
            $results += $result
        }
        
        return $results
    }
    finally {
        Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
    }
}
```

## State Management

### Persisting State Between Runs

```powershell
class StateManager {
    [string]$StateFilePath
    [hashtable]$State
    
    StateManager([string]$filePath) {
        $this.StateFilePath = $filePath
        $this.LoadState()
    }
    
    [void]LoadState() {
        if (Test-Path $this.StateFilePath) {
            $json = Get-Content -Path $this.StateFilePath -Raw | ConvertFrom-Json
            $this.State = @{}
            $json.PSObject.Properties | ForEach-Object {
                $this.State[$_.Name] = $_.Value
            }
        } else {
            $this.State = @{}
        }
    }
    
    [void]SaveState() {
        $this.State | ConvertTo-Json | Set-Content -Path $this.StateFilePath -Force
    }
    
    [object]Get([string]$key) {
        return $this.State[$key]
    }
    
    [void]Set([string]$key, [object]$value) {
        $this.State[$key] = $value
        $this.SaveState()
    }
}

# Usage
$state = [StateManager]::new("C:\Scripts\state.json")
$lastRunTime = $state.Get("LastRunTime")
$state.Set("LastRunTime", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
```

## Best Practices

✅ **Do:**
- Use `-ErrorAction Stop` in try blocks
- Implement comprehensive logging
- Use structured error handling
- Test retry logic thoroughly
- Document expected exceptions
- Use `finally` blocks for cleanup
- Validate inputs at function boundaries
- Use timeout mechanisms for long operations

❌ **Don't:**
- Catch generic exceptions without logging
- Ignore transient failures
- Use bare `catch` blocks without context
- Log sensitive data (passwords, tokens)
- Retry on permanent failures
- Assume operations complete silently

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Retry loop never exits | RetryPredicate always returns true | Ensure predicate checks MaxAttempts |
| Parallel jobs hang | Missing throttle limit | Set appropriate ThrottleLimit value |
| Logging fills disk space | No log rotation | Implement age-based log cleanup |
| State file corruption | Concurrent writes | Use file locking mechanism |

### Debug Commands

```powershell
# Check job status
Get-Job | Select-Object Id, Name, State, PSBeginTime, PSEndTime

# View job errors
Get-Job -State Failed | ForEach-Object { Receive-Job -Job $_ -ErrorAction Continue }

# Monitor script execution
GPO -ChildPath "*.log" | Get-Content -Tail 50 -Wait
```

---

**See Also:** [Performance-Tuning.md](Performance-Tuning.md) | [Security-Troubleshooting.md](Security-Troubleshooting.md) | [API-Reference.md](API-Reference.md)
