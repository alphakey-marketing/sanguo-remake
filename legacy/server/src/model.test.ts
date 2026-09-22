import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadData } from './model.ts';
import { createCharacter, gainExp, expToNext, maxHp, attrsAt, NEWBIE_LEVEL } from './rules/stats.ts';

const data = loadData();

test('資料完整: 六職、5 種怪、只啟用義士', () => {
  assert.equal(data.classes.size, 6);
  assert.deepEqual([...data.classes.values()].filter(c => c.enabled).map(c => c.id), ['yishi']);
  assert.equal(data.monsters.size, 5);
});

test('所有掉落/起手裝備 item id 都存在於 items.json', () => {
  for (const m of data.monsters.values())
    for (const d of m.drops) assert.ok(data.itemIds.has(d.item), `${m.name} 掉落 ${d.item} 不存在`);
  for (const st of Object.values(data.starter)) {
    assert.ok(data.itemIds.has(st.weapon)); assert.ok(data.itemIds.has(st.boots));
    for (const i of st.items) assert.ok(data.itemIds.has(i.id));
  }
});

test('spawn 引用嘅怪存在；掉落機率喺 0~1', () => {
  for (const s of data.spawns) assert.ok(data.monsters.has(s.monster));
  for (const m of data.monsters.values()) for (const d of m.drops) assert.ok(d.p > 0 && d.p <= 1);
});

test('建角: 義士 1 級，屬性=職業基礎，HP/MP/SP 滿，名字限 8 字', () => {
  const c = createCharacter(data, '關羽', 'yishi');
  assert.equal(c.level, 1);
  assert.deepEqual(c.attrs, data.classes.get('yishi')!.base);
  assert.equal(c.hp, maxHp(1, c.attrs));
  assert.equal(c.equip.weapon, 10001);
  assert.throws(() => createCharacter(data, '一二三四五六七八九', 'yishi'));
  assert.throws(() => createCharacter(data, '仕女', 'shinu'), /未開放/);
});

test('經驗: 曲線遞增；夠經驗升級，屬性成長，HP 回滿；可連升', () => {
  for (let l = 1; l < 99; l++) assert.ok(expToNext(l + 1) > expToNext(l));
  const c = createCharacter(data, '張飛', 'yishi');
  c.hp = 1;
  assert.equal(gainExp(data, c, expToNext(1) - 1), 0);
  assert.equal(c.level, 1);
  assert.equal(gainExp(data, c, 1), 1);
  assert.equal(c.level, 2);
  assert.equal(c.attrs.str, data.classes.get('yishi')!.base.str + 2);
  assert.equal(c.hp, maxHp(2, c.attrs));
  const d = createCharacter(data, '趙雲', 'yishi');
  assert.ok(gainExp(data, d, 100000) > 5);
  assert.deepEqual(d.attrs, attrsAt(data.classes.get('yishi')!, d.level));
});

test('新手區: 用 5 種怪嘅經驗，1 級打到 5 級 (脫新手) 要打幾多隻? (自訂手感檢查)', () => {
  let need = 0;
  for (let l = 1; l < NEWBIE_LEVEL; l++) need += expToNext(l);
  const dog = data.monsters.get(1002)!;
  const kills = Math.ceil(need / dog.exp);
  console.log(`  脫新手需 ${need} 經驗 ≈ ${kills} 隻野狗`);
  assert.ok(kills >= 20 && kills <= 300, `手感: ${kills}`);
});
