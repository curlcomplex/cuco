#!/usr/bin/env node
/**
 * ig — Issue Graph CLI
 * Reads and writes .issues.json directly, no MCP required.
 * 
 * READ COMMANDS:
 *   node scripts/ig/cuco_scripts_ig.cjs active              — open + investigating nodes
 *   node scripts/ig/cuco_scripts_ig.cjs blocked            — blocked nodes with blocker chain
 *   node scripts/ig/cuco_scripts_ig.cjs --next N           — top N priority nodes (next up)
 *   node scripts/ig/cuco_scripts_ig.cjs <id>               — single node detail
 *   node scripts/ig/cuco_scripts_ig.cjs --search <q>       — search title + description
 *   node scripts/ig/cuco_scripts_ig.cjs --recent N         — last N touched nodes
 *   node scripts/ig/cuco_scripts_ig.cjs --type <type>      — filter by node type
 *   node scripts/ig/cuco_scripts_ig.cjs --tag <tag>        — filter by tag
 *   node scripts/ig/cuco_scripts_ig.cjs --stale N          — not updated in N sessions
 *   node scripts/ig/cuco_scripts_ig.cjs --ready            — status=open + ready=true
 *   node scripts/ig/cuco_scripts_ig.cjs --blocks <id>      — what this node blocks
 *   node scripts/ig/cuco_scripts_ig.cjs --blocked-by <id>  — what's blocking this node
 *   node scripts/ig/cuco_scripts_ig.cjs --edges            — all edges
 *   node scripts/ig/cuco_scripts_ig.cjs --stats            — graph statistics
 * 
 * WRITE COMMANDS:
 *   node scripts/ig/cuco_scripts_ig.cjs create <type> <title>  — create new node
 *   node scripts/ig/cuco_scripts_ig.cjs delete <id>            — delete node
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --status <s>       — update status (open|investigating|pending-verify|fixed|blocked|deferred|wontfix)
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --verification <v>  — set verification tag (automated|uat|both); required to transition status=fixed
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --note <text>     — append note
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --title <title>   — update title
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --desc <desc>     — update description
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --tag <tag>       — add tag
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --ready <bool>    — set ready flag
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --doc <path>      — set doc_path
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --type <type>     — change type
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --severity <s>    — set severity
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --category <c>   — set category
 *   node scripts/ig/cuco_scripts_ig.cjs update <id> --priority <n>   — set priority (1-5)
 *   node scripts/ig/cuco_scripts_ig.cjs edge <source> <target> <type> — create edge
 *   node scripts/ig/cuco_scripts_ig.cjs edge --delete <edgeId>        — delete edge
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

// Resolve the *main* worktree's .issues.json regardless of which worktree the
// script is invoked from. `git worktree list --porcelain` always lists the main
// worktree first. Falls back to the legacy __dirname-relative path if git fails
// (script run outside any repo, etc).
function resolveMainIgPath() {
  if (process.env.IG_PATH) return process.env.IG_PATH;
  try {
    const out = execFileSync('git', ['worktree', 'list', '--porcelain'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    const firstLine = out.split('\n').find(l => l.startsWith('worktree '));
    if (firstLine) {
      return path.join(firstLine.replace(/^worktree /, '').trim(), '.issues.json');
    }
  } catch (_) { /* fall through */ }
  return path.join(__dirname, '../../.issues.json');
}

// Detect the current worktree's directory name. Stamped onto every node at
// create-time as `properties.worktree` so the IG records *which* parallel
// experiment a node originated in. Filterable via `--worktree <name>`.
function resolveCurrentWorktreeName() {
  try {
    const top = execFileSync('git', ['rev-parse', '--show-toplevel'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return path.basename(top);
  } catch (_) {
    return 'unknown';
  }
}

const IG_PATH = resolveMainIgPath();
const CURRENT_WORKTREE = resolveCurrentWorktreeName();

// ─── Core load/save ───────────────────────────────────────────────────────────

function loadGraph() {
  const raw = fs.readFileSync(IG_PATH, 'utf8');
  return JSON.parse(raw);
}

// All single-node writes go through saveGraphAtomic now. Multiple worktrees
// can ig-write concurrently against the same file; plain writeFileSync is a
// read-modify-write race. The atomic tempfile+rename also closes K-016.
function saveGraph(graph) {
  saveGraphAtomic(graph);
}

// Atomic variant: write to temp file, fsync, rename. Safe for batch mutations
// where a crash mid-write must not leave .issues.json half-serialised.
function saveGraphAtomic(graph) {
  const tmp = IG_PATH + '.tmp.' + process.pid;
  const fd = fs.openSync(tmp, 'w');
  try {
    fs.writeFileSync(fd, JSON.stringify(graph, null, 2));
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, IG_PATH);
}

// Collect all occurrences of a repeatable flag: --tag a --tag b → ['a', 'b'].
// Returns [] if the flag is absent. Skips malformed trailing flag with no value.
function collectRepeatable(args, flag) {
  const out = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === flag && i + 1 < args.length) out.push(args[i + 1]);
  }
  return out;
}

// Parse a --props <json> or --props-from-file <path> payload into an object.
// Returns null if neither flag is present. Exits on parse error.
function resolvePropsJson(args) {
  const fileIdx = args.indexOf('--props-from-file');
  if (fileIdx !== -1) {
    const p = args[fileIdx + 1];
    if (!p) { console.error('--props-from-file requires a path'); process.exit(1); }
    try {
      return JSON.parse(fs.readFileSync(p, 'utf8'));
    } catch (e) {
      console.error(`Cannot parse ${p}: ${e.message}`);
      process.exit(1);
    }
  }
  const idx = args.indexOf('--props');
  if (idx === -1) return null;
  const raw = args[idx + 1];
  if (!raw) { console.error('--props requires a JSON object'); process.exit(1); }
  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed !== 'object' || Array.isArray(parsed) || parsed === null) {
      console.error('--props must be a JSON object (got: ' + typeof parsed + ')');
      process.exit(1);
    }
    return parsed;
  } catch (e) {
    console.error(`Invalid JSON in --props: ${e.message}`);
    process.exit(1);
  }
}

// Text-field value resolver for write commands.
// Precedence: --<flag>-file <path>  >  --<flag> -  (stdin)  >  --<flag> <value>
// Returns null if the flag is absent in any form. Exits on read errors.
function resolveTextValue(args, flag) {
  const fileFlag = flag + '-file';
  const fileIdx = args.indexOf(fileFlag);
  if (fileIdx !== -1) {
    const p = args[fileIdx + 1];
    if (!p) { console.error(`${fileFlag} requires a path`); process.exit(1); }
    try {
      return fs.readFileSync(p, 'utf8').replace(/\n$/, '');
    } catch (e) {
      console.error(`Cannot read ${p}: ${e.message}`);
      process.exit(1);
    }
  }
  const idx = args.indexOf(flag);
  if (idx === -1) return null;
  const val = args[idx + 1];
  if (val === '-') {
    try {
      return fs.readFileSync(0, 'utf8').replace(/\n$/, '');
    } catch (e) {
      console.error(`Cannot read stdin: ${e.message}`);
      process.exit(1);
    }
  }
  return val != null ? val : null;
}

function nodeById(graph, id) {
  return graph.nodes.find(n => n.id === id);
}

// Explicit type→prefix map for types whose first letter collides with another
// type or whose prefix convention is established by legacy data.
const TYPE_PREFIX = {
  subfeature: 'SF',
  future_feature: 'FF',
  fix: 'X',           // legacy (fix and feature both start with F)
  research: 'RE',     // legacy (research and root-cause both start with R)
  concept: 'CON',     // unproven design hypothesis — distinct from C-cluster legacy
  specification: 'SPEC', // versioned canonical doc — distinct from S/SF prefix collisions
};

function nextId(graph, type) {
  const prefix = TYPE_PREFIX[type] || type.charAt(0).toUpperCase();
  const existing = graph.nodes
    .filter(n => n.id.startsWith(prefix + '-') &&
                 /^\d+$/.test(n.id.split('-')[1] || ''))
    .map(n => parseInt(n.id.split('-')[1]) || 0);
  const max = existing.length ? Math.max(...existing) : 0;
  return `${prefix}-${String(max + 1).padStart(3, '0')}`;
}

// ─── Edge helpers ──────────────────────────────────────────────────────────────

function outgoingEdges(graph, id) {
  return (graph.edges || []).filter(e => e.source === id);
}

function incomingEdges(graph, id) {
  return (graph.edges || []).filter(e => e.target === id);
}

function blocks(graph, id) {
  return outgoingEdges(graph, id)
    .filter(e => e.type === 'blocks')
    .map(e => nodeById(graph, e.target))
    .filter(Boolean);
}

function blockedBy(graph, id) {
  return incomingEdges(graph, id)
    .filter(e => e.type === 'blocks')
    .map(e => nodeById(graph, e.source))
    .filter(Boolean);
}

