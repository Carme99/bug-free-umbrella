#!/usr/bin/env node
/**
 * Bug-Free Umbrella MCP Server
 *
 * Exposes 358 PowerShell scripts as MCP tools for AI-native discovery.
 * Transport: stdio. Catalog: filesystem scan with optional metadata.json.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
  ListPromptsRequestSchema,
  GetPromptRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

// ---------------------------------------------------------------------------
// Logging — MUST go to stderr (stdout is MCP transport)
// ---------------------------------------------------------------------------
function log(msg: string): void {
  console.error(`[mcp] ${new Date().toISOString()} ${msg}`);
}

// ---------------------------------------------------------------------------
// Catalog types & helpers
// ---------------------------------------------------------------------------
interface ScriptEntry {
  path: string; // repo-relative e.g. scripts/cloud/azure/core/Monitor-AzureResources.ps1
  name: string; // file basename without extension
  category: string; // first segment under scripts/ e.g. cloud
  subcategory: string; // second segment e.g. azure
  synopsis: string;
  fullRelativeDir: string; // e.g. cloud/azure/core
}

let catalog: ScriptEntry[] = [];
let scriptsRoot = "";

// Resolve repo root: mcp-server is at <repo>/mcp-server, scripts at <repo>/scripts
function resolveScriptsRoot(): string {
  const thisFile = fileURLToPath(import.meta.url);
  // When running via tsx: src/index.ts -> ../../scripts ; when built: build/index.js -> ../scripts -> ../../scripts? handle both.
  // build/index.js lives in <repo>/mcp-server/build/index.js => dirname = build, up 2 = repo root -> scripts
  // src/index.ts lives in <repo>/mcp-server/src/index.ts => dirname = src, up 2 = repo root -> scripts
  const dir = path.dirname(thisFile);
  const candidate1 = path.resolve(dir, "../../scripts");
  const candidate2 = path.resolve(dir, "../scripts");
  // Prefer whichever exists and contains .catalog or .ps1 files
  for (const c of [candidate1, candidate2]) {
    if (fs.existsSync(c)) return c;
  }
  return candidate1;
}

function parseSynopsis(firstLines: string): string {
  // Match .SYNOPSIS block: .SYNOPSIS on its own line, then next non-empty lines until blank or dot-keyword
  const synopsisMatch = firstLines.match(/\.SYNOPSIS\s*\r?\n\s*([^\r\n]+)/i);
  if (synopsisMatch) return synopsisMatch[1].trim();
  // Fallback: look for first comment line that looks descriptive
  const lines = firstLines.split(/\r?\n/);
  for (const l of lines) {
    const t = l.trim().replace(/^#\s*/, "");
    if (t.length > 20 && !t.startsWith("<#") && !t.startsWith(".") && !t.startsWith("#")) {
      return t.slice(0, 120);
    }
  }
  return "No synopsis available";
}

