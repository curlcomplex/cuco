"""Setting E: a cut-only clip gain line plus an item gain boost, approved by ear on Check This EP3/EP4 (2026-10-19).

Two stacked cut layers, both scaled by STRENGTH:
  slow : cut speech above a ceiling (the clip's p50 400 ms level), 0.4 s glides -> sentence/cadence ramps
  fast : pull 20 ms peaks more than 2 dB over the surrounding syllables down to them; a resonant peak
         (a 1-5 kHz third-octave band's share of the level jumps >= 8 dB) goes a further 2 dB below; 0.06 s glides
The line never boosts. The item gain lands the speech median at TARGET; the compressor does the rest.
"""
import numpy as np

from levels import SR, frames, load, speech

TARGET = -26.9          # median speech level after gain (dBFS, 400 ms), matched to the EP2 mix
SLOW_GLIDE, FAST_GLIDE = 0.4, 0.06
PEAK_OVER = 2.0         # dB over surrounding syllables before the fast layer cuts
RES_JUMP = 8.0          # band-share jump that marks a resonance
RES_EXTRA = 2.0         # resonant peaks go this far below their surroundings
SPAN = 0.4              # surrounding-syllable window (s each side, excluding +-0.1 s)
TOL = 0.6               # envelope simplification tolerance (dB)
STEP = 0.005


def plan(path, offs, ln, strength=0.4, ceil_pct=50):
    """Plan one clip. Returns item gain (dB), envelope points [(t, amplitude)], and before/after stats."""
    x0 = load(path, offs, ln)
    n = int(ln / STEP) + 1
    tg = np.arange(n) * STEP
    X = np.fft.rfft(x0)
    X[np.fft.rfftfreq(len(x0), 1 / SR) < 100] = 0
    hp = np.fft.irfft(X, len(x0))

    def level(sig, win):
        c = np.concatenate([[0], np.cumsum(sig ** 2)])
        w = int(win * SR / 2)
        idx = np.clip((tg * SR).astype(int), 0, len(sig) - 1)
        lo, hi = np.clip(idx - w, 0, len(sig)), np.clip(idx + w, 0, len(sig))
        return 10 * np.log10((c[hi] - c[lo]) / np.maximum(hi - lo, 1) + 1e-12)

    def smooth_cut(req, glide):
        """Min-filter then Hann-smooth so every cut is fully reached before its peak and glides in/out."""
        r = max(1, int(glide / STEP))
        m = np.array([req[max(0, i - r // 2):i + r // 2 + 1].min() for i in range(n)])
        h = np.hanning(r * 2 + 1)
        h /= h.sum()
        return np.minimum(np.convolve(np.pad(m, r, mode="edge"), h, "same")[r:-r], 0)

    def gain(cut_db):
        return np.interp(np.arange(len(hp)) / SR, tg, 10 ** (cut_db / 20))

    L400 = level(hp, 0.4)
    sp = (L400 > -50) & (L400 > np.percentile(L400[L400 > -50], 90) - 12)   # voiced speech only

    C = np.percentile(L400[sp], ceil_pct)
    slow = smooth_cut(np.where(sp, strength * np.minimum(0, C - L400), 0), SLOW_GLIDE)

    # fast layer, measured after the slow layer
    y = hp * gain(slow)
    L20 = level(y, 0.02)
    R, Xc = int(SPAN / STEP), int(0.1 / STEP)
    ref = np.full(n, np.nan)
    for i in np.flatnonzero(sp):
        idx = np.r_[max(0, i - R):max(0, i - Xc), min(n, i + Xc):min(n, i + R)]
        idx = idx[sp[idx]]
        if len(idx) > 10:
            ref[i] = np.percentile(L20[idx], 75)
    w = int(0.02 * SR)
    hann = np.hanning(w)
    f = np.fft.rfftfreq(w, 1 / SR)
    cents = [1000 * 2 ** (i / 3) for i in range(8)]          # 1 k .. 5 k
    B = np.zeros((n, len(cents)))
    for i in range(n):
        a = int(tg[i] * SR) - w // 2
        seg = y[max(a, 0):max(a, 0) + w]
        if len(seg) < w:
            seg = np.pad(seg, (0, w - len(seg)))
        p = np.abs(np.fft.rfft(seg * hann)) ** 2
        B[i] = [10 * np.log10(p[(f >= c / 2 ** (1 / 6)) & (f < c * 2 ** (1 / 6))].sum() + 1e-12) for c in cents]
    share = B - L20[:, None]
    Sref = np.array([np.median(share[max(0, i - R):i + R][sp[max(0, i - R):i + R]], 0) if sp[i] else np.full(len(cents), np.inf)
                     for i in range(n)])
    res = sp & ((share - Sref).max(1) >= RES_JUMP) & (L20 > np.nan_to_num(ref, nan=0) - 3)
    over = np.where(sp & ~np.isnan(ref), L20 - np.nan_to_num(ref), 0)
    req = np.where(over > PEAK_OVER, -over, 0)
    req = np.where(res, np.minimum(req, -(np.maximum(over, 0) + RES_EXTRA)), req)
    fast = smooth_cut(strength * req, FAST_GLIDE)

    cut = slow + fast
    m4 = speech(frames(x0))
    item_db = round(TARGET - np.median(frames(x0 * gain(cut))[m4]), 1)

    def rdp(a, b):
        line = np.interp(tg[a:b + 1], [tg[a], tg[b]], [cut[a], cut[b]])
        k = int(np.argmax(np.abs(cut[a:b + 1] - line)))
        if abs(cut[a + k] - line[k]) > TOL and 0 < k < b - a:
            return rdp(a, a + k)[:-1] + rdp(a + k, b)
        return [a, b]

    pts = [(tg[i], 10 ** (cut[i] / 20)) for i in rdp(0, n - 1)]
    after = frames(x0 * np.interp(np.arange(len(x0)) / SR, *zip(*pts)) * 10 ** (item_db / 20))
    spread = lambda lv: float(np.subtract(*np.percentile(lv, [90, 10])))
    return {"item_db": item_db, "pts": pts, "deepest_cut": float(cut.min()),
            "spread_before": spread(frames(x0)[m4]), "spread_after": spread(after[m4])}
