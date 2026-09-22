class_name RulesWork
extends RefCounted
# 工作技能【原=種類/工具；自訂=解鎖等級/機率/耐久/SP 消耗，攻略無數字】(Step 7.1)
# skill def 見 data/work.json: {tool, starterTool, materials:[item_id,...], unlockLv:[lv,...]}

const SP_COST_RATIO := 0.1        # 每次工作扣 10% 最大 SP


# 依等級解鎖到第幾個材料 tier（回傳已解鎖數量，至少 1）
static func unlocked_tiers(level: int, unlock_lv: Array) -> int:
	var n := 1
	for i in unlock_lv.size():
		if level >= int(unlock_lv[i]):
			n = i + 1
	return n


# 喺已解鎖 tier 入面揀一個，低 tier 機率大 (weight = 1/(i+1))
static func roll_tier(unlocked: int, rng_fn: Callable) -> int:
	var weights: Array = []
	var total := 0.0
	for i in unlocked:
		var w := 1.0 / float(i + 1)
		weights.append(w)
		total += w
	var r: float = float(rng_fn.call()) * total
	var acc := 0.0
	for i in unlocked:
		acc += weights[i]
		if r < acc:
			return i
	return unlocked - 1


static func sp_cost(max_sp: int) -> int:
	return maxi(1, MathX.js_round(float(max_sp) * SP_COST_RATIO))


static func durability_after_use(dur: int) -> int:
	return maxi(0, dur - 1)
