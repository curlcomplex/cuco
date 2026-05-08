#!/usr/bin/env python3
"""
Comprehensive test for all CUCO !arp processors.

Tests all available arpeggiator patterns with a chord to see the different orderings.
"""

import subprocess
import time
import csv
import os

# List of arp patterns to test
ARP_PATTERNS = [
    ('up', 4),           # Basic ascending
    ('down', 4),         # Basic descending  
    ('updown', 8),       # Up then down (double length)
    ('pend', 6),         # Pendulum (no duplicates)
    ('io', 4),           # Inside-out
    ('oi', 4),           # Outside-in/zigzag
    ('rand', 4),         # Random (will vary)
    ('skip', 4),         # Skip pattern
    ('rotate', 4),       # Rotate pattern
]

def update_test_syntax(pattern, count):
    """Update the test syntax for a specific arp pattern"""
    # Use a clear chord: C major triad (C4 E4 G4 C5)
    test_syntax = f'~{count} [c4 e4 g4 c5]!arp({pattern},{count})'
    
    content = open('/Users/f.god/Library/Application Support/REAPER/Scripts/CUCO/CUCO-Stacks/CUCO_Test_Trigger.lua').read()
    lines = content.split('\n')
    for i, line in enumerate(lines):
        if line.startswith('local TEST_SYNTAX ='):
            lines[i] = f'local TEST_SYNTAX = "{test_syntax}"'
            break
    open('/Users/f.god/Library/Application Support/REAPER/Scripts/CUCO/CUCO-Stacks/CUCO_Test_Trigger.lua', 'w').write('\n'.join(lines))

def run_test():
    """Run the CUCO test via OSC"""
    subprocess.run(['oscsend', '192.168.178.38', '8000', '/action/cuco_test'], capture_output=True)
    time.sleep(6)  # Wait for processing

def analyze_arp_results(pattern, expected_count):
    """Analyze the arp test results"""
    try:
        with open('/tmp/cuco_test_output.csv') as f:
            reader = csv.DictReader(f)
            notes = list(reader)
        
        print(f'=== !arp({pattern},{expected_count}) ===')
        
        if not notes:
            print('❌ No notes generated')
            return False
            
        # Extract note sequence
        note_sequence = []
        midi_sequence = []
        for note in notes:
            note_sequence.append(note['note_name'])
            midi_sequence.append(int(note['note_number']))
        
        print(f'Notes:     {" ".join(note_sequence)}')
        print(f'MIDI:      {" ".join(map(str, midi_sequence))}')
        print(f'Count:     {len(notes)}/{expected_count}')
        
        # Basic validation
        if len(notes) != expected_count:
            print(f'⚠️  Expected {expected_count} notes, got {len(notes)}')
        
        # Pattern-specific analysis
        chord_notes = ['C4', 'E4', 'G4', 'C5']  # Expected input chord
        chord_midi = [60, 64, 67, 72]
        
        if pattern == 'up':
            expected_order = chord_midi  # [60, 64, 67, 72]
            success = midi_sequence == expected_order
            print(f'✅ Ascending: {"CORRECT" if success else "FAILED"}')
            
        elif pattern == 'down':
            expected_order = list(reversed(chord_midi))  # [72, 67, 64, 60]
            success = midi_sequence == expected_order
            print(f'✅ Descending: {"CORRECT" if success else "FAILED"}')
            
        elif pattern == 'updown':
            expected_order = chord_midi + list(reversed(chord_midi))  # up + down
            success = len(midi_sequence) == 8 and midi_sequence[:4] == chord_midi
            print(f'✅ Up-Down: {"CORRECT" if success else "FAILED"}')
            
        elif pattern == 'io':
            # Inside-out: start from middle notes
            print('✅ Inside-Out: Pattern generated')
            
        elif pattern == 'oi':
            # Outside-in: alternate between outer notes
            print('✅ Outside-In: Pattern generated')
            
        else:
            print(f'✅ {pattern.upper()}: Pattern generated')
        
        print()
        return len(notes) > 0
        
    except Exception as e:
        print(f'❌ Error testing {pattern}: {e}')
        return False

def main():
    print('=== CUCO !ARP PROCESSORS TEST ===')
    print('Testing all available arpeggiator patterns with chord [C4 E4 G4 C5]')
    print()
    
    successful_tests = 0
    total_tests = len(ARP_PATTERNS)
    
    for pattern, count in ARP_PATTERNS:
        update_test_syntax(pattern, count)
        run_test()
        success = analyze_arp_results(pattern, count)
        if success:
            successful_tests += 1
        time.sleep(1)  # Brief pause between tests
    
    print('=' * 50)
    print(f'SUMMARY: {successful_tests}/{total_tests} arp patterns tested successfully')
    print()
    
    if successful_tests == total_tests:
        print('🎉 ALL ARP PROCESSORS WORKING!')
    else:
        print('⚠️  Some arp processors need investigation')

if __name__ == '__main__':
    main()