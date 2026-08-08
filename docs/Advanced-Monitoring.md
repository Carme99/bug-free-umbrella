# Advanced Monitoring

[![Tier 3](https://img.shields.io/badge/Documentation-Tier%203-blue)]()
[![Monitoring](https://img.shields.io/badge/Focus-Monitoring-brightgreen)]()
[![Operations](https://img.shields.io/badge/Type-Operations-blue)]()

## Table of Contents

- [Overview](#overview)
- [Custom Alerting](#custom-alerting)
- [Metric Collection](#metric-collection)
- [Dashboard Integration](#dashboard-integration)
- [Log Aggregation](#log-aggregation)
- [Health Checks](#health-checks)
- [Trend Analysis](#trend-analysis)
- [Alerting Best Practices](#alerting-best-practices)

## Overview

Advanced monitoring goes beyond basic logging to provide actionable insights through metrics, alerts, and dashboards.

## Custom Alerting

### Email Alert System

```powershell
class AlertManager {
    [string]$SMTPServer
    [int]$SMTPPort
    [pscredential]$SMTPCredential
    [string]$FromAddress
    [string[]]$AlertRecipients
    
    AlertManager([string]$smtpServer, [string]$fromAddress, [string[]]$recipients) {
        $this.SMTPServer = $smtpServer
        $this.SMTPPort = 587
        $this.FromAddress = $fromAddress
        $this.AlertRecipients = $recipients
    }
    
    [void]SendAlert([string]$subject, [string]$body, [string]$severity) {
        $params = @{
            SmtpServer      = $this.SMTPServer
            Port            = $this.SMTPPort
            From            = $this.FromAddress
            To              = $this.AlertRecipients
            Subject         = "[$severity] $subject"
            Body            = $this.FormatAlertBody($body, $severity)
            BodyAsHtml      = $true
            ErrorAction     = "Continue"
        }
        
        if ($this.SMTPCredential) {
            $params["Credential"] = $this.SMTPCredential
            $params["UseSsl"] = $true
        }
        
        Send-MailMessage @params
    }
    
    hidden [string]FormatAlertBody([string]$body, [string]$severity) {
        $color = switch ($severity) {
            "CRITICAL" { "#ff0000" }
            "WARNING"  { "#ffaa00" }
            "INFO"     { "#0066ff" }
            default    { "#333333" }
        }
        
        return @"
        <html>
            <body>
                <div style="border-left: 4px solid $color; padding: 10px;">
                    <h3 style="color: $color;">[$severity] Alert</h3>
                    <p>$body</p>
                    <p style="color: #666; font-size: 12px;">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
                </div>
            </body>
        </html>
"@
    }
}

# Usage
$alertManager = [AlertManager]::new("smtp.gmail.com", "alerts@company.com", @("admin@company.com"))
$alertManager.SendAlert("High CPU Usage", "CPU exceeded 85% on Server1", "WARNING")
```

### Webhook-based Alerts

```powershell
function Send-WebhookAlert {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WebhookUrl,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARNING", "CRITICAL")]
        [string]$Severity = "INFO",
        
        [hashtable]$Context = @{}
    )
    
    $payload = @{
        timestamp = Get-Date -Format "o"
        severity  = $Severity
        message   = $Message
        context   = $Context
        hostname  = [System.Net.Dns]::GetHostName()
    } | ConvertTo-Json -Depth 5
    
    try {
        Invoke-RestMethod -Uri $WebhookUrl -Method POST -Body $payload -ContentType "application/json" -ErrorAction Stop
        Write-Verbose "Alert sent to webhook"
    }
    catch {
        Write-Error "Failed to send webhook alert: $_"
    }
}

# Usage with Teams/Slack
Send-WebhookAlert -WebhookUrl "https://hooks.slack.com/services/XXX/YYY/ZZZ" `
                  -Message "Deployment completed" `
                  -Severity "INFO" `
                  -Context @{ Environment = "Production"; Version = "3.7.0" }
```

## Metric Collection

### Prometheus Metrics Export

```powershell
class PrometheusMetrics {
    [hashtable]$Metrics
    
    PrometheusMetrics() {
        $this.Metrics = @{}
    }
    
    [void]RecordGauge([string]$metricName, [double]$value, [hashtable]$labels = @{}) {
        $key = $this.GetMetricKey($metricName, $labels)
        $this.Metrics[$key] = @{
            Type  = "gauge"
            Value = $value
            Labels = $labels
        }
    }
    
    [void]RecordCounter([string]$metricName, [double]$value, [hashtable]$labels = @{}) {
        $key = $this.GetMetricKey($metricName, $labels)
        
        if ($this.Metrics.ContainsKey($key)) {
            $this.Metrics[$key].Value += $value
        } else {
            $this.Metrics[$key] = @{
                Type  = "counter"
                Value = $value
                Labels = $labels
            }
        }
    }
    
    [string]ExportMetrics() {
        $output = ""
        
        foreach ($metric in $this.Metrics.GetEnumerator()) {
            $name = $metric.Key.Split("{")[0]
            $labels = $metric.Value.Labels
            $value = $metric.Value.Value
            
            $labelStr = if ($labels.Count -gt 0) {
                '{' + ($labels.GetEnumerator() | ForEach-Object { "$($_.Key)=\"$($_.Value)\"" } | Join-String -Separator ",") + '}'
            } else {
                ""
            }
            
            $output += "$name$labelStr $value`n"
        }
        
        return $output
    }
    
    hidden [string]GetMetricKey([string]$name, [hashtable]$labels) {
        return "$name{$(($labels.GetEnumerator() | ForEach-Object { $_.Key }).Join(','))}"
    }
}
```

## Dashboard Integration

### Grafana JSON Export

```powershell
function New-GrafanaDashboard {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DashboardName,
        
        [Parameter(Mandatory = $true)]
        [hashtable[]]$Panels
    )
    
    $dashboard = @{
        dashboard = @{
            title   = $DashboardName
            uid     = [guid]::NewGuid().ToString().Replace("-", "").Substring(0, 16)
            version = 1
            panels  = $Panels
            time    = @{
                from = "now-6h"
                to   = "now"
            }
            timezone = "browser"
        }
        overwrite = $true
    }
    
    return $dashboard | ConvertTo-Json -Depth 10
}

# Usage
$panel = @{
    id        = 1
    title     = "CPU Usage"
    targets   = @(@{
        expr = "node_cpu_usage_percent"
    })
    gridPos   = @{ h = 8; w = 12; x = 0; y = 0 }
}

$json = New-GrafanaDashboard -DashboardName "System Metrics" -Panels @($panel)
```

## Log Aggregation

### ELK Stack Integration

```powershell
function Send-LogsToElasticsearch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ElasticsearchUrl,
        
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$Logs,
        
        [string]$Index = "powershell-logs"
    )
    
    begin {
        $bulkBody = ""
    }
    
    process {
        foreach ($log in $Logs) {
            $metadata = @{
                index = @{
                    _index = $Index
                    _type  = "_doc"
                }
            } | ConvertTo-Json -Compress
            
            $logJson = $log | ConvertTo-Json -Compress
            
            $bulkBody += "$metadata`n$logJson`n"
        }
    }
    
    end {
        if ($bulkBody.Length -gt 0) {
            try {
                Invoke-RestMethod -Uri "$ElasticsearchUrl/_bulk" `
                                  -Method POST `
                                  -Body $bulkBody `
                                  -ContentType "application/x-ndjson" `
                                  -ErrorAction Stop
                
                Write-Verbose "Logs sent to Elasticsearch"
            }
            catch {
                Write-Error "Failed to send logs: $_"
            }
        }
    }
}
```

## Health Checks

### System Health Dashboard

```powershell
function Get-SystemHealthReport {
    param(
        [string[]]$ComputerNames = @("localhost")
    )
    
    $healthReport = @()
    
    foreach ($computer in $ComputerNames) {
        $session = if ($computer -ne "localhost") {
            New-PSSession -ComputerName $computer
        } else {
            $null
        }
        
        $cpu = Invoke-Command -Session $session -ScriptBlock {
            (Get-WmiObject Win32_PerfFormattedData_PerfOS_Processor -Filter 'Name="_Total"').PercentProcessorTime
        }
        
        $memory = Invoke-Command -Session $session -ScriptBlock {
            $os = Get-WmiObject Win32_OperatingSystem
            ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100
        }
        
        $disk = Invoke-Command -Session $session -ScriptBlock {
            Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object {
                [PSCustomObject]@{
                    Drive = $_.DriveLetter
                    Free  = $_.SizeRemaining / $_.Size * 100
                }
            }
        }
        
        $healthReport += [PSCustomObject]@{
            Computer = $computer
            CPU      = "$([math]::Round($cpu, 2))%"
            Memory   = "$([math]::Round($memory, 2))%"
            Disk     = $disk
            Status   = if ($cpu -lt 80 -and $memory -lt 85) { "Healthy" } else { "Degraded" }
        }
        
        if ($session) { Remove-PSSession $session }
    }
    
    return $healthReport
}
```

## Trend Analysis

### Historical Metrics Tracking

```powershell
function Analyze-MetricTrend {
    param(
        [Parameter(Mandatory = $true)]
        [double[]]$Values,
        
        [int]$WindowSize = 7
    )
    
    if ($Values.Count -lt 2) {
        return "Insufficient data"
    }
    
    # Calculate moving average
    $movingAvg = @()
    for ($i = $WindowSize - 1; $i -lt $Values.Count; $i++) {
        $window = $Values[($i - $WindowSize + 1)..$i]
        $movingAvg += ($window | Measure-Object -Average).Average
    }
    
    # Calculate trend
    $trend = if ($movingAvg[-1] -gt $movingAvg[0]) { "Increasing" } else { "Decreasing" }
    $changePercent = (($movingAvg[-1] - $movingAvg[0]) / $movingAvg[0] * 100)
    
    return [PSCustomObject]@{
        Trend          = $trend
        ChangePercent  = [math]::Round($changePercent, 2)
        MovingAverage  = $movingAvg
        Current        = $Values[-1]
    }
}
```

## Alerting Best Practices

✅ **Do:**
- Set meaningful thresholds based on baseline data
- Include context in alert messages
- Use alert severity levels
- Implement alert deduplication
- Monitor alert system health
- Document runbooks for each alert

❌ **Don't:**
- Alert on every anomaly
- Use vague alert titles
- Send alerts without recommended actions
- Ignore repeated alerts
- Mix different severity levels

---

**See Also:** [Performance-Diagnostics.md](Performance-Diagnostics.md) | [Advanced-Monitoring.md](Advanced-Monitoring.md)
