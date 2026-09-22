import { test } from 'node:test';
import assert from 'node:assert/strict';
import { World, INN } from './world.ts';
import { addBots, thinkBots } from './bots.ts';
import * as S from './rules/shop.ts';

test('買賣價: 魅力折扣有上限，賣價 50%', () => {
  assert.equal(S.buyPrice(100, 0), 100);
  assert.equal(S.buyPrice(100, 10), 95);
  assert.equal(S.buyPrice(100, 999), 80);
  assert.equal(S.sellPrice(175), 87);
  assert.equal(S.buyPrice(0, 0), 1);
});

test('客棧: 要喺附近、要有錢；回滿 HP 同扣錢', () => {
  const w = new World();
  const p = w.spawnPlayer('t'), ch = p.ch!;
  p.x = INN.x + 10; ch.hp = p.hp = 1; ch.gold = 100;
  w.rest(p.id); assert.equal(ch.gold, 100);
  p.x = INN.x; p.y = INN.y;
  w.rest(p.id); assert.equal(ch.gold, 100 - w.data.inn.restCost); assert.ok(ch.hp > 1);
  ch.gold = 0; ch.hp = 1; w.rest(p.id); assert.equal(ch.hp, 1);
});

test('商店: 買 → 扣錢入背包；唔賣嘅唔買到；賣 → 加錢；冇錢/冇貨失敗', () => {
  const w = new World(), shop = w.data.shops[0];
  const p = w.spawnPlayer('t'), ch = p.ch!;
  p.x = shop.x; p.y = shop.y; ch.gold = 1000; ch.bag = [];
  const cost = S.buyPrice(w.data.prices.get(10001)!, ch.attrs.cha);
  w.buy(p.id, 10001, 2);
  assert.equal(ch.gold, 1000 - cost * 2); assert.equal(ch.bag.find(b => b.id === 10001)?.n, 2);
  w.buy(p.id, 61501, 1); assert.ok(!ch.bag.some(b => b.id === 61501));
  ch.gold = 0; w.buy(p.id, 10001, 1); assert.equal(ch.bag.find(b => b.id === 10001)?.n, 2);
  w.sell(p.id, 10001, 1); assert.equal(ch.gold, S.sellPrice(w.data.prices.get(10001)!));
  w.sell(p.id, 99999, 1); assert.equal(ch.bag.length, 1);
  p.x = 50; w.buy(p.id, 10001, 1); assert.equal(ch.bag[0].n, 1);
});

test('聊天: 記錄並截 60 字，空字串忽略', () => {
  const w = new World(), p = w.spawn('t', false);
  w.chat(p.id, '  '); assert.equal(w.chats.length, 0);
  w.chat(p.id, 'x'.repeat(100)); assert.equal(w.chats[0].text.length, 60);
});

test('機械人: 跑一陣會打怪殺怪攞經驗', () => {
  const w = new World(); w.initMobs();
  const ids = addBots(w, 10);
  for (let i = 0; i < 6000; i++) { thinkBots(w, ids); w.step(); w.events.length = 0; }
  const chs = ids.map(i => w.ents.get(i)!.ch!);
  assert.ok(chs.some(c => c.level > 1 || c.exp > 0), 'bot 應有經驗');
});
