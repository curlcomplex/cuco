#!/usr/bin/env python3
"""
Simple OSC sender for triggering CUCO tests
Usage: python3 osc_sender.py /action/cuco_test
"""

import socket
import struct
import sys

def send_osc_message(host, port, address):
    """Send a simple OSC message without external dependencies"""
    
    # Create OSC message
    address_bytes = address.encode('utf-8')
    address_length = len(address_bytes)
    
    # Pad address to multiple of 4 bytes
    padding = (4 - (address_length % 4)) % 4
    address_padded = address_bytes + b'\x00' * (padding + 1)
    
    # Type tag string (just empty for simple message)
    type_tag = b',\x00\x00\x00'
    
    # Combine message
    message = address_padded + type_tag
    
    # Send via UDP
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.sendto(message, (host, port))
        print(f"Sent OSC message '{address}' to {host}:{port}")
        return True
    except Exception as e:
        print(f"Error sending OSC message: {e}")
        return False
    finally:
        sock.close()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 osc_sender.py <osc_address>")
        print("Example: python3 osc_sender.py /action/cuco_test")
        sys.exit(1)
    
    osc_address = sys.argv[1]
    success = send_osc_message("192.168.178.38", 8000, osc_address)
    sys.exit(0 if success else 1)