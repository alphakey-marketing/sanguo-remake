class_name RulesGeneral
extends RefCounted
# 登用 v2 (Step 15, spec 09 §3.1/3.3/3.4)。純函數；設定喺 data/general_skills.json
# 【原】將軍令/御賜金牌無視條件、用完即消；寶物 2 格、同類高取代低 (低嘅消失)、攞唔返
# 【自訂】特技清單/效果、特技分配、寶物數值換算、同伴絕招/術法數值

# ================= 將軍令 / 御賜金牌 =================
# 物品名 → 將軍令對應嘅武將名 ("呂布將軍令" → "呂布")；唔係將軍令 = ""
static func order_general_name(item_name: String, suffix: String, alias: Dictionary = {}) -> String:
	if item_name.length() <= suffix.length() or not item_name.ends_with(suffix):
		return ""
	var n := item_name.substr(0, item_name.length() - suffix.length())
	return String(alias.get(n, n))              # 字號 → 名 (孔明 → 諸葛亮)


# 無視條件嘅憑證: "medal" (御賜金牌) / "order" (有該人才將軍令) / "" (冇)
# 金牌行先 (無視一切)；兩樣都有都只消耗金牌嗰樣
static func pass_kind(has_order: bool, has_medal: bool) -> String:
	if has_medal:
		return "medal"
	if has_order:
		return "order"
	return ""


# ================= 武將寶物 (2 格) =================
# 物品效果 → 寶物 {type, value}；唔係寶物 = {}。effects = items.json effects；cat 要啱
static func treasure_of(cat: int, effects: Array, cfg: Dictionary) -> Dictionary:
	if cat != int(cfg["treasureCat"]):
		return {}
	var tt: Dictionary = cfg["treasure"]
	for e in effects:
		var k := str(int(e.get("type", 0)))
		if tt.has(k):
			return {"type": k, "value": int(e.get("value", 0))}
	return {}


# 放寶物入格: slots = [{item, type, value}]；t = {type, value}
# → {"res": "add"/"replace"/"lost"/"full", "slots": 新 slots, "old": 被取代嘅 item (0 = 冇)}
# 同類: 新值 > 舊值 → 取代 (舊嘅消失)；否則新嘅消失 (lost)【原】
static func treasure_put(slots: Array, item: int, t: Dictionary, max_slots: int) -> Dictionary:
	var out: Array = slots.duplicate(true)
	for i in out.size():
		if String(out[i]["type"]) == String(t["type"]):
			if int(t["value"]) > int(out[i]["value"]):
				var old := int(out[i]["item"])
				out[i] = {"item": item, "type": String(t["type"]), "value": int(t["value"])}
				return {"res": "replace", "slots": out, "old": old}
			return {"res": "lost", "slots": out, "old": 0}
	if out.size() >= max_slots:
		return {"res": "full", "slots": out, "old": 0}
	out.append({"item": item, "type": String(t["type"]), "value": int(t["value"])})
	return {"res": "add", "slots": out, "old": 0}


# 寶物加成 → {"bonus": {strFlat/defFlat/spellDefFlat/evadePct}, "flat": {agi/int}, "stats": {troops/wucai/junlue}}
static func treasure_bonus(slots: Array, cfg: Dictionary) -> Dictionary:
	var bonus := {}
	var flat := {}
	var stats := {}
	for s in slots:
		var d: Dictionary = cfg["treasure"].get(String(s["type"]), {})
		if d.is_empty():
			continue
		var v := float(s["value"]) * float(d.get("mul", 1.0))
		if d.has("bonus"):
			var bk := String(d["bonus"])
			bonus[bk] = (float(bonus.get(bk, 0.0)) + v) if bk.ends_with("Pct") else (int(bonus.get(bk, 0)) + MathX.js_round(v))
		elif d.has("flat"):
			var fk := String(d["flat"])
			flat[fk] = int(flat.get(fk, 0)) + MathX.js_round(v)
		elif d.has("stat"):
			var sk := String(d["stat"])
			stats[sk] = int(d["set"]) if d.has("set") else int(stats.get(sk, 0)) + MathX.js_round(v)
	return {"bonus": bonus, "flat": flat, "stats": stats}


