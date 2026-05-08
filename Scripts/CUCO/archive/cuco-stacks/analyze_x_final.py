#!/usr/bin/env python3
"""
Final X Functionality Test Analysis
Analyzes the results of: ~2 [c4 e4 g4]!arp(down,3) . x . X . x^ . X^
"""

import csv
import sys

def analyze_final_test():
    """Analyze the final comprehensive X test."""
    print("=== Final X Functionality Test Analysis ===")
    print("Test notation: ~2 [c4 e4 g4]!arp(down,3) . x . X . x^ . X^")
    print()
    
    # Read CSV data
    try:
        with open("/tmp/cuco_test_output.csv", 'r') as file:
            reader = csv.DictReader(file)
            notes = list(reader)
    except FileNotFoundError:
        print("ERROR: Could not find CSV file")
        return
    
    if not notes:
        print("ERROR: No notes found")
        return
    
    print(f"Total notes generated: {len(notes)}")
    print()
    
    # Group notes by time to identify sections
    sections = []
    current_section = []
    last_time = None
    
    for note in notes:
        start_time = float(note['start_time'])
        if last_time is None or abs(start_time - last_time) < 0.05:  # Same time or very close
            current_section.append(note)
        else:
            if current_section:
                sections.append(current_section)
            current_section = [note]
        last_time = start_time
    
    if current_section:
        sections.append(current_section)
    
    # Expected sections based on our test pattern
    expected_labels = [
        "Stack with !arp(down,3)",
        "x reference (should be chord)", 
        "X reference (should be chord)",
        "x^ inheritance (should be arpeggio)",
        "X^ inheritance (should be arpeggio)"
    ]
    
    print("=== Section Analysis ===")
    for i, section in enumerate(sections):
        label = expected_labels[i] if i < len(expected_labels) else f"Section {i+1}"
        
        print(f"\n{i+1}. {label}")
        print(f"   Time: {section[0]['start_time']} - {section[-1]['end_time']}")
        print(f"   Notes: {len(section)}")
        
        # Determine if it's a chord (simultaneous) or arpeggio (sequential)
        start_times = [float(note['start_time']) for note in section]
        unique_times = len(set(start_times))
        
        if unique_times == 1:
            # All notes start at the same time = chord
            pitches = sorted([note['note_name'] for note in section])
            print(f"   Pattern: CHORD - {' + '.join(pitches)}")
        else:
            # Notes start at different times = arpeggio
            pitches = [note['note_name'] for note in section]
            print(f"   Pattern: ARPEGGIO - {' -> '.join(pitches)}")
    
    print("\n=== Verification Results ===")
    
    # Check if we have the expected 5 sections
    if len(sections) >= 5:
        print("✅ Found expected number of sections")
        
        # Section 1: Should be arpeggio (stack with processor)
        s1_times = len(set(float(note['start_time']) for note in sections[0]))
        if s1_times > 1:
            print("✅ Section 1: Arpeggio (stack with !arp processor)")
        else:
            print("❌ Section 1: Expected arpeggio, got chord")
        
        # Section 2: Should be chord (x reference)
        s2_times = len(set(float(note['start_time']) for note in sections[1]))
        if s2_times == 1:
            print("✅ Section 2: Chord (x reference without inheritance)")
        else:
            print("❌ Section 2: Expected chord, got arpeggio")
        
        # Section 3: Should be chord (X reference)  
        s3_times = len(set(float(note['start_time']) for note in sections[2]))
        if s3_times == 1:
            print("✅ Section 3: Chord (X reference without inheritance)")
        else:
            print("❌ Section 3: Expected chord, got arpeggio")
        
        # Section 4: Should be arpeggio (x^ inheritance)
        s4_times = len(set(float(note['start_time']) for note in sections[3]))
        if s4_times > 1:
            print("✅ Section 4: Arpeggio (x^ with inherited processor)")
        else:
            print("❌ Section 4: Expected arpeggio, got chord")
        
        # Section 5: Should be arpeggio (X^ inheritance)
        s5_times = len(set(float(note['start_time']) for note in sections[4]))
        if s5_times > 1:
            print("✅ Section 5: Arpeggio (X^ with inherited processor)")
        else:
            print("❌ Section 5: Expected arpeggio, got chord")
        
        # Verify x and X produce identical results
        if len(sections) >= 3:
            s2_pitches = sorted([note['note_name'] for note in sections[1]])
            s3_pitches = sorted([note['note_name'] for note in sections[2]])
            if s2_pitches == s3_pitches and s2_times == s3_times:
                print("✅ x and X produce identical results")
            else:
                print("❌ x and X produce different results")
        
        # Verify x^ and X^ produce identical results
        if len(sections) >= 5:
            s4_sequence = [note['note_name'] for note in sections[3]]
            s5_sequence = [note['note_name'] for note in sections[4]]
            if s4_sequence == s5_sequence and s4_times == s5_times:
                print("✅ x^ and X^ produce identical results")
            else:
                print("❌ x^ and X^ produce different results")
    else:
        print(f"❌ Expected 5 sections, got {len(sections)}")
    
    print("\n=== Detailed Note Listing ===")
    for i, note in enumerate(notes, 1):
        print(f"{i:2d}. {note['note_name']:3s} | Start: {float(note['start_time']):8.3f} | Duration: {float(note['duration']):6.3f}")

if __name__ == "__main__":
    analyze_final_test()