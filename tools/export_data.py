"""Write the data file the mod ships: IDs and string-table keys only, no game text or assets.

Reads extracted/locations.json (tools/build_locations.py) and the dumped tables.
Writes data/bestiary_data.json:
  entries     one per in-game enemy name (design choice: fold units sharing a name). units[0] is the entry's main
              unit (lowest SortId); areas are area keys. An entry is listed only if some unit in it has an area.
  areas       area key -> {table, key} of its display name (resolved by the game at runtime)
  mapArea     map id -> area key, for recording where a battle happened (CurrentMapId)
  islandArea  island number (eMapIslandType) -> area key, used when the map is the world map (LastVisitedIsland)
  stageArea   unnamed cutscene-stage map id -> area keys it can be entered from (the runtime keeps the last
              named area instead when there are several)
  areaRegion  area key -> region (island number); an island counts as visited once any area of its region is
  stats       unit id -> scan data: name / traits as [string table, key], lv, hp, race, el {element: resistance},
              st {status: resistance}, drop [normal, rare, steal, rare steal] (enum numbers from the class dump)
  spriteBox   sprite path -> [x0, x1, y0, y1]: outline in sprite pixels from the canvas centre, y down, measured
  faces       unit id -> face icon texture path (battle timeline icon, by FaceIconId)
  spriteSize  sprite path -> {w, h, cy}: rough idle-pose size and body centre (tools/sprite_bounds.py), for scaling
"""
import collections, contextlib, io, json, os, re, runpy

with contextlib.redirect_stdout(io.StringIO()):
    g = runpy.run_path(os.path.join(os.path.dirname(__file__), 'build_locations.py'))

X = 'extracted'
locs = json.load(open(X + '/locations.json', encoding='utf8'))
units = {v['ID']: v for v in g['rows'](g['DT'] + '/Unit/DT_UnitParameter.json').values()
         if v['Category'] in ('eUnitCategory::Enemy', 'eUnitCategory::Boss')}
en_names = g['loc'].get('ST_UnitName', {})

groups = collections.defaultdict(list)
for uid, v in units.items():
    groups[en_names.get(v['Name']['Key']) or v['Name']['Key']].append(uid)

entries = []
for name, uids in groups.items():
    uids.sort(key=lambda u: (units[u]['SortId'], u))
    areas = sorted({a for u in uids for a in locs['enemies'].get(str(u), {}).get('areas', {})})
    if areas:
        entries.append({'units': uids, 'areas': areas})
entries.sort(key=lambda e: (units[e['units'][0]]['SortId'], e['units'][0]))


def name_ref(aid):
    kind, key = aid.split(':', 1)
    if kind in ('name', 'island') and key in g['loc'].get('ST_MAP_NAME', {}):
        return {'table': '/Game/Datatable/Strings/Map/ST_MAP_NAME.ST_MAP_NAME', 'key': key}
    if kind == 'colosseum':
        return {'table': None, 'key': None}       # TODO: find the colosseum's map name key
    return {'table': None, 'key': None}           # unnamed map that nothing enters: confirm in game


all_areas = sorted({a for e in entries for a in e['areas']})

# the runtime reads the island as a number (CPP_MapManager:GetCurrentIslandType); numbers from the class dump
enum_src = open(X + '/CXXHeaderDump/mucha_enums.hpp', encoding='utf8').read()
enum_body = re.search(r'enum class eMapIslandType \{(.*?)\};', enum_src, re.S).group(1)
island_num = {'eMapIslandType::' + k: int(v) for k, v in re.findall(r'(\w+) = (\d+)', enum_body)}


# list order of areas: by region (world map island first, then its towns/dungeons by map id); shared "Com" maps last
def area_order(aid):
    if aid.startswith('island:'):
        nums = [island_num[i] for i, x in g['islands'].items() if 'island:' + (x['nameKey'] or '') == aid]
        return (min(nums) if nums else 99, 0)
    mids = [mid for mid in g['maps'] if g['area_of'](mid) == aid]
    regions = [int(g['maps'][m]['row'][:2]) for m in mids if g['maps'][m]['row'][:2].isdigit()]
    region = min([r for r in regions if r > 0] or [99])
    return (region, min(mids) if mids else 99999)


# each listed unit's battle sprite (SpriteStudio 6 project) as an asset path, from DT_BtlUnitAsset
sprite_rows = g['rows'](g['DT'] + '/Asset/Battle/Unit/DT_BtlUnitAsset.json')
sprite_of = {v['ID']: v['animationAssetList'][0]['Ss6Project']['AssetPathName']
             for v in sprite_rows.values() if v.get('animationAssetList')}
