#!/usr/bin/env node
// Hook: SessionStart — IG-aware context injection.
//
// Reads .issues.json and emits structured queries:
//   - Active milestones (orientation)
//   - Resume point (if any node has tag=resume-here)
//   - Blockers for the highest-priority active milestone (top 10)
//   - Ready work (top 5, priority-sorted)
//   - Knowledge nodes (load-bearing constraints)
// Plus newest handover one-liner + git status one-liner.
//
// Target injection: 5–15KB. Structured queries, not doc dumps.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function git(args, cwd) {
  try {
    return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  } catch {
    return '';
  }
}

let input = '';
process.stdin.on('data', d => (input += d));
process.stdin.on('end', () => {
  let cwd;
  try {
    cwd = JSON.parse(input).cwd || process.cwd();
  } catch {
    cwd = process.cwd();
  }

  let output = '<session-start-context>\n\n';

  // --- IG snapshot ---
  try {
    const issuesRaw = fs.readFileSync(path.join(cwd, '.issues.json'), 'utf8');
    const issues = JSON.parse(issuesRaw);
    output += buildIgContext(issues);
  } catch (e) {
    output += `## Issue Graph\n(load failed: ${e.message})\nRun \`node scripts/ig/cuco_scripts_ig.cjs --stats\` manually.\n\n`;
  }

  // --- Newest handover (one line) ---
  try {
    const handoverDir = path.join(cwd, '.planning/handovers');
    const files = fs.readdirSync(handoverDir)
      .filter(f => f.endsWith('.md'))
      .map(f => ({ f, mtime: fs.statSync(path.join(handoverDir, f)).mtime.getTime() }))
      .sort((a, b) => b.mtime - a.mtime);
    if (files.length) {
      output += `## Newest handover\n.planning/handovers/${files[0].f}\n\n`;
    }
  } catch {}

  // --- Git one-liner ---
  const status = git(['status', '--short'], cwd);
  if (status) {
    const lines = status.trim().split('\n').filter(Boolean);
    const modified = lines.filter(l => l.startsWith(' M') || l.startsWith('M ') || l.startsWith('MM')).length;
    const added = lines.filter(l => l.startsWith('A ') || l.startsWith(' A')).length;
    const untracked = lines.filter(l => l.startsWith('??')).length;
    const renamed = lines.filter(l => l.startsWith('R ')).length;
    const deleted = lines.filter(l => l.startsWith(' D') || l.startsWith('D ')).length;
    const branch = git(['rev-parse', '--abbrev-ref', 'HEAD'], cwd).trim();
    const head = git(['rev-parse', '--short', 'HEAD'], cwd).trim();
    output += `## Git\n${branch} @ ${head} — ${modified}M ${added}A ${renamed}R ${deleted}D ${untracked}?\n\n`;
  }

  output += `## On-demand reads (not auto-loaded)\n`;
  output += `- Full blocker list — \`node scripts/ig/cuco_scripts_ig.cjs --children <M-id> --status open\`\n`;
  output += `- Node detail — \`node scripts/ig/cuco_scripts_ig.cjs <id>\`\n`;
  output += `- IG help — \`/ig-help\` slash command\n`;
  output += `- Operational rules — CLAUDE.md (auto-loaded) or \`/rules\`\n\n`;
  output += `</session-start-context>`;
  process.stdout.write(output);
});

