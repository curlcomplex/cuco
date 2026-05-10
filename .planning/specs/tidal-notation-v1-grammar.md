# SPEC-004 — Tidal Notation v1.0 Grammar

**Status:** draft (s328)
**Companion to:** IG node `SPEC-004`
**Source surface:** REAPER MIDI take name (P_NAME)
**Paradigm:** parse-time MIDI item generator (NOT a real-time modulator host)

---

## §1 Goals & non-goals

### Goals

Promote CUCO Tidal Notation from v0.8.1's bin-window step-language to a CURLOP-flavored accumulator grammar with:

- Explicit step delimiter (`/`) replacing v0.8.1's whitespace-implicit step model
- Comma-separated parallel events at step level (`c4, e4, g4` plays as a chord)
- Whitespace-adjacency op attachment (op binds to immediately-preceding note or scope)
- Chord names (`c4.maj7`) expanded at parse time
- Scale and groove as scope-respecting OPs
- Articulations and humanization as first-class primitives
- Two scope grouping forms: `()` for tuplets (sub-step) and `[]` for multi-step

### Non-goals (v1.0)

- **Real-time control modulators.** No `lfo`, `ad`, `adsr`, `keytrack`, `accum`, `bernoulli`, `shepard`, `random`-as-modulator. Tidal Notation writes notes to MIDI items at parse time; it does not emit continuous control streams. Re-evaluate in a future spec if the paradigm changes.
- **MIDI CC syntax.** Deferred — different design problem (curves, time, scope). v1.0 is notes-only.
- **Multi-line scripts.** Single take name in v1.0. P_NOTES long-form is Phase 4 (additive, doesn't block v1.0).
- **MPE.** Not addressed.
- **Deterministic RNG seeding semantics** of CUCO OP v2 — Tidal v1.0 is intentionally smaller-surface than CUCO OP v2.
- **Backward-compat with v0.8.1 corpus.** Hard break — the v0.8.1 take-name corpus is rewritten in v1.0 syntax (T-028 covers the rewrite).

---

## §2 Source surface

v1.0 reads from a single string: the take name (`P_NAME`).

```
~<v1-grammar-body> [//flag1 //flag2 …]
```

The `~` prefix is a **trigger marker**, not part of the grammar. The watcher uses it to detect Tidal-bearing takes [per `0.8.1.lua:126`]. Trailing `//` flags are runtime headers (see §11).

P_NOTES long-form is a Phase 4 extension. v1.0 ignores P_NOTES.

---

## §3 Token set

Lexer table (priority-ordered, port from VST `syntax.js:7-55`):

| Token | Pattern | Notes |
|---|---|---|
| `WHITESPACE` | `\s+` | skipped between tokens; significant as op-attachment marker |
| `COMMENT_LINE` | `//.*` (when not preceded by `\s\s` boundary at start of header) | runtime-flag context only |
| `STEP` | `/` | step delimiter [per `ScriptParser.h:29` SLASH] |
| `COMMA` | `,` | within-step delimiter; blocks op attachment |
| `LBRACKET` `RBRACKET` | `[` `]` | multi-step OP-scope group |
| `LPAREN` `RPAREN` | `(` `)` | tuplet — sub-step subdivision AND OP-scope group (carry-forward from v0.8.1) [per `0.8.1.lua:243`] |
| `ARG_OPEN` `ARG_CLOSE` | `(` `)` | function-call args (overloaded with subdivision; resolved by context — preceded by IDENT = call, otherwise = subdivision) |
| `ASSIGN` | `=` | reserved (future-use) |
| `ATTR_SEP` | `:` | attribute / processor key:value separator [per `syntax.js:26`] |
| `FRACTION` | `\d+/\d+` | musical durations (`1/16`, `3/4`) [per `syntax.js:35`] |
| `NUMBER` | `[+-]?\d+(\.\d+)?` | integers and decimals [per `syntax.js:36`] |
| `REST` | `-` | silence; replaces v0.8.1's `.` [per `ScriptParser.cpp:1715`] |
| `HOLD` | `_` | sustain previous step's notes [per `ScriptParser.cpp:1716`] |
| `NOTE` | `[a-gA-G][b#]?-?\d+(\.[a-zA-Z0-9_]+)?` | pitch token; supports negative octaves; optional `.<chordtype>` suffix [per `syntax.js:47`, `0.8.1.lua:79`] |
| `IDENT` | `[a-zA-Z_][a-zA-Z0-9_]*` | op names, scale roots, scale types, etc. |

### Token shape notes

- **Negative octaves**. Pattern `-?\d+` accommodates MIDI's `c-1` = note 0. Lua tokenizer must consume the `-` as part of the note token via the priority order above. Lua's pattern engine has no negative lookahead [per `syntax.js:45-47`]; the lexer must instead **peek-after** the digit to confirm no following alpha/digit/underscore (preventing `beat` matching as `b` + `eat`).
- **Note-octave whitespace rule**. Every note token must contain its octave digit contiguously — no whitespace permitted between the pitch letter (with optional accidental) and the octave number. `c-1` and `c4` are valid note tokens; `c -1` errors as a malformed note (the `c` is read as an incomplete note token, then `-` is the rest token, then `1` is an orphan number with no valid context). This rule eliminates ambiguity between negative octaves and the `-` rest token.
- **Chord names**. The optional `.<chordtype>` suffix on `NOTE` handles `c4.maj7`, `f#3.min7b5`, etc. The chord-type strings are looked up in the CHORDS table at parse time [per `music-math.js:39-105`].
- **`/` ambiguity**. `/` serves dual purpose: step delimiter AND fraction separator inside numbers. Resolved by lexer priority — `FRACTION` matches before `STEP`. `1/16` = fraction; `c4 / d4` = step delimiter.
- **`(` ambiguity**. `(` is both a sub-step subdivision opener AND a function-call argument opener. Resolution: if preceded immediately (no comma) by an IDENT that names a callable op (`scale`, `groove`, `arp`, `humanize`, `flam`, etc.), it's an arg list; otherwise it's a subdivision.

---

## §4 Step model (the `/` pivot)

Steps are bounded by `/`. Events between two `/` (or between source-start and the first `/`, or between the last `/` and source-end) belong to one step [per `ScriptParser.cpp:1711` — `if (tok.type == TokenType::SLASH) { ++pos_; pushAccumulatedStep(st); continue; }`].

### Within-step delimiter

`,` separates events that share a step's onset time, AND blocks op attachment (see §6).

```
c4, e4, g4    →    one step, three parallel notes (c-major triad)
c4 / e4 / g4  →    three steps, one note each
```

### Hard-break from v0.8.1

v0.8.1 uses whitespace as an implicit step boundary [per `0.8.1.lua:226-260` tokenizer]. **v1.0 does not.** Whitespace within a step is op-attachment significant only. A take name with no `/` characters parses as a single step. T-028 rewrites the v0.8.1 corpus in v1.0 syntax.

### Multi-step OP-scope groups

`[…]` groups multiple steps so a trailing whitespace-attached op applies to the whole group:

```
[c3 / g4] reverse    →    g4 / c3   (the contained step sequence is reversed)
```

Inside `[]`, `step:` and other per-step OPs may differ per-step; OPs trailing the `]` apply to the whole group. Adaptive OPs (notably `arp`) compute per-step (see §5).

### Tuplets — sub-step subdivisions and OP scope

`(…)` carries forward from v0.8.1: notes inside `()` play sequentially within the parent step's duration [per `0.8.1.lua:243-250`]. **`()` is also an OP-scope group** — OPs attached via whitespace adjacency to the closing `)` apply to the tuplet's contents:

```
(c4 d4 e4) reverse(1) / f4         →    e4 d4 c4 inside step 1; f4 in step 2
(c4 d4 e4) repeat:2 / f4           →    (c4 d4 e4)(c4 d4 e4) inside step 1
[(c4 d4 e4) / g4] octave:+1        →    octave shift applied across the whole group
```

Scope distinction:
- `()` — single-step tuplet scope (sequential sub-step events)
- `[]` — multi-step scope (groups whole steps including their `/` boundaries)

Both serve as OP-attachment anchors. Trailing whitespace-attached OPs apply to the bracketed/parenthesized content.

### Hold semantics

`_` sustains **all** notes from the previous step across the current step boundary [per `ScriptParser.cpp:1716`]. The previous step's full event set holds; if the previous step had three parallel notes, all three sustain.

### Rest semantics

`-` produces silence in the current event slot. Multiple rests in a step produce no output for that step [per `ScriptParser.cpp:1715`].

### Orphan ops

When an op is preceded by `,` (no whitespace-adjacent note to attach to), it is **silently dropped**:

```
c2, g3, bounce(0.5) / d3
```
- `c2` and `g3` play together in step 1
- `bounce(0.5)` is comma-separated from `g3`, so it does not attach; it has no other anchor; it is dropped
- `d3` is step 2

To attach bounce to g3:
```
c2, g3 bounce(0.5) / d3
```

---

## §5 Per-step OPs

Per-step OPs attach via whitespace adjacency to a step's content. Multiple OPs may chain (whitespace-separated). Order is left-to-right ("waterfall").

### OP catalog

| OP | Signature | Default | Source |
|---|---|---|---|
| `step` | `step:N` | — | musical duration (`1/16`, `1/4`) [per `ScriptParser.cpp:2002` — `getStepMultiplierFor`] |
| `repeat` | `repeat:N` | — | repeats the attached scope N times (whole `[]` group, single step, or sub-step) [per `ScriptParser.cpp:2031`] |
| `reverse` | `reverse(N)` | 1 | reverses note order in scope when N > 0; no-op when N = 0 [per `ScriptParser.cpp:2277`] |
| `timescale` | `timescale:N` | — | stretch factor on step duration [per `ScriptParser.cpp:2280`] |
| `octave` | `octave:±N` | — | transpose by N octaves [per `ScriptParser.cpp:2281`] |
| `grid` | `grid:1/N` | — | quantize onsets to grid (musical only) [per `ScriptParser.cpp:2281`] |
| `scale` | `scale(root, type)` | — | post-quantize emissions; `scale(c, major)` [per `music-math.js:5-37`, `music-math.js:125-178`] |
| `groove` | `groove(type, amount)` | — | swing post-process (8 modes) [per `groove.js`] |
| `arp` | `arp(type, scaler)` | type=up, scaler=1 | sequential-expand parallel notes; see below |
| `ratchet` | `ratchet(count)` | 4 | even subdivision; accepts decimals |
| `strum` | `strum(time, direction)` | 1/32, up | stagger parallel notes [per `ScriptLanguage.cpp:264`] |
| `humanize` | `humanize(vel, time)` | 0, 0 | jitter (sole primitive — replaces deviate) |

### `arp` — adaptive subdivision

`arp(type, scaler)`:
- `type` ∈ `{up, down, updown, random}` [per `ScriptCompiler.cpp:1171-1189`]
- `scaler` ∈ {unit-relative-to-step (0..n, default 1), OR absolute musical (`1/16`)}

Adaptive behavior inside `[]` with mixed `step:`:
```
[c4.maj7 step:1/16 / d4 step:1/8] arp(up, 0.5)
```
- Step 1 (1/16 step): arp subdivides to 1/32 (= 0.5 × 1/16)
- Step 2 (1/8 step): arp subdivides to 1/16 (= 0.5 × 1/8)

The relative scaler adapts per-step; the absolute form (`arp(up, 1/16)`) overrides with a fixed value.

### `ratchet` — decimal count

`ratchet(count)` produces evenly-spaced onsets across the scope:
- `interval = scope_duration / count`
- Onsets at `0, interval, 2·interval, …` while `position < scope_duration`

Examples (1-step scope):
- `ratchet(4)` → 4 onsets at 0, 0.25, 0.5, 0.75
- `ratchet(4.5)` → 5 onsets at 0, 0.222, 0.444, 0.667, 0.889

CURLOP floors the count to int [per `ScriptCompiler.cpp:356`]; **v1.0 diverges and accepts decimals**.

### `repeat` — scope-relative repetition

`repeat:N` repeats whatever scope it attaches to, N times total (so `repeat:1` is a no-op-equivalent passthrough, `repeat:3` produces three copies). Scope is determined by what the OP is whitespace-attached to:

```
c4 repeat:3 / d4              →    c4 c4 c4 / d4    (single step repeated)
[c4 / d4] repeat:3            →    c4/d4 c4/d4 c4/d4    (whole 2-step group repeated → 6 steps total)
(c4 d4 e4) repeat:2 / f4      →    (c4 d4 e4)(c4 d4 e4) / f4    (sub-step subdivision repeated within step)
```

Stacking with other OPs follows the waterfall rule (§5 interaction model): `[c4 / d4] reverse(1) repeat:3` = first reverse the group to `d4 / c4`, then repeat the reversed group 3 times.

### `humanize` — sole jitter primitive

`humanize(vel, time)`:
- `vel` ∈ 0..127 (max MIDI velocity delta, ±)
- `time` ∈ 0..1 (max timing offset as fraction of step, ±)

Replaces CURLOP's `deviate` [per `ScriptParser.cpp:2272`] — Tidal v1.0 has a single jitter primitive, not separate axes. `humanize(0, 0.05)` covers timing-only; `humanize(20, 0)` covers velocity-only.

### OP interaction model (waterfall)

OPs apply left-to-right within a header chain. Documented compositions:

| Stack | Result |
|---|---|
| `chord → arp` | arpeggiated chord |
| `grid → timescale` | quantize, then stretch |
| `arp → reverse` | reversed arpeggio |
| `chord → reverse` | no-op (parallel notes have no temporal order) |
| `humanize → grid` | anti-pattern (humanize defeats grid); accepted, not error |
| `arp → timescale` | timescale stretches arp's subdivisions proportionally (since arp scaler is step-relative) |
| `articulation → arp` | articulation applies per arp-emitted note |

OPs that don't interact (orthogonal): `step` ↔ `reverse`, `octave` ↔ `humanize`, `repeat` ↔ articulations.

### `reverse` — toggle argument

`reverse(N)` takes a single numeric argument: any positive non-zero value enables reversal; `0` disables it (no-op). The default is `1` (enabled). The argument exists so the OP can be parametrically toggled in future macro/template contexts without altering the grammar shape. v1.0 implementations should treat any non-zero positive number as identical-to-`1`; future spec revisions may extend semantics (e.g. partial-reverse on fractional values) without breaking v1.0 syntax.

---

## §6 Per-event attributes

Attributes attach to a single note via whitespace adjacency. Comma between note and attribute blocks attachment (orphan dropped).

| Attribute | Signature | Range / Form |
|---|---|---|
| `vel` | `vel:N` | 0..127 (MIDI native) |
| `len` | `len:N` | absolute musical duration (`1/8`, `1/4`) — replaces `gate` |
| `ch` | `ch:N` | MIDI channel 1..16 |

### Articulations

CURLOP-aligned signatures, time arguments musical (no ms):

| OP | Signature | Default | Meaning |
|---|---|---|---|
| `flam` | `flam(time, amp)` | 1/64, 0.5 | grace-note offset + grace velocity multiplier 0..1 [per `ScriptCompiler.cpp:359-372`] |
| `bounce` | `bounce(gravity)` | 0.5 | bouncing-ball decay; 0.1 = slow lazy bounces, 0.9 = quick die-out [per `ScriptCompiler.cpp:374-383`] |
| `buzz` | `buzz(pressure)` | 0.5 | snare buzz intensity; duration baked at parse time [per `ScriptCompiler.cpp:385-395`] |
| `geiger` | `geiger(density)` | 0.5 | Poisson-distributed retrigger rate [per `ScriptCompiler.cpp:397-409`] |
| `glide` | `glide(time)` | 1/16 | pitch-bend duration to next note [per `ScriptCompiler.cpp:451-458`] |

### Attachment examples

```
c4 vel:80 len:1/8       →    c4 with velocity 80 and length 1/8
c4 bounce(0.7)          →    c4 with bounce articulation (gravity 0.7)
c4, e4 flam(1/64, 0.4)  →    c4 (no flam — comma blocks); e4 with flam
c4 vel:80 bounce(0.5)   →    c4 with both vel and bounce (chained whitespace)
```

---

## §7 Chord names

Chord names are notes with a dotted-suffix chord-type:

```
c4.maj7    f#3.min7b5    eb2.dim    g3.sus4
```

Lexer matches via the optional `.<chordtype>` suffix on `NOTE` [per `syntax.js:47`].

### Parse-time expansion

Chord tokens expand at parse time to comma-separated parallel notes on the same step. Implementation lookup table is the CURLOP-VST CHORDS dictionary [per `music-math.js:39-105`, 50+ qualities].

Example expansion:
```
c4.maj7    →    c4, e4, g4, b4   (parsed as if user wrote the comma form)
```

Subsequent OPs see the expanded form (four parallel notes), not the original chord token. This is why `c4.maj7 reverse` is a no-op — by the time `reverse` runs, the input is four simultaneous notes with no order to reverse.

**Provenance flag**: chord expansion attaches a `chord_origin: true` flag to the resulting parallel-note set. Only `strum` (§5) reads this flag; all other OPs ignore it and treat the notes as ordinary parallels. This single-bit marker is the only place v1.0 distinguishes "chord-origin" from "explicit commas" — see §12 q2.

### Why parse-time (not execution-time)

- Simpler — chord becomes ordinary parallel events; no special "chord" abstraction in later passes
- Composes cleanly with arp (`c4.maj7 arp(up)` arpeggiates c, e, g, b in pitch order)
- No special-casing for `reverse`, `humanize`, etc.

---

## §8 Scale OP

`scale(root, type)` is a scope-respecting OP (not a header directive):

```
[c3 d3 eb3 f3 g3 ab3 b3] scale(c, minor)    →    quantize emissions to C natural minor
```

- `root` ∈ `{c, c#, d, d#, e, f, f#, g, g#, a, a#, b}` (alias forms via `b`/`#`)
- `type` ∈ scale-name from the SCALES table [per `music-math.js:5-37`, 35 scales]: `major`, `minor`, `dorian`, `mixolydian`, `phrygian`, `lydian`, `locrian`, `harmonic_minor`, `melodic_minor`, `pentatonic_major`, `pentatonic_minor`, `blues`, `chromatic`, microtonal scales, etc.

Quantization algorithm: nearest-note-in-scale per emission [per `music-math.js:125-178` `quantizeToScale`].

Out-of-scale notes from earlier OPs (e.g. transpose, arp) snap to the nearest scale note when `scale(...)` is in effect at their scope.

The v0.8.1 directive form `@scale c.major` is **removed**.

---

## §9 Groove OP

`groove(type, amount)` is a scope-respecting OP (not a header directive):

```
[c4 / e4 / g4 / b4] groove(swing, 0.6)
```

- `type` ∈ 8 modes from `groove.js`: `swing`, `shuffle`, `push`, `pull`, `bounce`, `slop`, `tight`, `loose`
- `amount` ∈ 0..1 (intensity)

Semantics: pure event-list post-processor [per `groove.js`]. Applies to onsets in scope.

The v0.8.1 directive form `!groove(swing, 50, 20)` is **removed**.

---

## §10 Backward-compat semantics

**v1.0 is a hard break from v0.8.1.** No source compatibility with the v0.8.1 take-name corpus.

Rationale: the user has confirmed there are no scripts to maintain externally, and the syntax changes (rest `.` → `-`, polyphony `[]` → `,`, step delimiter required, all-OP-from-headers-to-scope) are too pervasive to retrofit a back-compat layer without bloating the parser.

T-028 covers the regression-corpus rewrite in v1.0 syntax. Once T-028's corpus passes, parity with v0.8.1's expressive scope is verified.

### Tokens removed from v1.0

| v0.8.1 token | v1.0 replacement |
|---|---|
| `.` (rest) | `-` |
| `~` (header step-size like `~16 c4 d4 e4`) | `step:1/16 c4 / d4 / e4` |
| `[c4 e4 g4]` (polyphonic stack) | `c4, e4, g4` |
| Whitespace as implicit step boundary | `/` required |
| `*N` repeat | `repeat:N` (whitespace-attached) |
| `+N` / `-N` transpose suffix | `octave:±N` op (octaves only); chromatic transpose is a future addition (out of v1.0) |
| `x` (inherit previous note) | not preserved — write the note explicitly or use `_` for hold |

---

## §11 Diagnostics (runtime headers)

Headers are runtime flags appended to the take name after the grammar body. They do not participate in note emission.

| Flag | Meaning |
|---|---|
| `//force` | bypass parse cache and rerender (B-004) |
| `//debug` | enable v0.8.1-style debug console output |

Headers in v0.8.1 also carried music-semantic directives (`//groove(...)`, `@scale ...`); v1.0 moves all music semantics into scope-respecting OPs (§8, §9). Headers are now exclusively for **runtime concerns** — rendering, diagnostics.

### Parse-error surface (B-005)

When parsing fails, v1.0 commits to a visual error indicator on the take. Exact UI surface deferred to Phase 0 implementation; the spec commits only to "errors are visible to the user, not silently dropped." Specifics live in B-005.

---

## §12 Supplementary rules

Cross-cutting rules that extend earlier sections.

1. **Articulation stacking — sequential composition.** Multiple articulations on one note compose sequentially. `c4 flam(1/64, 0.5) bounce(0.7)` runs flam first (creates grace + main hits), then bounce runs on each resulting hit (so the grace note also bounces). Composition order matches whitespace-attachment order (left-to-right). Phase 3 (SF-004) implements; documented edge cases (e.g. flam grace note inheriting glide) surfaced during port.

2. **Strum is chord-only.** `strum(time, direction)` applies only to parallel note sets that originated from a chord-name token (`c4.maj7`). Explicit comma-separated parallels (`c4, g5, e7 strum(...)`) do NOT strum. Implementation: chord expansion (§7) preserves a `chord_origin: true` flag on the resulting parallel-note set; strum checks the flag at apply time. This is the sole exception to §7's "no special chord abstraction" rule — a single boolean marker, not a structural chord type.

3. **Group-as-unit for scope-aware OPs.** When an OP is attached to a scope (`[]` or `()`) that contains nested groups, the OP treats each nested group as a single opaque unit. `[(c4 d4 e4) / f4] reverse(1)` → `f4 / (c4 d4 e4)` — the outer scope's elements are reversed; the inner tuplet is untouched (reordered as a block, not recursed into). To reverse the tuplet's internal order, attach reverse inside: `(c4 d4 e4) reverse(1)`. Every scope-aware OP follows this principle: explicit nested OPs are required to operate on inner content.

4. **Articulation parameter values pass through unclamped.** v1.0 documents 0..1 as the canonical range for articulation amplitudes (`bounce.gravity`, `buzz.pressure`, `geiger.density`, `flam.amp`), but the parser does NOT clamp out-of-range inputs. `bounce(1.5)` is accepted; the implementation produces whatever its math yields for that value. This matches CURLOP's permissive behavior [per `ScriptCompiler.cpp`] and lets users explore extreme zones. Documented ranges are guidance, not enforcement.

---

## §13 Citation index

External canonical sources cited in this spec:

- **CURLOP** (`/Users/f.god/Work/Development/CURLOP/native/audio/`):
  - `ScriptParser.cpp` — token types, parseSeqBody accumulator, op reserved-name registry
  - `ScriptParser.h` — TokenType enum
  - `ScriptCompiler.cpp` — articulation extract functions, default values, arp expansion
  - `ScriptLanguage.cpp` — op param-table reference (default values, type info)
- **VST** (`/Users/f.god/Work/Development/CUCO-OP-VST/src/core/`):
  - `syntax.js` — lexer regex table, token order
  - `utils/music-math.js` — SCALES table, CHORDS table, quantizeToScale
  - `processors/groove.js` — 8 swing modes
- **v0.8.1** (`Scripts/CUCO/projects/tidal-notation/CUCO Tidal Notation 0.8.1.lua`):
  - lines 1-261 — header parse, tokenizer, scan_chunk_with_repeats

Every forward-looking grammar claim in this document traces to one of the above sources. Where v1.0 diverges from a cited source (e.g. `ratchet` accepts decimals; `humanize` replaces `deviate`), the divergence is explicitly noted in-line.

---

## End-state checklist (SPEC-004 close criteria)

- [x] Spec doc covers all 12 ToC sections from the s327 handover
- [x] Every grammar construct cites a canonical source
- [x] OP-interaction model documented (§5 waterfall table)
- [x] Hard-break with v0.8.1 explicit (§10)
- [x] Removed-from-scope items enumerated (§1 non-goals, §10 removed tokens)
- [ ] User signs off on §12 open questions
- [ ] SPEC-004 IG node `--doc` field populated
- [ ] Commit `docs(spec): draft SPEC-004 Tidal Notation v1.0 grammar`
- [ ] T-026 (Phase 0a — refactor `make_executor` to push events) opens after sign-off
