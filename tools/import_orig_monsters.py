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
CAVE_BAND = {11: (51, 80), 16: (14, 40), 17: (21, 50), 18: (46, 50), 20: (5, 20), 22: (51, 60), 23: (46, 50),
             24: (61, 70), 25: (25, 45), 27: (81, 90), 28: (51, 60), 30: (71, 80), 32: (61, 70)}
# 依用家 Drive 攻略：汝南/濮陽/晉陽/譙/桂陽/長沙/宛 按怪名對上 (可靠)；其餘 6 組 (11/17/24/27/30/32) 對應攻略 鄴/廬江/襄平/建業/一轉/二轉神秘，按怪名猜【猜】
GUIDE_EXTRA = {22: '光頭劍客 匕首流氓 武棍流氓 銀甲劍兵 光頭射手 青甲劍兵 短刀地痞 金甲劍兵 破斧土匪 銀甲弓兵 長劍士兵 山賊劍手 輕裝劍客 金甲弓兵 飛賊劍手 護甲劍客 紅髮地痞 金裝甲兵 野戰劍將 金鎧劍將 長矛土匪'.split(),
               28: '光頭劍客 匕首流氓 武棍流氓 銀甲劍兵 光頭射手 青甲劍兵 短刀地痞 金甲劍兵 破斧土匪 銀甲弓兵 長劍士兵 山賊劍手 輕裝劍客 金甲弓兵 飛賊劍手 護甲劍客 紅髮地痞 金裝甲兵 野戰劍將 金鎧劍將 長矛土匪'.split()}   # 攻略長沙/宛 名單 (spawn_maps 冇)
def cave_level(city, floor): lo, hi = CAVE_BAND[city]; return round(lo + (hi - lo) * (floor - 1) / 4)

