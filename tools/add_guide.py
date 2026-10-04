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

# ---- 工作師傅 + 新手工作任務 (Lv10 起可做工作；兩個許昌道路傳送點) ----
qn = jl('quest_npcs.json')
qn['npcs'] = [n for n in qn['npcs'] if n['id'] != 'work_master']
qn['npcs'].append({'id': 'work_master', 'name': '工作師傅', 'x': 8, 'y': 158, 'minLevel': 10, 'map': 'xuchang_o',
    'idle': ['工作師傅：「農漁獵去城外西面 (17,178) 嗰個傳送點，木礦藥去 (6,137) 嗰個。」'],
    'desc': '西城門旁嘅師傅，教 Lv10 以上嘅玩家做工作賺材料。'})
json.dump(qn, open(C + 'quest_npcs.json', 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
qd = jl('quests.json')
qd['quests'] = [q for q in qd['quests'] if q['id'] != 'newbie_work']
qd['quests'].append({'id': 'newbie_work', 'src': 'custom', 'name': '新手工作：第一次採集', 'type': 'newbie',
  'giver': 'work_master', 'pre': {'minLevel': 10}, 'stages': [
    {'type': 'talk', 'npc': 'work_master', 'dialog': ['工作師傅：「10 級就可以做工作喇。①去許昌工具店買把鋤頭，裝備佢 ②行去西城門附近 (17,178) 嗰個傳送點入「許昌道路（農漁獵）」③喺嗰度撳「工作」採集，每次扣 10% SP。帶 2 件農作物返嚟畀我。」'], 'hint': '同工作師傅傾偈'},
    {'type': 'collect', 'npc': 'work_master', 'item': {'id': 25064, 'n': 2}, 'hint': '去許昌道路（農漁獵）工作，帶 2 件農作物返嚟 (%v/%n)'},
    {'type': 'talk', 'npc': 'work_master', 'dialog': ['工作師傅：「做得好！木礦藥喺 (6,137) 嗰個傳送點，賣材料或者做生產都得。」'], 'hint': '返去同工作師傅報告', 'done': True}],
  'reward': {'exp': 120, 'gold': 200}})
json.dump(qd, open(C + 'quests.json', 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=2)
print('work quest added')