// ─── Session helpers ───────────────────────────────────────────────────────────

function guessCurrentSession() {
  try {
    const gitLog = require('child_process').execSync(
      'git log --oneline -20 --format="%s" 2>/dev/null || echo ""',
      { cwd: path.join(__dirname, '../..') }
    ).toString();
    const match = gitLog.match(/s(\d+)/);
    if (match) return `s${parseInt(match[1]) + 1}`;
  } catch {}
  return 's327';
}

function getCurrentSession() {
  return parseInt(guessCurrentSession().replace('s', '')) || 327;
}

// ─── Print helpers ───────────────────────────────────────────────────────────────

function pad(str, len) {
  return (str || '—').toString().padEnd(len);
}

function printNode(n, verbose = false, graph) {
  const title = n.title || n.description?.split('\n')[0] || '—';
  const truncated = title.length > 72 ? title.slice(0, 69) + '...' : title;
  console.log(`  ${pad(n.id, 8)} ${pad(n.status || 'open', 12)} ${pad(n.type || 'unknown', 14)} ${truncated}`);
  
  if (verbose) {
    if (n.session) console.log(`    session:   ${n.session}`);
    if (n.updated_at) console.log(`    updated:   ${n.updated_at.split('T')[0]}`);
    if (n.doc_path) console.log(`    doc:       ${n.doc_path}`);
    if (n.properties?.severity) console.log(`    severity:  ${n.properties.severity}`);
    if (n.properties?.category) console.log(`    category:  ${n.properties.category}`);
    if (n.tags?.length) console.log(`    tags:      ${n.tags.join(', ')}`);
    if (n.priority !== undefined) console.log(`    priority:  ${n.priority}`);
    if (n.ready !== undefined) console.log(`    ready:     ${n.ready}`);
    const bb = blockedBy(graph, n.id);
    if (bb.length) console.log(`    blocked by: ${bb.map(b => b.id).join(', ')}`);
    const bs = blocks(graph, n.id);
    if (bs.length) console.log(`    blocks:     ${bs.map(b => b.id).join(', ')}`);
    if (n.properties?.notes?.length) {
      const last = n.properties.notes[n.properties.notes.length - 1];
      console.log(`    last note: ${last.session} — ${last.text.slice(0, 60)}`);
    }
  }
}

// ─── READ COMMANDS ────────────────────────────────────────────────────────────

function cmdActive(graph, args) {
  const nodes = graph.nodes.filter(n => n.status === 'open' || n.status === 'investigating');
  console.log(`\n === ACTIVE (${nodes.length}) ===`);
  if (nodes.length === 0) { console.log('  (none)'); return; }
  for (const n of nodes) printNode(n, false, graph);
}

function cmdBlocked(graph) {
  const blockedIds = new Set((graph.edges || []).filter(e => e.type === 'blocks').map(e => e.target));
  const nodes = graph.nodes.filter(n => blockedIds.has(n.id));
  console.log(`\n === BLOCKED (${nodes.length}) ===`);
  if (nodes.length === 0) { console.log('  (none)'); return; }
  for (const n of nodes) {
    printNode(n, false, graph);
    const blockers = blockedBy(graph, n.id);
    if (blockers.length) {
      console.log(`    → blocked by: ${blockers.map(b => `${b.id} ${b.title?.slice(0, 36)}`).join(' | ')}`);
    }
  }
}

function cmdNext(graph, args) {
  const n = Math.min(parseInt(args[0]) || 5, 20);
  const nodes = graph.nodes
    .filter(n => n.status === 'open' || n.status === 'investigating')
    .sort((a, b) => {
      // Priority 1 first, then by session (recent first), then by id
      const pa = a.priority || 3;
      const pb = b.priority || 3;
      if (pa !== pb) return pa - pb;
      const sa = parseInt((a.session || 's0').replace('s', ''));
      const sb = parseInt((b.session || 's0').replace('s', ''));
      if (sa !== sb) return sb - sa;
      return a.id.localeCompare(b.id);
    })
    .slice(0, n);
  console.log(`\n === NEXT UP (${nodes.length}) ===`);
  if (nodes.length === 0) { console.log('  (none)'); return; }
  for (const node of nodes) printNode(node, true, graph);
}

function cmdDetail(graph, id) {
  const n = nodeById(graph, id);
  if (!n) { console.log(`Node ${id} not found`); return; }
  
  console.log(`\n === ${n.id}: ${n.title || n.description?.split('\n')[0]} ===`);
  console.log(`  status:   ${n.status || 'open'}`);
  if (n.verification) console.log(`  verified: ${n.verification}`);
  console.log(`  type:     ${n.type}`);
  console.log(`  session:  ${n.session || '—'}`);
  console.log(`  updated:  ${n.updated_at ? n.updated_at.split('T')[0] : '—'}`);
  console.log(`  ready:    ${n.ready !== undefined ? n.ready : '—'}`);
  console.log(`  doc:      ${n.doc_path || '—'}`);
  if (n.priority !== undefined) console.log(`  priority: ${n.priority}`);
  if (n.tags?.length) console.log(`  tags:     ${n.tags.join(', ')}`);
  if (n.properties) {
    if (n.properties.severity) console.log(`  severity: ${n.properties.severity}`);
    if (n.properties.category) console.log(`  category: ${n.properties.category}`);
  }
  
  const bb = blockedBy(graph, id);
  if (bb.length) {
    console.log(`\n  Blocked by:`);
    for (const b of bb) console.log(`    ← ${b.id} ${b.title?.slice(0, 60)}`);
  }
  const bs = blocks(graph, id);
  if (bs.length) {
    console.log(`\n  Blocks:`);
    for (const b of bs) console.log(`    → ${b.id} ${b.title?.slice(0, 60)}`);
  }
  
  const outE = outgoingEdges(graph, id);
  const inE = incomingEdges(graph, id);
  if (outE.length) console.log(`\n  Out edges: ${outE.length}`);
  if (inE.length) console.log(`  In edges:  ${inE.length}`);
  
  if (n.properties?.notes?.length) {
    console.log(`\n  Notes (${n.properties.notes.length}):`);
    for (const note of n.properties.notes.slice(-3)) {
      console.log(`    [${note.session}] ${note.text.slice(0, 80)}`);
    }
  }
  
  if (n.description) {
    const firstPara = n.description.split('\n\n')[0];
    console.log(`\n  Description:\n${indent(firstPara, '    ')}`);
  }
}

function cmdSearch(graph, query) {
  if (!query) { console.log('Usage: ig --search <query>'); return; }
  const q = query.toLowerCase();
  const nodes = graph.nodes.filter(n => {
    const text = [n.title, n.description, n.id].join(' ').toLowerCase();
    return text.includes(q);
  });
  console.log(`\n === SEARCH "${query}" (${nodes.length}) ===`);
  if (nodes.length === 0) { console.log('  (none)'); return; }
  for (const n of nodes) printNode(n, false, graph);
}

function cmdRecent(graph, args) {
  const n = Math.min(parseInt(args[0]) || 10, 50);
  const sorted = graph.nodes
    .filter(n => n.session)
    .sort((a, b) => {
      const sa = parseInt((a.session || 's0').replace('s', ''));
      const sb = parseInt((b.session || 's0').replace('s', ''));
      return sb - sa;
    })
    .slice(0, n);
  console.log(`\n === RECENT (${sorted.length}) ===`);
  for (const node of sorted) printNode(node, true, graph);
}

function cmdType(graph, type) {
  if (!type) { console.log('Usage: ig --type <type>'); return; }
  const t = type.toLowerCase();
  const nodes = graph.nodes.filter(n => n.type?.toLowerCase().includes(t));
  console.log(`\n === TYPE="${type}" (${nodes.length}) ===`);
  if (nodes.length === 0) { console.log('  (none)'); return; }
  for (const n of nodes) printNode(n, false, graph);
}

function cmdTag(graph, tag) {
  if (!tag) { console.log('Usage: ig --tag <tag>'); return; }
  const nodes = graph.nodes.filter(n => n.tags?.includes(tag));
  console.log(`\n === TAG="${tag}" (${nodes.length}) ===`);
  if (nodes.length === 0) { console.log('  (none)'); return; }
  for (const n of nodes) printNode(n, false, graph);
}

function cmdReady(graph) {
  const nodes = graph.nodes.filter(n => n.status === 'open' && n.ready === true);
  console.log(`\n === READY (${nodes.length}) ===`);
  if (nodes.length === 0) { console.log('  (none)'); return; }
  for (const n of nodes) printNode(n, false, graph);
}

function cmdWorktree(graph, name) {
  if (!name) { console.log('Usage: ig --worktree <name>'); return; }
  const nodes = graph.nodes.filter(n => n.properties?.worktree === name);
  console.log(`\n === WORKTREE="${name}" (${nodes.length}) ===`);
  if (nodes.length === 0) { console.log('  (none)'); return; }
  for (const n of nodes) printNode(n, false, graph);
}

