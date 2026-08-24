# BugFreeUmbrella

A collection of **539 PowerShell scripts across 8 technology domains** for enterprise IT automation: Intune endpoint management, M365 administration, Windows server operations, security compliance, Azure/AWS cloud, databases, and CI/CD.

<div align="center">

[![PowerShell](https://img.shields.io/badge/PowerShell-7.0+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Windows](https://img.shields.io/badge/Windows-Server_2016+-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://www.microsoft.com/windows-server)
[![Linux](https://img.shields.io/badge/Linux-Compatible-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://github.com/PowerShell/PowerShell)
[![macOS](https://img.shields.io/badge/macOS-Compatible-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/PowerShell/PowerShell)

[![License](https://img.shields.io/github/license/Carme99/bug-free-umbrella?style=for-the-badge)](LICENSE)
[![Stars](https://img.shields.io/github/stars/Carme99/bug-free-umbrella?style=for-the-badge)](https://github.com/Carme99/bug-free-umbrella/stargazers)
[![Issues](https://img.shields.io/github/issues/Carme99/bug-free-umbrella?style=for-the-badge)](https://github.com/Carme99/bug-free-umbrella/issues)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=for-the-badge)](CONTRIBUTING.md)

[![Scripts](https://img.shields.io/badge/Scripts-539-FF6B6B?style=for-the-badge&logo=files&logoColor=white)](docs/Script-Catalog.md)
[![Docs](https://img.shields.io/badge/Full_Documentation-docs%2F-4A9EFF?style=for-the-badge)](docs/README.md)
[![MCP Server](https://img.shields.io/badge/MCP-Server-8B5CF6?style=for-the-badge)](docs/MCP-Server.md)
[![Last Commit](https://img.shields.io/github/last-commit/Carme99/bug-free-umbrella?style=for-the-badge)](https://github.com/Carme99/bug-free-umbrella/commits/main)

**[Documentation](docs/README.md)** · **[Quick Start](docs/Getting-Started.md)** · **[Script Catalog](docs/Script-Catalog.md)** · **[Examples](docs/Script-Examples.md)** · **[Troubleshooting](docs/Troubleshooting.md)**

</div>

---

## Why This Exists

Most enterprise IT teams accumulate the same scripts independently: Intune remediations, compliance scans, server health checks, Exchange hygiene, Azure monitoring. This repository publishes one such collection in full — every script carries complete comment-based help, consistent structure, and Pester test coverage where marked, so you can audit, adapt, and run them instead of writing from scratch.

Development is AI-assisted ([Claude Code](https://github.com/anthropics/claude-code)) with human review on every change. The [v1.0.0 relaunch](CHANGELOG.md) applied a uniform standard to all 539 scripts — see [docs/RELAUNCH-SPEC.md](docs/RELAUNCH-SPEC.md) for the exact contract.

## Quick Start

```powershell
# Clone the repository
git clone https://github.com/Carme99/bug-free-umbrella.git
cd bug-free-umbrella

# Or install the generated module from the PowerShell Gallery
Install-Module BugFreeUmbrella -Scope CurrentUser

# Read a script's help before running it
Get-Help .\scripts\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1 -Detailed

# Run it
.\scripts\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1
```

Prefer copy-paste commands? [docs/RECIPES.md](docs/RECIPES.md) has 80+ task-oriented recipes. Full setup guidance lives in [docs/Getting-Started.md](docs/Getting-Started.md).

## What's Inside

```
BugFreeUmbrella/
├── endpoints/       # 429 — Intune, Winget app updates, proactive remediations
├── infrastructure/  #  42 — Windows servers, Active Directory, networking, IIS
├── collaboration/   #  24 — Exchange Online, Teams, SharePoint, M365 reporting
├── security/        #  16 — CIS/NIST/PCI-DSS/HIPAA/SOC2/ISO27001 scanning, hardening
├── cloud/           #  16 — Azure (incl. AVD), AWS, containers
├── automation/      #   6 — CI/CD pipelines, infrastructure as code
├── data/            #   6 — SQL Server, MySQL, PostgreSQL, API health
└── utilities/       #   5 — general-purpose helpers
```

| Capability | Details |
|-----------|---------|
| **Intune management** | 26 scripts for compliance reporting, device maintenance, and Graph-based administration |
| **Proactive remediations** | 51 detect/remediate pairs ready for Intune Proactive Remediations deployment |
| **Winget app updates** | 35 managed applications (34 full detect/remediate pairs) covering browsers, runtimes, and productivity apps |
| **Security & compliance** | Multi-framework scanning: CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001 |
| **Cloud automation** | Azure resource monitoring and AVD image builds, AWS EC2/S3 management, Kubernetes health checks |
| **Server management** | 32 Windows server scripts for health monitoring, patch reporting, and event log analysis |
| **M365 administration** | Exchange mailbox and permission auditing, Teams and SharePoint reporting |

**[Browse the full catalog](docs/Script-Catalog.md)** · **[Architecture overview](docs/ARCHITECTURE.md)**

## Commonly Used Scripts

| Area | Script | Purpose |
|------|--------|---------|
| Intune | [Get-DeviceComplianceReport.ps1](scripts/endpoints/intune/reporting/) | Compliance status across managed devices |
| Intune | [Find-StaleDevices.ps1](scripts/endpoints/intune/maintenance/) | Identify devices that have not checked in |
| Servers | [Monitor-ServerHealth.ps1](scripts/infrastructure/windows/monitoring/) | Fast health check of Windows servers |
| Security | [Invoke-SecurityComplianceScan.ps1](scripts/security/hardening/) | Multi-framework compliance scanning |
| Cloud | [Monitor-AzureResources.ps1](scripts/cloud/azure/core/) | Azure resource inventory and health |
| Cloud | [Get-KubernetesHealthCheck.ps1](scripts/cloud/containers/) | Kubernetes cluster health |
| Endpoints | [Winget update pairs](scripts/endpoints/devices/winget/) | Automated application updates via winget |

**[See examples with expected output](docs/Script-Examples.md)**

## Scope and Limitations

Read this before production use:

- These scripts are maintained by one developer with AI assistance and validated primarily in lab environments. They are not vendor-supported software.
- **Test in a non-production environment first.** Read the script before running it. Maintain backups and use `-WhatIf` where destructive operations support it.
- Coverage varies by domain: `endpoints/` is the most mature area; smaller domains contain fewer, more focused scripts.
- When you find an issue, [open an issue](https://github.com/Carme99/bug-free-umbrella/issues) — reports with environment details get fixed fastest.

## By the Numbers

| Metric | Count |
|--------|-------|
| Scripts | 539 |
| Technology domains | 8 |
| Catalog subcategories | 94 |
| Proactive remediation pairs | 51 (102 scripts) |
| Winget-managed applications | 35 |
| Documentation pages | 30+ |

## AI Integration: MCP Server

The repository ships an MCP server (`mcp-server/`) that exposes the script catalog as [Model Context Protocol](https://modelcontextprotocol.io) tools — search, preview, and validate scripts directly from Claude Desktop or any MCP client. Setup instructions: [docs/MCP-Server.md](docs/MCP-Server.md).

## Documentation

All documentation is versioned in [`docs/`](docs/README.md) and reviewed in the same PRs as the code it describes:

| Task | Reference |
|------|-----------|
| Get started | [Getting Started](docs/Getting-Started.md) |
| Install prerequisites | [Prerequisites](docs/Prerequisites.md) |
| Find a script | [Script Catalog](docs/Script-Catalog.md) |
| See usage examples | [Script Examples](docs/Script-Examples.md) · [RECIPES](docs/RECIPES.md) |
| Solve a specific problem | [Common Use Cases](docs/Common-Use-Cases.md) |
| Fix something broken | [Troubleshooting](docs/Troubleshooting.md) · [FAQ](docs/FAQ.md) |
| Understand the architecture | [ARCHITECTURE](docs/ARCHITECTURE.md) |
| Contribute or extend | [CONTRIBUTING](CONTRIBUTING.md) · [Custom Development Guide](docs/Custom-Development-Guide.md) · [Relaunch Standards Contract](docs/RELAUNCH-SPEC.md) |

Project policies: [CHANGELOG](CHANGELOG.md) · [SECURITY](SECURITY.md) · [CODE OF CONDUCT](CODE_OF_CONDUCT.md) · [GOVERNANCE](GOVERNANCE.md) · [SUPPORT](SUPPORT.md)

## Contributing

Bug reports, feature requests, and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). New scripts must satisfy the standards contract in [docs/RELAUNCH-SPEC.md](docs/RELAUNCH-SPEC.md) (header/help format, behavior standard, mirrored Pester tests). This is a hobby project; typical response time is one to two weeks.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
