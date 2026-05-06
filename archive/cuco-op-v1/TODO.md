# CUCO-OP Project TODO# CUCO-OP Project TODO# CUCO-OP Project TODO



**⚠️ MANDATORY: All TODO entries MUST include date AND time stamps**



**Current Session:** September 25, 2025 21:52**⚠️ MANDATORY: All TODO entries MUST include timestamps**Prioritized milestones to reach a fully autonomous### 7. System Functions Coverage (P1) — IN-PROGRESS



## Active Tasks

### [2025-09-29 04:47] CRITICAL: Fixed Research Guidelines PDF-First Protocol

**Status:** COMPLETED at 04:47

**Priority:** P0 (Critical)

**Description:** Fixed critical gap in research workflow where research was proceeding with surface-level analysis from AIMS.md instead of comprehensive PDF analysis from `docs/System Functions/`. Updated research guidelines to MANDATE PDF-first analysis.

**Actions Taken:**
- Updated `docs/research/README.md` with mandatory PDF-first protocol
- Enhanced research template with required PDF analysis section  
- Added critical warnings about consequences of skipping PDF analysis
- Established PDF analysis checklist requirements
- Used ambitus research example to demonstrate proper PDF-first approach

**Result:** All future system function research MUST begin with comprehensive analysis of relevant PDFs in `docs/System Functions/[Category]/` before proceeding with external source validation

### [2025-09-29 06:33] COMPLETED: Fixed Chord Literal Test + Added Notation Display Feature

**Status:** COMPLETED at 06:33

**Priority:** P1

**Description:** Fixed failing chord literal test and added debugging feature to display notation in REAPER items

**Actions Taken:**
- **Fixed `simple_chord_literal` test**: Changed from `return table` format to direct assignment (`notation = ...`, `expected = ...`) format
- **Added notation display to REAPER script**: MIDI items now show test name in item notes and notation code in take name for easy debugging
- **Verified chord literal functionality**: CM7 + Dm7 produces 8 events correctly (60,64,67,71 + 62,65,69,72)
- **Created debug documentation**: `TESTS_TO_DEBUG.md` documents remaining failing tests with specific error details

**Result:** Chord literal test now PASSING (8 events). System health improved from 5/8 to 6/8 tests passing. Notation display feature will help debug remaining issues.

- Create/maintain `SYSTEM_FUNCTIONS_COVERAGE.md` as the authoritative parity tracker



### [2025-09-25 21:52] Follow Pre-Implementation Protocol**Current Date:** September 25, 2025- For each category (Tonality, Pitches, Rhythm/Meter, Counterpoint, Permutations, Probability, etc.):

**Status:** Ready to start

**Priority:** P1    - Define DSL surface (headers/processors) and Lua API shape

**Description:** Before implementing Probability & Randomization functions, follow the pre-implementation protocol:

1. Check existing implementation status in src/, tests/, docs/System Functions/## Active Tasks  - Add at least 1–2 artifact tests in `tests/` covering the happy path

2. If new → Begin research phase using docs/research/ framework

3. If exists → Review current state and continue from where left off  - Mark status in coverage file as features land



**Acceptance:** Implementation status verified and appropriate next phase determined### [2025-09-25] Follow Pre-Implementation Protocol- **Current Status**:



### [2025-09-25 21:52] Complete Tier 1 System Functions  **Status:** Ready to start    - **Pitches** ✅ COMPLETED - chord literals, voicing, all tests passing

**Status:** In Progress (4 of 11 complete)

**Priority:** P1  **Priority:** P1    - **Tonality** ✅ COMPLETED - key/scale functions, @context integration, tonality_basic test passing

**Description:** Complete remaining Tier 1 system functions per roadmap priority:

- **Next:** Probability & Randomization (!rand, !human, @seed())**Description:** Before implementing Probability & Randomization functions, follow the pre-implementation protocol:  - **Velocity** ✅ COMPLETED - dynamics shaping with @96, @+10, !vel(linear,60,120), ^, ! working

