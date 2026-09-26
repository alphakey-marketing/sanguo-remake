class_name RulesCivic
extends RefCounted
# S08g 民心 + 城池法令 (spec 08 §9/§10；攻略 sy2_8_14 / sy2_8_5 尾) 純函數。
# 【原】民心：玩家攻佔城池先啟動、初始 100；每月初一評比，稅率高 → 民心 −4。
#        民心低 → 人口流失 / 市場 prod 跌 / 兵源減。
# 【自訂】單機化：救災/捐贈官令 +民心（每 10 名聲 +0.1，上限 +10/月）。
# cfg = data.world["cityMorale"]；law_cfg = data.world["cityLaw"]。
# 真值存喺 sim state["cityGov"]（城池被佔先有），呢度只做換算。


# ---- 民心 ----

static func cap(cfg: Dictionary) -> int:
	return int(cfg.get("cap", 100))


static func clamp_morale(v: Variant, cfg: Dictionary) -> int:
	return clampi(int(v), 0, cap(cfg))


static func initial(cfg: Dictionary) -> int:
	return clamp_morale(cfg.get("initial", 100), cfg)


# 每月初一民心變化：稅率階級（"low"/"normal"/"high"）→ 加減（高稅 −4【原】）
static func tax_drop(tax: String, cfg: Dictionary) -> int:
	return int((cfg.get("taxDrop", {}) as Dictionary).get(tax, 0))


# 救災/捐贈官令名聲 → 民心增益：每 10 名聲 +0.1（fame × famePerMorale），
# 連同本月已得 gained 一齊封頂 monthlyGainCap【自訂】。回傳今次可加值。
static func morale_gain(fame: int, gained: float, cfg: Dictionary) -> float:
	var cap_v := float(cfg.get("monthlyGainCap", 10.0))
	var raw := float(fame) * float(cfg.get("famePerMorale", 0.01))
	return maxf(0.0, minf(raw, cap_v - float(gained)))


# 市場 prod 乘數 = 民心/100（spec §9「市場 prod 乘民心/100」）
static func prod_mult(morale: int, cfg: Dictionary) -> float:
	return clampf(float(morale) / float(cap(cfg)), 0.0, 1.0)


# 民心低 → 每月人口流失後嘅人口（≥ lowThreshold 唔變；越低流失越多）
static func pop_after(morale: int, pop: int, cfg: Dictionary) -> int:
	var th := int(cfg.get("lowThreshold", 50))
	if morale >= th or pop <= 0:
		return pop
	var frac := float(th - morale) / float(th)
	var lost := int(round(float(pop) * float(cfg.get("popLossRate", 0.05)) * frac))
	return maxi(0, pop - lost)


# 民心低 → 兵源減：徵兵產出乘數（同 prod_mult 但設地板，避免歸零）
static func recruit_mult(morale: int, cfg: Dictionary) -> float:
	return maxf(float(cfg.get("recruitFloor", 0.3)), prod_mult(morale, cfg))


# ---- 城池法令 (spec §10；頭寫「保留 4 條」，但表 ✔ 咗 6 條 → 照表全部實裝) ----

static func laws(law_cfg: Dictionary) -> Array:
	return law_cfg.get("laws", [])


static func law_def(law_cfg: Dictionary, law_id: String) -> Dictionary:
	for l in laws(law_cfg):
		if String(l["id"]) == law_id:
			return l
	return {}


static func law_ids(law_cfg: Dictionary) -> Array:
	var out: Array = []
	for l in laws(law_cfg):
		out.append(String(l["id"]))
	return out


# 開局各法令預設開關
static func default_laws(law_cfg: Dictionary) -> Dictionary:
	var out := {}
	for l in laws(law_cfg):
		out[String(l["id"])] = bool(l.get("default", true))
	return out


# 每月 1 次：上次更改同一曆月 → 唔可以再改。回傳 "" = 得，否則原因。
static func change_block(last_day: int, cur_day: int, law_cfg: Dictionary) -> String:
	if int(last_day) < 0:
		return ""
	var per := int(law_cfg.get("perMonth", 1))
	if per <= 0:
		return ""
	var md := maxi(1, int(law_cfg.get("monthDays", 30)))
	if int(last_day) / md == int(cur_day) / md:
		return "城池法令每月改得一次"
	return ""


# 更改一次法令嘅行動力成本【原】100
static func ap_cost(law_cfg: Dictionary) -> int:
	return int(law_cfg.get("apCost", 100))
