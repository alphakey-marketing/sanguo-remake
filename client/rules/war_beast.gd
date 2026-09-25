class_name RulesWarBeast
extends RefCounted
# 戰騎 (Step 18a, spec 07 §8.1~8.2): 純函數，數值喺 data/war_beasts.json (cfg)。
# 戰騎 wb = 純資料 Dictionary (存喺 ch.warBeasts):
#   {uid, breed, nick, level, exp, attrs{pow,body,spirit,agi}, attrPts, battlePts, friendPts}
# 隨機數由 caller 傳入，呢度唔擲骰


static func breed_def(cfg: Dictionary, breed: String) -> Dictionary:
	for b in cfg["breeds"]:
		if String(b["id"]) == breed:
			return b
	return {}


static func breeds_enabled(cfg: Dictionary) -> Array:
	var out: Array = []
	for b in cfg["breeds"]:
		if bool(b.get("enabled", false)):
			out.append(b)
	return out


static func display_name(cfg: Dictionary, wb: Dictionary) -> String:
	if String(wb.get("nick", "")) != "":
		return String(wb["nick"])
	return String(breed_def(cfg, String(wb["breed"])).get("name", "戰騎"))


# 新戰騎: 屬性 = 品種底表 (§8.1)【原】；忠誠 = loyalty.start【自訂】
static func new_beast(cfg: Dictionary, breed: String, uid: int) -> Dictionary:
	var b := breed_def(cfg, breed)
	var attrs := {}
	for a in cfg["attrs"]:
		attrs[a] = int((b.get("attrs", {}) as Dictionary).get(a, 0))
	return {"uid": uid, "breed": breed, "nick": "", "level": 1, "exp": 0, "attrs": attrs,
		"attrPts": 0, "battlePts": 0, "friendPts": 0, "battleSkills": {}, "friendSkills": {},
		"loyalty": int(cfg["loyalty"]["start"])}


# 升到下一級所需經驗【自訂】: 同玩家公式款 (rules/stats.gd exp_to_next)，數值調過畀戰騎升得慢
static func exp_to_next(cfg: Dictionary, level: int) -> int:
	return MathX.js_round(float(cfg["expBase"]) * pow(level, float(cfg["expPow"])))


# 呢級每升一級發嘅 3 種點數 (§8.2)【原=1~25/26~50/51~75/76~100 四段】
static func points_for_level(cfg: Dictionary, level: int) -> Dictionary:
	for row in cfg["levelPoints"]:
		if level >= int(row["lo"]) and level <= int(row["hi"]):
			return row
	var last: Dictionary = cfg["levelPoints"][-1]
	return last if level > int(last["hi"]) else cfg["levelPoints"][0]


# 加經驗，可連升多級；每升一級發對應區間嘅 3 種點數。回傳升咗幾級
static func gain_exp(cfg: Dictionary, wb: Dictionary, amount: int) -> int:
	var ups := 0
	var max_lv := int(cfg["maxLevel"])
	wb["exp"] = int(wb["exp"]) + amount
	while int(wb["level"]) < max_lv and int(wb["exp"]) >= exp_to_next(cfg, int(wb["level"])):
		wb["exp"] = int(wb["exp"]) - exp_to_next(cfg, int(wb["level"]))
		var row := points_for_level(cfg, int(wb["level"]))
		wb["level"] = int(wb["level"]) + 1
		ups += 1
		wb["attrPts"] = int(wb.get("attrPts", 0)) + int(row["attrPts"])
		wb["battlePts"] = int(wb.get("battlePts", 0)) + int(row["battlePts"])
		wb["friendPts"] = int(wb.get("friendPts", 0)) + int(row["friendPts"])
	if int(wb["level"]) >= max_lv:
		wb["exp"] = 0
	return ups


