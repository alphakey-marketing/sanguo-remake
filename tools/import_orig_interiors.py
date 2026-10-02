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
ROADS = {1923: '許昌道路（木礦藥）', 1922: '許昌道路（農漁獵）', 1723: '陳留道路A', 1722: '陳留道路B'}
# 陳留室內 (名暫按許昌同號推；1724/1733/1741-47 係 1700 k2 觸發區指向嘅額外室內)；1706/1709/1717/1721 冇 k2 城內門 -> orphan
# 名按 named_locations.tsv (陳留 1701~1747)
INTERIORS |= {1701: '陳留官宅', 1702: '陳留客棧', 1703: '陳留藥房', 1704: '陳留武器店', 1705: '陳留私塾', 1707: '陳留室內07', 1708: '陳留室內08',
              1709: '陳留室內09', 1710: '陳留木工廠', 1711: '陳留打鐵鋪', 1712: '陳留錢莊', 1713: '陳留拍賣屋', 1714: '陳留馬廄', 1715: '陳留驛站',
              1716: '陳留室內16', 1717: '陳留監牢', 1718: '陳留廚房', 1719: '衛富豪家', 1720: '漁夫家', 1721: '陳留朝廷官署', 1724: '陳留大廚房',
              1733: '陳留室內33', 1741: '陳留室內41', 1742: '衛茲家', 1743: '小童家', 1744: '陳留室內44', 1745: '陳留室內45', 1746: '陳留室內46', 1747: '書生家'}
# 工作區入口: 城內 k2 觸發區 -> 道路圖 (用家 2026-09-30 指定: 600089 -> A=1923, 600865 -> B=1922)
FIELDS = {1851: '許昌洞穴一', 1852: '許昌洞穴二', 1853: '許昌洞穴三', 1854: '許昌洞穴四', 1855: '許昌洞穴五',     # N51-55 = 洞穴 (用家睇圖確認)
          1925: '外圍25'}
