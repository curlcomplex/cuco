# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

CUCO-OP is a sophisticated Domain-Specific Language (DSL) for musical notation and MIDI generation implemented as a REAPER script. It features a complete tokenizer → parser → executor pipeline that converts human-readable musical notation into MIDI events through automated testing validation.

**Core Architecture:**
```
Notation Text → Tokenizer → Parser → Executor → MIDI Events
```

## Development Commands

### Testing (Primary Development Tool)
The project uses OSC-driven REAPER testing with JSON artifact validation:

```bash
# Run any test (template)
python3 tools/send_osc_test.py <test_name> --osc-mode float \
  --root "$HOME/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP"

# Common tests to validate core functionality
python3 tools/send_osc_test.py rhythm_basic --osc-mode float \
  --root "$HOME/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP"

python3 tools/send_osc_test.py envelope_validation --osc-mode float \
  --root "$HOME/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP"

python3 tools/send_osc_test.py simple_chord_literal --osc-mode float \
  --root "$HOME/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP"
```

**Test Results:**
- JSON artifacts created in `tests/__artifacts__/` with pass/fail status
- CSV files contain MIDI event data for validation
- Expected format: `{pitch, s, e, vel, ch}` where s/e are in quarter notes

### Development Workflow Commands

```bash
# Check latest test results
ls -t tests/__artifacts__/ | head -5

# View current project tasks (with timestamps)
cat TODO.md

# Quick codebase structure overview
find src -name "*.lua" | head -10
find tests -name "*.lua" | head -10

# Search for specific functionality
grep -r "processor" src/
grep -r "envelope" src/
```

### Build and Validation
No traditional build process - validation occurs through OSC testing in REAPER:

```bash
# The primary build validation is running core tests
python3 tools/send_osc_test.py rhythm_basic --osc-mode float \
  --root "$HOME/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP"

# System health check (run multiple core tests)
python3 tools/send_osc_test.py envelope_validation --osc-mode float \
  --root "$HOME/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP"
```

## High-Level Architecture

### Core Pipeline Components

