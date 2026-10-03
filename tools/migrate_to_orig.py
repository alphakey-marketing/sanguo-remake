# 舊版 ASCII 圖 NPC → 原版圖 (舊圖永久封存)。可重跑: 只處理仲喺舊圖嘅 NPC。
# 用法: python tools/migrate_to_orig.py   (add_orig_quests.py 之後行)
import json, os
C = os.path.join(os.path.dirname(__file__), '..', 'client', 'data')

REMAP = {
    'xuchang': 'xuchang_o', 'field_1': 'xc1925', 'xinye': 'xc2700', 'xiangyang': 'xc2900', 'changsha': 'xc2200',
    'xiaopei': 'xc1400', 'wancheng': 'xc2800', 'runan_city': 'xc2000', 'luoyang': 'xc2600', 'xiapi': 'xc1500',
    'lingling': 'xc3200', 'chenliu': 'xc1700', 'jingzhou': 'xc2925', 'gangkou': 'xc2125', 'runan_road': 'xc2025',
    'hanshui': 'xc2925', 'wancheng_road': 'xc2825', 'yudu': 'xc2851', 'longzhong': 'xc2925',
    'xy_prison': 'xc2901', 'caolu': 'xc2902', 'hefu': 'xc2601', 'ding_fu': 'xc2001', 'chengfu': 'xc2602',
    'runan_f3': 'xc2053', 'runan_f5': 'xc2052', 'runan_f8': 'xc2051',
}

def jl(f):
    return json.load(open(os.path.join(C, f), encoding='utf8'))

def grid(mid):
    rows = open(os.path.join(C, 'maps', mid + '.txt'), encoding='utf8').read().split('\n')
    return [r for r in rows if r != '']

def ok(g, x, y):
    return 0 <= y < len(g) and 0 <= x < len(g[y]) and g[y][x] in '.:=,_+'

def snap(g, x, y, others):
    for r in range(0, 40):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) == r and ok(g, x + dx, y + dy) \
                        and all(max(abs(x + dx - ox), abs(y + dy - oy)) >= 2 for ox, oy in others):
                    return x + dx, y + dy
    raise SystemExit('搵唔到位 %s %d,%d' % ('?', x, y))

def spread(tm, others):
    """揀一格：喺某建築(傳送門)附近，離所有門 >=3、八鄰皆可行，並同 others 盡量遠 (目標 >=10 格，farthest-point)。"""
    tm_vis = os.path.exists(os.path.join(C, 'orig_maps', tm + '.json'))
    g = grid(tm)
    ports = [(q['x'], q['y']) for q in jl('maps.json')['portals'] if q['map'] == tm]
    lands = [tuple(q['land']) if q.get('land') else (q['x'], q['y']) for q in jl('maps.json')['portals'] if q['map'] == tm]
    cand = []
    for ly in range(len(g)):
        for lx in range(len(g[ly])):
            if not all(ok(g, lx + a, ly + b) for a in (-1, 0, 1) for b in (-1, 0, 1)):
                continue
            if any(max(abs(lx - a), abs(ly - b)) < 3 for a, b in ports):
                continue
            if lands and min(max(abs(lx - a), abs(ly - b)) for a, b in lands) > 8:
                continue
            if tm_vis and not visible(tm, lx, ly):
                continue
            cand.append((lx, ly))
    if not cand:
        return None
    def score(c):
        d = min([max(abs(c[0] - a), abs(c[1] - b)) for a, b in others] or [99])
        return (min(d, 10), -min(max(abs(c[0] - a), abs(c[1] - b)) for a, b in lands) if lands else 0)
    best = max(cand, key=score)
    return best


