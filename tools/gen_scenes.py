"""gen_scenes.py —— S04d 特殊場景首批資料分發 (spec 04 §4【原 sy3_10_1/6】)

`client/data/scenes.json` = 權威來源（攻略掉寶全表 + 怪物 def + 層地圖 + 入口）。呢個導入器做三件事：
  1) 將 scenes.json 每隻怪物 (id/name/stats/drops/skills) 分發落 `data/monsters.json`
     （加 `_scene:<sceneId>` 標記；帶 drops [] 唔受 import_drops 覆寫）
  2) 為每層 map id 建立 16x16 地圖 txt + `data/maps.json` 條目（自動打包 WORLD 512 揾空位，跟 gen_battles）
  3) --check 純核對（怪物/drops/地圖是否齊全一致）

用法:
  python tools/gen_scenes.py          # 分發 (idempotent)
  python tools/gen_scenes.py --check  # 核對，錯 exit 1
"""
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCENES = ROOT / "client/data/scenes.json"
MONSTERS = ROOT / "client/data/monsters.json"
MAPS = ROOT / "client/data/maps.json"
MAPS_DIR = ROOT / "client/data/maps"

WORLD = 512
GAP = 20
MAP_W = 16
MAP_H = 16


def gen_map_txt(seed):
    rnd = random.Random(seed)
    g = [["^"] * MAP_W for _ in range(MAP_H)]
    for y in range(1, MAP_H - 1):
        for x in range(1, MAP_W - 1):
            g[y][x] = "_"
    rocks = 0
    while rocks < 5:
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


def pack_maps(new_ids, existing_pos):
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
            if len(out) >= len(new_ids):
                return out
            ok = True
            for yy in range(oy - p, oy + MAP_H + p):
                if not ok:
                    break
                for xx in range(max(0, ox - p), min(WORLD, ox + MAP_W + p)):
                    if occ[yy][xx]:
                        ok = False
                        break
            if ok:
                out[new_ids[len(out)]] = (ox, oy)
                for yy in range(oy - p, oy + MAP_H + p):
                    for xx in range(max(0, ox - p), min(WORLD, ox + MAP_W + p)):
                        occ[yy][xx] = 1
    raise RuntimeError("WORLD 512 揾唔到 %d 個唔相撞嘅 16x16 地圖位" % len(new_ids))


def build():
    sj = load_json(SCENES)
    mj = load_json(MONSTERS)
    ap = load_json(MAPS)

    monsters = mj["monsters"]
    maps = ap["maps"]
    by_id = {int(m["id"]): m for m in monsters}
    map_ids = {m["id"] for m in maps}

    # 怪物分發 (idempotent: 已存在同 id 就更新 _scene 標記，除非係嚟自第個來源)
    for sc in sj["scenes"]:
        sid = str(sc["id"])
        for md in sc.get("monsters", []):
            mid = int(md["id"])
            drops = [{"item": int(d[0]), "p": float(d[1])} for d in md.get("drops", [])]
            entry = {k: v for k, v in md.items() if k not in ("drops", "_scene")}
            if mid in by_id:
                cur = by_id[mid]
                if cur.get("_scene", "") == sid:
                    cur.update(entry)
                    cur["drops"] = drops
                    continue
                # 撞 id 冚咗第個來源: 唔覆寫，由 check 報錯
                continue
            entry["drops"] = drops
            entry["_scene"] = sid
            monsters.append(entry)
            by_id[mid] = entry

    # 地圖分發 (揾未存在嘅層地圖)
    new_mids = []
    for sc in sj["scenes"]:
        sid = str(sc["id"])
        for li, layer in enumerate(sc.get("layers", [])):
            mid = str(layer["map"])
            if mid not in map_ids:
                new_mids.append(mid)
    existing_geom = []
    for m in maps:
        f = MAPS_DIR / (str(m["id"]) + ".txt")
        if not f.exists():
            continue
        rows = [r for r in f.read_text(encoding="utf-8").split("\n") if r.strip() != ""]
        existing_geom.append((int(m["ox"]), int(m["oy"]), max(len(r) for r in rows), len(rows)))
    placements = pack_maps(new_mids, existing_geom) if new_mids else {}
    for mid in new_mids:
        ox, oy = placements[mid]
        lid = mid.split("_f")[0]
        scn = next((s for s in sj["scenes"] if s["id"] == lid), {})
        maps.append({"id": mid, "name": "%s %s" % (str(scn.get("name", lid)), mid.split("_f")[-1] + "F"),
                     "ox": ox, "oy": oy, "safe": False, "kind": "cave", "instance": True})
        map_ids.add(mid)
        (MAPS_DIR / (mid + ".txt")).write_text(gen_map_txt(hash(mid) & 0x7FFFFFFF), encoding="utf-8")

    save_json(MONSTERS, mj)
    save_json(MAPS, ap)
    return len(sj["scenes"])


def check():
    sj = load_json(SCENES)
    mj = load_json(MONSTERS)
    ap = load_json(MAPS)
    by_id = {int(m["id"]): m for m in mj["monsters"]}
    map_ids = {m["id"] for m in ap["maps"]}
    errs = []
    for sc in sj["scenes"]:
        sid = str(sc["id"])
        for md in sc.get("monsters", []):
            mid = int(md["id"])
            if mid not in by_id or by_id[mid].get("_scene", "") != sid:
                errs.append("%s 怪物 %d 未分發/_scene 唔啱" % (sid, mid))
                continue
            want = sorted((int(d[0]) for d in md.get("drops", [])))
            got = sorted(int(d["item"]) for d in by_id[mid].get("drops", []))
            if want != got:
                errs.append("%s 怪物 %d drops 唔對齊" % (sid, mid))
        for layer in sc.get("layers", []):
            if str(layer["map"]) not in map_ids:
                errs.append("%s 層地圖 %s 唔存在" % (sid, str(layer["map"])))
            for md in layer.get("monsters", []):
                if int(md) not in by_id:
                    errs.append("%s 層怪物 %d 唔存在" % (sid, int(md)))
    for mid in map_ids:
        p = MAPS_DIR / (mid + ".txt")
        if not p.exists():
            errs.append("map txt 唔存在: " + mid)
    if errs:
        print("[scenes] --check 錯:")
        for e in errs:
            print("  -", e)
        return 1
    print("[scenes] --check OK (%d 場景怪物/層地圖/drops 全部分發齊)" % len(sj["scenes"]))
    return 0


def main():
    if "--check" in sys.argv:
        sys.exit(check())
    n = build()
    print("[scenes] 分發 %d 場景資料 (怪物 -> monsters.json, 層地圖 -> maps.json/txt)" % n)


if __name__ == "__main__":
    main()