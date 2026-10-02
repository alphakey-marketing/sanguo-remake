"""原版洞穴/營地怪 -> client/data/monsters.json (只加新怪，唔郁現有; 可重跑)
來源: spawn_maps.tsv (各洞穴圖怪名: 野獸怪 + 敵對人形) + Npc_table.tsv (id/name)；數值按 spec 04 §1 模板【自訂】。
id = 原版 npc id (同名多個 id 時揀有掉落嘅、再揀最細)；掉落由 import_drops.py 補 (dropSrc=自己 id)。
各城洞穴等級帶 CAVE_BAND (spec 04 §2)；每個怪名取佢出現過嘅洞穴圖 (城,層) 嘅平均等級。
用法: python tools/import_orig_monsters.py [--check]"""
import csv, json, sys, os, collections
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MP = os.path.join(ROOT, 'client/data/monsters.json')
ML = 'D:/Download/sanguo/extracted/map_list/'
TX = 'D:/Download/sanguo/extracted/text/'
# 城id -> 洞穴等級帶 (lo, hi)；spec 04 §2 有嘅用原文，冇嘅按鄰近帶估【自訂】
CAVE_BAND = {11: (81, 90), 16: (14, 40), 17: (20, 35), 18: (1, 10), 20: (5, 20), 22: (51, 60), 23: (46, 50),
             24: (15, 30), 25: (25, 45), 27: (14, 25), 28: (51, 60), 30: (40, 50), 32: (30, 45)}
def cave_level(city, floor): lo, hi = CAVE_BAND[city]; return round(lo + (hi - lo) * (floor - 1) / 4)

def main(check=False):
    d = json.load(open(MP, encoding='utf8')); mons = d['monsters']
    have_n = {m['name'] for m in mons}; have_id = {m['id'] for m in mons}
    tab = collections.defaultdict(list)
    for r in list(csv.reader(open(TX + 'Npc_table.tsv', encoding='utf8'), delimiter='\t'))[1:]: tab[r[1]].append(int(r[0]))
    for r in csv.reader(open(TX + 'npc_drops.csv', encoding='utf-8-sig')):
        if r and r[0].isdigit() and int(r[0]) not in tab[r[1]]: tab[r[1]].append(int(r[0]))
    for ln in open(TX + 'Npc_Client_names.txt', encoding='utf8'):
        t = ln.split(None, 1)
        if len(t) == 2 and t[0].isdigit() and int(t[0]) not in tab[t[1].strip()]: tab[t[1].strip()].append(int(t[0]))
    drops = {int(r[0]): int(r[3]) for r in csv.reader(open(TX + 'npc_drops.csv', encoding='utf-8-sig')) if r and r[0].isdigit()}
    lv = collections.defaultdict(list)
    for r in list(csv.reader(open(ML + 'spawn_maps.tsv', encoding='utf8'), delimiter='\t'))[1:]:
        if r[4] != '洞穴/營地': continue
        mid = int(r[0]); city, floor = mid // 100, mid % 100 - 50
        if city not in CAVE_BAND or not 1 <= floor <= 5: continue
        for col in (5, 6):
            for n in r[col].split('、'):
                if n: lv[n].append(cave_level(city, floor))
    spr = {}                                  # 名 -> okm sprite (洞穴圖 okm 記錄)
    for r in list(csv.reader(open(ML + 'okm_records.tsv', encoding='utf8'), delimiter='	'))[1:]:
        if int(r[0]) // 100 in CAVE_BAND and 1 <= int(r[0]) % 100 - 50 <= 5: spr.setdefault(r[2], int(r[3]))
    base = {n.rstrip('0123456789') for n in have_n}
    nextid = 70000 + max([i for i in have_id if 70000 <= i < 80000] or [69999]) - 69999
    pool = [m for m in mons if m.get('dropSrc') and not m.get('orig')]
    def near(L): return min(pool, key=lambda m: (abs(m['level'] - L), m['id']))['dropSrc']     # 表冇嘅怪借最近等級怪嘅掉落表【自訂】
    new = []
    for n, ls in sorted(lv.items()):
        if n in have_n or n in base: continue
        ids = sorted(tab.get(n, []), key=lambda i: (-drops.get(i, 0), i))
        L = max(1, round(sum(ls) / len(ls)))
        if ids: i = ids[0]
        elif n in spr: i = nextid; nextid += 1      # 表冇 -> 合成 id (70000+)，sprite 取 okm
        else: print('冇 npc 表亦冇 sprite:', n); continue
        if i in have_id: print('id 撞:', n, i); continue
        new.append({'id': i, 'name': n, 'level': L, 'hp': 10 * L * L + 20, 'atk': 3 * L + 4, 'def': max(0, L // 4),
                    'atkInterval': 20, 'moveSpeed': 1, 'exp': 6 + 3 * L, 'gold': [0, 3 * L], 'alignment': -30,
                    'aggroRange': 5, 'leash': 10, 'element': 'none', 'dropSrc': i if ids else near(L), 'orig': True} | ({'sprite': spr[n]} if n in spr else {}))
    print('新增怪', len(new), [m['name'] for m in new][:80])
    if check: return
    mons.extend(new)
    json.dump(d, open(MP, 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
if __name__ == '__main__': main('--check' in sys.argv)