# 屬性點分配: 1 點 = 對應屬性 +1 (上限 attrCap)【自訂=原文冇寫上限】
static func point_why(cfg: Dictionary, wb: Dictionary, attr: String) -> String:
	if not (cfg["attrs"] as Array).has(attr):
		return "冇呢個屬性"
	if int(wb.get("attrPts", 0)) <= 0:
		return "冇點數可以分配"
	if int(wb["attrs"][attr]) >= int(cfg["attrCap"]):
		return "%s已經到頂" % cfg["attrNames"][attr]
	return ""


static func spend_point(cfg: Dictionary, wb: Dictionary, attr: String) -> bool:
	if point_why(cfg, wb, attr) != "":
		return false
	wb["attrPts"] = int(wb["attrPts"]) - 1
	wb["attrs"][attr] = int(wb["attrs"][attr]) + 1
	return true


# ================= 戰鬥特技 (Step 18b, spec 07 §8.3) =================
# wb.battleSkills = {skill_id: level}；招式表存 cfg.battleSkills[breed] = [skill_def]（順序 = spec 表順序）


static func battle_skills_of(cfg: Dictionary, breed: String) -> Array:
	return (cfg["battleSkills"] as Dictionary).get(breed, [])


static func battle_skill_def(cfg: Dictionary, breed: String, skill_id: String) -> Dictionary:
	for s in battle_skills_of(cfg, breed):
		if String(s["id"]) == skill_id:
			return s
	return {}


# 「上一招」= 呢招喺品種表入面前一格（*招一定跟住返一招非 * 招）【原】
static func _prev_skill(cfg: Dictionary, breed: String, skill_id: String) -> Dictionary:
	var list := battle_skills_of(cfg, breed)
	for i in range(list.size()):
		if String(list[i]["id"]) == skill_id:
			return list[i - 1] if i > 0 else {}
	return {}


static func battle_skill_level(wb: Dictionary, skill_id: String) -> int:
	return int((wb.get("battleSkills", {}) as Dictionary).get(skill_id, 0))


# 訓練（升一級）得唔得: "" = 得【原=每級 1 點、最高 10 級；「*」招需上一招 >=5 級 + 唔可以高過上一招等級】
static func battle_train_why(cfg: Dictionary, wb: Dictionary, skill_id: String) -> String:
	var s := battle_skill_def(cfg, String(wb["breed"]), skill_id)
	if s.is_empty():
		return "冇呢招戰鬥特技"
	var lv := battle_skill_level(wb, skill_id)
	if lv >= int(cfg["battleMaxLv"]):
		return "已經頂級"
	if int(wb.get("battlePts", 0)) <= 0:
		return "冇戰鬥技點數"
	if bool(s.get("star", false)):
		var prev := _prev_skill(cfg, String(wb["breed"]), skill_id)
		var prev_lv := battle_skill_level(wb, String(prev.get("id", "")))
		if prev_lv < int(cfg["battleStarNeedLv"]):
			return "要「%s」練到 %d 級先學得" % [String(prev.get("name", "")), int(cfg["battleStarNeedLv"])]
		if lv >= prev_lv:
			return "唔可以高過「%s」嘅等級" % String(prev.get("name", ""))
	return ""


static func battle_train(cfg: Dictionary, wb: Dictionary, skill_id: String) -> bool:
	if battle_train_why(cfg, wb, skill_id) != "":
		return false
	wb["battlePts"] = int(wb["battlePts"]) - 1
	var bs: Dictionary = wb.get("battleSkills", {})
	bs[skill_id] = battle_skill_level(wb, skill_id) + 1
	wb["battleSkills"] = bs
	return true


# 招式數值 = val + valStep × (等級-1)【自訂，spec 淨係得效果文字】
static func skill_value(s: Dictionary, level: int) -> float:
	return float(s.get("val", 0.0)) + float(s.get("valStep", 0.0)) * float(level - 1)


# ================= 友好特技 (Step 18c, spec 07 §8.4) =================
# wb.friendSkills = {skill_id: true}；表存 cfg.friendSkills[breed] = [{id,name,tier,effect,needLoyalty?}]


