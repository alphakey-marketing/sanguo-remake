"""gen_battles.py —— S04c 其餘 5 場戰役實裝資料生成 (spec 04 §5 / spec 06 §7，【原 sy3_8】)

將 `data/battles.json` 其餘 5 場 (褚飛燕/李大目/張白騎/黃龍/十常侍) 由「資料殼 (playable=false，層得 drops)」補齊：
每層配 `monster` (boss id) + `map` (戰役地圖 id)，每場 `playable:true`；同步：
  - `data/monsters.json` 加每層 boss 怪物 (數值【自訂】按 lv template 遞增，drops = 層掉寶表 p=1.0 全部落，尾層大頭目加 skills)
  - `data/maps.json` + `data/maps/<bid>_f<n>.txt` 加每層戰役地圖 (16x16 arena，全自動打包揾 free 位，
    地圖之間 ≥20 格分隔 (run_maps t_gaps grow(10) 唔相撞)，WORLD 512 內唔重疊)
張牛角 (zhangniujiao) 已實作，唔郁。全部【自訂】boss 冇 npc_drops.csv 對應 → import_drops 唔會覆寫。

用法:
  python tools/gen_battles.py          # 寫返三個 data 檔 + 地圖 txt
  python tools/gen_battles.py --check  # 只核對 (data 一致) / 錯 exit 1
"""
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MONSTERS = ROOT / "client/data/monsters.json"
MAPS = ROOT / "client/data/maps.json"
BATTLES = ROOT / "client/data/battles.json"
MAPS_DIR = ROOT / "client/data/maps"

NEW_ID_START = 1039          # 張牛角 1015~1018 之後開始編
WORLD = 512
GAP = 20                     # 地圖之間最少隔 20 格 (run_maps t_gaps: grow(10) 唔相撞)
MAP_W = 16
MAP_H = 16
FINAL_SKILLS = {             # 尾層大頭目加 boss 技能表 (S04b 延續)，reuse 術書 spell id
    "chufeiyan":   [{"spell": "yun_m", "cd": 360}],
    "lidamu":      [{"spell": "shui_m", "cd": 360}],
    "zhangbaiqi":  [{"spell": "feng_m", "cd": 360}],
    "huanglong":   [{"spell": "huo_m", "cd": 360}],
    "shichangshi": [{"spell": "feng_l", "cd": 420}, {"spell": "shui_l", "cd": 420}],
}
# 每場各層 boss 等級 (尾層 = maxLevel；前面層喺之下遞增)【自訂】
FLOOR_LEVELS = {
    "chufeiyan":   [24, 27, 29, 30],
    "lidamu":      [33, 35, 37, 39, 40],
    "zhangbaiqi":  [42, 44, 46, 48, 49, 50],
    "huanglong":   [52, 54, 56, 58, 59, 60],
    "shichangshi": [62, 64, 66, 68, 70],
}


def boss_stats(lv):
    # 數值【自訂】按 lynl template (spec 04 §1) 隨 lv 遞增，但 boss 較強 (「練功打寶戰役」頭目)
    return {
        "level": lv,
        "hp": int(6.5 * lv * lv + 400),
        "atk": int(3.2 * lv + 2),
        "def": int(lv * 0.9 + 2),
        "spellDef": int(lv * 0.9 + 2) + 10,
        "atkInterval": 13,
        "moveSpeed": 1,
        "exp": int(95 * lv),
        "gold": [lv * 3, lv * 7],
        "alignment": -800,
        "aggroRange": 8,
        "leash": 16,
        "element": "none",
        "boss": True,
    }


def gen_map_txt(seed):
    rnd = random.Random(seed)
    g = [["^"] * MAP_W for _ in range(MAP_H)]
    for y in range(1, MAP_H - 1):
        for x in range(1, MAP_W - 1):
            g[y][x] = "_"
    rocks = 0
    while rocks < 8:
        x = rnd.randrange(1, MAP_W - 1)
        y = rnd.randrange(1, MAP_H - 1)
        if g[y][x] == "_":
            g[y][x] = "^"
            rocks += 1
    return "\n".join("".join(row) for row in g) + "\n"


def load_json(p):
    return json.load(open(p, encoding="utf-8"))


def save_json(p, data):
    open(p, "w", encoding="utf-8", newline="\n").write(
        json.dumps(data, ensure_ascii=False, indent=1) + "\n")


# 自動打包 16x16 地圖位：喺 WORLD 512 入面揾 26 個 grow(GAP/2)=唔相撞 嘅格 (決定性 row-major)
def pack_maps(existing_ids, existing_pos):
    occ = [[0] * WORLD for _ in range(WORLD)]
    for (ox, oy, w, h) in existing_pos:
        p = GAP // 2
        for yy in range(max(0, oy - p), min(WORLD, oy + h + p)):
            for xx in range(max(0, ox - p), min(WORLD, ox + w + p)):
                occ[yy][xx] = 1
    out = {}
    p = GAP // 2
    step = 2
    for oy in range(0, WORLD - MAP_H, step):
        for ox in range(0, WORLD - MAP_W, step):
            if len(out) >= len(existing_ids):
                return out
            ok = True
            for yy in range(oy - p, oy + MAP_H + p):
                if not ok:
                    break
                XXmin = max(0, ox - p); XXmax = min(WORLD, ox + MAP_W + p)
                for xx in range(XXmin, XXmax):
                    if occ[yy][xx]:
                        ok = False
                        break
            if ok:
                out[existing_ids[len(out)]] = (ox, oy)
                for yy in range(oy - p, oy + MAP_H + p):
                    for xx in range(max(0, ox - p), min(WORLD, ox + MAP_W + p)):
                        occ[yy][xx] = 1
    raise RuntimeError("WORLD 512 揾唔到 %d 個唔相撞嘅 16x16 地圖位" % len(existing_ids))


