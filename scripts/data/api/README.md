# API Management & Monitoring Scripts

> **⚠️ IMPORTANT NOTICE**: The vast majority of scripts in this repository have not been thoroughly tested in production environments. Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.

This category contains comprehensive monitoring and health check scripts for API management platforms and API endpoints.

## 📋 Available Scripts

### 1. Monitor-AzureAPIManagement.ps1
Comprehensive Azure API Management (APIM) service monitoring.

**Features:**
- API gateway health and availability status
- API call volume and success rates by API/operation
- Response time analysis and SLA compliance
- Error rate tracking (4xx, 5xx errors)
- Backend service health monitoring
- Capacity and performance metrics
- Published API inventory

**Example:**
```powershell
Connect-AzAccount
.\Monitor-AzureAPIManagement.ps1 -SubscriptionId "sub-id" `
    -ResourceGroupName "rg-apim" `
    -ServiceName "myapim" `
    -DaysToAnalyze 30 `
    -IncludeAPIDetails `
    -IncludeBackendHealth
```

---

### 2. Test-APIHealth.ps1
Universal API endpoint health testing and validation.

**Features:**
- Endpoint availability testing
- Response time monitoring
- SSL/TLS certificate validation
- Security header verification
- Response code validation
- Continuous monitoring mode
- Multi-endpoint testing from configuration file

**Example:**
```powershell
# Test single endpoint
.\Test-APIHealth.ps1 -SingleEndpoint "https://api.example.com/health" `
    -ExpectedStatusCode 200 `
    -MaxResponseTime 1000

# Test multiple endpoints from file
.\Test-APIHealth.ps1 -EndpointsFile ".\api-endpoints.json" -OutputFormat HTML

# Continuous monitoring
.\Test-APIHealth.ps1 -EndpointsFile ".\endpoints.json" `
    -RunContinuous `
    -IntervalSeconds 300
```

**Endpoints File Format:**
```json
[
  {
    "Name": "Health Check",
    "Url": "https://api.example.com/health",
    "Method": "GET",
    "ExpectedStatusCode": 200,
    "MaxResponseTime": 1000,
    "Headers": {
      "Authorization": "Bearer token123"
    }
  },
  {
    "Name": "User API",
    "Url": "https://api.example.com/v1/users",
    "Method": "GET",
    "ExpectedStatusCode": 200,
    "MaxResponseTime": 2000
  }
]
```

---

## 🎯 Common Use Cases

### Monitor Azure APIM Health
```powershell
# Connect to Azure
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"

# Generate comprehensive health report
.\Monitor-AzureAPIManagement.ps1 -SubscriptionId "sub-id" `
    -ResourceGroupName "rg-production" `
    -ServiceName "prod-apim" `
    -DaysToAnalyze 7 `
    -IncludeAPIDetails `
    -IncludeBackendHealth `
    -OutputFormat HTML
```

### Validate API SLA Compliance
```powershell
# Test critical endpoints with strict SLA requirements
.\Test-APIHealth.ps1 -EndpointsFile ".\production-apis.json" `
    -MaxResponseTime 500 `
    -OutputFormat JSON
```

### Continuous API Monitoring
```powershell
# Monitor APIs every 5 minutes
.\Test-APIHealth.ps1 -EndpointsFile ".\critical-apis.json" `
    -RunContinuous `
    -IntervalSeconds 300 `
    -OutputFormat Console
```

### SSL Certificate Expiration Monitoring
```powershell
# Check SSL certificates across all HTTPS APIs
.\Test-APIHealth.ps1 -EndpointsFile ".\https-endpoints.json" `
    -OutputFormat HTML
# Report will include SSL expiration warnings for certs expiring within 30 days
```

---

## 📊 Metrics Tracked

### Azure API Management Metrics
- **Availability**: Gateway uptime and health status
- **Request Volume**: Total requests, requests per day
- **Success Rate**: Percentage of successful requests
- **Error Rates**: 4xx client errors, 5xx server errors
- **Performance**: Average response time, capacity utilization
- **APIs**: Number of published APIs and operations
- **Backends**: Backend service health and connectivity

### API Health Test Metrics
- **Availability**: Endpoint reachability
- **Response Time**: Request latency in milliseconds
- **Status Codes**: HTTP response code validation
- **SSL Validity**: Certificate expiration and trust
- **Security Headers**: Presence of security headers (HSTS, CSP, X-Frame-Options)
- **Compliance**: SLA adherence based on response time thresholds

---

## 🔐 Authentication & Setup

### Azure API Management
Requires Azure PowerShell modules:
```powershell
Install-Module Az.ApiManagement -Force
Install-Module Az.Monitor -Force

