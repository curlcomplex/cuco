#!/usr/bin/env python3
"""
Script to test all available scales in CUCO Stacks systematically.

This script will:
1. Test each scale with a note that should be quantized (c#4)
2. Run the test and capture the CSV output
3. Summarize the results for each scale
"""

import subprocess
import time
import csv
import os

# List of scales to test (from CUCO Stacks.lua)
SCALES_TO_TEST = [
    # Western Traditional
    "major", "minor", "dorian", "phrygian", "lydian", "mixolydian", "locrian",
    "harmonic", "melodic", "pentatonic", "blues", "chromatic",
    
    # Middle Eastern & Arabic
    "maqam_hijaz", "maqam_rast", "maqam_bayati", "maqam_saba", "maqam_kurd",
    "persian", "double_harmonic",
    
    # Asian Traditional
    "japanese", "kumoi", "iwato", "in_sen", "yo", "chinese", "mongolian",
    "pelog", "slendro",
    
    # Indian Classical
    "raga_bilawal", "raga_kafi", "raga_bhairav", "raga_malkauns", "raga_yaman",
    "raga_bhimpalasi",
    
    # African Traditional
    "african_pentatonic", "ethiopian", "west_african", "pygmy", "saharan",
    
    # European Folk
    "gypsy", "hungarian_minor", "neapolitan_minor", "ukrainian_dorian", "flamenco",
    
    # Exotic & Experimental
    "whole_tone", "diminished", "augmented", "prometheus", "tritone",
    "enigmatic", "super_locrian", "bebop_dominant"
]

CSV_PATH = "/tmp/cuco_test_output.csv"
TEST_TRIGGER_PATH = "/Users/f.god/Library/Application Support/REAPER/Scripts/CUCO/CUCO-Stacks/CUCO_Test_Trigger.lua"

def update_test_syntax(scale_name):
    """Update the test syntax in CUCO_Test_Trigger.lua"""
    test_syntax = f"~4 @c.{scale_name}.near c#4"
    
    with open(TEST_TRIGGER_PATH, 'r') as f:
        content = f.read()
    
    # Replace the TEST_SYNTAX line
    lines = content.split('\n')
    for i, line in enumerate(lines):
        if line.startswith('local TEST_SYNTAX ='):
            lines[i] = f'local TEST_SYNTAX = "{test_syntax}"'
            break
    
    with open(TEST_TRIGGER_PATH, 'w') as f:
        f.write('\n'.join(lines))

def run_test():
    """Run the CUCO test via OSC"""
    subprocess.run(['oscsend', '192.168.178.38', '8000', '/action/cuco_test'], 
                   capture_output=True, text=True)
    time.sleep(1)  # Wait for processing

def read_csv_result():
    """Read the CSV result and return the note info"""
    try:
        with open(CSV_PATH, 'r') as f:
            reader = csv.DictReader(f)
            row = next(reader)
            return {
                'note_number': int(row['note_number']),
                'note_name': row['note_name']
            }
    except:
        return {'note_number': None, 'note_name': 'ERROR'}

def test_scale(scale_name):
    """Test a single scale"""
    print(f"Testing scale: {scale_name}")
    
    # Update test syntax
    update_test_syntax(scale_name)
    
    # Run test
    run_test()
    
    # Read result
    result = read_csv_result()
    
    return result

def main():
    print("=== CUCO Scales Testing ===")
    print("Input note: c#4 (MIDI 61)")
    print("Root: C")
    print("Quantization: near")
    print()
    
    results = []
    
    for scale in SCALES_TO_TEST:
        try:
            result = test_scale(scale)
            results.append({
                'scale': scale,
                'input_midi': 61,
                'input_note': 'C#4',
                'output_midi': result['note_number'],
                'output_note': result['note_name'],
                'changed': result['note_number'] != 61 if result['note_number'] else 'ERROR'
            })
            
            change_status = "CHANGED" if result['note_number'] != 61 else "UNCHANGED"
            print(f"  {scale:20} -> {result['note_name']:4} (MIDI {result['note_number']}) [{change_status}]")
            
        except Exception as e:
            print(f"  {scale:20} -> ERROR: {e}")
            results.append({
                'scale': scale,
                'input_midi': 61,
                'input_note': 'C#4',
                'output_midi': None,
                'output_note': 'ERROR',
                'changed': 'ERROR'
            })
        
        time.sleep(0.5)  # Pause between tests
    
    print("\n=== Summary ===")
    changed_count = sum(1 for r in results if r['changed'] == True)
    unchanged_count = sum(1 for r in results if r['changed'] == False)
    error_count = sum(1 for r in results if r['changed'] == 'ERROR')
    
    print(f"Total scales tested: {len(results)}")
    print(f"Scales that quantized C#4: {changed_count}")
    print(f"Scales that kept C#4: {unchanged_count}")
    print(f"Errors: {error_count}")
    
    # Show scales that kept C#4 (chromatic-like)
    unchanged_scales = [r['scale'] for r in results if r['changed'] == False]
    if unchanged_scales:
        print(f"\nScales that preserved C#4: {', '.join(unchanged_scales)}")

if __name__ == "__main__":
    main()