function cmdStale(graph, args) {
  const sessions = parseInt(args[0]) || 5;
  const current = getCurrentSession();
  const nodes = graph.nodes
    .filter(n => {
      if (!n.session) return false;
      return (current - parseInt(n.session.replace('s', ''))) >= sessions;
    })
    .sort((a, b) => {
      const sa = parseInt((a.session || 's0').replace('s', ''));
      const sb = parseInt((b.session || 's0').replace('s', ''));
      return sa - sb;
    });
  console.log(`\n === STALE >${sessions}s ago (${nodes.length}) ===`);
  if (nodes.length === 0) { console.log('  (none)'); return; }
  for (const n of nodes) printNode(n, true, graph);
}

function cmdBlocks(graph, id) {
  if (!id) { console.log('Usage: ig --blocks <id>'); return; }
  const bs = blocks(graph, id);
  console.log(`\n === ${id} BLOCKS (${bs.length}) ===`);
  if (bs.length === 0) { console.log('  (nothing)'); return; }
  for (const b of bs) printNode(b, false, graph);
}

function cmdBlockedBy(graph, id) {
  if (!id) { console.log('Usage: ig --blocked-by <id>'); return; }
  const bb = blockedBy(graph, id);
  console.log(`\n === BLOCKED BY ${id} (${bb.length}) ===`);
  if (bb.length === 0) { console.log('  (nothing)'); return; }
  for (const b of bb) printNode(b, false, graph);
}

// Children: nodes that are part_of <id> (i.e., <id> is their parent)
// Usage: ig --children <id> [--status <s>] [--type <t>]
function cmdChildren(graph, args) {
  const id = args[0];
  if (!id) { console.log('Usage: ig --children <id> [--status <s>] [--type <t>]'); return; }
  if (!nodeById(graph, id)) { console.log(`Node ${id} not found`); return; }
  const statusFilter = args.includes('--status') ? args[args.indexOf('--status') + 1] : null;
  const typeFilter = args.includes('--type') ? args[args.indexOf('--type') + 1] : null;
  let kids = (graph.edges || [])
    .filter(e => e.type === 'part_of' && e.target === id)
    .map(e => nodeById(graph, e.source))
    .filter(Boolean);
  if (statusFilter) kids = kids.filter(n => n.status === statusFilter);
  if (typeFilter) kids = kids.filter(n => n.type === typeFilter);
  kids.sort((a, b) => (a.priority || 3) - (b.priority || 3) || a.id.localeCompare(b.id));
  console.log(`\n === CHILDREN OF ${id} (${kids.length}) ===`);
  if (kids.length === 0) { console.log('  (none)'); return; }
  for (const k of kids) printNode(k, false, graph);
}

// Parents: nodes that <id> is part_of (i.e., where does this node belong?)
// Usage: ig --parents <id>
function cmdParents(graph, args) {
  const id = args[0];
  if (!id) { console.log('Usage: ig --parents <id>'); return; }
  if (!nodeById(graph, id)) { console.log(`Node ${id} not found`); return; }
  const parents = (graph.edges || [])
    .filter(e => e.type === 'part_of' && e.source === id)
    .map(e => nodeById(graph, e.target))
    .filter(Boolean);
  console.log(`\n === ${id} IS PART_OF (${parents.length}) ===`);
  if (parents.length === 0) { console.log('  (none)'); return; }
  for (const p of parents) printNode(p, false, graph);
}

function cmdEdges(graph, args) {
  const showAll = args.includes('--all');
  const typeFilter = args.find(a => a.startsWith('--type='))?.split('=')[1];
  const sourceFilter = args.find(a => a.startsWith('--source='))?.split('=')[1];
  const targetFilter = args.find(a => a.startsWith('--target='))?.split('=')[1];
  
  let edges = graph.edges || [];
  if (typeFilter) edges = edges.filter(e => e.type === typeFilter);
  if (sourceFilter) edges = edges.filter(e => e.source === sourceFilter);
  if (targetFilter) edges = edges.filter(e => e.target === targetFilter);
  
  console.log(`\n === EDGES (${edges.length}) ===`);
  if (edges.length === 0) { console.log('  (none)'); return; }

  const filtered = !!(typeFilter || sourceFilter || targetFilter);
  const limit = showAll ? 100 : (filtered ? edges.length : 30);
  for (const e of edges.slice(0, limit)) {
    const s = nodeById(graph, e.source);
    const t = nodeById(graph, e.target);
    console.log(`  ${pad(e.id, 10)} ${pad(e.type, 14)} ${s?.id || e.source} → ${t?.id || e.target}`);
  }
  if (edges.length > limit) console.log(`  ... and ${edges.length - limit} more`);
}

function cmdStats(graph) {
  const nodes = graph.nodes;
  const edges = graph.edges || [];
  
  const byType = {};
  const byStatus = {};
  const bySeverity = {};
  nodes.forEach(n => {
    byType[n.type] = (byType[n.type] || 0) + 1;
    byStatus[n.status] = (byStatus[n.status] || 0) + 1;
    if (n.properties?.severity) bySeverity[n.properties.severity] = (bySeverity[n.properties.severity] || 0) + 1;
  });
  
  const blockedCount = new Set(edges.filter(e => e.type === 'blocks').map(e => e.target)).size;
  const edgeTypes = {};
  edges.forEach(e => edgeTypes[e.type] = (edgeTypes[e.type] || 0) + 1);
  
  console.log(`\n === GRAPH STATS ===`);
  console.log(`  Nodes:     ${nodes.length}`);
  console.log(`  Edges:     ${edges.length}`);
  console.log(`  Blocked:   ${blockedCount}`);
  console.log(`\n  By status:`);
  Object.entries(byStatus).sort((a,b) => b[1]-a[1]).forEach(([k,v]) => console.log(`    ${pad(k, 14)} ${v}`));
  console.log(`\n  By type:`);
  Object.entries(byType).sort((a,b) => b[1]-a[1]).forEach(([k,v]) => console.log(`    ${pad(k, 14)} ${v}`));
  if (Object.keys(bySeverity).length) {
    console.log(`\n  By severity:`);
    Object.entries(bySeverity).sort((a,b) => b[1]-a[1]).forEach(([k,v]) => console.log(`    ${pad(k, 14)} ${v}`));
  }
  console.log(`\n  Edge types:`);
  Object.entries(edgeTypes).sort((a,b) => b[1]-a[1]).forEach(([k,v]) => console.log(`    ${pad(k, 14)} ${v}`));
}

// ─── WRITE COMMANDS ───────────────────────────────────────────────────────────

function cmdCreate(graph, args) {
  // ig create <type> <title> [--desc <desc>] [--status <status>] [--tags <tags>]
  const type = args[0];
  const title = args[1];

  if (!type || !title) {
    console.log('Usage: ig create <type> <title> [--desc <d>|--desc-file <p>|--desc -] [--status <s>] [--tags <t>]');
    console.log('  Types: milestone, future_feature, feature, subfeature, bug, task, knowledge, concept, specification');
    return;
  }

  const statusIdx = args.indexOf('--status');
  const tagsIdx = args.indexOf('--tags');
  const priorityIdx = args.indexOf('--priority');
  const readyIdx = args.indexOf('--ready');
  const docIdx = args.indexOf('--doc');

  const description = resolveTextValue(args, '--desc') || '';
  const status = statusIdx !== -1 ? args[statusIdx + 1] : 'open';

  // Tags: comma-list (--tags a,b,c) OR repeatable (--tag a --tag b), merged.
  const commaTags = tagsIdx !== -1 ? args[tagsIdx + 1].split(',').map(t => t.trim()) : [];
  const repeatTags = collectRepeatable(args, '--tag');
  const tagSet = new Set([...commaTags, ...repeatTags].filter(Boolean));
  const tags = [...tagSet];

  const props = resolvePropsJson(args) || {};

  const id = nextId(graph, type);
  const session = guessCurrentSession();
  const ts = new Date().toISOString();

  // Worktree origin tag — caller can override via --props but default is the
  // detected current worktree directory name. Lets queries filter by where a
  // node was filed (e.g. ig --worktree cuco-foo-spike --type bug).
  const propsWithWorktree = { worktree: CURRENT_WORKTREE, ...(props || {}) };

  const node = {
    id,
    type,
    status,
    title,
    description,
    tags,
    session,
    created_at: ts,
    updated_at: ts,
    properties: propsWithWorktree,
  };
  if (priorityIdx !== -1) node.priority = parseInt(args[priorityIdx + 1], 10);
  if (readyIdx !== -1) node.ready = args[readyIdx + 1] === 'yes' || args[readyIdx + 1] === 'true';
  if (docIdx !== -1) node.doc_path = args[docIdx + 1];

  graph.nodes.push(node);
  saveGraph(graph);
  console.log(`  Created ${id}: ${type} "${title}"`);
}