static func friend_skills_of(cfg: Dictionary, breed: String) -> Array:
	return (cfg["friendSkills"] as Dictionary).get(breed, [])


static func friend_skill_def(cfg: Dictionary, breed: String, skill_id: String) -> Dictionary:
	for s in friend_skills_of(cfg, breed):
		if String(s["id"]) == skill_id:
			return s
	return {}


static func friend_learned(wb: Dictionary, skill_id: String) -> bool:
	return bool((wb.get("friendSkills", {}) as Dictionary).get(skill_id, false))


# 學呢招要幾多友好技點：跨戰騎學（唔係 wb 本身品種）× friendCrossMult【原】
static func friend_cost(cfg: Dictionary, wb: Dictionary, breed: String, skill_id: String) -> int:
	var s := friend_skill_def(cfg, breed, skill_id)
	var base := int((cfg["friendCosts"] as Array)[int(s.get("tier", 1)) - 1])
	return base if breed == String(wb["breed"]) else base * int(cfg["friendCrossMult"])


# 學得唔得: "" = 得【原=消耗友好技點；階數要順序學；第四階需忠誠(部分獨家招)】
static func friend_train_why(cfg: Dictionary, wb: Dictionary, breed: String, skill_id: String) -> String:
	var s := friend_skill_def(cfg, breed, skill_id)
	if s.is_empty():
		return "冇呢招友好特技"
	if friend_learned(wb, skill_id):
		return "已經學咗"
	var tier := int(s["tier"])
	if tier > 1:
		var list := friend_skills_of(cfg, breed)
		var prev_id := String(list[tier - 2]["id"])
		if not friend_learned(wb, prev_id):
			return "要學咗上一階先學得"
	var need_loy := int(s.get("needLoyalty", 0))
	if need_loy > 0 and int(wb.get("loyalty", 0)) < need_loy:
		return "忠誠要 %d 先學得 (而家 %d)" % [need_loy, int(wb.get("loyalty", 0))]
	if int(wb.get("friendPts", 0)) < friend_cost(cfg, wb, breed, skill_id):
		return "友好技點唔夠 (要 %d)" % friend_cost(cfg, wb, breed, skill_id)
	return ""


static func friend_train(cfg: Dictionary, wb: Dictionary, breed: String, skill_id: String) -> bool:
	if friend_train_why(cfg, wb, breed, skill_id) != "":
		return false
	wb["friendPts"] = int(wb["friendPts"]) - friend_cost(cfg, wb, breed, skill_id)
	var fs: Dictionary = wb.get("friendSkills", {})
	fs[skill_id] = true
	wb["friendSkills"] = fs
	return true


# ================= 忠誠 / 交易 (Step 18c, spec 07 §8.5) =================
# 戰鬥死亡: 忠誠 −1；跌到 desertAt 或以下 = 走佬(離隊消失)【原】。回 true = 走咗


static func on_death(cfg: Dictionary, wb: Dictionary) -> bool:
	var l: Dictionary = cfg["loyalty"]
	wb["loyalty"] = maxi(0, int(wb["loyalty"]) - int(l["deathLoss"]))
	return int(wb["loyalty"]) <= int(l["desertAt"])


# 交易 (單機簡化 = 賣畀 NPC)【原=忠誠 <5 唔可以交易、玩家 <10 級唔可以交易】
static func sell_why(cfg: Dictionary, wb: Dictionary, player_level: int) -> String:
	var l: Dictionary = cfg["loyalty"]
	if player_level < int(l["tradeMinPlayerLevel"]):
		return "要 %d 級先交易得" % int(l["tradeMinPlayerLevel"])
	if int(wb.get("loyalty", 0)) < int(l["tradeMinLoyalty"]):
		return "戰騎忠誠太低，唔可以交易"
	return ""


static func sell_price(cfg: Dictionary, wb: Dictionary) -> int:
	return int(cfg["sellBase"]) + int(wb["level"]) * int(cfg["sellPerLevel"])
