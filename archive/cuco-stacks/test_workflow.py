#!/usr/bin/env python3
"""
Complete CUCO-Stacks Test Workflow
Handles proper script reloading and comprehensive testing

Usage:
    python3 test_workflow.py                    # Full test cycle
    python3 test_workflow.py --syntax "~8 c d e f"  # Custom test
"""

import sys
import os
import time
import argparse
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'osc_env/lib/python3.12/site-packages'))

from pythonosc import udp_client

class CUCOTestWorkflow:
    def __init__(self, reaper_host='192.168.178.38', reaper_port=8000):
        self.client = udp_client.SimpleUDPClient(reaper_host, reaper_port)
        
    def send_osc(self, message, delay=0.5):
        """Send OSC message with optional delay"""
        try:
            self.client.send_message(message, [])
            print(f"✓ Sent: {message}")
            if delay > 0:
                time.sleep(delay)
        except Exception as e:
            print(f"✗ Error sending {message}: {e}")
            
    def reload_cuco_stacks(self):
        """Properly reload CUCO-Stacks by toggling off then on"""
        print("🔄 Reloading CUCO-Stacks script...")
        self.send_osc('/action/cuco_stacks', delay=1.0)  # Turn off
        self.send_osc('/action/cuco_stacks', delay=1.0)  # Turn on
        print("✓ CUCO-Stacks reloaded")
        
    def set_test_syntax(self):
        """Set MIDI item name to test syntax"""
        print("📝 Setting test syntax...")
        self.send_osc('/action/cuco_test', delay=2.0)
        print("✓ Test syntax set")
        
    def process_with_cuco(self):
        """Process MIDI item with CUCO-Stacks"""
        print("⚙️  Processing with CUCO-Stacks...")
        self.send_osc('/action/cuco_stacks', delay=3.0)
        print("✓ CUCO processing complete")
        
    def export_results(self):
        """Export processed MIDI to CSV"""
        print("📊 Exporting results to CSV...")
        self.send_osc('/action/cuco_test', delay=1.0)
        print("✓ Results exported")
        
    def show_results(self):
        """Display CSV results"""
        csv_path = "/tmp/cuco_test_output.csv"
        try:
            with open(csv_path, 'r') as f:
                content = f.read()
            print("\n" + "="*80)
            print("📈 TEST RESULTS:")
            print("="*80)
            
            lines = content.strip().split('\n')
            if len(lines) > 1:
                # Show header
                headers = lines[0].split(',')
                print(f"{'#':<2} {'Note':<6} {'Start':<12} {'Duration':<10} {'Bar.Beat':<10} {'PPQ':<8}")
                print("-" * 60)
                
                # Show data rows
                for i, line in enumerate(lines[1:], 1):
                    parts = line.split(',')
                    if len(parts) >= 16:
                        note_name = parts[1]
                        start_time = float(parts[3])
                        duration = float(parts[5])
                        bar = parts[12]
                        beat = parts[13]
                        ppq = parts[7]
                        
                        print(f"{i:<2} {note_name:<6} {start_time:<12.6f} {duration:<10.6f} {bar}.{beat[:3]:<6} {ppq:<8}")
                        
                print(f"\nTotal notes: {len(lines)-1}")
            else:
                print("No MIDI data found in results")
                
        except FileNotFoundError:
            print(f"✗ CSV file not found: {csv_path}")
        except Exception as e:
            print(f"✗ Error reading results: {e}")
            
        print("="*80)
        
    def run_full_test(self):
        """Run complete test workflow"""
        print("🚀 Starting CUCO-Stacks Test Workflow...")
        print()
        
        # Step 1: Reload CUCO-Stacks to ensure fresh state
        self.reload_cuco_stacks()
        
        # Step 2: Set test syntax and initial export
        self.set_test_syntax()
        
        # Step 3: Process with CUCO-Stacks  
        self.process_with_cuco()
        
        # Step 4: Export final results
        self.export_results()
        
        # Step 5: Display results
        self.show_results()
        
        print("\n🎵 Test workflow complete!")

def main():
    parser = argparse.ArgumentParser(description='CUCO-Stacks Test Workflow')
    parser.add_argument('--syntax', type=str, help='Custom CUCO syntax to test (updates script)')
    parser.add_argument('--no-reload', action='store_true', help='Skip CUCO-Stacks reload step')
    
    args = parser.parse_args()
    
    if args.syntax:
        # Update the test script with custom syntax
        script_path = "/Users/f.god/Library/Application Support/REAPER/Scripts/CUCO/CUCO-Stacks/CUCO_Test_Trigger.lua"
        try:
            with open(script_path, 'r') as f:
                content = f.read()
            
            # Replace the TEST_SYNTAX line
            import re
            pattern = r'local TEST_SYNTAX = ".*?"'
            replacement = f'local TEST_SYNTAX = "{args.syntax}"'
            new_content = re.sub(pattern, replacement, content)
            
            with open(script_path, 'w') as f:
                f.write(new_content)
                
            print(f"✓ Updated test syntax to: {args.syntax}")
            print("  (Remember to reload the test script in REAPER)")
            
        except Exception as e:
            print(f"✗ Error updating syntax: {e}")
            return
    
    # Run the workflow
    workflow = CUCOTestWorkflow()
    
    if not args.no_reload:
        workflow.run_full_test()
    else:
        # Skip reload, just run test
        print("🚀 Running test without reload...")
        workflow.set_test_syntax()
        workflow.process_with_cuco()
        workflow.export_results()
        workflow.show_results()

if __name__ == "__main__":
    main()