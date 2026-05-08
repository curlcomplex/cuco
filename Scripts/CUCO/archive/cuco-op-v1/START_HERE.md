# START HERE: CUCO-OP Navigation & Continuity Anchor

Status: Active • Last Updated: 2025-09-25 • Purpose: Onboard fast + resume where prior work stopped

This file is the single source of truth to (a) familiarise yourself with CUCO-OP and seamlessly from the last active state. Treat it as the continuity anchor---

## 🔧 Maintenance Guidelines (Meta)

When you edit this file:
• Update the Status line date.
• Keep exactly one "Current Status" block (remove or archive old ones).
• If the status changes, replace the block with the next validated focus from `project_status.md`.
• Move any historical mapping or deprecated references into the Appendix.
• **ALWAYS maintain the mandatory workspace familiarization section** - this prevents dangerous oversights.
• **ALWAYS maintain the fresh context automation section** - this enables simple "do START_HERE.md" commands.
• Do NOT bloat with step-by-step debugging beyond what accelerates fresh continuity.
• Ensure examples still compile semantically with latest notation rules.

Intended Readers:
• New contributors needing <5 min ramp.
• Returning maintainer or AI agent re-attaching after context loss.
• **Any agent starting fresh context who must avoid missing critical workspace components**.

Primary Outcome: **Complete workspace awareness** + rapid situational awareness + next executable step.

---

This document is your jump pad—after reading it you should know: what we're fixing now, where specs live, how to validate work, and how to proceed without prior conversational context.r both humans and AI agents.

**🚨 CRITICAL**: If you open this repo fresh, you MUST complete the full workspace familiarization process below before any other work. This prevents dangerous oversights like missing the `docs/System Functions/` library or other critical components.

---

## 🤖 FRESH CONTEXT AUTOMATION

**When the user says "do START_HERE.md" or "follow START_HERE.md":**

1. **Immediately acknowledge**: "Starting CUCO-OP fresh context protocol. Completing mandatory workspace familiarization first."

2. **Execute the mandatory workspace familiarization** (Steps 1-4 below) - do NOT skip any part.

3. **Report completion**: Provide a brief summary of what you found, current status, and what you'll work on next.

4. **Begin work** using the established workflows and safeguards.

This automation prevents you from having to re-type the full handoff message each time. Just say "do START_HERE.md" and I'll execute the complete protocol automatically.

---

## 🚀 Quick Orientation

## 🔍 MANDATORY WORKSPACE FAMILIARIZATION (Fresh Context)
**CRITICAL**: Before proceeding with ANY work, complete full workspace exploration:

### Step 1: Core Documentation Review
Read in this order (stop early only if you already internalized earlier layers):
1. `AIMS.md` (spec + notation contract) – ALWAYS consult before changes
2. `ai_workflows/project_status.md` (current focus / blockers / next actions)
3. `ai_workflows/development_guide.md` (process, quality gates, testing workflow)
4. `ai_workflows/technical_details.md` (architecture + feature coverage)

### Step 2: Complete Workspace Structure Scan
**MANDATORY**: Execute these commands to see ALL workspace contents:

```bash
# Get complete workspace overview
find . -type f -name "*.md" | head -20
find . -type f -name "*.lua" | head -20
ls -la
ls -la ai_workflows/
ls -la docs/
ls -la src/
ls -la tests/

# Critical directories that must be acknowledged
ls -la "docs/System Functions/"
ls -la ai_workflows/knowledge_base/
ls -la ai_workflows/research/
ls -la tests/__artifacts__/
```

### Step 3: Workspace Acknowledgment Checklist
**Confirm awareness of ALL these critical areas:**

- [ ] **Core Source**: `src/` - tokenizer.lua, parser.lua, executor.lua, engine.lua, pitch.lua
- [ ] **System Functions Library**: `docs/System Functions/` - 40+ directories of mathematical/musical algorithms
- [ ] **Test Suite**: `tests/` - automated test files + artifacts directory
- [ ] **Research Framework**: `ai_workflows/research/` - theoretical documentation system
- [ ] **Knowledge Base**: `ai_workflows/knowledge_base/` - bug resolution and patterns
- [ ] **Documentation**: All `.md` files in root and `ai_workflows/`
- [ ] **Tools**: `tools/send_osc_test.py` - OSC test automation
- [ ] **Configuration**: Any config files, build scripts, or setup materials

### Step 4: Context Validation Questions
**Answer these before proceeding:**

