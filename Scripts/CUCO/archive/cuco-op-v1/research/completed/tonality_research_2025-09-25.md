# Tonality System Functions Research

**Function Name**: `tonality.*`
**System Function Category**: Tonality
**Research Start Date**: 2025-09-25
**Research Completion Date**: 2025-09-25
**Implementation Priority**: Tier 1 (from SYSTEM_FUNCTIONS_COVERAGE.md)

## Research Overview

### Function Purpose
Implement tonality and scale system functions that provide key/scale awareness, scale degree analysis, transposition, and modal harmony support for CUCO-OP's musical composition engine.

### Complexity Assessment
- **Mathematical Complexity**: Medium - Well-established music theory with clear mathematical relationships
- **Implementation Difficulty**: Moderate - Requires careful handling of enharmonic spelling and modal theory
- **Performance Requirements**: Light - Mostly lookup tables and simple calculations
- **Integration Dependencies**: Pitch system (already implemented), CONTEXT token parsing (already implemented)

## Theoretical Foundation

### Core Concepts
1. **Diatonic Scales**: Seven-note scales with specific interval patterns (major: T-T-S-T-T-T-S)
2. **Key Signatures**: Flat/sharp patterns that establish tonal center (Circle of Fifths)
3. **Scale Degrees**: Numbered positions within a scale (1-7) with functional names (tonic, dominant, etc.)
4. **Enharmonic Spelling**: Same pitch with different notation (C# vs Db) based on key context
5. **Modal Scales**: Variations of major scale starting from different degrees (Dorian, Phrygian, etc.)
6. **Chromatic Transposition**: Moving all pitches by same interval while maintaining relationships

### Mathematical Framework

#### Key Formulas
```
Major Scale Interval Pattern: [2, 2, 1, 2, 2, 2, 1] semitones
Circle of Fifths Position: (tonic * 7) mod 12 
Scale Degree to Chromatic: (degree - 1) mapped through interval pattern
Transposition: new_pitch = (old_pitch + interval) mod 12
```

#### Algorithm Descriptions
1. **Scale Generation**: Start from tonic, apply interval pattern, handle enharmonic spelling
2. **Key Signature Calculation**: Use circle of fifths to determine sharps/flats
3. **Scale Degree Analysis**: Map chromatic pitches back to scale degrees within key
4. **Transposition**: Preserve scale relationships while changing tonic

### Edge Cases & Boundary Conditions
- **Input Validation**: Key names must match standard notation (c, f#, bb, etc.)
- **Boundary Conditions**: Octave wrapping, enharmonic equivalents
- **Special Cases**: Diminished intervals, augmented scales, non-diatonic modes
- **Error Conditions**: Invalid key names, impossible transpositions

## Source Research & Validation

### Primary Sources Used
1. **Tonal Harmony by Stefan Kostka & Dorothy Payne**
   - **Authority Level**: Primary academic source, standard music theory textbook
   - **Key Insights**: Circle of fifths mathematics, scale degree functions, modal theory
   - **Concepts Used**: Diatonic scale construction, key signature systems

2. **The Jazz Theory Book by Mark Levine**
   - **Authority Level**: Primary professional source, jazz harmony authority  
   - **Key Insights**: Enharmonic spelling rules, modal applications, chromatic relationships
   - **Concepts Used**: Practical scale applications, transposition methods

### Cross-Validation Results
- **Consistency Check**: Both sources agree on fundamental scale construction and circle of fifths
- **Confidence Level**: High - These are well-established, standardized music theory concepts

### Additional References
- Common Music programming language implementations for algorithmic reference
- OMN (Opusmodus) documentation for similar system function patterns (found in CUCO-OP docs/)

## Implementation Design

### API Design
Based on research findings and CUCO-OP architecture patterns:

```lua
-- Core tonality module following established CUCO-OP patterns
local tonality = {}

-- Generate scale notes for given key and mode
function tonality.get_scale_notes(key, mode, octave)
    -- Purpose: Generate diatonic scale in specified key/mode
    -- Parameters: key (string, "c", "f#", "bb"), mode (string, "major", "minor", "dorian"), octave (number, base octave)
    -- Returns: array of {pitch, name} tables with MIDI numbers and note names
end

-- Get key signature (number of sharps/flats)
function tonality.get_key_signature(key, mode)
    -- Purpose: Calculate key signature for display and analysis
    -- Parameters: key (string), mode (string)
    -- Returns: {sharps=number, flats=number, accidentals={note names}}
end

-- Analyze scale degree for pitch in key context
function tonality.get_scale_degree(pitch, key, mode)
    -- Purpose: Determine scale degree (1-7) for given pitch in key
    -- Parameters: pitch (MIDI number), key (string), mode (string)  
    -- Returns: {degree=number, quality="perfect|major|minor", name="tonic|supertonic|etc"}
end

-- Transpose maintaining scale relationships
function tonality.transpose_in_key(pitches, from_key, to_key, mode)
    -- Purpose: Transpose pitch sequence preserving scale degree relationships
    -- Parameters: pitches (array of MIDI numbers), from_key, to_key, mode
    -- Returns: array of transposed MIDI numbers with proper enharmonic spelling
end

-- Check if pitch collection fits in key
function tonality.analyze_key_fit(pitches, key, mode)
    -- Purpose: Analyze how well pitch collection fits theoretical key
    -- Parameters: pitches (array), key, mode
    -- Returns: {fit_score=0.0-1.0, non_diatonic=array, suggested_key=string}
end
```

### Data Structures

```lua
-- Scale definition structure
local scale_definition = {
    name = "major",           -- scale type name
    intervals = {2,2,1,2,2,2,1}, -- semitone interval pattern
    degrees = {"tonic", "supertonic", "mediant", "subdominant", "dominant", "submediant", "leading"},
    qualities = {"perfect", "major", "minor", "perfect", "perfect", "minor", "major"}
}

-- Key context structure  
local key_context = {
    root = "c",              -- root note name
    mode = "major",          -- mode name
    signature = {sharps=0, flats=0}, -- key signature
    notes = {{pitch=60, name="c4"}},  -- scale notes with enharmonic spelling
    chromatic_map = {0,2,4,5,7,9,11} -- scale degrees to chromatic mapping
}
```

### Algorithm Implementation Plan
1. **Phase 1**: Basic scale generation and key signature calculation
2. **Phase 2**: Scale degree analysis and enharmonic spelling rules  
3. **Phase 3**: Integration with existing CONTEXT token system
4. **Phase 4**: Advanced features like modal interchange and key analysis

### Performance Considerations
- **Computational Complexity**: O(1) for most operations using lookup tables
- **Memory Requirements**: Small - mainly lookup tables for scales and keys
- **Real-time Constraints**: Suitable for real-time use, all operations are fast
- **Optimization Opportunities**: Pre-compute common keys and cache results

## Test Strategy & Validation

### Theoretical Correctness Tests
1. **Scale Generation Test**: Validates major/minor scale construction
   - **Input**: "c", "major", 4 
   - **Expected Output**: [C4, D4, E4, F4, G4, A4, B4] with correct MIDI numbers
   - **Validation Method**: Compare against music theory textbook examples

2. **Key Signature Test**: Validates circle of fifths mathematics
   - **Input**: "g", "major"
   - **Expected Output**: {sharps=1, accidentals=["f#"]}
   - **Validation Method**: Cross-reference with standard key signature charts

3. **Scale Degree Analysis Test**: Validates pitch-to-degree mapping
   - **Input**: pitch=67 (G4), key="c", mode="major"
   - **Expected Output**: {degree=5, quality="perfect", name="dominant"}

### Edge Case Tests
1. **Enharmonic Keys**: Test equivalent keys (f# major vs gb major)
2. **Chromatic Pitches**: Test non-diatonic pitches in key analysis
3. **Octave Boundaries**: Test scale generation across octave boundaries

### Integration Tests  
1. **CONTEXT Token Integration**: Test with existing @c.major parsing
2. **Pitch Module Integration**: Test interaction with chord literal system
3. **Executor Integration**: Test tonality-aware note generation

### Performance Tests
1. **Scale Generation Speed**: Measure time for generating all 12 major scales
2. **Key Analysis Speed**: Measure time for analyzing complex pitch collections

## Musical Context & Applications

### Practical Use Cases
1. **Scale-Constrained Generation**: Generate melodies that stay within key
2. **Intelligent Transposition**: Transpose while maintaining modal character
3. **Key Analysis**: Analyze existing music for key center and modulations
4. **Voice Leading**: Create smooth transitions between chords in key

### Integration with DSL
Current CONTEXT syntax already supports basic tonality:

```lua
~16 @c.major          -- Set key context for following notation
seq = [1 2 3 4 5 6 7] -- Scale degrees instead of absolute pitches
CM7 = 1 3 5 7         -- Chord degrees in current key
```

### Musical Examples
1. **Diatonic Sequence**: `@c.major [1 2 3 4 5 6 7 8]` → C D E F G A B C
2. **Modal Music**: `@d.dorian [1 2 b3 4 5 6 b7 8]` → D E F G A B C D
3. **Transposition**: Same sequence in different keys maintains relationships

## Implementation Roadmap

### Prerequisites
- ✅ CONTEXT token parsing (already implemented in tokenizer)
- ✅ Basic pitch system (already implemented) 
- ✅ MIDI number generation (already implemented)

### Implementation Phases
1. **Phase 1 (Core Algorithm)** - Duration: 1-2 days
   - Deliverables: Basic tonality.lua module with scale generation
   - Success Criteria: Can generate major/minor scales correctly

2. **Phase 2 (Integration & Polish)** - Duration: 1 day
   - Deliverables: Parser/executor integration with CONTEXT tokens
   - Success Criteria: @c.major affects note generation behavior

3. **Phase 3 (Testing & Documentation)** - Duration: 1 day  
   - Deliverables: Comprehensive test suite and documentation
   - Success Criteria: All tests pass via OSC automation

### Risk Assessment
- **Low Risk**: Well-established music theory with clear algorithms
- **Medium Risk**: Enharmonic spelling complexity could create edge cases
- **Mitigation Strategies**: Start with simple keys, add complexity incrementally

## Research Completion Checklist

**Theoretical Understanding**:
- [x] All mathematical concepts fully understood and documented
- [x] Cross-validated against authoritative music theory sources  
- [x] Edge cases and boundary conditions identified
- [x] Algorithm correctness verified through theoretical analysis

**Implementation Planning**:
- [x] API design complete and follows CUCO-OP patterns
- [x] Data structures planned and documented
- [x] Performance implications understood (lightweight operations)
- [x] Integration approach planned with existing CONTEXT system

**Test Strategy**:
- [x] Theoretical correctness tests defined with specific inputs/outputs
- [x] Edge case tests planned for enharmonic and boundary conditions
- [x] Integration tests specified for existing systems
- [x] Performance validation approach established

**Documentation Quality**:
- [x] Sources properly referenced (standard music theory texts)
- [x] Mathematical notation clear and accurate  
- [x] Implementation roadmap realistic and detailed
- [x] Musical context and applications clearly explained

---

**Research Sign-off**: This research is complete and implementation may proceed. All checklist items completed and theoretical foundation established.