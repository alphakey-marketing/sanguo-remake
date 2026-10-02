"""登用武將導入 (Step 13.5, spec 09 §2 / spec 11 §4)。

來源: data_src/general_npc.csv (1261 武將: id/名/f101/f116/9 技能 id:lv)【原】
  f101 = 戰等【原】: 同攻略 sy2_6_2「20 級之前武將一覽表」42 人逐個對得上 (見 GUIDE_LV 核對)
  f116 ≈ 智力類係數 0~255 (spec 11，中信心)；只用嚟分文官小類
  skill id 1~18 → 名: 由原版 general_skills.csv 對照得出 (SKILL_NAMES)；0 = 空格
【自訂】部分:
  - 類型: 戰等 < 50 或 (f116 ≥ 250 且戰等 < 70) = 文官 (問答登用)；其餘 = 武將 (擂台 PK)
  - 小類 (攻略 6 型只有名，冇公式): 武將 戰等 ≥80 武力型 / ≥60 平均型 / 其餘平庸型；
    文官 f116 ≥230 且戰等 ≥40 軍師型 / f116 ≥230 謀略型 / 其餘政治型
  - 理念: Tier1 人手定；其餘按 id 雜湊 → 約一半「出仕」(攻略: 出仕 600+ 人)，其餘平均分五理念
  - Tier1: 許昌/新野 19 人，人手揀站位 + 出現時辰 (window: startKe 含 ~ endKe 不含，同 quest_npcs)
    原表同名多版 (例: 曹操 id 26/1396/1462)：Tier1 用第一個 id；其餘同名版 tier = -1 (唔入登用池)
輸出: client/data/generals.json  (唔好手改，改完重跑)

用法:
  python tools/gen_generals.py           # 生成
  python tools/gen_generals.py --check   # 核對檔案同來源一致 + 攻略戰等表 + Tier1 站位行得 (run_tests 用)
"""
import csv
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "data_src", "general_npc.csv")
OUT = os.path.join(ROOT, "client", "data", "generals.json")
MAPS = os.path.join(ROOT, "client", "data", "maps.json")

SKILL_NAMES = {1: "火計", 2: "水計", 3: "混亂", 4: "落石", 5: "落雷", 6: "陷阱", 7: "激勵", 8: "鼓舞", 9: "颶風",
               10: "狂暴", 11: "冰雹", 12: "妖術", 13: "謾罵", 14: "鐵壁", 15: "狂砂", 16: "連環", 17: "嘲笑", 18: "破陣"}
IDEOLOGIES = ["義理", "霸權", "權謀", "隱遁", "治國"]

# 攻略 sy2_6_2 20 級前武將戰等【原】→ 核對 f101
GUIDE_LV = {"蔡邕": 6, "王允": 7, "劉琦": 8, "陳珪": 8, "蔣幹": 9, "鍾繇": 9, "顧雍": 10, "張紘": 10, "于吉": 10,
            "潘濬": 11, "劉繇": 11, "左慈": 11, "嚴畯": 13, "韓嵩": 14, "程秉": 14, "劉琮": 15, "伊籍": 16, "秦宓": 16,
            "向朗": 16, "辛毗": 17, "王粲": 17, "尹默": 17, "步騭": 17, "張松": 17, "王累": 17, "蒯良": 17, "許靖": 18,
            "張昭": 18, "華佗": 18, "王朗": 18, "劉曄": 18, "陳矯": 19, "糜竺": 19, "蒯越": 19, "司馬徽": 19,
            "司馬孚": 20, "郭嘉": 20, "楊修": 20, "劉璋": 20, "楊彪": 20, "禰衡": 20, "樊建": 20}

# 登用規則設定 (rules/recruit.gd 讀)【自訂】除註明【原】
CFG = {
    "serveDays": 15,            # U16: 登用期由 30→15 game 日減半，到期子時 0 刻離開
    "recruitLockDays": 15,      # U16: 登用成功後封鎖調查嘅日數 (由曆月鎖改做滾動 15 日，配合 serveDays 減半)
    "levelGap": 10,             # 【原】唔可以登用比自己高 10 級以上
    "titleGap": 5,              # 【原】50 級以上人才: 頭銜差 ≤5 階 (Step 14；人才頭銜【自訂】= 戰等 - titleMinLv)
    "titleMinLv": 50,
    "surveyMax": 5,             # 調查一次顯示幾多個候選
    "poolBelow": 10,            # 登用池 (非 Tier1) 只列戰等 ≥ 玩家 -10 嘅人 (spec 09 §3.2 ±10 檔)
    "quizN": 10,                # 【原】問答 10 題
    "quizPass": 8,              # 答啱 8 題過關 (spec 09 §3.2)
    "arena": {"hpPerLv": 20, "atkBase": 4, "atkPerLv": 1.6, "defPerLv": 0.5, "atkInterval": 16, "leash": 30,
              "maxDist": 12},
    "companion": {"strMulWu": 1.2, "strMulWen": 0.7, "intAddWen": 0.5, "regenTicks": 10, "regenPct": 0.01,
                  "follow": 2, "farFollow": 4, "huntRange": 8, "leashOwner": 12, "expShare": 0.5},
    "loyalty": {"init": 15, "sameIdeo": 10, "leave": 5, "ko": -5, "gift": 2, "badKill": -3,
                "badKillIdeo": ["義理", "治國"],
                "badNpcKill": -15, "badNpcKillIdeo": ["義理"]},   # U16: init 60→15、leave 30→5 (死 3 次 ko×3=-15 啱啱 0 即走)；S09b 謀殺善 NPC → 義理忠誠 -15 (spec 09 §4)
}

