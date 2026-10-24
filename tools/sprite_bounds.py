"""Where each enemy's idle sprite sits on its SpriteStudio canvas, so the Bestiary can fit it to the sprite box.

usage: python tools/sprite_bounds.py   (reads extracted/sprites/**.json from `ffr-dump objects`, writes extracted/sprite_bounds.json)

The game's sprite widget draws an animation's canvas (CanvasSize, origin at Pivot) fitted into the widget. Most enemy
canvases are cut to the enemy: as wide as it, and twice its height with the origin (its feet) in the middle, so the
enemy fills the canvas's top half. Square canvases (256, 512, 700...) are defaults that are not cut to the enemy; for
those the enemy's size comes from what the dump has: the biggest cell and the game's head marker (NULL_Head).
SpriteStudio cell references are not decoded by the dumper, so multi-part sprites can't be measured exactly.
Output per sprite: cw, ch (canvas), py (pivot Y, -0.5..0.5), w, h (enemy box) and cy (its centre above the origin).
"""
import glob, json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def value(v):
    return v.get('Float_temp') or v.get('Int_temp') or 0


def frame0(anim):
    out = {}
    for pa in anim['PartAnimes']:
        pos = {}
        for at in pa['Attributes']:
            tag = at['Tag'].split('::')[1]
            if tag in ('Posx', 'Posy') and at['Key']:
                pos[tag] = value(at['Key'][0]['Value'])
        out[pa['PartName']] = pos
    return out


def bounds(path):
    p = json.load(open(path, encoding='utf8'))['Properties']
    pack = p['AnimeList'][0]
    anims = {a['AnimationName']: a for a in pack['AnimeList']}
    idle = anims.get('idle') or anims.get('Idle') or next(a for n, a in anims.items() if n != 'Setup')
    cw, ch = idle['Settings']['CanvasSize']['X'], idle['Settings']['CanvasSize']['Y']
    py = idle['Settings']['Pivot']['Y']
    out = {'cw': round(cw), 'ch': round(ch), 'py': py}
    if py != 0:                                        # origin at the canvas bottom: the enemy fills the canvas
        out.update(w=round(cw), h=round(ch), cy=round(ch / 2))
        return out
    if ch >= 1.2 * cw:                                 # cut to the enemy: it fills the top half
        out.update(w=round(cw), h=round(ch / 2), cy=round(ch / 4))
        return out
    cells = [c for cm in p.get('CellmapList', []) for c in cm['Cells']]
    setup = frame0(anims['Setup']) if 'Setup' in anims else {}
    local = frame0(idle)
    parts = pack['Model']['PartList']
    idx = {pt['PartName']: i for i, pt in enumerate(parts)}

    def world_y(name):
        i, y = idx[name], 0
        while i >= 0:
            n = parts[i]['PartName']
            y += (local.get(n) or setup.get(n) or {}).get('Posy', 0)
            i = parts[i]['ParentIndex']
        return y
    head = world_y('NULL_Head') if 'NULL_Head' in idx else 0
    w = max((c['Size']['X'] for c in cells), default=cw / 2)
    h = max([head * 1.15] + [c['Size']['Y'] for c in cells])
    w, h = min(max(w, h * 0.8), cw), min(h, ch / 2)
    out.update(w=round(w), h=round(h), cy=round(h / 2))
    return out


out = {}
for f in glob.glob(str(ROOT / 'extracted/sprites/**/*.json'), recursive=True):
    rel = Path(f).relative_to(ROOT / 'extracted/sprites/FFRS/Content').with_suffix('')
    out['/Game/' + rel.as_posix() + '.' + rel.name] = bounds(f)
json.dump(out, open(ROOT / 'extracted/sprite_bounds.json', 'w'), indent=0, sort_keys=True)
for k in ('monster001', 'monster002', 'monster005', 'monster060', 'monster641', 'monster690', 'summon300050'):
    print(k, next(v for p, v in out.items() if p.endswith('.' + k)))
print(len(out), 'sprites')
