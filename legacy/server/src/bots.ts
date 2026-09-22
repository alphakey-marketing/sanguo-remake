// 機械人: 有角色，會去野區打怪、血低返客棧休息、間中講嘢。供新手練兵場頂替組隊。
import { World, INN, ZONE } from './world.ts';
import { maxHp } from './rules/stats.ts';

const NAMES = ['黃權', '張繡', '趙雲', '關平', '周倉', '徐庶', '龐統', '法正', '馬岱', '王平', '姜維', '魏延'];
const LINES = ['有冇人組隊?', '呢度啲怪好肥', '小心野豬', '我去練功', '升級喇!', '客棧休息好抵', '有刀賣未?', '三國萬歲'];
const rnd = (n: number) => Math.floor(Math.random() * n);

export function addBots(w: World, n: number) {
  const ids: number[] = [];
  for (let i = 0; i < n; i++) ids.push(w.spawnBot(NAMES[i % NAMES.length] + (i >= NAMES.length ? i : '')).id);
  return ids;
}

export function thinkBots(w: World, ids: number[]) {
  for (const id of ids) {
    const e = w.ents.get(id);
    if (!e?.ch) continue;
    if (Math.random() < 0.002) w.chat(id, LINES[rnd(LINES.length)]);
    const low = e.hp! < maxHp(e.ch.level, e.ch.attrs) * 0.4;
    const nearInn = Math.max(Math.abs(e.x - INN.x), Math.abs(e.y - INN.y)) <= 3;
    if (low) {                                    // 血低: 撤退返客棧休息
      e.atkTarget = 0;
      if (nearInn) { if (e.ch.gold < w.data.inn.restCost) e.ch.gold += w.data.inn.restCost; w.rest(id); }   // 窮機械人有免費住宿
      else w.setTarget(id, INN.x, INN.y);
      continue;
    }
    if (e.atkTarget) continue;                    // 戰鬥中
    // 揀附近最近嘅怪 (等級唔好高過自己太多)
    let best: { id: number; d: number } | undefined;
    for (const m of w.ents.values()) {
      if (m.kind !== 'mob' || m.level! > e.ch.level + 2) continue;
      const d = Math.max(Math.abs(m.x - e.x), Math.abs(m.y - e.y));
      if (d <= 14 && (!best || d < best.d)) best = { id: m.id, d };
    }
    if (best) { w.attack(id, best.id); continue; }
    if (e.x === e.tx && e.y === e.ty && Math.random() < 0.15)   // 冇怪: 行入練功區
      w.setTarget(id, ZONE.x0 + rnd(ZONE.x1 - ZONE.x0), ZONE.y0 + rnd(ZONE.y1 - ZONE.y0));
  }
}
