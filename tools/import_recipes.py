"""進階生產配方導入 (Step 12, spec 05 §4)。

來源: client/data/items.json 每件物品 `materials` 欄【原】+ `craft_kind`/`craft_lv`【原】
  craft_kind: 9 冶鐵(武器) / 10 修繕(防具) / 11 廚藝(食物藥水) / 12 煉丹(藥丸散) / 13 木匠(戒指/項鍊/箭)
  craft_lv  : 所需進階技能等級 (0 當 1)
  craft_kind 0 但有 materials 嘅 149 件 = 原版冇指定技能，唔導入
輸出: client/data/recipes.json  (唔好手改，改完重跑)

用法:
  python tools/import_recipes.py           # 生成
  python tools/import_recipes.py --check   # 核對檔案同 items.json 一致 (run_tests 用)
"""
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ITEMS = os.path.join(ROOT, "client", "data", "items.json")
OUT = os.path.join(ROOT, "client", "data", "recipes.json")

KIND_SKILL = {9: "smithing", 10: "mending", 11: "cooking", 12: "alchemy", 13: "carpentry"}


def build():
    items = json.load(open(ITEMS, encoding="utf-8"))
    ids = {int(x["id"]) for x in items}
    recipes = []
    skipped_kind0 = 0
    skipped_missing = 0
    for x in items:
        mats = x.get("materials") or []
        if not mats:
            continue
        kind = int(x.get("craft_kind", 0))
        if kind not in KIND_SKILL:
            skipped_kind0 += 1
            continue
        need = [[int(m["id"]), int(m["count"])] for m in mats]
        if any(m[0] not in ids or m[1] <= 0 for m in need):
            skipped_missing += 1
            continue
        recipes.append({"id": int(x["id"]), "skill": KIND_SKILL[kind],
                        "lv": max(1, int(x.get("craft_lv", 0))), "need": need})
    recipes.sort(key=lambda r: (r["skill"], r["lv"], r["id"]))
    out = {
        "_note": "由 tools/import_recipes.py 從 items.json materials/craft_kind/craft_lv【原】生成，唔好手改。"
                 "lv = 所需進階技能等級；need = [[材料 id, 數量]]",
        "recipes": recipes,
    }
    return out, skipped_kind0, skipped_missing


def dump(o):
    # 一個配方一行，方便 diff
    lines = ["{", '  "_note": %s,' % json.dumps(o["_note"], ensure_ascii=False), '  "recipes": [']
    rs = o["recipes"]
    for i, r in enumerate(rs):
        lines.append("    " + json.dumps(r, ensure_ascii=False) + ("," if i < len(rs) - 1 else ""))
    lines += ["  ]", "}", ""]
    return "\n".join(lines)


def main():
    o, k0, miss = build()
    txt = dump(o)
    per = {}
    for r in o["recipes"]:
        per[r["skill"]] = per.get(r["skill"], 0) + 1
    print("[recipes] %d 個配方 %s；craft_kind 0 跳過 %d；缺材料跳過 %d" % (len(o["recipes"]), per, k0, miss))
    if "--check" in sys.argv:
        cur = open(OUT, encoding="utf-8").read().replace("\r\n", "\n") if os.path.exists(OUT) else ""
        if cur != txt:
            print("[recipes] --check FAIL: recipes.json 同 items.json 唔一致，重跑 tools/import_recipes.py")
            sys.exit(1)
        print("[recipes] --check OK")
        return
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)
    print("[recipes] 寫咗", OUT)


if __name__ == "__main__":
    main()
