import { test } from 'node:test';
import assert from 'node:assert/strict';
import { World } from './world.ts';
import * as C from './rules/combat.ts';
import { expToNext } from './rules/stats.ts';

test('傷害: 至少 1；隨機範圍 0.9~1.1；防禦扣減', () => {
  assert.equal(C.calcDamage(1, 0, 999), 1);
  assert.equal(C.calcDamage(10, 10, 0, () => 0.5), 25);
  assert.equal(C.calcDamage(10, 10, 5, () => 0.5), 20);
  assert.ok(C.calcDamage(10, 10, 0, () => 0) >= 22 && C.calcDamage(10, 10, 0, () => 0.999) <= 28);
});

test('攻速: 敏捷越高越快，有下限', () => {
  assert.ok(C.attackInterval(20) < C.attackInterval(5));
  assert.equal(C.attackInterval(1000), 6);
});

test('命中率夾喺 0.3~0.98；等級高命中高', () => {
  assert.ok(C.hitChance(45, 10, 1) <= 0.98);
  assert.ok(C.hitChance(45, 1, 30) >= 0.3);
  assert.ok(C.hitChance(45, 5, 1) > C.hitChance(45, 1, 5));
});

test('掉落/善惡/死亡處分', () => {
  assert.deepEqual(C.rollDrops([{ item: 1, p: 1 }, { item: 2, p: 0.5 }], () => 0.6), [1]);
  assert.equal(C.rollGold([3, 3]), 3);
  assert.equal(C.karmaAfterKill(0, -200), 20);          // 殺惡加善惡值
  assert.equal(C.karmaAfterKill(29999, -1000), 30000);
  assert.equal(C.deathExpLoss(0, 100), 10);
  assert.equal(C.deathExpLoss(-1001, 100), 20);
  assert.equal(C.rollDeathDrop(0, [], () => 0), 0);
  assert.equal(C.rollDeathDrop(0, [{ id: 7, n: 1 }], () => 0.1), 7);
  assert.equal(C.rollDeathDrop(0, [{ id: 7, n: 1 }], () => 0.5), 0);
});

function fixture() {
  const w = new World();
  const p = w.spawnPlayer('測試');
  p.x = p.tx = 30; p.y = p.ty = 30;
  const def = w.data.monsters.get(1001)!;      // 田鼠
  const m = w.spawnMob(def);
  m.x = m.tx = m.mob!.homeX = 32; m.y = m.ty = m.mob!.homeY = 30;
  return { w, p, m, def };
}

test('即時戰鬥: 攻擊意圖 -> 追擊 -> 殺怪 -> 經驗/金錢/事件 -> 重生', () => {
  const { w, p, m, def } = fixture();
  w.attack(p.id, m.id);
  for (let i = 0; i < 400 && w.ents.has(m.id); i++) w.step();
  assert.ok(!w.ents.has(m.id), '怪應該死');
  assert.ok(p.ch!.exp >= def.exp || p.ch!.level > 1);
  assert.equal(p.atkTarget, 0);
  assert.equal(w.respawns.length, 1);
  assert.ok(w.events.some(e => e.k === 'kill'));
  const n = [...w.ents.values()].filter(e => e.kind === 'mob').length;
  for (let i = 0; i < 105; i++) w.step();
  assert.equal([...w.ents.values()].filter(e => e.kind === 'mob').length, n + 1);
});

test('只可攻擊怪，唔可以打玩家/機械人', () => {
  const { w, p } = fixture();
  const b = w.spawn('bot', true);
  w.attack(p.id, b.id);
  assert.equal(p.atkTarget, 0);
});

test('怪物仇恨: 進入範圍追擊 + 出手；離巢太遠脫戰回歸回血', () => {
  const w = new World();
  const p = w.spawnPlayer('測試');
  p.x = p.tx = 30; p.y = p.ty = 30;
  const m = w.spawnMob(w.data.monsters.get(1003)!);          // 山賊 aggro 5
  m.x = m.tx = m.mob!.homeX = 34; m.y = m.ty = m.mob!.homeY = 30;
  w.step();
  assert.equal(m.mob!.state, 'chase');
  for (let i = 0; i < 60; i++) w.step();
  assert.ok(p.hp! < p.maxHp!, '玩家應受傷');
  // 玩家瞬移走: 怪回歸
  p.x = p.tx = 5; p.y = p.ty = 5; m.hp = 1;
  for (let i = 0; i < 40; i++) w.step();
  assert.equal(m.mob!.state === 'wander' || m.mob!.state === 'return', true);
  assert.ok(m.hp! > 1);
});

test('玩家死亡: 回客棧、滿血、扣經驗', () => {
  const { w, p, m } = fixture();
  p.ch!.exp = 10;
  p.hp = p.ch!.hp = 1;
  m.mob!.state = 'chase'; m.mob!.target = p.id; m.tx = m.x = 31;
  for (let i = 0; i < 60 && !w.events.some(e => e.k === 'die'); i++) w.step();
  assert.ok(w.events.some(e => e.k === 'die'));
  assert.equal(p.hp, p.maxHp);
  assert.deepEqual([p.x, p.y], [10, 10]);
  assert.ok(p.ch!.exp < 10);
  assert.ok(expToNext(1) > 0);
});

test('手感: 1 級義士打田鼠，不會被秒殺；殺一隻花幾多 tick', () => {
  const { w, p, m } = fixture();
  w.attack(p.id, m.id);
  let t = 0;
  while (w.ents.has(m.id) && t < 600) { w.step(); t++; }
  console.log(`  殺田鼠 ${t} tick，剩 HP ${p.hp}/${p.maxHp}`);
  assert.ok(t < 600 && p.hp! > 0);
});
