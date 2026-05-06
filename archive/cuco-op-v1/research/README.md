# Research Documentation (CUCO-OP)

This file defines a token-efficient, IDEA-driven research workflow for agentic AI working on CUCO-OP features.

──────────────────────────────────────────────────────────────────────────────

## Directory Structure

ai_workflows/research/
├── README.md
├── sources/
│   ├── trusted_sources.md
│   └── source_validation.md
├── templates/
│   └── research_template.md
├── user_core-ideas/
│   ├── YYYY-MM-DD_title.md             # Human-language IDEA notes
│   └── _current.txt                    # Single line: active IDEA filename
├── in_progress/
│   └── YYYY-MM-DD_function_name.md     # Active research entries
└── completed/
    └── YYYY-MM-DD_function_name.md     # Finalized research docs

──────────────────────────────────────────────────────────────────────────────

## Role of /user_core-ideas (IDEA-Driven Research)

- The user writes IDEA(s) in plain language in `user_core-ideas/`.
- The active IDEA filename is stored in `user_core-ideas/_current.txt`.

### Minimal IDEA file format (token-friendly)

# IDEA: Short Title
## Feature
(plain language)
## Desired Outcome
(plain language)
## Suggested Syntax
(1–3 short lines showing intended token/function/operator use)
## Constraints
(bullets)
## Nice-to-haves
(bullets)
## Examples / References
(links or short quotes)

──────────────────────────────────────────────────────────────────────────────

## Token Budget Rules (HARD LIMITS)

**Inputs allowed per run**
- Active IDEA file (from `_current.txt`) + this README + `templates/research_template.md`
- ≤ 3 external source pages (full text) after a two-pass search

**Max lengths**
- Idea Summary ≤ 1,200 characters
- Per-source note ≤ 500 characters
- Suggested Syntax in summary ≤ 3 lines

**Generation caps (approx. word limits)**
- Feasibility Snapshot ≤ 400
- Findings ≤ 600
- Recommendations ≤ 300
- Tests ≤ 300
- Integration Notes ≤ 300

**Forbidden / Guardrails**
- No repo-wide scans; no scanning unrelated folders
- No long quotes or full PDF dumps; summarize with inline citations
- Maintain small “Working Notes” in the in-progress doc, not in prompts

**Two-Pass Search**
1) Titles/abstracts skim to shortlist up to 5
2) Open ≤ 3 best sources in full

──────────────────────────────────────────────────────────────────────────────

## Research Quality Standards

### Primary Research Requirements
1. **User-Provided CORE Idea**
   - Must exist in `/user_core-ideas/`. AI loads the active filename from `_current.txt`.
   - If missing/ambiguous: stop and request the filename; do not guess.
2. **CUCO-OP Feasibility Assessment**
   - **REAPER/Lua Compatibility**: Check ReaScript API constraints.
   - **Performance Viability**: Suitability for real-time MIDI generation.
   - **Integration Complexity**: Fit with existing CUCO-OP architecture/tokens.
   - **Syntax Viability**: Detect conflicts with existing grammar/tokens; estimate parser impact.
3. **Implementation Recommendations**
   - **Recommended**: Feasible, valuable, aligned with CUCO-OP goals
   - **Adapted**: Requires modifications for environment constraints or **syntax adjustments**
   - **Not Recommended**: Impractical, redundant, or out of scope
4. **Mathematical Verification**
   - Validate formulas/algorithms for correctness.

### Secondary Requirements
- **≥ 2 Authoritative Sources** from `/sources/trusted_sources.md` and validated via `/sources/source_validation.md`
- **Cross-Validation** against relevant music theory/maths where applicable
- **Integration Planning** for CUCO-OP systems/tokens (including **Suggested Syntax** implications)

### Documentation Requirements
- Clear mathematical notation where needed
- Code examples or pseudocode for complex algorithms (concise)
- Test cases for correctness + edge cases + performance boundaries
- Integration notes (interfaces/tokens touched, failure modes, migration)
- **Syntax notes**: any deviations from the user’s Suggested Syntax and rationale

──────────────────────────────────────────────────────────────────────────────

## Integration with Development Cycle

### Phase Flow
- **Phase 0 — Research (IDEA-driven)**
- **Phase 1 — Implementation**
- **Phase 2 — Validation & Docs Lock**

### Quality Gates (must pass before next phase)
- Feasibility (ReaScript, performance, integration, **syntax viability**) ✅
- Evidence cross-validation (≥ 2 authoritative sources) ✅
- Tests defined (correctness + edge cases + performance) ✅
- Integration plan aligned with CUCO-OP architecture **and syntax strategy** ✅
- Documentation complete (math if needed, concise pseudocode, test specs, integration & syntax notes) ✅

──────────────────────────────────────────────────────────────────────────────

## Phase 0 — Research Workflow (IDEA Parsing → Aims → Evidence)

**0.0 Load Active IDEA**
- Read `user_core-ideas/_current.txt` → open that single file.
- If `_current.txt` is missing/empty or file not found: stop and request exact filename.

