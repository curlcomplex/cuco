#!/usr/bin/env python3
"""
Semantic change markers (Whisper-AT first, markers second)

Two detection modes:
  - top1 : start a new segment when the top-1 tag *stably changes*
  - dist : start a new segment when the smoothed probability vector
           diverges from the running segment centroid beyond a threshold

Writes:
  - WAV: in-file RIFF 'cue ' + LIST/adtl 'labl' markers (audio frames untouched)
  - AIFF/FLAC/etc.: sidecar CSV with markers+labels

Dependencies:
  pip install numpy soundfile
  (optional for real model) pip install torch torchaudio   # and your Whisper-AT package
"""

import argparse
import csv
import os
import shutil
import struct
import datetime
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple, Dict, Optional

import numpy as np
import soundfile as sf

os.environ["PANN_DATA_DIR"] = str(Path(__file__).parent)

# --------------------
# Defaults
# --------------------
WIN_S = 10        # analysis window length (seconds)
HOP_S = 30        # hop length (seconds)
EMA_ALPHA = 0.30   # smoothing on probability vectors
MODE = "dist"      # 'top1' or 'dist'
DIST_THRESHOLD = 0.28   # for 'dist' mode (Jensen-Shannon distance ~ 0..1)
DWELL_S = 0.50          # required time the change stays above threshold
COOLDOWN_S = 0.80       # min gap after a cut before another is allowed
MIN_SEG_S = 1.50        # minimum segment duration
MAX_SEG_S = 20.0        # hard split if a segment runs too long (optional guard)
TOPK = 8               # tags to print into marker label
MIN_TAG_PROB = 0.5     # per-segment label probability threshold for printing

SUPPORTED_EXT = {".wav", ".wave", ".aiff", ".aif", ".flac"}

# --------------------
# Utils
# --------------------

def ema_smooth_mat(X: np.ndarray, alpha: float) -> np.ndarray:
    """EMA along time for a matrix [T, C]."""
    if len(X) == 0:
        return X
    Y = np.empty_like(X)
    acc = X[0].copy()
    Y[0] = acc
    a = float(alpha)
    for t in range(1, len(X)):
        acc = a * X[t] + (1.0 - a) * acc
        Y[t] = acc
    return Y

def cosine_distance(a: np.ndarray, b: np.ndarray, eps=1e-12) -> float:
    na = np.linalg.norm(a) + eps
    nb = np.linalg.norm(b) + eps
    return 1.0 - float(np.dot(a, b) / (na * nb))

def jensen_shannon_distance(p: np.ndarray, q: np.ndarray, eps=1e-12) -> float:
    """Jensen-Shannon distance (sqrt of JS divergence); inputs should sum to 1."""
    p = np.clip(p, eps, 1.0); p = p / p.sum()
    q = np.clip(q, eps, 1.0); q = q / q.sum()
    m = 0.5 * (p + q)
    def kl(x, y):
        return float(np.sum(x * (np.log2(x) - np.log2(y))))
    jsd = 0.5 * kl(p, m) + 0.5 * kl(q, m)
    return float(np.sqrt(max(jsd, 0.0)))

def is_pcm_wav(path: Path) -> bool:
    return path.suffix.lower() in {".wav", ".wave"}

def seconds_to_samples(t: float, sr: int) -> int:
    return int(round(t * sr))

# --------------------
# WAV cue/labl writer
# --------------------