1. What System Functions are available in `docs/System Functions/`?
2. What's the current implementation status from `ai_workflows/project_status.md`?
3. What tests exist and what was the last test result?
4. Are there any in-progress research documents?
5. What's in the knowledge base that might be relevant?
6. What does the AIMS.md say about the current area of work?

**⚠️ NEVER proceed without completing Steps 1-4. Missing ANY part of the workspace can lead to:**
- Overlooking existing implementations
- Duplicating existing research
- Missing critical context
- Ignoring established patterns
- Breaking existing functionality

Fast Lookup:
• Current priorities → `ai_workflows/project_status.md`
• Bug knowledge base → `ai_workflows/knowledge_base/` **[CHECK FIRST]**
• Research framework → `ai_workflows/research/` **[NEW - SYSTEM FUNCTIONS]**
• User-facing overview → `README.md`
• Implementation spec decisions → `AIMS.md`
• Deep internals → `ai_workflows/technical_details.md`

---

## 🎯 Current Status (2025-09-25)

Status: **Chord literal system fully functional** ✅
Resolution: Investigation revealed chord literals work perfectly - issue was incorrect test expectations.
Outcome: Created working `simple_chord_test.lua`, documented complete resolution in knowledge base.

**Next Context Mission:**
- **PRIMARY**: Test and validate new safeguard systems (workspace familiarization + research framework)
- **SECONDARY**: Expand system functions coverage using Phase 0A research process
- Continue systematic progress through AIMS.md functionality with rigorous theoretical backing

**Research & Knowledge Base Integration:**
- **MANDATORY**: Search `ai_workflows/knowledge_base/` before starting new work
- **MANDATORY**: Use `ai_workflows/research/` framework for system functions requiring mathematical/theoretical research
- Bug resolution: `knowledge_base/resolved/2025-09-25_chord_literal_zero_events.md`
- Research template: `research/templates/research_template.md`
- Trusted sources: `research/sources/trusted_sources.md`

Current Working Test:
```bash
python3 tools/send_osc_test.py simple_chord_test --osc-mode float \
  --root "$HOME/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP"
# Result: {"status":"pass","events":3} ✅
```

---

## 🏗️ System Snapshot

Flow: `tokenizer.lua` → `parser.lua` → `executor.lua` → MIDI events (coordinated by `engine.lua`). Pitch/chord semantics live in `pitch.lua`.

Notation Examples:
```lua
~16 @c.major                  -- 16th grid, tonal context
sequence = [c4*2 _ (e4 g4) .] -- 2 C4, rest, chord, sustain
ch1 = sequence                -- assign to channel 1
CM7 F#m7 B°7 DM7/F#           -- chord literals (current focus)
```

Minimal File Map:
```
CUCO-OP/
├─ START_HERE.md            # You are here (continuity & navigation)
├─ README.md                # User-level intro
├─ AIMS.md                  # Specification (authoritative)
├─ ai_workflows/
│  ├─ project_status.md     # Live status & next actions
│  ├─ development_guide.md  # Process + testing
│  └─ technical_details.md  # Architecture & coverage
├─ src/
│  ├─ tokenizer.lua         # Chord literal pattern focus
│  ├─ parser.lua
│  ├─ executor.lua
│  ├─ engine.lua            # Orchestrator
│  └─ pitch.lua             # Chord/pitch logic
└─ tests/
   ├─ pitch_system.lua      # Failing test target
   └─ __artifacts__/        # JSON + CSV outputs
```

---

## 🧪 Test Workflow (Canonical)

Run a test:
```bash
python3 tools/send_osc_test.py <test_name> --osc-mode float \
  --root "$HOME/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP"
```

Artifacts: `tests/__artifacts__/<test_name>_<timestamp>.json` + any CSV.
Selector File: `tests/__next_test__.txt` (written automatically by the runner).

Common Tests:
• `rhythm_basic`
• `chords_basic`
• `notation_chords`
• `notation_rests`
• `pitch_system` (current mission)
• `stress_many_events`

List latest pitch artifacts:
```bash
ls -t "tests/__artifacts__/" | grep pitch_system | head -1
```

---

## 🎵 Chord Literal Tokenization – Micro Debug Harness

Current pattern (as implemented):
```
^([A-G][#b]?[%w°ø#b/]*)
```
Potential refinement if punctuation bleeding (comma, period) is observed:
```
^([A-G][#b]?[%w°ø#b/]*)(%f[%s]|$)
```

