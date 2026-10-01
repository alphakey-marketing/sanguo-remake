#!/usr/bin/env python3
"""原版許昌室內圖 + 兩張工作區道路圖匯入。用法: import_orig_interiors.py [--check]
輸出: client/data/orig_maps/xc<id>.json  client/assets_orig/maps/xc<id>/{atlas.png,obj/*.png}
      client/data/maps/xc<id>.txt  maps.json 條目 + 傳送點 (城門/屋門 <-> 室內出口)
入屋位置 = 原版 evt k2 觸發區 (extracted/text/evt_k2_*.tsv)，k2 編號 = 室內圖編號；
工作區門 (600089 / 600865) 由用家指定；目標 map 係伺服器發落，原版冇表。"""
import sys, os, json, struct, base64, argparse, shutil, collections
SRC = 'D:/Download/sanguo/'
sys.path.insert(0, SRC + 'tools')
from mrg_decode import Mrg
from map_parse import parse
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, 'client', 'data', 'orig_maps')
ASSET = os.path.join(ROOT, 'client', 'assets_orig', 'maps')
MAPS = os.path.join(ROOT, 'client', 'data', 'maps.json')
MAPD = SRC + '_archive/client_launcher_folder/Sanguo_Client/Map/'
SP = SRC + 'extracted/sprites/'
TX = SRC + 'extracted/text/'
CITY = 'xuchang_o'                      # 許昌（原版）地圖 id
CITY_CELLS = 16                          # k2 px -> 16px 格

# 室內圖: id -> (名, 有冇城內門)
INTERIORS = {
    1901: '官宅', 1902: '客棧', 1903: '藥房', 1904: '武器店', 1905: '私塾', 1906: '廟', 1907: '練兵場',
    1908: '虎威府', 1909: '禁衛府', 1910: '木工廠', 1911: '打鐵鋪', 1912: '錢莊', 1913: '拍賣屋',
    1914: '馬廄', 1915: '室內15', 1916: '賭場', 1917: '大廳', 1918: '民宅', 1919: '老年人家', 1920: '民宅20',
    1921: '鳳嫂家', 1924: '廚房', 1942: '室內42', 1943: '室內43', 1944: '珠寶店', 1945: '室內45',
    1946: '王允府', 1947: '劉備家'}
ROADS = {1923: '許昌道路（木礦藥）', 1922: '許昌道路（農漁獵）'}
# 工作區入口: 城內 k2 觸發區 -> 道路圖 (用家 2026-09-30 指定: 600089 -> A=1923, 600865 -> B=1922)
ROAD_GATES = {600089: 1923, 600865: 1922}
TILESET = {1907: 'grd02', 1923: 'grd00'}   # 其餘 grd03

def sprite_index():
    idx = {}
    for d in sorted(os.listdir(SP)):
        if not d.startswith('upobj_'): continue
        for f in os.listdir(SP + d):
            idx.setdefault(f.split('_', 1)[1][:-4].lower(), SP + d + '/' + f)
    return idx

def k2_rects():
    """map id -> [(k2_id, sub, x1, y1, x2, y2)] (kind=1 矩形)"""
    out = collections.defaultdict(set)
    for e in ('evt1', 'evt2'):
        for ln in open(TX + 'evt_k2_%s.tsv' % e, encoding='utf8'):
            r = ln.rstrip('\n').split('\t')
            if len(r) < 8 or not r[0].isdigit() or r[1] != '1': continue
            x1, y1, x2, y2 = map(int, r[4:8])
            if x2 > x1 and y2 > y1: out[int(r[3])].add((int(r[0]), int(r[2]), x1, y1, x2, y2))
    return out

