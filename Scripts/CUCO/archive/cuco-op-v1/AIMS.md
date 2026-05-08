# CUCO-OP Project Aims

## Overview
Create a Reaper script that brings the sophisticated music composition and algorithmic generation capabilities of the CUCO-OP system into a DAW environment. The script will feature a GUI text editor where users can write code using CUCO-OP’s Stacks DSL and philosophy, then execute that code to generate or process MIDI data directly within Reaper.
We will also ship an autonomous test harness (OSC-triggered) that proves correctness by writing real MIDI items, scanning them, and comparing against expected plans.

## Primary Objectives
1. CUCO-OP and Reaper: Integrate the musical composition system’s functions into Reaper’s MIDI workflow.
2. Code Editor: Provide an intuitive GUI text editor within Reaper for writing and executing musical code with predictive text, colouring, and user-friendly syntax error flags.
3. Flexible MIDI Processing: Enable both generation of new MIDI items and processing of existing selected MIDI items.

## Target Features

### Core Ideas
- Analysis: Pitch, rhythm, harmonic analysis of existing MIDI.
- Generation: Algorithmic melody, harmony, and rhythm creation.
- Counterpoint: Species counterpoint and voice leading.
- Dodecaphony: Twelve-tone and serial techniques.
- L-Systems: Lindenmayer systems for musical structures.
- Probability: Stochastic composition methods.
- Permutations: Systematic pitch and rhythm transformations.
- Tonality: Key context, modulation, progressions.

### Interface Features
- GUI Text Editor: Syntax highlighting, code completion, error highlighting.
- Execution Engine: Run code with real-time feedback.
- MIDI Integration: Seamless connection to Reaper’s MIDI system.
- Template Library: Pre-built examples and starting points.
- Documentation Browser: Integrated access to function reference.

## Technical Goals
- Lua Implementation: Build using Reaper’s native Lua scripting environment (ReaImGui for GUI).
- Efficient MIDI Handling: Fast processing of large MIDI datasets.
- Modular Architecture: Clean separation between GUI, execution engine, and MIDI processing.
- Real-time Performance: Responsive interface suitable for live-coding scenarios.
- Cross-platform Compatibility: Work consistently across Windows, macOS, and Linux.
- Memory Management: Efficient handling of complex musical structures and large compositions.

## Success Criteria
- Tokenizer/DSL Correctness: All documented examples tokenize successfully under the current tokenizer.
- Functional Core: Implement key CUCO-OP functions (generation, analysis, transformations), with artifact-based tests exercising each feature.
- Seamless Integration: Script runs smoothly within Reaper without conflicts.
- User Experience: Intuitive interface that composers can learn and use effectively.
- Performance: Handle complex compositions without significant latency.
- Extensibility: Architecture allows for adding new functions and features.
- Adoption Signals: Early positive feedback from composers and Reaper users.

## Implementation Considerations

### 1. Syntax and Language Design

