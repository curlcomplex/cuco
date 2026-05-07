#!/usr/bin/env node
// Hook: Stop — if the last assistant turn used park-phrases ("out of
// scope", "for another session", "park for later", etc.) without
// invoking /handover-log, block stop and demand the agent either
// log the handover or explicitly mark a false positive.
//
// Bypass: HANDOVER_NUDGE_OFF=1

const fs = require('fs');

if (process.env.HANDOVER_NUDGE_OFF === '1') process.exit(0);

let input = '';
process.stdin.on('data', d => (input += d));
process.stdin.on('end', () => {
  let transcriptPath = '';
  let stopHookActive = false;
  try {
    const data = JSON.parse(input);
    transcriptPath = data.transcript_path || '';
    stopHookActive = !!data.stop_hook_active;
  } catch {
    process.exit(0);
  }

  if (stopHookActive) process.exit(0);
  if (!transcriptPath || !fs.existsSync(transcriptPath)) process.exit(0);

  let lines;
  try {
    lines = fs.readFileSync(transcriptPath, 'utf8').trim().split('\n');
  } catch {
    process.exit(0);
  }

  const turn = [];
  for (let i = lines.length - 1; i >= 0; i--) {
    let entry;
    try { entry = JSON.parse(lines[i]); } catch { continue; }
    const role = entry.message?.role || entry.role;
    if (role === 'user') break;
    if (role === 'assistant') turn.unshift(entry);
  }
  if (turn.length === 0) process.exit(0);

  let text = '';
  const toolUses = [];
  for (const entry of turn) {
    const content = entry.message?.content || entry.content;
    if (typeof content === 'string') {
      text += '\n' + content;
    } else if (Array.isArray(content)) {
      for (const block of content) {
        if (block.type === 'text' && block.text) text += '\n' + block.text;
        if (block.type === 'tool_use') toolUses.push(block);
      }
    }
  }

  const parkPatterns = [
    /\bout of scope\b/i,
    /\bfor another session\b/i,
    /\bpark (?:it |this |that )?for later\b/i,
    /\bpark (?:it|this|that)\b(?!.{0,40}\bdecision\b)/i,
    /\bdefer(?:red|ring)? to (?:a )?(?:later|future|next) session\b/i,
    /\bnot (?:in scope|this session)\b/i,
    /\bsave (?:it|this|that) for (?:another|the next|a future) session\b/i,
    /\bcome back to (?:it|this|that) (?:later|next session)\b/i,
  ];
  const matched = parkPatterns.find(p => p.test(text));
  if (!matched) process.exit(0);

  const invoked = toolUses.some(tu => {
    if (tu.name === 'Skill' && /handover-log/i.test(tu.input?.skill || '')) return true;
    if (tu.name === 'Bash' && /handover-log/i.test(tu.input?.command || '')) return true;
    return false;
  }) || /HANDOVER-LOG-NUDGE:\s*FALSE-POSITIVE/i.test(text);

  if (invoked) process.exit(0);

  const reason = [
    'handover-log-nudge: detected park-phrase in last assistant turn ' +
      `(matched ${matched}) without /handover-log invocation.`,
    '',
    'Either:',
    '  1. Invoke /handover-log <NODE-ID> (or bare to create node) ' +
      'to capture the deferred work, then stop.',
    '  2. If this is a false positive, include the literal token ' +
      '"HANDOVER-LOG-NUDGE: FALSE-POSITIVE" in your next response.',
    '',
    'Bypass for the rest of this session: HANDOVER_NUDGE_OFF=1.',
  ].join('\n');

  process.stdout.write(JSON.stringify({ decision: 'block', reason }));
  process.exit(0);
});
