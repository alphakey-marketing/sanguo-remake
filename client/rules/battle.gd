class_name RulesBattle
extends RefCounted
# 戰役任務純函數 (spec 06 §7, spec 04 §5, Step 19)【原 sy3_8】
# 6 場戰役窗口唔重疊 (每 16 刻一個，戌時起順序): 用 RulesQuest.ke_in_window 判斷。


static func find(battles: Array, id: String) -> Dictionary:
	for b in battles:
		if String(b["id"]) == id:
			return b
	return {}


# 邊場戰役而家開緊窗 (冇 = "")
static func open_id(battles: Array, ke: int) -> String:
	for b in battles:
		var w: Dictionary = b["window"]
		if RulesQuest.ke_in_window(ke, int(w["startKe"]), int(w["endKe"])):
			return String(b["id"])
	return ""


# 可以報名先? 得 = ""，唔得 = 提示字
static func can_enter(battle: Dictionary, level: int) -> String:
	if battle.is_empty():
		return "而家冇戰役開放"
	if not bool(battle.get("playable", false)):
		return "%s仲未開放【原型只做張牛角戰役】" % String(battle.get("name", ""))
	if level > int(battle["maxLevel"]):
		return "武等超過 %d，入唔到%s" % [int(battle["maxLevel"]), String(battle["name"])]
	return ""


static func floor_of(battle: Dictionary, idx: int) -> Dictionary:
	var floors: Array = battle.get("floors", [])
	if idx < 0 or idx >= floors.size():
		return {}
	return floors[idx]


static func floor_count(battle: Dictionary) -> int:
	return (battle.get("floors", []) as Array).size()


static func is_last_floor(battle: Dictionary, idx: int) -> bool:
	return idx >= floor_count(battle) - 1


# 死亡跌唔跌經驗/物品: 全部 6 場【原】都唔跌，留 flag 畀日後長阪坡類例外
static func drop_on_death(battle: Dictionary) -> bool:
	return bool(battle.get("dropOnDeath", false))
