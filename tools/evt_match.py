# 只讀: 用任務對白入面嘅人名 (「X：」講者 + 任務名入面嘅武將名) 去原版 evt 對白搵候選, 出報告
import json, re, sys, io
sys.stdout.reconfigure(encoding='utf-8')
T = 'D:/Download/sanguo/extracted/text/'
q = json.load(open('client/data/quests.json', encoding='utf-8'))['quests']
gens = {g['name'] for g in json.load(open('client/data/generals.json', encoding='utf-8')).get('generals', []) if len(g.get('name', '')) >= 2}
lines = []
for f in ('evt_dialog_evt1.tsv', 'evt_dialog_evt2.tsv'):
    for l in open(T + f, encoding='utf-8'):
        p = l.rstrip('\n').split('\t')
        if len(p) >= 4 and len(p[3]) >= 8:
            lines.append((f[11:15], p[0], p[3]))
out = ['# D2 evt 對白候選 (自動, 未套用)\n', f'對白行 {len(lines)}；任務 {len(q)}\n']
tot = 0
for x in q:
    txt = x['name'] + ''.join(d for s in x['stages'] for d in s.get('dialog', []))
    kws = sorted({n for n in gens if n in txt}, key=lambda n: -len(n))[:4]
    hits = []
    for n in kws:
        hits += [(n, a, b, c) for a, b, c in lines if n in c][:3]
    tot += bool(hits)
    out.append(f'\n## {x["id"]} {x["name"]} — 關鍵字 {kws or "冇"}')
    for n, a, b, c in hits[:8]:
        out.append(f'- [{a}#{b}] ({n}) {c[:80]}')
out.insert(2, f'有候選 {tot}/{len(q)}\n')
open('docs/uat/evt_dialog_candidates.md', 'w', encoding='utf-8').write('\n'.join(out))
print(len(lines), tot, len(q))
