// 商店/客棧純函數。買價受魅力影響【原】，折扣幅度【自訂】: 每點魅力 0.5%，上限 20%；賣價 = 原價 50%
export const buyPrice = (base: number, cha: number) =>
  Math.max(1, Math.round(base * (1 - Math.min(0.2, cha * 0.005))));
export const sellPrice = (base: number) => Math.floor(base * 0.5);

export type Bag = { id: number; n: number }[];
export function addItem(bag: Bag, id: number, n: number) {
  const s = bag.find(b => b.id === id);
  if (s) s.n += n; else bag.push({ id, n });
}
export function removeItem(bag: Bag, id: number, n: number): boolean {
  const s = bag.find(b => b.id === id);
  if (!s || s.n < n) return false;
  if ((s.n -= n) <= 0) bag.splice(bag.indexOf(s), 1);
  return true;
}
