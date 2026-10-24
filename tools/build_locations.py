"""Build enemy -> encounter areas from the dumped game data (recon output, not shipped).

Inputs (all produced by tools/ffr-dump into extracted/):
  json/Datatable/**            every DataTable
  json/Game.en.locres.json     English strings
  map_encount.jsonl            encounter actors placed in levels      (ffr-dump find Map .umap Encount)
  map_events.jsonl             event triggers / NPCs / gimmicks        (ffr-dump find Map .umap <event regex>)
Outputs:
  extracted/locations.json     {areas, enemies, unresolved}
  extracted/locations_report.txt

An area is what the player sees as a place name: maps sharing a display name are one area (a dungeon's floors),
and on the world map each island is one area.
"""
import collections, glob, json, os, re

X = 'extracted'
DT = X + '/json/Datatable'


def rows(path):
    for e in json.load(open(path, encoding='utf8')):
        if 'Rows' in e:
            return e['Rows']
    return {}


loc = json.load(open(X + '/json/Game.en.locres.json', encoding='utf8'))


def text(t):
    """FText from a table -> English, via the StringTable namespace + key."""
    if not t or not t.get('Key'):
        return None
    ns = (t.get('TableId') or '').split('.')[-1]
    return loc.get(ns, {}).get(t['Key'])


def stem(path):
    """'/Game/Map/Dng/x/Dng_x_PL.Dng_x_PL' or 'FFRS/Content/.../Dng_x_01_GD.umap' -> 'Dng_x_PL' / 'Dng_x_01_GD'"""
    return os.path.basename(path).split('.')[0]


def folder(game_path):
    """map package or level path -> its map folder ('/Game/Map/Dng/04Dir/04Dir_41')"""
    p = game_path.replace('FFRS/Content/', '/Game/')
    p = os.path.dirname(p)
    if os.path.basename(p) in ('GD', 'EV', 'BG', 'FG', 'SD', 'LT', 'MOCK'):
        p = os.path.dirname(p)
    return p


# ---------- areas ----------
maps = {}             # map id -> {name key, english, level stem, folder}
for f in glob.glob(DT + '/Map/MapData/DT_MapData_*.json'):
    for rk, v in rows(f).items():
        name = v['Name'] if v['Name'].get('Key') else (v.get('nameList') or [{}])[0].get('Name', {}) if v.get('nameList') else {}
        maps[v['ID']] = {'row': rk, 'nameKey': name.get('Key'), 'name': text(name), 'level': stem(v['Level']['AssetPathName']),
                         'folder': folder(v['Level']['AssetPathName']), 'jp': v.get('developmentName'), 'raw': v}

islands = {}          # eMapIslandType::X -> {nameKey, name}
for v in rows(DT + '/Map/DT_MapIslandData.json').values():
    islands[v['IslandType']] = {'nameKey': v['Name'].get('Key'), 'name': text(v['Name'])}

sublevel_map = {}     # level stem -> (map id, island or None)
folder_maps = collections.defaultdict(set)
for mid, m in maps.items():
    sublevel_map[m['level']] = (mid, None)
    folder_maps[m['folder']].add(mid)
    v = m['raw']
    for isl in v.get('worldMapIslandLevelList') or []:
        for s in isl['subLevelNameList']:
            sublevel_map[s] = (mid, isl['IslandType'])
    for key in ('mainProgressLoadLevelList', 'townAndDungeonDelayLoadLevelList', 'transitionLoadLevelList', 'underworldLevelList'):
        for e in v.get(key) or []:
            for s in e.get('subLevelNameList') or []:
                sublevel_map.setdefault(s, (mid, None))


WORLD = next(mid for mid, m in maps.items() if m['raw'].get('worldMapIslandLevelList'))
region_island = {}    # '04Dir' -> eMapIslandType::Dirnado, from world sublevel names Wld_04Dir_*
for s, (mid, isl) in sublevel_map.items():
    m = re.match(r'Wld_(\d\d[A-Za-z]+)_', s)
    if m and isl:
        region_island[m.group(1)] = isl