# Tier1 (spec 09 §2): 許昌 = 曹營；新野 = 劉備軍。x/y = 地圖內座標；window = 出現刻 (96 刻/日, 8 刻一時辰)
# 冇 window = 全日喺度
W_DAY = {"startKe": 32, "endKe": 80}      # 辰~酉
W_WIDE = {"startKe": 24, "endKe": 88}     # 卯~戌 (新手搵得到)
W_NIGHT = {"startKe": 48, "endKe": 0}     # 午~亥 (跨日寫法 endKe<=startKe)
TIER1 = [
    ("曹操", "xuchang", 26, 18, "霸權", "wen", W_DAY, "寧我負人，毋人負我。天下英雄，唯使君與操耳。"),
    ("荀彧", "xuchang", 29, 18, "治國", "wen", W_DAY, "奉天子以令不臣，此大順也。"),
    ("郭嘉", "xuchang", 32, 18, "權謀", "wen", W_NIGHT, "飲兩杯先，計仔自然嚟。"),
    ("程昱", "xuchang", 38, 18, "權謀", "wen", W_DAY, "兵者詭道，何必拘泥。"),
    ("滿寵", "xuchang", 41, 18, "治國", "wen", W_DAY, "法不阿貴，許都治安由我睇住。"),
    ("鍾繇", "xuchang", 47, 18, "治國", "wen", W_WIDE, "書法講心正筆正，做人都一樣。"),
    ("蔡邕", "xuchang", 56, 26, "隱遁", "wen", W_WIDE, "焦尾琴聲，知音難求。"),
    ("典韋", "xuchang", 8, 11, "義理", "wu", None, "主公安危，就係我條命。"),
    ("許褚", "xuchang", 11, 11, "義理", "wu", None, "邊個敢亂嚟？先過我虎痴呢關！"),
    ("夏侯惇", "xuchang", 14, 11, "霸權", "wu", W_DAY, "父精母血，不可棄也！"),
    ("劉備", "xinye", 30, 21, "義理", "wen", W_DAY, "勿以惡小而為之，勿以善小而不為。"),
    ("關羽", "xinye", 27, 21, "義理", "wu", W_DAY, "溫酒斬華雄，酒尚溫時，某已回營。"),
    ("張飛", "xinye", 33, 21, "義理", "wu", W_NIGHT, "燕人張翼德在此！邊個夠膽過嚟？"),
    ("趙雲", "xinye", 36, 21, "義理", "wu", W_DAY, "常山趙子龍，願為仁主效死。"),
    ("徐庶", "xinye", 10, 22, "隱遁", "wen", W_DAY, "單福只係化名，江湖事唔好多問。"),
    ("孫乾", "xinye", 20, 23, "治國", "wen", W_WIDE, "出使四方，靠嘅係一把口。"),
    ("簡雍", "xinye", 23, 23, "隱遁", "wen", W_WIDE, "坐低飲杯茶先，唔使咁趕。"),
    ("糜竺", "xinye", 40, 23, "治國", "wen", W_WIDE, "家財萬貫，不及明主一諾。"),
    ("伊籍", "xinye", 14, 23, "治國", "wen", W_WIDE, "荊州局勢複雜，要睇清先好落注。"),
]


def _hash(n):
    return (n * 2654435761) & 0xFFFFFFFF


def gen_type(lv, f116):
    return "wen" if lv < 50 or (f116 >= 250 and lv < 70) else "wu"


def gen_sub(t, lv, f116):
    if t == "wu":
        return "武力型" if lv >= 80 else "平均型" if lv >= 60 else "平庸型"
    if f116 >= 230:
        return "軍師型" if lv >= 40 else "謀略型"
    return "政治型"


def gen_ideo(gid):
    h = _hash(gid)
    if h % 100 < 48:
        return "出仕"
    return IDEOLOGIES[(h >> 8) % 5]


_placed = {}


def _orig_place(old_map):
    import migrate_to_orig as M
    from collections import defaultdict
    tm = M.REMAP[old_map]
    n = _placed.setdefault(tm, [])
    x, y = M.place_near(tm, len(n), n)
    n.append((x, y))
    return tm, x, y


