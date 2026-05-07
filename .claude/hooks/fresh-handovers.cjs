#!/usr/bin/env node
// Hook: SessionStart — surface IG nodes flagged with
// properties.handover_pending: true. Read-only, non-blocking.

const fs = require('fs');
const path = require('path');

const ISSUES = path.join(process.cwd(), '.issues.json');

let data;
try {
  data = JSON.parse(fs.readFileSync(ISSUES, 'utf8'));
} catch {
  process.exit(0);
}

const nodes = Array.isArray(data.nodes) ? data.nodes : Object.values(data.nodes || {});
const pending = nodes
  .filter(n => n && n.properties && n.properties.handover_pending === true)
  .sort((a, b) => (a.priority || 5) - (b.priority || 5));

if (pending.length === 0) process.exit(0);

const lines = [];
lines.push('=== FRESH HANDOVERS (handover_pending: true) ===');
lines.push(`${pending.length} pending — read the doc + ask "start it?"`);
lines.push('');

for (const n of pending) {
  const session = n.properties.handover_session || '?';
  const doc = n.properties.handover_doc || '(no doc)';
  lines.push(`  ${n.id} [${n.type}, p${n.priority || '?'}, ${session}] — ${n.title}`);
  lines.push(`    doc: ${doc}`);
}

lines.push('');
lines.push('After consuming a handover, clear the flag:');
lines.push('  node scripts/ig/cuco_scripts_ig.cjs update <id> --props \'{"handover_pending":false}\'');
lines.push('===============================================');

process.stdout.write(lines.join('\n') + '\n');