# ================= 特技 (70 項，先做 passive) =================
# 分配: 名將 override (按名) → 指定 pin (按名) → 抽 (合類型嘅池按 id 固定抽，同 id 永遠一樣)
# S07d「處理抽特技打亂問題」: 抽技池由 data 嘅 draw_pool 明確釘死 (唔再跟 impl flag 浮動)，
# 所以日後開多幾項特技都唔會改動其他武將原本抽到嘅特技；新開嘅特技經 pin / override 指派。
# draw_pool 空 = 舊行為 (由 impl flag 建池) 兼容舊 caller
static func skill_for(g: Dictionary, skills: Array, override: Dictionary, draw_pool: Dictionary = {}, pin: Dictionary = {}) -> int:
	var nm := String(g["name"])
	if override.has(nm):
		return int(override[nm])
	if pin.has(nm):
		return int(pin[nm])
	var pool: Array = []
	var t := String(g["type"])
	if draw_pool.has(t):
		for sid in (draw_pool[t] as Array):
			pool.append(int(sid))
	else:
		for s in skills:
			if bool(s.get("impl", false)) and (s["types"] as Array).has(t):
				pool.append(int(s["id"]))
	if pool.is_empty():
		return 0
	var h := (int(g["id"]) * 2654435761) & 0x7FFFFFFF
	return int(pool[h % pool.size()])


# 特技效果 dict (冇 / 未實作 = {})
static func skill_eff(skill: Dictionary) -> Dictionary:
	if skill.is_empty() or not bool(skill.get("impl", false)):
		return {}
	return skill.get("eff", {})


# 忠誠變動經特技調整: 跌 × lossMul (最少跌 1)；升 + giftAdd 喺 caller 處理
static func loyalty_delta(delta: int, eff: Dictionary) -> int:
	if delta >= 0 or not eff.has("loyaltyLossMul"):
		return delta
	return mini(-1, MathX.js_round(delta * float(eff["loyaltyLossMul"])))


# 殺怪經驗分成: 基本 expShare + 教導
static func exp_share(base: float, eff: Dictionary) -> float:
	return base + float(eff.get("expShareAdd", 0.0))


# 隊伍經驗池 (S02b, spec 02 §8)【自訂】: 70% 按傷害比例分 + 30% 平分俾有貢獻者 (dmg>0)
# dmg = {"id字串": 累積傷害}；貢獻者多過隊伍上限 6 → 只取傷害最高 6 個【原 隊伍上限 6】
# 回 {"id字串": exp}；dmg 空/total<=0 = {}
static func team_exp_split(total: int, dmg: Dictionary, cap: int = 6) -> Dictionary:
	var out := {}
	if dmg.is_empty() or total <= 0:
		return out
	var ids: Array = dmg.keys()
	if ids.size() > cap:
		ids.sort_custom(func(a, b): return float(dmg[a]) > float(dmg[b]))
		ids = ids.slice(0, cap)
	var total_dmg := 0.0
	for id in ids:
		total_dmg += float(dmg[id])
	if total_dmg <= 0.0:
		return out
	for id in ids:
		out[id] = MathX.js_round(float(total) * 0.7 * float(dmg[id]) / total_dmg) \
			+ MathX.js_round(float(total) * 0.3 / float(ids.size()))
	return out


# ================= 同伴絕招 / 術法 =================
# 同伴術法: 由武將戰術揀最高等級嘅攻擊戰術 → {name, elem}；冇 = 「計略」無屬性
static func spell_of(g: Dictionary, tactic_elems: Dictionary, names: Dictionary) -> Dictionary:
	var best := -1
	var best_lv := -1
	for s in g.get("skills", []):
		var sid := int(s[0])
		if tactic_elems.has(str(sid)) and int(s[1]) > best_lv:
			best = sid
			best_lv = int(s[1])
	if best < 0:
		return {"name": "計略", "elem": "none"}
	return {"name": String(names.get(str(best), "計略")), "elem": String(tactic_elems[str(best)])}


static func spell_mp(lv: int, sc: Dictionary) -> int:
	return MathX.js_round(float(sc["mpBase"]) + lv * float(sc["mpPerLv"]))


static func spell_power(lv: int, sc: Dictionary) -> float:
	return float(sc["powerBase"]) + lv * float(sc["powerPerLv"])


# 指令要唔要用技能: "ult"/"spell"/"" (普通攻擊)。夠 MP/SP + 冷卻完先用【原】唔夠 = 普通攻擊
# order = "ult"/"spell" 指定招式；"auto" (U16 skillMode 開關用) = 夠 SP 就用絕招，唔夠先試術法
static func skill_pick(order: String, mp: int, sp: int, mp_need: int, sp_need: int, ready: bool) -> String:
	if not ready:
		return ""
	if (order == "ult" or order == "auto") and sp >= sp_need:
		return "ult"
	if (order == "spell" or order == "auto") and mp >= mp_need:
		return "spell"
	return ""


