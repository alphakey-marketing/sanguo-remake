// 屬性/成長/經驗。全部【自訂】數值（攻略只講「升級時武/智/敏/靈提升」、「5 級脫新手」）
import type { Attrs, Character, ClassDef, GameData } from '../model.ts';

export const NEWBIE_LEVEL = 5;   // 【原】5 級脫離新手
export const MAX_LEVEL = 100;    // 【原】三轉 100 級

export const maxHp = (lv: number, a: Attrs) => 60 + lv * 15 + a.str * 4;
export const maxMp = (lv: number, a: Attrs) => 20 + lv * 5 + a.spi * 3 + a.int * 2;
export const maxSp = (lv: number, a: Attrs) => 50 + lv * 3 + a.agi * 2;

// 升到下一級所需經驗
export const expToNext = (lv: number) => Math.round(20 * Math.pow(lv, 1.8));

export function attrsAt(cls: ClassDef, lv: number): Attrs {
  const a = { ...cls.base };
  for (const k of Object.keys(cls.growth) as (keyof Attrs)[]) a[k] += (cls.growth[k] ?? 0) * (lv - 1);
  return a;
}

export function createCharacter(data: GameData, name: string, classId: string): Character {
  const cls = data.classes.get(classId);
  if (!cls || !cls.enabled) throw new Error(`職業未開放: ${classId}`);
  if ([...name].length < 1 || [...name].length > 8) throw new Error('名字要 1~8 字');   // 【原】≤8 字
  const st = data.starter[classId];
  const attrs = attrsAt(cls, 1);
  return {
    name, classId, level: 1, exp: 0, attrs,
    hp: maxHp(1, attrs), mp: maxMp(1, attrs), sp: maxSp(1, attrs),
    gold: st?.gold ?? 0, karma: 0,
    bag: (st?.items ?? []).map(i => ({ ...i })),
    equip: st ? { weapon: st.weapon, boots: st.boots } : {},
  };
}

// 加經驗，可連升多級；升級回滿 HP/MP/SP。回傳升咗幾級
export function gainExp(data: GameData, ch: Character, amount: number): number {
  const cls = data.classes.get(ch.classId)!;
  let ups = 0;
  ch.exp += amount;
  while (ch.level < MAX_LEVEL && ch.exp >= expToNext(ch.level)) {
    ch.exp -= expToNext(ch.level);
    ch.level++; ups++;
  }
  if (ch.level >= MAX_LEVEL) ch.exp = 0;
  if (ups) {
    ch.attrs = attrsAt(cls, ch.level);
    ch.hp = maxHp(ch.level, ch.attrs); ch.mp = maxMp(ch.level, ch.attrs); ch.sp = maxSp(ch.level, ch.attrs);
  }
  return ups;
}