function cmdDelete(graph, id) {
  if (!id) { console.log('Usage: ig delete <id>'); return; }
  const idx = graph.nodes.findIndex(n => n.id === id);
  if (idx === -1) { console.log(`Node ${id} not found`); return; }
  
  // Remove all edges connected to this node
  const beforeEdges = graph.edges.length;
  graph.edges = graph.edges.filter(e => e.source !== id && e.target !== id);
  const removed = beforeEdges - graph.edges.length;
  
  graph.nodes.splice(idx, 1);
  saveGraph(graph);
  console.log(`  Deleted ${id} + ${removed} edge(s)`);
}

function cmdUpdate(graph, args) {
  // ig update <id> [--status <s>] [--note <text>] [--title <t>] [--desc <d>]
  //             [--tag <tag>] [--ready <bool>] [--doc <path>] [--type <type>]
  //             [--severity <s>] [--category <c>] [--priority <n>] [--dry-run]
  // T-065: compare-before-set per field (idempotent), --dry-run preview
  const id = args[0];
  if (!id) { console.log('Usage: ig update <id> [--status <s>] [--note <text>] ...'); return; }

  const n = nodeById(graph, id);
  if (!n) { console.log(`Node ${id} not found`); return; }

  const dryRun = args.includes('--dry-run');
  const session = guessCurrentSession();
  const ts = new Date().toISOString();

  const flags = [
    ['--status', 'status'],
    ['--verification', 'verification'],
    ['--title', 'title'],
    ['--desc', 'description'],
    ['--ready', '_ready'],
    ['--doc', 'doc_path'],
    ['--type', 'type'],
    ['--severity', '_severity'],
    ['--category', '_category'],
    ['--priority', 'priority'],
    ['--note', '_note'],
  ];

  // Guard: status→fixed requires a verification tag on the node (either set
  // in this same update call via --verification, or pre-existing on the node).
  // Rationale: s328 revealed quiet "fixed" on unverified code-change-only edits.
  const statusIdx = args.indexOf('--status');
  if (statusIdx !== -1 && args[statusIdx + 1] === 'fixed') {
    const verIdx = args.indexOf('--verification');
    const incomingVer = verIdx !== -1 ? args[verIdx + 1] : null;
    const resultingVer = incomingVer || n.verification;
    if (!resultingVer) {
      console.log(`  ERROR: ${id} cannot transition to 'fixed' without --verification <automated|uat|both>`);
      console.log(`  Use --status pending-verify for code-landed-but-not-yet-verified changes.`);
      return;
    }
    if (!['automated', 'uat', 'both'].includes(resultingVer)) {
      console.log(`  ERROR: ${id} verification "${resultingVer}" invalid; must be automated | uat | both`);
      return;
    }
  }

  // Fields that accept --X-file <path> or --X - (stdin) in addition to --X <value>
  const TEXT_FIELDS = new Set(['--desc', '--note', '--title']);

  let changed = false;
  const tag = dryRun ? '[DRY-RUN] ' : '';

  // T-066: repeatable --tag a --tag b, handled outside the generic flag loop.
  const tagValues = collectRepeatable(args, '--tag');
  for (const tagVal of tagValues) {
    if (!n.tags) n.tags = [];
    if (!tagVal || n.tags.includes(tagVal)) {
      console.log(`  ${tag}${id}: tag "${tagVal}" already present — no change`);
      continue;
    }
    if (!dryRun) n.tags.push(tagVal);
    console.log(`  ${tag}${id}: tag +"${tagVal}"`);
    changed = true;
  }

  // T-066: --props '{JSON}' merge into n.properties. Shallow merge, keeps existing keys.
  const propsPatch = resolvePropsJson(args);
  if (propsPatch) {
    n.properties = n.properties || {};
    const added = [];
    for (const [k, v] of Object.entries(propsPatch)) {
      if (JSON.stringify(n.properties[k]) === JSON.stringify(v)) continue;
      if (!dryRun) n.properties[k] = v;
      added.push(k);
    }
    if (added.length) {
      console.log(`  ${tag}${id}: props merged: ${added.join(', ')}`);
      changed = true;
    } else {
      console.log(`  ${tag}${id}: props already match — no change`);
    }
  }

  for (const [flag, field] of flags) {
    const presentInline = args.indexOf(flag) !== -1;
    const presentFile = args.indexOf(flag + '-file') !== -1;
    if (!presentInline && !presentFile) continue;
    const rawVal = TEXT_FIELDS.has(flag) ? resolveTextValue(args, flag) : args[args.indexOf(flag) + 1];

    if (field === '_ready') {
      const next = rawVal === 'true' || rawVal === 'yes';
      if (n.ready === next) {
        console.log(`  ${tag}${id}: ready already ${next} — no change`);
        continue;
      }
      if (!dryRun) n.ready = next;
      console.log(`  ${tag}${id}: ready → ${next}`);
      changed = true;
      continue;
    }
    if (field === '_severity' || field === '_category') {
      const prop = field.slice(1); // 'severity' or 'category'
      const cur = n.properties && n.properties[prop];
      if (cur === rawVal) {
        console.log(`  ${tag}${id}: ${prop} already "${rawVal}" — no change`);
        continue;
      }
      if (!dryRun) {
        if (!n.properties) n.properties = {};
        n.properties[prop] = rawVal;
      }
      console.log(`  ${tag}${id}: ${prop} → ${rawVal}`);
      changed = true;
      continue;
    }
    if (field === '_note') {
      // Notes are append-only; never "no change" — they're a log, not a value
      if (!dryRun) {
        if (!n.properties) n.properties = {};
        if (!n.properties.notes) n.properties.notes = [];
        n.properties.notes.push({ at: ts, session, text: rawVal });
        n.session = session;
        n.updated_at = ts;
      }
      console.log(`  ${tag}${id}: note added (${session})`);
      changed = true;
      continue;
    }

    // Scalar fields: status, title, description, doc_path, type, priority
    // Normalise priority to int for comparison since args[] gives a string
    const nextVal = field === 'priority' ? parseInt(rawVal, 10) : rawVal;
    if (n[field] === nextVal) {
      console.log(`  ${tag}${id}: ${field} already "${nextVal}" — no change`);
      continue;
    }
    if (!dryRun) n[field] = nextVal;
    console.log(`  ${tag}${id}: ${field} → ${nextVal}`);
    changed = true;
  }
  
  if (changed) {
    if (!dryRun) {
      n.updated_at = ts;
      if (!n.session) n.session = session;
      saveGraph(graph);
    } else {
      console.log(`  [DRY-RUN] ${id}: no changes written`);
    }
  } else {
    console.log(`  ${tag}${id}: no changes`);
  }
}

function cmdEdge(graph, args) {
  // ig edge <source> <target> <type>
  // ig edge --delete <edgeId>
  const deleteIdx = args.indexOf('--delete');
  if (deleteIdx !== -1) {
    const edgeId = args[deleteIdx + 1];
    const idx = graph.edges.findIndex(e => e.id === edgeId);
    if (idx === -1) { console.log(`Edge ${edgeId} not found`); return; }
    const e = graph.edges[idx];
    graph.edges.splice(idx, 1);
    saveGraph(graph);
    console.log(`  Deleted edge ${edgeId} (${e.source} → ${e.target})`);
    return;
  }
  
  const source = args[0];
  const target = args[1];
  const type = args[2] || 'relates_to';
  
  if (!source || !target) {
    console.log('Usage: ig edge <source> <target> [type]');
    console.log('  Types: blocks, relates_to, part_of, causes, affects, same_root_cause, subsumes, revealed_by');
    return;
  }
  
  const sNode = nodeById(graph, source);
  const tNode = nodeById(graph, target);
  if (!sNode) { console.log(`Source node ${source} not found`); return; }
  if (!tNode) { console.log(`Target node ${target} not found`); return; }
  
  // Generate edge ID
  const edgeId = `ie_${Date.now().toString(36)}`;
  graph.edges.push({ id: edgeId, source, target, type, properties: {} });
  saveGraph(graph);
  console.log(`  Edge ${edgeId}: ${source} --${type}--> ${target}`);
}

// ─── BATCH APPLY ─────────────────────────────────────────────────────────────

// Validate a single op against the in-memory graph. Returns error string or null.
// Check a node-ID field that may be a real ID or a $ref to a node
// created earlier in this batch. Returns error string or null.
function checkNodeRef(val, kind, reserved, graph, prefix) {
  if (typeof val !== 'string') return `${prefix}${kind} must be a string`;
  if (val.startsWith('$')) {
    if (!reserved.has(val)) return `${prefix}${kind} ${val} not reserved earlier in batch`;
    return null; // resolved at apply time
  }
  if (!nodeById(graph, val)) return `${prefix}${kind} ${val} not found`;
  return null;
}

