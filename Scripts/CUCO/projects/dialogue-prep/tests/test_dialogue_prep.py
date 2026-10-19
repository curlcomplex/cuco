"""Self-checks for the planner and the fragment rule. Run: python3 tests/test_dialogue_prep.py (needs ffmpeg + numpy)."""
import os
import sys
import tempfile
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "modules"))
import setting_e  # noqa: E402
from dialogue_prep import borrow_gain  # noqa: E402
from levels import SR  # noqa: E402


def synthetic_speech(path):
    """6 s of syllable-like noise bursts around -35 dBFS, one burst 10 dB hot at 3 s."""
    rng = np.random.default_rng(1)
    t = np.arange(6 * SR) / SR
    env = np.clip(np.sin(2 * np.pi * 4 * t), 0, None) ** 2
    x = rng.standard_normal(len(t)) * env * 10 ** (-35 / 20) * 2
    x[(t > 2.9) & (t < 3.15)] *= 10 ** (10 / 20)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def test_plan_cuts_only_and_catches_the_hot_burst():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "speech.wav")
        synthetic_speech(p)
        r = setting_e.plan(p, 0, 6.0)
    amps = [a for _, a in r["pts"]]
    assert max(amps) <= 1 + 1e-9, "the line must never boost"
    at3 = np.interp(3.0, [t for t, _ in r["pts"]], amps)
    assert 20 * np.log10(at3) < -2, f"hot burst not pulled down ({20 * np.log10(at3):.1f} dB)"
    assert r["item_db"] > 0, "quiet speech should get an item gain boost"


def test_fragment_borrows_nearest_clip_on_same_track():
    planned = [{"tn": 5, "pos": 0.0, "item_db": 3.0}, {"tn": 5, "pos": 10.0, "item_db": 7.0},
               {"tn": 9, "pos": 8.0, "item_db": 1.0}]
    assert borrow_gain({"tn": 5, "pos": 8.5}, planned) == 7.0
    assert borrow_gain({"tn": 12, "pos": 8.5}, planned) == 1.0   # no clip on its track: nearest anywhere
    assert borrow_gain({"tn": 5, "pos": 1.0}, []) == 0.0


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
