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
    # 北門 (B2.5 開): 城門 + 吊橋 + 出城口 → 陳留郊外
    c.rect(34, 3, 37, 4, "+")
    c.rect(34, 2, 37, 2, "=")
    c.rect(34, 1, 37, 1, "b")
    c.put(35, 0, "=")                             # 北出城口 (傳送點 35,0)
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
    c.line(60, 20, 95, 20, "=", 1)                # 東口 → 汝南城 (B2.5，傳送點 95,20)
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
    c.rect(2, 14, 8, 14, "+")                     # 宛城東門 (B2.5 開，傳送點 2,14)
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
    # 南門 (B2.5 開) → 樊城
    c.rect(30, 43, 33, 44, "+")
    c.rect(30, 45, 33, 45, "=")
    c.rect(30, 46, 33, 46, "b")
    c.put(31, 47, "=")                            # 南出城口 (傳送點 31,47)
    # 西門 (B2.5 開) → 荊州地界
    c.rect(3, 22, 4, 23, "+")
    c.rect(2, 22, 2, 23, "=")
    c.rect(1, 22, 1, 23, "b")
    c.put(0, 22, "=")                             # 西出城口 (傳送點 0,22)
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


# ================= B2.5 (Step 16 前置): 歷史任務地點 + 襄陽 (B3 提前) =================
# 陳留郊外/于毒山寨/小沛 (許昌北)、汝南城/丁刺史府 (汝南道東)、宛城 (宛城道西)、
# 荊州地界/港口 (新野西)、樊城/漢水渡口/襄陽城/襄陽監獄/長沙 (新野南)
# 傳送點座標 = maps.json portals，改呢度要跟住改

# 城: 外圈樹 + 護城河 + 雙層城牆 + 石板街；gates = [(邊 N/S/W/E, 沿邊位置)]
# 出城口 (傳送點): N = (p+1, 0)、S = (p+1, h-1)、W = (0, p)、E = (w-1, p)
def _city_base(w, h, gates):
    c = Canvas(w, h, ".")
    c.ring(0, 0, w - 1, h - 1, "T")
    c.ring(1, 1, w - 2, h - 2, "~")
    c.ring(3, 3, w - 4, h - 4, "#", 2)
    c.rect(5, 5, w - 6, h - 6, ":")
    for side, p in gates:
        if side == "N":
            c.rect(p, 3, p + 3, 4, "+")
            c.rect(p, 2, p + 3, 2, "=")
            c.rect(p, 1, p + 3, 1, "b")
            c.put(p + 1, 0, "=")
        elif side == "S":
            c.rect(p, h - 5, p + 3, h - 4, "+")
            c.rect(p, h - 3, p + 3, h - 3, "=")
            c.rect(p, h - 2, p + 3, h - 2, "b")
            c.put(p + 1, h - 1, "=")
        elif side == "W":
            c.rect(3, p, 4, p + 1, "+")
            c.rect(2, p, 2, p + 1, "=")
            c.rect(1, p, 1, p + 1, "b")
            c.put(0, p, "=")
        elif side == "E":
            c.rect(w - 5, p, w - 4, p + 1, "+")
            c.rect(w - 3, p, w - 3, p + 1, "=")
            c.rect(w - 2, p, w - 2, p + 1, "b")
            c.put(w - 1, p, "=")
    return c