**1. Tokenizer (`src/tokenizer.lua`)**
- Converts CUCO Stacks notation into structured tokens
- Handles: notes (c4, d#3), special tokens (x, _, .), offsets (+2, -1), repeats (*N)
- Supports: contexts (@c.major), processors (!arp, !env), chords ((c4 e4 g4), CM7)

**2. Parser (`src/parser.lua`)**
- Transforms tokens into Abstract Syntax Tree (AST)
- Creates semantic structure for musical expressions
- Handles variable assignments and channel routing

**3. Executor (`src/executor.lua`)**
- Executes AST to generate MIDI event plans
- Integrates system functions: pitch, velocity, envelopes, tonality
- Produces time-quantized events in quarter notes

**4. Engine (`src/engine.lua`)**
- Main API coordinating the complete pipeline
- Provides debugging functions and self-validation
- Entry point: `engine.process_notation(notation_string, context)`

### System Functions Architecture

The project implements modular system functions in separate files:
- `src/pitch.lua` - Pitch/chord processing, chord literals
- `src/velocity.lua` - Velocity shaping, accents, humanization  
- `src/envelopes.lua` - Time-based interpolation (linear, exponential, ADSR)
- `src/tonality.lua` - Key/scale context integration
- `src/sort.lua` - Musical event sorting operations
- `src/ambitus.lua` - Voice range validation
- `src/probability.lua` - Random/stochastic operations
- `src/permutation.lua` - Pitch/rhythm transformations

### Testing Infrastructure

**OSC Automation Pipeline:**
1. Python script writes test name to `tests/__next_test__.txt`
2. OSC message sent to REAPER (localhost:8000)
3. REAPER runs `CUCO-OP Test Action.lua`
4. Notation executed → MIDI generated → CSV scanned → JSON result

**Test File Format:**
```lua
-- name: test_name
notation = [[
~16 @c.major
seq = [c4 d4 e4]
ch1 = seq
]]

expected = {
  {pitch=60, s=0.0, e=0.25, vel=96, ch=1},
  {pitch=62, s=0.25, e=0.5, vel=96, ch=1},
  {pitch=64, s=0.5, e=0.75, vel=96, ch=1},
}
```

## Current Notation System

### Basic Notation
```
c4 d4 e4 f4          # Notes with octave
c4 . . .             # Sustain with dots
c4 _ d4 _             # Rests
c4*4                 # Repeats
[c4 d4 e4]           # Stacks (sequences)
(c4 e4 g4)           # Chords
CM7 Dm7 G7           # Chord literals
```

### Context and Processing
```
~16                  # Grid resolution (16th notes)
~8t                  # Triplet 8ths
@c.major             # Scale context
@96                  # Velocity setting
!arp(up,7)          # Arpeggiation processor
!env(linear,60,120) # Velocity envelope
!vel(+10)           # Velocity modifier
```

### Variable Assignment
```
melody = [c4 d4 e4 f4]
ch1 = melody
ch2 = harmony = melody !arp(up,7)
```

## Development Process

### Updated Feature Development Workflow

**Phase 0: Feature Dictation (NEW)**
- **MANDATORY**: User must dictate specific features before any research begins
- No system function research or implementation occurs without explicit user specification
- User defines scope, requirements, and priorities for new features

**Phase 0A: Research & Foundation (If Required)**
- Only proceed if user specifies mathematically/theoretically complex features
- Create research documentation using established framework
- Validate against trusted sources before implementation

**Phase 1: Implementation**
- Follow AIMS.md specifications for syntax and behavior
- Implement tokenizer → parser → executor changes
- Create comprehensive tests with expected plans

**Phase 2: Validation**
- **MANDATORY**: OSC-driven REAPER testing with JSON artifacts
- All features must achieve `status:"pass"` in automated tests
- No manual validation accepted

**Phase 3: Documentation**
- Update README.md and technical documentation
- Update TODO.md with timestamp completion markers
- Document any architectural decisions

### Quality Requirements

**Testing Standards:**
- ALL features validated through OSC-driven REAPER testing
- JSON artifacts must show `status:"pass"` for completion
- Manual inspection/validation is prohibited
- Test files include expected MIDI event plans

**Development Standards:**
- Search knowledge base before starting investigation
- Follow established architectural patterns
- Maintain compatibility with existing features
- Update TODO.md with timestamped progress

## Project Status

### Current Capabilities
- **Core Engine**: Complete tokenizer→parser→executor pipeline
- **Notation**: Notes, rests, sustains, repeats, chords, chord literals
- **System Functions**: Velocity (✅), Envelopes (✅), Tonality (✅), Pitches (✅), Sort (✅), Ambitus (✅)
- **Testing**: OSC automation pipeline with JSON validation
- **Integration**: Full REAPER MIDI generation and validation

### Key Implementation Areas

**Completed System Functions (6/11 Tier 1):**
- MIDI I/O and OMN baseline
- Pitches and chord processing
- Tonality and scale contexts  
- Velocity shaping and dynamics
- Envelope interpolation systems
- Sort and Ambitus operations

**Architecture Patterns:**
- System functions follow modular pattern in separate files
- Processors integrate through executor.lua
- Tests validate through real REAPER MIDI generation
- Documentation maintained in docs/ hierarchy

### Common Development Patterns

**Adding New System Functions:**
1. Create `src/[function].lua` with module implementation
2. Integrate processor calls in `src/executor.lua`
3. Add tokenizer patterns if new syntax required
4. Create test files with expected MIDI plans
5. Validate through OSC testing pipeline

**Working with Tests:**
- Tests use quarter-note timing (`s`/`e` values)
- Expected plans match exact pitch/velocity/channel
- CSV comparison uses tight tolerances (QN eps=1e-6)
- All tests must pass for feature completion

## File Structure

```
CUCO-OP/
├── src/
│   ├── engine.lua              # Main API
│   ├── tokenizer.lua           # Notation parsing
│   ├── parser.lua              # AST generation  
│   ├── executor.lua            # MIDI event generation
│   ├── pitch.lua               # Pitch/chord functions
│   ├── velocity.lua            # Velocity processing
│   ├── envelopes.lua           # Time interpolation
│   ├── tonality.lua            # Scale/key context
│   └── [other system functions]
├── tests/
│   ├── rhythm_basic.lua        # Core rhythm test
│   ├── envelope_validation.lua # Envelope system test
│   ├── __artifacts__/          # JSON/CSV results
│   └── __next_test__.txt       # OSC bridge file
├── tools/
│   └── send_osc_test.py        # Test runner
├── docs/                       # Comprehensive documentation
├── README.md                   # User-facing overview
├── AIMS.md                     # Specification authority
├── TODO.md                     # Timestamped task tracking
└── START_HERE.md               # Fresh context guide
```

## Important Notes

- **OSC Testing**: Assumes REAPER running with OSC on localhost:8000
- **macOS Paths**: Always quote paths containing spaces in commands
- **Feature Development**: User dictation required before any research/implementation
- **Documentation**: README.md and AIMS.md are authoritative sources
- **Task Tracking**: TODO.md requires timestamped entries for all work
- **Testing Philosophy**: Real REAPER validation over theoretical correctness

This WARP.md provides the essential context for productive work on CUCO-OP while respecting the established development practices and quality standards.