function validateOp(graph, op, idx, reserved = new Set()) {
  const prefix = `[${idx}] ${op?.op || '?'}: `;
  if (!op || typeof op !== 'object') return prefix + 'not an object';
  if (!op.op) return prefix + 'missing "op"';
  switch (op.op) {
    case 'create':
      if (!op.type) return prefix + 'missing "type"';
      if (!op.title) return prefix + 'missing "title"';
      if (op._ref != null) {
        if (typeof op._ref !== 'string' || !op._ref.startsWith('$')) {
          return prefix + `_ref must be a string starting with "$" (got ${JSON.stringify(op._ref)})`;
        }
        if (reserved.has(op._ref)) return prefix + `_ref ${op._ref} already reserved earlier in batch`;
      }
      return null;
    case 'update':
    case 'delete': {
      if (!op.id) return prefix + 'missing "id"';
      const idErr = checkNodeRef(op.id, 'node', reserved, graph, prefix);
      if (idErr) return idErr;
      // If id is a $ref, skip status=fixed verification check (the node
      // doesn't exist yet — verification rules re-apply at apply time on
      // the resolved node, which was just created so can't be status=fixed anyway).
      if (op.id.startsWith('$')) return null;
      if (op.op === 'update' && op.status === 'fixed') {
        const n = nodeById(graph, op.id);
        const resultingVer = op.verification || n.verification;
        if (!resultingVer) return prefix + `cannot set status=fixed without "verification" (automated|uat|both). Use status=pending-verify for landed-but-unverified code.`;
        if (!['automated', 'uat', 'both'].includes(resultingVer)) {
          return prefix + `verification "${resultingVer}" invalid; must be automated | uat | both`;
        }
      }
      if (op.op === 'update' && op.verification && !['automated', 'uat', 'both'].includes(op.verification)) {
        return prefix + `verification "${op.verification}" invalid; must be automated | uat | both`;
      }
      return null;
    }
    case 'edge': {
      if (!op.source) {
        if (op.from) return prefix + 'missing "source" — note: edge ops use "source"/"target", not "from"/"to" (those are for reparent ops)';
        return prefix + 'missing "source"';
      }
      if (!op.target) {
        if (op.to) return prefix + 'missing "target" — note: edge ops use "source"/"target", not "from"/"to"';
        return prefix + 'missing "target"';
      }
      const srcErr = checkNodeRef(op.source, 'source', reserved, graph, prefix);
      if (srcErr) return srcErr;
      const tgtErr = checkNodeRef(op.target, 'target', reserved, graph, prefix);
      if (tgtErr) return tgtErr;
      return null;
    }
    case 'edge-delete':
      if (!op.id) return prefix + 'missing "id"';
      if (!(graph.edges || []).find(e => e.id === op.id)) return prefix + `edge ${op.id} not found`;
      return null;
    case 'reparent': {
      if (!op.node) return prefix + 'missing "node"';
      if (!op.from) return prefix + 'missing "from"';
      if (!op.to)   return prefix + 'missing "to"';
      const nErr = checkNodeRef(op.node, 'node', reserved, graph, prefix);
      if (nErr) return nErr;
      const fErr = checkNodeRef(op.from, 'from', reserved, graph, prefix);
      if (fErr) return fErr;
      const tErr = checkNodeRef(op.to,   'to',   reserved, graph, prefix);
      if (tErr) return tErr;
      // Edge-existence check skipped when any end is a $ref (resolved at apply time);
      // applyOp re-checks on resolved IDs and surfaces a clear error there.
      const anyRef = [op.node, op.from, op.to].some(v => typeof v === 'string' && v.startsWith('$'));
      if (!anyRef) {
        const edgeType = op.edge_type || op.type || 'part_of';
        const exists = (graph.edges || []).some(e =>
          e.source === op.node && e.target === op.from && e.type === edgeType);
        if (!exists) return prefix + `no ${edgeType} edge from ${op.node} to ${op.from} to reparent`;
      }
      return null;
    }
    default: {
      // Common wrong variants — suggest the canonical op name. Saves a
      // round-trip when a first-time author copies MCP-style names into a
      // batch payload (where the schema is shorter — `create` not
      // `create_node`, `edge` not `create_edge`).
      const suggestions = {
        create_node: 'create',
        create_edge: 'edge',
        delete_node: 'delete',
        delete_edge: 'edge-delete',
        update_node: 'update',
        node_create: 'create',
        edge_create: 'edge',
      };
      const hint = suggestions[op.op];
      if (hint) {
        return prefix + `unknown op type "${op.op}" — did you mean "${hint}"? `
                      + `(valid ops: create, update, delete, edge, edge-delete, reparent)`;
      }
      return prefix + `unknown op type "${op.op}" `
                    + `(valid ops: create, update, delete, edge, edge-delete, reparent)`;
    }
  }
}

// Mutate graph in-place for one op. Returns {kind, id?, message}.
// Validation must pass first; this does not re-check existence.
function applyOp(graph, op) {
  const session = guessCurrentSession();
  const ts = new Date().toISOString();

  if (op.op === 'create') {
    const id = nextId(graph, op.type);
    const node = {
      id,
      type: op.type,
      status: op.status || 'open',
      title: op.title,
      description: op.description || '',
      tags: Array.isArray(op.tags) ? op.tags : [],
      session,
      created_at: ts,
      updated_at: ts,
      // Worktree origin tag — caller can override via op.properties.
      properties: { worktree: CURRENT_WORKTREE, ...(op.properties || {}) },
    };
    if (op.priority != null) node.priority = op.priority;
    if (op.ready != null) node.ready = !!op.ready;
    if (op.doc_path) node.doc_path = op.doc_path;
    graph.nodes.push(node);
    const titleShort = op.title.length > 50 ? op.title.slice(0, 47) + '...' : op.title;
    const refSuffix = op._ref ? ` [ref: ${op._ref}]` : '';
    return { kind: 'created', id, message: `  + ${id} ${op.type}: ${titleShort}${refSuffix}` };
  }

  if (op.op === 'update') {
    const n = nodeById(graph, op.id);
    const changes = [];
    const scalarFields = ['status', 'verification', 'title', 'description', 'doc_path', 'type', 'priority'];
    for (const f of scalarFields) {
      if (op[f] != null && n[f] !== op[f]) { n[f] = op[f]; changes.push(f); }
    }
    if (op.ready != null) {
      const next = !!op.ready;
      if (n.ready !== next) { n.ready = next; changes.push('ready'); }
    }
    if (op.severity) { n.properties = n.properties || {}; n.properties.severity = op.severity; changes.push('severity'); }
    if (op.category) { n.properties = n.properties || {}; n.properties.category = op.category; changes.push('category'); }
    if (Array.isArray(op.tags_add) && op.tags_add.length) {
      n.tags = n.tags || [];
      let added = 0;
      for (const t of op.tags_add) if (!n.tags.includes(t)) { n.tags.push(t); added++; }
      if (added) changes.push(`tags+${added}`);
    }
    if (op.note) {
      n.properties = n.properties || {};
      n.properties.notes = n.properties.notes || [];
      n.properties.notes.push({ at: ts, session, text: op.note });
      n.session = session;
      changes.push('note');
    }
    n.updated_at = ts;
    return {
      kind: changes.length ? 'updated' : 'noop',
      id: op.id,
      message: changes.length
        ? `  ~ ${op.id}: ${changes.join(',')}`
        : `  · ${op.id}: no change`,
    };
  }

  if (op.op === 'delete') {
    const idx = graph.nodes.findIndex(n => n.id === op.id);
    graph.nodes.splice(idx, 1);
    const before = graph.edges.length;
    graph.edges = graph.edges.filter(e => e.source !== op.id && e.target !== op.id);
    const removed = before - graph.edges.length;
    return { kind: 'deleted', id: op.id, message: `  - ${op.id} (+ ${removed} edges)` };
  }

  if (op.op === 'edge') {
    const edgeType = op.edge_type || op.type || 'relates_to';
    const edgeId = `ie_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
    graph.edges.push({ id: edgeId, source: op.source, target: op.target, type: edgeType, properties: {} });
    return { kind: 'edge-created', id: edgeId, message: `  + ${edgeId}: ${op.source} --${edgeType}--> ${op.target}` };
  }

  if (op.op === 'edge-delete') {
    const idx = graph.edges.findIndex(e => e.id === op.id);
    const e = graph.edges[idx];
    graph.edges.splice(idx, 1);
    return { kind: 'edge-deleted', id: op.id, message: `  - ${op.id} (${e.source} → ${e.target})` };
  }

  if (op.op === 'reparent') {
    const edgeType = op.edge_type || op.type || 'part_of';
    const idx = graph.edges.findIndex(e =>
      e.source === op.node && e.target === op.from && e.type === edgeType);
    if (idx === -1) {
      throw new Error(`reparent: no ${edgeType} edge from ${op.node} to ${op.from} (validator should have caught)`);
    }
    const oldEdgeId = graph.edges[idx].id;
    graph.edges.splice(idx, 1);
    const edgeId = `ie_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
    graph.edges.push({ id: edgeId, source: op.node, target: op.to, type: edgeType, properties: {} });
    return {
      kind: 'reparented',
      id: edgeId,
      message: `  ↺ ${op.node} ${edgeType}: ${op.from} → ${op.to} (was ${oldEdgeId}, now ${edgeId})`,
    };
  }

  throw new Error('unreachable: validateOp should reject unknown op types');
}

