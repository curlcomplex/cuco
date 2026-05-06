#!/usr/bin/env python3
"""
Send an OSC message to Reaper to trigger a CUCO-OP test.

Usage:
    python3 tools/send_osc_test.py <test_name>
        [--host 192.168.178.38] [--port 8000]
        [--osc-mode float|string|none]
        [--root "/Users/.../REAPER/Scripts/CUCO/CUCO-OP"]

Notes:
- Defaults to float OSC arg for robust OSC Learn mappings.
- Verifies the CUCO-OP root and tests folder before writing token files to avoid bad paths.
"""
import argparse
import socket
import struct
import sys
from pathlib import Path
from typing import Optional, Tuple

def osc_str(s: str) -> bytes:
    b = s.encode("utf-8") + b"\x00"
    pad = (4 - (len(b) % 4)) % 4
    return b + (b"\x00" * pad)

def build_osc_message(address: str, arg_mode: str, arg_value: str) -> bytes:
    # address
    msg = osc_str(address)
    if arg_mode == "float":
        msg += osc_str(",f")
        # use 1.0 as a trigger value
        msg += struct.pack(">f", 1.0)
    elif arg_mode == "string":
        msg += osc_str(",s")
        msg += osc_str(arg_value)
    elif arg_mode == "none":
        msg += osc_str(",")  # no args
    else:
        raise ValueError(f"Unknown arg_mode: {arg_mode}")
    return msg

def resolve_root(cli_root: Optional[str]) -> Path:
    if cli_root:
        return Path(cli_root).expanduser().resolve()
    # Root is parent of this script: .../CUCO-OP/
    return Path(__file__).resolve().parent.parent

def verify_root(root: Path) -> Tuple[Path, Path]:
    tests_dir = root / "tests"
    # Guardrails: require an expected seed file to exist
    seed = tests_dir / "rhythm_basic.lua"
    if not tests_dir.exists() or not seed.exists():
        print("Error: tests folder or seed test not found.")
        print(" Checked:", tests_dir)
        print(" Seed test:", seed)
        print(" Hint: pass --root to set the correct CUCO-OP folder.")
        sys.exit(2)
    return root, tests_dir


def main():
    p = argparse.ArgumentParser()
    p.add_argument("test_name", help="Name of the test to run (e.g., rhythm_basic)")
    p.add_argument("--host", default="127.0.0.1", help="Reaper OSC host")
    p.add_argument("--port", type=int, default=8000, help="Reaper OSC port")
    p.add_argument("--osc-mode", default="float", choices=["float", "string", "none"], help="OSC argument mode")
    p.add_argument("--root", help="Explicit CUCO-OP root folder (defaults to this script's parent)")
    args = p.parse_args()

    # Resolve and verify root to avoid bad path typos
    root = resolve_root(args.root)
    root, tests_dir = verify_root(root)
    token_path = tests_dir / "__next_test__.txt"
    try:
        with open(token_path, "w", encoding="utf-8") as f:
            f.write(args.test_name + "\n")
    except Exception as e:
        print(f"Error: couldn't write token file {token_path}: {e}")
        sys.exit(3)

    msg = build_osc_message("/cuco/test/run", args.osc_mode, args.test_name)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.sendto(msg, (args.host, args.port))
    print("CUCO-OP root:", root)
    print("Token:", token_path)
    print(f"Sent OSC /cuco/test/run ({args.osc_mode}) to {args.host}:{args.port}")

    # Wait briefly for test execution and try to read ExtState plan data
    import time
    import json
    time.sleep(3)

    try:
        import subprocess
        # Use osascript to read ExtState from REAPER (macOS AppleScript)
        script = '''
        tell application "REAPER"
            set extState to (do shell script "echo 'reaper.GetExtState(\"CUCO\", \"LAST_PLAN\"); reaper.GetExtState(\"CUCO\", \"LAST_TEST_NAME\")' | nc localhost 40001" with timeout of 5 seconds)
        end tell
        '''
        # For now, just indicate that ExtState reading would happen here
        print("ExtState reading: would read LAST_PLAN and LAST_TEST_NAME from REAPER ExtState")
        print("(ExtState integration requires REAPER scripting API access or file-based bridge)")
    except Exception as e:
        print(f"ExtState read attempt failed: {e}")

    # Also show latest artifact if available
    try:
        artifacts_dir = root / "tests" / "__artifacts__"
        if artifacts_dir.exists():
            json_files = list(artifacts_dir.glob(f"{args.test_name}_*.json"))
            if json_files:
                latest = max(json_files, key=lambda p: p.stat().st_mtime)
                with open(latest) as f:
                    artifact_data = json.load(f)
                print(f"Latest artifact: {latest.name}")
                print(f"Result: {artifact_data}")
    except Exception as e:
        print(f"Artifact read failed: {e}")


if __name__ == "__main__":
    main()