function extractHelpBlock(content: string): string | null {
  // Extract <# ... #> block (comment-based help)
  const match = content.match(/<#([\s\S]*?)#>/);
  return match ? match[1].trim() : null;
}

function scanScriptsRecursively(root: string, relDir = ""): string[] {
  const results: string[] = [];
  const absDir = path.join(root, relDir);
  if (!fs.existsSync(absDir)) return results;
  const entries = fs.readdirSync(absDir, { withFileTypes: true });
  for (const e of entries) {
    const rel = path.join(relDir, e.name);
    if (e.isDirectory()) {
      // skip .catalog and node_modules etc
      if (e.name === ".catalog" || e.name === "node_modules" || e.name.startsWith(".")) continue;
      results.push(...scanScriptsRecursively(root, rel));
    } else if (e.isFile() && e.name.endsWith(".ps1")) {
      results.push(rel);
    }
  }
  return results;
}

function buildCatalog(): void {
  scriptsRoot = resolveScriptsRoot();
  log(`scriptsRoot resolved to ${scriptsRoot}`);

  // Try metadata.json first
  const metadataPath = path.join(scriptsRoot, ".catalog", "metadata.json");
  if (fs.existsSync(metadataPath)) {
    try {
      const raw = fs.readFileSync(metadataPath, "utf-8");
      const data = JSON.parse(raw);
      if (Array.isArray(data.scripts) && data.scripts.length > 0) {
        catalog = data.scripts.map((s: Record<string, string>) => ({
          path: s.path ? `scripts/${s.path}` : s.relativePath ? `scripts/${s.relativePath}` : "",
          name: path.basename(s.path ?? s.relativePath ?? "", ".ps1"),
          category: s.path ? s.path.split("/")[0] ?? "unknown" : "unknown",
          subcategory: s.path ? s.path.split("/")[1] ?? "" : "",
          synopsis: s.synopsis ?? s.description ?? "No synopsis",
          fullRelativeDir: s.path ? path.dirname(s.path) : "",
        }));
        log(`Loaded ${catalog.length} entries from metadata.json`);
        return;
      }
      if (Array.isArray(data) && data.length > 0) {
        // alternate shape: array of entries
        catalog = data.map((s: Record<string, string>) => ({
          path: s.path ? (s.path.startsWith("scripts/") ? s.path : `scripts/${s.path}`) : "",
          name: path.basename(s.path ?? "", ".ps1"),
          category: (s.path ?? "").replace(/^scripts\//, "").split("/")[0] ?? "unknown",
          subcategory: (s.path ?? "").replace(/^scripts\//, "").split("/")[1] ?? "",
          synopsis: s.synopsis ?? "No synopsis",
          fullRelativeDir: s.path ? path.dirname(s.path.replace(/^scripts\//, "")) : "",
        }));
        if (catalog.length > 0) {
          log(`Loaded ${catalog.length} entries from metadata.json (array shape)`);
          return;
        }
      }
    } catch (err) {
      log(`metadata.json parse failed, falling back to fs scan: ${String(err)}`);
    }
  }

  // Fallback: filesystem scan
  const relFiles = scanScriptsRecursively(scriptsRoot);
  log(`Filesystem scan found ${relFiles.length} .ps1 files`);
  const entries: ScriptEntry[] = [];
  for (const rel of relFiles) {
    const absPath = path.join(scriptsRoot, rel);
    let synopsis = "No synopsis available";
    try {
      const content = fs.readFileSync(absPath, "utf-8");
      const first50 = content.split(/\r?\n/).slice(0, 50).join("\n");
      synopsis = parseSynopsis(first50) || synopsis;
    } catch {
      // ignore
    }
    const parts = rel.split(path.sep);
    const category = parts[0] ?? "unknown";
    const subcategory = parts[1] ?? "";
    const repoRelative = path.posix.join("scripts", rel.split(path.sep).join("/"));
    entries.push({
      path: repoRelative,
      name: path.basename(rel, ".ps1"),
      category,
      subcategory,
      synopsis,
      fullRelativeDir: parts.slice(0, -1).join("/"),
    });
  }
  catalog = entries;
  log(`Catalog built: ${catalog.length} scripts indexed`);
}

// ---------------------------------------------------------------------------
// Zod schemas (used for validation inside handlers)
// ---------------------------------------------------------------------------
const SearchScriptsSchema = z.object({
  query: z.string().describe("Search term (fuzzy match on name/synopsis/category)"),
  category: z.string().optional().describe("Filter by top-level domain (automation, cloud, etc.)"),
  limit: z.number().int().min(1).max(50).optional().default(10).describe("Max results (default 10, max 50)"),
});

const GetScriptSchema = z.object({
  path: z.string().describe("Repo-relative script path, e.g. scripts/cloud/azure/core/Monitor-AzureResources.ps1"),
});

const GetScriptHelpSchema = z.object({
  path: z.string().describe("Repo-relative script path"),
});

const ValidateScriptSchema = z.object({
  path: z.string().describe("Repo-relative script path"),
});

// ---------------------------------------------------------------------------
// Tool implementations
// ---------------------------------------------------------------------------
function fuzzyScore(entry: ScriptEntry, q: string): number {
  const lower = q.toLowerCase();
  const name = entry.name.toLowerCase();
  const syn = entry.synopsis.toLowerCase();
  const cat = entry.category.toLowerCase();
  const dir = entry.fullRelativeDir.toLowerCase();
  let score = 0;
  if (name.includes(lower)) score += 10;
  if (name.startsWith(lower)) score += 5;
  if (syn.includes(lower)) score += 5;
  if (cat.includes(lower)) score += 3;
  if (dir.includes(lower)) score += 2;
  // token-wise
  for (const tok of lower.split(/\s+/)) {
    if (!tok) continue;
    if (name.includes(tok)) score += 2;
    if (syn.includes(tok)) score += 1;
  }
  return score;
}

function handleSearchScripts(args: unknown) {
  const parsed = SearchScriptsSchema.parse(args);
  const q = parsed.query.trim();
  const limit = Math.min(parsed.limit ?? 10, 50);
  let filtered = catalog;
  if (parsed.category) {
    filtered = filtered.filter((e) => e.category.toLowerCase() === parsed.category!.toLowerCase());
  }
  if (q) {
    const scored = filtered
      .map((e) => ({ entry: e, score: fuzzyScore(e, q) }))
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, limit)
      .map((x) => x.entry);
    // If no fuzzy hits but query given, fallback to substring
    if (scored.length === 0) {
      const lower = q.toLowerCase();
      return filtered
        .filter(
          (e) =>
            e.name.toLowerCase().includes(lower) ||
            e.synopsis.toLowerCase().includes(lower) ||
            e.path.toLowerCase().includes(lower)
        )
        .slice(0, limit);
    }
    return scored;
  }
  return filtered.slice(0, limit);
}

function handleGetScript(args: unknown) {
  const parsed = GetScriptSchema.parse(args);
  const repoRoot = path.resolve(scriptsRoot, "..");
  const absPath = path.resolve(repoRoot, parsed.path);

  // Security: ensure requested path is inside scripts directory
  if (!absPath.startsWith(scriptsRoot + path.sep) && absPath !== scriptsRoot) {
    throw new Error(`Path traversal detected: ${parsed.path}`);
  }
  if (!fs.existsSync(absPath)) {
    throw new Error(`Script not found: ${parsed.path}`);
  }
  const stat = fs.statSync(absPath);
  if (!stat.isFile()) throw new Error(`Not a file: ${parsed.path}`);
  const content = fs.readFileSync(absPath, "utf-8");
  const lines = content.split(/\r?\n/);
  const preview = lines.slice(0, 200).join("\n");
  const helpBlock = extractHelpBlock(content);
  const synopsis = parseSynopsis(lines.slice(0, 50).join("\n"));
  return {
    path: parsed.path,
    name: path.basename(parsed.path, ".ps1"),
    synopsis,
    lineCount: lines.length,
    helpBlock: helpBlock ? helpBlock.slice(0, 8000) : null,
    preview,
    truncated: lines.length > 200,
    totalLines: lines.length,
  };
}

function handleListCategories() {
  const domainMap = new Map<string, { count: number; subcategories: Map<string, number> }>();
  for (const e of catalog) {
    if (!domainMap.has(e.category)) domainMap.set(e.category, { count: 0, subcategories: new Map() });
    const d = domainMap.get(e.category)!;
    d.count++;
    const sub = e.subcategory || "(root)";
    d.subcategories.set(sub, (d.subcategories.get(sub) ?? 0) + 1);
  }
  const domains = Array.from(domainMap.entries())
    .map(([domain, info]) => ({
      domain,
      count: info.count,
      subcategories: Array.from(info.subcategories.entries())
        .map(([name, count]) => ({ name, count }))
        .sort((a, b) => b.count - a.count),
    }))
    .sort((a, b) => b.count - a.count);
  return {
    totalScripts: catalog.length,
    totalDomains: domains.length,
    domains,
  };
}

function handleGetScriptHelp(args: unknown) {
  const parsed = GetScriptHelpSchema.parse(args);
  const repoRoot = path.resolve(scriptsRoot, "..");
  const absPath = path.resolve(repoRoot, parsed.path);
  if (!absPath.startsWith(scriptsRoot + path.sep) && absPath !== scriptsRoot) throw new Error(`Path traversal detected: ${parsed.path}`);
  if (!fs.existsSync(absPath)) throw new Error(`Script not found: ${parsed.path}`);
  const content = fs.readFileSync(absPath, "utf-8");
  const helpBlock = extractHelpBlock(content);
  if (!helpBlock) {
    return { path: parsed.path, help: null, message: "No comment-based help block (<# ... #>) found." };
  }
  return { path: parsed.path, help: helpBlock };
}

function handleValidateScript(args: unknown) {
  const parsed = ValidateScriptSchema.parse(args);
  const repoRoot = path.resolve(scriptsRoot, "..");
  const absPath = path.resolve(repoRoot, parsed.path);
  if (!absPath.startsWith(scriptsRoot + path.sep) && absPath !== scriptsRoot) throw new Error(`Path traversal detected: ${parsed.path}`);
  if (!fs.existsSync(absPath)) throw new Error(`Script not found: ${parsed.path}`);
  const content = fs.readFileSync(absPath, "utf-8");
  const first50 = content.split(/\r?\n/).slice(0, 50).join("\n");
  const checks = {
    hasSynopsis: /\.SYNOPSIS/i.test(first50) || /\.SYNOPSIS/i.test(content.slice(0, 3000)),
    hasCmdletBinding: /\[CmdletBinding\s*\(/i.test(content),
    hasErrorActionPreference: /ErrorActionPreference\s*=\s*['"]Stop['"]/i.test(content),
    hasCommentHelpBlock: /<#[\s\S]*?#>/i.test(content),
    hasParamBlock: /\bparam\s*\(/i.test(content),
  };
  const issues: string[] = [];
  if (!checks.hasSynopsis) issues.push("Missing .SYNOPSIS in comment-based help (first 50 lines).");
  if (!checks.hasCmdletBinding) issues.push("Missing [CmdletBinding()] attribute.");
  if (!checks.hasErrorActionPreference) issues.push("Missing $ErrorActionPreference = 'Stop' (recommended for try/catch scripts).");
  const passed = issues.length === 0;
  return {
    path: parsed.path,
    passed,
    checks,
    issues,
    summary: passed ? "✅ All basic checks passed." : `⚠️ ${issues.length} check(s) failed.`,
  };
}

// ---------------------------------------------------------------------------
// MCP Server setup
// ---------------------------------------------------------------------------
const server = new Server(
  {
    name: "bug-free-umbrella",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
      resources: {},
      prompts: {},
    },
  }
);

// ListTools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "search_scripts",
        description: "Fuzzy search scripts by name/synopsis/category",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", description: "Search term (fuzzy match on name/synopsis/category)" },
            category: { type: "string", description: "Filter by domain (automation, cloud, collaboration, data, endpoints, infrastructure, security, utilities)" },
            limit: { type: "number", description: "Max results (default 10, max 50)", default: 10, minimum: 1, maximum: 50 },
          },
          required: ["query"],
        },
      },
      {
        name: "get_script",
        description: "Get full script content and help (first 200 lines + help block)",
        inputSchema: {
          type: "object",
          properties: {
            path: { type: "string", description: "Repo-relative script path, e.g. scripts/cloud/azure/core/Monitor-AzureResources.ps1" },
          },
          required: ["path"],
        },
      },
      {
        name: "list_categories",
        description: "List all 8 domains + subcategories with counts",
        inputSchema: {
          type: "object",
          properties: {},
          required: [],
        },
      },
      {
        name: "get_script_help",
        description: "Get comment-based help for script (extracts <# ... #> block)",
        inputSchema: {
          type: "object",
          properties: {
            path: { type: "string", description: "Repo-relative script path" },
          },
          required: ["path"],
        },
      },
      {
        name: "validate_script",
        description: "Basic PSScriptAnalyzer-lite checks (SYNOPSIS, CmdletBinding, ErrorActionPreference)",
        inputSchema: {
          type: "object",
          properties: {
            path: { type: "string", description: "Repo-relative script path" },
          },
          required: ["path"],
        },
      },
    ],
  };
});

