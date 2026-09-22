// 世界: 格子地圖 + 單位 + AOI + 即時戰鬥 + 怪物 AI。server 權威: client 只發意圖。
import type { EntView, Ev } from './protocol.ts';
import { loadData, type Character, type MonsterDef, type GameData } from './model.ts';
import { createCharacter, gainExp, expToNext, maxHp, maxMp, maxSp } from './rules/stats.ts';
import * as C from './rules/combat.ts';
import * as S from './rules/shop.ts';

export const W = 64, H = 64, AOI = 12;   // AOI = 視野半徑(格)
export const INN = { x: 10, y: 10 };                       // 復活點(客棧)
const NEAR = 3;                                            // 設施互動距離(格)
export const ZONE = { x0: 26, y0: 26, x1: 60, y1: 60 };    // field_1 野區

export interface MobState {
  def: MonsterDef; homeX: number; homeY: number; state: 'wander' | 'chase' | 'return';
  target: number; nextAtk: number;
}
export interface Ent extends EntView {
  tx: number; ty: number;
  kind: 'player' | 'bot' | 'mob';
  ch?: Character; mob?: MobState;
  atkTarget: number; nextAtk: number;       // 玩家攻擊意圖
}

export class World {
  ents = new Map<number, Ent>();
  tick = 0;
  private nextId = 1;
  blocked = new Set<number>();          // y*W+x 阻擋格
  events: Ev[] = [];                    // 本 tick 事件，index 廣播後清
  chats: { id: number; name: string; text: string; x: number; y: number }[] = [];   // 本 tick 聊天
  respawns: { at: number; def: MonsterDef }[] = [];
  data: GameData;

  constructor(data: GameData = loadData()) {
    this.data = data;
    // 簡單障礙: 兩道牆
    for (let i = 10; i < 30; i++) this.blocked.add(20 * W + i);
    for (let i = 30; i < 50; i++) this.blocked.add(i * W + 40);
  }

  isFree(x: number, y: number) {
    return x >= 0 && y >= 0 && x < W && y < H && !this.blocked.has(y * W + x);
  }

  spawn(name: string, bot: boolean): Ent {
    const id = this.nextId++;
    let x = 0, y = 0;
    do { x = 5 + Math.floor(Math.random() * 20); y = 5 + Math.floor(Math.random() * 12); } while (!this.isFree(x, y));
    const e: Ent = { id, name, x, y, tx: x, ty: y, face: id % 12, bot, kind: bot ? 'bot' : 'player', atkTarget: 0, nextAtk: 0 };
    this.ents.set(id, e);
    return e;
  }

  // 玩家: 有角色 (義士)
  spawnPlayer(name: string): Ent {
    const e = this.spawn(name, false);
    e.ch = createCharacter(this.data, name, 'yishi');
    this.syncStats(e);
    return e;
  }

  // 機械人: 有角色，會打怪
  spawnBot(name: string): Ent {
    const e = this.spawn(name, true);
    e.ch = createCharacter(this.data, name.slice(0, 8), 'yishi');
    this.syncStats(e);
    return e;
  }

  syncStats(e: Ent) {
    if (e.ch) { e.hp = e.ch.hp; e.maxHp = maxHp(e.ch.level, e.ch.attrs); e.level = e.ch.level; }
  }

  remove(id: number) { this.ents.delete(id); }

  setTarget(id: number, x: number, y: number) {
    const e = this.ents.get(id);
    if (e && this.isFree(x, y)) { e.tx = x; e.ty = y; e.atkTarget = 0; }   // 手動行路取消攻擊
  }

  // ---- 怪物刷新 ----
  initMobs() {
    for (const sp of this.data.spawns)
      for (let i = 0; i < sp.count; i++) this.spawnMob(this.data.monsters.get(sp.monster)!);
  }

  spawnMob(def: MonsterDef): Ent {
    const id = this.nextId++;
    let x = 0, y = 0;
    do {
      x = ZONE.x0 + Math.floor(Math.random() * (ZONE.x1 - ZONE.x0 + 1));
      y = ZONE.y0 + Math.floor(Math.random() * (ZONE.y1 - ZONE.y0 + 1));
    } while (!this.isFree(x, y));
    const e: Ent = {
      id, name: def.name, x, y, tx: x, ty: y, face: 0, bot: false, kind: 'mob',
      hp: def.hp, maxHp: def.hp, level: def.level, atkTarget: 0, nextAtk: 0,
      mob: { def, homeX: x, homeY: y, state: 'wander', target: 0, nextAtk: 0 },
    };
    this.ents.set(id, e);
    return e;
  }

  // ---- 玩家意圖: 只可攻擊怪 ----
  attack(id: number, target: number) {
    const e = this.ents.get(id), t = this.ents.get(target);
    if (e?.ch && e.hp! > 0 && t?.kind === 'mob') e.atkTarget = target;
  }

