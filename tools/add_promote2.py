# 原版二轉任務: 長沙門口貂蟬 → 四晶守護者 (晉/僕/汝/譙 洞最深層) → 四晶戒 → 回貂蟬；轉職後免費升一級
# 用法: PYTHONIOENCODING=utf-8 python tools/add_promote2.py   (可重跑)
import json
C = 'client/data/'
def jl(f): return json.load(open(C + f, encoding='utf8'))
# 守護者: (怪id, 名, 戒id, 洞最深層 zone, tint)
G = [(70039, '藍晶守護者', 64004, 'xc2555', '#6090ff'), (70040, '紅晶守護者', 64005, 'xc1655', '#ff6060'),
     (70041, '綠晶守護者', 64003, 'xc2055', '#60ff80'), (70028, '紫晶守護者', 64006, 'xc1855', None)]
md = jl('monsters.json')
base = [m for m in md['monsters'] if m['id'] == 70028][0]
ids = {g[0] for g in G}
md['monsters'] = [m for m in md['monsters'] if m['id'] not in ids - {70028}]
md['spawns'] = [s for s in md['spawns'] if s['monster'] not in ids]
al = jl('mon_alias.json')
for mid, name, ring, zone, tint in G:
    if mid == 70028:
        m = [x for x in md['monsters'] if x['id'] == 70028][0]
    else:
        m = dict(base); m['id'] = mid; m['name'] = name; md['monsters'].append(m)
    m['drops'] = [{'item': ring, 'p': 1.0}]
    m['exp'] = 0
    if tint: al['alias'][str(mid)] = {'mon': 70028, 'tint': tint}
    md['spawns'].append({'zone': zone, 'monster': mid, 'count': 1, 'respawnTicks': 300, 'lv': 50})
json.dump(md, open(C + 'monsters.json', 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
json.dump(al, open(C + 'mon_alias.json', 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)

# 貂蟬 NPC: 長沙原版圖門口 (搵最近行得格)
g = open(C + 'maps/xc2200.txt', encoding='utf8').read().split('\n')
def snap(x, y):
    for r in range(0, 12):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                xx, yy = x + dx, y + dy
                if max(abs(dx), abs(dy)) == r and 0 <= yy < len(g) and 0 <= xx < len(g[yy]) and g[yy][xx] in '.:=,_+':
                    return xx, yy
    raise SystemExit('冇位')
nx, ny = snap(8, 110)
nd = json.load(open(C + 'quest_npcs.json', encoding='utf8'))
lst = nd['npcs'] if isinstance(nd, dict) else nd
lst[:] = [n for n in lst if n['id'] != 'diaochan']
lst.append({'id': 'diaochan', 'name': '貂蟬', 'x': nx, 'y': ny, 'map': 'xc2200', 'minLevel': 50, 'questOnly': False,
            'idle': '集齊四晶戒，再嚟搵我。', 'desc': '長沙城門口嘅貂蟬（二轉考驗）'})
json.dump(nd, open(C + 'quest_npcs.json', 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)

qd = jl('quests.json')
ql = qd['quests']
ql[:] = [q for q in ql if not q['id'].startswith('promote_test_') and q['id'] != 'promote_test']
ql.append({'id': 'promote_test', 'src': 'orig', 'name': '轉職任務（二轉）', 'type': 'general', 'giver': 'diaochan',
  'pre': {'level': 50, 'tier': 0}, 'preHint': 'Lv50 去長沙城門口搵貂蟬',
  'stages': [
    {'type': 'talk', 'npc': 'diaochan', 'dialog': ['貂蟬：想轉職？先集齊四枚晶戒。', '貂蟬：晉陽、濮陽、汝南、譙城洞窟最深層，各有一隻晶守護者。'], 'hint': '同貂蟬傾偈接二轉任務'},
    {'type': 'collect', 'npc': 'diaochan', 'item': {'id': 64004, 'n': 1}, 'hint': '晉陽洞窟最深層殺藍晶守護者，得藍晶戒 (%v/%n)，交畀貂蟬'},
    {'type': 'collect', 'npc': 'diaochan', 'item': {'id': 64005, 'n': 1}, 'hint': '濮陽洞窟最深層殺紅晶守護者，得紅晶戒 (%v/%n)，交畀貂蟬'},
    {'type': 'collect', 'npc': 'diaochan', 'item': {'id': 64003, 'n': 1}, 'hint': '汝南洞窟最深層殺綠晶守護者，得綠晶戒 (%v/%n)，交畀貂蟬'},
    {'type': 'collect', 'npc': 'diaochan', 'item': {'id': 64006, 'n': 1}, 'hint': '譙城洞窟最深層殺紫晶守護者，得紫晶戒 (%v/%n)，交畀貂蟬'},
    {'type': 'talk', 'npc': 'diaochan', 'dialog': ['貂蟬：四晶戒齊晒，你通過考驗！', '貂蟬：轉職後仲免費升一級。'], 'hint': '返去搵貂蟬完成考驗，即可轉職', 'done': True}],
  'reward': {'fame': 10}})
json.dump(qd, open(C + 'quests.json', 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=2)
print('ok', nx, ny)
