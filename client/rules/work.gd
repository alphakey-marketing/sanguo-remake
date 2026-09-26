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


# 3 等工具 (S05b, spec 05 §2)【原=種類；耐久/成功率加成自訂】: tier = "special"/"platinum"/"godgiven"，"" = 普通/新手
static func tool_tier_dur(tier: String, tier_cfg: Dictionary) -> int:
	return int(tier_cfg.get(tier, {}).get("dur", 200))


static func tool_tier_bonus(tier: String, tier_cfg: Dictionary) -> float:
	return float(tier_cfg.get(tier, {}).get("bonus", 0.0))


# ================= 技能等級 / 進階生產 / 修理 (Step 12, spec 05 §2/§4) =================
# cfg 全部嚟自 data/work.json: level / basicRate / craftRate / repair

# 升下一級要幾多經驗【自訂】= base + perLv × lv
static func exp_to_next(lv: int, cfg: Dictionary) -> int:
	return int(cfg.get("base", 4)) + int(cfg.get("perLv", 1)) * lv


# 加經驗 → {lv, exp, ups}；到 max 級 exp 歸 0 唔再加
static func gain_exp(lv: int, cur_exp: int, amount: int, cfg: Dictionary) -> Dictionary:
	var max_lv := int(cfg.get("max", 100))
	var ups := 0
	cur_exp += amount
	while lv < max_lv and cur_exp >= exp_to_next(lv, cfg):
		cur_exp -= exp_to_next(lv, cfg)
		lv += 1
		ups += 1
	if lv >= max_lv:
		cur_exp = 0
	return {"lv": lv, "exp": cur_exp, "ups": ups}


# 初階工作成功率【自訂】= base + perLv × lv (cap)
static func basic_success(lv: int, cfg: Dictionary) -> float:
	return minf(float(cfg.get("cap", 0.98)), float(cfg.get("base", 0.85)) + float(cfg.get("perLv", 0.005)) * lv)


# 進階製作成功率【自訂】(spec 05 §4) = base + lv×perLv − 成品等級×perItemLv，clamp min~max
static func craft_chance(skill_lv: int, item_lv: int, cfg: Dictionary) -> float:
	var p := float(cfg.get("base", 0.6)) + skill_lv * float(cfg.get("perLv", 0.006)) - item_lv * float(cfg.get("perItemLv", 0.01))
	return clampf(p, float(cfg.get("min", 0.05)), float(cfg.get("max", 0.98)))


# 進階技能解鎖【原】: from 入面任何一個初階技能 ≥ need 級。levels = {skill: lv}
static func adv_unlocked(levels: Dictionary, from: Array, need: int) -> bool:
	for s in from:
		if int(levels.get(s, 0)) >= need:
			return true
	return false


# 材料夠唔夠: bag_count = {item: n}，need = [[id, n]]
static func has_materials(bag_count: Dictionary, need: Array) -> bool:
	for m in need:
		if int(bag_count.get(int(m[0]), 0)) < int(m[1]):
			return false
	return true


# 修理服務費【自訂】= ceil(價錢 × 損耗比例 × rate)，最少 1；冇損耗 = 0
static func repair_cost(price: float, cur: int, max_d: int, rate: float) -> int:
	if max_d <= 0 or cur >= max_d:
		return 0
	return maxi(1, int(ceil(price * float(max_d - cur) / float(max_d) * rate)))
