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
         {"type": "fight", "npc": "awu", "monster": 1106, "conv": [1248],
          "sp": {3: '阿武', 4: '呂布'}, "hint": "去汝南路口，董卓護衛阿武擋路，打低佢"},
         {"type": "talk", "npc": "dongzhuo", "conv": [1224, 1226], "sp": WY,
          "hint": "董卓肯赴宴，返去回報王允"},
         {"type": "talk", "npc": "wangyun", "conv": [1228, 1229], "sp": WY,
          "hint": "返王允處，宴席上貂蟬獻畀董卓，王允要你護送貂蟬去太師府"},
         {"type": "escort", "npc": "dz_guard", "escortName": "貂蟬", "conv": [1235], "sp": {2: '衛兵', 3: '貂蟬'},
          "hint": "帶貂蟬（跟住你走）去汝南路口太師府衛兵處，唔好行太遠"},
         {"type": "talk", "npc": "wangyun", "conv": [1236], "sp": WY, "done": True,
          "hint": "返去回報王允，連環計種子已經埋低"},
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
         {"type": "fight", "npc": "zangba", "monster": 1107, "conv": [1283], "sp": {0: '你'},
          "hint": "去下邳城外打低守河道嘅臧霸"},
         {"type": "fight", "npc": "lvbu_xp", "monster": 1108, "conv": [1290], "sp": {2: '曹操', 3: '呂布', 4: '劉備'},
          "hint": "白門樓下同呂布比武，贏咗曹操就放佢一條生路"},
         {"type": "talk", "npc": "caocao_cl", "conv": [1286, 1291], "sp": {2: '曹操'}, "done": True,
          "hint": "返去陳留搵曹操領賞"},
     ],
     "reward": {"fame": 50, "exp": 6000, "gold": 1200}})
NEW_NPCS_EXTRA = [
    {"id": "dz_guard", "name": "太師府衛兵", "x": 92, "y": 19, "map": "runan_road", "questOnly": True,
     "idle": ["衛兵：「太師府重地，閒人免進！」"], "desc": "董卓府衛兵【原版】"},
]
BOSSES = [(1106, '阿武', 22), (1107, '臧霸', 28), (1108, '呂布', 35)]
NEW_NPCS = NEW_NPCS_EXTRA + [
    {"id": "awu", "name": "阿武", "x": 88, "y": 19, "map": "runan_road", "questOnly": True,
     "idle": ["阿武：「太師出巡，閒人迴避！」"], "desc": "董卓護衛【原版】"},
    {"id": "zangba", "name": "臧霸", "x": 34, "y": 14, "map": "xiapi", "questOnly": True,
     "idle": ["臧霸：「想破我河道？先過我呢關！」"], "desc": "下邳守將【原版】"},
    {"id": "xunyou", "name": "荀攸", "x": 45, "y": 13, "map": "chenliu", "questOnly": True,
     "idle": ["荀攸：「下邳久攻不下，需要一位勇士相助……」"], "desc": "曹操軍師【原版】"},
    {"id": "lvbu_xp", "name": "呂布", "x": 20, "y": 14, "map": "xiapi", "questOnly": True,
     "idle": ["呂布：「天要亡我啊！」"], "desc": "下邳城內被圍嘅呂布【原版】"},
    {"id": "liubei", "name": "劉備", "x": 9, "y": 17, "map": "xiaopei", "questOnly": True,
     "idle": ["劉備：「曹操相請，此去兇多吉少……」"], "desc": "小沛城內劉玄德【原版】"},
]

