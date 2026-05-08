#!/usr/bin/env python3
"""
Simple CUCO Test Trigger via OSC
Sends /action/cuco_test to REAPER to trigger the test script
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'osc_env/lib/python3.12/site-packages'))

from pythonosc import udp_client
import time

def trigger_cuco_test():
    """Send OSC message to trigger CUCO test in REAPER"""
    client = udp_client.SimpleUDPClient('192.168.178.38', 8000)
    
    print("Triggering CUCO test via OSC...")
    try:
        client.send_message('/action/cuco_test', [])
        print("✓ OSC message sent to REAPER")
        print("Check REAPER console for test results")
        print("CSV output: /tmp/cuco_test_output.csv")
    except Exception as e:
        print(f"✗ Error sending OSC message: {e}")

if __name__ == "__main__":
    trigger_cuco_test()