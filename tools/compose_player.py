#!/usr/bin/env python3
"""玩家分層 sprite 疊合 (role1.mrg)。每 frame 有 (x,y) 偏移、共用原點；
碼 1{B}{C}{D}{E}{FG}: B=職業體型 1~6, C=動作 (1 走/2 攻), D=層 (1 身/2 武/3 髮/4 甲)。
用法: import compose_player as cp; cp.compose(B, C, hair=0, armor=0, weapon=1) -> 8x8 sheet (RGBA, cell CW x CH, 原點 OX,OY)"""
import sys, os
sys.path.insert(0, r"D:/Download/sanguo/tools")
from mrg_decode import Mrg
from cp_decode import CP
from PIL import Image

MRG = r"D:/Download/zyxy_client/Sanguo_Client/role/role1.mrg"
CW, CH, OX, OY = 144, 160, 72, 92
_m = None
_ix = {}

def _load():
    global _m
    if _m is None:
        _m = Mrg(MRG)
        for i, n in enumerate(_m.names):
            _ix[n.split(chr(92))[-1][:7]] = i

def layer(code):
    _load()
    return CP(_m.blob(_ix[code])) if code in _ix else None

_m9902 = None
_ix9902 = {}


def layer9902(code):
    """role9902.mrg = 三轉造型件 (第 5 位 4，FG 04~06 三款)；用家 2026-10-03 揀第 1 款 (04)"""
    global _m9902
    if _m9902 is None:
        _m9902 = Mrg(r"D:/Download/zyxy_client/Sanguo_Client/role/role9902.mrg")
        for i, n in enumerate(_m9902.names):
            _ix9902[n.split(chr(92))[-1][:7]] = i
    return CP(_m9902.blob(_ix9902[code])) if code in _ix9902 else None


def single(code, src=None):
    """單層 → 8x8 sheet (同 compose 一樣 cell/原點，可直接疊)"""
    c = (src or layer)(code)
    if c is None:
        return None
    sheet = Image.new("RGBA", (CW * 8, CH * 8), (0, 0, 0, 0))
    for f in range(c.n):
        im, _ = c.image(f)
        cell = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
        cell.alpha_composite(im, (OX + c.recs[f][0], OY + c.recs[f][1]))
        sheet.alpha_composite(cell, ((f % 8) * CW, (f // 8) * CH))
    return sheet

def compose(B, C, hair=0, armor=0, weapon=1, weapon_front=None):
    _load()
    e = {1: ("3", "1"), 2: ("3", "1")}
    body = layer(f"1{B}{C}1300")
    ar = layer(f"1{B}{C}41{armor:02d}")
    ha = layer(f"1{B}{C}31{hair:02d}")
    wp = layer(f"1{B}{C}21{weapon:02d}") if weapon else None
    sheet = Image.new("RGBA", (CW * 8, CH * 8), (0, 0, 0, 0))
    for f in range(body.n):
        row, col = f // 8, f % 8
        cell = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
        def put(c):
            if c is None or f >= c.n:
                return
            im, _ = c.image(f)
            x, y = c.recs[f][0], c.recs[f][1]
            cell.alpha_composite(im, (OX + x, OY + y))
        # 武器: 背向 (N/NE/NW = row 0,1,7) 喺身後，其餘身前
        wfront = (row not in (0, 1, 7)) if weapon_front is None else weapon_front
        if not wfront: put(wp)
        put(body); put(ar); put(ha)
        if wfront: put(wp)
        sheet.alpha_composite(cell, (col * CW, row * CH))
    return sheet

if __name__ == "__main__":
    B = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    out = os.environ.get("TEMP", ".") + f"/pc_{B}.png"
    s = compose(B, 1, hair=1, armor=1, weapon=1)
    bg = Image.new("RGBA", s.size, (40, 90, 60, 255)); bg.alpha_composite(s)
    bg.crop((0, 0, CW * 8, CH * 8)).save(out); print(out)