def build():
    rows = list(csv.DictReader(open(SRC, encoding="utf-8-sig")))
    t1 = {x[0]: x for x in TIER1}
    out = []
    for r in rows:
        gid = int(r["id"])
        lv = int(r["f101_str"])
        f116 = int(r["f116_int"])
        skills = []
        for tok in r["skills(id:lv)x9"].split():
            sid, slv = (int(v) for v in tok.split(":"))
            if sid > 0:
                skills.append([sid, slv])
        t = gen_type(lv, f116)
        g = {"id": gid, "name": r["name"], "lv": lv, "int": f116, "skills": skills, "type": t,
             "sub": gen_sub(t, lv, f116), "ideo": gen_ideo(gid), "tier": 0}
        if r["name"] in t1:
            _, mp, x, y, ideo, typ, win, idle = t1.pop(r["name"])
            mp, x, y = _orig_place(mp)       # 舊 ASCII 圖已封存：Tier1 常駐搬去原版城街
            g.update({"type": typ, "sub": gen_sub(typ, lv, f116), "ideo": ideo, "tier": 1, "map": mp, "x": x, "y": y,
                      "idle": [idle]})
            if win:
                g["window"] = win
        out.append(g)
    assert not t1, "Tier1 搵唔到: %s" % list(t1)
    t1_names = {x[0] for x in TIER1}
    for g in out:
        if g["tier"] == 0 and g["name"] in t1_names:
            g["tier"] = -1          # Tier1 同名另一版本 (原表同名多版)：唔入登用池
    return {"_note": "登用武將 (spec 09 §2~3)。由 tools/gen_generals.py 生成，唔好手改。lv = 戰等【原】；type wu=武將(擂台)/wen=文官(問答)；"
                     "ideo = 理念 (出仕 = 人人可登用)；tier 1 = 城內常駐 (map/x/y 地圖內座標, window = 出現刻)；tier -1 = Tier1 同名分身 (唔入池)。",
            "cfg": CFG, "skillNames": {str(k): v for k, v in SKILL_NAMES.items()}, "generals": out}


def dump(o):
    lines = ["{", '  "_note": %s,' % json.dumps(o["_note"], ensure_ascii=False),
             '  "cfg": %s,' % json.dumps(o["cfg"], ensure_ascii=False),
             '  "skillNames": %s,' % json.dumps(o["skillNames"], ensure_ascii=False), '  "generals": [']
    gs = o["generals"]
    for i, g in enumerate(gs):
        lines.append("    " + json.dumps(g, ensure_ascii=False) + ("," if i < len(gs) - 1 else ""))
    lines += ["  ]", "}", ""]
    return "\n".join(lines)


def verify(o):
    errs = []
    by = {g["name"]: g for g in o["generals"]}
    for n, lv in GUIDE_LV.items():
        if n not in by or by[n]["lv"] != lv:
            errs.append("攻略戰等對唔上: %s 應 %d 得 %s" % (n, lv, by.get(n, {}).get("lv")))
    mj = json.load(open(MAPS, encoding="utf-8"))
    walk = {k for k, v in mj["legend"].items() if v["walk"]}
    seen = set()
    for g in o["generals"]:
        if g["tier"] != 1:
            continue
        rows = open(os.path.join(ROOT, "client", "data", "maps", g["map"] + ".txt"), encoding="utf-8").read().split("\n")
        if rows[g["y"]][g["x"]] not in walk:
            errs.append("Tier1 站位行唔到: %s %s(%d,%d)" % (g["name"], g["map"], g["x"], g["y"]))
        if (g["map"], g["x"], g["y"]) in seen:
            errs.append("Tier1 站位重疊: %s" % g["name"])
        seen.add((g["map"], g["x"], g["y"]))
    return errs


def main():
    o = build()
    txt = dump(o)
    gs = o["generals"]
    n_wen = sum(1 for g in gs if g["type"] == "wen")
    n_ss = sum(1 for g in gs if g["ideo"] == "出仕")
    print("[generals] %d 人 (文官 %d / 武將 %d)；出仕 %d；Tier1 %d" % (len(gs), n_wen, len(gs) - n_wen, n_ss,
                                                                 sum(1 for g in gs if g["tier"] == 1)))
    errs = verify(o)
    for e in errs:
        print("[generals] FAIL " + e)
    if "--check" in sys.argv:
        cur = open(OUT, encoding="utf-8").read().replace("\r\n", "\n") if os.path.exists(OUT) else ""
        if cur != txt:
            print("[generals] --check FAIL: generals.json 同來源唔一致，重跑 tools/gen_generals.py")
            sys.exit(1)
        if errs:
            sys.exit(1)
        print("[generals] --check OK")
        return
    if errs:
        sys.exit(1)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)
    print("[generals] 寫咗", OUT)


if __name__ == "__main__":
    main()