// CallTool
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  try {
    let result: unknown;
    switch (name) {
      case "search_scripts":
        result = handleSearchScripts(args ?? {});
        break;
      case "get_script":
        result = handleGetScript(args ?? {});
        break;
      case "list_categories":
        result = handleListCategories();
        break;
      case "get_script_help":
        result = handleGetScriptHelp(args ?? {});
        break;
      case "validate_script":
        result = handleValidateScript(args ?? {});
        break;
      default:
        return {
          content: [{ type: "text", text: `Unknown tool: ${name}` }],
          isError: true,
        };
    }
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    log(`Tool ${name} error: ${message}`);
    // zod validation errors are user errors → isError true
    return {
      content: [{ type: "text", text: `Error: ${message}` }],
      isError: true,
    };
  }
});

// Resources
server.setRequestHandler(ListResourcesRequestSchema, async () => {
  return {
    resources: [
      {
        uri: "catalog://scripts",
        name: "Script Catalog",
        description: "JSON listing of all 358 scripts with path, category, and synopsis",
        mimeType: "application/json",
      },
    ],
  };
});

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const uri = request.params.uri;
  if (uri === "catalog://scripts") {
    return {
      contents: [
        {
          uri,
          mimeType: "application/json",
          text: JSON.stringify(catalog, null, 2),
        },
      ],
    };
  }
  throw new Error(`Resource not found: ${uri}`);
});

