# Automation & DevOps Scripts

CI/CD pipeline monitoring, Infrastructure as Code, and automation.

## Categories

### CI/CD (`cicd/`)
- Azure DevOps pipeline monitoring
- GitHub Actions monitoring
- GitLab CI monitoring
- Build performance analysis

### Infrastructure as Code (`iac/`)
- Terraform configuration testing
- Bicep template validation
- ARM template management

## Common Use Cases

- Monitor CI/CD pipeline health
- Validate IaC templates before deployment
- Track build performance metrics
- Automate infrastructure provisioning
- Test Terraform/Bicep configurations

## Prerequisites

**CI/CD Scripts:**
- PowerShell 7+
- API tokens (Azure DevOps PAT, GitHub token, GitLab token)

**IaC Scripts:**
- Terraform CLI (for Terraform scripts)
- Azure CLI (for Bicep scripts)
- PowerShell 7+

## Quick Start

**Monitor Azure DevOps:**
```powershell
.\cicd\Monitor-AzureDevOpsPipelines.ps1 -Organization "myorg" -Project "myproject"
```

**Test Terraform Configuration:**
```powershell
.\iac\Test-TerraformConfiguration.ps1 -Path "./terraform"
```

**Validate Bicep Templates:**
```powershell
.\iac\Test-BicepTemplates.ps1 -TemplatePath "./bicep/main.bicep"
```

## CI/CD Platform Support

| Platform | Scripts | Authentication |
|----------|---------|----------------|
| **Azure DevOps** | Pipeline monitoring, build analysis | PAT token |
| **GitHub Actions** | Workflow monitoring | GitHub token |
| **GitLab CI** | Pipeline status | GitLab token |

## IaC Tool Support

| Tool | Capabilities | Requirements |
|------|--------------|--------------|
| **Terraform** | Validation, testing | Terraform CLI |
| **Bicep** | Template validation | Azure CLI |
| **ARM** | Template testing | Azure PowerShell |

## Related Domains

- [Cloud](../cloud/) - Cloud infrastructure
- [Infrastructure](../infrastructure/) - On-premises automation

---

**[← Back to Scripts](../)**
