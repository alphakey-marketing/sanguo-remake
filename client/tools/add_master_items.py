"""S05c 大宗師合成術：一次性新增材料/寶石/寶物入 items.json（冇 recipes 欄，配方喺 master_recipes.json）。
執行一次後唔好再跑（idempotent：已存在 id 就跳過）。
"""
import json

PATH = "items.json"


def blank(id_, name, cat, cat_label, price, u24=1, weight=1):
    return {
        "id": id_, "name": name, "cat": cat, "cat_label": cat_label,
        "template": id_, "price": price, "u24": u24, "weight": weight, "b28": weight,
        "req_lv": 0, "pet_req_lv": 0, "pet_req_loyal": 0,
        "craft_kind": 0, "craft_lv": 0, "effects": [],
        "req_a": [0, 0, 0], "req_b": [0, 0, 0],
        "b47": 0, "b48": 0, "b49": 0, "b53": 250,
        "b54_59": [0, 1, 0, 2, 0, 0],
        "materials": [], "w76": 0, "w78": 0, "b80": 0,
    }


NEW = []
MAT_CAT, MAT_LABEL = 46, "大宗師材料"
GEM_CAT, GEM_LABEL = 224, "大宗師寶石"
TRE_CAT, TRE_LABEL = 225, "大宗師寶物"

# 新初階材料（御賜工具 + 指定產出地，spec §5）
BASIC = {
    26075: "黃金稻穗",   # 農耕
    26076: "飛天龍魚",   # 捕魚
    26077: "荒野虎肉",   # 打獵
    26078: "璀璨晶礦",   # 挖礦
    26079: "鐵樹精華",   # 伐木
    26080: "九命人參",   # 採藥
}
# 新進階材料
ADV = {
    26081: "茗香泉水",   # 廚藝
    26082: "煉獄礦石",   # 冶鐵
    26083: "雪羽晶塊",   # 修繕
    26084: "天山樹鬚",   # 木匠
    26085: "不老丹藥",   # 煉丹
}
BAIZHU = {26086: "白晝之珠"}
GEMS = {
    26087: "扈江之石",   # 廚藝
    26088: "玄牝之石",   # 煉丹
    26089: "炎冥之石",   # 冶鐵
    26090: "仲卿之石",   # 修繕
    26091: "山淵之石",   # 木匠
}
TREASURES = {
    26092: "龍威寶鼎",
    26093: "玄靈仙丹",
    26094: "焚天神鎚",
    26095: "山嶽玄鉉",
    26096: "淵匠靈刨",
}

for i, n in BASIC.items():
    NEW.append(blank(i, n, MAT_CAT, MAT_LABEL, 0))
for i, n in ADV.items():
    NEW.append(blank(i, n, MAT_CAT, MAT_LABEL, 0))
for i, n in BAIZHU.items():
    NEW.append(blank(i, n, MAT_CAT, MAT_LABEL, 0))
for i, n in GEMS.items():
    NEW.append(blank(i, n, GEM_CAT, GEM_LABEL, 0))
for i, n in TREASURES.items():
    NEW.append(blank(i, n, TRE_CAT, TRE_LABEL, 50000))

data = json.load(open(PATH, encoding="utf-8"))
existing = {int(x["id"]) for x in data}
to_add = [item for item in NEW if item["id"] not in existing]

raw = open(PATH, encoding="utf-8").read()
end = raw.rstrip()
assert end.endswith("]")
body = end[:-1].rstrip()
assert body.endswith("}")

pieces = []
for item in to_add:
    pieces.append(json.dumps(item, ensure_ascii=False, indent=1))

out = body + ",\n " + ",\n ".join(pieces) + "\n]\n"
open(PATH, "w", encoding="utf-8", newline="\n").write(out)
print("added", len(to_add), "total", len(data) + len(to_add))