// Core apply pipeline — validates all ops, applies in-memory, saves atomically.
// Shared by cmdApply (file-loader) and cmdHygiene (ops generated from graph state).
// Returns the results array for callers that need structured output.
function applyOps(graph, ops, opts = {}) {
  const { dryRun = false, label = 'apply' } = opts;

  if (!Array.isArray(ops)) {
    console.error('Ops payload must be a JSON array');
    process.exit(1);
  }

  // Validation pass — track $refs declared by create ops so subsequent ops
  // can reference them. Forward-only: a ref must be declared before it's used.
  const reserved = new Set();
  const errors = [];
  for (let i = 0; i < ops.length; i++) {
    const err = validateOp(graph, ops[i], i, reserved);
    if (err) { errors.push(err); continue; }
    // Reserve after successful validation so failed create ops don't poison later refs
    if (ops[i].op === 'create' && ops[i]._ref) reserved.add(ops[i]._ref);
  }
  if (errors.length) {
    console.error(`Validation failed (${errors.length} error${errors.length === 1 ? '' : 's'}):`);
    for (const e of errors) console.error('  ' + e);
    process.exit(1);
  }

  // Apply pass — resolve $refs to real IDs as create ops assign them.
  const resolved = {};
  const resolveField = (val) => {
    if (typeof val === 'string' && val.startsWith('$')) {
      const id = resolved[val];
      if (!id) throw new Error(`internal: unresolved $ref ${val} reached apply (validator bug)`);
      return id;
    }
    return val;
  };
  const results = [];
  for (const op of ops) {
    const r = { ...op };
    if (r.source) r.source = resolveField(r.source);
    if (r.target) r.target = resolveField(r.target);
    if (r.id) r.id = resolveField(r.id);
    const result = applyOp(graph, r);
    if (op.op === 'create' && op._ref) resolved[op._ref] = result.id;
    results.push(result);
  }

  const counts = {};
  for (const r of results) counts[r.kind] = (counts[r.kind] || 0) + 1;

  console.log((dryRun ? '[DRY-RUN] ' : '') + `${label}: ${ops.length} op${ops.length === 1 ? '' : 's'}`);
  for (const r of results) console.log(r.message);
  const summary = Object.entries(counts).map(([k, v]) => `${v} ${k}`).join(', ');
  console.log(`Summary: ${summary || 'nothing'}`);

  if (dryRun) {
    console.log('[DRY-RUN] No changes written.');
    return results;
  }

  saveGraphAtomic(graph);
  return results;
}

function cmdApply(graph, args) {
  const fileArg = args[0];
  const dryRun = args.includes('--dry-run');
  if (!fileArg) {
    console.log('Usage: ig apply <file|-> [--dry-run]');
    console.log('  Ops: create, update, delete, edge, edge-delete, reparent');
    return;
  }

  let raw;
  try {
    raw = fileArg === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(fileArg, 'utf8');
  } catch (e) {
    console.error(`Cannot read ${fileArg}: ${e.message}`);
    process.exit(1);
  }

  let ops;
  try {
    ops = JSON.parse(raw);
  } catch (e) {
    console.error(`Invalid JSON in ${fileArg}: ${e.message}`);
    process.exit(1);
  }

  applyOps(graph, ops, { dryRun, label: 'apply' });
}

// T-064: generate-and-apply hygiene sweep. Codifies K-001 rule as tooling.
function cmdHygiene(graph, args) {
  const shouldApply = args.includes('--apply');
  const ops = [];

  // 1. Stale blocks: edges of type=blocks where source.status === 'fixed'
  for (const e of graph.edges) {
    if (e.type !== 'blocks') continue;
    const src = nodeById(graph, e.source);
    if (src && src.status === 'fixed') {
      ops.push({ op: 'edge-delete', id: e.id });
    }
  }

  // 2. Duplicate edges: same source+target+type, keep first seen.
  const seen = new Set();
  const alreadyTargeted = new Set(ops.map(o => o.id));
  for (const e of graph.edges) {
    if (alreadyTargeted.has(e.id)) continue;
    const key = `${e.source}|${e.target}|${e.type}`;
    if (seen.has(key)) {
      ops.push({ op: 'edge-delete', id: e.id });
    } else {
      seen.add(key);
    }
  }

  if (ops.length) {
    if (!shouldApply) {
      console.log(`  ${ops.length} edge${ops.length === 1 ? '' : 's'} to sweep (run with --apply to mutate):`);
      applyOps(graph, ops, { dryRun: true, label: 'hygiene' });
    } else {
      applyOps(graph, ops, { dryRun: false, label: 'hygiene' });
    }
  } else {
    console.log('  No sweepable edge hygiene actions (no stale blocks, no duplicates).');
  }

  // Orphan report — report-only, can't auto-fix (needs judgment on which feature to attach).
  // Nodes that structurally require part_of: subfeature/bug/task/future_feature.
  // Exclude closed states (fixed/obsolete/wontfix) — historical records don't need edges.
  const needsParent = new Set(['subfeature', 'bug', 'task', 'future_feature']);
  const closedStates = new Set(['fixed', 'obsolete', 'wontfix']);
  const standalone = [];
  const orphans = graph.nodes.filter(n => {
    if (!needsParent.has(n.type)) return false;
    if (closedStates.has(n.status)) return false;
    const hasPartOf = (graph.edges || []).some(e => e.source === n.id && e.type === 'part_of');
    if (hasPartOf) return false;
    if (n.properties && n.properties.standalone === true) {
      standalone.push(n);
      return false;
    }
    return true;
  });

  if (orphans.length) {
    console.log('');
    console.log(`  Orphan nodes — no part_of edge, needs feature/milestone parent (${orphans.length}):`);
    for (const n of orphans.slice(0, 20)) {
      const title = (n.title || '').slice(0, 70);
      console.log(`    ${n.id.padEnd(8)} [${(n.type || '').padEnd(15)} ${(n.status || '').padEnd(13)}] ${title}`);
    }
    if (orphans.length > 20) console.log(`    ... +${orphans.length - 20} more`);
    console.log('');
    console.log('  Fix via: node scripts/ig/cuco_scripts_ig.cjs edge <orphan-id> <feature-id> part_of');
    console.log('  Or mark intentional-standalone: node scripts/ig/cuco_scripts_ig.cjs update <id> --props \'{"standalone":true}\'');
  } else {
    console.log('  No orphan nodes.');
  }
  if (standalone.length) {
    console.log(`  (${standalone.length} intentional-standalone node${standalone.length === 1 ? '' : 's'} excluded: ${standalone.map(n => n.id).join(', ')})`);
  }

  // ID-prefix vs node-type mismatches — historical from migrations.
  // Report-only: ID rename is destructive (breaks git/external references) so the fix
  // approach is undefined. Surfacing the count is enough to keep it visible.
  const expectedTypeFromPrefix = {
    F: 'feature', B: 'bug', SF: 'subfeature', FF: 'future_feature',
    T: 'task', M: 'milestone', K: 'knowledge', CON: 'concept',
    SPEC: 'specification',
  };
  const idMismatches = [];
  for (const n of graph.nodes) {
    const m = n.id.match(/^([A-Z]+)-/);
    if (!m) continue;
    const exp = expectedTypeFromPrefix[m[1]];
    if (exp && exp !== n.type) {
      idMismatches.push({ id: n.id, prefix: m[1], actual: n.type, title: n.title || '' });
    }
  }
  if (idMismatches.length) {
    console.log('');
    console.log(`  ID-prefix vs node-type mismatches (${idMismatches.length}) — historical from migrations:`);
    for (const x of idMismatches.slice(0, 20)) {
      console.log(`    ${x.id.padEnd(8)}  prefix=${x.prefix.padEnd(3)}  actual=${x.actual.padEnd(15)}  ${x.title.slice(0, 60)}`);
    }
    if (idMismatches.length > 20) console.log(`    ... +${idMismatches.length - 20} more`);
  }

  // Stub descriptions on open nodes — surfaces nodes that need elaboration.
  // Closed nodes excluded (historical record, fluff doesn't help).
  const closedForStubs = new Set(['fixed', 'obsolete', 'wontfix', 'closed', 'dropped']);
  const stubs = graph.nodes.filter(n => {
    if (closedForStubs.has(n.status)) return false;
    return !n.description || n.description.trim().length < 80;
  });
  if (stubs.length) {
    console.log('');
    console.log(`  Stub descriptions on open nodes (<80 chars) (${stubs.length}):`);
    for (const n of stubs.slice(0, 20)) {
      const len = (n.description || '').length;
      console.log(`    ${n.id.padEnd(8)} [${(n.type || '').padEnd(15)}] ${(n.title || '').slice(0, 50).padEnd(50)}  ${String(len).padStart(3)} chars`);
    }
    if (stubs.length > 20) console.log(`    ... +${stubs.length - 20} more`);
  }
}

