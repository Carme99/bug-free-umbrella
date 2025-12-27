# Infrastructure as Code (IaC) Validation Scripts

> **⚠️ IMPORTANT NOTICE**: The vast majority of scripts in this repository have not been thoroughly tested in production environments. Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.

This category contains validation and testing scripts for Infrastructure as Code templates and configurations including Azure Bicep and Terraform.

## 📋 Available Scripts

### 1. Test-BicepTemplates.ps1
Validates Azure Bicep templates for syntax, security, and best practices.

**Features:**
- Syntax validation and compilation
- Security vulnerability scanning
- Best practice analysis
- Parameter validation
- What-if deployment analysis
- Hardcoded secret detection
- Resource naming convention checks

**Example:**
```powershell
# Basic validation
.\Test-BicepTemplates.ps1 -TemplatePath ".\main.bicep"

# With what-if analysis
Connect-AzAccount
.\Test-BicepTemplates.ps1 -TemplatePath ".\templates" `
    -IncludeWhatIf `
    -SubscriptionId "sub-id" `
    -ResourceGroupName "rg-test" `
    -ParameterFile ".\parameters.json"
```

---

### 2. Test-TerraformConfiguration.ps1
Validates Terraform configurations for correctness and security.

**Features:**
- terraform init, validate, and fmt checking
- Plan generation and analysis
- Security scanning with tfsec
- Provider version compatibility
- Resource change impact analysis
- Configuration drift detection support

**Example:**
```powershell
# Basic validation
.\Test-TerraformConfiguration.ps1 -ConfigPath ".\terraform"

# Full validation with security scan
.\Test-TerraformConfiguration.ps1 -ConfigPath ".\infrastructure" `
    -IncludePlan `
    -IncludeSecurityScan `
    -OutputFormat HTML
```

---

## 🎯 Common Use Cases

### Pre-Deployment Validation
```powershell
# Validate Bicep before deployment
.\Test-BicepTemplates.ps1 -TemplatePath ".\main.bicep" -OutputFormat Console

# Validate Terraform before apply
.\Test-TerraformConfiguration.ps1 -ConfigPath ".\terraform" -IncludePlan
```

### CI/CD Pipeline Integration
```powershell
# Bicep validation in pipeline
.\Test-BicepTemplates.ps1 -TemplatePath ".\templates" -OutputFormat JSON
if ($LASTEXITCODE -ne 0) { exit 1 }

# Terraform validation in pipeline
.\Test-TerraformConfiguration.ps1 -ConfigPath ".\terraform" -OutputFormat JSON
if ($LASTEXITCODE -ne 0) { exit 1 }
```

### Security Scanning
```powershell
# Scan Bicep for hardcoded secrets
.\Test-BicepTemplates.ps1 -TemplatePath ".\templates" -OutputFormat HTML

# Scan Terraform with tfsec
.\Test-TerraformConfiguration.ps1 -ConfigPath ".\terraform" `
    -IncludeSecurityScan `
    -OutputFormat HTML
```

---

## 🔧 Requirements

### Bicep Validation
- **PowerShell**: 7.0 or later
- **Bicep CLI**: Install from https://aka.ms/bicep-install
- **Azure CLI**: For what-if analysis
- **Az PowerShell**: For Azure authentication (optional)

Install Bicep:
```bash
# Windows
winget install Microsoft.Bicep

# Linux/macOS
curl -Lo bicep https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64
chmod +x ./bicep
sudo mv ./bicep /usr/local/bin/bicep
```

### Terraform Validation
- **PowerShell**: 5.1 or later
- **Terraform CLI**: Install from https://www.terraform.io/downloads
- **tfsec**: (Optional) For security scanning - https://github.com/aquasecurity/tfsec

Install Terraform:
```bash
# Windows
winget install Hashicorp.Terraform

# Linux/macOS
# Visit https://www.terraform.io/downloads
```

Install tfsec (optional):
```bash
# Windows
winget install tfsec

