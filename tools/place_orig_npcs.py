# 功能 NPC / 設施 搬入原版許昌 (城內街 xuchang_o + 各室內 xcNNNN)。座標係自動估 (深入行走區、互相隔開、避開門/出生點)，之後人手調。
# 用法: python tools/place_orig_npcs.py   (可重跑，結果固定)
import json, io, os
C = os.path.join(os.path.dirname(__file__), '..', 'client', 'data')

# 室內分配: 對應 named_locations.tsv 各室內嘅 NPC 名
IN = {
 'shop:herbalist': 'xc1903', 'shop:weapon': 'xc1904', 'shop:armor': 'xc1908',
 'fac:pharmacy': 'xc1903', 'fac:school': 'xc1905', 'fac:temple': 'xc1906',
 'fac:training': 'xc1907', 'fac:trainer': 'xc1907', 'fac:forge': 'xc1911', 'fac:workshop': 'xc1910',
 'fac:kitchen': 'xc1924', 'fac:donate_xc': 'xc1901', 'fac:stable_xc': 'xc1914',
 'qn:court_official_tool': 'xc1901', 'qn:court_harm': 'xc1901', 'qn:court_rat': 'xc1901', 'qn:court_thief': 'xc1901',
 'qn:town_head': 'xc1901',
 'qn:training_recruit': 'xc1907', 'qn:recruit_officer': 'xc1907', 'qn:battle_herald': 'xc1907',
 
 'qn:shenjing_lao': 'xc1906', 'qn:zixu': 'xc1906',
 'qn:luopo_lao': 'xc1902',
}
# 城內街 (其餘全部): 食坊/雜貨/工具 = 街邊攤
CITY = 'xuchang_o'

def jl(f):
    return json.load(open(os.path.join(C, f), encoding='utf8'))
def jw(f, d):
    s = json.dumps(d, ensure_ascii=False, indent=1) + '\n'
    open(os.path.join(C, f), 'w', encoding='utf8', newline='\n').write(s)

maps = jl('maps.json')
MD = {m['id']: m for m in maps['maps']}
walk = {}
def load(mid):
    if mid not in walk:
        rows = open(os.path.join(C, 'maps', mid + '.txt'), encoding='utf8').read().split('\n')
        walk[mid] = [r for r in rows if r != '']
    return walk[mid]

def blocked_zones(mid):
    z = []
    sp = MD[mid]['spawn']; z.append((sp[0], sp[1], 3))
    for p in maps['portals']:
        if p['map'] != mid: continue
        if 'rect' in p:
            x1, y1, x2, y2 = p['rect']; z.append((x1 - 3, y1 - 3, x2 + 3, y2 + 3))
        else:
            z.append((p['x'] - 3, p['y'] - 3, p['x'] + 3, p['y'] + 3))
        if 'land' in p: z.append((p['land'][0], p['land'][1], 3))
    return z
def in_zone(x, y, zs):
    for z in zs:
        if len(z) == 3:
            if max(abs(x - z[0]), abs(y - z[1])) <= z[2]: return True
        elif z[0] <= x <= z[2] and z[1] <= y <= z[3]: return True
    return False

def pick(mid, n, taken, near_spawn=False):
    g = load(mid); H = len(g); W = len(g[0])
    zs = blocked_zones(mid)
    def ok(x, y, r):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                xx, yy = x + dx, y + dy
                if not (0 <= xx < W and 0 <= yy < H) or g[yy][xx] != '.': return False
        return True
    sp = MD[mid]['spawn']
    cands = [(x, y) for y in range(H) for x in range(W) if ok(x, y, 2) and not in_zone(x, y, zs)]
    if near_spawn:
        cands = [c for c in cands if 5 <= max(abs(c[0] - sp[0]), abs(c[1] - sp[1])) <= 32]
    cx = sum(c[0] for c in cands) / len(cands); cy = sum(c[1] for c in cands) / len(cands)
    out = []
    pool = sorted(cands, key=lambda c: (c[0] - cx) ** 2 + (c[1] - cy) ** 2)
    if not near_spawn: pool = pool[:max(60, len(pool) // 2)]
    gap = 4 if not near_spawn else 5
    for c in (pool if near_spawn else pool):
        if all(max(abs(c[0] - t[0]), abs(c[1] - t[1])) >= gap for t in taken + out):
            out.append(c)
            if len(out) == n: break
    # 位置唔夠 → 放寬間距
    gap2 = gap
    while len(out) < n and gap2 > 1:
        gap2 -= 1
        for c in pool:
            if c not in out and all(max(abs(c[0] - t[0]), abs(c[1] - t[1])) >= gap2 for t in taken + out):
                out.append(c)
                if len(out) == n: break
    return out

shops = jl('shops.json'); fac = jl('facilities.json'); qn = jl('quest_npcs.json')
items = []   # (key, dict)
for s in shops['shops']:
    if s['map'] == 'xuchang': items.append(('shop:' + s['id'], s))
for k, v in fac.items():
    if isinstance(v, dict) and v.get('map') == 'xuchang': items.append(('fac:' + k, v))
for n in qn['npcs']:
    if n['map'] == 'xuchang': items.append(('qn:' + n['id'], n))
by = {}
for k, d in items:
    by.setdefault(IN.get(k, CITY), []).append((k, d))
# 驛站(原版)/公佈欄同街 NPC 一齊避位
taken_city = []
st = None
if st: taken_city.append((st['x'], st['y']))
if 'inn' in shops and shops['inn'].get('map') == 'xc1902': pass
for mid, lst in by.items():
    pts = pick(mid, len(lst), taken_city if mid == CITY else [], near_spawn=(mid == CITY))
    assert len(pts) == len(lst), (mid, len(pts), len(lst))
    for (k, d), (x, y) in zip(lst, pts):
        d['map'] = mid; d['x'] = x; d['y'] = y
    print(mid, [k for k, _ in lst])
# 結婚 4 NPC 要貼埋一齊 (行近一個就掂到全部): 以第一個做錨，其餘放 2 格內
mar = [d for k, d in items if k.startswith('qn:marry_')]
g = load(CITY)
ax, ay = mar[0]['x'], mar[0]['y']
offs = [(2, 0), (0, 2), (2, 2)]
for d, (dx, dy) in zip(mar[1:], offs):
    nx, ny = ax + dx, ay + dy
    assert g[ny][nx] == '.', 'marry 位唔行得'
    d['x'], d['y'] = nx, ny
jw('shops.json', shops); jw('facilities.json', fac); jw('quest_npcs.json', qn)
