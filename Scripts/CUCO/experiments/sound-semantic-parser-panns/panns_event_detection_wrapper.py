import subprocess
import os
from pathlib import Path
from datetime import datetime

def get_timestamp():
    return datetime.now().strftime("%Y%m%d_%H%M%S")

def run_event_detection(audio_path, checkpoint_path, script_path, cuda=False):
    """Run the PANNs event detection script on a single file and return its output."""
    cmd = [
        "python", str(script_path),
        "--audio_path", str(audio_path),
        "--checkpoint_path", str(checkpoint_path),
        "--cuda", "True" if cuda else "False"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout

def batch_event_detection(
    folder,
    checkpoint_path,
    script_path,
    out_csv=None,
    cuda=False
):
    folder = Path(folder)
    if out_csv is None:
        out_csv = str(folder / f"event_detection_results_{get_timestamp()}.csv")
    results = []
    for wav in folder.rglob("*.wav"):
        print(f"Processing: {wav.name}")
        output = run_event_detection(wav, checkpoint_path, script_path, cuda=cuda)
        # Parse output lines for events (example: [start - end] label)
        for line in output.splitlines():
            if "]" in line and "[" in line:
                try:
                    time_part, label = line.split("]")
                    time_part = time_part.strip("[ ")
                    start, end = [float(t) for t in time_part.split("-")]
                    label = label.strip()
                    results.append((wav.name, start, end, label))
                except Exception:
                    continue
    # Write results to CSV
    with open(out_csv, "w", encoding="utf-8") as f:
        f.write("filename,start,end,label\n")
        for row in results:
            f.write(f"{row[0]},{row[1]},{row[2]},{row[3]}\n")
    print(f"[ok] Wrote batch event detection CSV: {out_csv}")

def run_tagging(audio_path, checkpoint_path, script_path, cuda=False):
    """Run the PANNs tagging script on a single file and return its output."""
    cmd = [
        "python", str(script_path),
        "--audio_path", str(audio_path),
        "--checkpoint_path", str(checkpoint_path),
        "--cuda", "True" if cuda else "False"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout

def batch_tagging(
    folder,
    checkpoint_path,
    script_path,
    out_csv=None,
    cuda=False
):
    folder = Path(folder)
    if out_csv is None:
        out_csv = str(folder / f"file_tagging_results_{get_timestamp()}.csv")
    results = []
    for wav in folder.rglob("*.wav"):
        print(f"Processing: {wav.name}")
        output = run_tagging(wav, checkpoint_path, script_path, cuda=cuda)
        # Parse output lines for tags (example: "Speech: 0.85")
        tags = []
        for line in output.splitlines():
            if ":" in line:
                label, prob = line.split(":")
                label = label.strip()
                prob = float(prob.strip())
                if prob > 0.1:  # Only include tags above threshold
                    tags.append(label)
        results.append((wav.name, "; ".join(tags)))
    # Write results to CSV
    with open(out_csv, "w", encoding="utf-8") as f:
        f.write("filename,tags\n")
        for row in results:
            f.write(f"{row[0]},{row[1]}\n")
    print(f"[ok] Wrote batch file tagging CSV: {out_csv}")

if __name__ == "__main__":
    folder = "/Volumes/CUCO Works/4 Sound Archive/ipad/test"
    checkpoint_path = "/Users/f.god/audioset_tagging_cnn/models/Cnn14_DecisionLevelAtt_mAP=0.425.pth"
    script_path = "/Users/f.god/audioset_tagging_cnn/pytorch/inference.py"  # or sound_event_detection.py if present

    batch_event_detection(folder, checkpoint_path, script_path)
    batch_tagging(folder, checkpoint_path, script_path)