# ---------------- 陳留郊外 96×56 (許昌北門 → 陳留城門口；西 = 于毒山寨、東 = 小沛) Lv9~20 ----------------
def chenliu():
    rng = random.Random(189)          # 中平六年 曹操陳留起兵
    c = _field_base(96, 56, rng)
    # 陳留城南牆 (城未開放): 牆 + 護城河 + 吊橋 + 城門口空地 (曹操)
    c.rect(20, 2, 76, 7, "#")
    c.rect(20, 8, 76, 8, "~")
    c.rect(44, 8, 51, 8, "b")
    c.rect(38, 9, 57, 13, "_")
    # 官道: 南口 (48,55) → 城門口；東西大路 y=30
    c.line(47, 14, 47, 55, "=", 2)
    c.line(0, 30, 95, 30, "=", 2)
    # 汴水支流 (北 → 南)，大路過橋
    _river(c, [(70, 9), (66, 20), (72, 34), (68, 45), (74, 55)], 2)
    for (x, y, r) in ((12, 18, 4), (28, 44, 4), (60, 42, 3), (86, 16, 4), (84, 46, 3), (30, 18, 3)):
        c.blob(x, y, r, "T", rng, 0.75, only=".,")
    c.rect(56, 17, 59, 18, "H")
    c.rect(22, 36, 25, 37, "H")
    c.scatter(4, 10, 92, 52, ",", 0.07, rng)
    n = c.seal_unreachable((48, 54), "T")
    print("chenliu sealed", n)
    c.put(47, 55, "T")
    c.put(48, 55, "=")                            # 南口 (傳送點 48,55)
    c.put(0, 31, "T")
    c.put(0, 30, "=")                             # 西口 (傳送點 0,30)
    c.put(95, 31, "T")
    c.put(95, 30, "=")                            # 東口 (傳送點 95,30)
    c.save("chenliu")


# ---------------- 于毒山寨 72×50 (陳留西；東口入) Lv11~14 ----------------
def yudu():
    rng = random.Random(191)          # 初平二年 于毒寇東郡
    c = _field_base(72, 50, rng)
    for x in range(4, 70, 5):
        c.blob(x, 4, 3, "^", rng, 0.8)
        c.blob(x + 2, 45, 3, "^", rng, 0.8)
    # 山路: 東口 (71,25) → 寨門
    c.poly([(71, 25), (56, 21), (44, 28), (28, 25)], "=", 2)
    # 山寨: 木柵 + 寨門 + 聚義廳 + 營房
    c.ring(4, 12, 26, 38, "T")
    c.rect(5, 13, 25, 37, "_")
    c.rect(26, 24, 26, 26, "=")                   # 寨門
    c.rect(6, 20, 10, 30, "H")                    # 聚義廳
    c.rect(15, 14, 19, 16, "H")
    c.rect(15, 34, 19, 36, "H")
    c.rect(21, 14, 24, 15, "H")
    c.rect(21, 35, 24, 36, "H")
    for (x, y, r) in ((36, 14, 3), (50, 36, 4), (62, 12, 3), (38, 38, 3)):
        c.blob(x, y, r, "T", rng, 0.75, only=".,")
    c.scatter(28, 8, 68, 42, ",", 0.07, rng)
    n = c.seal_unreachable((70, 25), "T")
    print("yudu sealed", n)
    c.put(71, 26, "T")
    c.put(71, 25, "=")                            # 東口 (傳送點 71,25)
    c.save("yudu")


# ---------------- 小沛城 48×36 (城門口一帶；陳留東) ----------------
def xiaopei():
    rng = random.Random(196)          # 建安元年 轅門射戟
    c = _city_base(48, 36, [("W", 17)])
    for b in ((8, 6, 16, 11), (20, 6, 28, 11), (32, 6, 42, 11), (8, 22, 16, 29), (22, 24, 28, 29), (32, 22, 42, 29)):
        c.rect(*b, "H")
    c.rect(34, 14, 40, 18, "_")                   # 轅門校場
    c.scatter(20, 13, 30, 19, "T", 0.08, rng, only=":")
    n = c.seal_unreachable((6, 17), "H")
    print("xiaopei sealed", n)
    c.save("xiaopei")


