"""新增原版任務 (src=orig)：對白由 evt_dialog 對話組 (conv id) 逐字抄入，流程/位置/獎勵係按 stage 簡化重組。
用法: python tools/add_orig_quests.py   (冪等: 同 id 會覆蓋)"""
import json, sys
sys.path.insert(0, 'tools')
from apply_orig_dialog import load_convs, lines, QJ, NJ

# 王允連環計: conv 1201~1250 | 劉備煮酒論英雄(左慈相助): conv 1254~1272
WY = {2: '王允', 3: '董卓', 4: '貂蟬'}
PATCH_STAGES = []   # (quest id, stage idx, convs, sp): 舊任務某 stage 補原版對白
REPLACED = []   # 被原版取代嘅自訂任務 id (會喺 quests.json 刪走)
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


# ---- 批次 3: 千里走單騎 (過五關斬六將) ----
BOSSES += [(1111, '秦琪', 30), (1112, '王植', 32), (1113, '卞喜', 34), (1114, '孟坦', 36), (1115, '孔秀', 38), (1116, '蔡陽', 40)]
def _npc(i, name, x, y, m, idle, desc):
    return {"id": i, "name": name, "x": x, "y": y, "map": m, "questOnly": True, "idle": [name + "：「" + idle + "」"], "desc": desc + "【原版】"}
NEW_NPCS_EXTRA += [
    _npc("guanyu", "關羽", 38, 16, "chenliu", "大哥……", "曹營中嘅關雲長"),
    _npc("qinqi", "秦琪", 30, 20, "hanshui", "黃河渡口，閒人免進！", "黃河渡口守將"),
    _npc("wangzhi", "王植", 40, 20, "wancheng_road", "滎陽城外，此路不通！", "滎陽守將"),
    _npc("bianxi", "卞喜", 40, 20, "runan_road", "沂水關重地！", "沂水關守將"),
    _npc("mengtan", "孟坦", 20, 20, "luoyang", "洛陽關口，速速退去！", "洛陽守將"),
    _npc("kongxiu", "孔秀", 30, 24, "chenliu", "東嶺關豈容你闖！", "東嶺關守將"),
    _npc("caiyang", "蔡陽", 20, 17, "xiaopei", "逆賊關羽，拿命來！", "追兵蔡陽"),
]
QUESTS += [
    {"id": "orig_guanyu", "src": "orig", "name": "千里走單騎", "type": "history", "giver": "liubei",
     "pre": {"minLevel": 32},
     "preHint": "武功 32 級以上，去小沛搵劉備",
     "stages": [
         {"type": "talk", "npc": "liubei", "conv": [1326], "sp": {2: '劉備'},
          "hint": "劉備要你去曹營搵關羽，沿途要闖五關：先去漢水渡口打秦琪"},
         {"type": "fight", "npc": "qinqi", "monster": 1111, "conv": [1342], "win": 1327, "hint": "漢水渡口打低守將秦琪"},
         {"type": "fight", "npc": "wangzhi", "monster": 1112, "conv": [1342], "win": 1328, "hint": "宛城道打低守將王植"},
         {"type": "fight", "npc": "bianxi", "monster": 1113, "conv": [1342], "win": 1329, "hint": "汝南道打低沂水關守將卞喜"},
         {"type": "fight", "npc": "mengtan", "monster": 1114, "conv": [1342], "win": 1330, "hint": "洛陽打低守將孟坦"},
         {"type": "fight", "npc": "kongxiu", "monster": 1115, "conv": [1342], "win": 1331, "hint": "陳留郊外打低東嶺關孔秀"},
         {"type": "talk", "npc": "guanyu", "conv": [1333], "sp": {2: '關羽'},
          "hint": "五關已破，面呈家書畀關羽"},
         {"type": "escort", "npc": "liubei", "escortName": "關羽", "conv": [1322], "sp": {2: '劉備'},
          "hint": "護送關羽返小沛見劉備，唔好行太遠"},
         {"type": "fight", "npc": "caiyang", "monster": 1116, "conv": [1340], "sp": {3: '蔡陽', 4: '關羽'}, "win": 1341,
          "hint": "蔡陽追到小沛，打低佢"},
         {"type": "talk", "npc": "liubei", "conv": [1323], "sp": {3: '劉備', 4: '關羽'}, "done": True,
          "hint": "兄弟團聚，向劉備領謝禮"}],
     "reward": {"fame": 60, "exp": 8000, "gold": 1600}},
]


