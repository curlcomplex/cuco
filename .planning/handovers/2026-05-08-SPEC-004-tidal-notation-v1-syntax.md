# SPEC-004 — Tidal Notation v1.0 grammar (next: nail the syntax before any code)

📋 Citation check skipped — `scripts/check-handover.sh` not installed in CUCO. Manual review for canonical citations applied.

## 🛑 PROTOCOLS FIRST (mandatory, leads opener)

Before Turn-1, run session-start protocols. **Opener = CONTEXT, not bypass.**

1. **CLAUDE.md Session Workflow 1–4** — read SessionStart hook output (active milestones, ready work, K-001..K-005). Run intent-verify on every "logged / spec-drafted / decided" claim below by inspecting source/IG, not this opener.
2. **Canonical-source verify pass** — for every "deferred / spike required / out of scope / pattern applies" claim below, open the cited canonical doc and verify the classification. Do NOT inherit forward-looking framing from this opener unchecked. The CURLOP and VST source pointers are external repos — open them, don't trust paraphrase.
3. **Governing IG nodes** — `ig M-005`, `ig SPEC-004`, `ig F-014`, `ig SF-001..SF-005` before any spec drafting. Each carries scoped intent that must align with what the spec authorizes.
4. **CLAUDE.md ABSOLUTE BAN 5** — DISCUSS before writing code. This work is intentionally **spec-first**: the user's direction is "nail the syntax." Don't open Phase 0 (T-026) ahead of spec consensus.
5. **CLAUDE.md ABSOLUTE BAN 7** — every alignment claim cites source/spec/IG. Forward-looking grammar claims in the spec draft must cite either CURLOP `ScriptParser.cpp:line` or VST `<file>.js:line`, not memory.
6. **Don't query REAPER/ReaImGui docs** — this is grammar/spec drafting, not REAPER-API code. Golden Rule applies later when Phase 0 begins, not now.

## Status anchor

M-005 (Tidal Notation v1.0) logged at HEAD `a163318` on `main`. **No code written yet** — only the IG roadmap (28 nodes, 41 edges) was committed. SPEC-004 reserved as a node; companion doc at `.planning/specs/tidal-notation-v1-grammar.md` is **not yet drafted**. Working tree clean. **28 commits ahead of `origin/main`, no push yet.**

## Mandatory reading (4 surfaces)