# Authenticate
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"
```

Requires Azure RBAC permissions:
- **Reader** role on API Management service
- **Monitoring Reader** for metrics access

### API Health Testing
No special authentication required for basic endpoint testing. For authenticated APIs, provide credentials in the endpoints JSON file:

```json
{
  "Name": "Protected API",
  "Url": "https://api.example.com/protected",
  "Method": "GET",
  "Headers": {
    "Authorization": "Bearer your-token-here",
    "X-API-Key": "your-api-key"
  }
}
```

---

## 📈 Health Status Definitions

### Azure APIM Health Status
| Status | Success Rate | Description |
|--------|--------------|-------------|
| **Excellent** | ≥ 99% | Service performing optimally |
| **Good** | 95-98.9% | Service healthy with minor issues |
| **Fair** | 90-94.9% | Service degraded, attention needed |
| **Poor** | < 90% | Service critical, immediate action required |

### API Endpoint Health
| Result | Criteria | Description |
|--------|----------|-------------|
| **Passed** | Status code matches expected, response time within threshold | Endpoint healthy |
| **Failed** | Status code mismatch or request failed | Endpoint unhealthy |
| **Warning** | Slow response time or SSL cert expiring soon | Endpoint degraded |

---

## 🛠️ Troubleshooting

### Azure APIM Module Not Found
```
Error: Az.ApiManagement module is required
```
**Solution:**
```powershell
Install-Module Az.ApiManagement -Force -AllowClobber
Install-Module Az.Monitor -Force -AllowClobber
```

### Azure Authentication Failed
```
Error: Not logged in to Azure
```
**Solution:**
```powershell
Connect-AzAccount
# Or for service principal
Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant "tenant-id"
```

### API Endpoint Timeout
```
Error: Request failed: The operation has timed out
```
**Solution:** Increase timeout or check network connectivity:
```powershell
# Endpoint configuration allows up to 30 second timeout
# Check network access to API endpoint
Test-NetConnection -ComputerName api.example.com -Port 443
```

### SSL Certificate Validation Fails
```
Error: SSL validation failed: The remote certificate is invalid
```
**Solution:** This may indicate an actual SSL problem. Investigate certificate:
- Check expiration date
- Verify certificate chain
- Ensure certificate matches domain
- Check for self-signed certificates in non-production environments

---

## 🔄 Integration Examples

### Scheduled Azure APIM Reports
```powershell
# Schedule daily reports via Task Scheduler
$trigger = New-ScheduledTaskTrigger -Daily -At 9am
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument @"
-File C:\Scripts\Monitor-AzureAPIManagement.ps1 -SubscriptionId 'sub-id' -ResourceGroupName 'rg-apim' -ServiceName 'prod-apim' -IncludeAPIDetails -IncludeBackendHealth
"@

Register-ScheduledTask -TaskName "Daily APIM Health Report" -Trigger $trigger -Action $action
```

### Alert on API Failures
```powershell
# Test APIs and send alert if failures detected
$results = .\Test-APIHealth.ps1 -EndpointsFile ".\critical-apis.json" -OutputFormat JSON
$data = Get-Content $results | ConvertFrom-Json

if ($data.Summary.FailedTests -gt 0) {
    Send-MailMessage -To "ops-team@company.com" `
        -Subject "⚠️ API Health Check Failed" `
        -Body "Failed endpoints: $($data.Summary.FailedTests)" `
        -SmtpServer "smtp.company.com"
}
```

### Push Metrics to Monitoring System
```powershell
# Export metrics for ingestion by monitoring platforms
.\Monitor-AzureAPIManagement.ps1 -SubscriptionId "sub-id" `
    -ResourceGroupName "rg-apim" `
    -ServiceName "prod-apim" `
    -OutputFormat JSON `
    -OutputPath "C:\Monitoring"

# Push to Prometheus, Grafana, Datadog, etc.
$metrics = Get-Content ".\Azure-APIM-Health-*.json" | ConvertFrom-Json
# Send to your monitoring platform's API
```

---

## 📚 Additional Resources

- [Azure API Management Documentation](https://learn.microsoft.com/en-us/azure/api-management/)
- [Azure APIM REST API Reference](https://learn.microsoft.com/en-us/rest/api/apimanagement/)
- [API Design Best Practices](https://learn.microsoft.com/en-us/azure/architecture/best-practices/api-design)
- [RESTful API Guidelines](https://github.com/microsoft/api-guidelines)

---

## ⚠️ Testing Notice

**IMPORTANT:** These scripts have not been thoroughly tested in all environments. Before using in production:

1. **Test with non-critical APIs first**
2. **Validate metric accuracy against Azure Portal**
3. **Review authentication and permission requirements**
4. **Test alert thresholds in staging environment**
5. **Verify API request limits won't be exceeded**

---

## 🔧 Requirements

- **PowerShell**: 5.1 or later (PowerShell 7+ recommended)
- **Azure Modules**: Az.ApiManagement, Az.Monitor (for Azure APIM monitoring)
- **Network Access**: Outbound HTTPS to API endpoints
- **Permissions**: Azure Reader role for APIM monitoring

---

*Generated: 2025-12-27*