def make_cue_and_list_chunks(markers: List[Tuple[float, str]], sample_rate: int):
    """
    markers: [(time_seconds, label_string), ...]
    Returns: (cue_chunk_bytes, list_chunk_bytes)
    """
    entries = []
    labels = []
    for i, (t, label) in enumerate(markers, start=1):
        sample_off = seconds_to_samples(t, sample_rate)
        dwName = i
        entry = struct.pack('<II4sIII', dwName, sample_off, b'data', 0, 0, sample_off)
        entries.append(entry)

        lab_text = (label or f"SEG {i}").encode('utf-8') + b'\x00'
        labl_data = struct.pack('<I', dwName) + lab_text
        labl_sz = len(labl_data)
        labl_chunk = b'labl' + struct.pack('<I', labl_sz) + labl_data
        if labl_sz % 2 == 1:
            labl_chunk += b'\x00'
        labels.append(labl_chunk)

    cue_body = struct.pack('<I', len(entries)) + b''.join(entries)
    cue_chunk = b'cue ' + struct.pack('<I', len(cue_body)) + cue_body
    if len(cue_body) % 2 == 1:
        cue_chunk += b'\x00'

    adtl_payload = b''.join(labels)
    list_body = b'adtl' + adtl_payload
    list_chunk = b'LIST' + struct.pack('<I', len(list_body)) + list_body
    if len(list_body) % 2 == 1:
        list_chunk += b'\x00'

    return cue_chunk, list_chunk

def write_markers_into_wav(path: Path, markers: List[Tuple[float, str]], sr: int):
    """Append cue/list chunks to WAV (audio frames unchanged)."""
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(path, 'rb') as fin, open(tmp, 'wb') as fout:
        header = fin.read(12)
        if header[:4] != b'RIFF' or header[8:12] != b'WAVE':
            raise ValueError("Not a RIFF/WAVE file")
        rest = fin.read()
        cue_chunk, list_chunk = make_cue_and_list_chunks(markers, sr)
        total_size = 4 + len(rest) + len(cue_chunk) + len(list_chunk)
        fout.write(b'RIFF' + struct.pack('<I', total_size) + b'WAVE')
        fout.write(rest)
        fout.write(cue_chunk)
        fout.write(list_chunk)
    shutil.move(tmp, path)

def write_sidecar_csv(markers: List[Tuple[float, str]], out_csv: Path):
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with open(out_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["index", "time_seconds", "label"])
        for i, (t, lab) in enumerate(markers, start=1):
            w.writerow([i, f"{t:.6f}", lab])

def write_batch_csv(all_markers: List[Tuple[str, float, str]], out_csv: Path):
    """
    Write a single CSV for all files.
    all_markers: List of (filename, time_seconds, label)
    """
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with open(out_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["filename", "index", "time_seconds", "label"])
        idx = 1
        for fname, t, lab in all_markers:
            w.writerow([fname, idx, f"{t:.6f}", lab])
            idx += 1

# --------------------
# Whisper-AT interface (stub)
# --------------------

@dataclass
class ClassifierOutput:
    """Holds per-window probabilities and the label list."""
    probs: np.ndarray   # shape [T, C]
    labels: List[str]   # length C
    times: np.ndarray   # shape [T], center time of each window (seconds)