def place_near(tm, i, others):
    r = spread(tm, others)
    if r:
        return r
    g = grid(tm)
    maps = {m['id']: m for m in jl('maps.json')['maps']}
    sp = maps[tm].get('spawn') or [len(g[0]) // 2, len(g) // 2]
    return snap(g, sp[0] + 8 + 5 * (i % 5), sp[1] + 4 * (i // 5) + 3, others)


def main():
    maps = {m['id']: m for m in jl('maps.json')['maps']}
    old = set(REMAP)           # 舊圖已封存 (maps.json 冇晒)，靠 REMAP 表認
    nd = jl('quest_npcs.json')
    placed = {}
    for n in nd['npcs']:
        if n['map'] not in old:
            placed.setdefault(n['map'], []).append((n['x'], n['y']))
    k = {}
    for n in nd['npcs']:
        if n['map'] not in old:
            continue
        tm = REMAP[n['map']]
        g = grid(tm)
        sp = maps[tm].get('spawn') or [len(g[0]) // 2, len(g) // 2]
        i = k.get(tm, 0); k[tm] = i + 1
        bx, by = sp[0] + 6 * (i % 4) - 9, sp[1] - 4 * (i // 4) - 3
        r = spread(tm, placed.setdefault(tm, []))
        x, y = r if r else snap(g, bx, by, placed[tm])
        placed[tm].append((x, y))
        n['map'], n['x'], n['y'] = tm, x, y
    # 汝南官宅 = 丁刺史府: 要丁原家鑰匙 (原 rn_ding 門鎖搬過嚟)
    md = jl('maps.json')
    for p in md['portals']:
        if p['id'] == 'xc_in_2001':
            p['gate'] = {'item': 56018, 'msg': '丁府大門深鎖，要有丁原家鑰匙先入得'}
    json.dump(md, open(os.path.join(C, 'maps.json'), 'w', encoding='utf8', newline=chr(10)), ensure_ascii=False, indent=1)
    json.dump(nd, open(os.path.join(C, 'quest_npcs.json'), 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
    print('ok moved', sum(k.values()))

if __name__ == '__main__':
    main()


# 許昌 NPC/武將 → 站喺邊座建築入口隔籬 (位置係估嘅)
AT = {'廟': ['神秘老人', '算命先生', '玄真道人'], '藥房': ['密醫'], '廚房': ['賣菜嬸', '禮餅商', '開餅盒師傅'],
      '客棧': ['茶館老闆', '郭嘉'], '官宅': ['禁衛大隊長', '朝廷官員', '曹操', '荀彧', '程昱', '滿寵', '鍾繇'],
      '虎威府': ['呂布', '典韋', '許褚', '夏侯惇'], '出城': ['許昌驛丞'], '老年人家': ['老丈'],
      '練兵場': ['轉職導師'], '私塾': ['黃師姐', '蔡邕'], '民宅': ['流浪狗', '巫姬婆', '斷情絕愛郎'],
      '打鐵鋪': ['蔡師傅'], '賭場': ['夢韶華'], '拍賣屋': ['商會長'], '王允府': ['林員外'],
      '劉備家': ['劉老', '徐庶', '劉備', '關羽', '張飛', '趙雲', '孫乾', '簡雍', '糜竺', '伊籍']}


INTERIOR = {'官宅': 'xc1901', '客棧': 'xc1902', '藥房': 'xc1903', '虎威府': 'xc1908', '練兵場': 'xc1907', '私塾': 'xc1905',
            '廟': 'xc1906', '打鐵鋪': 'xc1911', '拍賣屋': 'xc1913', '賭場': 'xc1916', '老年人家': 'xc1919', '廚房': 'xc1924',
            '王允府': 'xc1946', '劉備家': 'xc1947'}      # 街頭角色 (民宅/出城) 唔入屋


_OBJ = {}


def _objs(mid):
    """載入原版地圖物件 (非貼地) 嘅 alpha mask，用嚟判斷 NPC 會唔會畀物件遮住。回 (objs, walkable bytes, gw)"""
    if mid in _OBJ:
        return _OBJ[mid]
    import base64, zlib
    from PIL import Image
    jp = os.path.join(C, 'orig_maps', mid + '.json')
    if not os.path.exists(jp):
        _OBJ[mid] = ([], None, 0)
        return _OBJ[mid]
    d = jl('orig_maps/' + mid + '.json')
    wd = d.get('walk') or {}
    walk = zlib.decompress(base64.b64decode(wd['z'])) if wd else None
    gw = int(wd.get('w', 0)) if wd else 0
    out = []
    for o in d['objects']:
        f = os.path.join(C, '..', 'assets_orig', 'maps', mid, 'obj', str(o['n']) + '.png')
        if not os.path.exists(f):
            continue
        im = Image.open(f).convert('RGBA')
        a = im.split()[3]
        bb = a.getbbox()
        if not bb:
            continue
        x, y, w, h = int(o['x']), int(o['y']), im.width, im.height
        if bool(o.get('floor')) or str(o['n']).startswith('up6'):
            continue
        if walk is not None:                      # 貼地物件 (佔嘅格冇一格擋) 唔遮人
            cells = [walk[r * gw + c] for r in range(max(0, y // 16), (y + h - 1) // 16 + 1) for c in range(max(0, x // 16), min(gw - 1, (x + w - 1) // 16) + 1) if r * gw + c < len(walk)]
            if cells and not any(cells):
                continue
        out.append((x, y, w, h, y + bb[3], a))
    _OBJ[mid] = (out, walk, gw)
    return _OBJ[mid]


def visible(mid, x, y):
    """NPC 企 (x,y) 時，身體範圍 (約 50x72 px，腳底 = 格底) 有冇俾腳底更低嘅物件(牆/樓梯/屋簷)遮住"""
    objs, _, _ = _objs(mid)
    fx, fy = x * 16 + 8, y * 16 + 16
    pts = [(fx + dx, fy - dy) for dx in range(-22, 23, 6) for dy in range(2, 72, 6)]
    for ox, oy, w, h, bot, a in objs:
        if bot <= fy:
            continue
        for px, py in pts:
            lx, ly = px - ox, py - oy
            if 0 <= lx < w and 0 <= ly < h and a.getpixel((lx, ly)) > 40:
                return False
    return True


def _inside(mid, taken):
    """室內圖: 由出生點 (門口) BFS，揀行 7~16 步遠、離其他人 >=2 格嘅位"""
    g = grid(mid)
    md = next(m for m in jl('maps.json')['maps'] if m['id'] == mid)
    sx, sy = md['spawn'][0], md['spawn'][1]
    dist = {(sx, sy): 0}
    q = [(sx, sy)]
    for cx, cy in q:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (cx + dx, cy + dy)
            if n not in dist and ok(g, *n):
                dist[n] = dist[(cx, cy)] + 1
                q.append(n)
    # 新規則: 離門 >=6 步、5x5 全行得 (離牆 2 格)、唔畀物件遮住；同房人 >=10 格 (放唔晒逐級放寬)
    for lo, w, sep in ((6, 2, 10), (6, 2, 6), (4, 2, 4), (4, 1, 3), (3, 1, 2), (1, 0, 2)):
        c = [p for p, d in dist.items() if lo <= d <= 40 and all(ok(g, p[0] + a, p[1] + b) for a in range(-w, w + 1) for b in range(-w, w + 1))
             and all(max(abs(p[0] - a), abs(p[1] - b)) >= sep for a, b in taken) and visible(mid, p[0], p[1])]
        if c:
            c.sort(key=lambda p: (-min([max(abs(p[0] - a), abs(p[1] - b)) for a, b in taken] or [99]) if sep >= 6 else 0, abs(dist[p] - 12), p[1], p[0]))
            return c[0]
    return None


def at_building(name, taken):
    """回傳 (map, x, y)：功能建築 → 室內圖；街頭角色 → 許昌街；冇對照 = None。taken 係 {map: [(x,y)]}"""
    b = next((k for k, v in AT.items() if name in v), None)
    if b is None:
        return None
    if b in INTERIOR:
        t = taken.setdefault(INTERIOR[b], [])
        r = _inside(INTERIOR[b], t)
        if r:
            t.append(r)
            return INTERIOR[b], r[0], r[1]
    ps = [p for p in jl('maps.json')['portals'] if p['map'] == 'xuchang_o' and b in (p.get('name') or '')]
    if not ps:
        return None
    p = ps[0]
    g = grid('xuchang_o')
    allp = [(q['x'], q['y']) for q in jl('maps.json')['portals'] if q['map'] == 'xuchang_o']
    x = y = None
    for r in range(0, 14):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                cx, cy = p['x'] + dx, p['y'] + 4 + dy
                if max(abs(dx), abs(dy)) == r and ok(g, cx, cy) and ok(g, cx + 1, cy) and ok(g, cx - 1, cy) and x is None                         and all(max(abs(cx - a), abs(cy - b)) >= 3 for a, b in allp)                         and all(max(abs(cx - a), abs(cy - b)) >= 2 for a, b in taken.setdefault('xuchang_o', [])):
                    x, y = cx, cy
    if x is None:
        return None
    taken['xuchang_o'].append((x, y))
    return 'xuchang_o', x, y