// ─── Utilities ────────────────────────────────────────────────────────────────

function indent(text, prefix) {
  return text.split('\n').map(l => prefix + l).join('\n');
}

// ─── DISPLAY COMMANDS ─────────────────────────────────────────────────────────

function cmdBoard(graph) {
  const COLS = 5;
  const STATUSES = ['blocked', 'open', 'investigating', 'pending-verify', 'fixed', 'deferred'];
  
  const byStatus = {};
  STATUSES.forEach(s => byStatus[s] = []);
  graph.nodes.forEach(n => {
    const s = n.status || 'open';
    if (byStatus[s]) byStatus[s].push(n);
    else byStatus.open.push(n);
  });
  
  STATUSES.forEach(s => {
    byStatus[s].sort((a, b) => {
      const pa = a.priority || 3, pb = b.priority || 3;
      if (pa !== pb) return pa - pb;
      const sa = parseInt((a.session||'s0').slice(1)) || 0;
      const sb = parseInt((b.session||'s0').slice(1)) || 0;
      return sb - sa;
    });
  });
  
  const cw = 26;
  const W = COLS * (cw + 2) + 1;
  const sep = '─'.repeat(W);
  
  console.log('\n' + '═'.repeat(W));
  console.log(' ISSUE BOARD '.padStart(Math.floor((W + 12) / 2)).padEnd(W));
  console.log('═'.repeat(W));
  
  STATUSES.forEach(s => {
    const cnt = byStatus[s].length;
    process.stdout.write(`│ ${s.toUpperCase().padEnd(cw)} `);
  });
  console.log('│');
  console.log(sep);
  
  const maxRows = Math.min(Math.max(...STATUSES.map(s => byStatus[s].length)), 20);
  for (let r = 0; r < maxRows; r++) {
    STATUSES.forEach(s => {
      const n = byStatus[s][r];
      if (n) {
        const p = n.priority || 3;
        const id = n.id.replace(/^(B-|F-|K-|T-|I-|R-|M-|X-|C-|RE-)/, '');
        const title = (n.title || '—').substring(0, 17);
        const line = `[${p}]${id.padEnd(7)} ${title}`.substring(0, cw);
        process.stdout.write(`│ ${line.padEnd(cw)} `);
      } else {
        process.stdout.write(`│ ${' '.repeat(cw)} `);
      }
    });
    console.log('│');
  }
  console.log('═'.repeat(W));
}