  // ---- 聊天 (公用，AOI 內廣播) ----
  chat(id: number, text: string) {
    const e = this.ents.get(id);
    text = text.trim().slice(0, 60);
    if (e && text) this.chats.push({ id, name: e.name, text, x: e.x, y: e.y });
  }

  // ---- 城內設施: 客棧休息 / 商店買賣 (server 驗證距離+金錢+背包) ----
  private msg(id: number, text: string) { this.events.push({ k: 'msg', dst: id, text }); }
  private near(e: Ent, x: number, y: number) { return C.inRange(e.x, e.y, x, y, NEAR); }

  rest(id: number) {
    const e = this.ents.get(id), ch = e?.ch, inn = this.data.inn;
    if (!e || !ch || e.hp! <= 0) return;
    if (!this.near(e, inn.x, inn.y)) return this.msg(id, '要喺客棧附近先可以休息');
    if (ch.gold < inn.restCost) return this.msg(id, `住宿要 ${inn.restCost} 金`);
    ch.gold -= inn.restCost;
    ch.hp = maxHp(ch.level, ch.attrs); ch.mp = maxMp(ch.level, ch.attrs); ch.sp = maxSp(ch.level, ch.attrs);
    this.syncStats(e);
    this.msg(id, `休息完畢，花 ${inn.restCost} 金`);
  }

  private shopFor(e: Ent) { return this.data.shops.find(s => this.near(e, s.x, s.y)); }

  buy(id: number, item: number, n = 1) {
    const e = this.ents.get(id), ch = e?.ch;
    n = Math.min(99, n | 0);
    if (!e || !ch || n < 1) return;
    const shop = this.shopFor(e);
    if (!shop) return this.msg(id, '附近冇商店');
    if (!shop.stock.includes(item)) return this.msg(id, '呢間店唔賣呢件');
    const cost = S.buyPrice(this.data.prices.get(item) ?? 0, ch.attrs.cha) * n;
    if (ch.gold < cost) return this.msg(id, `金錢不足，要 ${cost}`);
    ch.gold -= cost; S.addItem(ch.bag, item, n);
    this.msg(id, `買咗 ${n} 件，花 ${cost} 金`);
  }

  sell(id: number, item: number, n = 1) {
    const e = this.ents.get(id), ch = e?.ch;
    n = Math.min(99, n | 0);
    if (!e || !ch || n < 1) return;
    if (!this.shopFor(e)) return this.msg(id, '附近冇商店');
    if (ch.equip.weapon === item && (ch.bag.find(b => b.id === item)?.n ?? 0) <= n) return this.msg(id, '裝備中，唔可以賣');
    if (!S.removeItem(ch.bag, item, n)) return this.msg(id, '背包冇咁多');
    const gain = S.sellPrice(this.data.prices.get(item) ?? 0) * n;
    ch.gold += gain;
    this.msg(id, `賣出 ${n} 件，得 ${gain} 金`);
  }

  // 怪物 AI: 遊蕩 / 仇恨追擊 / 脫戰回歸
  private thinkMob(m: Ent) {
    const s = m.mob!, d = s.def;
    const dist = (a: Ent) => Math.max(Math.abs(a.x - m.x), Math.abs(a.y - m.y));
    const tgt = this.ents.get(s.target);
    if (s.state === 'chase') {
      const lost = !tgt || !tgt.ch || tgt.hp! <= 0 ||
        Math.max(Math.abs(m.x - s.homeX), Math.abs(m.y - s.homeY)) > d.leash;
      if (lost) { s.state = 'return'; s.target = 0; m.tx = s.homeX; m.ty = s.homeY; return; }
      if (C.inRange(m.x, m.y, tgt.x, tgt.y)) {
        m.tx = m.x; m.ty = m.y;
        if (this.tick >= s.nextAtk) {
          s.nextAtk = this.tick + d.atkInterval;
          const dmg = C.calcMobDamage(d.atk, C.playerDef(tgt.ch!.level));
          this.events.push({ k: 'hit', src: m.id, dst: tgt.id, dmg });
          this.damage(tgt, dmg, m);
        }
      } else { m.tx = tgt.x; m.ty = tgt.y; }
      return;
    }
    if (s.state === 'return') {
      m.hp = Math.min(m.maxHp!, m.hp! + Math.ceil(m.maxHp! / 20));     // 脫戰回血
      if (m.x === s.homeX && m.y === s.homeY) s.state = 'wander';
      return;
    }
    // wander: 找仇恨目標，否則隨機遊蕩
    if (d.aggroRange > 0) {
      let best: Ent | undefined;
      for (const p of this.ents.values())
        if (p.ch && p.hp! > 0 && dist(p) <= d.aggroRange && (!best || dist(p) < dist(best))) best = p;
      if (best) { s.state = 'chase'; s.target = best.id; return; }
    }
    if (m.x === m.tx && m.y === m.ty && Math.random() < 0.05) {
      const nx = s.homeX + Math.floor(Math.random() * 7) - 3, ny = s.homeY + Math.floor(Math.random() * 7) - 3;
      if (this.isFree(nx, ny)) { m.tx = nx; m.ty = ny; }
    }
  }

