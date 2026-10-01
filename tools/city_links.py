#!/usr/bin/env python3
"""城際連線規則 (用家 2026-10-01 定): 每座城按「鄰城 map id 由細到大」順序分配外圍:
第 1 個鄰城 -> xx29, 第 2 個 -> xx25, 第 3 個 -> xx49; 多過 3 個就由頭循環 (同一張外圍開多個出口)。
一條線 A-B = A 嗰張外圍 <-> B 嗰張外圍。連線表用 world_map_draw.py 嘅 LINKS (用家嘅城市群分布示意圖)。
輸出: client/data/city_links.json + docs/plan/CITY_LINKS.md   用法: python tools/city_links.py"""
import json, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open('D:/Download/sanguo/tools/world_map_draw.py', encoding='utf8').read()
ns = {}
cities = eval(re.search(r'CITIES = (\[.*?\n\])', src, re.S).group(1))
links = eval(re.search(r'LINKS = (\[.*?\n\])', src, re.S).group(1))
cid = {n: i for n, i, x, y in cities}
SLOT = [29, 25, 49]
adj = {n: set() for n in cid}
for a, b in links:
    if a in cid and b in cid and a != b: adj[a].add(b); adj[b].add(a)
asg = {}                                   # (city, nb) -> 外圍 map id
for n, nbs in adj.items():
    for k, nb in enumerate(sorted(nbs, key=lambda x: cid[x])):
        asg[(n, nb)] = cid[n] + SLOT[k % 3]
out = []
for a, b in sorted({tuple(sorted((a, b), key=lambda x: cid[x])) for a, b in links if a in cid and b in cid}, key=lambda t: (cid[t[0]], cid[t[1]])):
    out.append({'a': a, 'b': b, 'a_out': asg[(a, b)], 'b_out': asg[(b, a)]})
json.dump({'rule': '鄰城按 map id 升序: 第1->xx29, 第2->xx25, 第3->xx49, 之後循環',
           'cities': {n: {'id': i, 'x': x, 'y': y} for n, i, x, y in cities}, 'links': out},
          open(os.path.join(ROOT, 'client/data/city_links.json'), 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
md = ['# 城際連線表 (外圍規則)', '', '規則: 每座城按鄰城 map id 升序，第 1 個鄰城用 xx29，第 2 個用 xx25，第 3 個用 xx49，多過 3 個就循環 (同一張外圍開多個出口)。',
      '線 A–B = A 嗰張外圍 ↔ B 嗰張外圍。連線來源 = 用家城市群分布示意圖。由 `tools/city_links.py` 生成，唔好手改。', '',
      '| 城 A | A 外圍 | 城 B | B 外圍 |', '|---|---|---|---|']
for l in out: md.append('| %s %d | %d | %s %d | %d |' % (l['a'], cid[l['a']], l['a_out'], l['b'], cid[l['b']], l['b_out']))
md += ['', '## 許昌', '']
for nb in sorted(adj['許昌'], key=lambda x: cid[x]): md.append('- 許昌 ↔ %s: 許昌 %d / %s %d' % (nb, asg[('許昌', nb)], nb, asg[(nb, '許昌')]))
open(os.path.join(ROOT, 'docs/plan/CITY_LINKS.md'), 'w', encoding='utf8', newline='\n').write('\n'.join(md) + '\n')
print(len(out), '條線')