def area_of(mid, island=None):
    if island and island in islands and islands[island]['nameKey']:
        return 'island:' + islands[island]['nameKey']
    m = maps.get(mid)
    if not m:
        return None
    return 'name:' + m['nameKey'] if m['nameKey'] else 'map:%d' % mid


def area_label(aid):
    kind, key = aid.split(':', 1)
    if kind == 'island':
        return next((i['name'] for i in islands.values() if i['nameKey'] == key), key) + ' (world map)'
    if kind == 'name':
        return loc.get('ST_MAP_NAME', {}).get(key, key)
    m = maps[int(key)]
    return '[unnamed map %s %s %s]' % (key, m['row'], m['jp'])


def areas_for_package(pkg):
    """Which areas a level package belongs to. Returns a set of area ids ('' set if unknown)."""
    s = stem(pkg)
    if s in sublevel_map:
        mid, isl = sublevel_map[s]
        return {area_of(mid, isl)}
    # world map sublevels: Wld_01Gra_GD -> the island listing Wld_01Gra_*
    m = re.match(r'Wld_(\d\d[A-Za-z]+)', s)
    if m:
        for sub, (mid, isl) in sublevel_map.items():
            if isl and sub.startswith('Wld_' + m.group(1)):
                return {area_of(mid, isl)}
    mids = folder_maps.get(folder(pkg))
    if mids:
        return {area_of(mid) for mid in mids}
    return set()


# ---------- battle groups -> units ----------
bgroups = {v['ID']: v['UnitIdList'] for v in rows(DT + '/Encount/DT_BattleGroup.json').values()}
encount_tables = {}
for f in glob.glob(DT + '/Encount/*/DT_*_Encount.json'):
    encount_tables['/Game/Datatable/Encount/' + os.path.relpath(f, DT + '/Encount').replace(os.sep, '/')[:-5]] = \
        [r['battleGroupId'] for r in rows(f).values()]

bg_rows = {v['ID']: v for v in rows(DT + '/Encount/DT_BattleGroup.json').values()}
group_areas = collections.defaultdict(lambda: collections.defaultdict(set))   # battle group -> area -> {source kinds}
unresolved = []
used_tables = set()


def add_group(gid, areas, kind, ref):
    if gid not in bgroups:
        unresolved.append({'kind': kind, 'ref': ref, 'why': 'battle group %s not in DT_BattleGroup' % gid}); return
    for a in areas:
        group_areas[gid][a].add(kind)


# 1. random encounters: encounter actors in levels
for l in open(X + '/map_encount.jsonl', encoding='utf8'):
    d = json.loads(l)
    p = d['obj'].get('Properties', {})
    tables = []
    if p.get('m_pEncountDatatable'):
        tables.append(p['m_pEncountDatatable']['ObjectPath'].rsplit('.', 1)[0])
    for e in p.get('m_EncountDatatableList') or []:
        if e.get('pEncountDatatable'):
            tables.append(e['pEncountDatatable']['ObjectPath'].rsplit('.', 1)[0])
    if not tables:
        continue
    areas = areas_for_package(d['package'])
    for t in tables:
        used_tables.add(t)
        here = areas
        if areas == {area_of(WORLD)}:       # shared world sublevel (Wld_GD): the table's region folder names the island
            code = t.split('/')[-2]          # /Game/Datatable/Encount/04Dir/DT_04Dir_Wld_03_Encount -> 04Dir
            here = {area_of(WORLD, region_island[code])} if code in region_island else areas
        for gid in encount_tables.get(t, []):
            add_group(gid, here, 'random', '%s %s %s' % (d['package'], d['name'], t))

# 2. story / scripted battles: talk events with an encountGroupId, placed via map actors or chained events
events = {}
for f in glob.glob(DT + '/Event/TalkEvent/**/*.json', recursive=True):
    if not os.path.basename(f).startswith('CDT_'):
        events.update(rows(f))
event_areas = collections.defaultdict(set)


