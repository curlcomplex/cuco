#!/usr/bin/env python3
"""
CUCO-Stacks Processing Trigger via OSC
Sends /action/cuco_stacks to REAPER to run CUCO-Stacks processing
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'osc_env/lib/python3.12/site-packages'))

from pythonosc import udp_client
import time

def trigger_cuco_stacks():
    """Send OSC message to run CUCO-Stacks processing in REAPER"""
    client = udp_client.SimpleUDPClient('192.168.178.38', 8000)
    
    print("Running CUCO-Stacks processing via OSC...")
    try:
        client.send_message('/action/cuco_stacks', [])
        print("✓ OSC message sent to REAPER")
        print("CUCO-Stacks should now process the selected MIDI item")
    except Exception as e:
        print(f"✗ Error sending OSC message: {e}")

if __name__ == "__main__":
    trigger_cuco_stacks()