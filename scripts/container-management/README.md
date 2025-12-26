# Container Management Scripts

PowerShell scripts for Docker and Kubernetes container platform management, monitoring, and optimization.

## 📋 Overview

Enterprise-grade container management tools for:
- **Docker**: Container health monitoring, cleanup, and resource management
- **Kubernetes**: Cluster health checks, pod monitoring, and diagnostics
- **Resource Optimization**: Storage cleanup and performance tuning

## 🚀 Scripts

### 1. Get-DockerHealthCheck.ps1

Comprehensive Docker environment health monitoring.

**Features**:
- Docker daemon status verification
- Container health and resource usage (CPU, memory)
- Image inventory and dangling image detection
- Volume usage and orphaned volume identification
- Network configuration analysis
- Docker Compose stack monitoring
- Performance metrics collection

**Usage**:
```powershell
# Basic health check
.\Get-DockerHealthCheck.ps1

# Comprehensive check with all features
.\Get-DockerHealthCheck.ps1 -IncludeImages -IncludeNetworks -ExportHTML

# With vulnerability scanning (requires Docker Scan/Trivy)
.\Get-DockerHealthCheck.ps1 -CheckVulnerabilities -ExportHTML
```

**Requirements**: Docker Desktop or Docker Engine

---

### 2. Optimize-DockerCleanup.ps1

Docker resource cleanup and storage optimization.

**Features**:
- Remove stopped containers
- Clean dangling (untagged) images
- Prune unused volumes
- Clear build cache
- Network cleanup
- Space savings reporting

**Usage**:
```powershell
# Interactive cleanup
.\Optimize-DockerCleanup.ps1 -RemoveStoppedContainers -RemoveDanglingImages

# Full automated cleanup
.\Optimize-DockerCleanup.ps1 -Force

# Custom cleanup
.\Optimize-DockerCleanup.ps1 -RemoveUnusedVolumes -PruneBuildCache
```

**Typical Space Savings**: 5-50 GB depending on usage

---

### 3. Get-KubernetesHealthCheck.ps1

Kubernetes cluster health check and diagnostics.

**Features**:
- Node status and resource utilization
- Pod health across all namespaces
- Deployment and StatefulSet status
- Persistent Volume Claims monitoring
- Service and Ingress configuration
- Cluster events and error analysis
- Resource quotas and limits checking

**Usage**:
```powershell
# All namespaces health check
.\Get-KubernetesHealthCheck.ps1

# Specific namespace with metrics
.\Get-KubernetesHealthCheck.ps1 -Namespace production -IncludeMetrics -ExportHTML

# With event history
.\Get-KubernetesHealthCheck.ps1 -CheckEvents -ExportHTML
```

**Requirements**: kubectl configured and connected to cluster

---

## 📊 Common Workflows

**Daily Docker Monitoring**:
```powershell
.\Get-DockerHealthCheck.ps1 -IncludeImages -ExportHTML
```

**Weekly Cleanup**:
```powershell
.\Optimize-DockerCleanup.ps1 -Force
```

**Kubernetes Production Monitoring**:
```powershell
.\Get-KubernetesHealthCheck.ps1 -Namespace production -IncludeMetrics -CheckEvents -ExportHTML
```

---

## ⚙️ Requirements

| Tool | Version | Purpose |
|------|---------|---------|
| Docker | 20.10+ | Container runtime |
| Kubernetes | 1.20+ | Container orchestration |
| kubectl | Latest | K8s CLI tool |
| PowerShell | 5.1+ | Script execution |

---

**Total Scripts**: 3
**Platforms**: Docker, Kubernetes
