#!/usr/bin/env python3
"""Dialogue Prep: De-crackle + HPF + setting-E clip gain on every active dialogue clip of an open REAPER project.

    python3 dialogue_prep.py --project EP4_MAIN --tracks 5,9 --tag EP4

--project is any part of the open tab's file path. Each clip gets a new active take
<source>_RX_<tag>-NN.wav (RX 11 De-crackle on the source region with handles, then a 2-pole HPF),
then the setting-E item gain + take volume envelope. Originals stay as the take underneath.
Clips whose active take is already an _RX_ take are skipped, so a rerun only does new clips.
Needs REAPER running, RX 11 De-crackle (VST3), ffmpeg/ffprobe and numpy.
"""
import argparse
import datetime
import os
import subprocess
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "modules"))
from levels import load  # noqa: E402
import setting_e  # noqa: E402

REAPER = os.environ.get("REAPER_BIN", "/Applications/REAPER.app/Contents/MacOS/REAPER")
JOBS = os.path.expanduser("~/.cuco/dialogue-prep")
FRAGMENT = 0.5   # clips shorter than this (s) are too short to measure: they borrow a neighbour's item gain


def step(job, name, timeout):
    """Run steps/dp_<name>.lua in the running REAPER and wait for its DONE/ABORT status."""
    status = os.path.join(job, name + ".status")
    if os.path.exists(status):
        os.remove(status)
    subprocess.Popen([REAPER, "-nonewinst", os.path.join(HERE, "steps", f"dp_{name}.lua")],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    end = time.time() + timeout
    while time.time() < end:
        if os.path.exists(status):
            msg = open(status).read().strip()
            if msg:
                print(f"  {name}: {msg}")
                if not msg.startswith("DONE"):
                    sys.exit(f"stopped at {name}")
                return msg
        time.sleep(0.5)
    sys.exit(f"stopped: {name} gave no status after {timeout} s")


def rows(path):
    return [line.rstrip("\n").split("\t") for line in open(path)]


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def lag(src, chan, a, render, length):
    """Sample offset between the render and its source region (1 s from the middle); 0 when aligned."""
    x, y = load(src, a, length, chan), load(render, 0, length)
    m = min(len(x), len(y))
    seg = slice(max(m // 2 - 24000, 0), m // 2 + 24000)
    c = np.correlate(y[seg], x[seg][1000:-1000], "valid")
    return int(np.argmax(np.abs(c))) - 1000


def borrow_gain(clip, planned):
    """Item gain of the nearest measured clip on the same track (0 dB if there is none)."""
    same = [p for p in planned if p["tn"] == clip["tn"]] or planned
    if not same:
        return 0.0
    return min(same, key=lambda p: abs(p["pos"] - clip["pos"]))["item_db"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", required=True, help="part of the open project's file path, e.g. EP4_MAIN")
    ap.add_argument("--tracks", required=True, help="track numbers holding dialogue, e.g. 5,9")
    ap.add_argument("--tag", required=True, help="name tag for the cleaned files, e.g. EP4")
    ap.add_argument("--rx-dir", help="where cleaned files go (default: <project dir>/Media/Dialogue RX)")
    ap.add_argument("--handle", type=float, default=5.0, help="De-crackle handle each side (s)")
    ap.add_argument("--quality", default="high", choices=["low", "medium", "high"])
    ap.add_argument("--decrackle", type=float, default=4.0, help="De-crackle strength 1-10")
    ap.add_argument("--plugin", default="RX 11 De-crackle")
    ap.add_argument("--hpf", type=float, default=40.0, help="high-pass frequency (Hz)")
    ap.add_argument("--strength", type=float, default=0.4, help="setting-E strength")
    ap.add_argument("--ceiling", type=float, default=50.0, help="setting-E ceiling percentile")
    a = ap.parse_args()

    job = os.path.join(JOBS, f"{a.tag}-{datetime.datetime.now():%y%m%d-%H%M%S}")
    os.makedirs(os.path.join(job, "renders"))
    os.makedirs(os.path.join(job, "plans"))
    blank = os.path.join(job, "dp_blank.RPP")
    open(blank, "w").write('<REAPER_PROJECT 0.1 "7.0" 0\n>\n')
    open(os.path.join(job, "job.txt"), "w").write(
        f"project={a.project}\ntracks={a.tracks}\nblank={blank}\nplugin={a.plugin}\nquality={a.quality}\nstrength={a.decrackle:g}\n")
    open(os.path.join(JOBS, "current.txt"), "w").write(job + "\n")
    print(f"job {job}")

    step(job, "dump", 30)
    clips = [dict(id=r[0], tn=int(r[1]), k=int(r[2]), pos=float(r[3]), len=float(r[4]), offs=float(r[5]),
                  rate=float(r[6]), cm=int(float(r[7])), src=r[8]) for r in rows(os.path.join(job, "clips.tsv"))]
    if not clips:
        return print("nothing to do")
    odd = [c["id"] for c in clips if c["rate"] != 1]
    if odd:
        sys.exit(f"stopped: playrate is not 1 on {', '.join(odd)}; handles assume 1")
    rx_dir = a.rx_dir or os.path.join(os.path.dirname(open(os.path.join(job, "project.txt")).read().strip()), "Media", "Dialogue RX")
    os.makedirs(rx_dir, exist_ok=True)

    # step 2-4: De-crackle each source region with handles, rendered in a scratch tab
    with open(os.path.join(job, "regions.tsv"), "w") as fo:
        for c in clips:
            c["a"] = max(0.0, c["offs"] - a.handle)
            c["b"] = min(duration(c["src"]), c["offs"] + c["len"] + a.handle)
            fo.write(f"{c['id']}\t{c['src']}\t{c['cm']}\t{c['a']}\t{c['b']}\n")
    step(job, "rx_build", 60)
    step(job, "rx_params", 30)
    step(job, "rx_render", 120 + sum(c["b"] - c["a"] for c in clips))
    renders = dict(rows(os.path.join(job, "renders.tsv")))

    # step 5: check alignment, high-pass into the final file
    with open(os.path.join(job, "rx_map.tsv"), "w") as fo:
        for n, c in enumerate(clips):
            chan = c["cm"] - 2 if c["cm"] >= 3 else 0   # I_CHANMODE 3.. = mono channel 1..
            off = lag(c["src"], chan, c["a"], renders[c["id"]], c["b"] - c["a"])
            if off:
                sys.exit(f"stopped: render of {c['id']} is {off} samples off its source; nothing added to the project")
            c["file"] = os.path.join(rx_dir, f"{os.path.splitext(os.path.basename(c['src']))[0]}_RX_{a.tag}-{n:02d}.wav")
            if os.path.exists(c["file"]):
                sys.exit(f"stopped: {c['file']} already exists; use another --tag")
            subprocess.run(["ffmpeg", "-v", "error", "-i", renders[c["id"]], "-af", f"highpass=f={a.hpf:g}:poles=2",
                            "-c:a", "pcm_s24le", c["file"]], check=True)
            c["handle"] = c["offs"] - c["a"]
            fo.write(f"{c['id']}\t{c['tn']}\t{c['k']}\t{c['pos']}\t{c['file']}\t{c['handle']}\n")
    print(f"  hpf: {len(clips)} files in {rx_dir}, all aligned")
    step(job, "add_takes", 60)

    # step 6-7: plan setting E, fragments borrow a neighbour's item gain, apply
    planned = []
    for c in clips:
        if c["len"] >= FRAGMENT:
            p = setting_e.plan(c["file"], c["handle"], c["len"], a.strength, a.ceiling)
            c.update(p)
            planned.append(c)
    for c in clips:
        if c["len"] < FRAGMENT:
            c.update(item_db=borrow_gain(c, planned), pts=[(0.0, 1.0)], fragment=True)
    with open(os.path.join(job, "plans.tsv"), "w") as fi:
        for n, c in enumerate(clips):
            path = os.path.join(job, "plans", f"{n:03d}.txt")
            open(path, "w").write(f"{c['tn']} {c['k']} {c['item_db']}\n" + "".join(f"{t:.5f} {v:.6f}\n" for t, v in c["pts"]))
            fi.write(path + "\n")
    step(job, "apply_gain", 60)

    print(f"\n{'clip':6} {'at':>8} {'len':>6} {'item':>7} {'pts':>4}  spread400")
    for c in clips:
        note = "fragment: neighbour's gain, no line" if c.get("fragment") else f"{c['spread_before']:.1f} -> {c['spread_after']:.1f} dB, deepest cut {c['deepest_cut']:.1f}"
        print(f"{c['id']:6} {c['pos']:8.2f} {c['len']:6.2f} {c['item_db']:+6.1f} {len(c['pts']):4}  {note}")


if __name__ == "__main__":
    main()