  // 受傷; 死亡處理
  damage(t: Ent, dmg: number, by: Ent) {
    t.hp = Math.max(0, t.hp! - dmg);
    if (t.kind === 'mob' && by.ch) { t.mob!.state = 'chase'; t.mob!.target = by.id; }
    if (t.ch) t.ch.hp = t.hp;
    if (t.hp > 0) return;
    if (t.kind === 'mob') this.killMob(t, by);
    else if (t.ch) this.killPlayer(t);
  }

  private killMob(m: Ent, by: Ent) {
    const d = m.mob!.def;
    this.ents.delete(m.id);
    this.respawns.push({ at: this.tick + (this.data.spawns.find(s => s.monster === d.id)?.respawnTicks ?? 200), def: d });
    for (const e of this.ents.values()) if (e.atkTarget === m.id) e.atkTarget = 0;
    const ch = by.ch;
    if (!ch) return;
    const gold = C.rollGold(d.gold), items = C.rollDrops(d.drops);
    ch.gold += gold;
    for (const it of items) {
      const slot = ch.bag.find(b => b.id === it);
      if (slot) slot.n++; else ch.bag.push({ id: it, n: 1 });
    }
    ch.karma = C.karmaAfterKill(ch.karma, d.alignment);
    const ups = gainExp(this.data, ch, d.exp);
    this.syncStats(by);
    this.events.push({ k: 'kill', src: by.id, dst: m.id, exp: d.exp, gold, items, lvUp: ups ? ch.level : 0 });
  }

  private killPlayer(p: Ent) {
    const ch = p.ch!;
    ch.exp = Math.max(0, ch.exp - C.deathExpLoss(ch.karma, expToNext(ch.level)));
    const lost = C.rollDeathDrop(ch.karma, ch.bag);
    if (lost) { const b = ch.bag.find(i => i.id === lost)!; if (--b.n <= 0) ch.bag.splice(ch.bag.indexOf(b), 1); }
    ch.hp = maxHp(ch.level, ch.attrs); ch.mp = maxMp(ch.level, ch.attrs); ch.sp = maxSp(ch.level, ch.attrs);
    p.x = p.tx = INN.x; p.y = p.ty = INN.y; p.atkTarget = 0;
    this.syncStats(p);
    this.events.push({ k: 'die', dst: p.id, lost });
  }

  // 玩家自動追擊 + 出手
  private thinkPlayer(p: Ent) {
    if (!p.atkTarget || !p.ch) return;
    const t = this.ents.get(p.atkTarget);
    if (!t || t.hp! <= 0 || p.hp! <= 0) { p.atkTarget = 0; return; }
    if (!C.inRange(p.x, p.y, t.x, t.y)) { p.tx = t.x; p.ty = t.y; return; }
    p.tx = p.x; p.ty = p.y;
    if (this.tick < p.nextAtk) return;
    const ch = p.ch, w = this.data.weapons.get(ch.equip.weapon ?? 0) ?? { power: 0, hit: 45 };
    p.nextAtk = this.tick + C.attackInterval(ch.attrs.agi);
    if (Math.random() >= C.hitChance(w.hit, ch.level, t.level!)) {
      this.events.push({ k: 'hit', src: p.id, dst: t.id, dmg: 0 });     // miss
      t.mob!.state = 'chase'; t.mob!.target = p.id;
      return;
    }
    const dmg = C.calcDamage(ch.attrs.str, w.power, t.mob!.def.def);
    this.events.push({ k: 'hit', src: p.id, dst: t.id, dmg });
    this.damage(t, dmg, p);
  }

  // 每 tick: 戰鬥/AI -> 重生 -> 移動 (一格)
  step() {
    this.tick++;
    for (const e of [...this.ents.values()]) {
      if (!this.ents.has(e.id)) continue;
      if (e.kind === 'mob') this.thinkMob(e); else if (e.ch) this.thinkPlayer(e);
    }
    for (let i = this.respawns.length - 1; i >= 0; i--)
      if (this.tick >= this.respawns[i].at) { this.spawnMob(this.respawns[i].def); this.respawns.splice(i, 1); }
    for (const e of this.ents.values()) {
      const dx = Math.sign(e.tx - e.x), dy = Math.sign(e.ty - e.y);
      if (dx && this.isFree(e.x + dx, e.y)) e.x += dx;
      else if (dy && this.isFree(e.x, e.y + dy)) e.y += dy;
    }
  }

  // AOI: 只回視野內單位
  view(id: number): EntView[] {
    const me = this.ents.get(id);
    if (!me) return [];
    const out: EntView[] = [];
    for (const e of this.ents.values()) {
      if (Math.abs(e.x - me.x) <= AOI && Math.abs(e.y - me.y) <= AOI)
        out.push({ id: e.id, name: e.name, x: e.x, y: e.y, face: e.face, bot: e.bot, hp: e.hp, maxHp: e.maxHp, level: e.level, mob: e.kind === 'mob' });
    }
    return out;
  }
}
