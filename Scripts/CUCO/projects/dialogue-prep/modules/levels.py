"""Audio loading and short-term level helpers shared by the planner and the driver."""
import subprocess

import numpy as np

SR = 48000
HOP = 0.05   # 50 ms
WIN = 0.4    # 400 ms short-term window


def load(path, start, length, chan=0):
    """Mono float audio of source[start:start+length]; chan is 1-based (0 = mix of all channels)."""
    cmd = ["ffmpeg", "-v", "error", "-ss", f"{max(start, 0):.6f}", "-t", f"{length:.6f}", "-i", path]
    cmd += ["-af", f"pan=mono|c0=c{chan - 1}"] if chan else ["-ac", "1"]
    cmd += ["-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, np.float32).astype(np.float64)


def frames(x, win=WIN):
    """Short-term RMS level (dBFS) every HOP with a WIN window, after a 100 Hz high-pass."""
    X = np.fft.rfft(x)
    X[np.fft.rfftfreq(len(x), 1 / SR) < 100] = 0
    y = np.fft.irfft(X, len(x))
    w, h = int(win * SR), int(HOP * SR)
    return np.array([20 * np.log10(np.sqrt(np.mean(y[i:i + w] ** 2)) + 1e-9) for i in range(0, max(len(y) - w, 1), h)])


def speech(levels, floor=-55, rel=25):
    """Mask of frames that are speech: above an absolute floor and within rel dB of the loudest."""
    return (levels > floor) & (levels > levels.max() - rel)
