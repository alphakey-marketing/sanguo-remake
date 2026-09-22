import { test } from 'node:test';
import assert from 'node:assert/strict';
import { World } from './world.ts';

test('走路: 一 tick 一格', () => {
  const w = new World();
  const e = w.spawn('t', false);
  e.x = 5; e.y = 5; e.tx = 5; e.ty = 5;
  w.setTarget(e.id, 8, 5);
  w.step(); assert.equal(e.x, 6);
  w.step(); w.step(); assert.equal(e.x, 8);
});

test('阻擋格唔可以做目標', () => {
  const w = new World();
  const e = w.spawn('t', false);
  assert.equal(w.isFree(15, 20), false);
  w.setTarget(e.id, 15, 20);
  assert.notDeepEqual([e.tx, e.ty], [15, 20]);
});

test('AOI: 遠處單位睇唔到', () => {
  const w = new World();
  const a = w.spawn('a', false), b = w.spawn('b', false);
  a.x = 5; a.y = 5; b.x = 60; b.y = 60;
  assert.ok(!w.view(a.id).some(v => v.id === b.id));
  b.x = 8; b.y = 8;
  assert.ok(w.view(a.id).some(v => v.id === b.id));
});