# ---- 批次 4: 三顧茅廬 (原版: 鐵樹精華 / 天山樹鬚 要打怪收集) ----
# 【自訂】掉落怪: 原版冇可收嘅來源，加兩種洞穴怪 (id 唔喺 npc_drops.csv，import_drops 唔會郁)
DROP_MONS = [  # (id, name, lv, sprite, 掉落 item, 出場 zone)
    (1117, '鐵樹精', 36, 31016, 52040, 'xc1753'),
    (1118, '樹鬚妖', 40, 54051, 52045, 'xc1754'),
]
NEW_NPCS_EXTRA += [
    _npc("xushu", "徐庶", 38, 30, "xuchang", "唉……老母被曹操所困……", "被曹操騙回許昌嘅徐元直"),
]
QUESTS += [
    {"id": "orig_longzhong", "src": "orig", "name": "三顧茅廬·原版", "type": "history", "giver": "guanyu",
     "pre": {"minLevel": 36},
     "preHint": "武功 36 級以上，去陳留搵關羽",
     "stages": [
         {"type": "talk", "npc": "guanyu", "conv": [1348], "sp": {2: '關羽'},
          "hint": "關羽要你去許昌城搵徐庶，問點樣救劉備"},
         {"type": "talk", "npc": "xushu", "conv": [1354], "sp": {2: '徐庶'},
          "hint": "去許昌城搵徐庶，問復原之法"},
         {"type": "talk", "npc": "caolu_boy", "conv": [1369], "sp": {2: '書童'},
          "hint": "去隆中草廬問書童臥龍先生喺邊"},
         {"type": "collect", "npc": "caolu_boy", "item": {"id": 52040, "n": 10}, "conv": [1366], "sp": {2: '書童'},
          "hint": "去陳留·洞穴3 打鐵樹精（Lv36），收集鐵樹精華 %v/%n，交畀書童"},
         {"type": "collect", "npc": "zhugeliang", "item": {"id": 52045, "n": 10}, "conv": [1384], "sp": {2: '諸葛亮'},
          "hint": "去陳留·洞穴4 打樹鬚妖（Lv40），收集天山樹鬚 %v/%n，交畀諸葛亮"},
         {"type": "talk", "npc": "zhugeliang", "conv": [1381], "sp": {2: '諸葛亮'}, "done": True,
          "hint": "孔明願意出山輔佐，聽佢分析天下大勢"}],
     "reward": {"fame": 80, "exp": 12000, "gold": 2000}},
]


