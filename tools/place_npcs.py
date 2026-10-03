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
open(M.os.path.join(M.C, 'quest_npcs.json'), 'w', encoding='utf8', newline=chr(10)).write(json.dumps(q, ensure_ascii=False, indent=1) + chr(10))
