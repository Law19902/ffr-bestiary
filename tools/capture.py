"""Record the screen for a few seconds and report where the picture stalls (for judging how smooth a menu is).

usage: python tools/capture.py <seconds> <out dir> [left top right bottom]   (box in screen pixels; default: whole screen)
Saves every frame (small JPEGs) with its time, then prints the gaps: runs of identical frames longer than 50 ms
while the screen was otherwise changing, i.e. hitches the player sees.
"""
import os, sys, time
from PIL import ImageGrab, ImageChops

secs, out = float(sys.argv[1]), sys.argv[2]
box = tuple(int(v) for v in sys.argv[3:7]) if len(sys.argv) >= 7 else None
os.makedirs(out, exist_ok=True)
frames = []
end = time.perf_counter() + secs
while time.perf_counter() < end:
    t = time.perf_counter()
    frames.append((t, ImageGrab.grab(bbox=box, all_screens=False)))
t0 = frames[0][0]
print('frames', len(frames), 'fps %.1f' % (len(frames) / secs))
changes, last = [], None
for i, (t, img) in enumerate(frames):
    small = img.resize((img.width // 4, img.height // 4))
    if i % 2 == 0:
        small.save(os.path.join(out, '%04d_%05d.jpg' % (i, int((t - t0) * 1000))), quality=70)
    if last is not None:
        diff = ImageChops.difference(small.convert('L'), last.convert('L')).getbbox()
        changes.append((t - t0, diff is not None))
    last = small
# stalls: stretches with no change, between changes
stalls, start, prev_change = [], None, None
for t, changed in changes:
    if changed:
        if prev_change is not None and t - prev_change > 0.05:
            stalls.append((prev_change, t - prev_change))
        prev_change = t
for at, length in stalls:
    print('no change %4d ms at %5.2f s' % (length * 1000, at))