**Source (external — open them, don't trust the paraphrase below):**
- `Scripts/CUCO/projects/tidal-notation/CUCO Tidal Notation 0.8.1.lua` (885 lines) — the **current** v0.8.1 grammar. Specifically:
  - lines 1-20 — header, version anchor (need ReaPack header in v1.0; B-003 tracks this)
  - lines 112-129 — `parse_step_header` (where `~16` and tuplet flags live; `@scale` directive lands here)
  - lines 158-261 — tokenizer + `scan_chunk_with_repeats` (the priority-ordered regex stack v1 needs to refactor)
  - lines 289-548 — `make_executor` (where Phase 0 event-list refactor happens)
  - line 459 — explicit `(group-inside-stack is parked)` bail; B-006 tracks
- `/Users/f.god/Work/Development/CUCO-OP-VST/src/core/syntax.js` — VST lexical grammar reference. Note `^[a-gA-G](?:[b#])?[0-9]?(?:\.[a-zA-Z0-9_]*)?(?![a-zA-Z0-9_])` for chord-name token (line 47); negative lookahead solves the `beat` vs `b` + `eat` problem. **Lua patterns have no negative lookahead** — port via manual peek-after.
- `/Users/f.god/Work/Development/CUCO-OP-VST/src/core/utils/music-math.js` — SCALES table (lines 5-37, 35 scales incl. microtonal), CHORDS table (lines 39-105, 50+ qualities), `quantizeToScale` (125-178), `noteToMidi` (201-223). All MIT-compatible logic, portable verbatim.
- `/Users/f.god/Work/Development/CUCO-OP-VST/src/processors/groove.js` (101 lines) — 8 swing modes; pure event-list post-processor.
- `/Users/f.god/Work/Development/CUCO-OP-VST/src/attributes/{flam,bounce,buzz,gate,glide,geiger,length,step}.js` — articulation references (Phase 3 source), `step:` and `len:` reference (Phase 2).
- `/Users/f.god/Work/Development/CURLOP/native/audio/ScriptParser.cpp:1660-2050` — **the load-bearing reference**. `parseSeqBody` (1661-1694) for the `/` accumulator model. `getStepMultiplierFor` (2002-2028) for `step:N` units. `getRepeatCountFor` (2031-2051), `getNaturalBeatsFor` (2054-2077), `resolveParallelTimings` (2080+) for timing math.
- `/Users/f.god/Work/Development/CURLOP/native/audio/ScriptParser.h:29` — full TokenType enum (AT, COLON, DOT, SLASH, COMMA, etc.) — the canonical token set v1.0 should align with.

**IG nodes (run `ig <id>`):**
- **M-005** — milestone umbrella. Description carries the design decisions committed in s327 (Phase 0-3 full build, hybrid source surface).
- **SPEC-004** — *this handover's umbrella*. Description names the contract surface (token set / accumulator / processors / attributes / chord names / scale / groove). Spec draft must cover all of it.
- **F-014** — CUCO Tidal Notation feature umbrella; older parent of v0.8.1 work and v1.0 plan.
- **SF-001 through SF-005** — phase subfeatures (Phase 0..4). Read each for the scoped intent the spec must authorize.
- **B-003 .. B-006** — bugs surfaced from s327 audit (no ReaPack header / no force-rerender / no visual error feedback / stack-with-groups asymmetry). Some intersect the grammar (B-006 especially — should `[]` accept nested `()` in v1.0? Spec must answer).

**Specs/research:**
- `Scripts/CUCO/projects/curlop/Language-Semantic&Runtime.MD` — CUCO OP v2's language doc. **Not authoritative for Tidal Notation**, but a useful prior art reference for processor-pipeline semantics, chance scoping, deterministic RNG, voice models. Note the audit: that spec is ~90% unimplemented (CON-002 carries the direction question). Tidal v1.0 spec should avoid scope creep into CUCO OP v2's territory.
- **No prior research doc for SPEC-004 yet** — intentional. The spec is the first artifact.

## Canonical sources

- **M-005 IG description** — authorizes the full Phase 0-3 build with hybrid source. Every "v1.0 will include X" claim in the spec must trace to either this description or one of its child SF nodes `[per ig M-005]`.
- **SPEC-004 IG description** — the abstract contract surface. The spec draft is its concretization. Any addition NOT named in SPEC-004's description (e.g. "let's also add deterministic RNG") triggers Obstacle = Stop and Ask, not silent expansion.
- **CURLOP `ScriptParser.cpp` parseSeqBody (lines 1660-1694)** — authoritative for the `/` accumulator + comma-group + bracket/paren scope handling that Tidal v1.0 inherits. `[per ScriptParser.cpp:1676]` for `/` semantics; `[per ScriptParser.cpp:1677]` for comma; `[per ScriptParser.cpp:2002]` for `step:N` multiplier with units (ms/s/hz/%).
- **VST `music-math.js`** — authoritative for chord/scale tables and quantization algorithm. `[per music-math.js:39]` for CHORDS, `[per music-math.js:5]` for SCALES, `[per music-math.js:125]` for `quantizeToScale`.
- **VST `syntax.js:47`** — authoritative for chord-name token shape. Lua port loses negative lookahead; spec must specify the peek-after workaround explicitly.
- **CUCO Tidal Notation 0.8.1.lua** — the **legacy contract** the spec must preserve via back-compat (whitespace-separated tokens with no `/` continue to behave as 1-event-per-step).
- **CLAUDE.md** — ABSOLUTE BANs (esp. 5 — discuss before code; 7 — citations); Obstacle = Stop and Ask; log multi-step plans IMMEDIATELY.

## Turn-1 action

After protocols above, **draft `.planning/specs/tidal-notation-v1-grammar.md`** as SPEC-004's companion doc. **No Lua written this turn.** The spec is the artifact; code happens after spec consensus.

**Pre-draft check:**
1. Read `Scripts/CUCO/projects/tidal-notation/CUCO Tidal Notation 0.8.1.lua` lines 1-261 (header + parse_step_header + tokenizer) — confirm the current grammar matches what's described above. Mismatch → flag to user before drafting.
2. Read `ScriptParser.cpp:1660-2050` and `syntax.js` end-to-end. The spec MUST reflect what those files actually authorize, not what this opener summarizes.
3. Run `node tools/ig/cuco_scripts_ig.cjs SPEC-004` and confirm the IG description names every contract surface listed below. Mismatch → reconcile (update SPEC-004's desc to match) before drafting the doc.

**Spec sections to cover (suggested ToC, refine before drafting):**
1. **Goals & non-goals** — what v1.0 IS (CURLOP-flavored notation for live coding via take name) and explicitly ISN'T (full CUCO OP v2 language; multi-line scripts in v1.0 unless Phase 4 lands; deterministic RNG; MPE).
2. **Source surface** — take name (short form) vs P_NOTES (long form, Phase 4). Spec the disambiguation rule (`~note` triggers P_NOTES read; CTN tag still in P_NOTES, separated by line prefix).
3. **Token set** — full lexer table. Compare to v0.8.1's hand-rolled regex stack. Decide: port to recursive-descent OR keep priority-ordered regex with documented order? Cite `syntax.js`.
4. **Step model (the `/` pivot)** — accumulator semantics. Define what's "in" a step (events between two `/`s) vs the back-compat case (no `/` → 1-event-per-step). Cite `ScriptParser.cpp:1676`. **B-006 decision lands here**: should `[]` stacks accept nested `()` groups in v1.0? Spec must say yes/no.
5. **Per-step processors** — `step:N`, `repeat:N`, `!groove(...)` (if processor syntax is added). Define multiplier semantics + units (`step:1/16`, `step:2`, `step:ms:300`). Cite `ScriptParser.cpp:2002`.
6. **Per-event attributes** — `len:N`, `vel:N`, `ch:N`, articulation attrs (`flam:`, `bounce:`, `buzz:`, `gate:`, `glide:`, `geiger:`). Define attachment syntax (`<note>:vel:80`? `<note>:vel(80)`? clarify) and event-shape transformation rules (1-in-N-out for articulations).
7. **Chord names** — `c4.maj7` token shape. Lua peek-after for negative-lookahead replacement. Expansion rule: chord token expands to a baked stack at parse time, OR at execution? (Pick one; cite VST behavior.)
8. **Scale directives** — `@scale c.major` global header parse; effect on emission (post-process quantize via `quantizeToScale`). Whether per-step `!scale(...)` overrides exist in v1.0 or defer to v1.1.
9. **Groove (swing) processor** — 8 modes from `groove.js`. Surface: `//groove(swing,50,20)` flag (matches existing `//debug` style) vs `!groove(...)` inline (requires processor-call grammar). Pick one, cite reasoning.
10. **Backward-compat semantics** — every v0.8.1 corpus case that must keep working. Reference T-028 (regression corpus task) explicitly.
11. **Diagnostics** — error-on-parse-fail visual feedback (B-005), `//force` rerender escape (B-004). What v1.0 commits to vs defers.
12. **Open questions surfaced for user decision** — collect them as a final section. Don't decide unilaterally inside the spec; ask.

**After draft:**
- Pair the doc to SPEC-004: `node tools/ig/cuco_scripts_ig.cjs update SPEC-004 --doc .planning/specs/tidal-notation-v1-grammar.md`.
- Present open-questions list to user. Resolve each. Update the spec in-place. Commit (`docs(spec): draft SPEC-004 Tidal Notation v1.0 grammar`).
- Only after user signs off on the spec: open T-026 (Phase 0a — refactor `make_executor` to push events).

## Discipline rules (this work's failure modes)

1. **No code this turn** (CLAUDE.md ABSOLUTE BAN 5) — spec drafting is the deliverable. The user's framing was "nail the syntax." Lua edits = scope creep.
2. **Cite CURLOP / VST / 0.8.1 line numbers in the spec, not memory** (BAN 7) — the spec is a contract; every claim must be traceable to a source. "It works like X" is invalid; "It works like X [per ScriptParser.cpp:1676]" is valid.
3. **Discuss open questions, don't decide them silently** (BAN 5) — the spec's "Open questions" section is the meeting place. If a grammar choice has two viable forms, list both with trade-offs and let the user pick.
4. **No subagents for the draft** (BAN 1) — write the spec yourself. Subagents miss the v0.8.1 idioms and the CURLOP semantics.
5. **Obstacle = Stop and Ask** — if a CURLOP / VST primitive turns out to be incompatible with Tidal Notation's take-name-as-source model (e.g. needs multi-line input), surface to user, don't paper over.
6. **Reconcile mismatches between SPEC-004 IG desc and source reality before drafting** — if reading `ScriptParser.cpp` reveals SPEC-004's description over-promises (or under-specifies), update the IG node first via `update SPEC-004 --desc-file <p>`.

## Branch + recent commits

Branch: `main` (28 ahead of `origin/main`, no push).

```
a163318 feat(ig): log Tidal Notation v1.0 roadmap — 4-phase build with hybrid source
095627b feat(ig): log CUCO OP v2 design audit — 2 bugs, 4 cleanup tasks, 1 direction concept
163dba1 feat(reapack): T-020 Random Walk prep + rename-on-install for shared theme
bf9e167 feat(keyframer): T-019 ReaPack prep — rename, version, @provides, @changelog, dofile refactor
ee34777 feat(ig): handover for T-019 (Keyframer ReaPack prep)
37c3d93 feat(ig): close T-001 — commit-staging pass done in Phase A of T-017
3939d70 fix(claude): repoint hook paths post-migration
c145a5e feat(ig): close T-018 — ReaPack scaffolding done
```

## End-state

SPEC-004 is "draft-complete" when:
- `.planning/specs/tidal-notation-v1-grammar.md` exists, covers the 12 ToC sections (or revised ToC after pre-draft check), every forward claim cites a canonical source.
- `node tools/ig/cuco_scripts_ig.cjs SPEC-004` shows `doc:` populated.
- Open questions surfaced to user, decisions captured back into the spec in-place.
- Commit lands: `docs(spec): draft SPEC-004 Tidal Notation v1.0 grammar`.
- IG: `update SPEC-004 --status closed --note <commit>` only after user signs off.

**Then** (and only then) Phase 0 begins via T-026.

## Caveats

- **CURLOP and VST are external repos.** Source pointers in this opener (`/Users/f.god/Work/Development/CUCO-OP-VST/...`, `/Users/f.god/Work/Development/CURLOP/...`) are read-only references. Don't edit them. Don't import them into CUCO. Port logic verbatim into `Scripts/CUCO/projects/tidal-notation/` when Phase 1+ begins.
- **CURLOP's `ScriptParser.cpp` is JUCE-dependent C++ (`juce::String`).** The spec models the grammar; the eventual Lua port is a new implementation, not a translation. Don't try to mirror C++ class structure into Lua.
- **VST repo's grammar is JS with `import` modules.** Lua doesn't have ES module sugar. Spec implementations will be flat tables.
- **Phase 4 (hybrid source) blocks nothing in v1.0 mainline.** Spec should treat it as additive — v1.0 ships fine on take-name-only; P_NOTES is upgrade path.

## Don't re-litigate

- **Phase 0-3 full build is committed.** User decided in s327 (the IG batch landed at `a163318`). Don't re-prompt "should we do less?" — instead surface scope-trim suggestions inside the spec's "non-goals" section.
- **Hybrid source surface (take name + P_NOTES) is committed** as the long-term direction. Don't reopen the editor question (CUCO OP v2 took that route and stalled — see CON-002 / B-001 / B-002).
- **`/` is the step delimiter** (not `,` or whitespace alone). User confirmed via the CURLOP source pointer.
- **Backward compatibility is required** for v0.8.1 corpus. T-028 is the regression-corpus task; spec must commit to its passing.
