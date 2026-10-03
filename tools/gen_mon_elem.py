# 怪物屬性規則表【自訂，用家 2026-10-02 授權我定】
# 按怪名關鍵字派風/地/水/火；冇中 = 無屬性。輸出 client/data/mon_elem.json {id: element}
# 只補 monsters.json 內 element 係 none/空嘅怪 (已有屬性嘅唔改)。跑: python tools/gen_mon_elem.py
import json, sys

RULES = [  # 先中先得
    ("fire", ["妖法師", "煉獄", "地獄", "午日", "南方虎", "紅魔", "橙魔", "紅寨", "紅衣", "紅髮", "紅菁", "黃蜂", "蜥蜴", "烈", "火"]),
    ("water", ["水鴨", "蟾蜍", "蜻蜓", "寒屍", "北方虎", "藍魔", "靛魔", "藍寨", "黑寨", "蛆", "水"]),
    ("wind", ["蝙蝠", "蛾", "蝴蝶", "狐蝠", "西方虎", "東方虎", "神鷹", "綠魔", "綠寨", "箭魔", "狼", "弒狼", "紫魔", "飛賊", "貂", "兔", "雞"]),
    ("earth", ["殭屍", "木乃伊", "骷髏", "鐵樹", "樹鬚", "野豬", "野牛", "熊", "螞蟻", "蠍", "黃金鼠", "紫晶", "黃魔", "田鼠", "大蟒", "蜘蛛", "鬼域", "山羊", "花鹿", "猴子"]),
]

def elem_of(name: str) -> str:
    for el, kws in RULES:
        for k in kws:
            if k in name:
                return el
    return "none"

if __name__ == "__main__":
    m = json.load(open("client/data/monsters.json", encoding="utf8"))
    L = m.get("monsters", m)
    out = {}
    for x in L:
        if str(x.get("element") or "none") != "none":
            continue
        e = elem_of(x["name"])
        if e != "none":
            out[str(x["id"])] = e
    json.dump(out, open("client/data/mon_elem.json", "w", encoding="utf8"), ensure_ascii=False, indent=1)
    from collections import Counter
    print(len(out), "/", len(L), Counter(out.values()))
