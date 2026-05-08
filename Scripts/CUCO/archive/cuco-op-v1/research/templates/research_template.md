<!--
System Function Research Template (STRICT per research README.md)

Provenance (metadata only; NOT part of parsed content):
- Function Name: <function_name>
- Date: YYYY-MM-DD
- Author/Agent: <name or agent>

Token Budget (REMINDERS — keep within caps from README):
- Idea Summary ≤ 1,200 chars total (Suggested Syntax ≤ 3 lines)
- Per-source note ≤ 500 chars
- Feasibility ≤ 400 words
- Findings ≤ 600 words
- Recommendations ≤ 300 words
- Tests ≤ 300 words
- Integration Notes ≤ 300 words
- Avoid long quotes/PDF dumps; summarize with inline citations.
-->

## Idea Summary (≤ 10 lines)
<!-- Populate ONLY from /user_core-ideas/_current.txt active IDEA file -->
- Feature: <plain description, 1–2 lines>
- Desired Outcome: <concrete result, 1–2 lines>
- Constraints: <bulleted, brief>
- Nice-to-haves: <bulleted, brief>
- References (links only): <short list of links>
- Suggested Syntax (≤ 3 lines; verbatim from IDEA):
    <example line 1>
    <example line 2>
    <example line 3>

## Research Aims (3–6 bullets)
- <What to validate, prototype, or measure 1>
- <…>
- <…>

## Feasibility Snapshot
| Aspect         | Verdict | Notes |
|----------------|---------|-------|
| ReaScript/Lua  | <OK/Risk/Block> | <brief note> |
| Performance    | <OK/Risk/Block> | <brief note> |
| Integration    | <OK/Risk/Block> | <brief note> |
| Syntax         | <OK/Risk/Block> | <ambiguity, precedence, naming collisions> |
| Blockers       | <none/list> | <brief note> |

## Evidence Plan (2–4 questions, incl. ≥1 syntax-related)
- <Question 1>
- <Question 2 (syntax-related: parser ambiguity/precedence/collisions?)>
- <Question 3>
- <Optional Question 4>

## Findings (concise; inline citations)
<!-- Summarize answers to Evidence Plan. Use short, source-mapped notes. Keep per-source notes ≤ 500 chars. -->
- <Finding A> (cite)
- <Finding B> (cite)
- <Conflicts & resolutions if any> (cite)

## Recommendations (ranked; tradeoffs noted; include syntax adaptations if any)
1. **<Top choice>** — <why>; tradeoffs: <brief>; **Syntax**: <accept/adapt/reject user suggestion (+ rationale)>
2. **<Alt>** — <why>; tradeoffs: <brief>
3. **<Deferred/Out>** — <why>

## Tests
- **Correctness:** <cases validating theory/expected behavior>
- **Edge cases:** <boundary conditions, invalid inputs, special modes>
- **Performance:** <checks for real-time viability; thresholds/metrics>

## Integration Notes
- **Interfaces / tokens touched:** <which modules, tokens, or APIs>
- **Failure modes:** <expected errors and handling>
- **Migration / compatibility:** <impacts on existing syntax/workflows>

## Syntax Spec
- **Final usage examples (1–3 lines):**
    <final example 1>
    <final example 2>
    <final example 3>
- **Differences vs user Suggested Syntax (if any) & rationale:**
  - <difference 1 + why>
  - <difference 2 + why>

## Out of Scope
- <Explicitly list items deferred to avoid scope creep>

## Appendices (optional, short)
- <Tiny notes, micro-derivations, or compact tables only>

<!--
Self-Review Checklist (from README; do not expand with new sections)
- [ ] ≥ 2 authoritative sources validated per /sources/source_validation.md
- [ ] Edge cases & boundary conditions identified
- [ ] Feasibility defined (ReaScript/Lua, performance, integration, syntax)
- [ ] Tests cover correctness, edge, performance
- [ ] Integration notes coherent with CUCO-OP tokens/architecture
- [ ] Syntax viability checked (no grammar conflicts; precedence/naming OK)
- [ ] Token caps respected; no unnecessary bloat
-->