# ---------------- 汝南城 64×52 (汝南道東；李府、丁刺史府) ----------------
def runan_city():
    rng = random.Random(184)          # 中平元年 汝南黃巾
    c = _city_base(64, 52, [("W", 24)])
    # 丁刺史府 (東北): 圍牆 + 前庭 + 府門 (→ 室內)
    c.ring(40, 6, 57, 18, "#")
    c.rect(41, 7, 56, 17, ".")
    c.rect(44, 8, 53, 13, "H")
    c.put(48, 13, "+")                            # 府門 (傳送點 48,13)
    c.rect(47, 18, 50, 18, ":")
    c.rect(42, 15, 43, 16, "T")
    c.rect(54, 15, 55, 16, "T")
    # 李府 (西北) + 民房
    c.rect(8, 6, 18, 11, "H")
    c.rect(22, 6, 32, 11, "H")
    c.rect(8, 15, 18, 20, "H")
    c.rect(22, 15, 32, 20, "H")
    # 商店街 (大街 y 24..25 以南)
    c.rect(8, 29, 14, 34, "H")                    # 武器店
    c.rect(18, 29, 24, 34, "H")                   # 防具店
    c.rect(36, 29, 44, 34, "H")                   # 客棧
    c.rect(48, 29, 57, 34, "H")
    for b in ((8, 39, 18, 46), (22, 39, 32, 46), (38, 39, 46, 46), (50, 39, 57, 46)):
        c.rect(*b, "H")
    c.scatter(48, 22, 57, 26, "T", 0.1, rng, only=":")
    n = c.seal_unreachable((6, 24), "H")
    print("runan_city sealed", n)
    c.save("runan_city")


# ---------------- 丁刺史府 32×20 (室內) ----------------
def ding_fu():
    c = Canvas(32, 20, "_")
    c.ring(0, 0, 31, 19, "#")
    c.rect(4, 2, 27, 5, "H")                      # 正堂
    c.rect(2, 8, 5, 11, "H")                      # 廂房
    c.rect(26, 8, 29, 11, "H")
    c.rect(10, 9, 11, 10, "T")                    # 庭樹
    c.rect(20, 9, 21, 10, "T")
    c.put(16, 19, "+")                            # 府門 (傳送點 16,19)
    c.save("ding_fu")


# ---------------- 宛城 72×56 (宛城道西；牌樓、王允) ----------------
def wancheng():
    rng = random.Random(197)          # 建安二年 宛城之戰
    c = _city_base(72, 56, [("E", 26)])
    for b in ((6, 6, 14, 11), (18, 6, 28, 11), (42, 6, 52, 11), (56, 6, 65, 11),
              (6, 15, 14, 21), (18, 15, 28, 21), (42, 15, 52, 21), (56, 15, 65, 21),
              (6, 32, 14, 37),                    # 武器店
              (18, 32, 26, 37),                   # 防具店
              (44, 32, 54, 37),                   # 客棧
              (58, 32, 65, 37),
              (6, 42, 20, 49), (24, 42, 34, 49), (40, 42, 52, 49), (56, 42, 65, 49)):
        c.rect(*b, "H")
    # 牌樓廣場 (中央) + 石柱
    c.rect(31, 23, 40, 30, "_")
    for (x, y) in ((32, 24), (39, 24), (32, 29), (39, 29)):
        c.put(x, y, "^")
    n = c.seal_unreachable((60, 26), "H")
    print("wancheng sealed", n)
    c.save("wancheng")


# ---------------- 荊州地界 96×50 (新野西門 → 西南 港口) Lv9~11 ----------------
def jingzhou():
    rng = random.Random(187)          # 中平四年 孫堅為長沙太守
    c = _field_base(96, 50, rng)
    c.line(40, 20, 95, 20, "=", 2)
    c.poly([(40, 20), (24, 30), (10, 40), (0, 44)], "=", 2)
    _river(c, [(60, 0), (56, 12), (62, 26), (58, 38), (64, 49)], 3)
    for (x, y, r) in ((14, 10, 4), (30, 8, 3), (44, 40, 4), (80, 8, 3), (84, 40, 4), (26, 44, 2)):
        c.blob(x, y, r, "T", rng, 0.75, only=".,")
    c.rect(70, 30, 73, 31, "H")
    c.rect(78, 33, 81, 34, "H")
    c.rect(66, 36, 88, 44, "%")
    c.scatter(4, 4, 92, 46, ",", 0.07, rng)
    n = c.seal_unreachable((94, 20), "T")
    print("jingzhou sealed", n)
    c.put(95, 21, "T")
    c.put(95, 20, "=")                            # 東口 (傳送點 95,20)
    c.put(0, 45, "T")
    c.put(0, 44, "=")                             # 西南口 (傳送點 0,44)
    c.save("jingzhou")