sprites = {str(u): sprite_of[u] for e in entries for u in e['units'] if u in sprite_of}
# each listed unit's scan data (DT_UnitParameter) as numbers and string-table keys: the mod reads these instead of
# asking the game (UE4SS's copy of GetUnitParameterById's struct points into freed memory once the call returns)
def enum_values(name):
    body = re.search(r'enum class %s \{(.*?)\};' % name, enum_src, re.S).group(1)
    return {k: int(v) for k, v in re.findall(r'(\w+) = (\d+)', body)}
E = {n: enum_values(n) for n in ('eElement', 'eResistance', 'eRace', 'eUnitStatusCondition')}
def ev(enum, value):
    return E[enum].get(value.split('::')[-1], 0)
def text_ref(t):
    return [t['TableId'], t['Key']] if t and t.get('TableId') and t.get('Key') else None
def scan_data(v):
    return {
        'name': text_ref(v['Name']), 'lv': v['Level'], 'hp': v['MaxHitPoint'], 'race': ev('eRace', v['Race']),
        'traits': [r for r in (text_ref(t) for t in v.get('Traits') or []) if r],
        'el': {str(ev('eElement', x['Key'])): ev('eResistance', x['Value'])
               for x in v['ElementResistanceList'] if ev('eResistance', x['Value'])},
        'st': {str(ev('eUnitStatusCondition', x['Key'])): x['Value']
               for x in v['StatusConditionResistanceList'] if x['Value']},
        'drop': [v['DropNormalItem'], v['DropRareItem'], v['StealNormalItem'], v['StealRareItem']],
    }
stats = {str(u): scan_data(units[u]) for e in entries for u in e['units']}

# each listed unit's face icon (the battle timeline's), by its FaceIconId in DA_UnitIcon_Timeline
face_map = {int(x['Key']): x['Value']['AssetPathName'] for x in json.load(open(
    X + '/json/Datatable/UI/Unit/Asset/DA_UnitIcon_Timeline.json', encoding='utf8'))['Properties']['assetMap']}
faces = {str(u): face_map[units[u]['FaceIconId']] for e in entries for u in e['units'] if units[u].get('FaceIconId') in face_map}
bounds = json.load(open(X + '/sprite_bounds.json', encoding='utf8'))
sprite_size = {p: bounds[p] for p in sorted(set(sprites.values())) if p in bounds}
# each sprite's outline as the game draws it (tools/sprite_measure.py, from the Bestiary's dev measure mode)
measured = json.load(open(X + '/sprite_measured.json', encoding='utf8')) if os.path.exists(X + '/sprite_measured.json') else {}
sprite_box = {p: measured[p] for p in sorted(set(sprites.values())) if p in measured}

# enemy HP multiplier per difficulty (DT_GameDifficultyParam), keyed by eGameDifficulty number
diff_enum = {'Easy': 0, 'Normal': 1, 'Expert': 2}
hp_rate = {str(diff_enum[v['difficulty'].split('::')[1]]): v['EnemyHpRate']
           for v in g['rows'](g['DT'] + '/Difficulty/DT_GameDifficultyParam.json').values()}

out = {
    'gameBuild': 24250053,
    'enemyHpRate': hp_rate,
    'sprites': sprites,
    'spriteSize': sprite_size,
    'spriteBox': sprite_box,
    'faces': faces,
    'stats': stats,
    'worldMapId': g['WORLD'],
    'areas': {a: name_ref(a) for a in all_areas},
    'areaOrder': sorted(all_areas, key=area_order),
    'areaRegion': {a: area_order(a)[0] for a in all_areas},
    'mapArea': {str(mid): g['area_of'](mid) for mid in sorted(g['maps']) if not g['area_of'](mid).startswith('map:')},
    'islandArea': {str(island_num[isl]): 'island:' + i['nameKey'] for isl, i in sorted(g['islands'].items()) if i['nameKey']},
    'stageArea': {a[4:]: sorted(v) for a, v in sorted(g['stage_alias'].items()) if v},
    'entries': entries,
}
os.makedirs('data', exist_ok=True)
json.dump(out, open('data/bestiary_data.json', 'w', encoding='utf8'), indent=1)
print('entries', len(entries), 'areas', len(all_areas), 'units in entries', sum(len(e['units']) for e in entries),
      'unplaced names', len(groups) - len(entries))


def lua(v, ind=''):
    """the same data as a Lua table, for the UE4SS mod (require 'bestiary_data')"""
    if isinstance(v, dict):
        items = [('[%s]' % k if isinstance(k, int) else '[%s]' % json.dumps(k)) + ' = ' + lua(x, ind + ' ') for k, x in v.items()]
        return '{' + ', '.join(items) + '}'
    if isinstance(v, list):
        return '{' + ', '.join(lua(x, ind) for x in v) + '}'
    if v is None:
        return 'nil'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    return json.dumps(v)


with open('data/bestiary_data.lua', 'w', encoding='utf8') as f:
    f.write('-- generated by tools/export_data.py from data/bestiary_data.json; do not edit\nreturn ' + lua(out) + '\n')
print('wrote data/bestiary_data.lua')
