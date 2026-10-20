#!/usr/bin/env python3
"""Cut Markers: picture-cut markers in an open REAPER project, from the edit's FCP XML.

    python3 cut_markers.py --xml "Cutdown.xml" --video "Cutdown.mp4" --project EP4_CUTDOWN --clear

A cut is any clip edge on a picture track. Tracks above V1 covering >= 90% of the sequence are
overlays (grain, backgrounds) and are ignored. With --video each cut is checked against ffmpeg's scene
score: visible -> "CUT", not visible -> "CUT?" (a same-shot split, a cut hidden under a graphic).
Markers go in as one undo step; the project is not saved. --clear removes all markers first (regions stay).
"""
import argparse
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
REAPER = os.environ.get("REAPER_BIN", "/Applications/REAPER.app/Contents/MacOS/REAPER")
JOB = os.path.expanduser("~/.cuco/cut-markers")
OVERLAY = 0.9    # a track covering this share of the sequence is an overlay, not picture
VISIBLE = 0.1    # ffmpeg scene score at the cut frame that counts as a visible change


def read_xml(path):
    """(fps, duration in frames, video tracks as [[(start, end), ...], ...] bottom to top) of the first sequence."""
    seq = next(ET.parse(path).getroot().iter("sequence"))
    fps = int(seq.findtext("rate/timebase"))
    if seq.findtext("rate/ntsc") == "TRUE":
        sys.exit("stopped: NTSC timebase; frame maths assume integer fps")
    tracks = [[(int(c.findtext("start")), int(c.findtext("end"))) for c in t.findall("clipitem")]
              for t in seq.find("media/video").findall("track")]
    return fps, int(seq.findtext("duration")), tracks


def cuts(tracks, dur):
    """Frames (excluding 0 and the end) where any picture clip starts or ends.

    Picture = the bottom track plus every track above it covering < OVERLAY of the sequence.
    Edges hidden under a clip above are kept; the scene check marks them CUT?.
    """
    # ponytail: coverage decides overlay; a picture track above V1 covering >= 90% would be missed, add a name/track flag if one turns up
    pic = tracks[:1] + [t for t in tracks[1:] if sum(b - a for a, b in t) < OVERLAY * dur]
    return sorted({e for t in pic for c in t for e in c if 0 < e < dur})


def scene_scores(video):
    """{frame time rounded to ms: ffmpeg scene score} for every frame of the video."""
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", video, "-an", "-vf",
                          "select='gte(scene,0)',metadata=print:file=-", "-f", "null", "-"],
                         capture_output=True, text=True, check=True).stdout
    t = [float(x) for x in re.findall(r"pts_time:([\d.]+)", out)]
    s = [float(x) for x in re.findall(r"scene_score=([\d.]+)", out)]
    return {round(a, 3): b for a, b in zip(t, s)}


def duration(video):
    return float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", video],
                                capture_output=True, text=True, check=True).stdout)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--xml", required=True, help="FCP 7 XML (xmeml) of the edit")
    ap.add_argument("--video", help="the edit's rendered video, to check each cut is visible")
    ap.add_argument("--project", required=True, help="part of the open project tab's file path")
    ap.add_argument("--offset", type=float, default=0.0, help="project time of the edit's first frame (s)")
    ap.add_argument("--clear", action="store_true", help="remove all existing markers first (regions stay)")
    a = ap.parse_args()

    fps, dur, tracks = read_xml(a.xml)
    frames = cuts(tracks, dur)
    names = ["CUT"] * len(frames)
    if a.video:
        if abs(duration(a.video) - dur / fps) > 1.5 / fps:
            sys.exit(f"stopped: XML is {dur / fps:.2f} s but the video is {duration(a.video):.2f} s; wrong version?")
        sc = scene_scores(a.video)
        names = ["CUT" if sc.get(round(f / fps, 3), 0) >= VISIBLE else "CUT?" for f in frames]

    os.makedirs(JOB, exist_ok=True)
    status = os.path.join(JOB, "status")
    if os.path.exists(status):
        os.remove(status)
    with open(os.path.join(JOB, "job.txt"), "w") as fo:
        fo.write(f"project={a.project}\nclear={int(a.clear)}\n")
        fo.writelines(f"{a.offset + f / fps:.6f}\t{n}\n" for f, n in zip(frames, names))
    subprocess.Popen([REAPER, "-nonewinst", os.path.join(HERE, "cm_place.lua")],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    end = time.time() + 30
    while time.time() < end and not (os.path.exists(status) and open(status).read().strip()):
        time.sleep(0.3)
    msg = open(status).read().strip() if os.path.exists(status) else "no status after 30 s"
    print(msg)
    for f, n in zip(frames, names):
        print(f"  {f / fps:7.2f}  {n}")
    if not msg.startswith("DONE"):
        sys.exit(1)


if __name__ == "__main__":
    main()
