#!/usr/bin/env python3
"""D1 資料核對: 原版 CSV vs client/data/*.json → docs/uat/data_audit_raw.md (只讀，唔改資料)。"""
import csv, json, os, re, sys, collections
T = r"D:/Download/sanguo/extracted/text/"
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "client", "data") + "/"
def rc(n):
    with open(T + n, encoding="utf-8-sig", newline="") as f: return list(csv.DictReader(f))
def rj(n): return json.load(open(D + n, encoding="utf-8"))
out = []
def H(s): out.append("\n## " + s + "\n")
def P(s=""): out.append(s)
def dids(txt): return {int(x) for x in re.findall(r"\((\d+)\)@", txt)}
def lst(xs, n=15): return ", ".join(str(x) for x in xs[:n]) + (f" …共{len(xs)}" if len(xs) > n else "")

items_j = {i["id"]: i for i in rj("items.json")}
items_c = {int(r["id"]): r for r in rc("items.csv")}
H("A. items.csv vs items.json")
P(f"- csv {len(items_c)} 件 / json {len(items_j)} 件")
only_c = sorted(set(items_c) - set(items_j)); only_j = sorted(set(items_j) - set(items_c))
P(f"- 只喺 csv: {lst(only_c)}"); P(f"- 只喺 json (json 多出): {lst(only_j)}")
diff = collections.defaultdict(list)
for i in set(items_c) & set(items_j):
    c, j = items_c[i], items_j[i]
    for fc, fj in [("name","name"),("price","price"),("weight","weight"),("req_lv","req_lv"),("craft_kind","craft_kind"),("craft_lv","craft_lv"),("cat","cat")]:
        if str(c[fc]) != str(j[fj]): diff[fc].append((i, c[fc], j[fj]))
    cm = sorted((m.rsplit("x", 1)[0], int(m.rsplit("x", 1)[1])) for m in c["materials"].split() if "x" in m)
    jm = sorted((m["name"], m["count"]) for m in j.get("materials", []))
    if cm != jm: diff["materials"].append((i, cm, jm))
for k in ["name","price","weight","req_lv","craft_kind","craft_lv","cat","materials"]:
    P(f"- 欄位 `{k}` 不一致: {len(diff[k])} " + (lst(diff[k], 5) if diff[k] else ""))
if only_j:
    P(f"- json 多出項目名稱: {lst([items_j[i]['name'] for i in only_j], 20)}")

H("B. general_npc.csv vs generals.json")
gc = {int(r["id"]): r for r in rc("general_npc.csv")}
gj = {g["id"]: g for g in rj("generals.json")["generals"]}
P(f"- csv {len(gc)} / json {len(gj)}; 只 csv {lst(sorted(set(gc)-set(gj)))}; 只 json {lst(sorted(set(gj)-set(gc)))}")
bad = collections.defaultdict(list)
for i in set(gc) & set(gj):
    c, j = gc[i], gj[i]
    if c["name"] != j["name"]: bad["name"].append(i)
    if int(c["f101_str"]) != j["lv"]: bad["lv(f101)"].append((i, c["f101_str"], j["lv"]))
    if int(c["f116_int"]) != j["int"]: bad["int(f116)"].append(i)
    sk = [[int(a) for a in s.split(":")] for s in c["skills(id:lv)x9"].split()]
    if sk != [list(s) for s in j["skills"]]: bad["skills"].append(i)
for k in ["name","lv(f101)","int(f116)","skills"]: P(f"- `{k}` 不一致: {len(bad[k])} {lst(bad[k],5)}")
sn = rj("generals.json")["skillNames"]; used = {s[0] for g in gj.values() for s in g["skills"]}
P(f"- skillNames 覆蓋: 用到 {len(used)} 種技能 id, 缺名 {lst(sorted(used - {int(k) for k in sn}))}")
tc = collections.Counter(g["tier"] for g in gj.values()); P(f"- tier 分佈: {dict(tc)}")

H("C. npc_drops.csv vs monsters.json")
nd = {int(r["npc_id"]): r for r in rc("npc_drops.csv")}
mons = rj("monsters.json")["monsters"]
P(f"- csv NPC {len(nd)} (有掉落 {sum(1 for r in nd.values() if int(r['n_drops'])>0)}); game 怪 {len(mons)}")
nosrc = [(m["id"], m["name"]) for m in mons if m.get("dropSrc") not in nd]
P(f"- game 怪冇 dropSrc (或唔喺 csv): {len(nosrc)} 隻 {lst(nosrc,8)}")
P(f"- 完全冇掉落嘅怪: {sum(1 for m in mons if not m.get('drops') and not m.get('rareDrops'))} 隻")
mism = []
for m in mons:
    r = nd.get(m.get("dropSrc"))
    if not r or not r["drops(item×rate)"]: continue
    
    csv_items = dids(r["drops(item×rate)"])
    game_items = {d["item"] for d in m.get("drops", [])} | {d["item"] for d in m.get("rareDrops", [])}
    if csv_items != game_items: mism.append((m["id"], m["name"], sorted(csv_items ^ game_items)[:6]))
