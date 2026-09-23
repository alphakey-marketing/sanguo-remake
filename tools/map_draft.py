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


if __name__ == "__main__":
    if "--force" not in sys.argv:
        sys.exit("會覆蓋 data/maps/*.txt，確定就加 --force")
    os.makedirs(OUT, exist_ok=True)
    xuchang()
    field()
    for f in range(1, 11):
        cave(f)
