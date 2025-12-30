# Data Management Scripts

Database administration and API management.

## Categories

### Databases (`databases/`)
- SQL Server management and monitoring
- MySQL administration
- PostgreSQL operations
- MongoDB management

### API (`api/`)
- Azure API Management monitoring
- API health checks

## Common Use Cases

- Test database connectivity
- Monitor database performance
- Backup database operations
- API health monitoring
- Database query optimization

## Prerequisites

**Database Scripts:**
```powershell
Install-Module -Name SqlServer  # For SQL Server
```

**Database Drivers:**
- SQL Server: Native client or ODBC driver
- MySQL: MySQL connector
- PostgreSQL: PostgreSQL driver
- MongoDB: MongoDB driver

**API Scripts:**
```powershell
Install-Module -Name Az.ApiManagement
```

## Quick Start

**Test Database Connectivity:**
```powershell
.\databases\Test-DatabaseConnectivity.ps1 -ServerName "sql-server" -Database "mydb"
```

**Monitor SQL Server Performance:**
```powershell
.\databases\Monitor-SQLServerPerformance.ps1 -Server "SQL-PROD-01"
```

**API Health Check:**
```powershell
.\api\Monitor-AzureAPIManagement.ps1
```

## Database Platform Support

| Platform | Versions | Features |
|----------|----------|----------|
| **SQL Server** | 2012+, Azure SQL | Full support on Windows; limited on Linux/macOS |
| **MySQL** | 5.7+, 8.0+ | Full cross-platform support |
| **PostgreSQL** | 10-15+ | Full cross-platform support |
| **MongoDB** | 4.0-7.0+ | Full cross-platform support |

## Related Domains

- [Cloud](../cloud/) - Cloud database services
- [Infrastructure](../infrastructure/) - Database server management
- [Automation](../automation/) - Database automation

---

**[← Back to Scripts](../)**
