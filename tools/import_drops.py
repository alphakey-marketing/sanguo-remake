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
    for m in data["monsters"]:
        src = int(m.get("dropSrc", m["id"]))
        if "dropSrc" in m and src not in rows:
            errors.append(f"{m['id']} {m['name']}: dropSrc {src} 唔喺 CSV")
        if src in rows:
            imported += 1
            common, rare = split(rows[src]["drops"])
            if m.get("drops", []) != common or m.get("rareDrops", []) != rare:
                diffs.append(f"{m['id']} {m['name']} <- {src} {rows[src]['name']}")
            m = with_drops(m, common, rare)
        else:
            custom.append(f"{m['id']} {m['name']}")
            for x in m.get("drops", []):
                if float(x["p"]) < RARE_BELOW:
                    errors.append(f"{m['id']} {m['name']}: drops 有 p<{RARE_BELOW} ({x['item']})")
            for x in m.get("rareDrops", []):
                if float(x["p"]) >= RARE_BELOW:
                    errors.append(f"{m['id']} {m['name']}: rareDrops 有 p>={RARE_BELOW} ({x['item']})")
        for x in m.get("drops", []) + m.get("rareDrops", []):
            if int(x["item"]) not in item_ids:
                errors.append(f"{m['id']} {m['name']}: item {x['item']} 唔喺 items.json")
            if not 0 < float(x["p"]) <= 1:
                errors.append(f"{m['id']} {m['name']}: item {x['item']} p={x['p']} 出界")
        new_monsters.append(m)

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
