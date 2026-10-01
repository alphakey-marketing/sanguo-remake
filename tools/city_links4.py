#!/usr/bin/env python3
"""城際連線 v2 (用家 2026-10-01): 每城只有一張外圍 xx25，東南西北各最多一條線；一條線 = A 嗰張 25 的 d 邊 <-> B 嗰張 25 的對邊。
方向按地理 (城市群示意圖座標，y 向下)。短線先分配；每條線只可用「對方大致喺嗰個方向」(夾角<90度) 嘅邊，兩端邊要啱 (A 東 = B 西)。
用法: python tools/city_links4.py  -> client/data/city_links.json + docs/plan/CITY_LINKS.md + docs/plan/city_links4.png"""
import json, os, re, math
from PIL import Image, ImageDraw, ImageFont
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open('D:/Download/sanguo/tools/world_map_draw.py', encoding='utf8').read()
cities = eval(re.search(r'CITIES = (\[.*?\n\])', src, re.S).group(1))
links = eval(re.search(r'LINKS = (\[.*?\n\])', src, re.S).group(1))
C = {n: (i, x, y) for n, i, x, y in cities}
DIRS = {'E': (1, 0), 'S': (0, 1), 'W': (-1, 0), 'N': (0, -1)}; OPP = {'E': 'W', 'W': 'E', 'N': 'S', 'S': 'N'}
SKIP = {('汝南', '許昌')}                          # 用家刪
EXTRA = [('汝南', '江夏')]
edges = sorted({tuple(sorted((a, b), key=lambda n: C[n][0])) for a, b in list(links) + EXTRA if a in C and b in C and a != b and (a, b) not in SKIP and (b, a) not in SKIP},
               key=lambda e: math.dist(C[e[0]][1:], C[e[1]][1:]))
import random
def pref(a, b):                                   # a 去 b 嘅邊，按夾角由近到遠，夾角 >= 90 度唔用
    dx, dy = C[b][1] - C[a][1], C[b][2] - C[a][2]; n = math.hypot(dx, dy)
    r = sorted(((-(DIRS[d][0] * dx + DIRS[d][1] * dy) / n, d) for d in DIRS))
    return [d for c, d in r if c <= 0.05]
def wt(e): return 100 if '許昌' in e else 1       # 許昌 (起始城) 嘅線一定要保
def run(order):
    """兩端各自揀自己面向對方嘅空邊 (不一定對邊：A 東 可以接 B 北)；兩端都有空位先成線"""
    slot = {}; chosen = []; dropped = []
    for a, b in order:
        da = next((d for d in pref(a, b) if (a, d) not in slot), None); db = next((d for d in pref(b, a) if (b, d) not in slot), None)
        if da and db: slot[(a, da)] = b; slot[(b, db)] = a; chosen.append((a, da, b, db))
        else: dropped.append((a, b))
    return sum(wt(e) for e in dropped), -len(chosen), slot, chosen, dropped
random.seed(7); best = run(edges)
for _ in range(20000):
    o = edges[:]; random.shuffle(o); r = run(o)
    if r[:2] < best[:2]: best = r
_, _, slot, chosen, dropped = best
# 每城出入口 25 + 連線
out = [{'a': a, 'b': b, 'a_dir': d, 'b_dir': e, 'a_out': C[a][0] + 25, 'b_out': C[b][0] + 25} for a, d, b, e in chosen]
json.dump({'rule': '每城只有 xx25 外圍；東南西北各最多一條線 (地理方向)', 'cities': {n: {'id': i, 'x': x, 'y': y} for n, (i, x, y) in C.items()},
           'links': out, 'dropped': [list(e) for e in dropped]}, open(os.path.join(ROOT, 'client/data/city_links.json'), 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
md = ['# 城際連線表 v2 (每城一張 25 外圍，東南西北各一線)', '', '| 城 A | 方向 | 城 B | 方向 |', '|---|---|---|---|']
md += ['| %s %d | %s | %s %d | %s |' % (l['a'], C[l['a']][0], l['a_dir'], l['b'], C[l['b']][0], l['b_dir']) for l in out]
md += ['', '## 刪走嘅線 (方向位被佔)', ''] + ['- %s — %s' % e for e in dropped]
open(os.path.join(ROOT, 'docs/plan/CITY_LINKS.md'), 'w', encoding='utf8', newline='\n').write('\n'.join(md) + '\n')
# 圖
S = 12; mx = max(x for _, x, _ in C.values()) + 8; my = max(y for _, _, y in C.values()) + 8
im = Image.new('RGB', (mx * S, my * S), (24, 28, 36)); dr = ImageDraw.Draw(im)
try: ft = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc', 15)
except Exception: ft = None
col = {'E': (255, 120, 120), 'W': (255, 120, 120), 'N': (120, 200, 255), 'S': (120, 200, 255)}
for a, d, b, e in chosen: dr.line([C[a][1] * S, C[a][2] * S, C[b][1] * S, C[b][2] * S], fill=col[d], width=2)
for a, b in dropped: dr.line([C[a][1] * S, C[a][2] * S, C[b][1] * S, C[b][2] * S], fill=(255, 230, 0), width=2)
for n, (i, x, y) in C.items():
    deg = sum(1 for d in DIRS if (n, d) in slot); dr.ellipse([x * S - 6, y * S - 6, x * S + 6, y * S + 6], fill=(255, 255, 255))
    dr.text((x * S + 8, y * S - 8), '%s%d(%d)' % (n, i // 100, deg), fill=(255, 255, 255), font=ft)
im.save(os.path.join(ROOT, 'docs/plan/city_links4.png'))
print(len(out), '條線，刪', len(dropped), dropped)
print('孤立城:', [n for n in C if not any((n, d) in slot for d in DIRS)])
