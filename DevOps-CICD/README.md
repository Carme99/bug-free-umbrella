# DevOps & CI/CD Monitoring Scripts

> **⚠️ IMPORTANT NOTICE**: The vast majority of scripts in this repository have not been thoroughly tested in production environments. Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.

This category contains comprehensive monitoring and analysis scripts for DevOps and CI/CD platforms including Azure DevOps, GitHub Actions, and GitLab CI.

## 📋 Available Scripts

### 1. Monitor-AzureDevOpsPipelines.ps1
Comprehensive Azure DevOps pipeline health monitoring.

**Features:**
- Pipeline success/failure rate tracking
- Build duration trends and performance analysis
- Failed build identification with detailed error analysis
- Agent pool utilization and health monitoring
- Release pipeline tracking
- Pull request build validation status

**Parameters:**
```powershell
-Organization         # Azure DevOps organization name (required)
-Project              # Project name or '*' for all projects (required)
-PersonalAccessToken  # PAT with Build/Release read permissions (required)
-DaysToAnalyze        # Days of history to analyze (default: 7)
-OutputFormat         # Console, HTML, CSV, or JSON (default: HTML)
-IncludeAgentPools    # Include agent pool health analysis
-IncludeReleases      # Include release pipeline monitoring
```

**Example:**
```powershell
.\Monitor-AzureDevOpsPipelines.ps1 -Organization "mycompany" `
    -Project "MyProject" `
    -PersonalAccessToken $env:AZURE_DEVOPS_PAT `
    -DaysToAnalyze 30 `
    -IncludeAgentPools `
    -IncludeReleases
```

**Requirements:**
- PowerShell 5.1 or later
- Azure DevOps PAT with Build (Read) and Release (Read) permissions
- Network access to dev.azure.com

---

### 2. Monitor-GitHubActions.ps1
GitHub Actions workflow health and performance monitoring.

**Features:**
- Workflow run success/failure rate analysis
- Workflow execution duration trends
- Failed workflow job-level analysis
- Self-hosted runner health monitoring
- Repository deployment status tracking
- Billing and usage metrics (with admin access)

**Parameters:**
```powershell
-Owner           # Repository owner/organization (required)
-Repository      # Repository name or '*' for all repos (required)
-GitHubToken     # GitHub PAT with repo and workflow scopes (required)
-DaysToAnalyze   # Days of history to analyze (default: 7)
-OutputFormat    # Console, HTML, CSV, or JSON (default: HTML)
-IncludeRunners  # Include self-hosted runner analysis
-IncludeBilling  # Include billing metrics (requires admin)
```

**Example:**
```powershell
.\Monitor-GitHubActions.ps1 -Owner "myorg" `
    -Repository "*" `
    -GitHubToken $env:GITHUB_TOKEN `
    -DaysToAnalyze 30 `
    -IncludeRunners
```

**Requirements:**
- PowerShell 5.1 or later
- GitHub Personal Access Token with 'repo' and 'workflow' scopes
- Network access to api.github.com

---

### 3. Monitor-GitLabCI.ps1
GitLab CI/CD pipeline health and performance monitoring.

**Features:**
- Pipeline success/failure rates across projects
- Job-level execution analysis
- GitLab Runner health and availability monitoring
- Pipeline duration trends and bottlenecks
- Deployment frequency and success tracking
- Environment-specific deployment status

**Parameters:**
```powershell
-GitLabUrl            # GitLab instance URL (required)
-ProjectId            # Project ID/path or '*' for all (required)
-PrivateToken         # GitLab PAT with read_api scope (required)
-DaysToAnalyze        # Days of history to analyze (default: 7)
-OutputFormat         # Console, HTML, CSV, or JSON (default: HTML)
-IncludeRunners       # Include runner health analysis
-IncludeDeployments   # Include deployment environment analysis
```

**Example:**
```powershell
.\Monitor-GitLabCI.ps1 -GitLabUrl "https://gitlab.company.com" `
    -ProjectId "mygroup/myproject" `
    -PrivateToken $env:GITLAB_TOKEN `
    -DaysToAnalyze 30 `
    -IncludeRunners `
    -IncludeDeployments
```

**Requirements:**
- PowerShell 5.1 or later
- GitLab Personal Access Token with 'read_api' scope
- Network access to your GitLab instance