def event_ids(o):
    """every EventId string inside an actor's properties"""
    if isinstance(o, dict):
        for k, v in o.items():
            if k == 'EventId' and isinstance(v, str) and v != 'None':
                yield v
            else:
                yield from event_ids(v)
    elif isinstance(o, list):
        for x in o:
            yield from event_ids(x)


entered_from = collections.defaultdict(set)                 # map id -> areas whose triggers move the player there
for l in open(X + '/map_events.jsonl', encoding='utf8'):
    d = json.loads(l)
    p = d['obj'].get('Properties', {})
    here = areas_for_package(d['package'])
    for td in p.get('mTransitionDataList') or []:        # events played on arrival at another map
        if td.get('mapId', -1) in maps:
            entered_from[td['mapId']] |= here
        dest = {area_of(td['mapId'])} if td.get('mapId', -1) in maps else here
        for e in event_ids(td):
            event_areas[e] |= dest
    for e in event_ids({k: v for k, v in p.items() if k != 'mTransitionDataList'}):
        event_areas[e] |= here
for mid, m in maps.items():                                 # events a map row runs (on entry, by progress)
    for e in event_ids(m['raw']):
        event_areas[e].add(area_of(mid))
for v in events.values():                                   # arrival events on table transitions
    tl = v.get('TransitionLocation') or {}
    if tl.get('mapId', -1) in maps:
        for e in tl.get('transitionEventList', []) + tl.get('afterTransitionEventList', []):
            if isinstance(e, dict) and e.get('EventId'):
                event_areas[e['EventId']].add(area_of(tl['mapId']))


def chained(v):
    for key in ('ContinuousEventList', 'ChoicesBranchEventList'):
        yield from (e for e in event_ids(v.get(key) or []) if e in events)


bundle = {v['EventId']: v for v in rows(DT + '/Event/BattleEvent/DT_BtlEventDataBundle.json').values()}


def group_events(g):
    """events a battle group starts: its finish events and its in-battle events (reinforcements etc.)"""
    for key in ('battleFinishEventId', 'battleFinishEscapeEventId', 'battleFinishLoseEventId'):
        if g.get(key) in events:
            yield g[key]
    if g.get('battleEventId', -1) in bundle:
        yield from (e for e in event_ids(bundle[g['battleEventId']]) if e in events)


def after(k):
    """where the player is once event k ends: its transition's map, else where it ran"""
    tl = events[k].get('TransitionLocation') or {}
    return {area_of(tl['mapId'])} if tl.get('mapId', -1) in maps else event_areas[k]


def propagate():
    """areas flow: event -> chained event -> its battle group -> that group's follow-up events -> ..."""
    changed = True
    while changed:
        changed = False
        for k, v in events.items():
            tl = v.get('TransitionLocation') or {}
            if tl.get('mapId', -1) in maps and event_areas[k] - entered_from[tl['mapId']]:
                entered_from[tl['mapId']] |= event_areas[k]; changed = True
            for nxt in chained(v):
                if after(k) - event_areas[nxt]:
                    event_areas[nxt] |= after(k); changed = True
            gid = v.get('encountGroupId', -1)
            if gid in bgroups:
                new = {a for a in event_areas[k] if a} - set(group_areas[gid])
                if new:
                    add_group(gid, new, 'event', k); changed = True
        for gid, g in bg_rows.items():
            have = set(group_areas[gid]) if gid in group_areas else set()
            for e in group_events(g):
                if have - event_areas[e]:
                    event_areas[e] |= have; changed = True


# 3. treasure-box monsters: DT_Dng_<map>.json rows with battleGroupId
for f in glob.glob(DT + '/Map/Gimmick/TreasureBox/DT_*.json'):
    if os.path.basename(f).startswith('CDT_'):
        continue
    lvl = os.path.basename(f)[3:-5]                          # Dng_01Gra_40 / Dng_01Gra_42_01
    areas = {area_of(mid) for mid, m in maps.items() if m['level'].startswith(lvl + '_PL') or m['level'] == lvl + '_PL'}
    if not areas:
        areas = {area_of(mid) for mid, m in maps.items() if m['level'].startswith(lvl)}
    for rk, v in rows(f).items():
        if v.get('battleGroupId', -1) not in (-1, 0):
            add_group(v['battleGroupId'], areas, 'chest', '%s %s' % (os.path.basename(f), rk))

