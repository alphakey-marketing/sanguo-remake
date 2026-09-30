"""npc_drops.csv -> client/data/monsters.json 掉落導入 (spec 04 §1, spec 11 §2)

規則:
- 來源 npc = 怪嘅 `dropSrc` 欄，冇就用自己 `id`；CSV 冇呢個 id = 【自訂】手寫掉落，唔郁
- p = rate / 100000 (原值，唔夾 min)；CSV 原次序；同一 item 重複出現 = 各自獨立擲骰 (照原表)
- p >= 0.05 入 drops，其餘入 rareDrops
- 全部掉落 item id 要喺 items.json，否則報錯

用法:
  python tools/import_drops.py          # 寫返 monsters.json
  python tools/import_drops.py --check  # 只核對，有差異 / 錯 exit 1
  --csv <path>  另指 CSV (預設 D:/Download/sanguo/extracted/text/npc_drops.csv)
"""
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MONSTERS = ROOT / "client/data/monsters.json"
ITEMS = ROOT / "client/data/items.json"
DEFAULT_CSV = Path("D:/Download/sanguo/extracted/text/npc_drops.csv")
RATE_BASE = 100000
RARE_BELOW = 0.05
DROP_RX = re.compile(r"\((\d+)\)@(\d+)")


def load_csv(path: Path) -> dict:
    rows = {}
    with open(path, encoding="utf-8-sig", newline="") as f:
        for r in csv.reader(f):
            if not r or not r[0].isdigit():
                continue   # 表頭
            raw = r[4] if len(r) > 4 else ""
            rows[int(r[0])] = {
                "name": r[1],
                "drops": [(int(i), int(rate) / RATE_BASE) for i, rate in DROP_RX.findall(raw)],
            }
    return rows


def split(pairs: list) -> tuple:
    common = [{"item": i, "p": p} for i, p in pairs if p >= RARE_BELOW]
    rare = [{"item": i, "p": p} for i, p in pairs if p < RARE_BELOW]
    return common, rare


def with_drops(m: dict, common: list, rare: list) -> dict:
    # 保持欄位次序: drops / rareDrops 放返原位 (冇就放尾)
    out = {}
    for k, v in m.items():
        if k == "rareDrops":
            continue
        out[k] = v
        if k == "drops":
            out["drops"] = common
            out["rareDrops"] = rare
    if "drops" not in out:
        out["drops"] = common
        out["rareDrops"] = rare
    return out


SUPP_CATS = (39, 45, 47)          # 寶石 / 技能書 / 能力石
SUPP_PER_ITEM = 2                 # 每件補到幾多隻怪
SUPP_P = {39: 0.002, 45: 0.003, 47: 0.003}
SUPP_SRC_FILES = ["quests.json", "shops.json", "mall.json", "master_recipes.json", "commissions.json", "donation.json",
                  "camp.json", "office.json", "titles.json", "work.json", "mount_weapons.json"]


def supp_plan(monsters: list, items: list, recipes: list) -> dict:
    """補「完全冇來源」嘅寶石/技能書/能力石 → 按等級帶掛落現有怪 rareDrops (spec: docs/uat/data_audit.md D)。
    決定性：等級估計 = req_lv (>0) 否則同 cat 內按 (價, id) 排名線性映射 1~90；揀等級最近 6 隻入面「已分配最少」嘅 2 隻。
    回傳 {monster_id: [item_id...]}"""
    data_dir = ROOT / "client/data"
    txt = "".join((data_dir / f).read_text(encoding="utf-8") for f in SUPP_SRC_FILES)
    base = set()
    for m in monsters:
        supp = set(m.get("suppDrops", []))
        base |= {int(x["item"]) for x in m.get("drops", []) + m.get("rareDrops", []) if int(x["item"]) not in supp}
    base |= {int(r["id"]) for r in recipes}
    pool = []
    for cat in SUPP_CATS:
        xs = [i for i in items if i["cat"] == cat and not re.match(r"書\d+$", i["name"])
              and int(i["id"]) not in base and not re.search(r"%d" % int(i["id"]), txt)]
        xs.sort(key=lambda i: (i["price"], i["id"]))
        for r, i in enumerate(xs):
            est = i["req_lv"] if i["req_lv"] > 0 else 1 + 89 * r / max(1, len(xs) - 1)
            pool.append((est, int(i["id"]), cat))
    pool.sort()
    load = {int(m["id"]): 0 for m in monsters}
    order = sorted(monsters, key=lambda m: (m["level"], m["id"]))
    plan = {}
    for est, iid, cat in pool:
        near = sorted(order, key=lambda m: (abs(m["level"] - est), m["id"]))[:6]
        for m in sorted(near, key=lambda m: (load[int(m["id"])], m["id"]))[:SUPP_PER_ITEM]:
            load[int(m["id"])] += 1
            plan.setdefault(int(m["id"]), []).append((iid, cat))
    return plan


