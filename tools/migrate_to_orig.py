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

def place_near(tm, i, others):
    g = grid(tm)
    maps = {m['id']: m for m in jl('maps.json')['maps']}
    sp = maps[tm].get('spawn') or [len(g[0]) // 2, len(g) // 2]
    return snap(g, sp[0] + 8 + 5 * (i % 5), sp[1] + 4 * (i // 5) + 3, others)


def main():
    maps = {m['id']: m for m in jl('maps.json')['maps']}
    old = {i for i, m in maps.items() if not m.get('orig')}
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
        x, y = snap(g, bx, by, placed.setdefault(tm, []))
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
    for lo, w in ((7, 2), (4, 2), (1, 2), (4, 0), (1, 0)):
        c = [p for p, d in dist.items() if lo <= d <= 16 and all(ok(g, p[0] + a, p[1] + b) for a in range(-w, w + 1) for b in (-1, 0, 1))
             and all(max(abs(p[0] - a), abs(p[1] - b)) >= 2 for a, b in taken)]
        if c:
            c.sort(key=lambda p: (abs(dist[p] - 10), p[1], p[0]))
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