- **Following:** Permutations (!perm(...) for pitch/rhythm transformation)

- **Final:** Sort & Ambitus (ordering operations and voice range validation)1. Check existing implementation status in src/, tests/, docs/System Functions/  - **Envelopes** ✅ COMPLETED - velocity/time interpolation with !env(linear,start,end), !env(exponential,start,end), !env(adsr,sustain,release), envelope_validation test passing



**Current Status:**2. If new → Begin research phase using docs/research/ framework    - Enhanced development cycle with research framework and knowledge base integration

- ✅ Pitches - Complete (chord literals, voicing algorithms)

- ✅ Tonality - Complete (key/scale context) 3. If exists → Review current state and continue from where left off  - 4 Tier 1 system functions complete with validation

- ✅ Velocity - Complete (dynamic shaping)

- ✅ Envelopes - Complete (time-based interpolation)- Acceptance:



**Acceptance:** All Tier 1 functions implemented with OSC-validated REAPER testing**Acceptance:** Implementation status verified and appropriate next phase determined  - Coverage file reflects up-to-date status and links to tests



## Completed Tasks  - ~~Tonality + Pitches + Rhythm/Meter marked In-Progress with initial tests passing~~ ✅ Pitches + Tonality DONEnd musical authoring experience inside Reaper.



### [2025-09-25 21:50] Documentation Consolidation Crisis Resolution### [2025-09-25] Complete Tier 1 System Functions

**Status:** COMPLETED at 21:50

**Priority:** P0 (Critical)  **Status:** In Progress (4 of 11 complete)  ## 0) Research & Knowledge Base Framework (P1) — NEW

**Description:** Eliminated dangerous documentation conflicts between ai_workflows/ and docs/ that could cause AI assistants to read contradictory information

**Priority:** P1  - Goal: Rigorous research process for complex system functions + institutional memory preservation

**Actions Taken:**

