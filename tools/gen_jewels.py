# -*- coding: utf-8 -*-
# 由 items.json 生成 jewels.json (Step 10, spec 02 §4)
# 屬性石(41-44) / 特殊石(46-51) / 輔助石(effects 其餘 cat47) / 融合寶石(cat39)
import json, io, sys
def load(p):
    return json.load(io.open(p, encoding='utf-8'))
items = load('client/data/items.json')
ELEM_BY_T = {41:'wind', 42:'earth', 43:'water', 44:'fire'}
SPECIAL_BY_T = {46:'wind', 47:'earth', 48:'water', 49:'fire', 50:'none', 51:'life'}
stones, special, support, fusable = [], [], [], []
for it in items:
    if not (it['cat'] == 47 or it['cat'] == 39):
        continue
    effs = [e for e in it.get('effects', [])]
    t = effs[0]['type'] if effs else 0
    rec = {'id': it['id'], 'name': it['name'], 'cat': it['cat'], 'effects': effs}
    if t in ELEM_BY_T and it['cat'] == 47:
        rec['elem'] = ELEM_BY_T[t]
        rec['pct'] = effs[0]['value']
        stones.append(rec)
    elif t in SPECIAL_BY_T:
        rec['elem'] = SPECIAL_BY_T[t]
        special.append(rec)
    elif it['cat'] == 47:
        support.append(rec)
    else:
        fusable.append(rec)
out = {
  '_note': '寶石目錄 (Step 10, spec 02 §4)。由 tools/gen_jewels.py 由 items.json 生成，唔好手改。' \
    'stones=屬性石(風/地/水/火×10階, pct=10..100)；special=大範圍施放石(元素術解鎖)；' \
    'support=輔助效果(著裝即生效, rules/jewel.gd support_bonus)；fusable=融合材料(cat39, 鑲武器用 Step 12 加)。',
  'stones': sorted(stones, key=lambda r: r['id']),
  'special': sorted(special, key=lambda r: r['id']),
  'support': sorted(support, key=lambda r: r['id']),
  'fusable': sorted(fusable, key=lambda r: r['id']),
}
json.dump(out, io.open('client/data/jewels.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('stones', len(out['stones']), 'special', len(out['special']), 'support', len(out['support']), 'fusable', len(out['fusable']))
