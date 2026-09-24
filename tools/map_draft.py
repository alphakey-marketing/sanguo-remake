# -*- coding: utf-8 -*-
# 地圖草稿產生器 (spec 12 §2): 用幾何畫法起 data/maps/*.txt 初稿。
# 一次性工具: 起完之後 txt 係正本，可以直接手改；再跑會覆蓋 (要加 --force)。
# 跑: python tools/map_draft.py --force
import os, random, sys
from collections import deque

OUT = os.path.join(os.path.dirname(__file__), "..", "client", "data", "maps")
WALK = set(".,=:_%b+")


class Canvas:
    def __init__(self, w, h, fill="."):
        self.w, self.h = w, h
        self.g = [[fill] * w for _ in range(h)]

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.g[y][x] = c

    def get(self, x, y):
        return self.g[y][x] if 0 <= x < self.w and 0 <= y < self.h else " "

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)

    def ring(self, x0, y0, x1, y1, c, t=1):
        for k in range(t):
            for x in range(x0 + k, x1 - k + 1):
                self.put(x, y0 + k, c)
                self.put(x, y1 - k, c)
            for y in range(y0 + k, y1 - k + 1):
                self.put(x0 + k, y, c)
                self.put(x1 - k, y, c)

    # 粗線 (Bresenham 每點畫 w×w)
    def line(self, x0, y0, x1, y1, c, w=1, only=None):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            for ox in range(w):
                for oy in range(w):
                    if only is None or self.get(x0 + ox, y0 + oy) in only:
                        self.put(x0 + ox, y0 + oy, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def poly(self, pts, c, w=1, only=None):
        for a, b in zip(pts, pts[1:]):
            self.line(a[0], a[1], b[0], b[1], c, w, only)

    # 不規則一團 (樹林/山/草叢): 圓形 + 噪聲
    def blob(self, cx, cy, r, c, rng, dens=0.85, only=None):
        for y in range(cy - r - 1, cy + r + 2):
            for x in range(cx - r - 1, cx + r + 2):
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if d <= r - 0.5 or (d <= r + 0.8 and rng.random() < dens * 0.5):
                    if rng.random() < dens and (only is None or self.get(x, y) in only):
                        self.put(x, y, c)

    def scatter(self, x0, y0, x1, y1, c, p, rng, only="."):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if self.get(x, y) in only and rng.random() < p:
                    self.put(x, y, c)

    # 由 start 行唔到嘅行得格 → 填 fillc (保證全圖連通, spec 12 §7)
    def seal_unreachable(self, start, fillc):
        seen = {start}
        q = deque([start])
        while q:
            x, y = q.popleft()
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if (nx, ny) not in seen and self.get(nx, ny) in WALK:
                    seen.add((nx, ny))
                    q.append((nx, ny))
        n = 0
        for y in range(self.h):
            for x in range(self.w):
                if self.g[y][x] in WALK and (x, y) not in seen:
                    self.g[y][x] = fillc
                    n += 1
        return n

    def save(self, name):
        p = os.path.join(OUT, name + ".txt")
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            for row in self.g:
                f.write("".join(row) + "\n")
        print("wrote", p, self.w, "x", self.h)


# ---------------- 許昌城 72×52 (許都) ----------------
def xuchang():
    rng = random.Random(196)          # 建安元年 遷都許
    c = Canvas(72, 52, ".")
    c.ring(0, 0, 71, 51, "T")                     # 城外樹邊
    c.ring(1, 1, 70, 50, "~")                     # 護城河
    c.ring(3, 3, 68, 48, "#", 2)                  # 城牆 2 厚
    c.rect(5, 5, 66, 46, ":")                     # 城內石板
    # 南門 (唯一開放城門 B1): 城門 + 吊橋 + 出城路
    c.rect(34, 47, 37, 48, "+")
    c.rect(34, 49, 37, 49, "=")
    c.rect(34, 50, 37, 50, "b")
    c.rect(34, 1, 37, 2, "#")                     # 北門 (B2 先開): 城樓畫咗但封住
    c.put(35, 51, "=")                            # 出城口 (傳送點，只得一格)
    # 皇城 (漢獻帝 許都宮)
    c.ring(24, 6, 47, 17, "#")
    c.rect(25, 7, 46, 16, ".")
    c.rect(29, 8, 42, 13, "H")
    c.rect(26, 8, 27, 15, "T")
    c.rect(44, 8, 45, 15, "T")
    c.rect(34, 17, 37, 17, "#")                   # 宮門 (唔畀入)
    # 大街: 南北御道 34..37 + 東西大街 y 25..26 已經係 ":"
    # 住宅/商戶 block (H)，留 1 格巷
    blocks = [
        (6, 6, 12, 10), (14, 6, 21, 10), (50, 6, 56, 10), (58, 6, 65, 10),
        (6, 12, 12, 15), (50, 12, 56, 15), (58, 12, 65, 15),
        (18, 19, 25, 23), (27, 19, 32, 23), (39, 19, 44, 23), (46, 19, 50, 23),
        (52, 18, 58, 22),                         # 私塾
        (6, 28, 12, 33), (20, 28, 26, 31),        # 武器店
        (44, 28, 50, 31),                         # 客棧
        (53, 28, 60, 32), (62, 28, 66, 33),
        (12, 36, 17, 39),                         # 打鐵鋪
        (6, 41, 11, 45), (19, 38, 25, 45),
        (46, 38, 51, 45), (54, 36, 62, 41),       # 寺廟
        (62, 43, 66, 45),
    ]
    for b in blocks:
        c.rect(*b, "H")
    # 練兵場 (空地 + 圍欄樹)
    c.rect(5, 17, 16, 26, "_")
    c.rect(5, 17, 16, 17, "T")
    c.rect(16, 17, 16, 23, "T")
    # 市集廣場 (南門入口)
    c.rect(28, 34, 43, 44, ":")
    for x in (29, 31, 40, 42):                    # 攤檔
        c.put(x, 36, "H")
    # 花園 / 寺前樹
    c.rect(54, 43, 60, 45, ".")
    c.scatter(54, 43, 60, 45, "T", 0.3, rng)
    c.rect(20, 33, 26, 35, ".")
    c.scatter(20, 33, 26, 35, "T", 0.25, rng)
    c.rect(59, 17, 65, 25, ".")
    c.scatter(59, 17, 65, 25, "T", 0.25, rng)
    n = c.seal_unreachable((35, 40), "H")
    print("xuchang sealed", n)
    c.save("xuchang")


# ---------------- 潁川郊外 112×84 (許昌南郊) ----------------
# 測試用練功格 26..46 × 26..46 要開揚 (許田圍場)
def field():
    rng = random.Random(198)
    c = Canvas(112, 84, ".")
    c.ring(0, 0, 111, 83, "T")
    c.ring(1, 1, 110, 82, "T")
    # 北面山 + 西面山邊
    for x in range(2, 110, 5):
        c.blob(x, 2, 2, "^", rng, 0.8)
    for y in range(8, 80, 6):
        c.blob(3, y, 2, "^", rng, 0.7)
    # 許下屯田 (東北田地 + 灌溉渠 + 村屋)
    c.rect(52, 5, 96, 22, "%")
    for x in (62, 74, 86):
        c.line(x, 5, x, 22, "=")                 # 田基路
    c.line(52, 13, 96, 13, "~")                  # 灌溉渠
    for x in (58, 80):
        c.put(x, 13, "b")
    for (x, y) in ((64, 7), (76, 17), (90, 8)):
        c.rect(x, y, x + 2, y + 1, "H")          # 屯田農舍
    # 官道: 北門口 → 十字路口 → 東 (汝南道 B2) / 南 (過潁水 宛城道 B2)
    c.line(40, 0, 40, 24, "=", 2)
    c.line(40, 24, 104, 24, "=", 2)
    c.line(40, 24, 40, 80, "=", 2)
    # 潁水 (東北入、西南出): 遇官道/田基路 = 橋
    river = [(111, 26), (96, 34), (84, 42), (70, 52), (56, 60), (44, 66), (30, 72), (14, 76), (0, 78)]
    rv = Canvas(c.w, c.h, " ")
    rv.poly(river, "~", 3)
    for y in range(c.h):
        for x in range(c.w):
            if rv.g[y][x] == "~":
                c.put(x, y, "b" if c.get(x, y) == "=" else "~")
    # 許田圍場: 開揚草地 + 草叢 (測試區唔放樹)
    c.scatter(10, 26, 50, 60, ",", 0.08, rng)
    for (x, y, r) in ((14, 30, 4), (12, 48, 5), (20, 58, 3), (54, 44, 3), (50, 32, 2)):
        c.blob(x, y, r, "T", rng, 0.8, only=".,")
    c.rect(26, 26, 46, 46, ".")                  # 練功格清空 (runtime 測試用)
    c.scatter(26, 26, 46, 46, ",", 0.06, rng, only=".")
    c.line(40, 24, 40, 50, "=", 2)               # 官道穿過
    # 東面丘陵樹林 (中等怪)
    for (x, y, r) in ((70, 30, 4), (80, 30, 3), (100, 40, 5), (92, 50, 3), (104, 30, 3)):
        c.blob(x, y, r, "T", rng, 0.75, only=".,")
    # 潁水南岸 (高等怪): 石山 + 疏林 + 汝南洞口 (東南)
    for (x, y, r) in ((70, 74, 4), (86, 66, 5), (100, 74, 6), (60, 80, 3)):
        c.blob(x, y, r, "^", rng, 0.8, only=".,")
    c.scatter(50, 60, 108, 80, "T", 0.05, rng)
    c.rect(96, 58, 108, 62, "^")                  # 洞口山
    c.rect(101, 60, 102, 62, "_")                 # 洞口 (傳送點 101,61)
    c.line(84, 60, 101, 61, "=", 1, only=".,T")   # 小路去洞口
    c.line(60, 58, 84, 60, "=", 1, only=".,T")
    # 出口封: 東/南邊 B2 先開，路尾擺路障
    c.rect(104, 24, 109, 25, "=")
    c.rect(110, 24, 110, 25, "T")
    c.rect(40, 80, 41, 81, "=")
    n = c.seal_unreachable((40, 2), "T")
    print("field sealed", n)
    # 北面入口: 只留一格 (傳送點 40,0)
    c.put(41, 0, "T")
    c.put(40, 0, "=")
    c.save("field_1")


# ---------------- 汝南洞窟 10 層 44×26 (元胞自動機 + 保證通道) ----------------
def cave(f):
    rng = random.Random(1000 + f)
    w, h = 44, 26
    c = Canvas(w, h, "^")
    g = [[(rng.random() < 0.42) for _ in range(w)] for _ in range(h)]
    for _ in range(4):
        ng = [[False] * w for _ in range(h)]
        for y in range(h):
            for x in range(w):
                n = sum(1 for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                        if not (0 <= x + dx < w and 0 <= y + dy < h) or g[y + dy][x + dx])
                ng[y][x] = n >= 5
        g = ng
    for y in range(h):
        for x in range(w):
            c.put(x, y, "^" if g[y][x] else "_")
    # 主通道: 左上入口 → 右下出口 (彎路)
    mid = (22, 6 + rng.randrange(14))
    c.poly([(3, 3), (12, 3 + rng.randrange(18)), mid, (32, 3 + rng.randrange(18)), (40, 22)], "_", 2)
    c.rect(2, 2, 5, 5, "_")                       # 上層樓梯位
    c.rect(38, 20, 41, 23, "_")                   # 落層樓梯位
    c.ring(0, 0, w - 1, h - 1, "^")
    c.seal_unreachable((3, 3), "^")
    c.save("runan_f%d" % f)


# ================= B2 (spec 12 §1): 汝南道、昆陽、宛城道、博望坡、新野城 =================
# 入口/出口格 = maps.json portals (地圖內座標)，改呢度要跟住改 portals

# 野外通用: 外圈樹 + 路尾一格出入口
def _field_base(w, h, rng):
    c = Canvas(w, h, ".")
    c.ring(0, 0, w - 1, h - 1, "T")
    c.ring(1, 1, w - 2, h - 2, "T")
    return c


# 河: 沿折線畫 ~，遇路 = 橋
def _river(c, pts, width):
    rv = Canvas(c.w, c.h, " ")
    rv.poly(pts, "~", width)
    for y in range(c.h):
        for x in range(c.w):
            if rv.g[y][x] == "~":
                c.put(x, y, "b" if c.get(x, y) == "=" else "~")


# ---------------- 汝南道 96×40 (潁川東 → 汝南山洞後洞) Lv18~20 ----------------
def runan_road():
    rng = random.Random(200)          # 建安五年 劉辟應袁紹
    c = _field_base(96, 40, rng)
    for x in range(4, 92, 6):
        c.blob(x, 3, 2, "^", rng, 0.7)
        c.blob(x + 2, 36, 2, "T", rng, 0.7)
    # 官道: 西口 (0,20) → 東 → 山洞 (後洞 88,12)
    c.line(0, 20, 60, 20, "=", 2)
    c.poly([(60, 20), (74, 14), (88, 12)], "=", 2)
    c.line(60, 21, 80, 30, "=", 1)                # 岔路去村
    # 汝水支流 (北 → 南)，官道過橋
    _river(c, [(40, 0), (44, 10), (40, 20), (46, 30), (42, 39)], 2)
    # 丘林 (狐貍/花鹿) + 賊寨 (霸盜賊)
    for (x, y, r) in ((14, 10, 4), (24, 30, 4), (54, 8, 3), (58, 32, 3), (30, 12, 3)):
        c.blob(x, y, r, "T", rng, 0.75, only=".,")
    c.scatter(4, 4, 90, 36, ",", 0.07, rng)
    c.ring(74, 24, 88, 34, "T")                   # 賊寨木柵
    c.rect(80, 24, 81, 24, "=")                   # 寨門
    c.rect(76, 26, 78, 27, "H")
    c.rect(83, 30, 86, 31, "H")
    # 山洞口 (後洞)
    c.rect(84, 6, 94, 10, "^")
    c.rect(86, 11, 90, 13, "_")
    c.rect(87, 10, 88, 10, "_")                   # 洞口傳送點 (87,10)
    n = c.seal_unreachable((1, 20), "T")
    print("runan_road sealed", n)
    c.put(0, 21, "T")
    c.put(0, 20, "=")                             # 西口 (傳送點 0,20)
    c.save("runan_road")


# ---------------- 昆陽 90×64 (潁川南 → 宛城道) Lv14~15 ----------------
def kunyang():
    rng = random.Random(23)           # 更始元年 (23) 昆陽之戰
    c = _field_base(90, 64, rng)
    for y in range(6, 60, 6):
        c.blob(86, y, 2, "^", rng, 0.7)
    # 官道: 北口 (45,0) → 昆陽故城 → 西口 (0,40)
    c.line(45, 0, 45, 40, "=", 2)
    c.line(0, 40, 46, 40, "=", 2)
    c.line(46, 40, 70, 56, "=", 1)                # 小路去東南丘
    # 滍水 (西北 → 東南)，官道過橋
    _river(c, [(0, 14), (20, 18), (40, 26), (60, 28), (89, 34)], 3)
    # 昆陽故城 (崩牆)
    c.ring(34, 44, 60, 60, "#")
    c.rect(35, 45, 59, 59, "_")
    for (x0, x1, y0, y1) in ((44, 47, 44, 44), (34, 34, 50, 53), (60, 60, 48, 51), (48, 52, 60, 60)):
        c.rect(x0, y0, x1, y1, ".")               # 缺口
    c.line(45, 41, 45, 44, "=", 2)
    c.rect(38, 47, 41, 49, "H")
    c.rect(52, 53, 56, 55, "H")
    c.scatter(35, 45, 59, 59, "^", 0.05, rng, only="_")
    # 野林 (山羊/瘋貓)
    for (x, y, r) in ((14, 30, 4), (20, 52, 5), (70, 12, 4), (74, 44, 4), (28, 6, 3), (62, 8, 3)):
        c.blob(x, y, r, "T", rng, 0.75, only=".,")
    c.scatter(4, 4, 86, 60, ",", 0.07, rng)
    n = c.seal_unreachable((45, 2), "T")
    print("kunyang sealed", n)
    c.put(46, 0, "T")
    c.put(45, 0, "=")                             # 北口 (傳送點 45,0)
    c.put(0, 41, "T")
    c.put(0, 40, "=")                             # 西口 (傳送點 0,40)
    c.save("kunyang")


# ---------------- 宛城道 96×50 (昆陽 → 博望坡；西面宛城 B3 前封) Lv7~11 ----------------
def wancheng_road():
    rng = random.Random(197)          # 建安二年 宛城之戰
    c = _field_base(96, 50, rng)
    # 官道: 東口 (95,14) → 西 → 宛城東門 (封) ；岔南 → 南口 (60,49) 博望
    c.line(20, 14, 95, 14, "=", 2)
    c.line(60, 14, 60, 49, "=", 2)
    # 淯水 (北 → 南)，官道過橋
    _river(c, [(34, 0), (30, 12), (36, 26), (30, 40), (34, 49)], 3)
    # 宛城東牆 (未開放): 牆 + 封咗嘅城門
    c.rect(2, 2, 8, 47, "#")
    c.rect(9, 2, 9, 47, "~")                      # 護城河
    c.rect(10, 13, 19, 15, "=")
    c.rect(9, 14, 9, 14, "b")
    c.rect(2, 12, 8, 16, "#")
    # 田 + 村 (淯水東岸)
    c.rect(66, 22, 88, 34, "%")
    c.line(66, 28, 88, 28, "=")
    c.rect(70, 36, 73, 37, "H")
    c.rect(80, 37, 83, 38, "H")
    # 樹林 (猴子/山賊)
    for (x, y, r) in ((20, 32, 4), (46, 36, 4), (48, 6, 3), (80, 6, 3), (16, 42, 3), (86, 44, 3)):
        c.blob(x, y, r, "T", rng, 0.75, only=".,")
    c.scatter(10, 4, 92, 46, ",", 0.07, rng)
    n = c.seal_unreachable((94, 14), "T")
    print("wancheng_road sealed", n)
    c.put(95, 15, "T")
    c.put(95, 14, "=")                            # 東口 (傳送點 95,14)
    c.put(61, 49, "T")
    c.put(60, 49, "=")                            # 南口 (傳送點 60,49)
    c.save("wancheng_road")


# ---------------- 博望坡 96×70 (宛城道 → 新野北門) Lv1~9，南低北高 ----------------
def bowang():
    rng = random.Random(208)          # 火燒博望 (演義 建安十三年前)
    c = _field_base(96, 70, rng)
    # 官道: 北口 (48,0) → 狹谷 → 南口 (48,69)
    c.poly([(48, 0), (48, 16), (44, 30), (50, 44), (48, 69)], "=", 2)
    # 博望坡: 兩邊山逼 (中段狹谷)
    for y in range(18, 44, 3):
        c.blob(30, y, 5, "^", rng, 0.8)
        c.blob(64, y, 5, "^", rng, 0.8)
    for (x, y, r) in ((36, 24, 3), (58, 36, 3), (38, 38, 2), (57, 22, 2)):
        c.blob(x, y, r, "T", rng, 0.85, only=".,")   # 谷口蘆葦叢樹
    # 北段 (惡虎/野豬): 疏林
    for (x, y, r) in ((14, 8, 4), (78, 10, 4), (24, 12, 3), (70, 4, 2)):
        c.blob(x, y, r, "T", rng, 0.75, only=".,")
    # 南段 (田鼠/野狗/山賊): 田 + 草地，近新野
    c.rect(8, 50, 34, 62, "%")
    c.line(8, 56, 48, 56, "=")
    c.rect(62, 52, 86, 62, "%")
    c.line(48, 57, 86, 57, "=")
    c.rect(20, 46, 23, 47, "H")
    c.rect(74, 47, 77, 48, "H")
    # 白河支流 (西南角)
    _river(c, [(0, 40), (8, 46), (4, 58), (10, 69)], 2)
    c.scatter(4, 4, 92, 66, ",", 0.07, rng)
    n = c.seal_unreachable((48, 1), "T")
    print("bowang sealed", n)
    c.put(49, 0, "T")
    c.put(48, 0, "=")                             # 北口 (傳送點 48,0)
    c.put(49, 69, "T")
    c.put(48, 69, "=")                            # 南口 (傳送點 48,69)
    c.save("bowang")


# ---------------- 新野城 64×48 (劉備屯兵) ----------------
def xinye():
    rng = random.Random(201)          # 建安六年 劉備屯新野
    c = Canvas(64, 48, ".")
    c.ring(0, 0, 63, 47, "T")
    c.ring(1, 1, 62, 46, "~")                     # 護城河
    c.ring(3, 3, 60, 44, "#", 2)                  # 城牆
    c.rect(5, 5, 58, 42, ":")
    # 北門 (開): 城門 + 吊橋 + 出城口
    c.rect(30, 3, 33, 4, "+")
    c.rect(30, 2, 33, 2, "=")
    c.rect(30, 1, 33, 1, "b")
    c.rect(0, 0, 63, 0, "T")
    c.put(31, 0, "=")                             # 出城口 (傳送點 31,0)
    # 南門 (樊城 B3 先開): 畫咗但封
    c.rect(30, 43, 33, 44, "#")
    # 縣衙 (中北)
    c.ring(22, 8, 41, 17, "#")
    c.rect(23, 9, 40, 16, ".")
    c.rect(26, 9, 37, 13, "H")
    c.rect(30, 17, 33, 17, ":")                   # 衙門 (開)
    c.rect(24, 15, 25, 16, "T")
    c.rect(38, 15, 39, 16, "T")
    # 大街: 南北 30..33、東西 y 22..23 已係 ":"
    blocks = [
        (6, 6, 12, 10), (14, 6, 19, 10), (44, 6, 50, 10), (52, 6, 57, 10),
        (6, 13, 12, 17), (45, 13, 50, 17), (52, 13, 57, 17),
        (6, 25, 12, 28),                          # 防具店
        (16, 25, 22, 28),                         # 武器店
        (40, 25, 46, 28),                         # 客棧
        (49, 25, 57, 29),
        (6, 33, 12, 40), (16, 34, 24, 40), (40, 34, 47, 40), (50, 33, 57, 40),
    ]
    for b in blocks:
        c.rect(*b, "H")
    # 城南空地 (練兵) + 樹
    c.rect(27, 33, 36, 40, "_")
    c.rect(52, 19, 57, 22, ".")
    c.scatter(52, 19, 57, 22, "T", 0.3, rng)
    n = c.seal_unreachable((31, 20), "H")
    print("xinye sealed", n)
    c.save("xinye")


B2 = {"runan_road": runan_road, "kunyang": kunyang, "wancheng_road": wancheng_road, "bowang": bowang, "xinye": xinye}


if __name__ == "__main__":
    if "--force" not in sys.argv:
        sys.exit("會覆蓋 data/maps/*.txt，確定就加 --force (--b2 = 只起 B2 五張)")
    os.makedirs(OUT, exist_ok=True)
    if "--b2" in sys.argv:
        for fn in B2.values():
            fn()
        sys.exit(0)
    xuchang()
    field()
    for f in range(1, 11):
        cave(f)