# ---------------- 港口 80×50 (荊州地界西南；海濱、渡船處) Lv12~15 ----------------
def gangkou():
    rng = random.Random(172)          # 熹平元年 孫堅十七歲斬海賊胡玉
    c = _field_base(80, 50, rng)
    # 海: 南面 + 西面，岸線唔規則
    c.rect(2, 34, 77, 47, "~")
    c.rect(2, 2, 12, 33, "~")
    for x in range(14, 76, 5):
        c.blob(x, 34, 2, "~", rng, 0.7)
    for y in range(6, 32, 5):
        c.blob(13, y, 2, "~", rng, 0.7)
    # 碼頭 (棧橋) + 渡船處 (中間棧橋盡頭)
    c.rect(24, 30, 26, 40, "b")
    c.rect(44, 30, 46, 43, "b")
    c.rect(41, 43, 49, 45, "b")                   # 渡船處
    c.rect(62, 30, 64, 39, "b")
    # 路: 東北口 (79,6) → 碼頭
    c.poly([(79, 6), (58, 12), (46, 22), (45, 30)], "=", 2)
    c.line(24, 28, 64, 28, "=", 1)
    # 貨倉
    c.rect(30, 14, 34, 17, "H")
    c.rect(54, 18, 58, 21, "H")
    c.rect(20, 20, 24, 23, "H")
    c.rect(66, 22, 70, 24, "H")
    for (x, y, r) in ((70, 12, 3), (24, 8, 3), (40, 6, 2)):
        c.blob(x, y, r, "T", rng, 0.75, only=".,")
    c.scatter(14, 4, 76, 32, ",", 0.05, rng)
    n = c.seal_unreachable((78, 6), "T")
    print("gangkou sealed", n)
    c.put(79, 7, "T")
    c.put(79, 6, "=")                             # 東北口 (傳送點 79,6)
    c.save("gangkou")


# ---------------- 樊城 96×60 (新野南門 → 漢水渡口；樊城城池未開) Lv11~14 ----------------
def fancheng():
    rng = random.Random(219)          # 建安二十四年 關羽水淹七軍圍樊城
    c = _field_base(96, 60, rng)
    c.poly([(48, 0), (48, 18), (40, 34), (48, 59)], "=", 2)
    # 樊城 (東面，未開放): 城牆 + 護城河 + 封門
    c.rect(68, 12, 90, 44, "#")
    c.rect(66, 12, 67, 44, "~")
    c.line(44, 28, 65, 28, "=", 1)
    c.put(66, 28, "b")
    c.put(67, 28, "b")
    c.rect(8, 40, 30, 52, "%")
    c.line(8, 46, 42, 46, "=", 1)
    c.rect(14, 36, 17, 37, "H")
    for (x, y, r) in ((14, 10, 4), (28, 22, 3), (60, 6, 3), (58, 50, 4), (80, 52, 3), (84, 6, 3)):
        c.blob(x, y, r, "T", rng, 0.75, only=".,")
    c.scatter(4, 4, 92, 56, ",", 0.07, rng)
    n = c.seal_unreachable((48, 1), "T")
    print("fancheng sealed", n)
    c.put(49, 0, "T")
    c.put(48, 0, "=")                             # 北口 (傳送點 48,0)
    c.put(49, 59, "T")
    c.put(48, 59, "=")                            # 南口 (傳送點 48,59)
    c.save("fancheng")