Quick Lua scratch to verify (paste into a temporary dev test or REPL):
```lua
local pat = '^([A-G][#b]?[%w°ø#b/]*)'
for _, s in ipairs({
  'CM7','F#m7','B°7','DM7/F#','G7,','Ebø7','Am','C','Db7','A#ø7'
}) do
  local m = s:match(pat)
  print(s, '=>', m)
end
-- If G7, prints G7, (with comma) you likely need a frontier to stop at punctuation.
```

Checklist After Pattern Validation:
• Confirm tokens produced (no empty or partial matches)
• Confirm parser node type for each chord literal
• Confirm pitch expansion yields expected pitch set cardinality

---

## ⚡ Quick Commands (Consolidated)

Run current mission test:
```bash
python3 tools/send_osc_test.py pitch_system --osc-mode float \
  --root "$HOME/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP"
```

Run any test (template):
```bash
python3 tools/send_osc_test.py <test_name> --osc-mode float \
  --root "$HOME/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP"
```

Inspect newest artifact:
```bash
ls -t "tests/__artifacts__/" | head -3
```

---

## ✅ Quality & Process Reminders

1. **MANDATORY**: Search knowledge base first before any investigation or implementation.
2. **MANDATORY**: Complete Phase 0A research documentation for system functions requiring mathematical/theoretical concepts.
3. Always verify against `AIMS.md` before adding or changing syntax.
4. Use only trusted sources from `research/sources/trusted_sources.md` for theoretical research.
5. Every change should be validated through the OSC test harness (never ad-hoc execution inside REAPER bypassing the workflow).
6. **MANDATORY**: Document bug resolutions in knowledge base before milestone completion.
7. Update `ai_workflows/project_status.md` if mission focus, blockers, or priorities shift.
8. Keep this file concise—remove stale mission notes once superseded.
9. Quote macOS paths containing spaces.

Definition of Done (for current mission):
• Chord literals produce non-zero events; test turns green.
• No regression in `chords_basic` or `notation_chords` tests.
• Pattern documented (if altered) in `technical_details.md` if semantics changed.

---

## 🔧 Maintenance Guidelines (Meta)

When you edit this file:
• Update the Status line date.
• Keep exactly one “Current Mission” block (remove or archive old ones).
• If the mission resolves, replace the block with the next validated focus from `project_status.md`.
• Move any historical mapping or deprecated references into the Appendix.
• Do NOT bloat with step-by-step debugging beyond what accelerates fresh continuity.
• Ensure examples still compile semantically with latest notation rules.

Intended Readers:
• New contributors needing <5 min ramp.
• Returning maintainer or AI agent re-attaching after context loss.
Primary Outcome: Rapid situational awareness + next executable step.

---

## 📎 Appendix: Legacy Mapping (Historical Consolidation)

Older standalone docs now merged under `ai_workflows/`:
• FRESH_CONTEXT_HANDOFF.md → project_status.md
• DEVELOPMENT_CYCLE.md / TESTING.md / README.dev.md → development_guide.md
• SYSTEM_FUNCTIONS_COVERAGE.md / NOTATION_FEATURES_IMPLEMENTATION.md → technical_details.md
• TODO.md → project_status.md

Keep this appendix only while references may still appear in commit history or open discussions. Remove once obsolete.

---

## 🛟 Escalation Path

If blocked:
1. **Verify workspace awareness**: Confirm you've completed the mandatory workspace familiarization
2. **Check knowledge base**: Search `ai_workflows/knowledge_base/` for similar issues
3. **Review research**: Check if relevant research exists in `ai_workflows/research/`
4. Re-run failing test verbatim (verify environment, rule out transient state)
5. Add temporary logging in tokenizer & pitch expansion
6. Compare expected vs actual chord symbol coverage with micro harness
7. Update `project_status.md` with findings + next hypothesis
8. Only then adjust pattern or parser—avoid speculative edits

## 🚨 Workspace Oversight Prevention

**Red Flags - Stop and Complete Workspace Familiarization If:**
- You don't know what's in `docs/System Functions/`
- You haven't checked the knowledge base for similar issues
- You're unaware of existing research documentation
- You don't know the current test status or available tests
- You haven't reviewed the current project status
- You're missing context about any major directory or component

**Recovery Process:**
1. Stop current work immediately
2. Complete the mandatory workspace familiarization above
3. Update your understanding based on complete workspace context
4. Restart work with full awareness of all components

---

This document is your jump pad—after reading it you should know: what we’re fixing now, where specs live, how to validate work, and how to proceed without prior conversational context.