def main(check=False):
    d = json.load(open(MP, encoding='utf8')); d['monsters'] = mons = [m for m in d['monsters'] if not m.get('orig')]   # 重跑先清走上次匯入嘅，等級帶改咗會更新
    have_n = {m['name'] for m in mons}; have_id = {m['id'] for m in mons}
    tab = collections.defaultdict(list)
    for r in list(csv.reader(open(TX + 'Npc_table.tsv', encoding='utf8'), delimiter='\t'))[1:]: tab[r[1]].append(int(r[0]))
    for r in csv.reader(open(TX + 'npc_drops.csv', encoding='utf-8-sig')):
        if r and r[0].isdigit() and int(r[0]) not in tab[r[1]]: tab[r[1]].append(int(r[0]))
    for ln in open(TX + 'Npc_Client_names.txt', encoding='utf8'):
        t = ln.split(None, 1)
        if len(t) == 2 and t[0].isdigit() and int(t[0]) not in tab[t[1].strip()]: tab[t[1].strip()].append(int(t[0]))
    drops = {int(r[0]): int(r[3]) for r in csv.reader(open(TX + 'npc_drops.csv', encoding='utf-8-sig')) if r and r[0].isdigit()}
    lv = collections.defaultdict(list); rows_cave = []
    for r in list(csv.reader(open(ML + 'spawn_maps.tsv', encoding='utf8'), delimiter='\t'))[1:]:
        if r[4] != '洞穴/營地': continue
        mid = int(r[0]); city, floor = mid // 100, mid % 100 - 50
        if city not in CAVE_BAND or not 1 <= floor <= 5: continue
        ex = GUIDE_EXTRA.get(city, [])[floor - 1::5]            # 攻略名單按層攤 (每層取 1/5)
        rows_cave.append((mid, [n for col in (5, 6, 7) for n in r[col].split('、') if n] + ex))
        for col in (5, 6, 7):
            for n in r[col].split('、') + ex:
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
    d['spawns'] = [x for x in d['spawns'] if not x.get('orig')] + gen_spawns(mons, rows_cave)
    hid = {m['id'] for m in mons if m.get('orig') and m['name'] in NO_SPRITE_HIDE}      # 冇圖又冇相似圖可借 -> 唔出場 (搵到圖包後清空 NO_SPRITE_HIDE 重跑)
    d['spawns'] = [x for x in d['spawns'] if x['monster'] not in hid]
    ix = os.path.join(ROOT, 'client/data/asset_index.json')
    if os.path.exists(ix):       # 野外怪冇 sprite (亦冇 BORROW 借圖) = 唔出場；任務怪/boss 唔受影響 (非 orig spawn)
        have = json.load(open(ix, encoding='utf8')).get('mon_S', {})
        d['spawns'] = [x for x in d['spawns'] if not x.get('orig') or str(x['monster']) in have]
    json.dump(d, open(MP, 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
# 外圍野怪名單: 官方攻略 (docs/plan/ORIG_MONSTERS.md 來源 = 用家 Drive 攻略截圖) 按州分；各州適合等級 荊/豫/并司 1-10、兗徐 10-20
WILD = {'荊': '田鼠 水鴨 野兔 蜻蜓 野貂 母雞 猴子 瘋貓 野豬 飛蛾怪 流氓', '豫': '田鼠 水鴨 野兔 野貂 母雞 公雞 山羊 瘋貓 野豬 流氓',
        '并司': '田鼠 水鴨 野兔 蝴蝶精 野貂 母雞 山羊 瘋貓 野豬 盜賊 流氓', '兗徐': '野狗 狐貍 花鹿 大蟒 黃蜂 野狼 野牛 花豹 老虎 大熊 流氓 地痞'}
REGION = {'荊': (29, 27, 28, 30, 21, 22, 31, 32, 23), '豫': (19, 18, 20, 17), '并司': (26, 24, 25, 34, 33, 35, 36, 37, 38, 39)}   # 其餘城用兗徐 (近似【自訂】)
# 缺 sprite 又冇相似圖可借，暫時隱藏嘅怪 (見 import_orig_assets.BORROW 借圖表)
NO_SPRITE_HIDE = {'野豬', '野牛', '山羊', '花鹿', '洞窟獸王'}
NEWBIE_WILD = '田鼠 水鴨 野兔 野豬'     # 許昌外圍 = 新手區【自訂】: 只留 Lv<=7，每種 4 隻；高級怪 (Lv9~14) 去鄰近外圍 (洛陽/譙/陳留/宛)
def gen_spawns(mons, rows):
    import re
    by = {}
    for m in mons: by.setdefault(m['name'].rstrip('0123456789'), m['id'])
    lvl = {m['id']: m['level'] for m in mons}
    mj = json.load(open(os.path.join(ROOT, 'client/data/maps.json'), encoding='utf8'))['maps']
    ids = {m['id'] for m in mj}; out = []
    def dims(mid):
        g = open(os.path.join(ROOT, 'client/data/maps/%s.txt' % mid), encoding='utf8').readline().rstrip(); return len(g)
    for mid, names in rows:
        z = 'xc%d' % mid
        if z not in ids: continue
        n = 4 if dims(z) >= 300 else 3
        for nm in names:
            if nm in by: out.append({'zone': z, 'monster': by[nm], 'count': n, 'respawnTicks': 300, 'orig': True, 'lv': cave_level(mid // 100, mid % 100 - 50)})   # 每層一個等級 (spawn 級別覆蓋)
    for c in range(1, 40):
        z = 'xc%d25' % c
        if z not in ids: continue
        reg = next((k for k, v in REGION.items() if c in v), '兗徐')
        lo, hi = (10, 20) if reg == '兗徐' else (1, 10)                    # 攻略外圍等級帶
        names, cnt = (WILD[reg].split(), 1) if c != 19 else (NEWBIE_WILD.split(), 5)
        for nm in names:
            if nm in by: out.append({'zone': z, 'monster': by[nm], 'count': cnt, 'respawnTicks': 300, 'orig': True, 'lv': min(hi, max(lo, lvl[by[nm]]))})
    return out
if __name__ == '__main__': main('--check' in sys.argv)