def main() -> int:
    args = sys.argv[1:]
    check = "--check" in args
    csv_path = Path(args[args.index("--csv") + 1]) if "--csv" in args else DEFAULT_CSV
    if not csv_path.exists():
        print(f"[ERR] 搵唔到 CSV: {csv_path}")
        return 1
    rows = load_csv(csv_path)
    item_ids = {int(x["id"]) for x in json.loads(ITEMS.read_text(encoding="utf-8"))}
    text = MONSTERS.read_text(encoding="utf-8")
    data = json.loads(text)

    errors, diffs, custom, imported = [], [], [], 0
    new_monsters = []
    recipes = json.loads((ROOT / "client/data/recipes.json").read_text(encoding="utf-8"))["recipes"]
    plan = supp_plan(data["monsters"], json.loads(ITEMS.read_text(encoding="utf-8")), recipes)
    supp_n = 0
    for m in data["monsters"]:
        orig = m
        # 補充掉落: 先清舊 suppDrops，再按 plan 加返 (idempotent)
        old = set(m.get("suppDrops", []))
        m = {k: v for k, v in m.items() if k != "suppDrops"}
        if old:
            m["drops"] = [x for x in m.get("drops", []) if int(x["item"]) not in old]
            m["rareDrops"] = [x for x in m.get("rareDrops", []) if int(x["item"]) not in old]
        src = int(m.get("dropSrc", m["id"]))
        if "dropSrc" in m and src not in rows:
            errors.append(f"{m['id']} {m['name']}: dropSrc {src} 唔喺 CSV")
        if src in rows:
            imported += 1
            common, rare = split(rows[src]["drops"])
            m = with_drops(m, common, rare)
        else:
            custom.append(f"{m['id']} {m['name']}")
            for x in m.get("drops", []):
                if float(x["p"]) < RARE_BELOW:
                    errors.append(f"{m['id']} {m['name']}: drops 有 p<{RARE_BELOW} ({x['item']})")
            for x in m.get("rareDrops", []):
                if float(x["p"]) >= RARE_BELOW:
                    errors.append(f"{m['id']} {m['name']}: rareDrops 有 p>={RARE_BELOW} ({x['item']})")
        add = plan.get(int(m["id"]), [])
        if add:
            m["rareDrops"] = m.get("rareDrops", []) + [{"item": i, "p": SUPP_P[c]} for i, c in add]
            m["suppDrops"] = [i for i, _ in add]
            supp_n += len(add)
        if m != orig:
            diffs.append(f"{m['id']} {m['name']}" + (f" <- {src} {rows[src]['name']}" if src in rows else " (補充掉落)"))
        for x in m.get("drops", []) + m.get("rareDrops", []):
            if int(x["item"]) not in item_ids:
                errors.append(f"{m['id']} {m['name']}: item {x['item']} 唔喺 items.json")
            if not 0 < float(x["p"]) <= 1:
                errors.append(f"{m['id']} {m['name']}: item {x['item']} p={x['p']} 出界")
        new_monsters.append(m)

    print(f"[drops] 補充掉落 {supp_n} 條 (寶石/技能書/能力石)")
    print(f"[drops] CSV 導入 {imported} 隻；【自訂】手寫 {len(custom)} 隻: {', '.join(custom)}")
    for d in diffs:
        print(f"[DIFF] {d}")
    for e in errors:
        print(f"[ERR] {e}")
    if errors:
        return 1
    if check:
        if diffs:
            print("[drops] --check: monsters.json 同 CSV 唔一致，跑一次唔帶 --check 更新")
            return 1
        print("[drops] --check OK")
        return 0
    if diffs:
        data["monsters"] = new_monsters
        MONSTERS.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
        print(f"[drops] 寫咗 {len(diffs)} 隻 -> {MONSTERS.relative_to(ROOT)}")
    else:
        print("[drops] 冇變")
    return 0


if __name__ == "__main__":
    sys.exit(main())
