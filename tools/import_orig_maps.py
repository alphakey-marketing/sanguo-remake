#!/usr/bin/env python3
"""原版地圖匯入（三新手城）。用法: import_orig_maps.py [--check]
輸出: client/data/orig_maps/<key>.json  client/assets_orig/maps/<key>/{atlas.png,obj/*.png}
tileset 一律 grd00；行走層用原版 .walk（16px, 1=擋）。"""
import sys, os, json, struct, zlib, base64, argparse, shutil
SRC = 'D:/Download/sanguo/'
sys.path.insert(0, SRC + 'tools')
from mrg_decode import Mrg
from map_parse import parse
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, 'client', 'data', 'orig_maps')
ASSET = os.path.join(ROOT, 'client', 'assets_orig', 'maps')
CITIES = {'xuchang': ('Map', '01900', '許昌'), 'xinye': ('Map', '02700', '新野'), 'xiangyang': ('Map', '02900', '襄陽')}
TS = SRC + 'extracted/sprites/grd_grd00/'
SP = SRC + 'extracted/sprites/'

def sprite_index():
    idx = {}
    for d in sorted(os.listdir(SP)):
        if not d.startswith('upobj_'): continue
        for f in os.listdir(SP + d):
            idx.setdefault(f.split('_', 1)[1][:-4].lower(), SP + d + '/' + f)
    return idx

MAPS = os.path.join(ROOT, 'client', 'data', 'maps.json')
TEST_OY = 644   # 全域格：放喺 WORLD_H(640) 之下，原版許昌 251x188 格

def register_test_map(key, cn, gw, gh, z):
    """原版許昌 = 測試地圖 xuchang_o：邏輯層 txt (行走層 -> '.'/'H')、maps.json 條目 + 兩個入口 portal。"""
    import numpy as np
    g = np.frombuffer(zlib.decompress(z), np.uint8).reshape(gh, gw)
    mid = key + '_o'
    # 出生點 = 底部中間最近嘅可行格
    best = min(((abs(x - 125) + abs(y - 170), x, y) for y in range(120, gh - 2) for x in range(60, 190) if not g[y, x] and not g[y-1:y+2, x-1:x+2].any()))
    sx, sy = best[1], best[2]
    txt = os.path.join(ROOT, 'client', 'data', 'maps', mid + '.txt')
    with open(txt, 'w', encoding='utf8', newline='\n') as f:
        f.write('\n'.join(''.join('H' if v else '.' for v in row) for row in g) + '\n')
    d = json.load(open(MAPS, encoding='utf8'))
    d['maps'] = [m for m in d['maps'] if m['id'] != mid]
    d['maps'].append({'id': mid, 'name': cn + '（原版）', 'ox': 0, 'oy': TEST_OY, 'safe': True, 'kind': 'city', 'orig': key, 'cityOf': 'xuchang', 'spawn': [sx, sy, sx, sy]})
    d['portals'] = [p for p in d['portals'] if not p['id'].startswith('orig_xc')]
    # 臨時傳送點已取消 (2026-10-01: 新局直接喺原版許昌開始，舊 ASCII 圖抽起)
    #d['portals'].append({'id': 'orig_xc_in', 'name': '原版許昌（測試）', 'map': 'xuchang', 'x': 37, 'y': 1, 'to': 'orig_xc_out', 'auto': True})
    #d['portals'].append({'id': 'orig_xc_out', 'name': '返回舊許昌', 'map': mid, 'x': sx, 'y': sy + 1, 'to': 'orig_xc_in', 'auto': True})
    open(MAPS, 'w', encoding='utf8', newline='\n').write(json.dumps(d, ensure_ascii=False, indent=1) + '\n')
    print('  測試地圖', mid, '出生', sx, sy)

# 許昌城牆線 (像素, 由左至右折線): 線以北 = 城內
WALL_XC = [(0, 1540), (920, 2020), (2160, 2700), (2400, 2760), (4000, 3160)]
def _wall_y(x):
    for (x0, y0), (x1, y1) in zip(WALL_XC, WALL_XC[1:]):
        if x <= x1: return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return WALL_XC[-1][1]

