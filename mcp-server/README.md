# 🌂 Bug-Free Umbrella MCP Server

[![MCP](https://img.shields.io/badge/MCP-Server-8B5CF6?style=for-the-badge)](https://modelcontextprotocol.io)
[![Node](https://img.shields.io/badge/Node-18+-339933?style=for-the-badge&logo=node.js&logoColor=white)](https://nodejs.org)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue?style=for-the-badge)](../LICENSE)

> **AI-native script discovery** — every one of the 357 PowerShell scripts in this repo is now a tool your AI assistant can search, preview, and validate.

## Why MCP?

Bug-Free Umbrella has 357 scripts across 8 domains. Finding the right one by browsing folders is slow. The MCP server puts the entire catalog behind a standard [Model Context Protocol](https://modelcontextprotocol.io) interface so Claude, Cursor, or Windsurf can answer:

- *"Find me Intune compliance scripts"*
- *"Show me the help for Monitor-ServerHealth"*
- *"Is this script well-formed?"*

No copy-paste. No guessing paths.

## Features

| Tool | Description | Input |
|------|-------------|-------|
| `search_scripts` | Fuzzy search by name / synopsis / category | `query` (string), `category`? (domain), `limit`? (1–50, default 10) |
| `get_script` | Full script content (first 200 lines + help block) | `path` (repo-relative) |
| `list_categories` | All 8 domains + subcategories with counts | — |
| `get_script_help` | Comment-based help (`<# ... #>`) | `path` |
| `validate_script` | PSScriptAnalyzer-lite checks (SYNOPSIS, CmdletBinding, ErrorActionPreference) | `path` |

**Bonus:** `catalog://scripts` resource (JSON dump of the whole index) and `find-script` prompt.

## Quick Start

```bash
cd mcp-server
npm install
npm run build
# smoke test — should print indexed count to stderr and wait for MCP messages
node build/index.js
```

## Claude Desktop config

Add to `claude_desktop_config.json` (macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`, Windows: `%APPDATA%\Claude\claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "bug-free-umbrella": {
      "command": "node",
      "args": ["/absolute/path/to/bug-free-umbrella/mcp-server/build/index.js"]
    }
  }
}
```

### Alternatives

**Cursor** — `.cursor/mcp.json` with the same `mcpServers` block.

**Windsurf** — `~/.codeium/windsurf/mcp_config.json`.

Restart the host app after editing the config.

## Example Queries

Once connected, try these in Claude:

- **Discovery:** *"Find scripts for Intune compliance"*
  → Claude calls `search_scripts { query: "Intune compliance" }` and summarises hits.

- **Preview:** *"Get help for Monitor-ServerHealth"*
  → Claude calls `search_scripts { query: "Monitor-ServerHealth" }`, then `get_script_help { path: "scripts/..." }`.

- **Validate:** *"Is scripts/security/hardening/Invoke-SecurityComplianceScan.ps1 well-formed?"*
  → Claude calls `validate_script { path: "..." }`.

- **Browse:** *"List all categories"*
  → Claude calls `list_categories`.

## Verification

With the [MCP Inspector](https://github.com/modelcontextprotocol/inspector):

```bash
npx @modelcontextprotocol/inspector node build/index.js
```

You should see 5 tools, 1 resource (`catalog://scripts`), and 1 prompt (`find-script`) in the inspector UI.

Quick stdio probe (no inspector):

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1.0"}}}' | node build/index.js 2> /tmp/mcp.log
cat /tmp/mcp.log
```

## How It Works

- **Startup:** scans `../scripts/**/*.ps1` (or `../scripts/.catalog/metadata.json` if present), parses `.SYNOPSIS` from the first 50 lines, builds an in-memory index.
- **Search:** fuzzy scoring on name, synopsis, category, and directory.
- **Read:** `get_script` / `get_script_help` resolve repo-relative paths safely (path-traversal guarded) and return content.
- **Validate:** regex checks for `.SYNOPSIS`, `[CmdletBinding()]`, and `$ErrorActionPreference = 'Stop'`.

All logging goes to **stderr** — stdout is reserved for the MCP JSON-RPC transport.

## Development

```bash
npm run dev   # tsx watch — no build needed
npm run build # tsc → build/
```

To add a new tool:

1. Define a `zod` schema in `src/index.ts`.
2. Implement a `handleX` function.
3. Register the tool in the `ListTools` and `CallTool` handlers.
4. Run `npm run build` and test via the inspector.

Catalog refresh: restart the server (it re-scans on startup).

---

*Part of [bug-free-umbrella](https://github.com/Carme99/bug-free-umbrella) · Apache-2.0*
