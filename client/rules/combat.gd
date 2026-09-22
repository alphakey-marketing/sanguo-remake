class_name RulesCombat
extends RefCounted
# 即時戰鬥純函數。全部【自訂】數值 (攻略只講: 攻速由敏捷、威力由武力+武器強度)
# 由 server/src/rules/combat.ts 移植；tests/vectors/rules.json 對拍

const STR_COEF := 1.5        # 武力係數
const MELEE_RANGE := 1       # 近戰射程(格, 切比雪夫距離)


# 攻擊間隔 (tick, 10Hz): 敏捷越高越快，最快 6 tick
static func attack_interval(agi: float) -> int:
	return maxi(6, MathX.js_round(20.0 - agi * 0.5))


# 玩家防禦: 自訂，隨等級
static func player_def(lv: int) -> int:
	return int(floor(lv / 2.0))


# 傷害 = max(1, (武力係數*武力 + 武器強度) * 隨機(0.9~1.1) - 防禦)
static func calc_damage(strength: float, weapon_power: float, def: float, rng: Callable = Callable()) -> int:
	return maxi(1, MathX.js_round((STR_COEF * strength + weapon_power) * (0.9 + MathX.roll(rng) * 0.2) - def))


# 怪物傷害 = max(1, atk * 隨機(0.9~1.1) - 防禦)
static func calc_mob_damage(atk: float, def: float, rng: Callable = Callable()) -> int:
	return maxi(1, MathX.js_round(atk * (0.9 + MathX.roll(rng) * 0.2) - def))


# 命中率: 武器命中率(45 = 基準) + 等級差
static func hit_chance(weapon_hit: float, atk_lv: float, def_lv: float) -> float:
	return minf(0.98, maxf(0.3, 0.8 + (weapon_hit - 45.0) / 200.0 + (atk_lv - def_lv) * 0.02))


static func in_range(ax: float, ay: float, bx: float, by: float, rng_cells: float = MELEE_RANGE) -> bool:
	return maxf(absf(ax - bx), absf(ay - by)) <= rng_cells


# 掉落: 每項獨立擲骰。drops = [{item, p}]
static func roll_drops(drops: Array, rng: Callable = Callable()) -> Array:
	var out: Array = []
	for d in drops:
		if MathX.roll(rng) < float(d["p"]):
			out.append(int(d["item"]))
	return out


static func roll_gold(gold_range: Array, rng: Callable = Callable()) -> int:
	var lo := int(gold_range[0])
	var hi := int(gold_range[1])
	return lo + int(floor(MathX.roll(rng) * (hi - lo + 1)))


# 殺怪善惡值: 殺惡(alignment<0)加善惡值【原】; 數值自訂，夾喺 ±30000
static func karma_after_kill(karma: int, alignment: float) -> int:
	return int(clampf(karma - MathX.js_round(alignment / 10.0), -30000, 30000))


# 死亡處分【原】: 善惡 ≥ -1000 掉 10% 該級經驗，否則 20%
static func death_exp_loss(karma: int, exp_to_next_lv: float) -> int:
	return MathX.js_round(exp_to_next_lv * (0.1 if karma >= -1000 else 0.2))


# 死亡掉背包物品【原】1 件機率掉落；機率自訂 (善惡 ≥ -1000: 20%，否則 50%)。回傳 item id，冇掉 = 0
static func roll_death_drop(karma: int, bag: Array, rng: Callable = Callable()) -> int:
	if bag.is_empty():
		return 0
	if MathX.roll(rng) >= (0.2 if karma >= -1000 else 0.5):
		return 0
	return int(bag[int(floor(MathX.roll(rng) * bag.size()))]["id"])
