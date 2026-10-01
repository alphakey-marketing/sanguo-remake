# 功能 NPC 接原版: 每個商店/設施/客棧加 "npc": {name, sprite} (原版名 + okm_records 嘅 sprite 編號)
# 原版 52xxx 人形圖我哋冇 (見 docs/plan/ORIG_MAPS_PLAN.md)，client 用通用人形頂住，補圖後唔使改資料。
# 用法: python tools/set_orig_npc_names.py   (可重跑)
import json, os
C = os.path.join(os.path.dirname(__file__), '..', 'client', 'data')

SHOP = {
 'weapon': ('武器商', 52081), 'armor': ('超級奸商', 52123), 'tool': ('工具商', 52121),
 'herbalist': ('藥房掌櫃', 52061), 'food': ('肉販', 52111), 'grocery': ('雜貨商', 52021),
}
FAC = {
 'training': ('民團校尉', 21022), 'trainer': ('練兵將', 20151), 'school': ('夫子', 52181),
 'temple': ('廟公', 52051), 'forge': ('打鐵鋪掌櫃', 52131), 'workshop': ('木工廠掌櫃', 52211),
 'kitchen': ('大廚', 52211), 'pharmacy': ('煉丹師傅', 52051), 'donate_xc': ('地方功曹', 52183),
 'stable_xc': ('馬廄老闆', 52131), 'station_xc': ('驛站長', 52071),
}
INN = ('客棧掌櫃', 52061)

def jl(f): return json.load(open(os.path.join(C, f), encoding='utf8'))
def jw(f, d):
    open(os.path.join(C, f), 'w', encoding='utf8', newline='\n').write(json.dumps(d, ensure_ascii=False, indent=1) + '\n')

sh = jl('shops.json')
sh['inn']['npc'] = {'name': INN[0], 'sprite': INN[1]}
for s in sh['shops']:
    if s['id'] in SHOP and (s['map'] == 'xuchang_o' or s['map'].startswith('xc')):
        s['npc'] = {'name': SHOP[s['id']][0], 'sprite': SHOP[s['id']][1]}
jw('shops.json', sh)

fc = jl('facilities.json')
for k, v in fc.items():
    if isinstance(v, dict) and k in FAC:
        v['npc'] = {'name': FAC[k][0], 'sprite': FAC[k][1]}
jw('facilities.json', fc)
print('ok')