- Removed 9 conflicting ai_workflows/*.md files **Description:** Complete remaining Tier 1 system functions per roadmap priority:- Tasks:

- Eliminated duplicate research/ and knowledge_base/ directories

- Established single source of truth: README.md + docs/ structure- **Next:** Probability & Randomization (!rand, !human, @seed())  - **Research Process**: Phase 0A integration for mathematical/theoretical system functions

- Moved TODO.md to root with timestamp requirements

- **Following:** Permutations (!perm(...) for pitch/rhythm transformation)  - **Trusted Sources**: Maintain authoritative source database with validation criteria

**Result:** Clean, unambiguous documentation structure achieved

- **Final:** Sort & Ambitus (ordering operations and voice range validation)  - **Research Documentation**: Complete research template system with theoretical validation

### [2025-09-25 21:45] OSC Testing Requirements Clarified

**Status:** COMPLETED at 21:45    - **Knowledge Base Maintenance**: Prevent repeated debugging through institutional memory

**Priority:** P1

**Description:** Made automated testing requirements absolutely clear in README to prevent confusion**Current Status:**  - **Quarterly Review** (Next: 2025-12-25): Review research quality and process effectiveness



**Changes Made:**- ✅ Pitches - Complete (chord literals, voicing algorithms)- Acceptance:

- Changed "Optional" to "MANDATORY" for test automation

- Added explicit prohibitions against manual validation- ✅ Tonality - Complete (key/scale context)   - Research phase integrated into development cycle for all system functions

- Emphasized JSON artifact requirement with status:"pass"

- Added assumption that OSC connection is already established- ✅ Velocity - Complete (dynamic shaping)  - Trusted sources database established with validation framework



**Result:** Zero ambiguity about testing requirements- ✅ Envelopes - Complete (time-based interpolation)  - Research documentation template system operational



---  - Knowledge base searches integrated into all development phases



## TODO Usage Rules**Acceptance:** All Tier 1 functions implemented with OSC-validated REAPER testing  - All complex implementations backed by rigorous theoretical research



**⚠️ STRICT REQUIREMENTS:**

1. **Date & Time Stamps:** ALL entries MUST include [YYYY-MM-DD HH:MM] timestamp

2. **Status tracking:** Use "Ready to start", "In Progress", "Blocked", "COMPLETED at HH:MM" ## Completed Tasks## 1) Comparator + Pass/Fail (P1) — DONE

3. **Priority levels:** P0 (Critical), P1 (High), P2 (Medium), P3 (Low)

4. **Acceptance criteria:** Clear, testable completion requirements- Goal: Mark tests as pass/fail automatically by comparing scanned CSV against each test’s expected plan

5. **Updates:** Modify existing entries rather than creating duplicates

6. **Completion timestamps:** Include time when marking tasks COMPLETED### [2025-09-25] Documentation Consolidation Crisis Resolution- Tasks:



**AI Assistant Instructions:****Status:** COMPLETED    - Implement a small comparator (Lua or Python) that reads CSV and expected plan table

- ALWAYS use this TODO.md file for task tracking

- NEVER create task lists in other files or conversations**Priority:** P0 (Critical)    - Tolerance: QN eps=1e-6, PPQ eps=1, velocity exact, pitch exact, channel exact

- UPDATE timestamps when modifying entries (include current time)

- MOVE completed tasks to "Completed Tasks" section with completion time**Description:** Eliminated dangerous documentation conflicts between ai_workflows/ and docs/ that could cause AI assistants to read contradictory information  - Update `CUCO-OP Test Action.lua` to call comparator and write JSON `{status: pass|fail, counts, diff}`

- FORMAT: [YYYY-MM-DD HH:MM] for all timestamps

  - (Optional) Diff helper producing a compact row-wise diff for failures

**Example Entry Format:**

```**Actions Taken:**- Acceptance:

### [2025-09-25 14:30] Task Title

**Status:** In Progress  - Removed 9 conflicting ai_workflows/*.md files   - Running `tools/send_osc_test.py rhythm_basic` ends with JSON status `pass` — CONFIRMED

**Priority:** P1

**Updated:** [2025-09-25 16:45] - Added acceptance criteria- Eliminated duplicate research/ and knowledge_base/ directories  - Intentionally altered expected plan yields `fail` with a human-readable diff — AVAILABLE

**Description:** Clear task description

**Acceptance:** Specific completion requirements- Established single source of truth: README.md + docs/ structure

```
- Moved TODO.md to root with timestamp requirements## 2) New Tests (P1) — DONE

- Add coverage for chords and processors

**Result:** Clean, unambiguous documentation structure achieved- Files:

  - `tests/chords_basic.lua` — parentheses chords, chord literals, simple voicing

### [2025-09-25] OSC Testing Requirements Clarified  - `tests/processors_arp_poly.lua` — !arp, !poly, channel routing

**Status:** COMPLETED  - Acceptance:

**Priority:** P1    - Both tests produce CSV/JSON artifacts and pass with their expected plans — CONFIRMED

**Description:** Made automated testing requirements absolutely clear in README to prevent confusion

## 3) Parser/Engine Scaffolding (P1) — ✅ COMPLETED

**Changes Made:**- Draft an executable skeleton for the DSL pipeline

- Changed "Optional" to "MANDATORY" for test automation- Tasks:

- Added explicit prohibitions against manual validation  - Tokenizer stub (notes, x/./_, repeats, ~grid, @context, !processors, parentheses chords) — ✅ DONE

- Emphasized JSON artifact requirement with status:"pass"  - AST structure and normalization contracts (from AIMS.md) — ✅ DONE

- Added assumption that OSC connection is already established  - Minimal executor that turns a tiny subset (notes + ./_ + *N + ~grid) into a plan — ✅ DONE

  - Place under `src/` (Lua) or hybrid with an external helper if needed — ✅ DONE

**Result:** Zero ambiguity about testing requirements- Acceptance:

  - A micro test (`tests/engine_smoke.lua`) runs notation → plan for a simple sequence — ✅ CONFIRMED

---  - **BONUS**: Complete basic notation features implemented and validated — ✅ CONFIRMED

- Implementation:

## TODO Usage Rules  - `src/tokenizer.lua` - Parses CUCO Stacks notation into tokens

  - `src/parser.lua` - Converts tokens into Abstract Syntax Tree

**⚠️ STRICT REQUIREMENTS:**  - `src/executor.lua` - Executes AST to generate plan tables with full repeat/rest/sustain/chord support

1. **Timestamps:** ALL entries MUST include [YYYY-MM-DD] timestamp  - `src/engine.lua` - Main API module

2. **Status tracking:** Use "Ready to start", "In Progress", "Blocked", "COMPLETED"   - `tests/engine_smoke.lua` - Pipeline validation test (PASSING)

3. **Priority levels:** P0 (Critical), P1 (High), P2 (Medium), P3 (Low)  - `tests/notation_*.lua` - Comprehensive notation feature tests (ALL PASSING)

4. **Acceptance criteria:** Clear, testable completion requirements  - **OSC automation pipeline fully functional in REAPER**

5. **Updates:** Modify existing entries rather than creating duplicates

## 4) Developer UX (P2)

**AI Assistant Instructions:**- Write `README.dev.md` describing the autonomous test loop and how to run it

- ALWAYS use this TODO.md file for task tracking- Add a menu in the GUI editor to run tests (Run All / Run File / Run Selected)

- NEVER create task lists in other files or conversations- Acceptance:

- UPDATE timestamps when modifying entries  - Docs exist and a developer can run a test end-to-end with 1–2 copy/paste commands

- MOVE completed tasks to "Completed Tasks" section with completion date
## 5) Output Routing + Syntax Polish (P2)
- Finalize chained assignment and quick @var outputs in AIMS.md
- Small parser hooks prepared for `chN = name = expr` and `@name = expr`
- Acceptance:
  - Examples in docs parse under the engine skeleton (even if no-ops for routing yet)

## 6) Nice-to-haves (P3)
- Optional file watcher that prints pass/fail live
- Snapshot regeneration helper
- Groove/humanize fixtures and randomized stability checks (seeded RNG)

## 7) System Functions Coverage (P1) — IN-PROGRESS
- Create/maintain `SYSTEM_FUNCTIONS_COVERAGE.md` as the authoritative parity tracker
- For each category (Tonality, Pitches, Rhythm/Meter, Counterpoint, Permutations, Probability, etc.):
  - Define DSL surface (headers/processors) and Lua API shape
  - Add at least 1–2 artifact tests in `tests/` covering the happy path
  - Mark status in coverage file as features land
- **Current Status**:
  - Pitches system functions implementation started (chord literals, voicing)
  - AIMS.md syntax validation process established in development cycle
  - Need to complete chord literal debugging and add comprehensive tests
- Acceptance:
  - Coverage file reflects up-to-date status and links to tests
  - Tonality + Pitches + Rhythm/Meter marked In-Progress with initial tests passing

## 8) Docs import pass (P2)
- From `docs/System Functions/` PDFs, compile a lightweight, structured index (name → short description → DSL/API mapping)
- Store under `docs/Reference/` as `System-Functions-Index.md`
- Acceptance:
  - Quick-searchable index exists and cross-links to AIMS and coverage tracker

## 9) Stress Test (P1) — DONE
- Add `tests/stress_many_events.lua` (8 bars of 16ths across 4 channels, 512 events)
- Acceptance:
  - JSON shows `status: pass`, `events: 512` — CONFIRMED

---
Owners: (assign as we go)
- Lua/Engine: <owner>
- Reaper Action: <owner>
- Tests/Comparator: <owner>
- Docs/UX: <owner>
