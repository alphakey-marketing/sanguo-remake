# -*- coding: utf-8 -*-
"""合併 docs/guide/ 攻略原文細檔成主題大檔。
每合併檔保留每頁 "# 標題" + "# http://...url" 做分隔（加 blank line），唔遺失出處。
用法: python tools/merge_guide.py
"""
import os

GUIDE = os.path.join(os.path.dirname(__file__), "..", "docs", "guide")
GUIDE = os.path.abspath(GUIDE)

# group -> 新檔名 : [原 file stem ...]（順序保持）
GROUPS = {
    "sy1_1_system.txt":        [["sy1_1_1"], ["sy1_1_2"], ["sy1_1_3_1"], ["sy1_1_3_2"]],
    "sy1_2_beginner.txt":      [["sy1_2_1"], ["sy1_2_2"], ["sy1_2_3"]],
    "sy1_2_class_guides.txt":  [["sy1_2_4"], ["sy1_2_5"], ["sy1_2_6"], ["sy1_2_7"], ["sy1_2_8"], ["sy1_2_9"]],
    "sy1_2_misc.txt":          [["sy1_2_10"], ["sy1_2_11"]],
    "sy2_1_class_attr.txt":    [["sy2_1_1"], ["sy2_1_2"], ["sy2_1_3"], ["sy2_1_4"]],
    "sy2_2_skill.txt":         [["sy2_2_1"], ["sy2_2_2"], ["sy2_2_3"]],
    "sy2_2_market_master.txt":[["sy2_2_4"], ["sy2_2_5"]],
    "sy2_3_disaster.txt":      [["sy2_3_1"], ["sy2_3_2"], ["sy2_3_3"]],
    "sy2_4_mount.txt":         [["sy2_4_%d" % i] for i in range(1, 8)],
    "sy2_5_warbeast.txt":      [["sy2_5_%d" % i] for i in range(1, 8)],
    "sy2_6_recruit.txt":       [["sy2_6_%d" % i] for i in range(1, 7)],
    "sy2_7_marry.txt":         [["sy2_7_1"], ["sy2_7_2"], ["sy2_7_3"], ["sy2_7_6"]],
    "sy2_8_militia.txt":       [["sy2_8_1"], ["sy2_8_2"], ["sy2_8_3"], ["sy2_8_4"], ["sy2_8_5"], ["sy2_8_6"], ["sy2_8_7"], ["sy2_8_8"], ["sy2_8_12"], ["sy2_8_14"]],
    "sy2_9_rules.txt":         [["sy2_9_1"], ["sy2_9_2"], ["sy2_9_21"], ["sy2_9_24"]],
    "sy2_9_battles.txt":       [["sy2_9_3"], ["sy2_9_4"], ["sy2_9_5"], ["sy2_9_6"], ["sy2_9_8"], ["sy2_9_10"], ["sy2_9_12"], ["sy2_9_13"], ["sy2_9_19"]],
    "sy2_10_gear.txt":         [["sy2_10_%d" % i] for i in range(1, 7)],
    "sy2_11_map.txt":          [["sy2_11_%d" % i] for i in range(1, 5)],
    "sy2_12_monster.txt":      [["sy2_12_1"], ["sy2_12_2"]],
    "sy2_13_promote.txt":      [["sy2_13_1"], ["sy2_13_2"]],
    "sy2_14_fortune.txt":      [["sy2_14"]],
    "sy2_15_virtual.txt":      [["sy2_15"]],
    "sy3_quests.txt":          [["sy3_1"], ["sy3_3"], ["sy3_4"], ["sy3_5"]],
    "sy3_6_skills.txt":        [["sy3_6_%d" % i] for i in range(1, 7)],
    "sy3_8_task.txt":          [["sy3_8"]],
    "sy3_9_expert.txt":        [["sy3_9_1"], ["sy3_9_2"]],
    "sy3_10_scene.txt":        [["sy3_10_%d" % i] for i in range(1, 8)],
    "sy4_shop.txt":            [["sy4_1"], ["sy4_1_go1_cla10"], ["sy4_3"]],
}

def read_page(stem):
    path = os.path.join(GUIDE, stem + ".txt")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return f.read()

def main():
    for new, stems in GROUPS.items():
        parts = []
        for stem in stems:
            s = stem[0]
            content = read_page(s)
            if content is None:
                print("!! 缺: %s" % s)
                continue
            parts.append(content.strip())
        newpath = os.path.join(GUIDE, new)
        with open(newpath, "w", encoding="utf-8") as f:
            f.write("\n\n\n=== === ===\n\n".join(parts) + "\n")
        for stem in stems:
            s = stem[0]
            p = os.path.join(GUIDE, s + ".txt")
            if os.path.exists(p):
                os.remove(p)
        print("OK %s <- %s" % (new, ", ".join(s[0] for s in stems)))

if __name__ == "__main__":
    main()