P(f"- 掉落集合同 csv 唔同嘅怪: {len(mism)} {lst(mism,6)}")
used_src = {m.get("dropSrc") for m in mons}
unused = [(k, r["npc_name"], int(r["n_drops"])) for k, r in nd.items() if int(r["n_drops"]) > 0 and k not in used_src]
P(f"- csv 有掉落但 game 冇用嘅 NPC: {len(unused)} 個 (例: {lst(unused,8)})")
mon_drop_items = {d["item"] for m in mons for d in m.get("drops", []) + m.get("rareDrops", [])}
csv_drop_items = set().union(*[dids(r["drops(item×rate)"]) for r in nd.values()])
P(f"- csv 全部掉落物 {len(csv_drop_items)} 種; game 有掉落嘅 {len(mon_drop_items)} 種; csv 有 game 無 {len(csv_drop_items - mon_drop_items)} 種")

H("D. jewel.csv vs items/jewels.json")
jc = {int(r["item_id"]): r for r in rc("jewel.csv")}
jj = rj("jewels.json"); jids = {x["id"] for k in ["stones","special","support","fusable"] for x in jj[k]}
P(f"- csv {len(jc)} / jewels.json {len(jids)}; 只 csv {lst(sorted(set(jc)-jids))}; 只 json {lst(sorted(jids-set(jc)),10)}")
fus = {x["id"]: x for x in jj["fusable"]}
P("- (jewel.csv value 欄語意同 fusable 效果值唔同 (如 56328 = 9831000)，唔比對數值)")

H("E. 配方材料來源 (material_sources.csv)")
ms = {int(r["material_id"]): r for r in rc("material_sources.csv")}
rec = rj("recipes.json")["recipes"]
need = collections.Counter(n[0] for r in rec for n in r["need"])
shop_items = set()
sj = rj("shops.json")
for s in sj["shops"]: shop_items |= set(s.get("stock", []))
mall = set(rj("mall.json")["stock"])
P(f"- 配方 {len(rec)} 條, 用到 {len(need)} 種材料; material_sources.csv {len(ms)} 種")
orph = []
for mid in need:
    src = ms.get(mid, {}).get("source", "?")
    if mid in mon_drop_items or mid in shop_items or mid in mall: continue
    if "採集" in src or "種植" in src: continue
    orph.append((mid, items_j.get(mid, {}).get("name", "?"), src))
P(f"- 材料唔喺掉落/商店/商城/採集嘅孤兒: {len(orph)} {lst(orph,12)}")
srcc = collections.Counter(r["source"] for r in ms.values()); P(f"- csv source 類型: {dict(srcc)}")
P(f"- 配方材料 id 唔喺 items.json: {lst(sorted(m for m in need if m not in items_j))}")
mat_ids = os.path.join(D, "material_ids.json"); P(f"- material_ids.json 存在於 client/data: {os.path.exists(mat_ids)}")

H("F. 已知待處理項")
mp = rj("mall.json")["prices"]
for k, v in mp.items():
    ij = items_j.get(int(k), {})
    P(f"- 商城 {k} {ij.get('name','?')}: mall.json {v} / items.price {ij.get('price')}")
P(f"- 渾天儀 26029: items.json {'有' if 26029 in items_j else '無'} ({items_j.get(26029,{}).get('name')}); 商店 {26029 in shop_items}; 商城 {26029 in mall}; 掉落 {26029 in mon_drop_items}")
arrows = [i for i in items_j.values() if i["cat"] == 49]
P(f"- 箭矢 cat49: {len(arrows)} 支; 商店有賣 {sum(1 for a in arrows if a['id'] in shop_items)}; 掉落 {sum(1 for a in arrows if a['id'] in mon_drop_items)}")
H("G. 全遊戲可得性 (items 有價/有配方但完全冇來源)")
recipe_out = {r["id"] for r in rec}
src_all = shop_items | mall | mon_drop_items | recipe_out
noget = collections.Counter(); ex = collections.defaultdict(list)
for i in items_j.values():
    if i["id"] in src_all: continue
    noget[i["cat_label"]] += 1; ex[i["cat_label"]].append(i["name"])
P(f"- 冇商店/商城/掉落/配方產出嘅道具: {sum(noget.values())} 件 (按 cat: {dict(noget.most_common(12))})")
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "uat", "data_audit_raw.md"), "w", encoding="utf-8").write("# D1 資料核對原始輸出 (tools/data_audit.py 生成)\n" + "\n".join(out))
print("\n".join(out))
