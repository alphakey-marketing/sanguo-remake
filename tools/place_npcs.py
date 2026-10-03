# 許昌 (xuchang_o) 任務 NPC 擺去對應建築入口隔籬 (migrate_to_orig.AT)。可重跑。
import json, migrate_to_orig as M
q = M.jl('quest_npcs.json')
taken = {}
for n in q['npcs']:
    if n['map'] == 'xuchang_o' or n['map'] in M.INTERIOR.values():
        r = M.at_building(n['name'], taken)
        if r:
            n['map'], n['x'], n['y'] = r
open(M.os.path.join(M.C, 'quest_npcs.json'), 'w', encoding='utf8', newline=chr(10)).write(json.dumps(q, ensure_ascii=False, indent=1) + chr(10))
