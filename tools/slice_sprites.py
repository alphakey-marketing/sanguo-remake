#!/usr/bin/env python3
"""A4a spike: sheets/<set>/CP_<id><A|S|W>.CP.png 切幀 (8 方向列 x 8 幀欄，格 = 圖寬/8 x 圖高/8)。
用法: python tools/slice_sprites.py contact OUT.png set:id [set:id ...]   # 出 contact sheet 人手驗排列
      python tools/slice_sprites.py frames set id  -> 印 A/S/W 尺寸同格尺寸
"""
import os, sys, glob
from PIL import Image, ImageDraw
SRC = r"D:\Download\sanguo\extracted\sheets"
COLS = ROWS = 8

def find(set_, id_, act):
    g = glob.glob(os.path.join(SRC, set_, f"*CP_{id_}{act}.CP.png")) or glob.glob(os.path.join(SRC, set_, f"CP_{id_}{act}.CP.png"))
    return g[0] if g else None

def cells(path):
    im = Image.open(path).convert("RGBA")
    cw, ch = im.width // COLS, im.height // ROWS
    return im, cw, ch

def contact(out, specs):
    rows = []
    for sp in specs:
        set_, id_ = sp.split(":")
        for act in "ASW":
            p = find(set_, id_, act)
            if p:
                rows.append((f"{sp}{act}", *cells(p)))
    W = max(r[1].width for r in rows) + 10
    H = sum(r[1].height + 14 for r in rows)
    c = Image.new("RGBA", (W, H), (60, 90, 60, 255))
    d = ImageDraw.Draw(c)
    y = 0
    for name, im, cw, ch in rows:
        d.text((0, y), f"{name} cell={cw}x{ch}", fill=(255, 255, 0, 255))
        c.paste(im, (0, y + 12), im)
        y += im.height + 14
    c.save(out)
    print(len(rows), "sheets ->", out)

if __name__ == "__main__":
    if sys.argv[1] == "contact":
        contact(sys.argv[2], sys.argv[3:])
    else:
        for a in "ASW":
            p = find(sys.argv[2], sys.argv[3], a)
            if p:
                im, cw, ch = cells(p)
                print(a, im.size, "cell", cw, ch)