// Prompts
server.setRequestHandler(ListPromptsRequestSchema, async () => {
  return {
    prompts: [
      {
        name: "find-script",
        description: "Help the user find the right script for a task",
        arguments: [
          { name: "task", description: "Describe the IT task you need to automate", required: true },
          { name: "domain", description: "Optional domain hint (e.g. intune, azure, security)", required: false },
        ],
      },
    ],
  };
});

server.setRequestHandler(GetPromptRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  if (name === "find-script") {
    const task = (args?.task as string) ?? "unknown task";
    const domain = (args?.domain as string) ?? "";
    return {
      description: "Find a script for the given task",
      messages: [
        {
          role: "user",
          content: {
            type: "text",
            text: `I need a PowerShell script for: "${task}"${domain ? ` (domain hint: ${domain})` : ""}.\n\nUse the bug-free-umbrella MCP tools to help me:\n1. Call search_scripts with a relevant query\n2. Summarise the top 3 matches with path, synopsis, and why they fit\n3. If one looks ideal, call get_script_help to show its help\n4. Advise next steps (prereqs, test in non-prod, etc.)`,
          },
        },
      ],
    };
  }
  throw new Error(`Prompt not found: ${name}`);
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
async function main(): Promise<void> {
  buildCatalog();
  const transport = new StdioServerTransport();
  await server.connect(transport);
  log(`MCP server started — ${catalog.length} scripts indexed, 5 tools registered`);
}

main().catch((err) => {
  console.error(`[mcp] fatal: ${String(err)}`);
  process.exit(1);
});
