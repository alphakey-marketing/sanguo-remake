# [通用] 新城(原版)功能 NPC / 商店 / 設施: 由許昌同類條目複製 (id 加 _cl)，放入陳留各室內 xc17NN + 城街 xc1700。座標自動估，之後人手調。
# 室內分配按 named_locations.tsv (陳留 1700~1724)。公佈欄/練兵場/廟 暫不複製；官宅(donate)+驛站(station) 同新野一樣係通用設施 (flag 驅動)；義舉證明仍只許昌官員受理。
# 用法: python tools/place_city_npcs.py   (可重跑，先清走舊 _cl 條目)
import json, os, copy
C = os.path.join(os.path.dirname(__file__), '..', 'client', 'data')


def jl(f): return json.load(open(os.path.join(C, f), encoding='utf8'))
def jw(f, d): open(os.path.join(C, f), 'w', encoding='utf8', newline='\n').write(json.dumps(d, ensure_ascii=False, indent=1) + '\n')


maps = jl('maps.json'); MD = {m['id']: m for m in maps['maps']}
_walk = {}
def load(mid):
    if mid not in _walk: _walk[mid] = [r for r in open(os.path.join(C, 'maps', mid + '.txt'), encoding='utf8').read().split('\n') if r != '']
    return _walk[mid]


def zones(mid):
    sp = MD[mid]['spawn']; z = [(sp[0], sp[1], 3)]
    for p in maps['portals']:
        if p['map'] != mid: continue
        if 'rect' in p: x1, y1, x2, y2 = p['rect']; z.append((x1 - 3, y1 - 3, x2 + 3, y2 + 3))
        else: z.append((p['x'] - 3, p['y'] - 3, p['x'] + 3, p['y'] + 3))
        if 'land' in p: z.append((p['land'][0], p['land'][1], 3))
    return z
def in_zone(x, y, zs):
    return any((max(abs(x - z[0]), abs(y - z[1])) <= z[2]) if len(z) == 3 else (z[0] <= x <= z[2] and z[1] <= y <= z[3]) for z in zs)


def pick(mid, n, near_spawn=False):
    g = load(mid); H = len(g); W = len(g[0]); zs = zones(mid); sp = MD[mid]['spawn']
    def ok(x, y, r): return all(0 <= x + dx < W and 0 <= y + dy < H and g[y + dy][x + dx] == '.' for dy in range(-r, r + 1) for dx in range(-r, r + 1))
    cands = [(x, y) for y in range(H) for x in range(W) if ok(x, y, 2) and not in_zone(x, y, zs)]
    if near_spawn: cands = [c for c in cands if 5 <= max(abs(c[0] - sp[0]), abs(c[1] - sp[1])) <= 40]
    assert cands, mid
    cx = sum(c[0] for c in cands) / len(cands); cy = sum(c[1] for c in cands) / len(cands)
    pool = sorted(cands, key=lambda c: (c[0] - cx) ** 2 + (c[1] - cy) ** 2)
    out = []
    for gap in (5, 4, 3, 2, 1):
        for c in pool:
            if c not in out and all(max(abs(c[0] - t[0]), abs(c[1] - t[1])) >= gap for t in out):
                out.append(c)
                if len(out) == n: return out
    raise SystemExit('位唔夠 ' + mid)



# 設施表 (docs/plan/city_facilities.md 同 importer 嘅室內命名)：按室內名關鍵字決定放咩。cityOf 無 world.json 城，故唔放公佈欄/救災區
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import import_orig_interiors as _I
CITIES = {c: (n, _I.CITY_SLUG[c]) for c, n in _I.NEWCITIES.items()}      # importer 匯入咗室內嘅城
ROOM_FAC = {'官宅': 'donate_xc', '藥房': 'pharmacy', '私塾': 'school', '廟': 'temple', '練兵場': 'training', '木工廠': 'workshop', '打鐵鋪': 'forge',
            '馬廄': 'stable_xc', '驛站': 'station_xc', '廚房': 'kitchen'}
ROOM_SHOP = {'藥房': 'herbalist', '武器店': 'weapon'}
EXTRA_ROOM = {26: {14: 'stable_xc'}}                 # 洛陽 2614 = 獸醫師/馬術師 (馬廄)
STREET_SHOP = ['tool', 'food', 'grocery']
TYPED = {'school': 'school', 'temple': 'temple', 'training': 'training'}

shops = jl('shops.json'); fac = jl('facilities.json')
for c in CITIES:
    sfx = '_cl%d' % c
    shops['shops'] = [s for s in shops['shops'] if not s['id'].endswith(sfx)]
    for k in [k for k in fac if k.endswith(sfx)]: del fac[k]
    shops['inns'] = [i for i in shops['inns'] if not i['id'].startswith('c%d_' % c)]
tmpl = {s['id']: s for s in shops['shops']}
tmpl.update({s['id']: s for s in shops['shops'] if s['id'] in ('tool', 'food', 'grocery', 'weapon', 'herbalist')})
inn_t = [i for i in shops['inns'] if i['id'] == 'xuchang_o'][0]

for c, (cn, slug) in CITIES.items():
    sfx = '_cl%d' % c; city_map = 'xc%d00' % c
    todo = []   # (map, kind, src)
    for m in maps['maps']:
        mid = m['id']
        if not (mid.startswith('xc%d' % c) and mid[2:].isdigit() and len(mid) == 6) or m.get('orphan'): continue
        n = int(mid[2:]) % 100; nm = m['name'].split('·')[-1]
        if n in EXTRA_ROOM.get(c, {}): todo.append((mid, 'fac', EXTRA_ROOM[c][n]))
        if '客棧' in nm: todo.append((mid, 'inn', 'xuchang_o'))
        for k, f in ROOM_FAC.items():
            if k in nm: todo.append((mid, 'fac', f))
        for k, s in ROOM_SHOP.items():
            if k in nm: todo.append((mid, 'shop', s))
    for sid in STREET_SHOP: todo.append((city_map, 'shop', sid))
    by = {}
    for t in todo: by.setdefault(t[0], []).append(t)
    for mid, lst in by.items():
        pts = pick(mid, len(lst), near_spawn=(mid == city_map))
        for (m, kind, src), (x, y) in zip(lst, pts):
            if kind == 'shop':
                n = copy.deepcopy(tmpl[src]); n['id'] = src + sfx; n['name'] = cn + n['name']
                n.update(map=m, x=x, y=y); shops['shops'].append(n)
            elif kind == 'inn':
                n = copy.deepcopy(inn_t); n['id'] = 'c%d_o' % c; n['name'] = cn + '客棧（原版）'
                n.update(map=m, x=x, y=y); shops['inns'].append(n)
            else:
                n = copy.deepcopy(fac[src]); n['name'] = n['name'].replace('許昌', cn) if '許昌' in n['name'] else cn + n['name']
                n.update(map=m, x=x, y=y)
                if src in TYPED: n['type'] = TYPED[src]
                if 'city' in n: n['city'] = cn if src.startswith('donate') else slug
                fac[src + sfx] = n
        print(c, mid, [t[2] for t in lst])
jw('shops.json', shops); jw('facilities.json', fac)