# Linux
curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

# macOS
brew install tfsec
```

---

## 📊 Validation Checks

### Bicep Template Checks
| Check | Description |
|-------|-------------|
| **Syntax Validation** | Bicep compilation and syntax errors |
| **Hardcoded Secrets** | Detection of passwords, keys in plaintext |
| **Secure Parameters** | Verification of @secure decorator for sensitive params |
| **Location Parameters** | Best practice location parameter presence |
| **Resource Tags** | Tag compliance for governance |
| **Naming Conventions** | Resource naming standard adherence |
| **What-If Analysis** | Preview deployment changes |

### Terraform Configuration Checks
| Check | Description |
|-------|-------------|
| **Init** | terraform init success |
| **Format** | terraform fmt compliance |
| **Validate** | terraform validate configuration correctness |
| **Plan** | terraform plan resource change analysis |
| **Security** | tfsec vulnerability scanning |
| **Provider Versions** | Version constraint validation |

---

## 🛠️ Troubleshooting

### Bicep CLI Not Found
```
Error: Bicep CLI not found
```
**Solution:**
```powershell
# Install Bicep
winget install Microsoft.Bicep
# Or follow: https://aka.ms/bicep-install
```

### Terraform Init Fails
```
Error: terraform init failed
```
**Solution:**
```bash
# Ensure you're in correct directory
cd /path/to/terraform/config

# Initialize manually to see detailed errors
terraform init
```

### tfsec Not Found
```
Warning: tfsec not found
```
**Solution:**
```bash
# Install tfsec
# Windows: winget install tfsec
# Linux: curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
# macOS: brew install tfsec
```

### Azure Authentication for What-If
```
Error: Not logged in to Azure
```
**Solution:**
```powershell
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"
```

---

## 🔄 Integration Examples

### Azure DevOps Pipeline
```yaml
# Bicep validation
- task: PowerShell@2
  displayName: 'Validate Bicep Templates'
  inputs:
    filePath: '$(System.DefaultWorkingDirectory)/Scripts/Test-BicepTemplates.ps1'
    arguments: '-TemplatePath "$(System.DefaultWorkingDirectory)/bicep" -OutputFormat JSON'
    pwsh: true

# Terraform validation
- task: PowerShell@2
  displayName: 'Validate Terraform'
  inputs:
    filePath: '$(System.DefaultWorkingDirectory)/Scripts/Test-TerraformConfiguration.ps1'
    arguments: '-ConfigPath "$(System.DefaultWorkingDirectory)/terraform" -IncludeSecurityScan -OutputFormat JSON'
```

### GitHub Actions
```yaml
- name: Validate Bicep
  run: |
    pwsh -File ./scripts/Test-BicepTemplates.ps1 -TemplatePath ./bicep -OutputFormat JSON

- name: Validate Terraform
  run: |
    pwsh -File ./scripts/Test-TerraformConfiguration.ps1 -ConfigPath ./terraform -IncludePlan -OutputFormat JSON
```

### GitLab CI
```yaml
validate_bicep:
  script:
    - pwsh -File ./scripts/Test-BicepTemplates.ps1 -TemplatePath ./bicep -OutputFormat JSON

validate_terraform:
  script:
    - pwsh -File ./scripts/Test-TerraformConfiguration.ps1 -ConfigPath ./terraform -IncludeSecurityScan -OutputFormat JSON
```

---

## 📚 Additional Resources

- [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Documentation](https://www.terraform.io/docs)
- [tfsec Security Scanner](https://github.com/aquasecurity/tfsec)
- [Azure What-If Deployment](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deploy-what-if)

---

## ⚠️ Testing Notice

**IMPORTANT:** These scripts have not been thoroughly tested in all environments. Before using in production:

1. **Test in non-production environments first**
2. **Validate detection accuracy**
3. **Review false positives**
4. **Understand tool limitations**
5. **Complement with manual code review**

---

*Generated: 2025-12-27*
