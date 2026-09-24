extends "res://sim/sim_ai.gd"
# Sim 繼承鏈 第 8 層: 登用武將 (Step 13.5, spec 09 §2~3)
# Tier1 武將 = 城內靜態 NPC (按時辰出現，同 quest_npcs 一樣唔入 ents)


# ================= Tier1 武將 (城內常駐) =================
# 而家見唔見到: 時辰窗口 + 冇離開城 (跟緊人/呢個月走咗)
func general_visible(g: Dictionary) -> bool:
	if _general_away(int(g["id"])):
		return false
	var w: Dictionary = g.get("window", {})
	return w.is_empty() or RulesQuest.ke_in_window(int(_clock()["ke"]), int(w["startKe"]), int(w["endKe"]))


# 武將唔喺城: 跟緊人 / 呢個月走咗 (state.generals[id].awayMonth)
func _general_away(gid: int) -> bool:
	var st: Dictionary = state.get("generals", {}).get(str(gid), {})
	if bool(st.get("serving", false)):
		return true
	return int(st.get("awayMonth", -1)) == _month()


func _month() -> int:
	return RulesRecruit.month_of(int(_clock()["day"]), int(data.world["clock"].get("monthDays", 30)))


func view_generals() -> Array:
	var out: Array = []
	for g in data.generals_t1:
		if general_visible(g):
			out.append({"id": int(g["id"]), "name": g["name"], "x": g["x"], "y": g["y"], "lv": int(g["lv"]),
				"type": g["type"], "sub": g["sub"], "ideo": g["ideo"], "map": g["map"]})
	return out


# 同 Tier1 武將傾偈: 講 idle 對白 + 簡介 (登用要用「調查」)
func cmd_general_talk(id: int, gid: int) -> void:
	var e := ent(id)
	var g: Dictionary = data.general_by_id.get(gid, {})
	if e.is_empty() or not e.has("ch") or g.is_empty() or int(g["tier"]) != 1:
		return
	if not general_visible(g):
		return _msg(id, "呢度搵唔到%s" % g["name"])
	if not _near(e, int(g["x"]), int(g["y"])):
		return _msg(id, "要行近%s先得" % g["name"])
	var pool: Array = g.get("idle", [])
	var text := String(pool[rng.below(pool.size())]) if not pool.is_empty() else "……"
	_emit({"k": "npc_say", "id": 0, "name": String(g["name"]), "text": text, "action": "greet",
		"x": int(g["x"]), "y": int(g["y"]), "general": gid})
	_msg(id, "%s（戰等 %d・%s%s・理念 %s）" % [g["name"], int(g["lv"]), RulesRecruit.type_name(String(g["type"])),
		String(g["sub"]), g["ideo"]])
