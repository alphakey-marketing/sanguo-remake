// 即時戰鬥純函數。全部【自訂】數值 (攻略只講: 攻速由敏捷、威力由武力+武器強度)
export type Rng = () => number;

export const STR_COEF = 1.5;        // 武力係數
export const MELEE_RANGE = 1;       // 近戰射程(格, 切比雪夫距離)

// 攻擊間隔 (tick, 10Hz): 敏捷越高越快，最快 6 tick
export const attackInterval = (agi: number) => Math.max(6, Math.round(20 - agi * 0.5));

// 玩家防禦: 自訂，隨等級
export const playerDef = (lv: number) => Math.floor(lv / 2);

// 傷害 = max(1, (武力係數*武力 + 武器強度) * 隨機(0.9~1.1) - 防禦)
export function calcDamage(str: number, weaponPower: number, def: number, rng: Rng = Math.random): number {
  return Math.max(1, Math.round((STR_COEF * str + weaponPower) * (0.9 + rng() * 0.2) - def));
}

// 怪物傷害 = max(1, atk * 隨機(0.9~1.1) - 防禦)
export function calcMobDamage(atk: number, def: number, rng: Rng = Math.random): number {
  return Math.max(1, Math.round(atk * (0.9 + rng() * 0.2) - def));
}

// 命中率: 武器命中率(45 = 基準) + 等級差
export function hitChance(weaponHit: number, atkLv: number, defLv: number): number {
  return Math.min(0.98, Math.max(0.3, 0.8 + (weaponHit - 45) / 200 + (atkLv - defLv) * 0.02));
}

export const inRange = (ax: number, ay: number, bx: number, by: number, range = MELEE_RANGE) =>
  Math.max(Math.abs(ax - bx), Math.abs(ay - by)) <= range;

// 掉落: 每項獨立擲骰
export function rollDrops(drops: { item: number; p: number }[], rng: Rng = Math.random): number[] {
  return drops.filter(d => rng() < d.p).map(d => d.item);
}

export function rollGold(range: [number, number], rng: Rng = Math.random): number {
  return range[0] + Math.floor(rng() * (range[1] - range[0] + 1));
}

// 殺怪善惡值: 殺惡(alignment<0)加善惡值【原】; 數值自訂，夾喺 ±30000
export const karmaAfterKill = (karma: number, alignment: number) =>
  Math.max(-30000, Math.min(30000, karma - Math.round(alignment / 10)));

// 死亡處分【原】: 善惡 ≥ -1000 掉 10% 該級經驗，否則 20%
export function deathExpLoss(karma: number, expToNextLv: number): number {
  return Math.round(expToNextLv * (karma >= -1000 ? 0.1 : 0.2));
}

// 死亡掉背包物品【原】1 件機率掉落；機率自訂 (善惡 ≥ -1000: 20%，否則 50%)。回傳掉咗嘅 item id，冇掉 = 0
export function rollDeathDrop(karma: number, bag: { id: number; n: number }[], rng: Rng = Math.random): number {
  if (!bag.length || rng() >= (karma >= -1000 ? 0.2 : 0.5)) return 0;
  return bag[Math.floor(rng() * bag.length)].id;
}
