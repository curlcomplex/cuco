---
description: Print the CUCO operational rules summary (one-screen)
---

Print the operational rules summary in this exact format. No additional commentary.

```
=== CUCO OPERATIONAL RULES ===

Source: CLAUDE.md (auto-loaded). This is a one-screen reminder.

ABSOLUTE BANs:
  1. NO subagents for implementation — write Lua yourself
  2. NO REAPER API guessing — query context7 /cfillion/reaimgui or
     curl REAPER's SDK help page first
  3. NO destructure assumptions for REAPER tuples — count return values
     (K-001: TrackFX_GetParam returns 3, not 4)
  4. NO full-read of plugin library (57MB) — line-anchored greps only
  5. DISCUSS before writing code
  6. Read IG snapshot before non-trivial action
  7. Cite IG node + spec line when claiming alignment

GOLDEN RULE: Check ReaImGui + REAPER SDK docs FIRST.
  - context7 /cfillion/reaimgui for reaper.ImGui_*
  - REAPER SDK help page for everything else
  - Don't WebFetch the SDK — its summary is lossy on return-value count

WORKFLOW:
  - Session-start hook injects IG snapshot — read it, don't re-query
  - Intent-verify pass on every "shipped/landed/done" claim before trusting
  - One-line brief with citation before starting work
  - Multi-step plans → log to IG immediately on agreement (not later)
  - Document Pairing Rule: significant findings paired with .planning/research/

COMMITS: conventional (feat / fix / docs / refactor / chore)

OBSTACLE = STOP AND ASK. Don't reframe limitations as features.

For full text: cat CLAUDE.md
For IG: /ig-help
```
