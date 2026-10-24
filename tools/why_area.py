"""Debug: which events/battle groups put a unit in an area. usage: why_area.py <unitId> <area substring>"""
import runpy, sys, io, contextlib
uid, sub = int(sys.argv[1]), sys.argv[2]
with contextlib.redirect_stdout(io.StringIO()):
    g = runpy.run_path('tools/build_locations.py')
for gid, areas in g['group_areas'].items():
    if uid in g['bgroups'][gid] and any(sub in a for a in areas):
        evs = [k for k, v in g['events'].items() if v.get('encountGroupId') == gid]
        print('group', gid, dict(areas), 'events', evs)
        for e in evs:
            v = g['events'][e]; tl = v.get('TransitionLocation') or {}
            print('   ', e, v.get('Description'), 'areas', g['event_areas'][e], 'tl.mapId', tl.get('mapId'), 'island', tl.get('overrideIslandType'))
            print('    referenced by:', [k for k, w in g['events'].items() if e in set(g['chained'](w))][:5])