# 4. colosseum
for f in glob.glob(DT + '/UI/Colosseum/*.json'):
    for rk, v in rows(f).items():
        if v.get('battleGroupId', -1) not in (-1, 0):
            add_group(v['battleGroupId'], {'colosseum:'}, 'colosseum', '%s %s' % (os.path.basename(f), rk))

propagate()

# unnamed maps (cutscene stages like 00Eve_95) show no place name; a fight there counts for the named area the
# player entered it from. Resolved transitively; a stage nobody enters stays 'map:<id>' (reported).
def named_origin(mid, seen=()):
    out = set()
    for a in entered_from.get(mid, ()):
        if a and a.startswith('map:') and int(a[4:]) not in seen:
            out |= named_origin(int(a[4:]), seen + (mid,))
        elif a:
            out.add(a)
    return out


stage_alias = {}
for mid in maps:
    if area_of(mid).startswith('map:'):
        stage_alias[area_of(mid)] = named_origin(mid)
for gid in list(group_areas):
    for a in [a for a in group_areas[gid] if stage_alias.get(a)]:
        kinds = group_areas[gid].pop(a)
        for b in stage_alias[a]:
            group_areas[gid][b] |= kinds

for k, v in events.items():
    gid = v.get('encountGroupId', -1)
    if gid not in (-1, 0) and not event_areas[k]:
        unresolved.append({'kind': 'event', 'ref': k, 'why': 'no area', 'group': gid, 'units': bgroups.get(gid),
                           'desc': v.get('Description')})
    elif gid not in (-1, 0) and gid not in bgroups:
        unresolved.append({'kind': 'event', 'ref': k, 'why': 'battle group %s not in DT_BattleGroup' % gid})

sources = collections.defaultdict(lambda: collections.defaultdict(set))   # unit -> area -> {source kinds}
for gid, areas in group_areas.items():
    for u in bgroups[gid]:
        for a, kinds in areas.items():
            sources[u][a] |= kinds

# 5. units a unit brings in mid-battle: AI skills -> skill effects SummonUnit (ParamList[1] = unit) /
#    SummonGroup (ParamList[0] = battle group). Summoned units inherit the summoner's areas.
skills = {v['ID']: v for v in rows(DT + '/Skill/DT_SkillData.json').values()}
effects = {v['ID']: v for v in rows(DT + '/Skill/DT_SkillEffectData.json').values()}
summons = collections.defaultdict(set)                      # unit -> units it can summon
for v in rows(DT + '/Unit/AI/DT_BtlUnitAIParameter.json').values():
    ids = [v.get('fightSkillId'), v.get('chaseSkillId'), v.get('silenceFightId')] + v.get('counterSkillIdList', []) +           v.get('highRiskSkillIdList', []) + [x['SkillId'] for x in v.get('skillRandData1', []) + v.get('skillRandData2', [])]
    for sid in ids:
        for b in (skills.get(sid) or {}).get('effectBundleList', []):
            e = effects.get(b.get('effectId'))
            if not e:
                continue
            if e['EffectType'] in ('eSkillEffectType::SummonUnit', 'eSkillEffectType::SummonUnitBackCounter'):
                summons[v['ID']].add(e['ParamList'][1])
            elif e['EffectType'] == 'eSkillEffectType::SummonGroup':
                summons[v['ID']].update(bgroups.get(e['ParamList'][0], []))
