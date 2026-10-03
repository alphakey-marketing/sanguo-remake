"""gen_scenes.py —— 特殊場景 (spec 04 §4【原 sy3_10_*】) 用原版模板圖重做

場景每層開獨立 instance 地圖 `sc_<場景>_f<n>` (複製原版 template txt；template 由
tools/import_orig_scene_maps.py 匯入)，擺喺世界 y>=33750 (WORLD_H 34000 以內)，跟 gen_battles。
  - 通天關 xc5061~5068 (8 擂台，每擂台 3 魔神，打晒三隻過下擂台；夢幻收集品必掉)
  - 異族禁地 xc5283~5289 (7 關，每關 1 魔王；血量按單機化縮)
  - 七彩奪寶陣 xc5255~5261 (晶孟獲 7 層，用原本 1080~1086)
  桃花渡 / 黑山寨 / 安定戰場 / 雪山 找唔到原版 template → 暫留 archive/legacy_scenes.json，唔入場景表。
`data/scenes.json` 由呢度生成；怪物分發落 monsters.json (新怪 id 1200+，加 `_scene` 標記；已存在嘅七彩怪唔郁)。

用法:
  python tools/gen_scenes.py          # 生成 (idempotent)
  python tools/gen_scenes.py --check  # 核對，錯 exit 1
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
D = ROOT / "client/data"
SCENES = D / "scenes.json"
MONSTERS = D / "monsters.json"
MAPS = D / "maps.json"
MAPS_DIR = D / "maps"
LEGACY = D / "archive/legacy_scenes.json"
ALIAS = D / "mon_alias.json"

BASE_OY = 33750
COLW, ROWH, PERROW = 64, 67, 8

TT_NAMES = ["劉備", "呂布", "蓋普洛", "董卓", "關羽", "風魔", "火魔", "水魔", "地魔", "心魔", "地煞", "天煞",
            "火云邪神", "水云邪神", "風云邪神", "地云邪神", "無云邪神", "弓奴", "玄德公", "玉皇", "豆腐屍", "阿煞力", "血魄", "闇之神"]
YZ = [  # 名, 血(單機化縮)，掉寶
    ("羌奴勇士", 70000, [65029, 32225, 28067]), ("羌奴戰士", 80000, [65055, 65082, 28065]),
    ("烏丸戰士", 85000, [63018, 65084]), ("烏丸勇士", 110000, [65083, 63019]),
    ("南蠻勇士", 130000, [65049, 65144, 32204]), ("南蠻法師", 140000, [65008, 28066, 63018]),
    ("孟獲", 170000, [32053, 65145, 65030, 65016]),
]
ALIAS_ACTORS = [(20018, "#ffd060"), (20142, "#ff9070"), (20150, "#c0c0ff"), (20218, "#d0ffd0")]


def load_json(p):
    return json.load(open(p, encoding="utf-8"))


def save_json(p, data):
    open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(data, ensure_ascii=False, indent=1) + "\n")


def mk_mon(mid, name, lv, hp, drops, boss):
    return {"id": mid, "name": name, "level": lv, "hp": hp, "atk": int(lv * 3.6), "def": int(lv * 0.6),
            "spellDef": int(lv * 0.7), "atkInterval": 12, "moveSpeed": 2, "exp": lv * 450, "gold": [lv * 8, lv * 16],
            "alignment": -900, "aggroRange": 10, "leash": 18, "element": "none", "boss": boss,
            "drops": [[d, p] for d, p in drops]}


def build_defs():
    """回傳 (scenes 列表, tpl 對照 {sid: [xc...]})"""
    tpl = {"tongtian": ["xc%d" % i for i in range(5061, 5069)],
           "yizu": ["xc%d" % i for i in range(5283, 5290)],
           "qicai": ["xc5260", "xc5258", "xc5255", "xc5259", "xc5256", "xc5261", "xc5257"]}
    lg = {s["id"]: s for s in load_json(LEGACY)["scenes"]}
    # 通天關: 24 魔神 id 1200~1223；每擂台 3 隻，第 3 隻 = 擂主 (boss)
    tm, tl = [], []
    for i, nm in enumerate(TT_NAMES):
        lay = i // 3
        boss = i % 3 == 2
        hp = 40000 + lay * 12000
        tm.append(mk_mon(1200 + i, nm, 100 + lay, int(hp * (1.5 if boss else 1)), [(53008, 1.0)], boss))
    for lay in range(8):
        tl.append({"monsters": [1200 + lay * 3 + k for k in range(3)], "density": 1, "map": "sc_tongtian_f%d" % (lay + 1)})
    ym, yl = [], []
    for i, (nm, hp, dr) in enumerate(YZ):
        ym.append(mk_mon(1224 + i, nm, 80 + i * 2, hp, [(d, 0.7) for d in dr], True))
        yl.append({"monsters": [1224 + i], "density": 1, "map": "sc_yizu_f%d" % (i + 1)})
    q = dict(lg["qicai"])
    q["layers"] = [{"monsters": l["monsters"], "density": 1, "map": "sc_qicai_f%d" % (i + 1)} for i, l in enumerate(lg["qicai"]["layers"])]
    sched = {"days": [1, 2, 3, 15, 16, 17]}
    scenes = [
        {"id": "tongtian", "name": "通天關", "minLevel": 71, "entryMap": "xc2125", "entryX": 185, "entryY": 51,
         "schedule": sched, "droplore": "8 擂台 24 魔神【原 sy3_10_4】: 守關魔神必掉夢幻收集品 (換夢幻裝備)；原版 24 魔神能力不詳，數值【自訂】。單機化: 擂台改按序闖，每擂台打晒 3 魔神過下一擂。",
         "monsters": tm, "layers": tl},
        {"id": "yizu", "name": "異族禁地", "minLevel": 70, "entryMap": "xc2125", "entryX": 191, "entryY": 53,
         "schedule": {"days": [1, 8, 15, 22]}, "droplore": "7 關魔王【原 sy3_10_7】: 羌奴/烏丸/南蠻 + 孟獲殿；原版血量 70萬~500萬×回血，單機化縮細【自訂】。",
         "monsters": ym, "layers": yl},
        q,
    ]
    return scenes, tpl


def spawn_of(txt):
    rows = [r for r in txt.split("\n") if r]
    h, w = len(rows), len(rows[0])
    best = None
    for y in range(h - 1, 0, -1):
        for x in range(w):
            if rows[y][x] == "." and (best is None or abs(x - w // 2) + abs(y - (h - 5)) < best[0]):
                best = (abs(x - w // 2) + abs(y - (h - 5)), x, y)
    return [best[1], best[2], best[1], best[2]]


def build():
    scenes, tpl = build_defs()
    mj = load_json(MONSTERS)
    ap = load_json(MAPS)
    al = load_json(ALIAS)
    by_id = {int(m["id"]): m for m in mj["monsters"]}
    for sc in scenes:
        for md in sc["monsters"]:
            mid = int(md["id"])
            if mid in by_id and by_id[mid].get("_scene") == sc["id"]:
                continue                      # 已有 (七彩，數值已校) 唔郁
            e = {k: v for k, v in md.items() if k != "drops"}
            e["drops"] = [{"item": int(d[0]), "p": float(d[1])} for d in md.get("drops", [])]
            e["_scene"] = sc["id"]
            mj["monsters"] = [m for m in mj["monsters"] if int(m["id"]) != mid] + [e]
            by_id[mid] = e
            if mid >= 1200:
                act, tint = ALIAS_ACTORS[mid % len(ALIAS_ACTORS)]
                al["alias"].setdefault(str(mid), {"actor": act, "tint": tint})
    maps = [m for m in ap["maps"] if not str(m["id"]).startswith("sc_")]
    n = 0
    for sc in scenes:
        for i, layer in enumerate(sc["layers"]):
            t = tpl[sc["id"]][i]
            txt = (MAPS_DIR / (t + ".txt")).read_text(encoding="utf-8")
            mid = layer["map"]
            maps.append({"id": mid, "name": "%s %dF" % (sc["name"], i + 1), "ox": (n % PERROW) * COLW,
                         "oy": BASE_OY + (n // PERROW) * ROWH, "safe": False, "kind": "field", "orig": t,
                         "instance": True, "spawn": spawn_of(txt)})
            (MAPS_DIR / (mid + ".txt")).write_text(txt, encoding="utf-8")
            n += 1
    ap["maps"] = maps
    save_json(MONSTERS, mj)
    save_json(MAPS, ap)
    save_json(ALIAS, al)
    lg = load_json(LEGACY)
    save_json(SCENES, {"_note": "特殊場景 (spec 04 §4)【原 sy3_10_*】，由 tools/gen_scenes.py 生成 (原版模板圖 instance)。" + lg["_note"][-200:],
                       "scenes": scenes})
    return n


def check():
    sj = load_json(SCENES)
    mj = load_json(MONSTERS)
    ap = load_json(MAPS)
    by_id = {int(m["id"]): m for m in mj["monsters"]}
    maps = {m["id"]: m for m in ap["maps"]}
    errs = []
    nl = 0
    for sc in sj["scenes"]:
        sid = sc["id"]
        for md in sc["monsters"]:
            m = by_id.get(int(md["id"]))
            if m is None or m.get("_scene") != sid:
                errs.append("%s 怪 %d 未分發" % (sid, md["id"]))
        for i, l in enumerate(sc["layers"]):
            nl += 1
            mp = maps.get(l["map"])
            if mp is None:
                errs.append("%s 層地圖 %s 唔存在" % (sid, l["map"]))
                continue
            if not (MAPS_DIR / (l["map"] + ".txt")).exists():
                errs.append("%s txt 冇" % l["map"])
            if not (D / "orig_maps" / (mp["orig"] + ".json")).exists():
                errs.append("%s 原版 template %s 冇匯入" % (l["map"], mp["orig"]))
            if not any(int(x) in by_id and by_id[int(x)].get("boss") for x in l["monsters"]):
                errs.append("%s 層%d 冇 boss" % (sid, i + 1))
    if errs:
        print("[scenes] --check 錯:")
        for e in errs:
            print("  -", e)
        return 1
    print("[scenes] --check OK (%d 場景、%d 層 instance 地圖)" % (len(sj["scenes"]), nl))
    return 0


if __name__ == "__main__":
    if "--check" in sys.argv:
        sys.exit(check())
    print("[scenes] 生成 %d 層 instance 地圖" % build())
