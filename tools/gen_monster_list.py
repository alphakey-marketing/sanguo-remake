"""生成 docs/plan/ORIG_MONSTERS.md: 各洞穴層怪名單 + 等級 + 缺 sprite 清單 (讀 monsters.json / asset_index.json / spawn_maps.tsv)"""
import csv, json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from import_orig_monsters import CAVE_BAND, cave_level
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ML = 'D:/Download/sanguo/extracted/map_list/'
mons = json.load(open(ROOT + '/client/data/monsters.json', encoding='utf8'))['monsters']
idx = json.load(open(ROOT + '/client/data/asset_index.json', encoding='utf8'))
by = {}
for m in mons: by.setdefault(m['name'].rstrip('0123456789'), m)
have = lambda m: str(m['id']) in idx['mon_S']
names = {}
for r in list(csv.reader(open(ML + 'locations.tsv', encoding='utf8'), delimiter='\t'))[:0]: pass
CITY = {11: '吳', 16: '濮陽', 17: '陳留', 18: '許昌', 20: '汝南', 22: '長沙', 23: '桂陽', 24: '河內', 25: '晉陽', 27: '新野', 28: '宛', 30: '江陵', 32: '零陵'}
o = ['# 原版洞穴怪名單', '', '由 `tools/gen_monster_list.py` 生成。等級 = 該城洞穴等級帶 (spec 04 §2) 按層線性內插【自訂】，之後可調平衡。',
     '圖示：✅ 有原版 sprite　⚠️ 缺 sprite (原圖包冇，遊戲內退回舊色塊/舊圖，**冇借用任何武將 sprite**)', '']
rows = list(csv.reader(open(ML + 'spawn_maps.tsv', encoding='utf8'), delimiter='\t'))[1:]
missing = {}
for city in CAVE_BAND:
    o += ['## %s (城 %d，等級帶 %d–%d)' % (CITY[city], city, *CAVE_BAND[city]), '']
    for r in sorted(rows, key=lambda r: int(r[0])):
        mid = int(r[0])
        if mid // 100 != city or not 1 <= mid % 100 - 50 <= 5 or r[4] != '洞穴/營地': continue
        fl = mid % 100 - 50
        ns = [n for c in (5, 6) for n in r[c].split('、') if n]
        parts = []
        for n in ns:
            m = by.get(n)
            if not m: parts.append(n + '(?)'); continue
            ok = have(m)
            if not ok: missing[m['name']] = m
            parts.append('%s%s' % ('✅' if ok else '⚠️', m['name']))
        o.append('- 第%d層 (map %d) Lv%d：%s' % (fl, mid, cave_level(city, fl), '、'.join(parts) or '（無怪）'))
    o.append('')
o += ['## 外圍 (xx25) 野外怪', '', '尚未做。下一步按各城所屬區域、用原版怪替換自創怪後補入此表。', '',
      '## 缺 sprite 清單 (%d 隻)' % len(missing), '', '| id | 名 | 原 sprite 編號 | 現時顯示 |', '|---|---|---|---|']
for m in sorted(missing.values(), key=lambda m: m['id']):
    o.append('| %d | %s | %s | 舊色塊 (未借用武將圖) |' % (m['id'], m['name'], m.get('sprite', '—')))
open(ROOT + '/docs/plan/ORIG_MONSTERS.md', 'w', encoding='utf8', newline='\n').write('\n'.join(o) + '\n')
print('OK', len(missing))