def seamless(im):
    """半格錯位 + 中心權重混合 → 四方連續 (磚紋唔做鏡像，免得砌出菱形)"""
    import numpy as np
    a = np.asarray(im.convert('RGB'), dtype=float); h, w = a.shape[:2]
    sh = np.roll(np.roll(a, h // 2, 0), w // 2, 1)
    wy = np.sin(np.linspace(0, np.pi, h, endpoint=False)) ** 2; wx = np.sin(np.linspace(0, np.pi, w, endpoint=False)) ** 2
    m = (wy[:, None] * wx[None, :])[:, :, None]
    return Image.fromarray((a * m + sh * (1 - m)).astype('uint8'), 'RGB').convert('RGBA')

def _near_building(objs_rects, cx, cy):
    for x0, y0, x1, y1 in objs_rects:
        if x0 <= cx <= x1 and y0 <= cy <= y1: return True
    return False

def cobble_fix(tl, used, tiles, cols, rows, objs, sizes):
    """舊版客戶端地面係草/泥；原版新版城內主要係磚塊路，圓石仔只喺建築物周圍。
    城牆內非灰色地磚 → 磚塊 (tools/orig_brick.png) / 建築腳附近 → 圓石仔 (tools/orig_cobble.png)；都係用戶原版截圖切出。"""
    here = os.path.dirname(os.path.abspath(__file__))
    cob = Image.open(os.path.join(here, 'orig_cobble.png')).convert('RGBA')
    cv = [cob, cob.transpose(Image.FLIP_LEFT_RIGHT), cob.transpose(Image.FLIP_TOP_BOTTOM), cob.transpose(Image.ROTATE_180)]
    brk = seamless(Image.open(os.path.join(here, 'orig_brick.png')))
    base = len(used)
    pos = {v: n for n, v in enumerate(used)}
    # 地圖資料入面「草地」有兩個值：37 = 街道 (新版美術係磚塊路)、39 = 建築庭院 (新版係圓石仔)。
    # 灰石板 (768/804/1024...) 同泥地 (2075/258...) 保持原圖。已用 val2 疊圖對照原版截圖確認。
    n37 = pos.get(37, -1); n39 = pos.get(39, -1)
    # 灰石板/沙泥 (舊美術) 喺街道入面零星出現，原版冇呢啲塊 → 一併當磚塊路
    slab = set()
    for v, n in pos.items():
        if v in tiles and v not in (37, 39):
            px = list(Image.open(TS + tiles[v]).convert('RGB').resize((8, 8)).getdata())
            r = sum(q[0] for q in px) / 64; g = sum(q[1] for q in px) / 64; b = sum(q[2] for q in px) / 64
            if (r + g + b) / 3 > 100: slab.add(n)     # 淺色地磚 (灰石板/沙泥)；深色泥保留 (屋簷影)
    out = list(tl); nb = nc = 0
    for i, n in enumerate(tl):
        r, c = divmod(i, cols)
        if (n in (n37, n39) or n in slab) and r * 48 + 24 < _wall_y(c * 48 + 24) - 40:
            if n == n39: out[i] = base + 1 + (c & 1) + 2 * (r & 1); nc += 1
            else: out[i] = base; nb += 1
    print('  磚塊', nb, '格 / 石仔', nc, '格')
    return out, [brk] + cv

def run(check):
    tiles = {int(f.split('_')[0]): f for f in os.listdir(TS)}
    sidx = sprite_index(); errs = []
    os.makedirs(DATA, exist_ok=True)
    for key, (mrg, name, cn) in CITIES.items():
        m = Mrg(SRC + '_archive/client_launcher_folder/Sanguo_Client/Map/%s.mrg' % mrg)
        i = m.names.index(name); d = parse(m.blob(i))
        cols, rows = d['cols'], d['rows']
        used = sorted(set(d['tiles'])); miss = [v for v in used if v not in tiles]
        if miss: errs.append('%s 缺 tile %s' % (key, miss[:5]))
        remap = {v: n for n, v in enumerate(used)}
        objs = []; names = set()
        for n, x, y in d['objs']:
            k = n.lower().rsplit('.', 1)[0]
            if k not in sidx: errs.append('%s 缺物件圖 %s' % (key, n)); continue
            objs.append({'n': k, 'x': x, 'y': y}); names.add(k)
        wf = SRC + 'extracted/maps/walk/%s_%05d.walk' % (mrg, i)
        w = open(wf, 'rb').read(); gw, gh = struct.unpack('<HH', w[:4])
        if gw != d['W'] // 16 + 1 or gh != d['H'] // 16 + 1: errs.append('%s walk 尺寸 %dx%d 不符' % (key, gw, gh))
        tl = [remap[v] for v in d['tiles']]; extra = []
        if key == 'xuchang': tl, extra = cobble_fix(tl, used, tiles, cols, rows, objs, {k: Image.open(sidx[k]).size for k in names})
        out = {'key': key, 'name': cn, 'orig': {'mrg': mrg, 'id': name, 'idx': i}, 'W': d['W'], 'H': d['H'],
               'tile': 48, 'cols': cols, 'rows': rows, 'atlas_cols': 32,
               'tiles': tl, 'objects': sorted(objs, key=lambda o: o['y']),
               'walk': {'w': gw, 'h': gh, 'z': base64.b64encode(w[4:]).decode()}}
        if key == 'xuchang' and not check: register_test_map(key, cn, gw, gh, w[4:])
        print(key, cn, d['W'], d['H'], 'tile 種', len(used), '物件', len(objs), '物件圖', len(names), 'walk', gw, gh)
        if check: continue
        with open(os.path.join(DATA, key + '.json'), 'w', encoding='utf8') as f: json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
        ad = os.path.join(ASSET, key); os.makedirs(ad + '/obj', exist_ok=True)
        rws = (len(used) + len(extra) + 31) // 32; at = Image.new('RGBA', (32 * 48, rws * 48))
        for n, v in enumerate(used):
            if v in tiles: at.paste(Image.open(TS + tiles[v]).convert('RGBA'), ((n % 32) * 48, (n // 32) * 48))
        for j, im in enumerate(extra): at.paste(im, (((len(used) + j) % 32) * 48, ((len(used) + j) // 32) * 48))
        at.save(ad + '/atlas.png')
        for k in names: shutil.copyfile(sidx[k], ad + '/obj/%s.png' % k)
        print('  資產', ad, '%.1f MB' % (sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(ad) for f in fs) / 1e6))
    if errs:
        print('錯:'); [print(' -', e) for e in errs[:20]]; sys.exit(1)
    print('OK')

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('--check', action='store_true'); run(ap.parse_args().check)