def add_drop_mons():
    p = 'client/data/monsters.json'
    md = json.load(open(p, encoding='utf8'))
    ms = md['monsters']
    ids = {m[0] for m in DROP_MONS}
    ms[:] = [m for m in ms if m['id'] not in ids]
    md['spawns'] = [x for x in md['spawns'] if x['monster'] not in ids]
    for mid, name, lv, spr, item, zone in DROP_MONS:
        ms.append({'id': mid, 'name': name, 'level': lv, 'hp': 10 * lv * lv + 20, 'atk': 3 * lv + 4, 'def': max(0, lv // 4),
                   'atkInterval': 20, 'moveSpeed': 1, 'exp': 6 + 3 * lv, 'gold': [0, 3 * lv], 'alignment': -30,
                   'aggroRange': 5, 'leash': 10, 'element': 'none', 'sprite': spr,
                   'drops': [{'item': item, 'p': 0.5}], 'rareDrops': [], 'suppDrops': []})
        md['spawns'].append({'zone': zone, 'monster': mid, 'count': 6, 'respawnTicks': 200, 'lv': lv})
    json.dump(md, open(p, 'w', encoding='utf8', newline=chr(10)), ensure_ascii=False, indent=1)


# ---- 批次 5: 甘寧殺黃祖 ----
BOSSES += [(1119, '黃祖', 44)]
NEW_NPCS_EXTRA += [
    _npc("ganning", "甘寧", 20, 14, "gangkou", "咳……痛死我了……", "身受重傷嘅東吳將軍"),
    _npc("huangzu", "黃祖", 30, 18, "changsha", "何方小賊，敢闖我營！", "江夏太守黃祖"),
    _npc("zhouyu_gk", "周瑜", 28, 14, "gangkou", "戰事吃緊，不可延誤！", "東吳都督"),
]
QUESTS += [
    {"id": "orig_ganning", "src": "orig", "name": "替甘寧復仇", "type": "history", "giver": "liubei",
     "pre": {"minLevel": 42},
     "preHint": "武功 42 級以上，去小沛搵劉備",
     "stages": [
         {"type": "talk", "npc": "liubei", "conv": [1388], "sp": {2: '劉備'},
          "hint": "劉備要你去殺黃祖，先去港口搵受傷嘅甘寧"},
         {"type": "talk", "npc": "ganning", "conv": [1392, 1393], "sp": {2: '甘寧'},
          "hint": "去港口搵甘寧，了解黃祖嘅仇怨"},
         {"type": "fight", "npc": "huangzu", "monster": 1119, "conv": [], "win": 1394,
          "hint": "去長沙城打低黃祖（Lv44）"},
         {"type": "talk", "npc": "zhouyu_gk", "conv": [1395], "sp": {2: '周瑜'}, "done": True,
          "hint": "返港口向東吳都督周瑜覆命"}],
     "reward": {"fame": 70, "exp": 10000, "gold": 1800}},
]


# ---- 批次 6: 孫堅匿璽 (取代自訂 hist_sunjian_seal) ----
REPLACED += ['hist_sunjian_seal']
NEW_NPCS_EXTRA += [
    _npc("well_guard", "守井小兵", 26, 14, "luoyang", "真是一口詭異的井呀！", "守著皇城古井嘅小兵"),
]
QUESTS += [
    {"id": "orig_sunjian_seal", "src": "orig", "name": "孫堅匿璽", "type": "history", "giver": "well_guard",
     "pre": {"minLevel": 10, "attr": {"pol": 10, "cha": 10}},
     "preHint": "武功 10 級以上，去洛陽城搵守井小兵",
     "stages": [
         {"type": "talk", "npc": "well_guard", "conv": [3198], "sp": {2: '守井小兵'},
          "hint": "守井小兵請你去稟告孫文臺（洛陽城內宮宅旁）"},
         {"type": "talk", "npc": "sunwentai", "conv": [3205], "sp": {2: '孫文臺'}, "getItem": {"id": 56491, "n": 1},
          "hint": "帶特亮蠟燭，落皇城井底打撈"},
         {"type": "collect", "npc": "well_guard", "item": {"id": 56494, "n": 1}, "conv": [3210], "sp": {2: '守井小兵'},
          "hint": "皇城井底打木乃伊/殭屍，撈玉璽錦囊 %v/%n，交畀守井小兵"},
         {"type": "talk", "npc": "sunwentai", "conv": [3211, 3213], "sp": {2: '孫文臺'},
          "takeItems": [[56491, 1]], "getItem": {"id": 56495, "n": 1},
          "hint": "將玉璽錦囊呈畀孫文臺，攞佢嘅委託函"},
         {"type": "fight", "npc": "chengpu", "monster": 1089, "conv": [3217], "sp": {2: '程普'},
          "takeItems": [[56495, 1]], "done": True,
          "hint": "去程府（洛陽城內）同程普 PK，行近程普對話開打"}],
     "reward": {"fame": 40, "polExp": 30, "items": [[31902, 1]]}},
]


# ---- 批次 7: 張公公謀害何進 (取代自訂) + 代呂布斬丁原 (補原版對白) ----
REPLACED += ['hist_zhanggong']
PATCH_STAGES += [('hist_dingyuan', 3, [3189], {2: '丁原'})]
PATCH_STAGES += [('hist_dongzhuo', 0, [2860, 2861], {2: '李儒'}), ('hist_dongzhuo', 1, [2866], {2: '董卓'}),
                 ('hist_yuanshao', 0, [2880, 2881], {2: '袁紹'}), ('hist_yuanshao', 1, [2885], {2: '王允'}),
                 ('hist_caoamang', 1, [2980, 2982], {2: '曹阿瞞'}), ('hist_caoamang', 2, [2986], {2: '曹嵩'})]
QUESTS += [
    {"id": "orig_zhanggong", "src": "orig", "name": "張公公謀害何進", "type": "history", "giver": "zhanggong",
     "pre": {"karmaMax": 0, "minLevel": 10, "attr": {"pol": 10, "cha": 10}},
     "preHint": "PK 值為 0（未曾濫殺），去下邳城內搵張公公",
     "stages": [
         {"type": "talk", "npc": "zhanggong", "conv": [3176, 3177], "sp": {2: '張公公'}, "getItem": {"id": 56497, "n": 1},
          "hint": "帶何府通行牌去下邳何府，傳何太后懿旨"},
         {"type": "talk", "npc": "hefu_guard", "conv": [3179], "sp": {2: '何府守衛'},
          "hint": "守衛唔放行，返去搵張公公取太后手諭"},
         {"type": "talk", "npc": "zhanggong", "conv": [3180], "sp": {2: '張公公'}, "getItem": {"id": 56498, "n": 1},
          "hint": "帶太后手諭返何府畀守衛睇"},
         {"type": "talk", "npc": "hefu_guard", "conv": [3181], "sp": {2: '何府守衛'}, "takeItems": [[56498, 1]],
          "hint": "守衛放行，入何府搵何進"},
         {"type": "fight", "npc": "hejin", "monster": 1090, "conv": [], "win": 3182, "hint": "喺何府同何進 PK（行近何進對話開打）"},
         {"type": "talk", "npc": "zhanggong", "conv": [3183], "sp": {2: '張公公'}, "takeItems": [[56497, 1]], "done": True,
          "hint": "返下邳向張公公覆命"}],
     "reward": {"fame": 40, "polExp": 30, "items": [[32203, 1]]}},
]


# ---- 批次 8: 替天行道討伐張角 (取代自訂) + 三顧茅廬 原版取代自訂 ----
REPLACED += ['hist_zhangjiao']
QUESTS += [
    {"id": "orig_zhangjiao", "src": "orig", "name": "替天行道討伐張角", "type": "history", "giver": "zhangjiao",
     "pre": {"minLevel": 20, "attr": {"cha": 10, "pol": 10}, "workLv": {"herbalism": 10}},
     "preHint": "武功 20 級、魅力/政治/採藥 10 級以上，去洛陽私塾黃巾道場搵張角",
     "stages": [
         {"type": "talk", "npc": "zhangjiao", "conv": [2704, 2705], "sp": {2: '張角'},
          "hint": "去洛陽城外南華竹林（左下方）搵南華老仙"},
         {"type": "ask", "npc": "nanhua_child", "conv": [2713, 2714], "sp": {2: '南華小童'},
          "options": ["元稹", "張祐", "賈島", "李頻"], "answer": 2, "resp": 2715, "wrongc": 2716,
          "hint": "答啱南華小童嘅問題（『松下問童子』嘅作者）"},
         {"type": "talk", "npc": "nanhua_old", "conv": [2719], "sp": {2: '南華老仙'}, "getItem": {"id": 56502, "n": 1},
          "hint": "入屋搵南華老仙，攞太平要術"},
         {"type": "talk", "npc": "zhangjiao", "conv": [2708, 2709], "sp": {2: '張角'}, "takeItems": [[56502, 1]],
          "hint": "將太平要術交畀張角"},
         {"type": "talk", "npc": "nanhua_child", "conv": [2722, 2724], "sp": {2: '南華小童'},
          "hint": "張角要造反，返南華竹林聽小童交代"},
         {"type": "fight", "npc": "zhangjiao", "monster": 1092, "conv": [2710], "sp": {3: '張角'}, "win": 2711,
          "getItem": {"id": 56502, "n": 1}, "hint": "擊敗張角，奪返太平要術"},
         {"type": "talk", "npc": "nanhua_old", "conv": [2725, 2749], "sp": {2: '南華老仙'}, "takeItems": [[56502, 1]], "done": True,
          "hint": "帶太平要術返去搵南華老仙"}],
     "reward": {"fame": 50, "items": [[56027, 1]]}},
]


def snap(g, x, y, others):
    for r in range(0, 20):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) != r:
                    continue
                xx, yy = x + dx, y + dy
                if 0 <= yy < len(g) and 0 <= xx < len(g[yy]) and g[yy][xx] in '.:=,_+'                         and all(max(abs(xx - ox), abs(yy - oy)) >= 2 for ox, oy in others):
                    return xx, yy
    raise SystemExit('搵唔到位 %d,%d' % (x, y))


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
    add_drop_mons()
    convs = load_convs()

    for n in ALL_NPCS:      # 位置係估嘅: 唔行得就搵最近行得嘅格 (同圖其他 NPC ≥2 格)
        g = open('client/data/maps/%s.txt' % n['map'], encoding='utf8').read().split(chr(10))
        n['x'], n['y'] = snap(g, n['x'], n['y'], [(o['x'], o['y']) for o in ALL_NPCS if o['map'] == n['map'] and o is not n])
    qd = json.load(open(QJ, encoding='utf8'))
    nd = json.load(open(NJ, encoding='utf8'))
    names = {n['id']: n['name'] for n in nd['npcs']}
    for n in ALL_NPCS:
        names[n['id']] = n['name']
        nd['npcs'] = [x for x in nd['npcs'] if x['id'] != n['id']] + [n]
    ids = {q['id'] for q in QUESTS} | set(REPLACED)
    qd['quests'] = [q for q in qd['quests'] if q['id'] not in ids]
    for q in QUESTS:
        q = json.loads(json.dumps(q))
        for st in q['stages']:
            ls = []
            for cid in st['conv']:
                ls += lines(convs[cid], names[st['npc']], st.get('sp'))
            st['dialog'] = ls
            for k, tgt in (('resp', 'response'), ('wrongc', 'wrong')):
                if k in st:
                    st[tgt] = lines(convs[st.pop(k)], names[st['npc']], st.get('sp'))
            oc = list(st.pop('conv'))
            if 'win' in st:      # 打贏後敗將對白
                w = st.pop('win')
                nm = names[st['npc']]
                st['winDialog'] = lines(convs[w], nm, {2: nm, 3: nm})
                oc.append(w)
            st['origConv'] = oc
            st.pop('sp', None)
        qd['quests'].append(q)
    for qid, si, cv, sp in PATCH_STAGES:
        st = next(q for q in qd['quests'] if q['id'] == qid)['stages'][si]
        ls = []
        for cid in cv:
            ls += lines(convs[cid], st['npc'], sp)
        st['dialog'] = ls
        st['origConv'] = cv
    json.dump(qd, open(QJ, 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
    json.dump(nd, open(NJ, 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
    print('ok', len(QUESTS), 'quests', len(ALL_NPCS), 'npcs')

if __name__ == '__main__':
    main()
