#!/usr/bin/env python3
"""
Test accidental parsing in REAPER by creating a MIDI item with sharps and flats
and triggering CUCO-Stacks to process it.
"""

import os
import time

def create_reaper_test_item():
    """Create a REAPER project file with MIDI item containing accidentals."""
    
    timestamp = str(int(time.time() * 1000))
    
    # Test case with both sharps and flats
    test_name = f"~4 c#4 d#4 eb4 f#4 gb4 a4 // accidental_test_{timestamp}"
    
    # Create a simple REAPER project with one MIDI item
    reaper_project = f"""<REAPER_PROJECT 0.1 "7.27/macOS-arm64" 1757869200
  RIPPLE 0
  GROUPOVERRIDE 0 0 0
  AUTOXFADE 129
  ENVATTACH 1
  POOLEDENVATTACH 0
  MIXERUIFLAGS 11 48
  PEAKGAIN 1
  FEEDBACK 0
  PANLAW 1
  PROJOFFS 0 0 0
  MAXPROJLEN 0 0
  GRID 3199 8 1 8 1 0 0 0
  TIMEMODE 1 5 -1 30 0 0 -1
  VIDEO_CONFIG 0 0 1000
  PANMODE 3
  CURSOR 0
  ZOOM 100 0 0
  VZOOMEX 6 0
  USE_REC_CFG 0
  RECMODE 1
  SMPTESYNC 0 30 100 40 1000 300 0 0 1 0 0
  <METRONOME 6 2
    VOL 0.25 0.125
    FREQ 800 1600 1
    BEATLEN 4
    SAMPLES "" ""
    PATTERN 2863311530 2863311529
    MULT 1
  >
  MASTERAUTOMODE 0
  MASTERTRACKHEIGHT 0 0
  MASTERPEAKCOL 16576
  MASTERMUTESOLO 0
  MASTERTRACKSEL 0
  MASTERHWOUT 0 0 1 0 0 0 0 -1
  MASTER_NCH 2 2
  MASTER_VOLUME 1
  MASTER_PANMODE 3
  MASTER_FX 1
  MASTER_SEL 0
  <MASTERPLAYSPEEDENV
    EGUID {{12345678-1234-5678-9012-123456789012}}
    ACT 0 -1
    VIS 0 1 1
    LANEHEIGHT 0 0
    ARM 0
    DEFSHAPE 0 -1 -1
  >
  <TEMPOENVEX
    EGUID {{12345678-1234-5678-9012-123456789013}}
    ACT 0 -1
    VIS 1 0 1
    LANEHEIGHT 0 0
    ARM 0
    DEFSHAPE 1 -1 -1
    PT 0 120 1
  >
  <TRACK {{12345678-1234-5678-9012-123456789014}}
    NAME "Test Track"
    PEAKCOL 16576
    BEAT -1
    AUTOMODE 0
    VOLPAN 1 0 -1 -1 1
    MUTESOLO 0 0 0
    IPHASE 0
    PLAYOFFS 0 1
    ISBUS 0 0
    BUSCOMP 0 0 0 0 0
    SHOWINMIX 1 0.6667 0.5 1 0.5 0 0 0
    FIXEDLANES 0 0
    SEL 1
    REC 0 0 1 0 0 0 0 0
    VU 2
    TRACKHEIGHT 0 0 0 0
    INQ 0 0 0 0.5 100 0 0 100
    NCHAN 2
    FX 1
    TRACKID {{12345678-1234-5678-9012-123456789015}}
    PERF 0
    MIDIOUT -1
    MAINSEND 1 0
    <ITEM
      POSITION 0
      SNAPOFFS 0
      LENGTH 4
      LOOP 1
      ALLTAKES 0
      FADEIN 1 0 0 1 0 0 0
      FADEOUT 1 0 0 1 0 0 0
      MUTE 0 0
      SEL 1
      IGUID {{12345678-1234-5678-9012-123456789016}}
      IID 1
      NAME {test_name}
      VOLPAN 1 0 1 -1
      SOFFS 0
      PLAYRATE 1 1 0 -1 0 0.0025
      CHANMODE 0
      GUID {{12345678-1234-5678-9012-123456789017}}
      <SOURCE MIDI
        HASDATA 1 960 QN
        E 0 90 3c 60
        E 480 80 3c 40
        E 480 90 3e 60
        E 960 80 3e 40
        E 960 90 40 60
        E 1440 80 40 40
        E 1440 90 41 60
        E 1920 80 41 40
      >
    >
  >
>"""
    
    # Write the project file
    project_file = f"/Users/f.god/Desktop/accidental_test_{timestamp}.rpp"
    with open(project_file, 'w') as f:
        f.write(reaper_project)
    
    print(f"Created REAPER project: {project_file}")
    print(f"MIDI Item Name: {test_name}")
    print("\nExpected behavior when CUCO-Stacks processes this:")
    print("- c#4 should produce MIDI note 61 (not 60)")
    print("- d#4 should produce MIDI note 63 (not 62)")  
    print("- eb4 should produce MIDI note 63 (not 64)")
    print("- f#4 should produce MIDI note 66 (not 65)")
    print("- gb4 should produce MIDI note 66 (not 67)")
    print("- a4 should produce MIDI note 69 (baseline natural note)")
    
    return project_file

def main():
    print("REAPER Accidental Parsing Test")
    print("=" * 50)
    
    project_file = create_reaper_test_item()
    
    print(f"\nInstructions:")
    print(f"1. Open REAPER")
    print(f"2. Open the project file: {project_file}")
    print(f"3. Select the MIDI item in the track")
    print(f"4. Make sure CUCO-Stacks watcher is running")
    print(f"5. Rename the MIDI item to trigger CUCO-Stacks processing")
    print(f"6. Check the resulting MIDI notes in the item")
    print(f"")
    print(f"If the fix is working correctly, you should see:")
    print(f"- Distinct pitches for c#4 (61), d#4 (63), eb4 (63), f#4 (66), gb4 (66)")
    print(f"- NO more systematic stripping of # and b symbols")
    print(f"- Proper chromatic progression instead of just natural notes")

if __name__ == "__main__":
    main()