# ---------------- 漢水渡口 80×44 (樊城 → 渡漢水 → 襄陽北門) Lv16~20 ----------------
def hanshui():
    rng = random.Random(208)          # 建安十三年 劉備攜民渡漢水
    c = _field_base(80, 44, rng)
    c.line(40, 0, 40, 43, "=", 2)
    _river(c, [(0, 20), (20, 18), (40, 22), (60, 19), (79, 21)], 5)
    c.rect(34, 12, 47, 14, "_")                   # 北岸碼頭
    c.rect(34, 28, 47, 30, "_")                   # 南岸碼頭
    c.rect(30, 8, 33, 10, "H")
    c.rect(48, 8, 51, 10, "H")
    c.rect(30, 32, 33, 34, "H")
    for (x, y, r) in ((12, 6, 3), (66, 6, 3), (14, 36, 3), (64, 36, 4)):
        c.blob(x, y, r, "T", rng, 0.75, only=".,")
    c.scatter(4, 4, 76, 40, ",", 0.07, rng)
    n = c.seal_unreachable((40, 1), "T")
    print("hanshui sealed", n)
    c.put(41, 0, "T")
    c.put(40, 0, "=")                             # 北口 (傳送點 40,0)
    c.put(41, 43, "T")
    c.put(40, 43, "=")                            # 南口 (傳送點 40,43)
    c.save("hanshui")


# ---------------- 襄陽城 76×60 (漢水南；宮宅、監獄；南門 → 長沙) ----------------
def xiangyang():
    rng = random.Random(190)          # 初平元年 劉表單騎入荊州，治襄陽
    c = _city_base(76, 60, [("N", 36), ("S", 36), ("W", 24)])   # W = 隆中 (B3)
    # 宮宅 (中北)
    c.ring(26, 8, 49, 19, "#")
    c.rect(27, 9, 48, 18, ".")
    c.rect(30, 9, 45, 14, "H")
    c.rect(36, 19, 39, 19, ":")
    c.rect(28, 16, 29, 17, "T")
    c.rect(46, 16, 47, 17, "T")
    # 監獄 (西南): 圍牆 + 獄門 (→ 室內)
    c.ring(6, 40, 22, 53, "#")
    c.rect(7, 41, 21, 52, "_")
    c.rect(9, 43, 19, 48, "H")
    c.put(14, 48, "+")                            # 獄門 (傳送點 14,48)
    c.rect(13, 53, 15, 53, ":")
    for b in ((6, 6, 14, 11), (16, 6, 22, 11), (54, 6, 62, 11), (64, 6, 69, 11),
              (6, 15, 14, 22), (54, 15, 62, 22), (64, 15, 69, 22),
              (6, 26, 14, 32),                    # 武器店
              (16, 26, 24, 32),                   # 防具店
              (50, 26, 58, 32),                   # 客棧
              (60, 26, 69, 32),
              (28, 40, 34, 50), (42, 40, 48, 50), (52, 40, 60, 50), (62, 40, 69, 50)):
        c.rect(*b, "H")
    c.scatter(26, 22, 34, 34, "T", 0.06, rng, only=":")
    n = c.seal_unreachable((37, 24), "H")
    print("xiangyang sealed", n)
    c.save("xiangyang")


# ---------------- 襄陽監獄 36×22 (室內) ----------------
def xy_prison():
    c = Canvas(36, 22, "_")
    c.ring(0, 0, 35, 21, "#")
    for x in range(3, 33, 6):
        c.rect(x, 3, x + 3, 6, "H")               # 牢房 (北排)
        c.rect(x, 15, x + 3, 18, "H")             # 牢房 (南排)
    c.rect(2, 9, 4, 11, "H")                      # 獄卒桌
    c.put(18, 0, "+")                             # 獄門 (傳送點 18,0)
    c.save("xy_prison")


# ---------------- 長沙城 48×36 (城門口一帶；賭場) ----------------
def changsha():
    rng = random.Random(187)          # 孫堅長沙太守
    c = _city_base(48, 36, [("N", 22)])
    for b in ((6, 8, 16, 14),                    # 賭場
              (30, 8, 42, 14), (6, 20, 16, 29), (20, 22, 28, 29), (32, 20, 42, 29)):
        c.rect(*b, "H")
    c.scatter(18, 14, 28, 19, "T", 0.08, rng, only=":")
    n = c.seal_unreachable((23, 6), "H")
    print("changsha sealed", n)
    c.save("changsha")


