# Email Services Management Scripts

PowerShell scripts for Microsoft Exchange Server administration, monitoring, and maintenance.

## 📋 Overview

Comprehensive Exchange Server management including:
- **Health Monitoring**: Server, database, and queue monitoring
- **Performance Analysis**: Resource utilization and bottleneck detection
- **Mailbox Management**: Quota monitoring and cleanup
- **Compliance**: Audit logging and retention policies

## 🚀 Scripts

### 1. Get-ExchangeServerHealth.ps1

Comprehensive Exchange Server health assessment.

**Features**:
- Exchange services status monitoring
- Database mount status and health
- Mail queue analysis
- DAG replication monitoring (if applicable)
- Transport service health
- Client connectivity testing
- Performance counter collection

**Usage**:
```powershell
# Basic health check
.\Get-ExchangeServerHealth.ps1

# Full check with databases and queues
.\Get-ExchangeServerHealth.ps1 -CheckDatabaseHealth -CheckMailQueues -ExportHTML
```

**Requirements**: Exchange Management Shell, Exchange Administrator role

---

## ⚙️ Requirements

| Component | Requirement |
|-----------|-------------|
| **Exchange** | 2016, 2019 |
| **PowerShell** | Exchange Management Shell |
| **Roles** | Exchange Administrator |

---

**Total Scripts**: 4 (1 included, 3 more available)
**Versions**: Exchange Server 2016, 2019
