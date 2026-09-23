// 術法系統純函數 (spec 02 §3/§7)。數值【自訂】；術書等級/職業/大範圍/需寶石表 = data/spells.json
// 由 Godot 版 client/rules/spell.gd 對拍 (tests/vectors/rules.json)
export type Rng = () => number;

// 【原】地剋水、水剋火、火剋風、風剋地
const BEATS: Record<string, string> = { earth: 'water', water: 'fire', fire: 'wind', wind: 'earth' };
export const COUNTER_X = 1.5;

export const elementFactor = (att: string, def: string) =>
  BEATS[att] === def ? COUNTER_X : BEATS[def] === att ? 1 / COUNTER_X : 1.0;

// 術攻 = 術書威力 × (1 + 0.06×對應屬性(智力/靈力))
export const spellAttack = (power: number, attr: number) => power * (1 + 0.06 * attr);

// 術法傷害 = max(1, round(術攻 × rand(0.9~1.1) × (100/(100+術防)) × 相剋 × (1+寶石加成)))
export function calcSpellDamage(
  power: number, attr: number, spellDef: number, attElem: string, defElem: string,
  jewelPct: number, rng: Rng = Math.random): number {
  return Math.max(1, Math.round(spellAttack(power, attr) * (0.9 + rng() * 0.2)
    * (100 / (100 + spellDef)) * elementFactor(attElem, defElem) * (1 + jewelPct)));
}

// 狀態 (spec 02 §7): 持續 tick 封咒 600 / 中邪 300 / buff 900
export const STATUS_TICKS: Record<string, number> = {
  sealed: 600, hex: 300,
  armor1: 900, armor2: 900, armor3: 900,
  mirror1: 900, mirror2: 900, mirror3: 900,
  power1: 900, power2: 900, power3: 900,
};
export const statusTicks = (id: string) => STATUS_TICKS[id] ?? 0;
export const hasStatus = (st: Record<string, number>, id: string, tick: number) => (st[id] ?? 0) > tick;

export const blocksCast = (st: Record<string, number>, tick: number) => hasStatus(st, 'sealed', tick);
export const blocksMove = (st: Record<string, number>, tick: number) => hasStatus(st, 'hex', tick);

// buff 倍率 (無狀態 = 1.0): power = 物攻 +15%/30%/50%
export const atkMult = (st: Record<string, number>, tick: number) =>
  hasStatus(st, 'power3', tick) ? 1.5 : hasStatus(st, 'power2', tick) ? 1.3
    : hasStatus(st, 'power1', tick) ? 1.15 : 1.0;
// armor = 物防 +20%/40%/60%
export const defMult = (st: Record<string, number>, tick: number) =>
  hasStatus(st, 'armor3', tick) ? 1.6 : hasStatus(st, 'armor2', tick) ? 1.4
    : hasStatus(st, 'armor1', tick) ? 1.2 : 1.0;
// mirror = 術防 +20%/40%/60%
export const spellDefMult = (st: Record<string, number>, tick: number) =>
  hasStatus(st, 'mirror3', tick) ? 1.6 : hasStatus(st, 'mirror2', tick) ? 1.4
    : hasStatus(st, 'mirror1', tick) ? 1.2 : 1.0;