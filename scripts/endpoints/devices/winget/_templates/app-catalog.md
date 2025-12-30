# Popular Enterprise Apps for Winget Update Scripts

## Communication & Collaboration
- **Microsoft Teams** - `Microsoft.Teams`
- **Slack** - `SlackTechnologies.Slack`
- **Discord** - `Discord.Discord`

## Compression & File Tools
- **7-Zip** - `7zip.7zip`
- **WinRAR** - `RARLab.WinRAR`
- **Everything** - `voidtools.Everything`

## Media & Viewers
- **VLC Media Player** - `VideoLAN.VLC`
- **Adobe Acrobat Reader DC** - `Adobe.Acrobat.Reader.64-bit` (already have 32/64 bit versions)
- **Foxit Reader** - `Foxit.FoxitReader`
- **IrfanView** - `IrfanSkiljan.IrfanView`

## Development Tools
- **Git** - `Git.Git`
- **Python 3** - `Python.Python.3.12`
- **Node.js LTS** - `OpenJS.NodeJS.LTS`
- **Postman** - `Postman.Postman`
- **Docker Desktop** - `Docker.DockerDesktop`
- **GitHub Desktop** - `GitHub.GitHubDesktop`
- **PowerShell 7** - `Microsoft.PowerShell`

## Security & Password Management
- **Bitwarden** - `Bitwarden.Bitwarden`
- **KeePass** - `KeePassXCTeam.KeePassXC`
- **1Password** - `AgileBits.1Password`

## Productivity Tools
- **LibreOffice** - `TheDocumentFoundation.LibreOffice`
- **Greenshot** - `Greenshot.Greenshot`
- **ShareX** - `ShareX.ShareX`
- **Notion** - `Notion.Notion`

## System Utilities
- **PuTTY** - `PuTTY.PuTTY`
- **FileZilla** - `TimKosse.FileZilla.Client`
- **Microsoft PowerToys** - `Microsoft.PowerToys`
- **TreeSize Free** - `JAMSoftware.TreeSize.Free`
- **Sysinternals Suite** - `Microsoft.Sysinternals.ProcessExplorer`
- **Process Explorer** - `Microsoft.Sysinternals.ProcessExplorer`

## Browsers (Additional)
- **Brave Browser** - `Brave.Brave`
- **Opera** - `Opera.Opera`
- **Vivaldi** - `Vivaldi.Vivaldi`

## Remote Desktop & Access
- **AnyDesk** - `AnyDeskSoftwareGmbH.AnyDesk`
- **Parsec** - `Parsec.Parsec`

## Messaging
- **WhatsApp** - `WhatsApp.WhatsApp`
- **Telegram** - `Telegram.TelegramDesktop`

## Graphics & Design
- **GIMP** - `GIMP.GIMP`
- **Paint.NET** - `dotPDN.PaintDotNet`
- **Inkscape** - `Inkscape.Inkscape`

## Priority List (Top 15 for initial implementation)
1. 7-Zip
2. Microsoft Teams
3. Slack
4. VLC Media Player
5. Git
6. Python 3
7. Node.js LTS
8. PowerShell 7
9. Bitwarden
10. Microsoft PowerToys
11. PuTTY
12. Greenshot
13. Postman
14. GitHub Desktop
15. Everything (search tool)

## Notes
- Some apps may require user context instead of SYSTEM
- Docker Desktop typically requires admin rights and may need special handling
- Password managers should probably use standard (non-force-close) remediation
- Development tools (Git, Python, Node) are safe for force-close in most cases
