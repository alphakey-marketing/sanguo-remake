# 舊版 ASCII 圖 (80 張, 非 orig) 永久封存: 由 maps/portals/landmarks/shops/facilities/spawns/battles/scenes 抽走,
# 備份入 client/data/archive/。天下大地圖改用原版 35 城 (city_links.json)。可重跑 (冇舊圖就乜都唔做)。
# 用法: python tools/archive_legacy.py
import json, os, shutil
D = os.path.join(os.path.dirname(__file__), '..', 'client', 'data')
A = os.path.join(D, 'archive')
NL = chr(10)

def jl(f):
    return json.load(open(os.path.join(D, f), encoding='utf8'))

def jw(f, d):
    open(os.path.join(D, f), 'w', encoding='utf8', newline=NL).write(json.dumps(d, ensure_ascii=False, indent=1) + NL)

def main():
    os.makedirs(os.path.join(A, 'maps'), exist_ok=True)
    md = jl('maps.json')
    old = {m['id'] for m in md['maps'] if not m.get('orig')}
    if not old:
        print('冇舊圖，done'); return
    bak = {'maps': [m for m in md['maps'] if m['id'] in old],
           'portals': [p for p in md['portals'] if p['map'] in old],
           'landmarks': [l for l in md['landmarks'] if l['map'] in old],
           'world': md['world']}
    json.dump(bak, open(os.path.join(A, 'legacy_maps.json'), 'w', encoding='utf8', newline=NL), ensure_ascii=False, indent=1)
    for i in old:
        s = os.path.join(D, 'maps', i + '.txt')
        if os.path.exists(s):
            shutil.move(s, os.path.join(A, 'maps', i + '.txt'))
    md['maps'] = [m for m in md['maps'] if m['id'] not in old]
    md['portals'] = [p for p in md['portals'] if p['map'] not in old]
    md['landmarks'] = [l for l in md['landmarks'] if l['map'] not in old]
    # 天下大地圖: 原版 35 城 (座標由 city_links 正規化)
    cl = jl('city_links.json')
    wd = jl('world.json')
    cid = {m['cityOf']: m['id'] for m in md['maps'] if m.get('cityOf') and m['id'] == m.get('orig', m['id']) and m['name'].endswith('（原版）')}
    byname = {c['name']: c['id'] for c in wd['cities']}
    xs = [v['x'] for v in cl['cities'].values()]; ys = [v['y'] for v in cl['cities'].values()]
    nodes, ids = [], {}
    for nm, v in cl['cities'].items():
        c = byname.get(nm)
        if c is None or c not in cid and c != 'xuchang':
            continue
        ids[nm] = c
        nodes.append({'id': c, 'name': nm, 'province': next(x['province'] for x in wd['cities'] if x['id'] == c),
                      'x': round(0.04 + 0.92 * (v['x'] - min(xs)) / (max(xs) - min(xs)), 3),
                      'y': round(0.04 + 0.92 * (v['y'] - min(ys)) / (max(ys) - min(ys)), 3), 'map': cid.get(c, 'xuchang_o'), 'city': True})
    edges = [[ids[l['a']], ids[l['b']]] for l in cl['links'] if l['a'] in ids and l['b'] in ids]
    md['world'] = {'_note': md['world']['_note'], 'nodes': nodes, 'edges': edges}
    jw('maps.json', md)

    sh = jl('shops.json')
    o_inn = next(i for i in sh['inns'] if i['id'] == 'xuchang_o')
    sh['inn'] = {'x': o_inn['x'], 'y': o_inn['y'], 'restCost': o_inn['restCost'], 'map': o_inn['map'], 'id': 'xuchang',
                 'npc': sh['inn'].get('npc', {'name': '客棧掌櫃', 'sprite': 52061})}
    sh['inns'] = [i for i in sh['inns'] if i['map'] not in old and i['id'] != 'xuchang_o']
    sh['shops'] = [s for s in sh['shops'] if s.get('map') not in old]
    jw('shops.json', sh)

    f = jl('facilities.json')
    for k in [k for k, v in f.items() if isinstance(v, dict) and v.get('map') in old]:
        del f[k]
    jw('facilities.json', f)

    mo = jl('monsters.json')
    mo['spawns'] = [s for s in mo['spawns'] if s.get('zone') not in old]
    json.dump(mo, open(os.path.join(D, 'monsters.json'), 'w', encoding='utf8', newline=NL), ensure_ascii=False, indent=1)

    for fn, key in (('battles.json', 'battles'), ('scenes.json', 'scenes')):
        d = jl(fn)
        json.dump(d, open(os.path.join(A, 'legacy_' + fn), 'w', encoding='utf8', newline=NL), ensure_ascii=False, indent=1)
        d[key] = []
        jw(fn, d)
    print('archived', len(old), 'maps')

if __name__ == '__main__':
    main()
