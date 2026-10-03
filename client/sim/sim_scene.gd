extends "res://sim/sim_battle.gd"
# Sim 繼承鏈: 特殊場景 (S04d, spec 04 §4)。企喺 sim_battle 之上、sim_combat 之下，
# 咁 sim_combat 嘅 _kill_mob 先叫得落嚟嘅 _scene_on_boss_kill / _scene_exit。
# 同戰役嘅分別: 開門 = game 日曆窗口（非時辰窗）；每層多款怪物 + density；boss:true 打完先過層；
# 掉落照喺 _kill_mob 處理——場景怪 (scene_id != "") 掉寶照直入袋（同戰役，teleport 過層唔返頭執）。

# 場景入口 NPC (quest_npcs 帶 scene:<id> 標記)；揾第一隻
func _scene_gate(sid: String) -> Dictionary:
	for n in data.quest_npc_list:
		if String(n.get("scene", "")) == sid:
			return n
	return {}


func _month_days() -> int:
	return int(data.world["clock"].get("monthDays", 30))


# 場景開住邊啲 + 玩家進度 (read-model，記事/地圖/入口 UI)
func view_scenes(id: int) -> Dictionary:
	var e := ent(id)
	var day := int(_clock()["day"])
	var md := _month_days()
	var out := {"day": day, "dayOfMonth": RulesScene.day_of_month(day, md), "list": [], "inScene": false}
	for s in data.scenes:
		var sid := String(s["id"])
		out["list"].append({"id": sid, "name": String(s["name"]),
			"minLevel": int(s.get("minLevel", 1)),
			"open": RulesScene.is_open(s, day, md),
			"openDays": RulesScene.open_days_text(s),
			"entryMap": String(s.get("entryMap", "")),
			"in": bool(e.has("scene")) and String(e["scene"]["id"]) == sid})
	if e.has("scene"):
		var sc: Dictionary = e["scene"]
		var s2 := RulesScene.find(data.scenes, String(sc["id"]))
		out["inScene"] = true
		out["sceneName"] = String(s2.get("name", String(sc["id"])))
		out["layer"] = int(sc["layer"]) + 1
		out["totalLayers"] = RulesScene.layer_count(s2)
	return out


# 入口 NPC 睇嘅單場狀態 (context dialog 用)
func scene_view(id: int, sid: String) -> Dictionary:
	var e := ent(id)
	var s := RulesScene.find(data.scenes, sid)
	var day := int(_clock()["day"])
	var md := _month_days()
	var out := {"id": sid, "name": String(s.get("name", "")), "open": RulesScene.is_open(s, day, md),
		"err": RulesScene.can_enter(s, int(e["ch"]["level"]), day, md),
		"minLevel": int(s.get("minLevel", 1)), "openDays": RulesScene.open_days_text(s),
		"inScene": e.has("scene") and String(e["scene"].get("id", "")) == sid}
	if bool(out["inScene"]):
		out["layer"] = int(e["scene"]["layer"]) + 1
		out["totalLayers"] = RulesScene.layer_count(s)
	return out


func cmd_scene_enter(id: int, sid: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if e.has("scene"):
		if String(e["scene"].get("id", "")) == sid:
			return _msg(id, "已經喺%s入面" % String(RulesScene.find(data.scenes, sid).get("name", "")))
		return _msg(id, "喺另一個場景入面，先離開先")
	var gate := _scene_gate(sid)
	if gate.is_empty() or String(gate.get("map", "")) != map_id_at(int(e["x"]), int(e["y"])) \
			or not _near(e, int(gate["x"]), int(gate["y"])):
		return _msg(id, "要行近%s入口先入得" % String(RulesScene.find(data.scenes, sid).get("name", "")))
	var s := RulesScene.find(data.scenes, sid)
	# 三轉考驗期間七彩奪寶陣長開 (S01e)
	var t3_open := sid == "qicai" and (e["ch"].get("quests", {}) as Dictionary).has(RulesClass.PROMOTE_QUEST_T3)
	var err := RulesScene.can_enter(s, int(e["ch"]["level"]), int(_clock()["day"]), _month_days(), t3_open)
	if err != "":
		return _msg(id, err)
	e["scene"] = {"id": sid, "layer": 0, "back_x": int(gate["x"]), "back_y": int(gate["y"])}
	_scene_goto_layer(e, s, 0)
	_emit({"k": "scene_enter", "dst": id, "name": String(s["name"])})


func cmd_scene_leave(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("scene"):
		return
	_msg(id, "離開咗特殊場景")
	_scene_exit(e, "leave")


func _scene_goto_layer(e: Dictionary, s: Dictionary, layer_idx: int) -> void:
	var layer := RulesScene.layer_of(s, layer_idx)
	var mid := String(layer["map"])
	var md := _map_def(mid)
	var sp: Array = md.get("spawn", [])
	var px := int(sp[0]) if sp.size() >= 2 else int(md.get("ox", 0)) + 2
	var py := int(sp[1]) if sp.size() >= 2 else int(md.get("oy", 0)) + 2
	e["x"] = px; e["tx"] = px; e["y"] = py; e["ty"] = py
	e.erase("path"); e.erase("goto")
	e["atk_target"] = 0
	e["scene"]["layer"] = layer_idx
	var sid := String(s["id"])
	var monsters: Array = layer.get("monsters", [])
	for mid2 in monsters:
		var def_id := int(mid2)
		var cnt := 1 if RulesScene.scene_boss_of(s, def_id) else maxi(1, int(layer.get("density", 1)))
		for i in cnt:
			var boss: Variant = _spawn_mob(def_id, mid)
			if boss == null:
				continue
			boss["mob"]["scene_id"] = sid
			boss["mob"]["scene_layer"] = layer_idx
			if RulesScene.scene_boss_of(s, def_id):
				boss["mob"]["scene_boss"] = true
	_msg(int(e["id"]), "%s 第 %d 層（共 %d 層）" % [String(s["name"]), layer_idx + 1, RulesScene.layer_count(s)])


# sim_combat._kill_mob 打死場景 boss 之後叫呢個: 未到尾層 = 過下層，到尾 = 完場
func _scene_on_boss_kill(by: Dictionary, sid: String, layer_idx: int) -> void:
	if not by.has("scene"):
		return
	var s := RulesScene.find(data.scenes, sid)
	if RulesScene.is_last_layer(s, layer_idx):
		_msg(int(by["id"]), "%s通晒！" % String(s["name"]))
		_emit({"k": "scene_win", "dst": int(by["id"]), "name": String(s["name"])})
		_scene_exit(by, "win")
	else:
		_scene_goto_layer(by, s, layer_idx + 1)


# 離開場景 (完成/放棄/死亡都經呢度): 清晒呢場遺留嘅 mob + 傳送返入口
func _scene_exit(e: Dictionary, _reason: String) -> void:
	var sc: Dictionary = e.get("scene", {})
	if sc.is_empty():
		return
	var sid := String(sc["id"])
	var to_erase: Array = []
	for o in ents.values():
		if o["kind"] == "mob" and String(o.get("mob", {}).get("scene_id", "")) == sid:
			to_erase.append(int(o["id"]))
	for oid in to_erase:
		ents.erase(oid)
	var bx := int(sc.get("back_x", int(e["x"])))
	var byy := int(sc.get("back_y", int(e["y"])))
	e["x"] = bx; e["tx"] = bx; e["y"] = byy; e["ty"] = byy
	e.erase("path"); e.erase("goto")
	e["atk_target"] = 0
	e.erase("scene")