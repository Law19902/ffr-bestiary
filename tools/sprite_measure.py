"""Measure each enemy's sprite as the game draws it, from captures of the Bestiary's dev measure mode.

usage: python tools/sprite_measure.py <capture dir> <log lines file>
  capture dir: NNNa.png / NNNb.png, crops of the screen around the sprite box, one pair per dev step (F8)
  log lines:   the "dev sprite ..." lines from UE4SS.log for the same steps, in order (path, k, vs)
Writes extracted/sprite_measured.json: sprite path -> [x0, x1, y0, y1], the outline in sprite pixels from the
canvas centre (y down), and lists the sprites whose outline touched the box edge (clipped, so measured too small).

In measure mode (dev.txt, F9) the box has a magenta background and the sprite widget draws the canvas fitted to the
box at MEASURE_SCALE, so a sprite pixel covers k * vs * MEASURE_SCALE screen pixels.
"""
import json, re, sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MEASURE_SCALE = 0.5                                       # must match ui.lua

caps, logfile = Path(sys.argv[1]), Path(sys.argv[2])
lines = [l for l in logfile.read_text(encoding='utf8').splitlines() if 'dev sprite' in l]
OUT = ROOT / 'extracted/sprite_measured.json'
earlier = json.load(open(OUT)) if OUT.exists() else {}      # earlier runs are kept; this run's sprites replace theirs
out, clipped, missing = {}, [], []
for n, line in enumerate(lines, 1):
    m = re.search(r'dev sprite (\d+) unit (\d+) (\S+) k=([\d.]+) vs=([\d.]+)', line)
    path, k, vs = m.group(3), float(m.group(4)), float(m.group(5))
    boxes = []
    for suffix in 'ab':
        f = caps / ('%03d%s.png' % (n, suffix))
        if not f.exists():
            continue
        a = np.asarray(Image.open(f).convert('RGB')).astype(int)
        magenta = (a[..., 0] > 225) & (a[..., 1] < 40) & (a[..., 2] > 225)
        ys, xs = np.nonzero(magenta)
        if len(xs) < 1000:
            continue
        bx0, bx1, by0, by1 = xs.min(), xs.max(), ys.min(), ys.max()
        inner = a[by0 + 2:by1 - 1, bx0 + 2:bx1 - 1]
        dist = np.abs(inner - np.array([255, 0, 255])).sum(axis=2)
        sy, sx = np.nonzero(dist > 90)
        if len(sx) == 0:
            continue
        cx, cy = (bx0 + bx1) / 2 - (bx0 + 2), (by0 + by1) / 2 - (by0 + 2)
        touch = sx.min() <= 1 or sy.min() <= 1 or sx.max() >= inner.shape[1] - 2 or sy.max() >= inner.shape[0] - 2
        boxes.append((sx.min() - cx, sx.max() + 1 - cx, sy.min() - cy, sy.max() + 1 - cy, touch))
    if not boxes:
        missing.append(path); continue
    per = k * vs * MEASURE_SCALE                          # screen px per sprite px
    b = [min(x[0] for x in boxes) / per, max(x[1] for x in boxes) / per,
         min(x[2] for x in boxes) / per, max(x[3] for x in boxes) / per]
    if any(x[4] for x in boxes):
        clipped.append(path)
    old = out.get(path)
    out[path] = [round(v, 1) for v in (b if not old else [min(old[0], b[0]), max(old[1], b[1]), min(old[2], b[2]), max(old[3], b[3])])]
json.dump({**earlier, **out}, open(OUT, 'w'), indent=0, sort_keys=True)
print('measured', len(out), 'clipped', len(clipped), 'missing', len(missing))
for p in clipped[:20]: print('  clipped', p)
for p in missing[:20]: print('  missing', p)