def build():
    mj = load_json(MONSTERS)
    ap = load_json(MAPS)
    bj = load_json(BATTLES)

    monsters = mj["monsters"]
    maps = ap["maps"]
    existing_ids = {int(m["id"]) for m in monsters}
    next_id = max([i for i in existing_ids if i < NEW_ID_START] + [NEW_ID_START - 1]) + 1

    by_tag = {}
    for m in monsters:
        if "_battle" in m:
            by_tag[(str(m["_battle"]), int(m.get("_floor", 0)))] = m

    map_ids = {m["id"] for m in maps}
    # 新 map 要嘅位：僅計未存在嘅
    new_mids = []
    for bt in bj["battles"]:
        bid = str(bt["id"])
        if bid == "zhangniujiao":
            continue
        for i in range(len(bt["floors"])):
            mid = "%s_f%d" % (bid, i + 1)
            if mid not in map_ids:
                new_mids.append(mid)
    # 已存在地圖 (純尺寸，唔含 instance 標記——按 id 揾 txt 睇 w/h)
    existing_geom = []
    for m in maps:
        f = MAPS_DIR / (str(m["id"]) + ".txt")
        if not f.exists():
            continue
        rows = [r for r in f.read_text(encoding="utf-8").split("\n") if r.strip() != ""]
        existing_geom.append((int(m["ox"]), int(m["oy"]), max(len(r) for r in rows), len(rows)))
    placements = pack_maps(new_mids, existing_geom) if new_mids else {}

    for bt in bj["battles"]:
        bid = str(bt["id"])
        if bid == "zhangniujiao":
            continue
        floors = bt["floors"]
        lvs = FLOOR_LEVELS[bid]
        is_final = len(floors) - 1
        for i, fl in enumerate(floors):
            tag = by_tag.get((bid, i))
            boss_name = str(fl["boss"])
            # ---- monster ----
            if tag is None:
                st = boss_stats(lvs[i])
                mob = {
                    "id": next_id, "name": boss_name, **st,
                    "drops": [{"item": int(d[0]), "p": float(d[1])} for d in fl["drops"]],
                    "_battle": bid, "_floor": i,
                }
                if i == is_final and bid in FINAL_SKILLS:
                    mob["skills"] = FINAL_SKILLS[bid]
                monsters.append(mob)
                next_id += 1
                tag = mob
            else:
                tag["name"] = boss_name
                tag["drops"] = [{"item": int(d[0]), "p": float(d[1])} for d in fl["drops"]]
                if i == is_final and bid in FINAL_SKILLS:
                    tag["skills"] = FINAL_SKILLS[bid]
                elif "skills" in tag:
                    del tag["skills"]
            # ---- map ----
            mid = "%s_f%d" % (bid, i + 1)
            if mid not in map_ids:
                ox, oy = placements[mid]
                maps.append({
                    "id": mid, "name": "%s %dF" % (str(bt["name"]), i + 1),
                    "ox": ox, "oy": oy, "safe": False, "kind": "field",
                    "instance": True,
                })
                map_ids.add(mid)
            # ---- battle floor ----
            fl["monster"] = int(tag["id"])
            fl["map"] = mid
        bt["playable"] = True

    txt_seed = 0
    for bt in bj["battles"]:
        bid = str(bt["id"])
        if bid == "zhangniujiao":
            continue
        for fl in bt["floors"]:
            mid = str(fl["map"])
            (MAPS_DIR / (mid + ".txt")).write_text(gen_map_txt(txt_seed), encoding="utf-8")
            txt_seed += 1

    save_json(MONSTERS, mj)
    save_json(MAPS, ap)
    save_json(BATTLES, bj)
    return txt_seed


def check():
    mj = load_json(MONSTERS)
    ap = load_json(MAPS)
    bj = load_json(BATTLES)
    monsters = {int(m["id"]): m for m in mj["monsters"]}
    map_ids = {m["id"] for m in ap["maps"]}
    respect = 0
    errs = []
    for bt in bj["battles"]:
        bid = str(bt["id"])
        if bid == "zhangniujiao":
            continue
        respect += 1
        if not bool(bt.get("playable")):
            errs.append("%s 未 playable" % bid)
        for i, fl in enumerate(bt["floors"]):
            if "monster" not in fl or "map" not in fl:
                errs.append("%s 層 %d 冇 monster/map" % (bid, i + 1))
                continue
            mid = int(fl["monster"])
            if mid not in monsters:
                errs.append("%s 層 %d monster %d 唔存在" % (bid, i + 1, mid))
                continue
            m = monsters[mid]
            want = sorted((int(d[0]) for d in fl["drops"]))
            got = sorted(int(d["item"]) for d in m["drops"])
            if want != got:
                errs.append("%s 層 %d drops 唔對齊怪物 %d" % (bid, i + 1, mid))
            if str(fl["map"]) not in map_ids:
                errs.append("%s 層 %d map 唔存在" % (bid, i + 1))
    for mid in map_ids:
        p = MAPS_DIR / (mid + ".txt")
        if not p.exists():
            errs.append("map txt 唔存在: " + mid)
    if errs:
        print("[battles] --check 錯:")
        for e in errs:
            print("  -", e)
        return 1
    print("[battles] --check OK (%d 場非張牛角戰役全部 playable + monster/map/drops 齊)" % respect)
    return 0


def main():
    if "--check" in sys.argv:
        sys.exit(check())
    n = build()
    print("[battles] 生成/確定 %d 層戰役 (5 場非張牛角全部 playable + monster/map/drops 齊)" % n)


if __name__ == "__main__":
    main()