# 6. mode changes: an AI blueprint calls CPP_BtlUnitAI:ChangeParameter(<unit id>) to turn its unit into another one.
#    BP_BtlUnitAI_<aiId>*.json (ffr-dump tree with FFR_SCRIPT=1) -> units whose AI row has that aiId.
def change_targets(bp):
    out = set()

    def walk(o, call=None):
        if isinstance(o, dict):
            if o.get('Token', '').endswith('Function'):
                sn = o.get('Function') or o.get('StackNode')
                call = sn.get('ObjectName') if isinstance(sn, dict) else call
            if o.get('Token') == 'EX_IntConst' and call and call.endswith(":ChangeParameter'"):
                out.add(o['Value'])
            for v in o.values():
                walk(v, call)
        elif isinstance(o, list):
            for x in o:
                walk(x, call)
    walk(bp)
    return out


ai_units = collections.defaultdict(set)
for v in rows(DT + '/Unit/AI/DT_BtlUnitAIParameter.json').values():
    if v.get('aiId', -1) != -1:
        ai_units[v['aiId']].add(v['ID'])
for f in glob.glob(X + '/json/BP_AI_script/**/BP_BtlUnitAI_*.json', recursive=True):
    m = re.match(r'BP_BtlUnitAI_(\d+)', os.path.basename(f))
    if m:
        for u in ai_units.get(int(m.group(1)), ()):
            summons[u] |= change_targets(json.load(open(f, encoding='utf8')))

changed = True
while changed:
    changed = False
    for u, called in summons.items():
        for c in called:
            for a, kinds in list(sources.get(u, {}).items()):
                if 'summon' not in sources[c][a]:
                    sources[c][a].add('summon'); changed = True     # 'summon' covers mode changes too

# ---------- enemies ----------
units = {v['ID']: (rk, v) for rk, v in rows(DT + '/Unit/DT_UnitParameter.json').items()}
enemies, cut = {}, []
for uid, (rk, v) in sorted(units.items()):
    if v.get('Category') not in ('eUnitCategory::Enemy', 'eUnitCategory::Boss'):
        continue
    name = text(v['Name'])
    if uid in sources:
        enemies[uid] = {'row': rk, 'name': name, 'boss': v.get('IsBoss'), 'areas': {a: sorted(k) for a, k in sorted(sources[uid].items())}}
    else:
        cut.append((uid, rk, name))
not_enemy = sorted(u for u in sources if u not in units or units[u][1].get('Category') not in ('eUnitCategory::Enemy', 'eUnitCategory::Boss'))

all_areas = sorted({a for e in enemies.values() for a in e['areas']})
labels = {a: ('Colosseum' if a == 'colosseum:' else area_label(a)) for a in all_areas}
json.dump({'areas': labels, 'enemies': enemies, 'unresolved': unresolved},
          open(X + '/locations.json', 'w', encoding='utf8'), ensure_ascii=False, indent=1)

with open(X + '/locations_report.txt', 'w', encoding='utf8') as w:
    w.write('enemy units: %d with an area, %d with none (cut?)\n' % (len(enemies), len(cut)))
    w.write('areas: %d\n' % len(all_areas))
    w.write('unit ids in battle groups that are not Enemy-category units: %s\n' % not_enemy)
    unused = sorted(set(encount_tables) - used_tables)
    w.write('encounter tables no actor uses (%d): %s\n' % (len(unused), [os.path.basename(t) for t in unused]))
    kinds = collections.Counter(u['kind'] + ': ' + u['why'].split(' ')[0] for u in unresolved)
    w.write('unresolved battle sources: %s\n\n' % dict(kinds))
    for a in all_areas:
        w.write('AREA %-40s %s\n' % (a, labels[a]))
    w.write('\n')
    for uid, e in enemies.items():
        w.write('%5d %-28s %-24s boss=%s  %s\n' % (uid, e['name'], e['row'], e['boss'],
                '; '.join('%s[%s]' % (labels[a], ','.join(k)) for a, k in e['areas'].items())))
    w.write('\nNO AREA (cut content, or a source this script does not read yet):\n')
    for uid, rk, name in cut:
        w.write('%5d %-28s %s\n' % (uid, name, rk))
    w.write('\nUNRESOLVED:\n')
    for u in unresolved:
        w.write(json.dumps(u, ensure_ascii=False) + '\n')
print(open(X + '/locations_report.txt', encoding='utf8').read()[:1500])
