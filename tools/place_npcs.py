# 許昌 (xuchang_o) 任務 NPC 擺去對應建築入口隔籬 (migrate_to_orig.AT)。可重跑。
import json, migrate_to_orig as M
q = M.jl('quest_npcs.json')
taken = {}
for n in q['npcs']:
    if n['map'] == 'xuchang_o' or n['map'] in M.INTERIOR.values():
        r = M.at_building(n['name'], taken)
        if r:
            n['map'], n['x'], n['y'] = r
# 其他城 (室外城圖) NPC：攤開，唔好擠埋一齊 (最少 ~10 格)
mp = {m['id']: m for m in M.jl('maps.json')['maps']}
done = {}
for n in q['npcs']:
    m = mp.get(n['map'])
    if not m or n['map'] == 'xuchang_o' or n['map'] in M.INTERIOR.values() or m.get('kind') == 'house' or n['map'].endswith('25') is True:
        continue
    if not any(pp['map'] == n['map'] for pp in M.jl('maps.json')['portals']):
        continue
    t = done.setdefault(n['map'], [])
    r = M.spread(n['map'], t)
    if r:
        n['x'], n['y'] = r
        t.append(r)
# 最後一關: 仍然畀物件遮住嘅 (原版位置) → 搬去最近一格睇得到 + 周圍可行走 (半徑 10 內)
for n in q['npcs']:
    m = n['map']
    if not M.os.path.exists(M.os.path.join(M.C, 'orig_maps', m + '.json')) or M.visible(m, n['x'], n['y']):
        continue
    g = M.grid(m)
    best = None
    for r in range(1, 11):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) != r:
                    continue
                x, y = n['x'] + dx, n['y'] + dy
                if all(M.ok(g, x + a, y + b) for a in (-1, 0, 1) for b in (-1, 0, 1)) and M.visible(m, x, y):
                    best = (x, y)
                    break
            if best:
                break
        if best:
            break
    if best:
        print('遮擋→搬', n['name'], m, (n['x'], n['y']), best)
        n['x'], n['y'] = best
open(M.os.path.join(M.C, 'quest_npcs.json'), 'w', encoding='utf8', newline=chr(10)).write(json.dumps(q, ensure_ascii=False, indent=1) + chr(10))