# 外圍模板 (所有城共用同一份圖資料): 每城一個邏輯實例 (自己 map id/擺位)，orig 指向模板
LINKS = json.load(open(os.path.join(ROOT, 'client', 'data', 'city_links.json'), encoding='utf8'))   # tools/city_links.py 生成
CITY_NAME = {c['id'] // 100: n for n, c in LINKS['cities'].items()}
TPLS = (25,)                              # v2: 每城只有一張外圍 xx25 (所有城共用)
# 城圖 (3200x2400 / 4000x3000，type=城市)：除許昌 (import_orig_maps 負責 xuchang_o) 外全部城池；(漢中/梓潼 係 map22 大圖，天水/武都 冇城圖 -> 跳過)
SKIP_TOWNS = {1900, 3700, 3800, 3900}     # 漢中/武都/梓潼 = map22 空殼圖 (全平地、無物件、tile 0)，原版未做完
TOWNS = {c['id']: n for n, c in LINKS['cities'].items() if c['id'] not in SKIP_TOWNS}
CITY_MAPID = {19: CITY} | {t // 100: 'xc%d' % t for t in TOWNS}     # 城 id(//100) -> 城圖 map id
# cityOf slug: 有舊圖嘅城沿用舊 city id (驛站/市場借舊圖)，其餘拼音
SLUG = {'許昌': 'xuchang', '陳留': 'chenliu', '洛陽': 'luoyang', '汝南': 'runan', '宛': 'wancheng', '襄陽': 'xiangyang', '新野': 'xinye', '長沙': 'changsha',
        '小沛': 'xiaopei', '下邳': 'xiapi', '零陵': 'lingling', '襄平': 'xiangping', '北平': 'beiping', '薊': 'ji', '北海': 'beihai', '平原': 'pingyuan',
        '南皮': 'nanpi', '鄴': 'ye', '盧江': 'lujiang', '壽春': 'shouchun', '柴桑': 'chaisang', '吳': 'wu', '天水': 'tianshui', '漢中': 'hanzhong', '武都': 'wudu', '梓潼': 'zitong', '會稽': 'kuaiji', '建業': 'jianye', '濮陽': 'puyang',
        '譙': 'qiao', '江夏': 'jiangxia', '桂陽': 'guiyang', '河內': 'henei', '晉陽': 'jinyang', '江陵': 'jiangling', '武陵': 'wuling', '安定': 'anding',
        '長安': 'changan', '西涼': 'xiliang'}
CITY_SLUG = {c['id'] // 100: SLUG[n] for n, c in LINKS['cities'].items() if n in SLUG}
INSTANCES = sorted({m for l in LINKS['links'] for m in (l['a_out'], l['b_out'])} - {1925})   # 非許昌嘅外圍實例
SIDE_DIR = {'E': (1, 0), 'W': (-1, 0), 'N': (0, -1), 'S': (0, 1)}
GATE_W = [0, 146, 4, 168]                 # 許昌城西邊緣 (用家確認 A 位) -> 許昌外圍25 正中
MODEL = ('ad021', 'ad022')                # 城池模型: 兩張相鄰切片 (320+480 px 闊) 合成一座完整城堡，放外圍 25 正中
MODEL_XY = (1200, 900)                    # 模型左上 px (外圍 3200x2400 正中；合成 800x600)
MODEL_DIAMOND = (400, 410, 340, 165)      # 模型地面菱形 (中心 x, y, 半闊, 半高；模型 px) -> 佔格擋路
GATE_RECT = [84, 89, 91, 92]              # 入城傳送區 = 城門 (模型左前牆，約模型 px (230,480)) 門口
GATE_LAND = (80, 94)                      # 由城出來嘅落腳點 (城門外)


def tpl_runs(g, gw, gh):
    """模板外圍 25/29/49: 每邊緣 (深 4 格都喺最大連通塊) 嘅最長連續段 -> {side: [座標...]}；封死嘅邊冇"""
    from collections import deque
    seen = set(); best = set()
    for y0 in range(gh):
        for x0 in range(gw):
            if not g[y0 * gw + x0] and (x0, y0) not in seen:
                comp = {(x0, y0)}; q = deque([(x0, y0)])
                while q:
                    x, y = q.popleft()
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        n = (x + dx, y + dy)
                        if 0 <= n[0] < gw and 0 <= n[1] < gh and not g[n[1] * gw + n[0]] and n not in comp: comp.add(n); q.append(n)
                seen |= comp
                if len(comp) > len(best): best = comp
    D = 4; res = {}
    spec = {'N': (gw, lambda k: [(k, y) for y in range(D)]), 'S': (gw, lambda k: [(k, gh - 1 - y) for y in range(D)]),
            'W': (gh, lambda k: [(x, k) for x in range(D)]), 'E': (gh, lambda k: [(gw - 1 - x, k) for x in range(D)])}
    for side, (n, cells) in spec.items():
        runs = []; cur = []
        for k in range(n):
            if all(c in best for c in cells(k)): cur.append(k)
            else:
                if cur: runs.append(cur); cur = []
        if cur: runs.append(cur)
        if runs: res[side] = max(runs, key=len)
    return res


OPP = {'E': 'W', 'W': 'E', 'N': 'S', 'S': 'N'}


def plan_links(runs, cruns):
    """v2: 每條線兩端各用 city_links.json 定好嘅方向邊 (a_dir/b_dir)；每城外圍每邊最多一口。回 {外圍 id: [conn]}"""
    conns = {}
    for l in LINKS['links']:
        conns.setdefault(l['a_out'], []).append({'side': l['a_dir'], 'other': l['b_out'], 'ocity': l['b'], 'key': 0})
        conns.setdefault(l['b_out'], []).append({'side': l['b_dir'], 'other': l['a_out'], 'ocity': l['a'], 'key': 0})
    return conns


def place_slots(lst, run_of, gw, gh):
    """同一邊 n 個口: 沿該邊行得段等分，口闊 9 格深 4 格；回填 rect/cell/land/idx"""
    for side in {c['side'] for c in lst}:
        cs = sorted([c for c in lst if c['side'] == side], key=lambda c: c['key']); run = run_of(side)
        if not run: continue
        for i, c in enumerate(cs):
            mid = run[min(len(run) - 1, int(len(run) * (i + 0.5) / len(cs)))]
            lo = max(run[0], mid - 4); hi = min(run[-1], mid + 4)
            if side in 'EW':
                x1, x2 = (0, 3) if side == 'W' else (gw - 4, gw - 1); r = [x1, lo, x2, hi]
            else:
                y1, y2 = (0, 3) if side == 'N' else (gh - 4, gh - 1); r = [lo, y1, hi, y2]
            cx, cy = (r[0] + r[2]) // 2, (r[1] + r[3]) // 2
            lx, ly = {'W': (cx + 4, cy), 'E': (cx - 4, cy), 'N': (cx, cy + 4), 'S': (cx, cy - 4)}[side]
            c['idx'] = i; c['rect'] = r; c['cell'] = (cx, cy); c['land'] = (lx, ly)


def slot_rects(runs, conns, gw, gh):
    for m, lst in conns.items():
        place_slots(lst, lambda sd: runs[m % 100][sd], gw, gh)

# 新增完整城 (用家 2026-10 指定: 譙/汝南/洛陽/宛)：室內 = locations.tsv 該城「城內設施」+ 該城 k2 門指向嘅其他室內；道路 xx22/xx23
NEWCITIES = {18: '譙', 20: '汝南', 26: '洛陽', 28: '宛'}
FULLCITIES = [19, 17] + sorted(NEWCITIES)
_FAC_KW = [('官宅', '地方功曹'), ('客棧', '客棧掌櫃'), ('藥房', '藥房掌櫃'), ('藥房', '煉丹師傅'), ('武器店', '武器商'), ('私塾', '夫子'), ('廟', '廟公'), ('練兵場', '練兵將'),
           ('木工廠', '木匠師傅'), ('打鐵鋪', '火爐師傅'), ('錢莊', '錢莊掌櫃'), ('拍賣屋', '拍賣屋掌櫃'), ('馬廄', '馬廄老闆'), ('驛站', '驛站長'), ('賭場', '賭場'),
           ('監牢', '獄卒'), ('廚房', '大廚')]
def _load_new_interiors():
    rows = [r.rstrip(chr(10)).split(chr(9)) for r in open(os.path.join(SRC, 'extracted', 'map_list', 'locations.tsv'), encoding='utf8')][1:]
    info = {int(r[0]): r for r in rows}
    rc = k2_rects(); out = {}; tsets = {}
    for c in NEWCITIES:
        cn = NEWCITIES[c]; extra = {k for k, *_ in rc[c * 100] if c * 100 < k < c * 100 + 100}
        for mid in sorted({m for m in info if m // 100 == c and m % 100 and info[m][5] == '城內設施'} | extra):
            if mid not in info or not rc[mid]: continue      # 冇任何 k2 觸發 (無出口) = 原版未用空房，跳過
            names = info[mid][7]; fx = next((k for k, w in _FAC_KW if w in names), None)
            out[mid] = '%s%s' % (cn, fx) if fx else '%s室內%02d' % (cn, mid % 100)
            tsets[mid] = info[mid][4]
        for m, n in ((c * 100 + 22, '道路B'), (c * 100 + 23, '道路A')):
            out[m] = cn + n; tsets[m] = info[m][4]
    return out, tsets
ROAD_GATES = {600089: 1923, 600865: 1922, 600857: 1722, 600861: 1822, 600868: 2022, 600872: 2622, 600820: 2822}      # 600857 = 陳留南邊整條寬觸發區 (同許昌 600865 類似)，暫定去道路B；道路A(1723) 未知入口
TILESET = {1907: 'grd02', 1923: 'grd00', 1700: 'grd00'}   # 其餘 grd03 (新城 tileset 見 NEW_TS)

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

NEW_INT, NEW_TS = _load_new_interiors()
ROADS |= {m: n for m, n in NEW_INT.items() if m % 100 in (22, 23)}
INTERIORS |= {m: n for m, n in NEW_INT.items() if m % 100 not in (22, 23)}
TILESET.update(NEW_TS)

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
    for f in ('Map', 'map21', 'map22'):
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
    targets = dict(INTERIORS); targets.update(ROADS); targets.update(FIELDS); targets.update(TOWNS)
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
            elif im.size[1] <= 300:
                # 矮嘅無碰撞裝飾 (草叢/地上雜物): 輪廓底下大部分格行得 = 角色會行入去 → 貼地，唔好蓋住角色
                bb = im.getchannel('A').getbbox()
                if bb:
                    c0, c1 = (x + bb[0]) // 16, (x + bb[2] - 1) // 16
                    r0, r1 = (y + bb[1]) // 16, (y + bb[3] - 1) // 16
                    cells = [(cx, cy) for cy in range(max(0, r0), min(gh - 1, r1) + 1) for cx in range(max(0, c0), min(gw - 1, c1) + 1)]
                    if cells and sum(1 for cx, cy in cells if not g[cy * gw + cx]) >= 0.6 * len(cells): o['floor'] = True
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

    b25 = built[1925]                              # 外圍 25: 正中加城池模型 (地面菱形擋路，城門口留空)
    g25 = bytearray(b25['g']); mcx, mcy, mhw, mhh = MODEL_DIAMOND
    for yy in range(b25['gh']):
        for xx in range(b25['gw']):
            if abs(xx * 16 + 8 - MODEL_XY[0] - mcx) / mhw + abs(yy * 16 + 8 - MODEL_XY[1] - mcy) / mhh <= 1: g25[yy * b25['gw'] + xx] = 1
    b25['g'] = bytes(g25); b25['out']['walk']['z'] = base64.b64encode(zlib.compress(bytes(g25), 9)).decode()
    ox2 = MODEL_XY[0]
    for nm in MODEL:
        b25['out']['objects'].append({'n': nm, 'x': ox2, 'y': MODEL_XY[1]}); b25['names'].add(nm); ox2 += Image.open(sidx[nm]).size[0]
    b25['out']['objects'].sort(key=lambda o: o['y'])
    # 地圖擺位: 全域格仔 x 0..511；許昌原版 (oy 644 + 188) 之下
    pos, bottom = shelf_pack([(m, b["gw"], b["gh"]) for m, b in built.items() if m not in FIELDS and m not in TOWNS], 512, 860)
    fitems = [(m, b["gw"], b["gh"]) for m, b in built.items() if m in FIELDS or m in TOWNS]
    fitems += [(m, 201, 151) for m in INSTANCES]
    fpos, bottom = shelf_pack(fitems, 512, bottom + 20)
    pos.update(fpos)
    print('地圖擺位完，最底行', bottom, '(WORLD_H 要 >=', bottom + 1, ')')
    if check: return
    # 城內門 / 工作區門 -> 城內 portal；室內出口 -> 返城
    portals = []; nodoor = []
    door_of = {}
    for cr in [rects[c * 100] for c in FULLCITIES]:
        for k, sub, x1, y1, x2, y2 in sorted(cr):
            if k in INTERIORS: door_of.setdefault(k, (x1, y1, x2, y2))
            elif k in ROAD_GATES: door_of[ROAD_GATES[k]] = (x1, y1, x2, y2)
    cityg = {19: (cg, cgw, cgh)} | {t // 100: (built[t]['g'], built[t]['gw'], built[t]['gh']) for t in TOWNS if t in built}
    for mid, b in sorted(built.items()):
        key = 'xc%d' % mid; g = b['g']; gw, gh = b['gw'], b['gh']
        if mid in FIELDS or mid in TOWNS:
            b['spawn'] = nearest_outside(g, gw, gh, (0, 0, -1, -1), (gw // 2, gh // 2)); continue
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
            cgrid, cgw, cgh = cityg[mid // 100]
            dx1, dy1, dx2, dy2 = door_of[mid]
            drc = [dx1 // 16, dy1 // 16, dx2 // 16, dy2 // 16]
            dcells = [c for c in rect_cells(drc, cgw, cgh) if walkable(cgrid, cgw, cgh, *c)]
            grow = 0
            while not dcells and grow < 4:
                grow += 1
                dcells = [c for c in rect_cells([drc[0] - grow, drc[1] - grow, drc[2] + grow, drc[3] + grow], cgw, cgh) if walkable(cgrid, cgw, cgh, *c)]
            if not dcells: print('警告: %d 城門口冇行得格' % mid); continue
            if grow: drc = [drc[0] - grow, drc[1] - grow, drc[2] + grow, drc[3] + grow]
            dc = dcells[len(dcells) // 2]
            city_land = nearest_outside(cgrid, cgw, cgh, drc, ((drc[0] + drc[2]) // 2, drc[3] + 2))
            portals.append({'id': 'xc_in_%d' % mid, 'name': '入 ' + b['cn'], 'map': CITY_MAPID[mid // 100], 'x': dc[0], 'y': dc[1],
                            'rect': drc, 'land': list(city_land), 'to': 'xc_out_%d' % mid, 'auto': True})
            portals.append({'id': 'xc_out_%d' % mid, 'name': '出 ' + b['cn'], 'map': key, 'x': ec[0], 'y': ec[1],
                            'rect': erc, 'land': list(in_land), 'to': 'xc_in_%d' % mid, 'auto': True})
        b['spawn'] = in_land
    # 外圍線 (外圍 <-> 對方外圍，地圖邊緣傳送) + 城圖邊緣口 <-> 本城外圍
    runs = {t: tpl_runs(built[1900 + t]['g'], built[1900 + t]['gw'], built[1900 + t]['gh']) for t in TPLS}
    cruns = {k: tpl_runs(*v) for k, v in cityg.items()}
    conns = plan_links(runs, cruns)
    for m, lst in conns.items(): place_slots(lst, lambda sd: runs[25][sd], built[1925]['gw'], built[1925]['gh'])
    pid = lambda m, c: 'xc_ln_%d_%s_%d' % (m, c['side'], c['idx'])
    for m, lst in sorted(conns.items()):
        for c in lst:
            back = [d for d in conns[c['other']] if d['other'] == m][0]
            portals.append({'id': pid(m, c), 'name': '去 ' + c['ocity'] + '外圍', 'map': 'xc%d' % m, 'x': c['cell'][0], 'y': c['cell'][1],
                            'rect': c['rect'], 'land': list(c['land']), 'to': pid(c['other'], back), 'auto': True})
    # 城口: 每城單一邊緣出口 <-> 本城外圍 25 正中城池模型門口。許昌 = 西邊緣 A 位 (用家確認)；其他城 = 西邊緣行得段
    gates = {}
    for city in sorted(cityg):
        gcg, gcw, gch = cityg[city]; out25 = city * 100 + 25
        if city == 19: rect, cell, land = GATE_W, (2, 157), (6, 157)
        else:
            side = 'W' if 'W' in cruns[city] else sorted(cruns[city])[0]; sl = [{'side': side, 'key': 0}]
            place_slots(sl, lambda sd: cruns[city][sd], gcw, gch); rect, cell = sl[0]['rect'], sl[0]['cell']
            land = tuple(nearest_outside(gcg, gcw, gch, rect, sl[0]['land']))
        gid, gido = ('xc_gate_w', 'xc_gate_w_o') if city == 19 else ('xc_gate_%d' % city, 'xc_gate_%d_o' % city)
        cx = (GATE_RECT[0] + GATE_RECT[2]) // 2; cy = (GATE_RECT[1] + GATE_RECT[3]) // 2
        portals.append({'id': gido, 'name': '入' + CITY_NAME[city] + '城', 'map': 'xc%d' % out25, 'x': cx, 'y': cy, 'rect': GATE_RECT,
                        'land': list(GATE_LAND), 'to': gid, 'auto': True})
        portals.append({'id': gid, 'name': '出城', 'map': CITY_MAPID[city], 'x': cell[0], 'y': cell[1], 'rect': rect, 'land': list(land), 'to': gido, 'auto': True})
        gates[city] = land
    # 由許昌可達: 外圍之間按連線
    reach = {1925}; ch = True
    while ch:
        ch = False
        for l in LINKS['links']:
            if (l['a_out'] in reach) != (l['b_out'] in reach): reach |= {l['a_out'], l['b_out']}; ch = True
    reach |= {t for t in TOWNS if t // 100 * 100 + 25 in reach}      # 城圖經本城外圍 25 嘅入城口到得
    for t in TOWNS:
        if t in built: built[t]['spawn'] = gates[t // 100]
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
        if mid in TOWNS:
            mj['maps'].append({'id': 'xc%d' % mid, 'name': b['cn'] + '（原版）', 'ox': ox, 'oy': oy, 'safe': True, 'kind': 'field', 'orig': 'xc%d' % mid,
                               'cityOf': CITY_SLUG[mid // 100], 'spawn': [sp[0], sp[1], sp[0], sp[1]]} | ({} if mid in reach else {'orphan': True}))
            continue
        mj['maps'].append({'id': 'xc%d' % mid, 'name': CITY_NAME[mid // 100] + '·' + b['cn'], 'ox': ox, 'oy': oy, 'safe': mid not in FIELDS,
                           'kind': 'field' if (mid in ROADS or mid in FIELDS) else 'house', 'orig': 'xc%d' % mid, 'cityOf': CITY_SLUG[mid // 100],
                           'spawn': [sp[0], sp[1], sp[0], sp[1]]}
                  | ({'orphan': True} if (mid in nodoor or mid in FIELDS) else {}))     # orphan = 未知城內門，暫時去唔到
    tplids = ('xc1925', 'xc1929', 'xc1949')            # 1929/1949 係 v1 舊模板，一併清走
    stale = {m['id'] for m in mj['maps'] if m['id'].startswith('xc') and m.get('orig') in tplids and m['id'] != 'xc1925' and int(m['id'][2:]) not in INSTANCES}
    for sid in stale:
        try: os.remove(os.path.join(ROOT, 'client', 'data', 'maps', sid + '.txt'))
        except OSError: pass
        if sid in ('xc1929', 'xc1949'):
            shutil.rmtree(os.path.join(ASSET, sid), ignore_errors=True)
            try: os.remove(os.path.join(DATA, sid + '.json'))
            except OSError: pass
    mj['maps'] = [m for m in mj['maps'] if m['id'] not in stale and m['id'] not in {'xc%d' % i for i in INSTANCES}]
    for mid in INSTANCES:
        ox, oy = pos[mid]; sp = conns[mid][0]['land']
        mj['maps'].append({'id': 'xc%d' % mid, 'name': CITY_NAME[mid // 100] + '·外圍%d' % (mid % 100), 'ox': ox, 'oy': oy, 'safe': False,
                           'kind': 'field', 'orig': 'xc1925',
                           'spawn': [sp[0], sp[1], sp[0], sp[1]]} | ({} if mid in reach else {'orphan': True}))
        shutil.copyfile(os.path.join(ROOT, 'client', 'data', 'maps', 'xc1925.txt'), os.path.join(ROOT, 'client', 'data', 'maps', 'xc%d.txt' % mid))
    for m in mj['maps']:
        if m['id'] in ('xc%d' % x for x in reach) and m.get('orphan'): del m['orphan']
    mj['portals'] = [p for p in mj['portals'] if not (p['id'].startswith('xc_in_') or p['id'].startswith('xc_out_') or p['id'].startswith('xc_ln_') or p['id'].startswith('xc_gate_'))] + portals
    open(MAPS, 'w', encoding='utf8', newline='\n').write(json.dumps(mj, ensure_ascii=False, indent=1) + '\n')
    print('傳送點', len(portals), '無城內門嘅室內圖', nodoor)
    print('OK, WORLD_H >=', bottom + 1)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('--check', action='store_true'); run(ap.parse_args().check)
