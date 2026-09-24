"""頭銜 60 階導入 (Step 14, spec 08 §2)。

來源: docs/guide/sy2_8_4.txt (攻略「初級頭銜大公開」全表)【原】
  每階 = 階級 / 御賜頭銜 / 名聲 / 資金 / 行動力上限 / 俸祿 / 可執行的任務 (0~N 行，跟喺該階後面)
攻略手民之誤 (FIXES)：41 階後將軍俸祿寫 4900，前後都係每階 100 → 改 4100 (保留原值喺 salaryGuide)
【自訂】: 冇 (全表照攻略；行動力上限 = 100 + 2×階，驗證用)
輸出: client/data/titles.json  (唔好手改，改完重跑)

用法:
  python tools/gen_titles.py           # 生成
  python tools/gen_titles.py --check   # 核對檔案同攻略一致 + 表內規律 (run_tests 用)
"""
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "docs", "guide", "sy2_8_4.txt")
OUT = os.path.join(ROOT, "client", "data", "titles.json")

FIXES = {41: {"salary": 4100}}      # 攻略筆誤修正 (見頂註)


def parse():
    lines = [l.strip() for l in open(SRC, encoding="utf-8").read().splitlines()]
    i = lines.index("可執行的任務") + 1
    rows = []
    while i < len(lines):
        if not re.fullmatch(r"\d+", lines[i] or "x"):
            i += 1
            continue
        rank, name = int(lines[i]), lines[i + 1]
        fame, gold, ap, salary = (int(lines[i + k]) for k in range(2, 6))
        i += 6
        unlock = []
        while i < len(lines) and lines[i] and not re.fullmatch(r"\d+", lines[i]):
            unlock.append(lines[i].rstrip("、"))
            i += 1
        rows.append({"rank": rank, "name": name, "fame": fame, "gold": gold, "ap": ap, "salary": salary, "unlock": unlock})
    rows.sort(key=lambda r: r["rank"])
    for r in rows:
        for k, v in FIXES.get(r["rank"], {}).items():
            r[k + "Guide"] = r[k]
            r[k] = v
    return rows


def verify(rows):
    errs = []
    if [r["rank"] for r in rows] != list(range(1, 61)):
        errs.append("階級唔係 1~60")
    for r in rows:
        if r["ap"] != 100 + 2 * r["rank"]:
            errs.append("%d 階行動力上限 %d != 100+2×階" % (r["rank"], r["ap"]))
        if r["fame"] != r["gold"]:
            errs.append("%d 階名聲 != 資金" % r["rank"])
        exp_sal = 0 if r["rank"] < 6 else r["rank"] * 100
        if r["salary"] != exp_sal:
            errs.append("%d 階俸祿 %d != %d" % (r["rank"], r["salary"], exp_sal))
    for rank, name in {1: "校尉", 6: "南中郎將", 20: "領軍將軍", 50: "征東將軍", 60: "大將軍"}.items():
        if rows[rank - 1]["name"] != name:
            errs.append("%d 階名 %s != %s" % (rank, rows[rank - 1]["name"], name))
    if "成立義勇軍" not in rows[5]["unlock"] or "戶口普查" not in rows[14]["unlock"]:
        errs.append("任務解鎖欄對錯行")
    return errs


def main():
    rows = parse()
    o = {"_note": "頭銜 60 階 (Step 14, spec 08 §2)。由 tools/gen_titles.py 從攻略 sy2_8_4 生成【原】，唔好手改。"
                  "fame/gold = 討取要名聲/資金 (資金一次過扣)；ap = 行動力上限；salary = 每月初一俸祿；unlock = 攻略「可執行的任務」欄；"
                  "salaryGuide = 攻略原值 (筆誤已修)",
         "titles": rows}
    txt = "{\n" + ",\n".join([' "_note": ' + json.dumps(o["_note"], ensure_ascii=False),
                               ' "titles": [\n' + ",\n".join("  " + json.dumps(r, ensure_ascii=False) for r in rows) + "\n ]"]) + "\n}\n"
    errs = verify(rows)
    for e in errs:
        print("[titles] FAIL " + e)
    print("[titles] %d 階；有解鎖欄 %d 階" % (len(rows), sum(1 for r in rows if r["unlock"])))
    if "--check" in sys.argv:
        cur = open(OUT, encoding="utf-8").read().replace("\r\n", "\n") if os.path.exists(OUT) else ""
        if cur != txt:
            print("[titles] --check FAIL: titles.json 同攻略唔一致，重跑 tools/gen_titles.py")
            sys.exit(1)
        if errs:
            sys.exit(1)
        print("[titles] --check OK")
        return
    if errs:
        sys.exit(1)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)
    print("[titles] 寫咗", OUT)


if __name__ == "__main__":
    main()
