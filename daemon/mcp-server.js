#!/usr/bin/env node
/**
 * CWT MCP Server - Model Context Protocol server for Claude Code
 *
 * Exposes knowledge base and budget tools natively to Claude.
 * Runs via stdio, connects through mcpServers in settings.json.
 *
 * Usage in .claude/settings.json:
 * {
 *   "mcpServers": {
 *     "cwt": {
 *       "command": "node",
 *       "args": ["/path/to/mcp-server.js"],
 *       "env": { "CWT_PROJECT_ROOT": "/path/to/project" }
 *     }
 *   }
 * }
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');

// Project root from env or cwd
const PROJECT_ROOT = process.env.CWT_PROJECT_ROOT || process.cwd();
const GLOBAL_KB = path.join(process.env.HOME, '.cwt', 'knowledge');
const PROJECT_KB = path.join(PROJECT_ROOT, '.cwt', 'knowledge');
const CONFIG_FILE = path.join(PROJECT_ROOT, '.cwt', 'config.json');
const BILLING_CACHE = path.join(PROJECT_ROOT, '.cwt', 'billing-cache.json');

// Worker ID from env
const WORKER_ID = process.env.CLAUDE_WORKER_ID || 'unknown';

// =============================================================================
// KNOWLEDGE BASE FUNCTIONS
// =============================================================================

function listKbFiles(category = null) {
  const files = [];
  const seen = new Set();

  const scanDir = (baseDir) => {
    if (!fs.existsSync(baseDir)) return;

    const categories = category ? [category] : ['patterns', 'guidelines', 'architecture'];
    for (const cat of categories) {
      const catDir = path.join(baseDir, cat);
      if (!fs.existsSync(catDir)) continue;

      for (const file of fs.readdirSync(catDir)) {
        if (!file.endsWith('.md')) continue;
        const id = `${cat}-${file.replace('.md', '')}`;
        if (seen.has(id)) continue;
        seen.add(id);
        files.push({
          id,
          category: cat,
          file: path.join(catDir, file),
          name: file.replace('.md', '')
        });
      }
    }
  };

  // Project first (higher priority), then global
  scanDir(PROJECT_KB);
  scanDir(GLOBAL_KB);

  return files;
}

function parseMarkdownFile(filePath) {
  if (!fs.existsSync(filePath)) return null;

  const content = fs.readFileSync(filePath, 'utf8');
  const result = { frontmatter: {}, content: content, file: filePath };

  if (content.startsWith('---')) {
    const parts = content.split('---');
    if (parts.length >= 3) {
      const fmText = parts[1].trim();
      result.content = parts.slice(2).join('---').trim();

      for (const line of fmText.split('\n')) {
        const colonIdx = line.indexOf(':');
        if (colonIdx > 0) {
          const key = line.substring(0, colonIdx).trim();
          let val = line.substring(colonIdx + 1).trim();

          // Parse arrays [a, b, c]
          if (val.startsWith('[') && val.endsWith(']')) {
            val = val.slice(1, -1).split(',').map(s => s.trim().replace(/['"]/g, ''));
          }
          result.frontmatter[key] = val;
        }
      }
    }
  }

  return result;
}

function kbQuery(query) {
  const queryLower = query.toLowerCase();
  const results = [];

  for (const entry of listKbFiles()) {
    const parsed = parseMarkdownFile(entry.file);
    if (!parsed) continue;

    const title = (parsed.frontmatter.title || entry.name).toLowerCase();
    const keywords = Array.isArray(parsed.frontmatter.keywords)
      ? parsed.frontmatter.keywords.join(' ').toLowerCase()
      : String(parsed.frontmatter.keywords || '').toLowerCase();
    const content = parsed.content.toLowerCase();

    if (title.includes(queryLower) || keywords.includes(queryLower) || content.includes(queryLower)) {
      results.push({
        id: entry.id,
        category: entry.category,
        title: parsed.frontmatter.title || entry.name,
        keywords: parsed.frontmatter.keywords || [],
        snippet: parsed.content.substring(0, 200) + '...'
      });
    }
  }

  return results;
}

function kbList(category = null) {
  const entries = [];

  for (const entry of listKbFiles(category)) {
    const parsed = parseMarkdownFile(entry.file);
    entries.push({
      id: entry.id,
      category: entry.category,
      title: parsed?.frontmatter?.title || entry.name
    });
  }

  return entries;
}

function kbGet(id) {
  // Try to find by id (category-name) or just name
  for (const entry of listKbFiles()) {
    if (entry.id === id || entry.name === id) {
      const parsed = parseMarkdownFile(entry.file);
      if (parsed) {
        return {
          id: entry.id,
          category: entry.category,
          title: parsed.frontmatter.title || entry.name,
          keywords: parsed.frontmatter.keywords || [],
          type: parsed.frontmatter.type || 'unknown',
          content: parsed.content
        };
      }
    }
  }
  return null;
}

// =============================================================================
// BUDGET FUNCTIONS
// =============================================================================

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_FILE)) {
      return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    }
  } catch (e) {}
  return {};
}

function loadBillingCache() {
  try {
    if (fs.existsSync(BILLING_CACHE)) {
      return JSON.parse(fs.readFileSync(BILLING_CACHE, 'utf8'));
    }
  } catch (e) {}
  return { cost: 0, lastUpdate: null };
}

function saveBillingCache(data) {
  try {
    fs.writeFileSync(BILLING_CACHE, JSON.stringify(data, null, 2));
  } catch (e) {}
}

function getBudgetStatus() {
  const config = loadConfig();
  const budget = config.budget || {};
  const billing = loadBillingCache();

  const limit = budget.limit || null;
  const period = budget.period || 'daily';
  const warningThreshold = budget.warning_threshold || 0.8;
  const currentCost = billing.cost || 0;

  const result = {
    enabled: limit !== null,
    limit,
    period,
    currentCost,
    remaining: limit ? Math.max(0, limit - currentCost) : null,
    percentUsed: limit ? (currentCost / limit) * 100 : 0,
    lastUpdate: billing.lastUpdate,
    status: 'ok'
  };

  if (limit) {
    if (currentCost >= limit) {
      result.status = 'exceeded';
    } else if (currentCost >= limit * warningThreshold) {
      result.status = 'warning';
    }
  }

  return result;
}

function updateBudgetCost(cost) {
  const billing = loadBillingCache();
  billing.cost = cost;
  billing.lastUpdate = new Date().toISOString();
  saveBillingCache(billing);
  return getBudgetStatus();
}

// =============================================================================
// MCP PROTOCOL
// =============================================================================

const TOOLS = [
  {
    name: 'kb_query',
    description: 'Search the knowledge base for patterns, guidelines, and architecture decisions. Use this BEFORE asking questions to check if the answer already exists.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Search terms (e.g., "error handling", "git workflow")' }
      },
      required: ['query']
    }
  },
  {
    name: 'kb_list',
    description: 'List all entries in the knowledge base, optionally filtered by category.',
    inputSchema: {
      type: 'object',
      properties: {
        category: { type: 'string', description: 'Filter by category: patterns, guidelines, architecture', enum: ['patterns', 'guidelines', 'architecture'] }
      }
    }
  },
  {
    name: 'kb_get',
    description: 'Get the full content of a specific knowledge base entry.',
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'Entry ID (e.g., "patterns-error-handling" or "error-handling")' }
      },
      required: ['id']
    }
  },
  {
    name: 'budget_status',
    description: 'Check the current budget status including spend, remaining budget, and warnings.',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  },
  {
    name: 'budget_check',
    description: 'Check if a task should proceed based on estimated cost and remaining budget.',
    inputSchema: {
      type: 'object',
      properties: {
        estimated_cost: { type: 'number', description: 'Estimated cost in USD for the task' },
        task_description: { type: 'string', description: 'Brief description of the task' }
      },
      required: ['estimated_cost']
    }
  }
];

function handleToolCall(name, args) {
  switch (name) {
    case 'kb_query':
      return { results: kbQuery(args.query || '') };

    case 'kb_list':
      return { entries: kbList(args.category) };

    case 'kb_get':
      const entry = kbGet(args.id);
      if (entry) return entry;
      return { error: `Entry not found: ${args.id}` };

    case 'budget_status':
      return getBudgetStatus();

    case 'budget_check':
      const status = getBudgetStatus();
      const estimated = args.estimated_cost || 0;
      const canProceed = !status.enabled || (status.remaining >= estimated);

      return {
        can_proceed: canProceed,
        estimated_cost: estimated,
        remaining_budget: status.remaining,
        recommendation: canProceed
          ? 'Proceed with task'
          : `Budget insufficient. Remaining: $${status.remaining?.toFixed(2)}, Estimated: $${estimated.toFixed(2)}. Consider: 1) Simplify task, 2) Request budget increase, 3) Prioritize critical parts only.`
      };

    default:
      return { error: `Unknown tool: ${name}` };
  }
}

// JSON-RPC handling
function sendResponse(id, result) {
  const response = { jsonrpc: '2.0', id, result };
  process.stdout.write(JSON.stringify(response) + '\n');
}

function sendError(id, code, message) {
  const response = { jsonrpc: '2.0', id, error: { code, message } };
  process.stdout.write(JSON.stringify(response) + '\n');
}

function handleRequest(request) {
  const { id, method, params } = request;

  switch (method) {
    case 'initialize':
      sendResponse(id, {
        protocolVersion: '2024-11-05',
        capabilities: {
          tools: {}
        },
        serverInfo: {
          name: 'cwt-mcp',
          version: '1.0.0'
        }
      });
      break;

    case 'notifications/initialized':
      // No response needed for notifications
      break;

    case 'tools/list':
      sendResponse(id, { tools: TOOLS });
      break;

    case 'tools/call':
      try {
        const result = handleToolCall(params.name, params.arguments || {});
        sendResponse(id, { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] });
      } catch (e) {
        sendResponse(id, { content: [{ type: 'text', text: JSON.stringify({ error: e.message }) }], isError: true });
      }
      break;

    default:
      sendError(id, -32601, `Method not found: ${method}`);
  }
}

// Main loop - read JSON-RPC from stdin
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false
});

rl.on('line', (line) => {
  try {
    const request = JSON.parse(line);
    handleRequest(request);
  } catch (e) {
    sendError(null, -32700, 'Parse error');
  }
});

// Log startup to stderr (doesn't interfere with protocol)
process.stderr.write(`[CWT MCP] Started for project: ${PROJECT_ROOT}\n`);
process.stderr.write(`[CWT MCP] Worker: ${WORKER_ID}\n`);