**0.1 Structured Parse (no full-doc scan)**
Extract these fields (null if missing):
- Feature
- Desired Outcome
- Suggested Syntax (up to 3 short lines)
- Constraints
- Nice-to-haves
- Examples/References

Compose an **Idea Summary** (≤ 10 lines / ≤ 1,200 chars), including the **Suggested Syntax** snippet verbatim (≤ 3 lines).

**0.2 Research Aims Synthesis (3–6 bullets)**
- Convert the Idea Summary into explicit Aims (what to validate, prototype, and measure).

**0.3 CUCO-OP Fit Check (fast pass)**
Produce a short table:
| Aspect | Verdict | Notes |
|---|---|---|
| ReaScript/Lua |  |  |
| Performance   |  |  |
| Integration   |  |  |
| Syntax        |  |  |
| Blockers      |  |  |

**0.4 Evidence Plan (2–4 questions)**
- Define the minimum set of questions that require external sources.
- Include at least one **syntax-related** question (e.g., parser ambiguity, token precedence, naming collisions).

**0.5 Scope Guard**
- List out-of-scope items explicitly to prevent scope creep.

**0.6 Research Execution (Two-Pass)**
- Pass 1: Skim titles/abstracts, shortlist up to 5 candidates.
- Pass 2: Open ≤ 3 best sources in full; take notes (≤ 500 chars each) mapped to Aims.

**0.7 Closure Deliverables**
- Findings (concise, cite inline)
- Recommendations (ranked, with tradeoffs; **call out syntax adaptations if needed**)
- Tests (correctness, edge, performance)
- Integration Notes (interfaces/tokens, failure modes, migration)
- **Syntax Spec** (final proposed token/function/operator usage & any deviations from Suggested Syntax)
- Out of Scope (copied from 0.5)

──────────────────────────────────────────────────────────────────────────────

## Template (to paste into templates/research_template.md)

## Idea Summary (≤ 10 lines)
- Feature:
- Desired Outcome:
- Constraints:
- Nice-to-haves:
- References (links only):
- Suggested Syntax (≤ 3 lines):

## Research Aims (3–6 bullets)

## Feasibility Snapshot
| Aspect | Verdict | Notes |
|---|---|---|
| ReaScript/Lua |  |  |
| Performance   |  |  |
| Integration   |  |  |
| Syntax        |  |  |
| Blockers      |  |  |

## Evidence Plan (2–4 questions, incl. ≥1 syntax-related)

## Findings (concise; inline citations)

## Recommendations (ranked; tradeoffs noted; include syntax adaptations if any)

## Tests
- Correctness:
- Edge cases:
- Performance:

## Integration Notes
- Interfaces / tokens touched:
- Failure modes:
- Migration / compatibility:

## Syntax Spec
- Final usage examples (1–3 lines)
- Notes on differences from user Suggested Syntax (if any) and why

## Out of Scope

## Appendices (optional, short)

──────────────────────────────────────────────────────────────────────────────

## Research Review Process

### Self-Review Checklist
- [ ] All mathematical concepts validated against ≥ 2 authoritative sources
- [ ] Edge cases and boundary conditions identified and documented
- [ ] Implementation approach technically feasible and well-defined
- [ ] Test validation covers correctness, edge cases, and performance
- [ ] Integration coherent with existing CUCO-OP syntax/tokens
- [ ] **Syntax viability checked** (no grammar conflicts; naming/precedence OK)
- [ ] Performance implications understood and documented

──────────────────────────────────────────────────────────────────────────────

## Success Metrics

### Research Quality Indicators
- Implementation matches theoretical spec
- Tests validate theory (not only behavior)
- No math errors found during implementation/testing
- Smooth integration with CUCO-OP syntax/tokens
- **Final syntax either matches user Suggested Syntax or has documented, justified adaptations**
- Performance meets expectations for algorithmic complexity

### Process Effectiveness Measures
- Fewer implementation iterations
- Fewer algorithmic/mathematical bugs
- Consistent quality across complex features
- Higher confidence in sophisticated musical algorithms

──────────────────────────────────────────────────────────────────────────────

## Commands (single root, token-aware)

# Start a new research doc from template
cp ai_workflows/research/templates/research_template.md \
   ai_workflows/research/in_progress/$(date +%Y-%m-%d)_function_name.md

# Set / confirm active IDEA (single line filename)
echo "YYYY-MM-DD_title.md" > ai_workflows/research/user_core-ideas/_current.txt

# Run Phase 0 (AI reads ONLY: _current.txt, that IDEA file, this README, the template)

# Archive on completion
mv ai_workflows/research/in_progress/$(date +%Y-%m-%d)_function_name.md \
   ai_workflows/research/completed/

──────────────────────────────────────────────────────────────────────────────

## Trusted Sources Policy

- Use only sources listed in `/sources/trusted_sources.md`.
- Validate credibility per `/sources/source_validation.md`.
- Keep source notes ≤ 500 characters; cite inline; avoid long quotes.

──────────────────────────────────────────────────────────────────────────────

END
