"""洞穴傳送: 外圍 xx25 洞口 <-> 洞穴第1層，層與層之間按 k2 出口 id 配對。【猜測】要手測
配對法: 相鄰兩層各揀 id 差最細嘅未用出口 (原版 k2 id 連號)；第1層剩低嗰個 = 出洞口。外圍洞口位置 = xc1925 模板上固定一格 (原版 25 圖冇洞口座標)。
要喺 import_orig_interiors.py 之後跑 (佢會重置洞穴 orphan 旗)。用法: python tools/link_caves.py"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import import_orig_interiors as I
ROOT = I.ROOT; MAPS = I.MAPS
def walk(mid):
    return [l.rstrip('\n') for l in open('%s/client/data/maps/xc%d.txt' % (ROOT, mid), encoding='utf8')]
def ok(g, x, y): return 0 <= y < len(g) and 0 <= x < len(g[y]) and g[y][x] == '.'
def land_near(g, r):
    """離矩形 r 至少 3 格、最近嘅可行走格"""
    cx, cy = (r[0] + r[2]) // 2, (r[1] + r[3]) // 2; best = None
    for y in range(max(0, r[1] - 12), min(len(g), r[3] + 13)):
        for x in range(max(0, r[0] - 12), min(len(g[0]), r[2] + 13)):
            if not ok(g, x, y) or r[0] - 3 < x < r[2] + 3 and r[1] - 3 < y < r[3] + 3: continue
            d = (x - cx) ** 2 + (y - cy) ** 2
            if best is None or d < best[0]: best = (d, x, y)
    return [best[1], best[2]] if best else [cx, cy]
def entrance_rect(g):
    """外圍模板上揀洞口: 由 (150,45) 起搵 5x3 全可行走 + 下面 3 格可行走嘅位"""
    for rad in range(0, 60):
        for dy in range(-rad, rad + 1):
            for dx in range(-rad, rad + 1):
                x, y = 150 + dx, 45 + dy
                if all(ok(g, x + i, y + j) for i in range(-3, 4) for j in range(-1, 8)): return [x - 2, y, x + 2, y + 2]
    raise SystemExit('搵唔到洞口位')
def near_walk(g, r):
    """矩形內最近中心嘅可行走格；冇就向外搵 (傳送點 x,y 要行得)"""
    cx, cy = (r[0] + r[2]) // 2, (r[1] + r[3]) // 2; best = None
    for y in range(max(0, r[1] - 20), min(len(g), r[3] + 21)):
        for x in range(max(0, r[0] - 20), min(len(g[0]), r[2] + 21)):
            if ok(g, x, y):
                d = (x - cx) ** 2 + (y - cy) ** 2 + (0 if r[0] <= x <= r[2] and r[1] <= y <= r[3] else 400)
                if best is None or d < best[0]: best = (d, x, y)
    return best[1:] if best else (cx, cy)
def P(pid, name, mid, r, land, to):
    x, y = near_walk(walk(mid), r)
    return {'id': pid, 'name': name, 'map': 'xc%d' % mid, 'x': x, 'y': y, 'rect': r, 'land': land, 'to': to, 'auto': True}
def main():
    rects = I.k2_rects(); mj = json.load(open(MAPS, encoding='utf8'))
    ids = {m['id'] for m in mj['maps']}
    g25 = walk(1925); er = entrance_rect(g25); eland = [(er[0] + er[2]) // 2, er[3] + 3]
    out, linked = [], set()
    for c in sorted({m // 100 for m in I.CAVES}):
        fl = sorted(m for m in I.CAVES if m // 100 == c)
        ex = {m: {k: [v // 16 for v in (x1, y1, x2, y2)] for k, s, x1, y1, x2, y2 in rects[m] if s == 1} for m in fl}
        used = {m: set() for m in fl}
        for a, b in zip(fl, fl[1:]):
            c2 = [(abs(ka - kb), ka, kb) for ka in ex[a] if ka not in used[a] for kb in ex[b] if kb not in used[b]]
            if not c2: print('警告: %d->%d 配唔到' % (a, b)); continue
            _, ka, kb = min(c2); used[a].add(ka); used[b].add(kb)
            ra, rb = ex[a][ka], ex[b][kb]; ga, gb = walk(a), walk(b)
            pa, pb = 'xc_cv_%d_dn' % a, 'xc_cv_%d_up' % b
            out += [P(pa, '往下一層', a, ra, land_near(ga, ra), pb), P(pb, '往上一層', b, rb, land_near(gb, rb), pa)]
            linked |= {a, b}
        rest = [k for k in ex[fl[0]] if k not in used[fl[0]]]
        if rest: r = ex[fl[0]][min(rest)]
        else:                                  # 陳留/河內/江陵/零陵: 第1層得一個出口 (=往下層)，洞口冇 k2 -> 用出生點周圍 3x3
            sp = next(m for m in mj['maps'] if m['id'] == 'xc%d' % fl[0])['spawn']; r = [sp[0] - 1, sp[1] - 1, sp[0] + 1, sp[1] + 1]
        g1 = walk(fl[0]); o25 = c * 100 + 25
        if 'xc%d' % o25 not in ids: print('警告: 冇外圍 %d' % o25); continue
        out += [P('xc_cv_in_%d' % c, '入洞穴', o25, er, eland, 'xc_cv_out_%d' % c), P('xc_cv_out_%d' % c, '出洞穴', fl[0], r, land_near(g1, r), 'xc_cv_in_%d' % c)]
        linked.add(fl[0])
    mj['portals'] = [p for p in mj['portals'] if not p['id'].startswith('xc_cv_')] + out
    for m in mj['maps']:
        if m['id'] in ('xc%d' % x for x in linked): m.pop('orphan', None)
    open(MAPS, 'w', encoding='utf8', newline='\n').write(json.dumps(mj, ensure_ascii=False, indent=1) + '\n')
    print('洞穴傳送點', len(out), '已連通層', len(linked), '/', len(I.CAVES), '洞口', er)
main()