---

### 4. Analyze-BuildPerformance.ps1
Build performance trend analysis and regression detection.

**Features:**
- Build duration trend analysis over time
- Identification of slow build stages/jobs
- Build time regression detection
- Performance bottleneck identification
- Parallel vs sequential execution analysis
- Statistical analysis (average, median, P95)

**Parameters:**
```powershell
-Platform              # AzureDevOps, GitHub, or GitLab (required)
-DataSource            # Path to exported build data JSON (required)
-DaysToAnalyze         # Days to include in analysis (default: 30)
-OutputFormat          # Console, HTML, or JSON (default: HTML)
-IdentifyRegressions   # Detect performance regressions
-RegressionThreshold   # Percentage increase to flag (default: 25)
```

**Example:**
```powershell
.\Analyze-BuildPerformance.ps1 -Platform "AzureDevOps" `
    -DataSource ".\exported-builds.json" `
    -DaysToAnalyze 60 `
    -IdentifyRegressions `
    -RegressionThreshold 30
```

**Data Format:**
The script expects JSON data with the following structure:
```json
[
  {
    "BuildId": "12345",
    "StartTime": "2025-01-01T10:00:00Z",
    "DurationMinutes": 15.5,
    "Result": "Success",
    "Branch": "main",
    "Stages": [
      {
        "Name": "Build",
        "DurationMinutes": 8.2
      },
      {
        "Name": "Test",
        "DurationMinutes": 7.3
      }
    ]
  }
]
```

**Requirements:**
- PowerShell 5.1 or later
- Exported build data in JSON format

---

## 🎯 Common Use Cases

### Monitor All Pipelines Across Platform
```powershell
# Azure DevOps - Monitor all projects
.\Monitor-AzureDevOpsPipelines.ps1 -Organization "myorg" -Project "*" -PersonalAccessToken $pat

# GitHub - Monitor all repositories
.\Monitor-GitHubActions.ps1 -Owner "myorg" -Repository "*" -GitHubToken $token

# GitLab - Monitor all projects
.\Monitor-GitLabCI.ps1 -GitLabUrl "https://gitlab.com" -ProjectId "*" -PrivateToken $token
```

### Identify Performance Issues
```powershell
# Export build data first, then analyze
.\Analyze-BuildPerformance.ps1 -Platform "AzureDevOps" `
    -DataSource ".\builds.json" `
    -IdentifyRegressions `
    -RegressionThreshold 20
```

### Generate Executive Reports
```powershell
# Generate HTML reports for stakeholders
.\Monitor-AzureDevOpsPipelines.ps1 -Organization "myorg" `
    -Project "*" `
    -PersonalAccessToken $pat `
    -DaysToAnalyze 90 `
    -OutputFormat HTML `
    -IncludeAgentPools `
    -IncludeReleases
```

### Track Runner/Agent Health
```powershell
# Azure DevOps Agents
.\Monitor-AzureDevOpsPipelines.ps1 -Organization "myorg" -Project "*" -PersonalAccessToken $pat -IncludeAgentPools

# GitHub Runners
.\Monitor-GitHubActions.ps1 -Owner "myorg" -Repository "*" -GitHubToken $token -IncludeRunners

# GitLab Runners
.\Monitor-GitLabCI.ps1 -GitLabUrl "https://gitlab.com" -ProjectId "*" -PrivateToken $token -IncludeRunners
```

---

## 📊 Output Formats

All monitoring scripts support multiple output formats:

### HTML Reports
- Interactive dashboards with charts and trends
- Color-coded health status indicators
- Sortable tables with detailed metrics
- Automatically opens in default browser

### CSV Exports
- Structured data for Excel analysis
- Easy integration with BI tools
- Historical trend tracking

### JSON Output
- Machine-readable format for automation
- Integration with monitoring systems
- API consumption

### Console Output
- Quick health checks
- Command-line friendly
- Real-time feedback

---

## 🔐 Authentication Setup

### Azure DevOps Personal Access Token
1. Navigate to: `https://dev.azure.com/{organization}/_usersSettings/tokens`
2. Click "New Token"
3. Grant: **Build (Read)** and **Release (Read)** permissions
4. Set environment variable: `$env:AZURE_DEVOPS_PAT = "your-token"`