function cmdMermaid(graph, args) {
  const filter = args[0]; // 'blocked', 'bug', 'feature', 'knowledge', or undefined
  const isBlocked = filter === 'blocked';
  let nodes = graph.nodes;
  if (filter === 'bug') nodes = nodes.filter(n => n.type === 'bug');
  else if (filter === 'feature') nodes = nodes.filter(n => n.type === 'feature');
  else if (filter === 'knowledge') nodes = nodes.filter(n => n.type === 'knowledge');
  
  const blockedIds = new Set((graph.edges || []).filter(e => e.type === 'blocks').map(e => e.target));
  if (isBlocked) nodes = nodes.filter(n => blockedIds.has(n.id));
  
  const nodeMap = {};
  nodes.forEach(n => { nodeMap[n.id] = n; });
  
  let edges = (graph.edges || []).filter(e => nodeMap[e.source] && nodeMap[e.target]);
  if (isBlocked) {
    const seen = new Set();
    edges = edges.filter(e => e.type === 'blocks' && !seen.has(e.target) && seen.add(e.target));
  } else {
    edges = edges.slice(0, 80);
  }
  
  const shortId = id => id.replace(/^(B-|F-|K-|T-|I-|R-|M-|X-|C-|RE-)/, '');
  
  console.log('\n```mermaid');
  console.log('flowchart LR');
  console.log('    %% Nodes');
  
  nodes.forEach(n => {
    const label = `${shortId(n.id)} ${(n.title||'').substring(0,28)}`.replace(/"/g, "'");
    console.log(`    ${n.id}["${label}"]`);
  });
  
  console.log('    %% Edges');
  edges.forEach(e => {
    const arrow = e.type === 'blocks' ? '-->' : '-.->';
    console.log(`    ${e.source} ${arrow} ${e.target}`);
  });
  console.log('```\n');
}

function cmdHtml(graph) {
  const total = graph.nodes.length;
  const byStatus = {}, byType = {};
  graph.nodes.forEach(n => {
    byStatus[n.status] = (byStatus[n.status] || 0) + 1;
    byType[n.type] = (byType[n.type] || 0) + 1;
  });
  
  const blockedIds = new Set((graph.edges || []).filter(e => e.type === 'blocks').map(e => e.target));
  const active = graph.nodes.filter(n => n.status === 'open' || n.status === 'investigating');
  const top = [...active].sort((a,b) => (a.priority||3)-(b.priority||3)).slice(0, 25);
  const blocked = graph.nodes.filter(n => blockedIds.has(n.id));
  
  const shortId = id => id.replace(/^(B-|F-|K-|T-|I-|R-|M-|X-|C-|RE-)/, '');
  const TC = {bug:'#f87171',feature:'#60a5fa',knowledge:'#fbbf24',task:'#a3e635',investigation:'#c084fc',rootcause:'#fb923c',fix:'#34d399',research:'#67e8f9',cluster:'#94a3b8',milestone:'#f472b6'};
  const SC = {open:'#3b82f6',investigating:'#eab308',fixed:'#22c55e',deferred:'#6b7280',blocked:'#ef4444'};
  
  let html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>IG</title><style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,system-ui,sans-serif;background:#0f172a;color:#e2e8f0;padding:24px;font-size:14px}
h1{font-size:18px;font-weight:600;margin-bottom:20px;color:#f1f5f9}
.grid{display:grid;grid-template-columns:260px 1fr;gap:20px}
.panel{background:#1e293b;border-radius:12px;padding:18px}
.row{display:flex;gap:12px;margin-bottom:14px}
.stat{flex:1;background:#0f172a;border-radius:8px;padding:12px;text-align:center}
.stat .v{font-size:26px;font-weight:700}.stat .l{font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:#64748b;margin-top:4px}
.bars{display:flex;flex-direction:column;gap:5px;margin-bottom:14px}
.bar{display:flex;align-items:center;gap:8px}
.bl{width:88px;font-size:11px;color:#94a3b8;text-align:right;flex-shrink:0}
.bg{flex:1;height:16px;background:#0f172a;border-radius:4px;overflow:hidden}
.bf{height:100%;border-radius:4px;transition:width .3s}
.bv{width:28px;font-size:10px;color:#64748b;text-align:right;flex-shrink:0}
.cards{display:flex;flex-direction:column;gap:4px;max-height:480px;overflow-y:auto}
.cards::-webkit-scrollbar{width:4px}
.cards::-webkit-scrollbar-thumb{background:#334155;border-radius:2px}
.card{display:flex;align-items:center;gap:8px;padding:8px 10px;background:#0f172a;border-radius:6px;border-left:3px solid}
.card:hover{background:#334155}
.cid{font-size:10px;font-weight:700;color:#64748b;width:42px;flex-shrink:0}
.ctitle{flex:1;font-size:11px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cp{font-size:9px;width:18px;height:18px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-weight:700;flex-shrink:0}
.p1{background:#ef4444;color:#fff}.p2{background:#f97316;color:#fff}.p3{background:#eab308;color:#000}.p4{background:#475569;color:#fff}.p5{background:#374151;color:#9ca3af}
.blk{font-size:9px;color:#ef4444;font-weight:700;flex-shrink:0}
.legend{display:flex;gap:10px;font-size:10px;color:#64748b;margin-bottom:10px}
h2{font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.05em;color:#64748b;margin-bottom:8px}
</style></head><body>
<h1>IG · ${total} nodes · ${graph.edges.length} edges · v0.3.0</h1>
<div class="grid">
<div>
<div class="panel">
<div class="row">
<div class="stat"><div class="v" style="color:#3b82f6">${byStatus.open||0}</div><div class="l">Open</div></div>
<div class="stat"><div class="v" style="color:#eab308">${byStatus.investigating||0}</div><div class="l">Active</div></div>
<div class="stat"><div class="v" style="color:#22c55e">${byStatus.fixed||0}</div><div class="l">Fixed</div></div>
</div>
<div class="bars"><h2>By Status</h2>`;
  
  Object.entries(byStatus).sort((a,b)=>b[1]-a[1]).forEach(([s,c])=>{
    const p=Math.round(c/total*100);
    html+=`<div class="bar"><div class="bl">${s}</div><div class="bg"><div class="bf" style="width:${p}%;background:${SC[s]||'#6b7280'}"></div></div><div class="bv">${c}</div></div>`;
  });
  html+=`</div><div class="bars"><h2>By Type</h2>`;
  Object.entries(byType).sort((a,b)=>b[1]-a[1]).forEach(([t,c])=>{
    const p=Math.round(c/total*100);
    html+=`<div class="bar"><div class="bl">${t}</div><div class="bg"><div class="bf" style="width:${p}%;background:${TC[t]||'#6b7280'}"></div></div><div class="bv">${c}</div></div>`;
  });
  html+=`</div></div></div><div class="panel">
<div class="legend"><span>● P1</span><span>● P2</span><span>● P3</span><span>◀ BLOCKED</span></div>
<div class="bars"><h2>Top Priority (${top.length})</h2></div>
<div class="cards">`;
  top.forEach(n=>{
    const p=n.priority||3;
    const col=TC[n.type]||'#6b7280';
    const bl=blockedIds.has(n.id);
    html+=`<div class="card" style="border-color:${col}">
<div class="cp p${p}">${p}</div><div class="cid">${shortId(n.id)}</div>
<div class="ctitle">${(n.title||'—').replace(/"/g,'&quot;')}</div>
${bl?`<span class="blk">◀ BLOCKED</span>`:''}
</div>`;
  });
  html+=`</div>`;
  if(blocked.length){
    html+=`<div style="margin-top:14px"><h2>Blocked (${blocked.length})</h2><div class="cards">`;
    blocked.slice(0,15).forEach(n=>{
      const p=n.priority||3;
      const col=TC[n.type]||'#6b7280';
      const bls=(graph.edges||[]).filter(e=>e.type==='blocks'&&e.target===n.id).map(e=>e.source).join(',');
      html+=`<div class="card" style="border-color:${col}">
<div class="cp p${p}">${p}</div><div class="cid">${shortId(n.id)}</div>
<div class="ctitle">${(n.title||'—').replace(/"/g,'&quot;')}</div>
<span class="blk">◀ ${bls}</span>
</div>`;
    });
    html+=`</div></div>`;
  }
  html+=`</div></div></body></html>`;
  
  fs.writeFileSync('scripts/ig/ig.html', html);
  console.log('\n  Written: scripts/ig/ig.html  (open in browser)\n');
}

function printHelp() {
  console.log(`
=== ig — Issue Graph CLI ===

READ:
  node scripts/ig/cuco_scripts_ig.cjs active              — open + investigating nodes
  node scripts/ig/cuco_scripts_ig.cjs blocked            — blocked nodes with blocker chain
  node scripts/ig/cuco_scripts_ig.cjs --next N           — top N priority nodes
  node scripts/ig/cuco_scripts_ig.cjs <id>               — single node detail
  node scripts/ig/cuco_scripts_ig.cjs --search <query>   — search title + description
  node scripts/ig/cuco_scripts_ig.cjs --recent N         — last N touched nodes
  node scripts/ig/cuco_scripts_ig.cjs --type <type>      — filter by node type
  node scripts/ig/cuco_scripts_ig.cjs --tag <tag>        — filter by tag
  node scripts/ig/cuco_scripts_ig.cjs --worktree <name>  — filter by origin worktree (e.g. cuco-foo-spike)
  node scripts/ig/cuco_scripts_ig.cjs --stale N          — stale (>N sessions old)
  node scripts/ig/cuco_scripts_ig.cjs --ready            — ready=true + status=open
  node scripts/ig/cuco_scripts_ig.cjs --blocks <id>      — what this node blocks
  node scripts/ig/cuco_scripts_ig.cjs --blocked-by <id>  — what's blocking this node
  node scripts/ig/cuco_scripts_ig.cjs --children <id> [--status <s>] [--type <t>]
                                            — nodes part_of <id> (feature/milestone children)
  node scripts/ig/cuco_scripts_ig.cjs --parents <id>     — what this node is part_of
  node scripts/ig/cuco_scripts_ig.cjs --edges [--source=<id>] [--target=<id>] [--type=<t>] [--all]
                                            — list edges (filters narrow scope; default limit 30, --all = 100)
  node scripts/ig/cuco_scripts_ig.cjs --stats           — graph statistics

WRITE:
  node scripts/ig/cuco_scripts_ig.cjs create <type> <title> [--desc <d>|--desc-file <p>|--desc -]
    [--tags a,b,c] [--tag a --tag b ...] [--priority N] [--ready yes]
    [--props '{JSON}'|--props-from-file <p>] [--doc <path>]
  node scripts/ig/cuco_scripts_ig.cjs delete <id>
  node scripts/ig/cuco_scripts_ig.cjs update <id> [--dry-run]
    --status <s> | --note <text> | --note-file <path> | --note -
    --title <t>  | --desc <d>    | --desc-file <path> | --desc -
    --tag <t> (repeatable) | --ready <bool> | --doc <path>
    --type <type> | --severity <s> | --category <c> | --priority <n>
    --props '{JSON}' | --props-from-file <path>
  node scripts/ig/cuco_scripts_ig.cjs edge <source> <target> [type]    — create edge
  node scripts/ig/cuco_scripts_ig.cjs edge --delete <edgeId>           — delete edge
  node scripts/ig/cuco_scripts_ig.cjs apply <file|-> [--dry-run]       — atomic batch ops (JSON array)
       Ops: create | update | delete | edge | edge-delete | reparent
       reparent: {op:"reparent", node:"X", from:"Y", to:"Z", edge_type:"part_of"}
                 — atomic delete-old + create-new edge in one step
  node scripts/ig/cuco_scripts_ig.cjs hygiene [--apply]                — sweep stale blocks + dupe edges; report orphans, ID-prefix vs type mismatches, stub descriptions

TYPES: milestone (M), future_feature (FF), feature (F), subfeature (SF),
       bug (B), task (T), knowledge (K), concept (CON), specification (SPEC)
EDGE TYPES: blocks, relates_to, part_of, causes, affects, same_root_cause, subsumes, revealed_by

DISPLAY:
  node scripts/ig/cuco_scripts_ig.cjs --board       — ASCII kanban board (5 columns)
  node scripts/ig/cuco_scripts_ig.cjs --mermaid [blocked|bug|feature|knowledge]  — Mermaid flowchart
  node scripts/ig/cuco_scripts_ig.cjs --html      — HTML dashboard (writes scripts/ig/ig.html)

`);
}

// ─── Main ─────────────────────────────────────────────────────────────────────

function main() {
  const graph = loadGraph();
  const args = process.argv.slice(2);
  
  if (args.length === 0) {
    cmdActive(graph, []);
    cmdBlocked(graph);
    console.log('');
    return;
  }
  
  const cmd = args[0];
  
  if (cmd === 'active') cmdActive(graph, args.slice(1));
  else if (cmd === 'blocked') cmdBlocked(graph);
  else if (cmd === '--next') cmdNext(graph, args.slice(1));
  else if (cmd === '--search') cmdSearch(graph, args.slice(1).join(' '));
  else if (cmd === '--recent') cmdRecent(graph, args.slice(1));
  else if (cmd === '--type') cmdType(graph, args[1]);
  else if (cmd === '--tag') cmdTag(graph, args[1]);
  else if (cmd === '--ready') cmdReady(graph);
  else if (cmd === '--worktree') cmdWorktree(graph, args[1]);
  else if (cmd === '--stale') cmdStale(graph, args.slice(1));
  else if (cmd === '--blocks') cmdBlocks(graph, args[1]);
  else if (cmd === '--blocked-by') cmdBlockedBy(graph, args[1]);
  else if (cmd === '--children') cmdChildren(graph, args.slice(1));
  else if (cmd === '--parents') cmdParents(graph, args.slice(1));
  else if (cmd === '--edges') cmdEdges(graph, args.slice(1));
  else if (cmd === '--stats') cmdStats(graph);
  else if (cmd === 'create') cmdCreate(graph, args.slice(1));
  else if (cmd === 'delete') cmdDelete(graph, args[1]);
  else if (cmd === 'update') cmdUpdate(graph, args.slice(1));
  else if (cmd === 'edge') cmdEdge(graph, args.slice(1));
  else if (cmd === 'apply') cmdApply(graph, args.slice(1));
  else if (cmd === 'hygiene') cmdHygiene(graph, args.slice(1));
  else if (cmd === '--help' || cmd === '-h') printHelp();
  else if (cmd === '--board') cmdBoard(graph);
  else if (cmd === '--mermaid') cmdMermaid(graph, args.slice(1));
  else if (cmd === '--html') cmdHtml(graph);
  else if (/^[A-Z]+-\d+$/.test(cmd)) {
    cmdDetail(graph, cmd);
  }
  else {
    console.log(`Unknown command: ${cmd}`);
    console.log(`Run: node scripts/ig/cuco_scripts_ig.cjs --help`);
    process.exit(1);
  }
  
  console.log('');
}

main();
