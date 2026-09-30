#!/usr/bin/env python3
"""把 sanguo extracted 素材轉入 client/assets_orig/ (私人本機用，唔入 git)。
用法: python tools/import_orig_assets.py [--src DIR] [--sets items,faces] [--check]
產出: client/assets_orig/<set>/... + client/data/asset_index.json (id -> 相對路徑，入 git)
--check: 淨驗索引同檔案一致 (assets_orig 空/未有 = 視為 0 覆蓋，仍 PASS，因為 AssetLib 有 fallback)
"""
import argparse, json, os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "client", "assets_orig")
INDEX = os.path.join(ROOT, "client", "data", "asset_index.json")
DEF_SRC = r"D:\Download\sanguo\extracted"

def natural(dirs):
    return sorted(dirs, key=lambda s: (len(s), s))

def imp_items(src, idx):
    """Pic_item*/NNNN_<id><a|b>.png: a=100x100 大圖, b=32x32 細圖。"""
    base = os.path.join(src, "sprites")
    small, large = {}, {}
    for d in natural(x for x in os.listdir(base) if x.lower().startswith("pic_item")):
        for f in sorted(os.listdir(os.path.join(base, d))):
            m = re.match(r"\d+_(\d+)([ab])\.png$", f)
            if not m:
                continue
            iid, kind = m.group(1), m.group(2)
            tgt = small if kind == "b" else large
            tgt.setdefault(iid, os.path.join(base, d, f))     # 重複 id 取先出現
    for name, tab, suf in (("items", small, ""), ("items_l", large, "")):
        out = {}
        for iid, p in tab.items():
            rel = f"{name}/{iid}.png"
            dst = os.path.join(OUT, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if not os.path.exists(dst):
                shutil.copyfile(p, dst)
            out[iid] = rel
        idx[name] = out
    # 冇自己圖嘅物品 (例: 10201) 用 items.json template 嘅圖 (同一模板共用 icon)；只加索引，唔複製檔
    items_json = os.path.join(ROOT, "client", "data", "items.json")
    if os.path.exists(items_json):
        with open(items_json, encoding="utf-8") as fh:
            for it in json.load(fh):
                iid, tpl = str(it["id"]), str(it.get("template", ""))
                for name in ("items", "items_l"):
                    if iid not in idx[name] and tpl in idx[name]:
                        idx[name][iid] = idx[name][tpl]

def imp_faces(src, idx):
    """Pic_npcFace1 等: NNNN_<npcid>.jpg / Pic_Face: NNNN_<code>.png -> faces/<key>.<ext>"""
    base = os.path.join(src, "sprites")
    out = {}
    for d in natural(x for x in os.listdir(base) if "face" in x.lower()):
        for f in sorted(os.listdir(os.path.join(base, d))):
            m = re.match(r"\d+_(\w+)\.(jpg|png)$", f)
            if not m:
                continue
            key = m.group(1)
            if key in out:
                continue
            rel = f"faces/{key}.{m.group(2)}"
            dst = os.path.join(OUT, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if not os.path.exists(dst):
                shutil.copyfile(os.path.join(base, d, f), dst)
            out[key] = rel
    idx["faces"] = out

SETS = {"items": imp_items, "faces": imp_faces}

def check():
    if not os.path.exists(INDEX):
        print("PASS asset_index.json 未生成 (0 覆蓋，fallback 生效)")
        return 0
    with open(INDEX, encoding="utf-8") as fh:
        idx = json.load(fh)
    miss = 0
    total = 0
    for name, tab in idx.items():
        if name.startswith("_"):
            continue
        for k, rel in tab.items():
            total += 1
            if os.path.isdir(OUT) and not os.path.exists(os.path.join(OUT, rel)):
                miss += 1
    print(f"{'FAIL' if miss and os.path.isdir(OUT) else 'PASS'} asset_index: {total} 項, 檔案缺 {miss}")
    return 1 if (miss and os.path.isdir(OUT)) else 0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=DEF_SRC)
    ap.add_argument("--sets", default=",".join(SETS))
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if a.check:
        sys.exit(check())
    idx = {"_note": "由 tools/import_orig_assets.py 生成，唔好手改。key=id, value=相對 res://assets_orig/ 路徑"}
    for s in a.sets.split(","):
        SETS[s](a.src, idx)
    os.makedirs(os.path.dirname(INDEX), exist_ok=True)
    with open(INDEX, "w", encoding="utf-8") as fh:
        json.dump(idx, fh, ensure_ascii=False, indent=0, sort_keys=True)
    print({k: len(v) for k, v in idx.items() if not k.startswith("_")})
    if os.path.exists(os.path.join(ROOT, "client", "data", "items.json")):
        with open(os.path.join(ROOT, "client", "data", "items.json"), encoding="utf-8") as fh:
            ids = [str(i["id"]) for i in json.load(fh)]
        miss = [i for i in ids if i not in idx.get("items", {})]
        print(f"覆蓋率 items: {len(ids) - len(miss)}/{len(ids)}；缺圖 id 頭 20: {miss[:20]}")

if __name__ == "__main__":
    main()
