# CUCO-OP

A Lua ReaScript project for REAPER implementing a comprehensive Domain-Specific Language (DSL) for musical notation and MIDI generation, with automated testing and research-driven development

Quality Requirements for AI Development
- **📋 MANDATORY TODO USAGE:** Major tasks must be tracked and marked as complete in /TODO.md in root directory with timestamps
- **🔌 OSC TESTING USAGE:** Automatical testing can be done by using the script "tools/send_osc_test.py" to trigger a test action in Reaper. The test action then outputs a test file for examination in "/tests/__artifacts__" OSC connection. Always assume the OSC setup to REAPER is established and functional
- **MANDATORY:** Document all bug resolutions in knowledge base

## 🛠️ Development Process

### Pre-Implementation Protocol
**⚠️ CRITICAL: Before starting ANY new feature implementation:**
1. **If feature is new:** Begin with research phase using `/research/` framework. `/research/sources` tells you where to conduct research.
2. **If feature exists:** Review current implementation and identify next steps
3. **Never assume features are unstarted** - Always verify implementation status first

### Quality Standards
- **🚫 ZERO TOLERANCE:** Manual inspection/validation - ALL features MUST use OSC automation
- **MANDATORY:** OSC-driven REAPER testing with JSON artifact validation (`status:"pass"`)
- **PROHIBITED:** "Looks correct", "appears to work", or manual acceptance criteria
- **Research-first:** Complex system functions require theoretical documentation
- **Knowledge base:** Search existing solutions before new implementation
- **Token coverage:** Comprehensive tests must exercise all notation types

### Architecture
**Core Pipeline:**
```
Notation Text → Tokenizer → Parser → Executor → MIDI Events
```

**System Integration:**
- **REAPER API:** Native MIDI generation and project integration
- **OSC Automation:** External test orchestration with artifact validation
- **Research Framework:** Mathematical accuracy through trusted source validation

## 🗺️ Roadmap

### Immediate Priorities (Tier 1 System Functions)
- **Probability & Randomization:** `!rand`, `!human`, `@seed()`
- **Permutations:** `!perm(...)` for pitch/rhythm transformation
- **Sort & Ambitus:** Ordering operations and voice range validation

### Near-term (Tier 2 Processing)
- **Filters & Find:** Event filtering and pattern search
- **L-System & Generation:** Algorithmic composition tools
- **Advanced Mapping:** Controller and keymap integration

### Long-term (Tier 3+ Advanced)
- **Analysis engines:** Counterpoint, dodecaphony, sieve theory
- **External integration:** MusicXML, CL Collider, spectral tools
- **GUI enhancement:** Widgets, persistence, docking, MIDI editor integration

### System Functions Progress: **5 of 60+ complete**
- **Tier 0:** 2/9 functions (MIDI, OMN)
- **Tier 1:** 4/11 functions (Pitches, Tonality, Velocity, Envelopes)
- **Tier 2:** 1/6 functions (OSC testing automation)
- **Next milestone:** Complete remaining Tier 1 functions

## 🤖 AI Development Integration

### ⚠️ CRITICAL: Always Read This README First
**Before taking ANY action, AI assistants must:**
1. **Read this complete README file** to understand current project state
2. **Check the sections relevant to your task** for specific guidance
3. **Follow the fresh context protocol** if starting new work
4. **Never skip README review** - it contains critical context and prevents errors

### Fresh Context Protocol
**When an AI assistant starts fresh context:**

**Command:** "do START_HERE protocol" or "follow fresh context procedure"

**Automated Response:**
1. **Acknowledge:** "Starting CUCO-OP fresh context protocol. Completing mandatory workspace familiarization."
2. **Execute mandatory workspace scan:** Review all critical directories and documentation
3. **Report findings:** Current status summary and immediate next actions
4. **Begin work:** Using established workflows and quality gates

### Mandatory Workspace Familiarization
**⚠️ CRITICAL:** Complete ALL steps before any development work

**Step 1: Core Documentation (Read in order)**
- `AIMS.md` - Authoritative specification and notation contract
- `docs/project/current_status.md` - Current focus, blockers, next actions
- `docs/guides/development.md` - Process, quality gates, testing workflow
- `docs/technical/architecture.md` - System architecture and implementation details

**Step 2: Complete Workspace Scan**
```bash
# Essential workspace awareness commands
find . -type f -name "*.md" | head -20
find . -type f -name "*.lua" | head -20
ls -la docs/ src/ tests/ ai_workflows/
ls -la "docs/System Functions/"  # Critical: 60+ function library
ls -la tests/__artifacts__/       # Latest test results
```

**Step 3: Context Validation Checklist**
- [ ] **Source code:** `src/` components understood (tokenizer, parser, executor, engine)
- [ ] **System Functions:** `docs/System Functions/` library acknowledged (60+ directories)
- [ ] **Test suite:** `tests/` structure and latest artifacts reviewed
- [ ] **Knowledge base:** `docs/qa/knowledge_base/` searched for relevant patterns
- [ ] **Research docs:** `docs/research/` framework understood for complex features
- [ ] **Current status:** Project state and immediate priorities identified

### Quality Requirements for AI Development
- **� ASSUMPTION:** OSC connection to REAPER is established and functional
- **�🚫 ABSOLUTE PROHIBITION:** Manual testing, "looks correct" validation, manual inspection
- **MANDATORY:** ALL features validated through OSC-driven REAPER testing with JSON artifacts
- **MANDATORY:** Search knowledge base before starting new investigation
- **MANDATORY:** Use research framework for mathematically complex system functions
- **MANDATORY:** Document all bug resolutions in knowledge base
- **NEVER:** Proceed without completing workspace familiarization
- **NEVER:** Accept manual validation as completion criteria

### Development Commands
```bash
# Check current tasks and priorities
cat TODO.md

# Run current test focus
python3 tools/send_osc_test.py <test_name> --osc-mode float \
  --root "$HOME/Library/Application Support/REAPER/Scripts/CUCO/CUCO-OP"

# Check latest test results
ls -t tests/__artifacts__/ | head -3

# Search knowledge base for similar issues
grep -r "keywords" docs/qa/knowledge_base/
```

## 📞 Support & Contributing

- **Documentation:** Complete guides in `docs/` directory
- **Issues:** Check `docs/qa/knowledge_base/` for known solutions
- **Development:** Follow `docs/guides/development.md` process
- **Research:** Use `docs/research/` framework for system functions

**License:** MIT
**Repository:** Comprehensive DSL implementation with research-driven quality standards
