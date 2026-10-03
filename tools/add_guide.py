# 新手嚮導 (出生點旁) + 新手跑腿任務鏈；公佈欄搬去城門旁。可重跑
# 用法: PYTHONIOENCODING=utf-8 python tools/add_guide.py
import json, re
C = 'client/data/'
def jl(f): return json.load(open(C + f, encoding='utf8'))
qn = jl('quest_npcs.json')
qn['npcs'] = [n for n in qn['npcs'] if n['id'] != 'newbie_guide']
qn['npcs'].append({'id': 'newbie_guide', 'name': '新手嚮導', 'x': 127, 'y': 160, 'maxLevel': 4, 'map': 'xuchang_o',
    'idle': ['新手嚮導：「有咩唔識問我。神秘老人、練兵場、私塾、廟，都係新手必去。」'],
    'desc': '出生點旁嘅嚮導，帶新手跑城、升到 5 級。'})
json.dump(qn, open(C + 'quest_npcs.json', 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
qd = jl('quests.json')
qd['quests'] = [q for q in qd['quests'] if q['id'] != 'newbie_guide']
qd['quests'].append({'id': 'newbie_guide', 'src': 'custom', 'name': '新手嚮導：跑城熟路', 'type': 'newbie',
  'giver': 'newbie_guide', 'pre': {'maxLevel': 4}, 'stages': [
    {'type': 'talk', 'npc': 'newbie_guide', 'dialog': ['新手嚮導：「初到許昌？跟我一套：①搵賣菜嬸、算命先生、茶館老闆傾偈 ②去私塾同廟修練 ③練兵場對練 ④城西神秘老人有考驗。做晒就升到 5 級。」'], 'hint': '同新手嚮導傾偈'},
    {'type': 'talk_n', 'npcs': ['citizen_1', 'citizen_2', 'citizen_3'], 'n': 3, 'hint': '搵賣菜嬸、算命先生、茶館老闆傾偈 (%v/%n)'},
    {'type': 'facility', 'fac': 'school', 'hint': '去私塾修練 1 次'},
    {'type': 'facility', 'fac': 'temple', 'hint': '去廟修練 1 次'},
    {'type': 'talk', 'npc': 'newbie_guide', 'dialog': ['新手嚮導：「好！街你識晒喇。另外練兵場對練、神秘老人嘅考驗都記得做，仲有公佈欄喺城門旁。」'], 'hint': '返去同新手嚮導報告', 'done': True}],
  'reward': {'exp': 40, 'gold': 30}})
json.dump(qd, open(C + 'quests.json', 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=2)
p = C + 'facilities.json'
s = open(p, encoding='utf8', newline='').read()
s2 = s  # 公佈欄座標已直接改 facilities.json (5,158)
print('bulletin moved' if s2 != s else 'bulletin NOT matched (check format)')
open(p, 'w', encoding='utf8', newline='').write(s2)