# ---- 批次 2: 孫策/于吉 ----
BOSSES += [(1109, '許貢家客', 30), (1110, '孫策護衛', 32)]
NEW_NPCS_EXTRA += [
    {"id": "xs_merchant", "name": "行腳商人", "x": 14, "y": 16, "map": "changsha", "questOnly": True,
     "idle": ["行腳商人：「最近風聲好緊……」"], "desc": "打探到許貢家客情報嘅商人【原版】"},
    {"id": "xugong_ke", "name": "許貢家客", "x": 32, "y": 22, "map": "jingzhou", "questOnly": True,
     "idle": ["許貢家客：「孫策呢個殺人兇手！」"], "desc": "許貢舊家客【原版】"},
    {"id": "sunce", "name": "孫策", "x": 30, "y": 20, "map": "jingzhou", "questOnly": True,
     "idle": ["孫策：「大恩不言謝，日後有事儘管搵我。」"], "desc": "小霸王孫策【原版】"},
    {"id": "ys_guard", "name": "祭壇守衛", "x": 22, "y": 18, "map": "changsha", "questOnly": True,
     "idle": ["守衛：「于仙人將於午時祈風禱雨……」"], "desc": "長沙祭壇守衛【原版】"},
    {"id": "sunce_guard", "name": "孫策護衛", "x": 28, "y": 16, "map": "changsha", "questOnly": True,
     "idle": ["護衛：「軍家重地，速速退去！」"], "desc": "孫策護衛【原版】"},
]
QUESTS += [
    {"id": "orig_sunce", "src": "orig", "name": "保護孫策", "type": "history", "giver": "xs_merchant",
     "pre": {"minLevel": 28},
     "preHint": "武功 28 級以上，去長沙搵行腳商人探情報",
     "stages": [
         {"type": "talk", "npc": "xs_merchant", "conv": [1296], "sp": {2: '行腳商人'},
          "hint": "商人話許貢家客要伏擊孫策，去荊州地界丹徒山睇睇"},
         {"type": "fight", "npc": "xugong_ke", "monster": 1109, "conv": [1298], "sp": {3: '孫策', 4: '許貢家客'},
          "hint": "喺荊州地界打退行刺孫策嘅許貢家客"},
         {"type": "talk", "npc": "sunce", "conv": [1299], "sp": {3: '孫策', 4: '許貢家客'}, "done": True,
          "hint": "孫策想多謝你"}],
     "reward": {"fame": 45, "exp": 5500, "gold": 1100}},
    {"id": "orig_yuji", "src": "orig", "name": "解救于吉", "type": "history", "giver": "ys_guard",
     "pre": {"minLevel": 30},
     "preHint": "武功 30 級以上，去長沙祭壇搵守衛",
     "stages": [
         {"type": "talk", "npc": "ys_guard", "conv": [1307, 1309], "sp": {2: '祭壇守衛'},
          "hint": "守衛畀咗祭壇通行令，去祭壇見孫策同于吉"},
         {"type": "fight", "npc": "sunce_guard", "monster": 1110, "conv": [1314], "sp": {3: '孫策', 4: '護衛'},
          "hint": "孫策要燒死于吉，打低孫策護衛救人"},
         {"type": "talk", "npc": "yuji", "conv": [1313], "sp": {2: '于吉'}, "done": True,
          "hint": "于吉脫困，向你道謝"}],
     "reward": {"fame": 50, "exp": 6000, "gold": 1200}},
]


def add_bosses():
    p = 'client/data/monsters.json'
    md = json.load(open(p, encoding='utf8'))
    ms = md['monsters'] if isinstance(md, dict) else md
    ms[:] = [m for m in ms if m['id'] not in {b[0] for b in BOSSES}]
    for mid, name, lv in BOSSES:   # 【自訂】數值按 lv 線性，唔掉落
        ms.append({'id': mid, 'name': name, 'level': lv, 'hp': 46 * lv, 'atk': round(3.6 * lv), 'def': round(0.55 * lv),
                   'spellDef': round(1.5 * lv), 'atkInterval': 13, 'moveSpeed': 1, 'exp': 0, 'gold': [0, 0],
                   'alignment': -200, 'aggroRange': 8, 'leash': 16, 'element': 'none', 'drops': [], 'rareDrops': [],
                   'suppDrops': []})
    json.dump(md, open(p, 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)


def main():
    ALL_NPCS = NEW_NPCS + [n for n in NEW_NPCS_EXTRA if n not in NEW_NPCS]
    add_bosses()
    convs = load_convs()

    for n in ALL_NPCS:
        g = open('client/data/maps/%s.txt' % n['map'], encoding='utf8').read().split(chr(10))
        assert g[n['y']][n['x']] in '.:=,_+', 'NPC 位置唔行得: %s %s' % (n['id'], g[n['y']][n['x']])
    qd = json.load(open(QJ, encoding='utf8'))
    nd = json.load(open(NJ, encoding='utf8'))
    names = {n['id']: n['name'] for n in nd['npcs']}
    for n in ALL_NPCS:
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
    print('ok', len(QUESTS), 'quests', len(ALL_NPCS), 'npcs')

if __name__ == '__main__':
    main()