Stacks & Tokens (authoritative)
- Stacks: [...] are the primary containers (one step per token by default).
- Notes: c3, d#4, f-2 (octaves may be negative).
- Inherit: "-" inherits the previous note/chord; before the first explicit token it inherits from c3.
- Rest: "_" (silence for the current step).
- Sustain: "." (continue the previous note/chord through the current step).
- Offsets (on notes): c3+2, c3-5 (transpose the note literal).
- Repeats: *N on any token or stack (e.g., c3*4, [c3 d3]*2).
- Grid / Resolution: ~16, ~8t, ~4q, ~12s (t=triplet, q=quintuplet, s=septuplet).
- Context (key/scale with optional quantize flag): @c.major, @f#.minor.q.
- Processors: !name(args) or bare !name (e.g., !arp(up,7), !rand/3, !poly(3,5,2), !c.major, !f#.minor).
- Headers (global controls): @accent(12), @human(ms=10,vel=5[,pct=30]).
- Velocity (post-note): @96, @+10, @-15 immediately after a note token.
- Channel outputs: ch1…ch16 are output variables for MIDI channels 1–16. Other identifiers are plain variables and do not output unless assigned to a chN.
- Comments / Debug: //debug, //full, //trace.

Named Chords & Note Groups
- Named chords (exclusive form): noteOctave.identifier (e.g., c4.maj7, f#3.min9, g2.7b9, d3.sus4). Roman numerals and literal symbols like CM7, G7/B are not supported.
- Note groups: (c3 e3 g3) (no commas) = simultaneous notes in one step. Note groups are written inside stacks and can be followed by processors placed after the enclosing stack. Velocity after a closed group token is a planned extension—use per-note velocity inside the group for now: (c3@70 e3@70 g3@70).

Routing Model (authoritative)
    melody = [c4 d4 e4 f4]
    ch1 = melody              -- outputs on MIDI channel 1

    ch2 = [(c3 e3 g3) (d3 f3 a3)]
    ch3 = [(c3@70 e3@70 g3@70)] !arp(up,7)

- Remove all “quick output” patterns like @name = [...]. Pipelines (->, >>), @outputs{}, and write() calls are not part of the DSL.

Inherit Examples
    [- - g3 -]         -- begins as c3, c3, g3, g3
    [- c4 - - d4 -]    -- inherits c3, c4, c4, then d4, d4

### 2. Rhythm and Timing System
- Grid: ~N with optional tuple suffix (t/q/s) selects the subdivision base.
- One token == one step by default.
- Sustain/Rest/Repeat:
  - Sustain previous: "."
  - Rest: "_"
  - Repeat: *N on a token or stack.
- No duration sugars in v1: no ties "~", no :beats, %steps, or named durations. Use sustain and repeats instead.
- Humanize via header @human(...). (Swing/groove headers are not part of the tokenizer surface; defer to future processors if added.)

### 3. Harmony and Chords
- Use only noteOctave.identifier for named chords.
- Note groups implement simultaneity (no commas).
- Processors such as !arp(...)/!poly(...) may operate on the preceding stack or chord tokens as implemented in the executor.

### 4. State Management and Persistence
- Define variable scope and lifetime across runs; provide a reset/clear mechanism and project-level persistence where appropriate.

### 5. Real-time vs Batch Processing
- Support iterative, low-latency workflows for live coding during playback and offline generation for large structures.

### 6. Reaper Integration Depth
- Integrate tempo & meter awareness, project state persistence.

### 7. User Experience and Accessibility
- Built-in docs, helpful errors, stack traces for DSL lines, code completion, and a template/example library.

### 8. Performance and Scalability
- Stress-test large MIDI outputs; maintain UI responsiveness; avoid blocking the audio thread.

## Timeline & Milestones

### Phase 1: Foundation and Core Architecture
- Lock tokenizer-driven syntax (this spec).
- Build basic GUI framework (ReaImGui).
- Implement core MIDI I/O and execution engine.
- comprehensive artifact tests in the harness to ensure robust operation

### Phase 2: Core Musical Functions
- Implement priority processors/functions (generation, analysis, transformations).
- Add state management system.
- Build template & example library (all examples must tokenize).
- Develop error handling & diagnostics.

### Phase 3: Advanced Features and Polish
- Add real-time capabilities and optimizations.
- Expand processor library (counterpoint, permutations, probability, etc.).
- Performance tuning and comprehensive documentation.

## Key Considerations & Potential Challenges

### Missing Elements to Consider
1. State Management: Variable lifetimes, persistence, and reset semantics.
2. Undo/Redo Integration: Clear boundaries for generated edits.
3. Preset Management: Save/load code snippets and configurations.
4. Error Handling: Friendly diagnostics mapped to DSL locations.
5. Performance Optimization: Real-time safety and large dataset throughput.
6. Audio Preview: Rely on Reaper instruments (no internal audio engine in v1).
7. Collaboration: Sharing templates/examples; versioning guidance.

### Technical Constraints
- Reaper API: Stay within REAPER’s scripting & MIDI APIs.
- GUI: ReaImGui
- Processing Power: Balance features with performance.

### Integration Challenges
- MIDI Timing: Precise sync with project tempo & PPQ.
- Project State: Save relevant script state within project files.

---
Created: September 30, 2025 (spec updated to current tokenizer)
