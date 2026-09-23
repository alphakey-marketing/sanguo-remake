#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Step 11 導入器 (spec 11 §2 + spec 04 §1~2):
npc_drops.csv (rate 基數 100000) → monsters.json 掉落；等級帶模板生成數值。
- rate -> p = rate/100000；p >= 0.05 入 drops(常見)，p < 0.05 入 rareDrops(稀有)
- 怪物等級 = npc_drops.csv 第 3 欄 (Npc_table.tsv hp 柱相同，怪物用唔用都得)
- 數值模板【自訂】spec 04 §1 表 (等級帶線性插值 + 用 npc_id 做 ±20% 確定性抖動，唔用 RNG → 檔案穩定)
- item id 全部對 items.json 校驗，報 missing
- 同時生成汝南洞窟 10 層 zones + 傳送點 + 牆 (spec 04 §2)

用法: python tools/import_drops.py   (輸出 client/data/monsters.json + zones.json)
"""
import csv
import json
import math
import os
import re

RE_ID_RATE = re.compile(r"\((\d+)\)@(\d+)")

HERE = os.path.dirname(os.path.abspath(__file__))
CLIENT = os.path.normpath(os.path.join(HERE, ".."))
DATA = os.path.join(CLIENT, "data")
SRC = r"D:/Download/sanguo/extracted/text"

NPC_DROPS = os.path.join(SRC, "npc_drops.csv")

# ---------------------------------------------------------------------------
# 1. 怪物名單【自訂揀選】(spec 04 §2)：npc id -> 檔案內要點
#    zone      = 地圖區 (field_1 = 許昌城外；runan_f* = 汝南洞窟層)
#    spawn     = {count, respawnTicks}
#    aggro     = 主動攻擊距離 (0 = 被動)
#    groups    = 群居: 打 1 隻附近 5 格同類一齊仇恨【自訂】(spec 04 §3)
#    flee      = False = 唔會逃跑 (boss/PK 戰怪)
#    boss      = True = 每日重生一次 (spec 04 §3)
#    alignment = 善惡值 (負 = 惡)；無害動物低值、猛獸/匪按等級
ROSTER = [
    # 許昌城外深處 (原 11 隻以外)
    (11091, "山賊",   "field_1",   (3, 400), 5, False, True,  None),
    (11068, "流氓1",  "field_1",   (2, 500), 5, False, True,  None),
    (11070, "地痞1",  "field_1",   (1, 900), 4, False, True,  None),
    # 汝南洞窟 1 層 (5~6 級)
    (12022, "水鴨",   "runan_f1",  (4, 150), 0, False, True,  None),
    (12044, "兔兒",   "runan_f1",  (4, 180), 0, False, True,  None),
    # 2 層 (7~9)
    (12003, "野兔",   "runan_f2",  (3, 200), 0, False, True,  None),
    (12046, "草貂",   "runan_f2",  (3, 220), 0, False, True,  None),
    # 3 層 (9)
    (12021, "野貂",   "runan_f3",  (3, 240), 0, False, True,  None),
    (12029, "蝴蝶精", "runan_f3",  (2, 250), 0, False, True,  None),
    (12031, "蜻蜓",   "runan_f3",  (2, 240), 0, False, True,  None),
    # 4 層 (11)
    (12011, "猴子",   "runan_f4",  (3, 260), 0, False, True,  None),
    (12005, "母雞",   "runan_f4",  (3, 260), 0, False, True,  None),
    # 5 層 (14)
    (12018, "山羊",   "runan_f5",  (3, 280), 0, False, True,  None),
    (12030, "飛蛾怪", "runan_f5",  (2, 280), 0, False, True,  None),
    # 6 層 (14)
    (12013, "野豬",   "runan_f6",  (3, 300), 4, False, True,  None),
    (12019, "瘋貓",   "runan_f6",  (2, 300), 4, False, True,  None),
    # 7 層 (16) 群居
    (12012, "野狗",   "runan_f7",  (4, 260), 5, True,  True,  None),
    # 8 層 (18~20)
    (12006, "狐貍",   "runan_f8",  (3, 320), 5, False, True,  None),
    (12014, "花鹿",   "runan_f8",  (2, 300), 0, False, True,  None),
    # 9 層 (20)
    (12028, "黃蜂",   "runan_f9",  (4, 240), 4, True,  True,  None),
    (12017, "大蟒",   "runan_f9",  (2, 350), 4, False, True,  None),
    (12034, "蝙蝠",   "runan_f9",  (4, 200), 4, True,  True,  None),
    # 10 層: 蝙蝠群 + boss (每日重生)
    (19001, "洞窟獸王", "runan_f10", (1, 0), 6, False, False, True),
]

# boss 無 npc_drops 資料 → 唔查 CSV，直接手寫 (item id 已驗；level 22 自訂)
BOSS_LEVEL = 22
BOSS_DROPS = {"drops": [(61505, 0.5), (61504, 0.35), (29042, 0.3), (25107, 0.12), (28035, 0.08)],
              "rareDrops": [(32302, 0.02)]}

# 等級帶數值模板 (spec 04 §1 表): (lv, hp_lo, hp_hi, atk_lo, atk_hi, def_lo, def_hi)
BANDS = [
    (1, 20, 70, 4, 12, 0, 3),
    (5, 20, 70, 4, 12, 0, 3),
    (6, 120, 260, 16, 26, 5, 8),
    (10, 120, 260, 16, 26, 5, 8),
    (11, 300, 800, 30, 55, 10, 16),
    (20, 300, 800, 30, 55, 10, 16),
    (21, 900, 2200, 60, 100, 18, 30),
    (35, 900, 2200, 60, 100, 18, 30),
    (36, 2400, 5000, 110, 180, 32, 48),
    (50, 2400, 5000, 110, 180, 32, 48),
    (51, 5500, 12000, 190, 320, 50, 75),
    (70, 5500, 12000, 190, 320, 50, 75),
    (71, 13000, 40000, 330, 600, 80, 120),
    (90, 13000, 40000, 330, 600, 80, 120),
    (91, 45000, 300000, 650, 1500, 130, 200),
    (100, 45000, 300000, 650, 1500, 130, 200),
]


def band_stats(lv: int):
    """等級帶內線性插值 -> (hp, atk, def)。lv 介乎兩條 band edge 之間。"""
    for i in range(len(BANDS) - 1):
        l0, hp0, hp1, a0, a1, d0, d1 = BANDS[i]
        l1, hp2, hp3, a2, a3, d2, d3 = BANDS[i + 1]
        if l0 <= lv <= l1:
            t = (lv - l0) / (l1 - l0)
            return (hp0 + t * (hp2 - hp0), a0 + t * (a2 - a0), d0 + t * (d2 - d0))
    raise ValueError("level out of band: %d" % lv)


def exp_to_next(lv: int) -> int:
    """還原 client/rules/stats.gd exp_to_next 公式。"""
    return int(round(20.0 * lv ** 1.8))


def jitter_pct(npc_id: int) -> float:
    """確定性抖動 ±20% (spec 04 §1): 用 npc_id 做 hash，唔用 RNG → 導入結果穩定。"""
    h = (npc_id * 2654435761) % 41 - 20
    return h / 100.0


def parse_drops(raw: str, item_ids, report):
    """drops 欄: '名(id)@rate 名(id)@rate' -> (common, rare)。rate 基數 100000。"""
    common, rare = [], []
    for m_id, m_rate in RE_ID_RATE.findall(raw):
        iid = int(m_id)
        p = int(m_rate) / 100000.0
        if iid not in item_ids:
            report.append("MISSING item %d" % iid)
            continue
        (common if p >= 0.05 else rare).append((iid, p))
    return common, rare


def build_monsters():
    items = json.load(open(os.path.join(DATA, "items.json"), encoding="utf-8"))
    item_ids = {int(it["id"]) for it in items}
    old = json.load(open(os.path.join(DATA, "monsters.json"), encoding="utf-8"))
    # 冪等: 10000 以下係手寫原裝怪 (1001~1011)，每次都重新由 0 組 list；roster 怪一律重建
    defs = [d for d in old["monsters"] if int(d["id"]) < 10000]
    spawns = [s for s in old["spawns"] if int(s["monster"]) < 10000]

    csv_map = {}
    with open(NPC_DROPS, encoding="utf-8-sig") as f:
        for row in csv.reader(f):
            if not row or not row[0].strip().isdigit():
                continue
            csv_map[int(row[0])] = row  # id -> [id, name, level, n_drops, drops]

    report = []
    imported = 0
    for npc_id, _, zone, (count, respawn), aggro, groups, flee, is_boss in ROSTER:
        if is_boss:
            jit = jitter_pct(npc_id)
            lv = BOSS_LEVEL
            hp, atk, d = band_stats(lv)
            hp = max(1, int(round(hp * (1 + jit) * 3.0)))
            atk = max(1, int(round(atk * (1 + jit) * 1.6)))
            d = max(0, int(round(d * 1.5)))
            exp = max(5, int(round(exp_to_next(lv) / 6.0 * 1.5)))
            common, rare = BOSS_DROPS["drops"], BOSS_DROPS["rareDrops"]
            name, lv_s = "洞窟獸王", lv
            for iid, _ in common + rare:
                if iid not in item_ids:
                    report.append("MISSING item %d (boss)" % iid)
        else:
            row = csv_map.get(npc_id)
            if row is None:
                report.append("MISSING npc %d in npc_drops.csv" % npc_id)
                continue
            name, lv_s = row[1], int(row[2])
            lv = lv_s if lv_s in range(1, 101) else 1
            jit = jitter_pct(npc_id)
            hp, atk, d = band_stats(lv)
            hp = max(1, int(round(hp * (1 + jit))))
            atk = max(1, int(round(atk * (1 + jit))))
            d = max(0, int(round(d)))
            exp = max(5, int(round(exp_to_next(lv) / 6.0)))
            common, rare = parse_drops(row[4] if len(row) > 4 else "", item_ids, report)
        alignment = -40 if aggro == 0 else -(lv * 20)
        mdef = {
            "id": npc_id,
            "name": name,
            "level": lv,
            "hp": hp,
            "atk": atk,
            "def": d,
            "atkInterval": max(12, 20 - lv // 5),
            "moveSpeed": 1,
            "exp": exp,
            "gold": [0, lv * 3],
            "alignment": alignment,
            "aggroRange": aggro,
            "leash": 10,
            "groups": groups,
            "flee": flee,
            "drops": [{"item": i, "p": p} for i, p in common],
            "rareDrops": [{"item": i, "p": p} for i, p in rare],
        }
        if is_boss:
            mdef["boss"] = True
        defs.append(mdef)
        spawns.append({
            "zone": zone,
            "monster": npc_id,
            "count": count,
            "respawnTicks": respawn,
        })
        imported += 1

    out = {
        "_note": "第一批 5 種 1~10 級野區怪 + 3 隻術法怪 (Step 9) + 絕招 boss (Step 10) +"
                 "Step 11 導入 (spec 11 §2): npc_drops.csv rate→p (rate/100000)，p≥0.05 入 drops、p<0.05 入 rareDrops。"
                 "levels/hp/atk/exp 數值 = spec 04 §1 等級帶模板【自訂】(npc_id 確定性抖動 ±20%)。"
                 "boss=true → 每日重生一次 (spec 04 §3)；groups=true 群居 / flee=false 唔逃走 (boss/PK 怪)。"
                 "洞窟怪 levels 由 npc_drops.csv 第 3 欄 (怪物等級)，樓層分佈見 spawns zone: runan_f1~f10。"
                 "alignment: NPC 善惡值，負=惡。atkInterval = tick(10Hz)。element: 屬性 (spec 02 §3.2 相剋)。"
                 "spell/spellCd: 術法怪用 data/spells.json 術法 id + 冷卻 (tick)。",
        "monsters": defs,
        "spawns": spawns,
    }
    path = os.path.join(DATA, "monsters.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("monsters.json: %d defs (%d imported), %d spawns" % (len(defs), imported, len(spawns)))
    print("item validation: %s" % ("ALL OK" if not report else "; ".join(report)))
    return imported, report


# ---------------------------------------------------------------------------
# 汝南洞窟 10 層 (spec 04 §2): 雙欄 5×2 佈局，每層一 zone，樓梯傳送點串連
# 地圖擴闊到 W=128 (sim.gd)。舊區 0~60 不動；洞窟佔 x 62~123 (牆 61/92~93/124~127、頂底)。
# 層 1~5 喺左欄, 6~10 右欄。每層可用區 = 30×10；樓梯點係雙向傳送對。
# 【自訂改編】入口暫放許昌城外東邊 (58,44)——新野地圖未開 (spec 04 §2 原文: 新野城外入口)。
COL_A = (62, 91)
COL_B = (94, 123)
FLOOR_ROWS = [(1, 10), (13, 22), (25, 34), (37, 46), (49, 58)]  # 每欄 5 層

CAVE_FLOOR_NAMES = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]


def cave_layout():
    rooms = {}  # floor (1..10) -> (x0, y0, x1, y1)
    for row, (y0, y1) in enumerate(FLOOR_ROWS):
        rooms[row + 1] = (COL_A[0], y0, COL_A[1], y1)
        rooms[row + 6] = (COL_B[0], y0, COL_B[1], y1)
    return rooms


def build_zones():
    rooms = cave_layout()
    zones = [
        {"id": "town", "name": "許昌城", "safe": True, "x0": 0, "y0": 0, "x1": 25, "y1": 25},
        {"id": "field_1", "name": "城外野地", "safe": False, "x0": 26, "y0": 26, "x1": 60, "y1": 60},
    ]
    for f in range(1, 11):
        x0, y0, x1, y1 = rooms[f]
        zones.append({"id": "runan_f%d" % f, "name": "汝南洞窟 %dF" % f,
                      "safe": False, "x0": x0, "y0": y0, "x1": x1, "y1": y1})

    # 傳送點對 (A 點 ↔ B 點): 洞口 + 每層樓梯。point 喺邊層就放邊層內
    cave_enter = {"id": "cave_enter", "name": "山洞入口 [洞窟]", "zone": "field_1", "x": 58, "y": 44, "to": "cave_f1"}
    points = [
        cave_enter,
        {"id": "cave_f1", "name": "洞口→野外", "zone": "runan_f1", "x": 64, "y": 3, "to": "cave_enter"},
    ]
    # 樓梯: (層, 下點座標, 下點 id, 落去嗰層到達點座標, 到達點 id)
    stairs = [
        (1, (89, 9), "f1_down",  (64, 15), "f2_up"),
        (2, (89, 21), "f2_down", (64, 27), "f3_up"),
        (3, (89, 33), "f3_down", (64, 39), "f4_up"),
        (4, (89, 45), "f4_down", (64, 51), "f5_up"),
        (5, (89, 57), "f5_down", (97, 3), "f6_up"),
        (6, (121, 9), "f6_down", (97, 15), "f7_up"),
        (7, (121, 21), "f7_down", (97, 27), "f8_up"),
        (8, (121, 33), "f8_down", (97, 39), "f9_up"),
        (9, (121, 45), "f9_down", (97, 51), "f10_up"),
    ]
    for f, (dx, dy), did, (ux, uy), uid in stairs:
        points.append({"id": did, "name": "落%s層" % CAVE_FLOOR_NAMES[f], "zone": "runan_f%d" % f,
                       "x": dx, "y": dy, "to": uid})
        points.append({"id": uid, "name": "上一層", "zone": "runan_f%d" % (f + 1),
                       "x": ux, "y": uy, "to": did})

    # 牆 (sim._build_terrain 讀): 舊兩幅 (練兵場個位係舊 code) + 洞窟外框/夾層
    walls = [
        [10, 20, 29, 20],
        [40, 30, 40, 49],
        # 洞窟密封: 左邊 x61 + 欄間 92~93 + 右邊 124~127 + 頂底橫牆
        [61, 0, 61, 63],
        [92, 0, 93, 63],
        [124, 0, 127, 63],
        [62, 0, 127, 0],
        [62, 11, 127, 11],
        [62, 12, 127, 12],
        [62, 23, 127, 23],
        [62, 24, 127, 24],
        [62, 35, 127, 35],
        [62, 36, 127, 36],
        [62, 47, 127, 47],
        [62, 48, 127, 48],
        [62, 59, 127, 59],
        [62, 60, 127, 63],
    ]
    travel = [
        {"id": "gate_out", "name": "南門 [G]出城", "zone": "town", "x": 24, "y": 24, "to": "gate_in"},
        {"id": "gate_in", "name": "北門 [G]入城", "zone": "field_1", "x": 27, "y": 27, "to": "gate_out"},
    ]
    travel += points
    out = {
        "_note": "安全區(城內)/戰鬥區(野外) 分界 + 傳送點 + 牆。zones 唔重疊；spawns.json 嘅 zone 欄位對應呢度 id。"
                 "Step 11 加汝南洞窟 10 層 (spec 04 §2): 雙欄佈局，樓梯傳送點串連，洞內商店喺 1F (shops.json)。"
                 "【自訂改編】入口暫放許昌城外東邊 (58,44)，新野地圖未開。walls = sim._build_terrain 讀。",
        "zones": zones,
        "walls": walls,
        "travel_points": travel,
    }
    path = os.path.join(DATA, "zones.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("zones.json: %d zones, %d walls, %d travel points" % (len(zones), len(walls), len(travel)))
    return zones, travel


if __name__ == "__main__":
    n, rep = build_monsters()
    build_zones()
    print("imported %d" % n)
    if rep:
        print("VALIDATION FAILED:")
        for r in rep:
            print(" -", r)
        raise SystemExit(1)
    print("ALL OK")