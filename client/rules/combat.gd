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
# atk_mult/def_mult = 狀態 buff 倍率 (聚力/護甲系, spec 02 §7)，冇狀態 = 1.0
static func calc_damage(strength: float, weapon_power: float, def: float, rng: Callable = Callable(),
		atk_mult: float = 1.0, def_mult: float = 1.0) -> int:
	return maxi(1, MathX.js_round((STR_COEF * strength + weapon_power) * atk_mult * (0.9 + MathX.roll(rng) * 0.2) - def * def_mult))


# 怪物傷害 = max(1, atk * 隨機(0.9~1.1) - 防禦)
static func calc_mob_damage(atk: float, def: float, rng: Callable = Callable(), atk_mult: float = 1.0, def_mult: float = 1.0) -> int:
	return maxi(1, MathX.js_round(atk * atk_mult * (0.9 + MathX.roll(rng) * 0.2) - def * def_mult))


# 戰騎降敵屬性 (S07c, spec 07 §8.3 debuff)：debuff = {stat: {val, until}}
# 未過期就先乘 (1 + val)；val 係負數（降）。stat 唔喺入面 = 原值。
static func debuffed(value: float, debuff: Dictionary, stat: String, tick: int) -> float:
	var d = debuff.get(stat)
	if d is Dictionary and tick < int(d.get("until", 0)):
		return value * (1.0 + float(d.get("val", 0.0)))
	return value


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
# (舊簡單規則，向量對拍用；spec 03 §4.1 表格版改用 roll_death_drop_items)
static func roll_death_drop(karma: int, bag: Array, rng: Callable = Callable()) -> int:
	if bag.is_empty():
		return 0
	if MathX.roll(rng) >= (0.2 if karma >= -1000 else 0.5):
		return 0
	return int(bag[int(floor(MathX.roll(rng) * bag.size()))]["id"])


# ============ S03c 死亡道具 (spec 03 §4)【自訂】============
# 死亡道具 id (items.json cat 250 消耗/特殊): 幸運符 / 護身符 / 還魂丹 / 復活丹
const LUCKY_CHARM := 65016      # 死亡唔掉物品 (消耗 1)
const PROTECTION_CHARM := 65029 # 經驗損失減半 (消耗 1)
const REVIVE_PILL := 65030      # 死亡即喺客棧復活，物品/經驗照掉；天譴無效
const ONSITE_REVIVE_PILL := 65338 # 復活丹: 倒地期間就地復活（唔使返鎮，回滿血），消耗 1

# 死亡掉物品表【原】spec 03 §4.1: 按善惡階返 {max 最高掉落件數, p 每件獨立機率}
# 機率【自訂】善劣兩邊 0.8/0.6/0.4/0.3/0.25/0.2 檔 (惡越高跌得越多件 × 每件機率越高)
static func death_drop_table(karma: int) -> Dictionary:
	if karma <= -16001: return {"max": 7, "p": 0.8}
	if karma <= -8001:  return {"max": 6, "p": 0.8}
	if karma <= -1001:  return {"max": 3, "p": 0.6}
	if karma <= 1000:   return {"max": 1, "p": 0.4}
	if karma <= 8000:   return {"max": 1, "p": 0.3}
	if karma <= 16000:  return {"max": 1, "p": 0.25}
	return {"max": 1, "p": 0.2}

# 死亡掉物品表格版: 逐「件」獨立擲骰，上限 = 善惡階最高件數。bag = 未裝上身嘅件。
# 回傳 [{id, n}] (每項 n=1)；幸運符出手前由 sim 擋。
static func roll_death_drop_items(karma: int, bag: Array, rng: Callable = Callable()) -> Array:
	var tb := death_drop_table(karma)
	var out: Array = []
	var mx := int(tb["max"])
	for b in bag:
		var id := int(b["id"])
		var n := int(b["n"])
		for _i in n:
			if out.size() >= mx:
				return out
			if MathX.roll(rng) < float(tb["p"]):
				out.append({"id": id, "n": 1})
	return out

# 護身符: 經驗損失減半 (spec 03 §4.2)【自訂】
static func death_exp_loss_protected(karma: int, exp_to_next_lv: float, has_protection: bool) -> int:
	var base := death_exp_loss(karma, exp_to_next_lv)
	return MathX.js_round(base / 2.0) if has_protection else base
