#!/usr/bin/env python3
"""
CUCO X Functionality Test Result Analysis
This script analyzes the CSV output from the X functionality tests.
"""

import csv
import sys

def analyze_x_test_results(csv_file_path):
    """Analyze the X functionality test results from CSV."""
    print("=== CUCO X Functionality Test Analysis ===")
    print()
    
    # Read the CSV data
    notes = []
    try:
        with open(csv_file_path, 'r') as file:
            reader = csv.DictReader(file)
            notes = list(reader)
    except FileNotFoundError:
        print(f"ERROR: Could not find CSV file: {csv_file_path}")
        return
    
    if not notes:
        print("ERROR: No notes found in CSV file")
        return
    
    print(f"Total notes generated: {len(notes)}")
    print()
    
    # Group notes by time sections to identify different parts
    # Our test was: ~4 [c4 e4 g4]!arp(up,4) X X^
    # Expected structure:
    # 1. Stack with arp: c4->e4->g4->c4 (up arpeggio)
    # 2. X reference: c4+e4+g4 chord (no arp)
    # 3. X^ inheritance: c4->e4->g4->c4 (inherited up arp)
    
    # Analyze timing patterns
    sections = []
    current_section = []
    last_time = None
    
    for note in notes:
        start_time = float(note['start_time'])
        if last_time is None or start_time - last_time < 0.2:  # Notes close together
            current_section.append(note)
        else:
            if current_section:
                sections.append(current_section)
            current_section = [note]
        last_time = start_time
    
    if current_section:
        sections.append(current_section)
    
    print(f"Identified {len(sections)} musical sections:")
    print()
    
    for i, section in enumerate(sections, 1):
        print(f"Section {i}:")
        print(f"  Time range: {section[0]['start_time']} - {section[-1]['end_time']}")
        print(f"  Notes: {len(section)}")
        
        # Check if notes are sequential (arpeggio) or simultaneous (chord)
        start_times = [float(note['start_time']) for note in section]
        is_sequential = len(set(start_times)) > 1
        
        if is_sequential:
            print("  Pattern: ARPEGGIO (sequential notes)")
            pitches = [note['note_name'] for note in section]
            print(f"  Sequence: {' -> '.join(pitches)}")
        else:
            print("  Pattern: CHORD (simultaneous notes)")
            pitches = sorted([note['note_name'] for note in section])
            print(f"  Chord: {' + '.join(pitches)}")
        
        print()
    
    # Verify expected behavior
    print("=== Expected vs Actual Behavior ===")
    print()
    
    if len(sections) >= 3:
        print("✓ Found 3 sections as expected")
        
        # Section 1: Stack with arp should be sequential
        if len(set(float(note['start_time']) for note in sections[0])) > 1:
            print("✓ Section 1: Arpeggio pattern (stack with !arp(up,4))")
        else:
            print("✗ Section 1: Expected arpeggio, got chord")
        
        # Section 2: X reference should be chord
        if len(set(float(note['start_time']) for note in sections[1])) == 1:
            print("✓ Section 2: Chord pattern (X reference without inheritance)")
        else:
            print("✗ Section 2: Expected chord, got arpeggio")
            
        # Section 3: X^ inheritance should be arpeggio
        if len(sections) > 2:
            if len(set(float(note['start_time']) for note in sections[2])) > 1:
                print("✓ Section 3: Arpeggio pattern (X^ with inherited !arp)")
            else:
                print("✗ Section 3: Expected inherited arpeggio, got chord")
    else:
        print(f"✗ Expected 3 sections, got {len(sections)}")
    
    print()
    print("=== Key Findings ===")
    
    # Check if X^ actually inherited the arpeggio
    if len(sections) >= 3:
        sec1_pattern = len(set(float(note['start_time']) for note in sections[0])) > 1
        sec3_pattern = len(set(float(note['start_time']) for note in sections[2])) > 1
        
        if sec1_pattern and sec3_pattern:
            print("✓ X^ INHERITANCE WORKING: Section 3 shows same arpeggio pattern as Section 1")
        elif not sec1_pattern and not sec3_pattern:
            print("? Both sections are chords - need to check if this is expected")
        else:
            print("✗ X^ INHERITANCE FAILED: Different patterns between sections")
            
        sec2_pattern = len(set(float(note['start_time']) for note in sections[1])) == 1
        if sec2_pattern:
            print("✓ X REFERENCE WORKING: Section 2 shows chord pattern (no inheritance)")
        else:
            print("✗ X REFERENCE FAILED: Expected chord pattern")
    
    # Detailed note listing for debugging
    print()
    print("=== Detailed Note Listing ===")
    for i, note in enumerate(notes, 1):
        print(f"{i:2d}. {note['note_name']:3s} | Start: {note['start_time']:8s} | Duration: {note['duration']:8s}")

if __name__ == "__main__":
    csv_path = "/tmp/cuco_test_output.csv"
    if len(sys.argv) > 1:
        csv_path = sys.argv[1]
    
    analyze_x_test_results(csv_path)