# Cut Markers

Picture-cut markers in an open REAPER project, from the edit's FCP 7 XML (IG F-018).

```bash
python3 cut_markers.py --xml "Cutdown.xml" --video "Cutdown.mp4" --project EP4_CUTDOWN --clear
```

- **Cuts:** every clip edge on a picture track. V1 is always picture. Tracks above it that cover ≥ 90% of the sequence are overlays (grain, backgrounds) and are ignored.
- **`--video`:** the duration must match the XML, otherwise the tool stops (it's the wrong version of the edit). Each cut gets ffmpeg's scene score on its frame. A visible change is named `CUT`. Anything else is named `CUT?`: a same-shot split, a cut hidden under a graphic, or a soft transition. Audition those.
- **REAPER:** the markers (orange) go into the matching open tab as one undo step, and the project is not saved. `--clear` removes all existing markers first; regions stay. Without it, the tool stops if `CUT` markers are already there.
- **`--offset`:** project time of the edit's first frame (default 0).
- **Use the XML, not the EDL.** On Check This EP3 the EDL was from an older 35 s edit, while the XML matched the 14.72 s video.

Check: `python3 test_cut_markers.py`. End to end, it reproduced the hand-made EP3 (30) and EP4 (26) cutdown lists exactly.
