// 由 TS rules 導出測試向量 → tests/vectors/rules.json，供 Godot 版 rules 對拍
// 跑法: node tools/export_vectors.ts
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as C from '../legacy/server/src/rules/combat.ts';
import * as S from '../legacy/server/src/rules/stats.ts';
import * as H from '../legacy/server/src/rules/shop.ts';
import { loadData } from '../legacy/server/src/model.ts';

const data = loadData();
const seqRng = (seq: number[]) => { let i = 0; return () => seq[i++ % seq.length]; };
const RNGS = [[0], [0.5], [0.999], [0.1, 0.9], [0.9, 0.1], [0.25, 0.75, 0.5]];

type V = { fn: string; args: unknown[]; rng?: number[]; expect: unknown };
const out: V[] = [];
const add = (fn: string, args: unknown[], expect: unknown, rng?: number[]) => out.push({ fn, args, expect, ...(rng ? { rng } : {}) });

for (const agi of [0, 1, 8, 20, 27, 28, 40, 60, 100]) add('attackInterval', [agi], C.attackInterval(agi));
for (const lv of [1, 2, 5, 10, 50, 100]) add('playerDef', [lv], C.playerDef(lv));

for (const [str, wp, def] of [[12, 10, 0], [12, 10, 5], [30, 50, 10], [1, 0, 999], [50, 100, 20]])
  for (const r of RNGS) add('calcDamage', [str, wp, def], C.calcDamage(str, wp, def, seqRng(r)), r);
for (const [atk, def] of [[4, 0], [10, 3], [5, 100], [30, 10]])
  for (const r of RNGS) add('calcMobDamage', [atk, def], C.calcMobDamage(atk, def, seqRng(r)), r);
for (const [wh, al, dl] of [[45, 1, 1], [60, 1, 1], [30, 1, 1], [45, 10, 1], [45, 1, 10], [200, 50, 1], [0, 1, 50]])
  add('hitChance', [wh, al, dl], C.hitChance(wh, al, dl));
for (const [ax, ay, bx, by, rg] of [[0, 0, 1, 1, 1], [0, 0, 2, 1, 1], [5, 5, 5, 5, 1], [0, 0, 3, 0, 3], [0, 0, 4, 0, 3]])
  add('inRange', [ax, ay, bx, by, rg], C.inRange(ax, ay, bx, by, rg));

const drops = [{ item: 61501, p: 0.5 }, { item: 61502, p: 0.1 }, { item: 61503, p: 1 }];
for (const r of RNGS) add('rollDrops', [drops], C.rollDrops(drops, seqRng(r)), r);
for (const rg of [[0, 3], [5, 5], [10, 20]] as [number, number][])
  for (const r of RNGS) add('rollGold', [rg], C.rollGold(rg, seqRng(r)), r);
for (const [k, a] of [[0, -10], [0, 100], [29999, -1000], [-29999, 1000], [500, 0]]) add('karmaAfterKill', [k, a], C.karmaAfterKill(k, a));
for (const [k, e] of [[0, 100], [-1000, 100], [-1001, 100], [-20000, 999]]) add('deathExpLoss', [k, e], C.deathExpLoss(k, e));
const bag = [{ id: 1, n: 2 }, { id: 2, n: 1 }, { id: 3, n: 5 }];
for (const k of [0, -1000, -1001, -9000]) for (const r of RNGS) add('rollDeathDrop', [k, bag], C.rollDeathDrop(k, bag, seqRng(r)), r);
add('rollDeathDrop', [0, []], 0, [0]);

for (const [b, c] of [[100, 0], [100, 10], [100, 40], [100, 100], [1, 50], [0, 0]]) add('buyPrice', [b, c], H.buyPrice(b, c));
for (const b of [0, 1, 3, 100, 101]) add('sellPrice', [b], H.sellPrice(b));
{
  const b: H.Bag = [{ id: 1, n: 2 }];
  H.addItem(b, 1, 3); H.addItem(b, 9, 1);
  add('bag_add', [[{ id: 1, n: 2 }], [[1, 3], [9, 1]]], b);
  const b2: H.Bag = [{ id: 1, n: 2 }];
  const r1 = H.removeItem(b2, 1, 1), r2 = H.removeItem(b2, 1, 5), r3 = H.removeItem(b2, 1, 1), r4 = H.removeItem(b2, 7, 1);
  add('bag_remove', [[{ id: 1, n: 2 }], [[1, 1], [1, 5], [1, 1], [7, 1]]], { bag: b2, results: [r1, r2, r3, r4] });
}

for (const lv of [1, 2, 5, 10, 50, 100]) {
  const a = S.attrsAt(data.classes.get('yishi')!, lv);
  add('maxHp', [lv, a], S.maxHp(lv, a)); add('maxMp', [lv, a], S.maxMp(lv, a)); add('maxSp', [lv, a], S.maxSp(lv, a));
  add('expToNext', [lv], S.expToNext(lv));
}
for (const cls of data.classes.values()) for (const lv of [1, 5, 50]) add('attrsAt', [cls.id, lv], S.attrsAt(cls, lv));
add('createCharacter', ['義士甲', 'yishi'], S.createCharacter(data, '義士甲', 'yishi'));
for (const amt of [0, 10, 100, 477, 5000, 1e6]) {
  const ch = S.createCharacter(data, '測', 'yishi');
  const before = structuredClone(ch);
  const ups = S.gainExp(data, ch, amt);
  add('gainExp', [before, amt], { ch, ups });
}

const dir = fileURLToPath(new URL('../tests/vectors/', import.meta.url));
mkdirSync(dir, { recursive: true });
writeFileSync(dir + 'rules.json', JSON.stringify(out, null, 1));
console.log(`vectors: ${out.length} -> tests/vectors/rules.json`);