function buildIgContext(issues) {
  const nodes = Array.isArray(issues.nodes) ? issues.nodes : Object.values(issues.nodes || {});
  const edges = Array.isArray(issues.edges) ? issues.edges : Object.values(issues.edges || {});
  const byId = Object.fromEntries(nodes.map(n => [n.id, n]));

  let out = '';

  const milestones = nodes
    .filter(n => n.type === 'milestone' && n.status === 'open')
    .sort((a, b) => (a.priority || 3) - (b.priority || 3));

  if (milestones.length === 0) {
    out += `## Active milestones\n(none — graph may be empty. Run \`node scripts/ig/cuco_scripts_ig.cjs --type milestone\`.)\n\n`;
  } else {
    out += `## Active milestones (${milestones.length})\n`;
    for (const m of milestones) {
      const meta = [];
      if (m.priority) meta.push(`p${m.priority}`);
      if (m.ready) meta.push('ready');
      const metaStr = meta.length ? ` [${meta.join(', ')}]` : '';
      out += `**${m.id}** ${m.title}${metaStr}\n`;
      if (m.description) {
        const first = m.description.split('\n\n')[0].replace(/\s+/g, ' ').slice(0, 240);
        out += `  ${first}\n`;
      }
    }
    out += '\n';
  }

  const resumeNodes = nodes.filter(n =>
    (n.tags || []).includes('resume-here') &&
    n.status !== 'fixed' && n.status !== 'obsolete' && n.status !== 'wontfix'
  );
  if (resumeNodes.length) {
    out += `## Resume here\n`;
    for (const n of resumeNodes) {
      out += `**${n.id}** [${n.type}, ${n.status}] ${n.title}\n`;
      const lastNote = (n.properties?.notes || []).slice(-1)[0];
      if (lastNote) out += `  [${lastNote.session || '?'}] ${(lastNote.text || '').slice(0, 240)}\n`;
    }
    out += '\n';
  }

  const currentMilestone = milestones[0];
  if (currentMilestone) {
    const blockers = edges
      .filter(e => (e.type === 'part_of' || e.type === 'blocks') && e.target === currentMilestone.id)
      .map(e => byId[e.source])
      .filter(n => n && (n.status === 'open' || n.status === 'investigating'));

    blockers.sort((a, b) => {
      const pa = a.priority || 3, pb = b.priority || 3;
      if (pa !== pb) return pa - pb;
      return (a.id || '').localeCompare(b.id || '');
    });

    const top = blockers.slice(0, 10);
    out += `## Blockers — ${currentMilestone.id} ${currentMilestone.title} (${top.length}/${blockers.length})\n`;
    if (top.length === 0) {
      out += `(none — milestone clear)\n`;
    } else {
      for (const n of top) {
        const pri = n.priority ? `, p${n.priority}` : '';
        out += `${n.id} [${n.type}, ${n.status}${pri}] ${n.title}\n`;
        const parents = edges
          .filter(e => e.type === 'part_of' && e.source === n.id)
          .map(e => byId[e.target])
          .filter(p => p && p.type === 'feature')
          .map(p => p.title);
        if (parents.length) out += `  ${parents.join(' | ')}\n`;
      }
      if (blockers.length > top.length) {
        out += `... +${blockers.length - top.length} more. Full list: \`node scripts/ig/cuco_scripts_ig.cjs --children ${currentMilestone.id} --status open\`\n`;
      }
    }
    out += '\n';
  }

  const ready = nodes.filter(n =>
    n.ready === true &&
    (n.status === 'open' || n.status === 'investigating')
  );
  ready.sort((a, b) => {
    const pa = a.priority || 3, pb = b.priority || 3;
    if (pa !== pb) return pa - pb;
    return (a.id || '').localeCompare(b.id || '');
  });
  const topReady = ready.slice(0, 5);
  if (topReady.length) {
    out += `## Ready to start (${topReady.length}/${ready.length})\n`;
    for (const n of topReady) {
      const pri = n.priority ? `p${n.priority}` : 'p?';
      out += `${n.id} [${n.type}, ${pri}] ${n.title}\n`;
    }
    out += '\n';
  }

  const knowledge = nodes
    .filter(n => n.type === 'knowledge' && n.status !== 'obsolete' && n.status !== 'wontfix')
    .sort((a, b) => (a.priority || 3) - (b.priority || 3));
  if (knowledge.length) {
    out += `## Knowledge (${knowledge.length} load-bearing)\n`;
    for (const n of knowledge) {
      const pri = n.priority ? `p${n.priority} ` : '';
      out += `**${n.id}** ${pri}${n.title}\n`;
      if (n.description) {
        const first = n.description.split('\n\n')[0].replace(/\s+/g, ' ').slice(0, 280);
        out += `  ${first}\n`;
      }
    }
    out += '\n';
  }

  return out;
}
