"""玩家 vs 同級怪 戰鬥估算 (docs/spec/14_怪物數值.md §5)。玩家模型 = 武士類全點武力 + 武器強度 max(10, 2.5L) (items.json 各級最強武器約 2.5×等級)。
rules/combat.gd: 傷害=1.5*武+武器-防；攻速 max(6, 20-agi*0.5) tick；怪 20 tick。
用法: python tools/sim_balance.py [--solve]   (--solve 印出達到目標嘅曲線錨點)"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import balance_monsters as B
LV = [1, 3, 8, 15, 28, 43, 60, 80, 95, 130, 180]
def player(L):
    s = 12 + 5 * (L - 1); agi = 8 + (L - 1)
    return {'dmg': 1.5 * s + max(10, 2.5 * L), 'hp': 60 + 15 * L + 4 * s, 'def': L // 2, 'iv': max(6, round(20 - agi * 0.5))}
def fight(L, H, A, D):
    p = player(L); n = H / max(1, p['dmg'] - D); t = n * p['iv']          # tick
    taken = t / 20 * max(1, A - p['def'])
    return n, taken / p['hp']
def target(L, D):                                                         # 目標: 打 n 下死，損失 f 血
    n = 3 + L / 10; f = 0.12 + 0.13 * min(L, 60) / 60
    p = player(L)
    return round(n * (p['dmg'] - D)), round(f * p['hp'] / (n * p['iv'] / 20) + p['def'])
if '--solve' in sys.argv:
    out = []
    for L in LV:
        D = round(0.6 * L, 1) if L > 1 else 0; H, A = target(L, D); out.append([L, H, A, round(D, 1)])
    print(json.dumps(out))
else:
    print('Lv   n(打幾下死怪)  損失血% | 玩家hp dmg  怪hp atk def exp | 殺幾多隻升級(含升級表)')
    for L in LV + [100, 120]:
        H, A, D = B.curve(L, 0), B.curve(L, 1), B.curve(L, 2); n, f = fight(L, H, A, D); p = player(L)
        print('%3d  %6.1f  %6.0f%%  | %6d %5d  %7d %5d %4d %7d | %d 隻' % (L, n, f * 100, p['hp'], p['dmg'], H, A, D, B.exp_at(L), B.kills(L)))