### GitHub Personal Access Token
1. Navigate to: `https://github.com/settings/tokens`
2. Click "Generate new token (classic)"
3. Grant: **repo** and **workflow** scopes
4. Set environment variable: `$env:GITHUB_TOKEN = "your-token"`

### GitLab Personal Access Token
1. Navigate to: `https://gitlab.com/-/profile/personal_access_tokens`
2. Create token with **read_api** scope
3. Set environment variable: `$env:GITLAB_TOKEN = "your-token"`

---

## 📈 Health Status Definitions

All monitoring scripts use consistent health status definitions:

| Status | Success Rate | Description |
|--------|--------------|-------------|
| **Healthy** | ≥ 90% | Pipeline is performing well |
| **Warning** | 70-89% | Pipeline has moderate issues |
| **Critical** | < 70% | Pipeline requires immediate attention |

---

## 🛠️ Troubleshooting

### Authentication Errors
```
Error: 401 Unauthorized
```
**Solution:** Verify your token has correct permissions and hasn't expired.

### Rate Limiting
```
Error: 429 Too Many Requests
```
**Solution:** Reduce query frequency or use pagination. GitHub/GitLab have API rate limits.

### No Data Returned
```
Warning: No recent pipelines found
```
**Solution:** Increase `-DaysToAnalyze` parameter or verify pipelines exist in the time period.

### Agent/Runner Access Denied
```
Failed to analyze agent pools: Access denied
```
**Solution:** Agent pool analysis may require administrator permissions in some platforms.

---

## 🔄 Integration Examples

### Automated Daily Reports
```powershell
# Schedule with Windows Task Scheduler
$trigger = New-ScheduledTaskTrigger -Daily -At 8am
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\Monitor-AzureDevOpsPipelines.ps1 -Organization 'myorg' -Project '*' -PersonalAccessToken $env:AZURE_DEVOPS_PAT"
Register-ScheduledTask -TaskName "Daily Pipeline Report" -Trigger $trigger -Action $action
```

### Send Reports via Email
```powershell
# Generate report and email
.\Monitor-GitHubActions.ps1 -Owner "myorg" -Repository "*" -GitHubToken $token -OutputFormat HTML

$htmlReport = Get-Content ".\GitHub-Actions-Health-*.html" -Raw
Send-MailMessage -To "team@company.com" `
    -Subject "Daily CI/CD Health Report" `
    -Body $htmlReport `
    -BodyAsHtml `
    -SmtpServer "smtp.company.com"
```

### Integration with Monitoring Systems
```powershell
# Export JSON for consumption by monitoring tools
.\Monitor-AzureDevOpsPipelines.ps1 -Organization "myorg" `
    -Project "*" `
    -PersonalAccessToken $pat `
    -OutputFormat JSON `
    -OutputPath "C:\Monitoring\Data"

# Push to monitoring API
$data = Get-Content ".\AzureDevOps-Pipelines-*.json" | ConvertFrom-Json
Invoke-RestMethod -Uri "https://monitoring.company.com/api/cicd" `
    -Method Post `
    -Body ($data | ConvertTo-Json -Depth 10) `
    -ContentType "application/json"
```

---

## 📚 Additional Resources

- [Azure DevOps REST API Documentation](https://learn.microsoft.com/en-us/rest/api/azure/devops/)
- [GitHub REST API Documentation](https://docs.github.com/en/rest)
- [GitLab API Documentation](https://docs.gitlab.com/ee/api/)
- [PowerShell Script Best Practices](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/best-practices-for-cmdlet-development)

---

## ⚠️ Testing Notice

**IMPORTANT:** These scripts have not been thoroughly tested in all environments. Before using in production:

1. **Test in non-production environments first**
2. **Validate output accuracy against known data**
3. **Review and understand authentication requirements**
4. **Check API rate limits for your platform**
5. **Verify token permissions match your security policies**

---

## 🔧 Requirements

- **PowerShell**: 5.1 or later (PowerShell 7+ recommended)
- **Network Access**: Outbound HTTPS to CI/CD platform APIs
- **Permissions**: Read access to build/pipeline data via API tokens
- **Disk Space**: Minimal (HTML reports are typically < 1 MB)

---

## 📝 Version History

- **1.0.0** - Initial release with Azure DevOps, GitHub Actions, and GitLab CI monitoring

---

*Generated: 2025-12-27*