# ================= B3 (spec 12 §1): 隆中 + 草廬 =================
# ---------------- 隆中 72×50 (襄陽西門外；臥龍岡、草廬、竹林、隴畝) Lv14~18 ----------------
def longzhong():
    rng = random.Random(207)          # 建安十二年 三顧茅廬
    c = _field_base(72, 50, rng)
    # 官道: 東口 (71,25) → 岡下
    c.poly([(71, 25), (52, 25), (40, 30), (30, 30)], "=", 2)
    # 臥龍岡 (西北): 山環 + 上岡小徑 + 草廬前院 + 門 (→ 室內)
    c.blob(16, 14, 11, "^", rng, 0.9)
    c.rect(9, 8, 22, 18, "_")
    c.rect(12, 9, 19, 13, "H")
    c.put(15, 13, "+")                            # 草廬門 (傳送點 15,13)
    c.rect(10, 16, 11, 17, "T")
    c.rect(20, 16, 21, 17, "T")
    c.poly([(16, 18), (16, 26), (22, 30), (30, 30)], "=", 2)
    # 竹林 (東北)
    for (x, y, r) in ((44, 8, 5), (58, 10, 4), (52, 16, 3)):
        c.blob(x, y, r, "T", rng, 0.7, only=".,")
    # 隴畝 (南): 躬耕田
    c.rect(10, 36, 26, 44, "%")
    c.rect(30, 38, 40, 44, "%")
    c.rect(28, 34, 29, 45, "=")
    # 小溪 (北 → 南)，官道過橋
    _river(c, [(62, 2), (60, 14), (64, 26), (58, 38), (62, 47)], 2)
    c.rect(4, 30, 6, 32, "H")                     # 農舍
    c.rect(44, 40, 47, 42, "H")
    c.scatter(4, 4, 68, 46, ",", 0.07, rng)
    n = c.seal_unreachable((70, 25), "T")
    print("longzhong sealed", n)
    c.put(71, 26, "T")
    c.put(71, 25, "=")                            # 東口 (傳送點 71,25)
    c.save("longzhong")


# ---------------- 草廬 28×18 (室內) ----------------
def caolu():
    c = Canvas(28, 18, "_")
    c.ring(0, 0, 27, 17, "#")
    c.rect(3, 2, 10, 3, "H")                      # 書架
    c.rect(17, 2, 24, 3, "H")
    c.rect(12, 7, 15, 8, "H")                     # 書案
    c.rect(2, 12, 3, 14, "T")                     # 盆景
    c.rect(24, 12, 25, 14, "T")
    c.put(14, 17, "+")                            # 門 (傳送點 14,17)
    c.save("caolu")


B3 = {"longzhong": longzhong, "caolu": caolu}


B25 = {"chenliu": chenliu, "yudu": yudu, "xiaopei": xiaopei, "runan_city": runan_city, "ding_fu": ding_fu,
       "wancheng": wancheng, "jingzhou": jingzhou, "gangkou": gangkou, "fancheng": fancheng,
       "hanshui": hanshui, "xiangyang": xiangyang, "xy_prison": xy_prison, "changsha": changsha}


if __name__ == "__main__":
    if "--force" not in sys.argv:
        sys.exit("會覆蓋 data/maps/*.txt，確定就加 --force (--b2 = 只起 B2 五張；--b25 = 只起 B2.5 十三張；--b3 = 只起隆中/草廬)")
    os.makedirs(OUT, exist_ok=True)
    if "--b3" in sys.argv:
        for fn in B3.values():
            fn()
        sys.exit(0)
    if "--b25" in sys.argv:
        for fn in B25.values():
            fn()
        sys.exit(0)
    if "--b2" in sys.argv:
        for fn in B2.values():
            fn()
        sys.exit(0)
    xuchang()
    field()
    for f in range(1, 11):
        cave(f)
