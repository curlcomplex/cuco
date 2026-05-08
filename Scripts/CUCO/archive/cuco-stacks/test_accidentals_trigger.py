#!/usr/bin/env python3
"""
Test script to verify that accidental parsing (sharps and flats) is working correctly
in CUCO-Stacks by creating MIDI items with accidental notes and checking the results.
"""

import os
import time
import subprocess
import tempfile

def create_test_midi_item(name_content, output_file):
    """Create a test MIDI item file with the given name content."""
    
    # Basic MIDI item content with the test name
    midi_content = f"""ITEM {{{output_file}
POSITION 0
LENGTH 4
NAME {name_content}
MUTE 0 0
BEAT -1
}}"""
    
    with open(output_file, 'w') as f:
        f.write(midi_content)
    
    print(f"Created test MIDI item: {output_file}")
    print(f"Content: {name_content}")

def main():
    # Test cases with accidentals
    test_cases = [
        "~4 c#4 d#4 e4 f#4",     # Sharp notes
        "~4 db4 eb4 f4 gb4",      # Flat notes  
        "~8 c4 c#4 db4 d4",       # Mixed naturals, sharps, flats
        "~4 [c4 c#4] [db4 d4]",   # Accidentals in stacks
    ]
    
    base_dir = "/Users/f.god/Library/Application Support/REAPER/Scripts/CUCO/CUCO-Stacks"
    
    for i, test_case in enumerate(test_cases, 1):
        print(f"\n{'='*60}")
        print(f"Test Case {i}: {test_case}")
        print('='*60)
        
        # Create unique timestamp to ensure watcher triggers
        timestamp = str(int(time.time() * 1000))
        test_name = f"{test_case} // accidental_test_{timestamp}"
        
        # Create test file
        test_file = os.path.join(base_dir, f"accidental_test_{i}_{timestamp}.mid")
        create_test_midi_item(test_name, test_file)
        
        # Wait a moment for file system
        time.sleep(0.5)
        
        print(f"Test file created: {test_file}")
        print("Check the MIDI item output in REAPER to verify accidentals are parsed correctly.")
        print("Expected behavior:")
        if "#" in test_case:
            print("- Sharp notes (c#4, d#4, f#4) should produce MIDI notes 61, 63, 66 respectively")
        if "b" in test_case and "b4" not in test_case:  # avoid matching b4 natural note
            print("- Flat notes (db4, eb4, gb4) should produce MIDI notes 61, 63, 66 respectively")
        
        # Small delay between tests
        time.sleep(1)

if __name__ == "__main__":
    main()