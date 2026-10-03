"""gen_battles.py —— 戰役任務 6 場 (spec 04 §5 / spec 06 §7，【原 sy3_8】) 用原版戰役地圖重做

原版有戰役地圖系列 (xc3251~4 張牛角 / xc1451~4 褚飛燕 / xc2451~5 李大目 / xc1751~5 張白騎 /
xc3051~5 黃龍 / xc1551~5 十常侍)。每層開獨立 instance 地圖 `bt_<戰役>_f<n>` (複製 template txt，
唔同練功洞穴共用)，放喺世界最底，地圖之間 ≥20 格。

由 `data/archive/legacy_battles.json` (攻略 sy3_8 掉寶表) 生成 `data/battles.json`：
  - 張白騎 / 黃龍 攻略 6 層、原版地圖得 5 張 → 攻略第 5+6 層併做原版第 5 層 (尾層 boss = 攻略第 6 層，掉寶兩層合併)
  - 每層 `mobs` = [[怪 id, 數量], ...]，入層先生、離開清走 (battle_mob)；怪用原版近似怪借位 (原版缺嘅冇圖怪用相近怪)
  - boss 怪 (monsters.json 1015~1064) drops 同層掉寶表對齊

用法:
  python tools/gen_battles.py          # 寫 battles.json / maps.json / monsters.json / maps/*.txt / mon_alias.json
  python tools/gen_battles.py --check  # 只核對 / 錯 exit 1
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
D = ROOT / "client/data"
MONSTERS = D / "monsters.json"
MAPS = D / "maps.json"
BATTLES = D / "battles.json"
LEGACY = D / "archive/legacy_battles.json"
ALIAS = D / "mon_alias.json"
ITEMS = D / "items.json"
MAPS_DIR = D / "maps"

BASE_OY = 30000              # instance 地圖由世界 y=30000 起，向下疊
STEP = 113 + 20              # 地圖高 113 + 20 格間隔
GAP_OK = 20

# 戰役 → 原版 template 地圖 (層序)
TPL = {
    "zhangniujiao": ["xc3251", "xc3252", "xc3253", "xc3254"],
    "chufeiyan":    ["xc1451", "xc1452", "xc1453", "xc1454"],
    "lidamu":       ["xc2451", "xc2452", "xc2453", "xc2454", "xc2455"],
    "zhangbaiqi":   ["xc1751", "xc1752", "xc1753", "xc1754", "xc1755"],
    "huanglong":    ["xc3051", "xc3052", "xc3053", "xc3054", "xc3055"],
    "shichangshi":  ["xc1551", "xc1552", "xc1553", "xc1554", "xc1555"],
}
MERGE_LAST = {"zhangbaiqi", "huanglong"}      # 攻略 6 層、原版 5 層 → 第 5+6 層併

# 每層小怪 [[def, 數量], ...] (原版小怪；冇圖/冇資料嘅用近似怪)
MOBS = {
    "zhangniujiao": [[[70000, 4]], [[70000, 3], [70005, 2]], [[70005, 4]], [[70005, 3], [70000, 3]]],
    "chufeiyan":    [[[27045, 5]], [[27045, 3], [70011, 3]], [[27061, 4], [70011, 2]], [[27061, 4], [70011, 3]]],
    "lidamu":       [[[27047, 3], [27050, 1]], [[27046, 4]], [[27048, 4]], [[27049, 4]], [[1030, 3], [27045, 3], [27044, 2]]],
    "zhangbaiqi":   [[[27057, 4]], [[27057, 3], [27061, 3]], [[27061, 4], [27059, 2]], [[27059, 4], [27057, 3]], [[27061, 4], [27059, 3], [27057, 2]]],
    "huanglong":    [[[27076, 2], [27077, 2]], [[27078, 2], [27079, 2]], [[27074, 3], [27072, 3]], [[27080, 3], [27070, 3]], [[27076, 2], [27078, 2], [27080, 2]]],
    "shichangshi":  [[[13026, 5]], [[13026, 4], [27061, 3]], [[27061, 4], [27059, 3]], [[27059, 4], [27061, 4]], [[27061, 5], [27059, 4], [13026, 3]]],
}

# 冇原版 sprite 嘅 boss 借人形 sprite (soldier 池 id) + 染色，asset_lib.mon_sheet 搵唔到先用
ALIAS_ACTORS = {
    1018: (20150, "#ffd0b0"), 1039: (20142, "#ffe0c0"), 1040: (20142, "#ffc0a0"), 1041: (20142, "#ff9070"),
    1042: (20150, "#c0c0ff"), 1043: (20218, "#ffe0a0"), 1047: (20150, "#a0ffa0"), 1052: (20218, "#d0ffd0"),
    1053: (20150, "#e0e0ff"), 1057: (20142, "#c0ffc0"), 1058: (20218, "#ffd0ff"), 1060: (20018, "#d0b0ff"),
    1061: (20018, "#ffb0b0"), 1062: (20018, "#b0ffb0"), 1063: (20018, "#b0b0ff"), 1064: (20018, "#ffd060"),
}


def load_json(p):
    return json.load(open(p, encoding="utf-8"))


def save_json(p, data):
    open(p, "w", encoding="utf-8", newline="\n").write(
        json.dumps(data, ensure_ascii=False, indent=1) + "\n")


def inst_id(bid, i):
    return "bt_%s_f%d" % (bid, i + 1)


def merged_floors(bid, floors):
    fl = [dict(f) for f in floors]
    if bid in MERGE_LAST and len(fl) == len(TPL[bid]) + 1:
        a, b = fl[-2], fl[-1]
        seen = set()
        drops = []
        for d in a["drops"] + b["drops"]:
            if int(d[0]) not in seen:
                seen.add(int(d[0]))
                drops.append([int(d[0]), float(d[1])])
        b["drops"] = drops
        fl = fl[:-2] + [b]
    return fl


def build():
    mj = load_json(MONSTERS)
    ap = load_json(MAPS)
    lg = load_json(LEGACY)
    monsters = {int(m["id"]): m for m in mj["monsters"]}
    maps = [m for m in ap["maps"] if not str(m["id"]).startswith("bt_")]
    by_id = {str(m["id"]): m for m in maps}
    out = {"_note": "戰役任務 (spec 06 §7, spec 04 §5)【原 sy3_8】用原版戰役地圖 (instance)。窗口【自訂】落 game 日曆：96 刻/日，每 16 刻一個窗 (8 刻報名)。由 tools/gen_battles.py 生成。",
           "battles": []}
    n = 0
    for bt in lg["battles"]:
        bid = str(bt["id"])
        floors = merged_floors(bid, bt["floors"])
        tpls = TPL[bid]
        assert len(floors) == len(tpls), bid
        nb = {k: v for k, v in bt.items() if k != "floors"}
        nb["playable"] = True
        nb["floors"] = []
        for i, fl in enumerate(floors):
            mid = inst_id(bid, i)
            tpl = by_id[tpls[i]]
            boss = monsters[int(fl["monster"])]
            boss["drops"] = [{"item": int(d[0]), "p": float(d[1])} for d in fl["drops"]]
            boss["_battle"] = bid
            boss["_floor"] = i
            oy = BASE_OY + n * STEP
            maps.append({"id": mid, "name": "%s %dF" % (str(bt["name"]), i + 1), "ox": 0, "oy": oy,
                         "safe": False, "kind": "field", "orig": tpls[i], "instance": True,
                         "spawn": list(tpl.get("spawn", [75, 56, 75, 56]))})
            (MAPS_DIR / (mid + ".txt")).write_text((MAPS_DIR / (tpls[i] + ".txt")).read_text(encoding="utf-8"), encoding="utf-8")
            n += 1
            nf = {"boss": fl["boss"], "monster": int(fl["monster"]), "map": mid, "tpl": tpls[i],
                  "drops": fl["drops"], "mobs": MOBS[bid][i]}
            if i == len(floors) - 1:
                nf["final"] = True
            nb["floors"].append(nf)
        out["battles"].append(nb)
    # 唔再用嘅合併前 boss (1052/1058) 去掉 _battle 標記，免俾測試當戰役 boss
    used = {int(f["monster"]) for b in out["battles"] for f in b["floors"]}
    for m in monsters.values():
        if "_battle" in m and int(m["id"]) not in used:
            del m["_battle"]
            m.pop("_floor", None)
    ap["maps"] = maps
    save_json(MONSTERS, mj)
    save_json(MAPS, ap)
    save_json(BATTLES, out)
    al = load_json(ALIAS)
    for mid, (act, tint) in ALIAS_ACTORS.items():
        al["alias"].setdefault(str(mid), {"actor": act, "tint": tint})
    save_json(ALIAS, al)
    return n


def check():
    mj = load_json(MONSTERS)
    ap = load_json(MAPS)
    bj = load_json(BATTLES)
    items = load_json(ITEMS)
    item_ids = {int(i["id"]) for i in (items if isinstance(items, list) else items.get("items", []))}
    monsters = {int(m["id"]): m for m in mj["monsters"]}
    maps = {m["id"]: m for m in ap["maps"]}
    errs = []
    ys = []
    for bt in bj["battles"]:
        bid = str(bt["id"])
        if not bt.get("playable"):
            errs.append("%s 未 playable" % bid)
        if len(bt["floors"]) != len(TPL.get(bid, [])):
            errs.append("%s 層數唔對原版 template" % bid)
        for i, fl in enumerate(bt["floors"]):
            tag = "%s 層%d" % (bid, i + 1)
            m = monsters.get(int(fl["monster"]))
            if m is None:
                errs.append("%s boss 唔存在" % tag)
                continue
            if sorted(int(d[0]) for d in fl["drops"]) != sorted(int(d["item"]) for d in m["drops"]):
                errs.append("%s drops 唔對齊 boss %d" % (tag, fl["monster"]))
            for d in fl["drops"]:
                if item_ids and int(d[0]) not in item_ids:
                    errs.append("%s 掉落 item %d 唔喺 items.json" % (tag, int(d[0])))
            mp = maps.get(str(fl["map"]))
            if mp is None:
                errs.append("%s map 唔存在" % tag)
            else:
                if mp.get("orig") != fl.get("tpl"):
                    errs.append("%s map orig 唔係 template" % tag)
                if not (MAPS_DIR / (str(fl["map"]) + ".txt")).exists():
                    errs.append("%s map txt 冇" % tag)
                ys.append(int(mp["oy"]))
            for d, c in fl.get("mobs", []):
                if int(d) not in monsters:
                    errs.append("%s 小怪 %d 唔存在" % (tag, d))
    ys.sort()
    for a, b in zip(ys, ys[1:]):
        if b - a < 113 + GAP_OK:
            errs.append("instance 地圖間隔 <20: y %d/%d" % (a, b))
    for mid, (act, _t) in ALIAS_ACTORS.items():
        if str(mid) not in load_json(ALIAS)["alias"] and str(mid) not in load_json(D / "asset_index.json").get("mon_S", {}):
            errs.append("boss %d 冇 sprite / alias" % mid)
    if errs:
        print("[battles] --check 錯:")
        for e in errs:
            print("  -", e)
        return 1
    print("[battles] --check OK (%d 場戰役、%d 層 instance 地圖，boss/drops/小怪/sprite 齊)" % (len(bj["battles"]), len(ys)))
    return 0


def main():
    if "--check" in sys.argv:
        sys.exit(check())
    n = build()
    print("[battles] 生成 %d 層戰役 instance 地圖" % n)


if __name__ == "__main__":
    main()
