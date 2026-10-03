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
    # 名 → 頭像 (Npc_table.tsv: npcid/name/sprite；sprite id = 頭像檔名)。同名取先出現有圖者
    tsv = os.path.join(src, "text", "Npc_table.tsv")
    by_name = {}
    if os.path.exists(tsv):
        with open(tsv, encoding="utf-8") as fh:
            next(fh, None)
            for line in fh:
                c = line.rstrip("\r\n").split("\t")
                if len(c) >= 3 and c[2] in out and c[1] and c[1] not in by_name:
                    by_name[c[1]] = out[c[2]]
    idx["faces_by_name"] = by_name

def imp_facelayers(src, idx):
    """臉譜疊層 (Pic_Face/Pic_face2, 72x80 同座標): key = 小寫碼 (b01bNN 背景 / <組>c|f|e|h0N 頸/臉型/眉眼/髮)；跳過 32x36 細圖 (尾 s)"""
    base = os.path.join(src, "sprites")
    out = {}
    for d in ("Pic_Face", "Pic_face2"):
        for f in sorted(os.listdir(os.path.join(base, d))):
            m = re.match(r"\d+_(\w+)\.png$", f)
            if not m or m.group(1).lower().endswith("s"):
                continue
            key = m.group(1).lower()
            rel = f"facelayers/{key}.png"
            dst = os.path.join(OUT, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if not os.path.exists(dst):
                shutil.copyfile(os.path.join(base, d, f), dst)
            out[key] = rel
    idx["face_layers"] = out
    print(f"臉譜疊層: {len(out)} 張")

def _find(src, d, name):
    base = os.path.join(src, "sprites", d)
    for f in os.listdir(base):
        if f.split("_", 1)[-1] == name:
            return os.path.join(base, f)
    raise FileNotFoundError(f"{d}/{name}")

def _blank_button(path, cap=10):
    """原版掣字燒死喺圖入面 → 保留左右 cap 像素邊框，中間用 cap 內一條直欄橫向拉闊 (去字)，做成 9-slice 空白掣。"""
    from PIL import Image
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    out = Image.new("RGBA", (cap * 2 + 8, h))
    out.paste(im.crop((0, 0, cap, h)), (0, 0))
    out.paste(im.crop((w - cap, 0, w, h)), (cap + 8, 0))
    # 中間填色: 每行取內部「淺色 (羊皮紙)」像素中位數 (排除燒死嘅墨字)，再垂直平滑 → 無字無橫紋
    px = im.load()
    rows = []
    for y in range(h):
        v = [px[x, y] for x in range(cap + 2, w - cap - 2) if px[x, y][3] > 200 and sum(px[x, y][:3]) > 420]
        rows.append(tuple(sorted(c[i] for c in v)[len(v) // 2] for i in range(3)) if len(v) > 6 else None)
    for y in range(h):
        if rows[y] is None:
            rows[y] = next((rows[k] for d in range(1, h) for k in (y - d, y + d) if 0 <= k < h and rows[k]), (200, 170, 110))
    sm = []
    for y in range(h):
        nb = [rows[k] for k in range(max(0, y - 2), min(h, y + 3))]
        sm.append(tuple(sum(c[i] for c in nb) // len(nb) for i in range(3)) + (255,))
    for y in range(h):
        for x in range(cap, cap + 8):
            out.putpixel((x, y), sm[y])
    return out

def imp_ui(src, idx):
    """UI 皮: 視窗底框 (240x330Form 9-slice) + 空白掣 (btnjui_1 正常/ _1s 按下)。"""
    from PIL import Image, ImageOps
    os.makedirs(os.path.join(OUT, "ui"), exist_ok=True)
    out = {}
    def save(name, im):
        rel = f"ui/{name}.png"
        im.save(os.path.join(OUT, rel))
        out[name] = rel
    save("panel", Image.open(_find(src, "Pic_menu04", "240x330Form.png")).convert("RGBA"))
    save("card", Image.open(_find(src, "Pic_menu04", "104x133form.png")).convert("RGBA"))
    n = _blank_button(_find(src, "Pic_menu24", "btnjui_1.png"))
    p = _blank_button(_find(src, "Pic_menu24", "btnjui_1s.png"))
    save("btn_n", n)
    save("btn_p", p)
    g = ImageOps.grayscale(n.convert("RGB")).convert("RGBA")
    g.putalpha(n.getchannel("A"))
    save("btn_d", g)
    idx["ui"] = out

def _keyed_copy(f, dst):
    """sheets/ 底色係實心 (40,90,60) → 轉透明再存 (每次覆寫，方便改規則)"""
    from PIL import Image
    im = Image.open(f).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y][:3] == (40, 90, 60):
                px[x, y] = (0, 0, 0, 0)
    im.save(dst)

# 缺原版 sprite 嘅怪借相似怪嘅圖 + 染色區分 (怪名 -> (借圖怪名, 染色 #rrggbb))；搵到真圖包 (hsnpc01/editnpc01/warnpc 等 mrg) 後刪走對應項
BORROW = {
    '野狼': ('山狼', '#d8c8a8'), '野狗': ('大狼', '#c89a6a'), '夜狼': ('惡狼', '#7a86b8'),
    '老虎': ('南方虎', '#ffffff'), '惡虎': ('東方虎', '#c8a0a0'), '花豹': ('金錢豹', '#a0c8a0'),
    '大熊': ('食人巨熊', '#c8a888'), '狐貍': ('百年狐狸', '#ffd0a0'), '狐蝠精': ('狐蝠王', '#b0a0d8'),
    '蟾蜍王': ('蟾蜍怪', '#d0a050'), '蝴蝶精': ('蜻蜓', '#ffb0e0'), '飛蛾怪': ('黃蜂', '#b09070'),
    '瘋貓': ('草貂', '#e0c070'), '蜥蜴王': ('毒蠍子', '#70c070'),
    '木乃伊': ('千年殭屍', '#e0d0a0'), '殭屍': ('千年殭屍', '#a0c0a0'), '妖僧侶': ('萬年寒屍', '#d0a0d0'),
    '妖法師': ('輕裝劍客', '#b080e0'), '妖道士': ('輕裝劍客', '#80b0e0'),
    '親衛隊': ('金甲劍兵', '#a0c0ff'), '精銳親衛隊': ('金甲劍兵', '#ffb0b0'), '義勇軍士兵': ('銀甲劍兵', '#a0e0a0'),
    '白馬護衛': ('銀甲劍兵', '#f0f0ff'), '神射手': ('神鷹箭士', '#ffd080'), '邪惡弓兵': ('金甲弓兵', '#c080c0'),
    '鬼面弓兵': ('銀甲弓兵', '#8090a0'), '山賊弓箭手': ('金甲弓兵', '#d0b080'),
    '冷血殺手': ('匕首流氓', '#8090c0'), '紅衣殺手': ('匕首流氓', '#ff8080'), '雙刃殺手': ('飛賊劍手', '#80c0a0'),
    '雙風黑殺手': ('飛賊劍手', '#606070'), '奪命書生': ('輕裝劍客', '#a0a0e0'), '邪惡書生': ('輕裝劍客', '#c08080'),
    '山寨頭目': ('盜王', '#d0a070'), '嗜殺狂': ('狂徒', '#ff9090'), '戰狂': ('狂斧兵', '#ffa060'), '殺人狂': ('狂徒', '#c0c0c0'),
    '土匪1': ('破斧土匪', '#d0b090'), '土匪2': ('破斧土匪', '#b09070'), '地痞1': ('短刀地痞', '#c0d0a0'),
    '地痞2': ('紅髮地痞', '#d0d0d0'), '流氓1': ('匕首流氓', '#d0c0a0'), '流氓2': ('武棍流氓', '#c0a0c0'),
    '霸盜賊': ('盜王', '#c0b0a0'), '盜賊2': ('盜賊', '#d0d0a0'), '小兵1': ('流浪兵', '#c0c0ff'),
    '彎刀兵': ('刀兵', '#a0d0d0'), '長刀兵': ('刀兵', '#d0a0a0'), '長槍兵': ('槍兵', '#a0a0d0'),
    '隨護衛': ('流亡士兵', '#d0e0b0'), '簡護衛': ('守門流浪兵', '#e0d0b0'), '巨斧兵': ('長斧兵', '#d0b0b0'),
    '煉獄使者': ('地獄使者', '#ff9060'), '紫晶守護者': ('嗜血狂魔', '#c090ff'), '午日凶靈': ('地獄使者', '#ffe080'),
    '試煉守衛': ('金盾兵', '#e0e0a0'), '試煉武師': ('護甲劍客', '#e0a0a0'), '試煉魔將': ('野戰劍將', '#c06060'),
}

def imp_mon(src, idx):
    """怪物動畫 sheet (8 方向列 x 8 幀欄，見 docs/plan/sprite_layout.md)。
    monsters.json 怪 id -> Npc_Client.Dat 記錄 (先 id，再 dropSrc，再同名) -> sprite id (@offset 150) -> sheets/*/CP_<sprite><A|S|W>.CP.png"""
    import glob, struct
    sys.path.insert(0, os.path.join(os.path.dirname(src), "tools"))
    import npc_dat
    dat = os.path.join(os.path.dirname(src), "reference", "Npc_Client.Dat")
    recs = npc_dat.parse(open(dat, "rb").read())
    spr = lambda r: struct.unpack_from("<H", r["raw"], 150)[0]
    where = {}
    for f in glob.glob(os.path.join(src, "sheets", "*", "CP_*S.CP.png")):
        where[int(os.path.basename(f)[3:-8])] = os.path.dirname(f)
    byid = {r["id"]: r for r in recs}
    byname = {}
    for r in recs:
        byname.setdefault(r["name"], r)
    with open(os.path.join(ROOT, "client", "data", "monsters.json"), encoding="utf-8") as fh:
        mons = json.load(fh)["monsters"]
    out = {"A": {}, "S": {}, "W": {}}
    done = set()
    os.makedirs(os.path.join(OUT, "mon"), exist_ok=True)
    for m in mons:
        sid = m.get("sprite") if m.get("sprite") in where else None   # 洞穴怪表冇 id -> 用 okm sprite
        for r in () if sid else (byid.get(m["id"]), byid.get(m.get("dropSrc")), byname.get(m["name"])):
            if r and spr(r) in where:
                sid = spr(r)
                break
        if sid is None:
            continue
        for a in "ASW":
            f = os.path.join(where[sid], f"CP_{sid}{a}.CP.png")
            if not os.path.exists(f):
                continue
            rel = f"mon/{sid}{a}.png"
            dst = os.path.join(OUT, rel)
            if (sid, a) not in done:
                _keyed_copy(f, dst)
                done.add((sid, a))
            out[a][str(m["id"])] = rel
    tint = {}
    ok = {m["name"]: m["id"] for m in reversed(mons) if str(m["id"]) in out["S"] and m["name"] not in BORROW}
    for m in mons:
        b = BORROW.get(m["name"])
        if not b or str(m["id"]) in out["S"] or b[0] not in ok:
            continue
        for a in "ASW":
            if str(ok[b[0]]) in out[a]:
                out[a][str(m["id"])] = out[a][str(ok[b[0]])]
        tint[str(m["id"])] = b[1]
    idx["_mon_tint"] = tint
    for a in "ASW":
        idx["mon_" + a] = out[a]
    print(f"怪物動畫覆蓋: {len(out['S'])}/{len(mons)}")

# 通用人形 sprite 池 (由 contact sheet 人手分類，NPC/居民冇專屬 sprite 時按 role 揀)。玩家暫用每職業一個佔位，待疊層解碼 (A4c 後續)
ACTOR_POOL = {
    "civ_m": [20110, 20115, 20116, 20120, 20121, 20122, 20140, 20142, 20155, 20156, 20157, 20159, 20095, 20096, 20134],
    "civ_f": [20091, 20136, 20138, 20144, 20158, 20424],
    "soldier": [20150, 20151, 20160, 20161, 20163, 20208, 20209, 20218, 20219, 20147, 20148, 20149],
    "elder": [20018, 20039],
    "player": {"yishi": 20208, "shinu": 20136, "daoshi": 20155, "wunu": 20231, "bianshi": 20226, "meinu": 20144},
}

def imp_actor(src, idx):
    """人形 sprite (NPC/居民/武將/玩家)。actor_A/S/W: sprite id -> sheet；_actor_by_name: 名 -> sprite id (Npc_Client.Dat @150)；_actor_pool: 通用池"""
    import glob, struct
    sys.path.insert(0, os.path.join(os.path.dirname(src), "tools"))
    import npc_dat
    recs = npc_dat.parse(open(os.path.join(os.path.dirname(src), "reference", "Npc_Client.Dat"), "rb").read())
    where = {}
    for f in glob.glob(os.path.join(src, "sheets", "*", "CP_*S.CP.png")):
        d = os.path.dirname(f)
        if os.path.basename(d).lower().startswith(("npc", "dnpc")):       # 人形 sheet (排除怪 d2npc01 / effect / warnpc)
            where[int(os.path.basename(f)[3:-8])] = d
    by_name = {}
    for r in recs:
        sid = struct.unpack_from("<H", r["raw"], 150)[0]
        if sid in where and r["name"] not in by_name:
            by_name[r["name"]] = sid
    used = set(by_name.values())
    for v in ACTOR_POOL.values():
        used |= set(v.values() if isinstance(v, dict) else v)
    out = {"A": {}, "S": {}, "W": {}}
    os.makedirs(os.path.join(OUT, "actor"), exist_ok=True)
    for sid in sorted(used):
        if sid not in where:
            print("警告: 池 sprite 缺", sid)
            continue
        for a in "ASW":
            f = os.path.join(where[sid], f"CP_{sid}{a}.CP.png")
            if os.path.exists(f):
                rel = f"actor/{sid}{a}.png"
                _keyed_copy(f, os.path.join(OUT, rel))
                out[a][str(sid)] = rel
    # 玩家職業: role1 分層 sheet 疊合 (身體+甲+髮+武器, 默認款), 見 tools/compose_player.py
    #   sid 91001~91006 = 義士/士女/道士/舞女/辯士/美女; S/W=走路 (C=1), A=攻擊 (C=2)
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import compose_player
    PBODY = {"yishi": 1, "shinu": 2, "daoshi": 3, "wunu": 4, "bianshi": 5, "meinu": 6}
    ACTOR_POOL["player"] = {}
    for cid, b in PBODY.items():
        sid = 91000 + b
        cache = {}
        for a, c in (("S", 1), ("W", 1), ("A", 2)):
            if c not in cache:
                try:
                    cache[c] = compose_player.compose(b, c, hair=1, armor=1, weapon=1)
                except Exception as ex:
                    print("警告: 玩家疊合失敗", cid, c, ex)
                    cache[c] = None
            if cache[c] is not None:
                rel = f"actor/{sid}{a}.png"
                cache[c].save(os.path.join(OUT, rel))
                out[a][str(sid)] = rel
        ACTOR_POOL["player"][cid] = sid
    for a in "ASW":
        idx["actor_" + a] = out[a]
    idx["_actor_by_name"] = {k: str(v) for k, v in by_name.items() if str(v) in out["S"]}
    idx["_actor_pool"] = ACTOR_POOL
    print(f"人形 sprite: {len(out['S'])} 個，名字對應 {len(idx['_actor_by_name'])}")

# 座騎: npc02 123001~5 披甲馬 (8x8)；6 馬種按毛色對應 5 款
MOUNT_MAP = {"wusun": 123004, "damo": 123001, "huangbiao": 123003, "dawan": 123005, "shenshan": 123002, "zhongyuan": 123001}

def imp_mount(src, idx):
    os.makedirs(os.path.join(OUT, "mount"), exist_ok=True)
    out = {}
    for breed, sid in MOUNT_MAP.items():
        f = os.path.join(src, "sheets", "npc02", f"CP_{sid}S.CP.png")
        if not os.path.exists(f):
            print("警告: 馬 sprite 缺", sid)
            continue
        rel = f"mount/{sid}S.png"
        _keyed_copy(f, os.path.join(OUT, rel))
        out[breed] = rel
    idx["mount_S"] = out
    print(f"座騎 sprite: {len(out)} 馬種")

# 特別服裝: (名, role mrg, 甲 E 位, 甲 FG, 髮 FG 或 "")；E=4 夢幻/特殊套，E=1 FG08~12 = 變身吉祥物 (只部分職業有)
COSTUMES = [
    ("神話一", "role9902", "4", "04", "04"), ("神話二", "role9902", "4", "05", "05"), ("神話三", "role9902", "4", "06", "06"),
    ("夢幻一", "role9", "4", "01", "01"), ("夢幻二", "role9", "4", "02", "02"), ("夢幻三", "role9", "4", "03", "03"), ("夢幻四", "role9", "4", "07", "07"),
    ("節慶", "role9904", "4", "07", "07"), ("聖誕", "role9904", "4", "15", ""), ("華服", "role9905", "4", "14", ""),
    ("變身一", "role9", "1", "08", ""), ("變身二", "role9", "1", "09", ""), ("變身三", "role9", "1", "10", ""),
    ("變身四", "role9", "1", "11", ""), ("變身五", "role9", "1", "12", ""),
]


def imp_player_layers(src, idx):
    """玩家分層 (運行時按裝備疊): player_layers key = "B/C/kind/style"
    kind: b 身 / w 武 (1~9) / a 甲 (0~6) / h 髮 (0~6)；B=職業 1~6, C=動作 1 走 2 攻。同 cell/原點，直接疊。"""
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import compose_player as cp
    os.makedirs(os.path.join(OUT, "player"), exist_ok=True)
    out = {}
    for b in range(1, 7):
        for c in (1, 2):
            specs = [("b", 0, f"1{b}{c}1300")] + [("w", k, f"1{b}{c}21{k:02d}") for k in range(1, 10)]                 + [("a", k, f"1{b}{c}41{k:02d}") for k in range(0, 7)] + [("h", k, f"1{b}{c}31{k:02d}") for k in range(0, 7)]
            for kind, k, code in specs:
                sh = cp.single(code)
                if sh is None:
                    continue
                rel = f"player/{b}_{c}_{kind}{k}.png"
                sh.save(os.path.join(OUT, rel))
                out[f"{b}/{c}/{kind}/{k}"] = rel
            # 三轉基本造型 (role9902 第 1 款 FG04): kind t = 甲(含翼)，th = 髮
            for kind, code in (("t", f"1{b}{c}4404"), ("th", f"1{b}{c}3404")):
                sh = cp.single(code, cp.layer9902)
                if sh is None:
                    continue
                rel = f"player/{b}_{c}_{kind}0.png"
                sh.save(os.path.join(OUT, rel))
                out[f"{b}/{c}/{kind}/0"] = rel
    # 特別服裝 (外觀頁): kind t = 甲、th = 髮，style = 服裝 id (見 COSTUMES)；冇髮件就用裝備髮
    cls_of = {1: "yishi", 2: "shinu", 3: "daoshi", 4: "wunu", 5: "bianshi", 6: "meinu"}
    meta = []
    for cid, (name, mrg, ae, afg, hfg) in enumerate(COSTUMES, 1):
        have = []
        for b in range(1, 7):
            ok = False
            for c in (1, 2):
                sh = cp.single(f"1{b}{c}4{ae}{afg}", cp.mrg_layer(mrg))
                if sh is None:
                    continue
                ok = True
                sh.save(os.path.join(OUT, f"player/{b}_{c}_t{cid}.png"))
                out[f"{b}/{c}/t/{cid}"] = f"player/{b}_{c}_t{cid}.png"
                if hfg:
                    hh = cp.single(f"1{b}{c}34{hfg}", cp.mrg_layer(mrg))
                    if hh is not None:
                        hh.save(os.path.join(OUT, f"player/{b}_{c}_th{cid}.png"))
                        out[f"{b}/{c}/th/{cid}"] = f"player/{b}_{c}_th{cid}.png"
            if ok:
                have.append(cls_of[b])
        meta.append({"id": cid, "name": name, "classes": have})
    with open(os.path.join(ROOT, "client", "data", "costumes.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"_note": "特別服裝 (角色面板外觀頁)，由 tools/import_orig_assets.py 生成，唔好手改。classes = 邊啲職業有呢款", "costumes": meta}, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    idx["player_layers"] = out
    print(f"玩家分層: {len(out)} 張")

FX_PICK = {"hit": ("40004E", 12), "spell": ("30516E", 10), "ult": ("22203E", 11), "heal": ("41003E", 15), "levelup": ("41002E", 11)}

def imp_fx(src, idx):
    """特效 (effect.mrg): 每個取頭 N 個有效 frame (後面係雜訊)，按 frame 偏移烘成橫條 strip。
    fx key=名; _fx_meta[名]={n,cw,ch,ax,ay} (ax/ay = 錨點喺 cell 入面位置)"""
    sys.path.insert(0, r"D:/Download/sanguo/tools")
    from mrg_decode import Mrg
    from cp_decode import CP
    from PIL import Image
    m = Mrg(r"D:/Download/zyxy_client/Sanguo_Client/role/effect.mrg")
    ix = {n.split(chr(92))[-1].split(".")[0]: i for i, n in enumerate(m.names)}
    os.makedirs(os.path.join(OUT, "fx"), exist_ok=True)
    out, meta = {}, {}
    for key, (code, lim) in FX_PICK.items():
        c = CP(m.blob(ix[code]))
        fr = [f for f in range(min(c.n, lim)) if c.recs[f][2] > 0]
        ims = [(c.image(f)[0], c.recs[f][0], c.recs[f][1]) for f in fr]
        x0 = min(x for _, x, _y in ims); y0 = min(y for _, _x, y in ims)
        cw = max(x + im.width for im, x, _y in ims) - x0; chh = max(y + im.height for im, _x, y in ims) - y0
        sh = Image.new("RGBA", (cw * len(ims), chh), (0, 0, 0, 0))
        for i, (im, x, y) in enumerate(ims):
            sh.alpha_composite(im, (i * cw + x - x0, y - y0))
        rel = f"fx/{key}.png"
        sh.save(os.path.join(OUT, rel))
        out[key] = rel
        meta[key] = {"n": len(ims), "cw": cw, "ch": chh, "ax": -x0, "ay": -y0}
    idx["fx"] = out
    idx["_fx_meta"] = meta
    print(f"特效: {len(out)} 個")

# 音效: 名 → (mrg, 原名)。名直接對原 mrg 條目名 (見 docs/plan/sprite_layout.md 音效節)
AUDIO_PICK = {
    "bgm_town": ("sounds5", "BGM01"), "bgm_field": ("sounds5", "BGM02"), "bgm_battle": ("sounds5", "BGM03"), "bgm_extra": ("sounds5", "BGM04"),
    "swing": ("sounds4", "20142-0"), "hit": ("sounds4", "20142-D"),
    "spell": ("Sounds3", "30512E"), "ult": ("Sounds3", "22202E"), "heal": ("Sounds3", "41003E"), "levelup": ("Sounds3", "41006E"),
    "click": ("Sounds", "S03"),
}

def imp_audio(src, idx):
    """音效 (Sound/*.mrg 按名抽 RIFF → ogg，需 ffmpeg)"""
    import subprocess, tempfile
    sys.path.insert(0, r"D:/Download/sanguo/tools")
    from mrg_decode import Mrg
    ff = os.environ.get("FFMPEG", r"D:/ffmpeg/ffmpeg-2026-03-12-git-9dc44b43b2-full_build/bin/ffmpeg.exe")
    os.makedirs(os.path.join(OUT, "audio"), exist_ok=True)
    mrgs, out = {}, {}
    for key, (mn, nm) in AUDIO_PICK.items():
        if mn not in mrgs:
            m = Mrg(rf"D:/Download/zyxy_client/Sanguo_Client/Sound/{mn}.mrg")
            mrgs[mn] = (m, {n.split(chr(92))[-1].split(".")[0]: i for i, n in enumerate(m.names)})
        m, ix = mrgs[mn]
        tmp = os.path.join(tempfile.gettempdir(), f"_{key}.wav")
        open(tmp, "wb").write(m.blob(ix[nm]))
        rel = f"audio/{key}.ogg"
        subprocess.run([ff, "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "3", os.path.join(OUT, rel)], check=True)
        out[key] = rel
    idx["audio"] = out
    print(f"音效: {len(out)} 條")

SETS = {"audio": imp_audio, "fx": imp_fx, "player": imp_player_layers, "mount": imp_mount, "actor": imp_actor, "mon": imp_mon, "items": imp_items, "faces": imp_faces, "facelayers": imp_facelayers, "ui": imp_ui}

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
    idx = json.load(open(INDEX, encoding="utf-8")) if os.path.exists(INDEX) and a.sets != ",".join(SETS) else {}
    idx["_note"] = "由 tools/import_orig_assets.py 生成，唔好手改 (單跑部分 --sets 會合併舊索引)"
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