def get_probs_mock(audio: np.ndarray, sr: int, win_s: float, hop_s: float) -> ClassifierOutput:
    """
    Mock classifier to test the pipeline without a model.
    Generates a few synthetic 'classes' that flip over time.
    """
    labels = ["DRUMS", "HIHAT", "SNARE", "AMBIENCE"]
    C = len(labels)
    n = len(audio)
    hop = seconds_to_samples(hop_s, sr)
    win = seconds_to_samples(win_s, sr)
    starts = np.arange(0, max(0, n - win + 1), hop)
    T = len(starts)
    probs = np.zeros((T, C), dtype=np.float32)
    rng = np.random.default_rng(42 + n % 1000)
    for i, s in enumerate(starts):
        t = (s + win // 2) / sr
        # Toy regime: alternate segments every ~5 s
        phase = int((t // 5) % 4)
        base = np.zeros(C)
        base[phase % C] = 0.75
        base[(phase+1) % C] = 0.20
        base += 0.05 * rng.random(C)
        base = base / base.sum()
        probs[i] = base
    times = (starts + win // 2) / sr
    return ClassifierOutput(probs=probs, labels=labels, times=times)

import tempfile
import numpy as np
import soundfile as sf

_whisper_model = None
_whisper_labels = None

def _load_whisper_at(model_name="large", at_low_compute=False):
    global _whisper_model, _whisper_labels
    import whisper_at as whisper  # pip package
    if _whisper_model is None:
        _whisper_model = whisper.load_model(model_name, at_low_compute=at_low_compute)
        try:
            import importlib.resources as ir
            with ir.files("whisper_at").joinpath("audioset_label.csv").open("r", encoding="utf-8") as f:
                _whisper_labels = [line.strip().split(",")[2] for line in f if line.strip()]
        except Exception:
            _whisper_labels = [f"class_{i}" for i in range(527)]
    return _whisper_model, _whisper_labels

def _softmax(x, axis=-1):
    x = x - np.max(x, axis=axis, keepdims=True)
    e = np.exp(x)
    return e / np.sum(e, axis=axis, keepdims=True)

def get_probs_whisper_at(audio: np.ndarray, sr: int, win_s: float, hop_s: float) -> ClassifierOutput:
    whisper_model, labels = _load_whisper_at(model_name="large", at_low_compute=False)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=True) as tmp:
        sf.write(tmp.name, audio, sr)
        at_time_res = 10.0
        result = whisper_model.transcribe(
            tmp.name, 
            at_time_res=at_time_res,
            condition_on_previous_text=True,
            word_timestamps=True
        )
        logits = result["audio_tag"].cpu().numpy()
        probs = _softmax(logits, axis=1)
        T = probs.shape[0]
        times = (np.arange(T) + 0.5) * at_time_res

        # Only use segment boundaries for cuts
        segments = result.get("segments", [])
        cuts = []
        for seg in segments:
            cuts.append(float(seg["start"]))
            cuts.append(float(seg["end"]))
        cuts = sorted(set(cuts))

        out = ClassifierOutput(
            probs=probs,
            labels=labels,
            times=times
        )
        out.cuts = cuts
        return out

# --------------------
# Semantic boundary detection
# --------------------

def detect_boundaries_top1(times: np.ndarray, probs_smooth: np.ndarray,
                           dwell_s: float, cooldown_s: float) -> List[float]:
    """Cut when top-1 label changes and remains changed for dwell_s."""
    top = probs_smooth.argmax(axis=1)
    T = len(times)
    if T == 0:
        return []
    cuts = []
    last_cut_t = -1e9
    i = 1
    while i < T:
        if top[i] != top[i-1]:
            # dwell: require it stays different for dwell_s
            j = i
            while j < T and (times[j] - times[i]) < dwell_s and top[j] == top[i]:
                j += 1
            if j < T and (times[j] - times[i]) >= dwell_s:
                if (times[i] - last_cut_t) >= cooldown_s:
                    cuts.append(times[i])
                    last_cut_t = times[i]
                i = j
                continue
        i += 1
    return cuts

def detect_boundaries_dist(times: np.ndarray, probs_smooth: np.ndarray,
                           dwell_s: float, cooldown_s: float, threshold: float,
                           metric: str = "jsd") -> List[float]:
    """Cut when distance from running centroid exceeds threshold for dwell_s."""
    T, C = probs_smooth.shape
    if T == 0:
        return []
    cuts = []
    last_cut_t = -1e9

    seg_start_idx = 0
    centroid = probs_smooth[0].copy()

    def dist(a, b):
        if metric == "cos":
            return cosine_distance(a, b)
        return jensen_shannon_distance(a, b)

    i = 1
    while i < T:
        d = dist(probs_smooth[i], centroid)
        if d >= threshold:
            # dwell check
            j = i
            ok = False
            while j < T and (times[j] - times[i]) < dwell_s:
                if dist(probs_smooth[j], centroid) < threshold:
                    ok = False
                    break
                ok = True
                j += 1
            if ok and (times[i] - last_cut_t) >= cooldown_s:
                cuts.append(times[i])
                last_cut_t = times[i]
                # start new segment at i; reset centroid to current frame
                seg_start_idx = i
                centroid = probs_smooth[i].copy()
                i = j
                continue
        # update centroid (running mean) gently within a segment
        w = 1.0 / max(1, i - seg_start_idx + 1)
        centroid = (1 - w) * centroid + w * probs_smooth[i]
        i += 1

    return cuts

def segments_from_cuts(cuts: List[float], t0: float, t1: float,
                       min_seg_s: float, max_seg_s: Optional[float]) -> List[Tuple[float, float]]:
    """Convert cut times into [start, end) segments with guards."""
    if not cuts:
        segs = [(t0, t1)]
    else:
        points = [t0] + sorted(cuts) + [t1]
        segs = [(points[i], points[i+1]) for i in range(len(points)-1)]

    # Enforce min duration: merge small ones into neighbors (left-leaning)
    merged = []
    for s, e in segs:
        if not merged:
            merged.append([s, e])
        else:
            if (e - s) < min_seg_s:
                merged[-1][1] = e
            else:
                merged.append([s, e])

    # Enforce max duration by hard splitting evenly (rare)
    if max_seg_s is not None and max_seg_s > 0:
        out = []
        for s, e in merged:
            L = e - s
            if L <= max_seg_s:
                out.append((s, e))
            else:
                k = int(np.ceil(L / max_seg_s))
                hop = L / k
                for j in range(k):
                    ss = s + j * hop
                    ee = min(e, ss + hop)
                    out.append((ss, ee))
        return out
    return [(float(s), float(e)) for s, e in merged]

def load_label_names(csv_path: Path) -> Dict[int, str]:
    """Load AudioSet label names from CSV file."""
    names = {}
    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    index = int(row['index'])
                    names[index] = row['display_name'].strip('"')
                except (ValueError, KeyError):
                    continue
    except FileNotFoundError:
        print("[warn] audioset_label.csv not found, using numeric indices")
    return names

LABEL_NAMES = load_label_names(Path(__file__).parent / "audioset_label.csv")

def label_for_segment(probs_smooth: np.ndarray, labels: List[str],
                      times: np.ndarray, seg: Tuple[float, float],
                      topk: int, min_prob: float) -> str:
    """Pick tags for one segment from the median probability vector inside the span."""
    s, e = seg
    idx = np.where((times >= s) & (times < e))[0]
    if len(idx) == 0:
        # Fallback: nearest frame
        idx = [int(np.clip(np.searchsorted(times, (s+e)/2), 0, len(times)-1))]
    vecs = probs_smooth[idx]
    med = np.median(vecs, axis=0)
    order = np.argsort(-med)
    tags = []
    for k in order[:topk]:
        if med[k] >= min_prob:
            # Try to get human readable name, fallback to index if not found
            if k < len(labels):
                tag = LABEL_NAMES.get(k, labels[k])
            else:
                tag = f"CLASS_{k}"
            # Normalize label: uppercase, replace spaces with underscores
            tag = tag.upper().replace(" ", "_")
            # Add probability as percentage
            prob_pct = int(round(med[k] * 100))
            tags.append(f"{tag}_{prob_pct}%")
    if not tags and len(order) > 0:
        k = order[0]
        if k < len(labels):
            tag = LABEL_NAMES.get(k, labels[k])
        else:
            tag = f"CLASS_{k}"
        tag = tag.upper().replace(" ", "_")
        prob_pct = int(round(med[k] * 100))
        tags = [f"{tag}_{prob_pct}%"]
    return "; ".join(tags)

# --------------------
# File processing
# --------------------

def sliding_windows(n_samples: int, sr: int, win_s: float, hop_s: float) -> np.ndarray:
    win = seconds_to_samples(win_s, sr)
    hop = seconds_to_samples(hop_s, sr)
    if win <= 0 or hop <= 0:
        raise ValueError("win_s and hop_s must be > 0")
    if n_samples < win:
        return np.array([0], dtype=int)
    return np.arange(0, n_samples - win + 1, hop, dtype=int)

def run_classifier(audio: np.ndarray, sr: int, win_s: float, hop_s: float, use_mock: bool) -> ClassifierOutput:
    if use_mock:
        return get_probs_mock(audio, sr, win_s, hop_s)
    # Replace with your actual model call:
    return get_probs_whisper_at(audio, sr, win_s, hop_s)

def rename_file_with_tags(path: Path, probs_smooth: np.ndarray, labels: List[str], topk: int = 8, min_prob: float = 0.15):
    """Rename the file to include top tags (no duplicate tag names, single underscore between tags)."""
    med = np.median(probs_smooth, axis=0)
    mx = np.max(probs_smooth, axis=0)
    order = np.argsort(-med)
    tags = []
    seen = set()
    for k in order[:topk]:
        if med[k] >= min_prob or mx[k] >= min_prob:
            tag = LABEL_NAMES.get(k, labels[k]) if k < len(labels) else f"CLASS_{k}"
            tag = tag.upper().replace(" ", "_")
            if tag not in seen:
                tags.append(tag)
                seen.add(tag)
    if not tags and len(order) > 0:
        k = order[0]
        tag = LABEL_NAMES.get(k, labels[k]) if k < len(labels) else f"CLASS_{k}"
        tag = tag.upper().replace(" ", "_")
        tags = [tag]
    tag_str = "_".join(tags)
    new_name = f"{path.stem}_{tag_str}{path.suffix}"
    new_path = path.with_name(new_name)
    path.rename(new_path)
    print(f"[renamed] {path.name} -> {new_path.name}")

def get_timestamped_outdir(target: Path) -> Path:
    # Use the target folder name at the beginning of the export folder name
    # Place export folder in the same layer as the target folder
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    target_name = target.name if target.is_dir() else target.parent.name
    outdir = target.parent / f"{target_name}_tagged_{ts}"
    outdir.mkdir(parents=True, exist_ok=True)
    return outdir

def walk_inputs(root: Path):
    if root.is_file():
        yield root
        return
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in SUPPORTED_EXT:
            yield p

def process_file(path: Path, args, out_dir: Path):
    try:
        info = sf.info(str(path))
        if info.frames <= 0:
            print(f"[skip] {path.name}: empty/invalid")
            return
    except Exception as e:
        print(f"[skip] {path.name}: unreadable ({e})")
        return

    copied_path = out_dir / path.name
    shutil.copy2(path, copied_path)

    audio, sr = sf.read(str(copied_path), dtype='float32', always_2d=True)
    x = audio.mean(axis=1)

    # Run PANNs event detection
    events = get_panns_events(x, sr)

    markers: List[Tuple[float, str]] = []
    for t, label in events:
        markers.append((t, label))

    markers.sort(key=lambda x: x[0])
    dedup = []
    for t, lab in markers:
        if not dedup or abs(t - dedup[-1][0]) > 0.001:
            dedup.append((t, lab))
    markers = dedup

    if args.dry_run:
        print(f"[dry] {path.name}: {len(markers)} event markers")
        return

    if is_pcm_wav(copied_path):
        try:
            write_markers_into_wav(copied_path, markers, sr)
            print(f"[ok]  {copied_path.name}: wrote {len(markers)} event markers (RIFF cue/labl)")
        except Exception as e:
            print(f"[err] {copied_path.name}: RIFF write failed ({e}); wrote sidecar CSV instead.")
            out_csv = out_dir / (copied_path.stem + "_event_markers.csv")
            write_sidecar_csv(markers, out_csv)
    else:
        out_csv = out_dir / (copied_path.stem + "_event_markers.csv")
        write_sidecar_csv(markers, out_csv)
        print(f"[ok]  {copied_path.name}: wrote sidecar CSV with {len(markers)} event markers")

    # No renaming needed for PANNs event markers

# --------------------
# Marker stripping
# --------------------

def strip_markers_from_wav(path: Path):
    """Remove RIFF cue/labl/list markers from a WAV file (audio frames untouched)."""
    tmp = path.with_suffix(path.suffix + ".nomarkers")
    with open(path, 'rb') as fin, open(tmp, 'wb') as fout:
        riff = fin.read(12)
        if riff[:4] != b'RIFF' or riff[8:12] != b'WAVE':
            raise ValueError("Not a RIFF/WAVE file")
        fout.write(riff)
        while True:
            chunk_header = fin.read(8)
            if not chunk_header or len(chunk_header) < 8:
                break
            chunk_id = chunk_header[:4]
            chunk_size = struct.unpack('<I', chunk_header[4:])[0]
            chunk_data = fin.read(chunk_size)
            if chunk_size % 2 == 1:
                fin.read(1)  # skip pad byte
            # Skip marker chunks
            if chunk_id in {b'cue ', b'LIST'}:
                continue
            fout.write(chunk_header)
            fout.write(chunk_data)
            if chunk_size % 2 == 1:
                fout.write(b'\x00')
    shutil.move(tmp, path)

def strip_markers_in_folder(folder: Path):
    """Strip markers from all supported files in a folder."""
    for p in folder.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".wav", ".wave"}:
            try:
                strip_markers_from_wav(p)
                print(f"[stripped] {p.name}")
            except Exception as e:
                print(f"[err] {p.name}: {e}")

# --------------------
# PANNs event detection
# --------------------

def get_panns_events(audio: np.ndarray, sr: int) -> List[Tuple[float, str]]:
    from panns_inference import AudioTagging, SoundEventDetection
    import torch

    if sr != 32000:
        import scipy.signal
        gcd = np.gcd(sr, 32000)
        up = 32000 // gcd
        down = sr // gcd
        audio = scipy.signal.resample_poly(audio, up, down)
        sr = 32000

    # Skip files shorter than 1 second
    if len(audio) < 32000:
        print("[skip] Audio too short for PANNs event detection")
        return []

    at = AudioTagging(checkpoint_path="/Users/f.god/panns_data/Cnn14_mAP=0.431.pth", device='cpu')
    sed = SoundEventDetection(checkpoint_path="/Users/f.god/panns_data/Cnn14_mAP=0.431.pth", device='cpu')

    events = []
    results = sed.inference(audio[np.newaxis, :])
    if not isinstance(results, dict):
        print("[debug] PANNs output type:", type(results))
        print("[debug] PANNs output value:", results)
        print("[warn] PANNs returned non-dict output, skipping file.")
        return []

    sound_events = results.get('sound_event_detection', [])
    if not isinstance(sound_events, list):
        print("[warn] Unexpected output from PANNs, skipping file.")
        return []
    for event in sound_events:
        t = event.get('event_time')
        label = event.get('event_label')
        if t is not None and label is not None:
            events.append((t, label))
    return events

def get_panns_tags(audio: np.ndarray, sr: int, topk: int = 5, min_prob: float = 0.1) -> List[Tuple[float, str]]:
    from panns_inference import AudioTagging
    import torch

    if sr != 32000:
        import scipy.signal
        gcd = np.gcd(sr, 32000)
        up = 32000 // gcd
        down = sr // gcd
        audio = scipy.signal.resample_poly(audio, up, down)
        sr = 32000

    at = AudioTagging(checkpoint_path="/Users/f.god/panns_data/Cnn14_mAP=0.431.pth", device='cpu')
    probs = at.inference(audio[np.newaxis, :])  # shape [1, classes]
    probs = probs[0]  # remove batch dimension

    # Get label names
    from panns_inference.config import labels
    tags = []
    for idx in np.argsort(-probs)[:topk]:
        if probs[idx] >= min_prob:
            tags.append(labels[idx])
    label_str = "; ".join(tags)
    return [(0.0, label_str)]

def get_panns_events(audio: np.ndarray, sr: int, topk: int = 5, min_prob: float = 0.1) -> List[Tuple[float, str]]:
    from panns_inference import AudioTagging
    import torch

    if sr != 32000:
        import scipy.signal
        gcd = np.gcd(sr, 32000)
        up = 32000 // gcd
        down = sr // gcd
        audio = scipy.signal.resample_poly(audio, up, down)
        sr = 32000

    if len(audio) < 32000:
        print("[skip] Audio too short for PANNs tagging")
        return []

    at = AudioTagging(checkpoint_path="/Users/f.god/panns_data/Cnn14_mAP=0.431.pth", device='cpu')
    probs = at.inference(audio[np.newaxis, :])  # shape [1, classes]
    probs = probs[0]  # remove batch dimension

    from panns_inference.config import labels
    tags = []
    for idx in np.argsort(-probs)[:topk]:
        if probs[idx] >= min_prob:
            tags.append(labels[idx])
    label_str = "; ".join(tags)
    return [(0.0, label_str)]

# --------------------
# CLI
# --------------------

def main():
    ap = argparse.ArgumentParser(description="Semantic change markers using Whisper-AT probabilities.")
    ap.add_argument("input", type=Path, help="File or folder")
    ap.add_argument("--dry-run", action="store_true", help="Analyze only, do not write markers")
    ap.add_argument("--out-dir", type=Path, default=Path("./semantic_marker_csv"))
    ap.add_argument("--strip", action="store_true", help="Remove all markers from files in the target folder before processing")

    # Mode: use Whisper-AT segmentation by default (dist mode, jsd metric, recommended thresholds)
    ap.add_argument("--mode", choices=["top1", "dist"], default="dist")
    ap.add_argument("--metric", choices=["jsd", "cos"], default="jsd")
    ap.add_argument("--dist-thr", type=float, default=0.28)

    # Windowing / smoothing: match Whisper-AT training resolution
    ap.add_argument("--win-s", type=float, default=10.0)
    ap.add_argument("--hop-s", type=float, default=10.0)
    ap.add_argument("--ema", type=float, default=0.30)

    # Dwell / cooldown / segment guards
    ap.add_argument("--dwell-s", type=float, default=0.5)
    ap.add_argument("--cooldown-s", type=float, default=0.8)
    ap.add_argument("--min-seg-s", type=float, default=1.5)
    ap.add_argument("--max-seg-s", type=float, default=20.0)

    # Labels in markers
    ap.add_argument("--topk", type=int, default=3)
    ap.add_argument("--min-tag-prob", type=float, default=0.35)

    # Model selection
    ap.add_argument("--mock", action="store_true", help="Use mock classifier (for testing without a model)")

    args = ap.parse_args()
    if not args.input.exists():
        raise SystemExit(f"Input not found: {args.input}")

    if args.strip:
        strip_markers_in_folder(args.input)
        print("[info] Existing markers stripped. Continuing with semantic marker processing...")

    args.out_dir = get_timestamped_outdir(args.input)

    files = list(walk_inputs(args.input))
    all_markers = []

    for p in files:
        rel_path = p.relative_to(args.input.parent if args.input.is_file() else args.input)
        export_path = args.out_dir / rel_path
        export_path.parent.mkdir(parents=True, exist_ok=True)

        try:
            info = sf.info(str(p))
            if info.frames <= 0:
                print(f"[skip] {p.name}: empty/invalid")
                continue
        except Exception as e:
            print(f"[skip] {p.name}: unreadable ({e})")
            continue

        shutil.copy2(p, export_path)

        audio, sr = sf.read(str(export_path), dtype='float32', always_2d=True)
        x = audio.mean(axis=1)

        events = get_panns_events(x, sr)
        markers: List[Tuple[float, str]] = []
        for t, label in events:
            markers.append((t, label))

        markers.sort(key=lambda x: x[0])
        dedup = []
        for t, lab in markers:
            if not dedup or abs(t - dedup[-1][0]) > 0.001:
                dedup.append((t, lab))
        markers = dedup

        if args.dry_run:
            print(f"[dry] {p.name}: {len(markers)} event markers")
            continue

        for t, lab in markers:
            all_markers.append((str(rel_path), t, lab))

        if is_pcm_wav(export_path):
            try:
                write_markers_into_wav(export_path, markers, sr)
                print(f"[ok]  {export_path.name}: wrote {len(markers)} event markers (RIFF cue/labl)")
            except Exception as e:
                print(f"[err] {export_path.name}: RIFF write failed ({e})")
        else:
            print(f"[ok]  {export_path.name}: processed (non-WAV)")

    # Write single batch CSV for all files
    batch_csv = args.out_dir / "semantic_markers_all.csv"
    write_batch_csv(all_markers, batch_csv)
    print(f"[ok] Wrote batch CSV: {batch_csv}")

if __name__ == "__main__":
    main()

import os
from pathlib import Path
labels_csv_path = os.path.join(
    os.environ.get("PANN_DATA_DIR", str(Path(__file__).parent)),
    "class_labels_indices.csv"
)