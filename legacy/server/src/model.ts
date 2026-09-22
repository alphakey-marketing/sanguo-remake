// 資料模型 + 載入。數值表全部喺 data/*.json，規則喺 rules/*.ts
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export type Attr = 'str' | 'agi' | 'int' | 'spi' | 'pol' | 'cha';   // 武力 敏捷 智力 靈力 政治 魅力【原】
export type Attrs = Record<Attr, number>;

export interface ClassDef {
  id: string; name: string; gender: 'M' | 'F'; enabled: boolean;
  attackRange: string; spell: string | null; weapons: string[]; skill: string; tier2: string; tier3: string;
  base: Attrs; growth: Partial<Attrs>;
}

export interface MonsterDef {
  id: number; name: string; level: number; hp: number; atk: number; def: number;
  atkInterval: number; moveSpeed: number; exp: number; gold: [number, number];
  alignment: number; aggroRange: number; leash: number;
  drops: { item: number; p: number }[];
}
export interface SpawnDef { zone: string; monster: number; count: number; respawnTicks: number }

export interface Character {
  name: string; classId: string; level: number; exp: number;
  attrs: Attrs; hp: number; mp: number; sp: number;
  gold: number; karma: number;                       // 善惡值 -30000~30000【原】
  bag: { id: number; n: number }[];
  equip: { weapon?: number; boots?: number };
}

export interface GameData {
  classes: Map<string, ClassDef>;
  monsters: Map<number, MonsterDef>;
  spawns: SpawnDef[];
  starter: Record<string, { weapon: number; boots: number; items: { id: number; n: number }[]; gold: number }>;
  itemIds: Set<number>;
  weapons: Map<number, { power: number; hit: number }>;   // 武器強度(effect 99) / 命中率(effect 13)
  prices: Map<number, number>;                            // items.json price
  inn: { x: number; y: number; restCost: number };
  shops: { id: string; name: string; x: number; y: number; stock: number[] }[];
}

const dataDir = fileURLToPath(new URL('../../../client/data/', import.meta.url));
const readJson = (f: string) => JSON.parse(readFileSync(dataDir + f, 'utf-8'));

let cached: GameData | undefined;
export function loadData(): GameData {
  if (cached) return cached;
  const c = readJson('classes.json'), m = readJson('monsters.json'), items = readJson('items.json'), sh = readJson('shops.json');
  const weapons = new Map<number, { power: number; hit: number }>();
  for (const it of items as { id: number; effects?: { type: number; value: number }[] }[]) {
    const p = it.effects?.find(e => e.type === 99), h = it.effects?.find(e => e.type === 13);
    if (p) weapons.set(it.id, { power: p.value, hit: h?.value ?? 45 });
  }
  return cached = {
    classes: new Map((c.classes as ClassDef[]).map(x => [x.id, x])),
    monsters: new Map((m.monsters as MonsterDef[]).map(x => [x.id, x])),
    spawns: m.spawns,
    starter: c.starter,
    itemIds: new Set((items as { id: number }[]).map(i => i.id)),
    weapons,
    prices: new Map((items as { id: number; price: number }[]).map(i => [i.id, i.price])),
    inn: sh.inn,
    shops: sh.shops,
  };
}
