"""Self-check for the cut rule. Run: python3 test_cut_markers.py"""
from cut_markers import cuts

# 100-frame edit. V1 has a gap at 40-60 filled by two V2 clips; V3 is a full-length grain overlay
# (its 30 is not a cut); V4 is a graphic from 80 with a V1 cut under it at 90.
tracks = [
    [(0, 20), (20, 40), (60, 90), (90, 100)],
    [(40, 50), (50, 60)],
    [(0, 30), (30, 100)],
    [(80, 100)],
]
assert cuts(tracks, 100) == [20, 40, 50, 60, 80, 90], cuts(tracks, 100)
# V1 running end to end is still picture, not an overlay
assert cuts([[(0, 50), (50, 100)], [(0, 100)]], 100) == [50]
print("ok")
