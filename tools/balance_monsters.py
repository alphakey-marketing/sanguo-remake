"""怪物數值平衡 (docs/spec/14_怪物數值.md)：全部怪 (orig + 舊手寫) hp/atk/def/exp/gold 按等級曲線 + 原版怪表強弱系數重算。
曲線/kills = client/data/mob_curve.json；升級表 = client/rules/exp_table.gd；同引擎 rules/mob_scale.gd 同一公式。
冪等，要喺 import_orig_monsters.py / import_drops.py 之後跑 (importer 會重置 orig 怪數值)。
用法: python tools/balance_monsters.py [--check] [--report]"""
import csv, json, math, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MP = os.path.join(ROOT, 'client/data/monsters.json')
CV = json.load(open(os.path.join(ROOT, 'client/data/mob_curve.json'), encoding='utf8'))
src = open(os.path.join(ROOT, 'client/rules/exp_table.gd'), encoding='utf8').read()
EXP = [int(x) for x in re.findall(r'\d+', src.split('const LV := [')[1].split(']')[0])]
TBL = 'D:/Download/sanguo/extracted/text/Npc_table.tsv'
def need(lv): return EXP[0] if lv < 1 else EXP[min(lv, len(EXP)) - 1]
def curve(lv, k):
    a = CV['anchors']
    if lv <= a[0][0]: return max(float(a[0][k + 1]), 0.0)
    for i in range(1, len(a)):
        if lv <= a[i][0]:
            l0, l1, y0, y1 = a[i-1][0], a[i][0], a[i-1][k+1], a[i][k+1]; t = (lv - l0) / (l1 - l0)
            return y0 + (y1 - y0) * t if y0 <= 0 or y1 <= 0 else math.exp(math.log(y0) + (math.log(y1) - math.log(y0)) * t)
    return float(a[-1][k + 1])
def kills(lv):
    for lim, n in CV['kills']:
        if lv <= lim: return n
    return CV['kills'][-1][1]
def exp_at(lv): return max(1, round(need(lv) / kills(lv)))
BOSS_HP = 4.0
def strength(tbl_hp):          # 原版怪表 hp 欄 = 強弱指標 (中位 ~80)；無表 (合成 id) = 1.0
    return 1.0 if not tbl_hp else min(1.8, max(0.7, (tbl_hp / 80) ** 0.5))
def balanced(m, tbl_hp):
    L = m['level']; f = strength(tbl_hp)
    bm = BOSS_HP if m.get('boss') else 1.0                  # boss: hp ×4、atk ×1.5
    b = {'hp': max(1, round(curve(L, 0) * f * bm)), 'atk': max(1, round(curve(L, 1) * f ** 0.5 * (1.5 if m.get('boss') else 1.0))),
         'def': round(curve(L, 2)), 'exp': exp_at(L) * (3 if m.get('boss') else 1)}
    if not m.get('orig'):                                   # 手寫舊怪：gold 保留；exp 原本 0 (任務 boss/歷史怪) 保持 0
        b['gold'] = m.get('gold', [0, 0])
        if m.get('exp', 1) == 0: b['exp'] = 0
    else: b['gold'] = [0, 3 * L]
    return b
def main(check, report):
    d = json.load(open(MP, encoding='utf8'))
    tbl = {int(r[0]): int(r[3]) for r in list(csv.reader(open(TBL, encoding='utf8'), delimiter='\t'))[1:] if r[0].isdigit()}
    bad = 0; rows = []
    for m in d['monsters']:
        b = balanced(m, tbl.get(m['id']))
        if any(m[k] != v for k, v in b.items()): bad += 1
        rows.append((m['level'], m['id'], b))
        if not check: m.update(b)
    if report:
        for L, i, b in sorted(rows): print('Lv%3d id%-6d hp%-7d atk%-5d def%-4d exp%-6d' % (L, i, b['hp'], b['atk'], b['def'], b['exp']))
    if check: print('[balance] --check', 'OK' if not bad else 'FAIL %d 隻同曲線不符 (跑 tools/balance_monsters.py)' % bad); sys.exit(1 if bad else 0)
    json.dump(d, open(MP, 'w', encoding='utf8', newline='\n'), ensure_ascii=False, indent=1)
    print('[balance] 重算 %d 隻 orig 怪' % len(rows))
if __name__ == '__main__': main('--check' in sys.argv, '--report' in sys.argv)
