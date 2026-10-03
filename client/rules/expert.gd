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


# 專長任務認證 (S06e, spec 06 §8): 直接將專長提升到指定等級 (唔降級，封頂喺職業上限)。
# 用 exp 門檻代表「已達 N 級」；回傳最終 exp。tier = 職階 (二轉/三轉上限提升)
static func certify(ch: Dictionary, data: Dictionary, skill_id: String, level: int, tier: int = 0) -> int:
	var exp: Dictionary = ch.get("expert", {})
	var cur := int(exp.get(skill_id, 0))
	var cap := cap_of(data, String(ch.get("classId", "")), skill_id, tier)
	if cap <= 0 or level <= 0:
		return cur
	var lv := mini(level, cap)
	var level_exp: Array = data.get("levelExp", [])
	var target := int(level_exp[lv - 1]) if lv >= 1 and lv <= level_exp.size() else 0
	if target > cur:
		exp[skill_id] = target
		ch["expert"] = exp
		return target
	return cur


# 專長效果說明 (專長頁用): 現級效果；lv<cap 再加「下一級」。純文字，數值同上面倍率函數一致
static func effect_line(skill_id: String, lv: int, cap: int) -> String:
	var nxt := lv + 1 if lv < cap else 0
	match skill_id:
		"kaiken", "zhaolai", "siyu", "tankuang", "xiuzhu", "gongyi":
			return "內政工作收益 ×%.2f" % domestic_mult(lv) + ("　→ 下一級 ×%.2f" % domestic_mult(nxt) if nxt > 0 else "（已達上限）")
		"jiuzai":
			return "救災完成度 ×%.2f" % relief_mult(lv) + ("　→ 下一級 ×%.2f" % relief_mult(nxt) if nxt > 0 else "（已達上限）")
		"xunlian", "jingjie":
			return "營地訓練度／治安 ×%.2f" % militia_mult(lv) + ("　→ 下一級 ×%.2f" % militia_mult(nxt) if nxt > 0 else "（已達上限）")
		"jiaoyi":
			var s := "買入 -%d%%　賣出 +%d%%" % [int(round(trade_buy_discount(lv) * 100.0)), int(round(trade_sell_bonus(lv) * 100.0))]
			if nxt > 0:
				s += "　→ 下一級 -%d%% / +%d%%" % [int(round(trade_buy_discount(nxt) * 100.0)), int(round(trade_sell_bonus(nxt) * 100.0))]
			return s + ("（買賣各封頂 10%）" if nxt == 0 or trade_buy_discount(nxt) >= 0.10 else "")
		"tianwen":
			return "已解鎖：天氣道具、渾天儀天氣情報" if weather_unlocked(lv) else "Lv1 解鎖：天氣道具、渾天儀天氣情報"
		"dili":
			return "已解鎖：地理功能" if geo_unlocked(lv) else "Lv1 解鎖：地理功能"
	return ""


# 專長使用方法 (專長頁用): 自動生效定要做乜
static func usage_line(skill_id: String) -> String:
	match skill_id:
		"kaiken", "zhaolai", "siyu", "tankuang", "xiuzhu", "gongyi":
			return "用法：去官宅做對應工作，自動加成；做得多就升級"
		"jiuzai":
			return "用法：官宅領「救災」官令，自動加成"
		"xunlian", "jingjie":
			return "用法：義勇軍營地訓練／治安，自動加成"
		"jiaoyi":
			return "用法：喺商店買賣，自動減價／加價"
		"tianwen":
			return "用法：背包帶渾天儀，專長頁睇各城天氣"
		"dili":
			return "用法：解鎖後小地圖顯示設施"
	return ""

static func weather_unlocked(lv: int) -> bool:
	return lv >= 1


static func geo_unlocked(lv: int) -> bool:
	return lv >= 1
