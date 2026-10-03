#!/usr/bin/env python3
"""原版特殊場景模板圖匯入 (通天關 5061~5068 / 異族禁地 5283~5289 / 七彩奪寶陣晶孟獲 5255~5261)。
只出 orig_maps/xc<id>.json + assets_orig/maps/xc<id>/ + data/maps/xc<id>.txt (模板)，唔郁 maps.json
(擺位/instance 由 tools/gen_scenes.py 做，跟 gen_battles)。借用 import_orig_interiors 嘅解析/行走層函數。
用法: python tools/import_orig_scene_maps.py"""
import sys, os, json, base64, zlib, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import import_orig_interiors as I
from PIL import Image

NAMES = {}
NAMES.update({m: '通天關擂台%d' % (m - 5060) for m in range(5061, 5069)})
NAMES.update({m: '異族禁地第%d關' % (m - 5282) for m in range(5283, 5290)})
NAMES.update({5260: '七彩·紫晶', 5258: '七彩·靛晶', 5255: '七彩·藍晶', 5259: '七彩·綠晶', 5256: '七彩·黃晶', 5261: '七彩·橙晶', 5257: '七彩·紅晶'})
TS = {5256: 'grd02', 5258: 'grd02', 5259: 'grd02', 5260: 'grd00'}   # named_locations.tsv tileset 欄


def main():
    sidx = I.sprite_index()
    for mid, cn in sorted(NAMES.items()):
        name = '%05d' % mid
        mrgname, m = I.open_mrg(name)
        if m is None:
            print('跳過 %d: 解析唔到' % mid); continue
        i = m.names.index(name); d = I.parse(m.blob(i))
        gw, gh, g = I.build_walk(d)
        ts = TS.get(mid, 'grd03'); tdir = I.SP + 'grd_' + ts + '/'
        tiles = {int(f.split('_')[0]): tdir + f for f in os.listdir(tdir)}
        for alt in ('grd00', 'grd02', 'grd01', 'grd03'):
            for f in os.listdir(I.SP + 'grd_' + alt): tiles.setdefault(int(f.split('_')[0]), I.SP + 'grd_' + alt + '/' + f)
        used = sorted(set(d['tiles'])); remap = {v: n for n, v in enumerate(used)}
        miss = [v for v in used if v not in tiles]
        objs = []; names = set()
        for n, x, y in d['objs']:
            k = n.lower().rsplit('.', 1)[0]
            if k not in sidx: continue
            o = {'n': k, 'x': x, 'y': y}
            im = Image.open(sidx[k]).convert('RGBA')
            if min(im.size) >= 250 and im.getchannel('A').getextrema()[0] == 255: o['floor'] = True
            elif im.size[1] <= 300:
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
        with open(os.path.join(I.DATA, key + '.json'), 'w', encoding='utf8') as f: json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
        ad = os.path.join(I.ASSET, key); os.makedirs(ad + '/obj', exist_ok=True)
        rws = (len(used) + 31) // 32; at = Image.new('RGBA', (32 * 48, max(1, rws) * 48))
        for n, v in enumerate(used):
            if v in tiles: at.paste(Image.open(tiles[v]).convert('RGBA'), ((n % 32) * 48, (n // 32) * 48))
        at.save(ad + '/atlas.png')
        for k in names: shutil.copyfile(sidx[k], ad + '/obj/%s.png' % k)
        with open(os.path.join(I.ROOT, 'client', 'data', 'maps', key + '.txt'), 'w', encoding='utf8', newline='\n') as f:
            f.write('\n'.join(''.join('H' if g[y * gw + x] else '.' for x in range(gw)) for y in range(gh)) + '\n')
        print(key, cn, d['W'], d['H'], '格', gw, gh, '物件', len(objs), '缺tile', len(miss))


if __name__ == '__main__':
    main()
