# 陳留(原版)功能 NPC / 商店 / 設施: 由許昌同類條目複製 (id 加 _cl)，放入陳留各室內 xc17NN + 城街 xc1700。座標自動估，之後人手調。
# 室內分配按 named_locations.tsv (陳留 1700~1724)。公佈欄/練兵場/廟 暫不複製；官宅(donate)+驛站(station) 同新野一樣係通用設施 (flag 驅動)；義舉證明仍只許昌官員受理。
# 用法: python tools/place_chenliu_npcs.py   (可重跑，先清走舊 _cl 條目)
import json, os, copy
C = os.path.join(os.path.dirname(__file__), '..', 'client', 'data')
SFX = '_cl'
CITY = 'xc1700'


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


# 許昌模板 id -> 陳留室內。shops 用 shops.json id，fac 用 facilities.json key
SHOP_IN = {'weapon': 'xc1704', 'herbalist': 'xc1703'}
SHOP_STREET = ['tool', 'food', 'grocery']          # 城街攤
FAC_IN = {'pharmacy': 'xc1703', 'workshop': 'xc1710', 'forge': 'xc1711', 'kitchen': 'xc1724', 'school': 'xc1705', 'stable_xc': 'xc1714', 'donate_xc': 'xc1701', 'station_xc': 'xc1715',
          'bulletin_xc': CITY, 'relief_xc': 'xc1725'}      # 救災區放陳留外圍25 (近正中城模型以外嘅空地)
INN_IN = 'xc1702'

shops = jl('shops.json'); fac = jl('facilities.json')
# 清走舊複製
shops['shops'] = [s for s in shops['shops'] if not s['id'].endswith(SFX)]
shops['inns'] = [i for i in shops['inns'] if not i['id'].endswith(SFX)]
for k in [k for k in fac if k.endswith(SFX)]: del fac[k]

todo = []   # (列表種類, 新條目)
tmpl = {s['id']: s for s in shops['shops']}
for sid, mid in SHOP_IN.items(): todo.append((mid, 'shop', sid))
for sid in SHOP_STREET: todo.append((CITY, 'shop', sid))
for k, mid in FAC_IN.items(): todo.append((mid, 'fac', k))
todo.append((INN_IN, 'inn', 'xuchang_o'))

by = {}
for t in todo: by.setdefault(t[0], []).append(t)
for mid, lst in by.items():
    pts = pick(mid, len(lst), near_spawn=(mid == CITY))
    for (m, kind, src), (x, y) in zip(lst, pts):
        if kind == 'shop':
            n = copy.deepcopy(tmpl[src]); n['id'] = src + SFX; n['name'] = '陳留' + n['name']
            n.update(map=m, x=x, y=y); shops['shops'].append(n)
        elif kind == 'inn':
            n = copy.deepcopy([i for i in shops['inns'] if i['id'] == src][0]); n['id'] = 'chenliu_o'; n['name'] = '陳留客棧（原版）'
            n.update(map=m, x=x, y=y); shops['inns'].append(n)
        else:
            n = copy.deepcopy(fac[src]); n['name'] = n['name'].replace('許昌', '陳留') if '許昌' in n['name'] else '陳留' + n['name']
            n.update(map=m, x=x, y=y)
            if src == 'school': n['type'] = 'school'
            if 'cityId' in n: n['cityId'] = 'chenliu'
            if 'city' in n: n['city'] = '陳留' if src.startswith('donate') else 'chenliu'     # 官宅 city = 顯示名；馬廄 city = 城 id
            fac[src + SFX] = n
    print(mid, [t[2] for t in lst])
jw('shops.json', shops); jw('facilities.json', fac)