_GRIDS = None
def build_walk(d):
    """同 tools/walk_export.py 一樣砌行走層 (該檔會按 hash 去重，室內圖範本相同，冇逐張 .walk)；回 (gw, gh, bytes 1=擋)"""
    global _GRIDS
    import numpy as np
    old = os.getcwd(); os.chdir(SRC)
    try:
        import walk_build
        if _GRIDS is None:
            _GRIDS = {}
            for nm, r in walk_build.load_col().items():
                w, h = struct.unpack_from('<2I', r, 0x28)
                _GRIDS[nm] = (np.frombuffer(r[walk_build.G0:walk_build.G0 + 1600], np.uint8).reshape(40, 40), h)
    finally:
        os.chdir(old)
    CELL = walk_build.CELL
    W, H = d['W'], d['H']; gw, gh = W // CELL + 1, H // CELL + 1
    t = np.array(d['tiles'], np.uint16).reshape(d['rows'], d['cols'])
    sp = ((t & 0xff) >= 100) & ((t & 0xff) <= 104)
    ys = np.minimum(np.arange(gh) * CELL // 48, d['rows'] - 1); xs = np.minimum(np.arange(gw) * CELL // 48, d['cols'] - 1)
    g = sp[np.ix_(ys, xs)].astype(np.uint8)
    for nm, x, y in d['objs']:
        e = _GRIDS.get(nm.lower())
        if e is None: continue
        m, h = e; base = (y + h + 15) // CELL - 1; x0 = x // CELL
        for r in range(40):
            cy = base - r
            if not 0 <= cy < gh: continue
            row = m[r]
            if not row.any(): continue
            c0, c1 = max(0, -x0), min(40, gw - x0)
            if c0 >= c1: continue
            seg = row[c0:c1]; dst = g[cy, x0 + c0:x0 + c1]
            dst[seg == 2] = 0; dst[(seg >= 1) & (seg <= 19) & (seg != 2)] = 1
    return gw, gh, g.tobytes()

def open_mrg(name):
    for f in ('Map', 'map21'):
        m = Mrg(MAPD + f + '.mrg')
        if name in m.names and parse(m.blob(m.names.index(name))) is not None: return f, m
    return None, None

def walkable(g, gw, gh, x, y): return 0 <= x < gw and 0 <= y < gh and not g[y * gw + x]

def rect_cells(rc, gw, gh):
    x1, y1, x2, y2 = rc
    return [(x, y) for y in range(max(0, y1), min(gh - 1, y2) + 1) for x in range(max(0, x1), min(gw - 1, x2) + 1)]

def nearest_outside(g, gw, gh, rc, near, prefer_far_from_edge=False):
    """離 near 最近、行得、唔喺 rc 入面嘅格 (用嚟落地)"""
    x1, y1, x2, y2 = rc
    best = None
    for y in range(gh):
        for x in range(gw):
            if not walkable(g, gw, gh, x, y) or (x1 <= x <= x2 and y1 <= y <= y2): continue
            d = abs(x - near[0]) + abs(y - near[1])
            # 落地格四周要有空位，免得卡死
            free = sum(walkable(g, gw, gh, x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1))
            if free < 6: continue
            if best is None or d < best[0]: best = (d, x, y)
    return None if best is None else (best[1], best[2])

def pick_exit(rects, W, H):
    c = [r for r in sorted(rects) if r[1] == 1 and (r[2] <= 64 or r[3] <= 64 or r[4] >= W - 64 or r[5] >= H - 64)]
    c = [r for r in c if (r[4] - r[2]) * (r[5] - r[3]) < 0.25 * W * H]
    return c[0] if c else None

def shelf_pack(items, width, top):
    """items: [(key, w, h)] -> {key: (ox, oy)}，由 top 行起，一行行排，格間留 20 格 (run_maps 間隔測試)"""
    pos = {}; x = 0; y = top; rowh = 0
    for k, w, h in sorted(items, key=lambda t: -t[2]):
        if x + w > width: x = 0; y += rowh + 20; rowh = 0
        pos[k] = (x, y); x += w + 20; rowh = max(rowh, h)
    return pos, y + rowh

def run(check):
    sidx = sprite_index(); rects = k2_rects(); errs = []
    city = json.load(open(DATA + '/xuchang.json', encoding='utf8'))['walk']
    import zlib
    cg = zlib.decompress(base64.b64decode(city['z'])); cgw, cgh = city['w'], city['h']
    targets = dict(INTERIORS); targets.update(ROADS)
    built = {}
    for mid, cn in sorted(targets.items()):
        name = '%05d' % mid
        mrgname, m = open_mrg(name)
        if m is None: print('跳過 %d: 兩個 mrg 都解析唔到' % mid); continue
        i = m.names.index(name); d = parse(m.blob(i))
        gw, gh, g = build_walk(d)
        ts = TILESET.get(mid, 'grd03'); TS = SP + 'grd_' + ts + '/'
        tiles = {int(f.split('_')[0]): TS + f for f in os.listdir(TS)}
        for alt in ('grd00', 'grd02', 'grd01'):         # 本 tileset 冇嘅 tile id，借其他 tileset 同號 (例如 1913 嘅 1536)
            for f in os.listdir(SP + 'grd_' + alt): tiles.setdefault(int(f.split('_')[0]), SP + 'grd_' + alt + '/' + f)
        used = sorted(set(d['tiles'])); miss = [v for v in used if v not in tiles]
        if miss: errs.append('%d 缺 tile %s' % (mid, miss[:5]))
        remap = {v: n for n, v in enumerate(used)}
        objs = []; names = set()
        for n, x, y in d['objs']:
            k = n.lower().rsplit('.', 1)[0]
            if k not in sidx: errs.append('%d 缺物件圖 %s' % (mid, n)); continue
            o = {'n': k, 'x': x, 'y': y}
            im = Image.open(sidx[k]).convert('RGBA')
            if min(im.size) >= 250 and im.getchannel('A').getextrema()[0] == 255: o['floor'] = True   # 整塊不透明大圖 = 室內地板底圖，要貼地
            objs.append(o); names.add(k)
        key = 'xc%d' % mid
        out = {'key': key, 'name': cn, 'orig': {'mrg': mrgname, 'id': name, 'idx': i}, 'W': d['W'], 'H': d['H'], 'tile': 48,
               'cols': d['cols'], 'rows': d['rows'], 'atlas_cols': 32, 'tiles': [remap[v] for v in d['tiles']],
               'objects': sorted(objs, key=lambda o: o['y']),
               'walk': {'w': gw, 'h': gh, 'z': base64.b64encode(zlib.compress(g, 9)).decode()}}
        built[mid] = dict(out=out, used=used, tiles=tiles, TS=TS, names=names, g=g, gw=gw, gh=gh, cn=cn, W=d['W'], H=d['H'])
        print(key, cn, d['W'], d['H'], 'tile', len(used), '物件', len(objs))
    if errs:
        print('錯:'); [print(' -', e) for e in errs[:30]]; sys.exit(1)

    # 地圖擺位: 全域格仔 x 0..511；許昌原版 (oy 644 + 188) 之下
    pos, bottom = shelf_pack([(m, b["gw"], b["gh"]) for m, b in built.items()], 512, 860)
    print('地圖擺位完，最底行', bottom, '(WORLD_H 要 >=', bottom + 1, ')')
    if check: return
    # 城內門 / 工作區門 -> 城內 portal；室內出口 -> 返城
    portals = []; nodoor = []
    city_rects = rects[1900]
    door_of = {}
    for k, sub, x1, y1, x2, y2 in sorted(city_rects):
        if k in INTERIORS: door_of.setdefault(k, (x1, y1, x2, y2))
        elif k in ROAD_GATES: door_of[ROAD_GATES[k]] = (x1, y1, x2, y2)
    for mid, b in sorted(built.items()):
        key = 'xc%d' % mid; g = b['g']; gw, gh = b['gw'], b['gh']
        is_road = mid in ROADS
        # 室內出口 / 道路出口 (北邊整條)
        ex = pick_exit(rects[mid], b['W'], b['H']) if not is_road else (0, 1, 0, 0, 3200, 48)
        if ex is None: print('警告: %d 搵唔到出口' % mid); continue
        erc = [ex[2] // 16, ex[3] // 16, ex[4] // 16, ex[5] // 16]
        ecells = [c for c in rect_cells(erc, gw, gh) if walkable(g, gw, gh, *c)]
        if not ecells:
            erc = [erc[0] - 2, erc[1] - 2, erc[2] + 2, erc[3] + 2]
            ecells = [c for c in rect_cells(erc, gw, gh) if walkable(g, gw, gh, *c)]
        if not ecells: print('警告: %d 出口冇行得格' % mid); continue
        ec = ecells[len(ecells) // 2]
        centre = ((erc[0] + erc[2]) // 2, (erc[1] + erc[3]) // 2)
        in_land = nearest_outside(g, gw, gh, erc, (centre[0], centre[1] + (6 if is_road else 0)))
        if mid not in door_of:
            nodoor.append(mid)
        else:
            dx1, dy1, dx2, dy2 = door_of[mid]
            drc = [dx1 // 16, dy1 // 16, dx2 // 16, dy2 // 16]
            dcells = [c for c in rect_cells(drc, cgw, cgh) if walkable(cg, cgw, cgh, *c)]
            grow = 0
            while not dcells and grow < 4:
                grow += 1
                dcells = [c for c in rect_cells([drc[0] - grow, drc[1] - grow, drc[2] + grow, drc[3] + grow], cgw, cgh) if walkable(cg, cgw, cgh, *c)]
            if not dcells: print('警告: %d 城門口冇行得格' % mid); continue
            if grow: drc = [drc[0] - grow, drc[1] - grow, drc[2] + grow, drc[3] + grow]
            dc = dcells[len(dcells) // 2]
            city_land = nearest_outside(cg, cgw, cgh, drc, ((drc[0] + drc[2]) // 2, drc[3] + 2))
            portals.append({'id': 'xc_in_%d' % mid, 'name': '入 ' + b['cn'], 'map': CITY, 'x': dc[0], 'y': dc[1],
                            'rect': drc, 'land': list(city_land), 'to': 'xc_out_%d' % mid, 'auto': True})
            portals.append({'id': 'xc_out_%d' % mid, 'name': '出 ' + b['cn'], 'map': key, 'x': ec[0], 'y': ec[1],
                            'rect': erc, 'land': list(in_land), 'to': 'xc_in_%d' % mid, 'auto': True})
        b['spawn'] = in_land
    # 寫資產 / 資料 / txt
    for mid, b in sorted(built.items()):
        key = 'xc%d' % mid
        with open(os.path.join(DATA, key + '.json'), 'w', encoding='utf8') as f: json.dump(b['out'], f, ensure_ascii=False, separators=(',', ':'))
        ad = os.path.join(ASSET, key); os.makedirs(ad + '/obj', exist_ok=True)
        rws = (len(b['used']) + 31) // 32; at = Image.new('RGBA', (32 * 48, max(1, rws) * 48))
        for n, v in enumerate(b['used']):
            if v in b['tiles']: at.paste(Image.open(b['tiles'][v]).convert('RGBA'), ((n % 32) * 48, (n // 32) * 48))
        at.save(ad + '/atlas.png')
        for k in b['names']: shutil.copyfile(sidx[k], ad + '/obj/%s.png' % k)
        gw, gh, g = b['gw'], b['gh'], b['g']
        with open(os.path.join(ROOT, 'client', 'data', 'maps', key + '.txt'), 'w', encoding='utf8', newline='\n') as f:
            f.write('\n'.join(''.join('H' if g[y * gw + x] else '.' for x in range(gw)) for y in range(gh)) + '\n')
    mj = json.load(open(MAPS, encoding='utf8'))
    keep = {'xc%d' % m for m in built}
    mj['maps'] = [m for m in mj['maps'] if m['id'] not in keep]
    for mid, b in sorted(built.items()):
        ox, oy = pos[mid]; sp = b.get('spawn') or (b['gw'] // 2, b['gh'] // 2)
        mj['maps'].append({'id': 'xc%d' % mid, 'name': '許昌·' + b['cn'], 'ox': ox, 'oy': oy, 'safe': True,
                           'kind': 'field' if mid in ROADS else 'house', 'orig': 'xc%d' % mid,
                           'spawn': [sp[0], sp[1], sp[0], sp[1]]}
                  | ({'orphan': True} if mid in nodoor else {}))     # orphan = 未知城內門，暫時去唔到
    mj['portals'] = [p for p in mj['portals'] if not (p['id'].startswith('xc_in_') or p['id'].startswith('xc_out_'))] + portals
    open(MAPS, 'w', encoding='utf8', newline='\n').write(json.dumps(mj, ensure_ascii=False, indent=1) + '\n')
    print('傳送點', len(portals), '無城內門嘅室內圖', nodoor)
    print('OK, WORLD_H >=', bottom + 1)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('--check', action='store_true'); run(ap.parse_args().check)
