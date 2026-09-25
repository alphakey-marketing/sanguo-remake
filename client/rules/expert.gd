class_name RulesExpert
extends RefCounted
# 專長 (Step S01c, spec 01 §8)。純函數。data = GameData.experts (skills/caps/levelExp)
# ch.expert = { skillId: exp(int) } 未學過 = 冇 key (= 0 exp = 0 級)


# 呢個職業該專長嘅等級上限 (1~4)；表冇 (偵查/統御/補給) = 0 (未解鎖，S10 先做)
# tier = 職階 (S01d, spec 01 §7): 二轉 +1 / 三轉 +2【自訂】，封頂喺 levelExp 表長度 (現 6 級)
static func cap_of(data: Dictionary, class_id: String, skill_id: String, tier: int = 0) -> int:
	var base := int(data.get("caps", {}).get(class_id, {}).get(skill_id, 0))
	if base <= 0:
		return 0
	return mini(base + tier, int((data.get("levelExp", []) as Array).size()))


# exp 對應嘅生嘅級 (唔理上限)：levelExp = 每級門檻 (累積)
static func level_of_exp(exp: int, level_exp: Array) -> int:
	var lv := 0
	for i in level_exp.size():
		if exp >= int(level_exp[i]):
			lv = i + 1
	return lv


# 實際生效等級 = min(exp 對應級, 職業上限)；tier = 職階 (S01d 二轉/三轉上限提升)
static func eff_level(data: Dictionary, class_id: String, skill_id: String, exp: int, tier: int = 0) -> int:
	return mini(level_of_exp(exp, data.get("levelExp", [])), cap_of(data, class_id, skill_id, tier))


# 加專長 exp，封頂喺「呢職業上限」嘅門檻 (加多都冇用，唔使囤)
static func add_exp(ch: Dictionary, data: Dictionary, skill_id: String, amount: int) -> int:
	var cap := cap_of(data, String(ch.get("classId", "")), skill_id)
	var level_exp: Array = data.get("levelExp", [])
	var cap_exp := int(level_exp[cap - 1]) if cap >= 1 and cap <= level_exp.size() else 0
	var exp: Dictionary = ch.get("expert", {})
	var cur := int(exp.get(skill_id, 0))
	var nv := mini(cap_exp, cur + amount) if cap >= 1 else cur
	exp[skill_id] = nv
	ch["expert"] = exp
	return nv


# 交易專長: 買入折扣 (與魅力折扣分開計，各自上限 10%)
static func trade_buy_discount(lv: int) -> float:
	return minf(0.10, lv * 0.02)


# 交易專長: 賣出加成
static func trade_sell_bonus(lv: int) -> float:
	return minf(0.10, lv * 0.02)


# 內政專長: 工作完成度倍率 (留返 S08 接)
static func domestic_mult(lv: int) -> float:
	return 1.0 + 0.25 * lv


# 訓練/警戒專長: 營地訓練度/治安值倍率 (留返 S08 接)
static func militia_mult(lv: int) -> float:
	return 1.0 + 0.3 * lv


# 救災專長: 完成度倍率 (留返 S08 接)
static func relief_mult(lv: int) -> float:
	return 1.0 + 0.25 * lv


static func weather_unlocked(lv: int) -> bool:
	return lv >= 1


static func geo_unlocked(lv: int) -> bool:
	return lv >= 1
