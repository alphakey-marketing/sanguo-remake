"""新增原版任務 (src=orig)：對白由 evt_dialog 對話組 (conv id) 逐字抄入，流程/位置/獎勵係按 stage 簡化重組。
用法: python tools/add_orig_quests.py   (冪等: 同 id 會覆蓋)"""
import json, sys
sys.path.insert(0, 'tools')
from apply_orig_dialog import load_convs, lines, QJ, NJ

# 王允連環計: conv 1201~1250 | 劉備煮酒論英雄(左慈相助): conv 1254~1272
WY = {2: '王允', 3: '董卓', 4: '貂蟬'}
QUESTS = [
    {"id": "orig_lianhuan", "src": "orig", "name": "王允連環計", "type": "history", "giver": "wangyun",
     "pre": {"minLevel": 15, "attr": {"cha": 8}},
     "preHint": "武功 15 級以上、魅力 8 以上，去宛城搵司徒王允",
     "stages": [
         {"type": "talk", "npc": "wangyun", "conv": [1201, 1202], "sp": WY,
          "hint": "王允要你將金冠送去汝南城，交畀呂布"},
         {"type": "talk", "npc": "lvbu_rn", "conv": [1204], "sp": {3: '呂布'},
          "hint": "呂布收咗金冠，返去回報王允"},
         {"type": "talk", "npc": "wangyun", "conv": [1207, 1211], "sp": WY,
          "hint": "王允要你將邀請函送去汝南路口畀董卓"},
         {"type": "talk", "npc": "dongzhuo", "conv": [1224, 1226], "sp": WY,
          "hint": "董卓肯赴宴，返去回報王允"},
         {"type": "talk", "npc": "wangyun", "conv": [1228, 1236], "sp": WY, "done": True,
          "hint": "貂蟬獻畀董卓，連環計種子已經埋低"},
     ],
     "reward": {"fame": 40, "exp": 4000, "gold": 800}},
    {"id": "orig_liubei", "src": "orig", "name": "煮酒論英雄", "type": "history", "giver": "zuoci",
     "pre": {"minLevel": 20, "attr": {"int": 10}},
     "preHint": "武功 20 級以上、智力 10 以上，去襄陽搵左慈",
     "stages": [
         {"type": "talk", "npc": "zuoci", "conv": [1256, 1257], "sp": {2: '左慈'},
          "hint": "左慈要你將天機情報函送去小沛畀劉備"},
         {"type": "talk", "npc": "liubei", "conv": [1265], "sp": {2: '劉備'},
          "hint": "劉備要你陪佢去見曹操（陳留）"},
         {"type": "talk", "npc": "caocao_cl", "conv": [1270, 1271, 1272], "sp": {2: '曹操', 3: '劉備'},
          "hint": "喺陳留曹操煮酒席上用仙法借雷救劉備"},
         {"type": "talk", "npc": "liubei", "conv": [1263], "sp": {2: '劉備'}, "done": True,
          "hint": "返去小沛搵劉備領謝禮"},
     ],
     "reward": {"fame": 40, "exp": 5000, "gold": 1000}},
]
QUESTS.append({"id": "orig_xiapi", "src": "orig", "name": "水淹下邳", "type": "history", "giver": "xunyou",
     "pre": {"minLevel": 25, "attr": {"int": 12}},
     "preHint": "武功 25 級以上、智力 12 以上，去陳留搵荀攸",
     "stages": [
         {"type": "talk", "npc": "xunyou", "conv": [1281], "sp": {2: '荀攸'},
          "hint": "荀攸獻水淹下邳之計，要你去下邳搵呂布探路"},
         {"type": "talk", "npc": "lvbu_xp", "conv": [1290], "sp": {2: '曹操', 3: '呂布', 4: '劉備'},
          "hint": "白門樓下見到被擒嘅呂布，返去回報曹操"},
         {"type": "talk", "npc": "caocao_cl", "conv": [1286, 1291], "sp": {2: '曹操'}, "done": True,
          "hint": "返去陳留搵曹操領賞"},
     ],
     "reward": {"fame": 50, "exp": 6000, "gold": 1200}})
NEW_NPCS = [
    {"id": "xunyou", "name": "荀攸", "x": 45, "y": 13, "map": "chenliu", "questOnly": True,
     "idle": ["荀攸：「下邳久攻不下，需要一位勇士相助……」"], "desc": "曹操軍師【原版】"},
    {"id": "lvbu_xp", "name": "呂布", "x": 20, "y": 14, "map": "xiapi", "questOnly": True,
     "idle": ["呂布：「天要亡我啊！」"], "desc": "下邳城內被圍嘅呂布【原版】"},
    {"id": "liubei", "name": "劉備", "x": 9, "y": 17, "map": "xiaopei", "questOnly": True,
     "idle": ["劉備：「曹操相請，此去兇多吉少……」"], "desc": "小沛城內劉玄德【原版】"},
]

def main():
    convs = load_convs()
    qd = json.load(open(QJ, encoding='utf8'))
    nd = json.load(open(NJ, encoding='utf8'))
    names = {n['id']: n['name'] for n in nd['npcs']}
    for n in NEW_NPCS:
        names[n['id']] = n['name']
        nd['npcs'] = [x for x in nd['npcs'] if x['id'] != n['id']] + [n]
    ids = {q['id'] for q in QUESTS}
    qd['quests'] = [q for q in qd['quests'] if q['id'] not in ids]
    for q in QUESTS:
        q = json.loads(json.dumps(q))
        for st in q['stages']:
            ls = []
            for cid in st['conv']:
                ls += lines(convs[cid], names[st['npc']], st.get('sp'))
            st['dialog'] = ls
            st['origConv'] = st.pop('conv')
            st.pop('sp', None)
        qd['quests'].append(q)
    json.dump(qd, open(QJ, 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
    json.dump(nd, open(NJ, 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
    print('ok', len(QUESTS), 'quests', len(NEW_NPCS), 'npcs')

if __name__ == '__main__':
    main()