# ================= 內政協助 / 被動特技 (S09c, spec 09 §3.3/§3.4) =================
# 攻略只舉「每刻恢復 HP / 發話唔扣飲水度 / 無限遁地 / 使用職業特技」4 例；70 項清單同效果皆【自訂】。
# 內政/生產/經濟類 = 同伴跟住主公時對主公系統嘅 passive 加成 (唔限距離，同政才/辯才一致)。

# 武將政治【自訂】: generals 表冇政治值 → 由智力換算 (政治 = round(智力 × polPerInt))
static func pol_of(g: Dictionary, cfg: Dictionary) -> int:
	return MathX.js_round(float(g.get("int", 0)) * float(cfg.get("polPerInt", 0.5)))


# 內政協助加成: 同伴政治 / polDivisor + 內政類特技 domesticAssist，封頂 maxAssist
# 呢個值會加落 RulesExpert.domestic_mult 一齊餵 RulesCity.attr_gain
static func assist_bonus(pol: int, eff: Dictionary, cfg: Dictionary) -> float:
	var v := float(pol) / float(cfg.get("polDivisor", 200.0)) + float(eff.get("domesticAssist", 0.0))
	return clampf(v, 0.0, float(cfg.get("maxAssist", 1.0)))


# 生產專精 45~48: 對應工作技能嘅經驗倍率 (1.0 = 冇加成)
static func work_exp_mult(eff: Dictionary, skill: String) -> float:
	if eff.is_empty() or String(eff.get("workSkill", "")) != skill:
		return 1.0
	return 1.0 + float(eff.get("workExpAdd", 0.0))


# 生產專精 49~51: 對應進階技能嘅成功率加成 (0.0 = 冇)
static func craft_rate_add(eff: Dictionary, skill: String) -> float:
	if eff.is_empty() or String(eff.get("craftSkill", "")) != skill:
		return 0.0
	return float(eff.get("craftRateAdd", 0.0))


# 商才 43: 買入 / 賣出價乘數 {buy, sell} (冇 = 1.0 / 1.0)
static func trade_mul(eff: Dictionary) -> Dictionary:
	var buy := 1.0
	var sell := 1.0
	if not eff.is_empty():
		buy = float(eff.get("tradeBuyMul", 1.0))
		sell = float(eff.get("tradeSellMul", 1.0))
	return {"buy": buy, "sell": sell}


# ================= 主動特技 (S09c-b, spec 09 §3.4) =================
# 21 無限遁地 / 32 挑釁 / 38 急救 = 同伴主動技，由主公落 cmd_companion_skill 指令。
# 種類由 eff["active"] 決定；冷卻 tick 由 eff["cd"]。22 職業特技 = proximity 被動 (見下面 class_skill_mul)。

# 主動特技種類: "burrow"/"taunt"/"heal"；"" = 唔係主動
static func active_kind(eff: Dictionary) -> String:
	return String(eff.get("active", ""))


# 主動特技冷卻 (tick)：缺省 0 = 無限
static func active_cd(eff: Dictionary) -> int:
	return int(eff.get("cd", 0))


# 主動特技用唔用得 → "" = 得；否則 = 原因。cooldowns = {kind: 冷卻完 tick}
static func active_block(eff: Dictionary, cooldowns: Dictionary, tick: int) -> String:
	var kind := active_kind(eff)
	if kind == "":
		return "同伴冇呢招主動特技"
	if tick < int(cooldowns.get(kind, 0)):
		return "特技冷卻中"
	return ""


# 38 急救: 回復量 = 主公上限 HP × hpPct (最少 1)
static func heal_amount(max_hp: int, eff: Dictionary) -> int:
	return maxi(1, MathX.js_round(float(maxi(1, max_hp)) * float(eff.get("healPct", 0.0))))


# 32 挑釁: 影響範圍 (格)
static func taunt_range(eff: Dictionary) -> int:
	return int(eff.get("tauntRange", 0))


# 22 職業特技 (proximity): 主公職業特技冷卻 / 消耗乘數 {cd, cost} (冇 = 1.0 / 1.0)
static func class_skill_mul(eff: Dictionary) -> Dictionary:
	return {"cd": float(eff.get("classSkillCdMul", 1.0)), "cost": float(eff.get("classSkillCostMul", 1.0))}
