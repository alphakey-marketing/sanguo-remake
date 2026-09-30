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
        out = {'key': key, 'name': cn, 'orig': {'mrg': mrg, 'id': name, 'idx': i}, 'W': d['W'], 'H': d['H'],
               'tile': 48, 'cols': cols, 'rows': rows, 'atlas_cols': 32,
               'tiles': [remap[v] for v in d['tiles']], 'objects': sorted(objs, key=lambda o: o['y']),
               'walk': {'w': gw, 'h': gh, 'z': base64.b64encode(w[4:]).decode()}}
        print(key, cn, d['W'], d['H'], 'tile 種', len(used), '物件', len(objs), '物件圖', len(names), 'walk', gw, gh)
        if check: continue
        with open(os.path.join(DATA, key + '.json'), 'w', encoding='utf8') as f: json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
        ad = os.path.join(ASSET, key); os.makedirs(ad + '/obj', exist_ok=True)
        rws = (len(used) + 31) // 32; at = Image.new('RGBA', (32 * 48, rws * 48))
        for n, v in enumerate(used):
            if v in tiles: at.paste(Image.open(TS + tiles[v]).convert('RGBA'), ((n % 32) * 48, (n // 32) * 48))
        at.save(ad + '/atlas.png')
        for k in names: shutil.copyfile(sidx[k], ad + '/obj/%s.png' % k)
        print('  資產', ad, '%.1f MB' % (sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(ad) for f in fs) / 1e6))
    if errs:
        print('錯:'); [print(' -', e) for e in errs[:20]]; sys.exit(1)
    print('OK')

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('--check', action='store_true'); run(ap.parse_args().check)
