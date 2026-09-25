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
# 分配: 名將 override (按名)；其餘 = 合類型 + impl 嘅特技按 id 固定抽 (同 id 永遠一樣)
static func skill_for(g: Dictionary, skills: Array, override: Dictionary) -> int:
	var nm := String(g["name"])
	if override.has(nm):
		return int(override[nm])
	var pool: Array = []
	for s in skills:
		if bool(s.get("impl", false)) and (s["types"] as Array).has(String(g["type"])):
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
static func skill_pick(order: String, mp: int, sp: int, mp_need: int, sp_need: int, ready: bool) -> String:
	if not ready:
		return ""
	if order == "ult" and sp >= sp_need:
		return "ult"
	if order == "spell" and mp >= mp_need:
		return "spell"
	return ""
