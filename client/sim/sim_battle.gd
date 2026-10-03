extends "res://sim/sim_econ.gd"
# Sim 繼承鏈: 戰役任務 (Step 19, spec 06 §7)。企喺 sim_econ 之上、sim_combat 之下，
# 咁 sim_combat 嘅 _kill_mob/_kill_player 先叫得落嚟嘅 _battle_on_boss_kill / _battle_exit。
# 教學/單機簡化【自訂】: 冇行門，靠直接傳送入層/過層/出返去，唔跟原版「戰役地圖」實體場景。

func _battle_herald() -> Dictionary:
	for n in data.quest_npc_list:
		if bool(n.get("battle", false)):
			return n
	return {}


func battle_view(id: int) -> Dictionary:
	var e := ent(id)
	var ke := int(_clock()["ke"])
	var open_id := RulesBattle.open_id(data.battles, ke)
	var out := {"open": open_id, "inBattle": false}
	if not open_id.is_empty():
		var b := RulesBattle.find(data.battles, open_id)
		out["name"] = String(b["name"])
		out["maxLevel"] = int(b["maxLevel"])
		out["playable"] = bool(b.get("playable", false))
	if e.has("battle"):
		var bt: Dictionary = e["battle"]
		var b2 := RulesBattle.find(data.battles, String(bt["id"]))
		out["inBattle"] = true
		out["battleName"] = String(b2.get("name", ""))
		out["floor"] = int(bt["floor"]) + 1
		out["totalFloors"] = RulesBattle.floor_count(b2)
	return out


# S04c: 記事/大地圖 讀戰役日程 (UI read-model，架構 A2)。全部 6 場 + 而家開邊場 + 玩家進度
func view_battles(id: int) -> Dictionary:
	var e := ent(id)
	var ke := int(_clock()["ke"])
	var open_id := RulesBattle.open_id(data.battles, ke)
	var list: Array = []
	for b in data.battles:
		var w: Dictionary = b["window"]
		list.append({"id": String(b["id"]), "name": String(b["name"]),
			"maxLevel": int(b["maxLevel"]),
			"startKe": int(w["startKe"]), "endKe": int(w["endKe"]),
			"open": String(b["id"]) == open_id})
	var out := {"ke": ke, "open": open_id, "list": list, "inBattle": false}
	if e.has("battle"):
		var bt: Dictionary = e["battle"]
		var b2 := RulesBattle.find(data.battles, String(bt["id"]))
		out["inBattle"] = true
		out["battleName"] = String(b2.get("name", ""))
		out["floor"] = int(bt["floor"]) + 1
		out["totalFloors"] = RulesBattle.floor_count(b2)
	return out


func cmd_battle_enter(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if e.has("battle"):
		return _msg(id, "已經喺戰役入面")
	var herald := _battle_herald()
	if herald.is_empty() or String(herald.get("map", "")) != map_id_at(int(e["x"]), int(e["y"])) \
			or not _near(e, int(herald["x"]), int(herald["y"])):
		return _msg(id, "要行近義勇士兵先報名得")
	var ke := int(_clock()["ke"])
	var bid := RulesBattle.open_id(data.battles, ke)
	var b := RulesBattle.find(data.battles, bid)
	var err := RulesBattle.can_enter(b, int(e["ch"]["level"]))
	if err != "":
		return _msg(id, err)
	e["battle"] = {"id": bid, "floor": 0, "back_x": int(herald["x"]), "back_y": int(herald["y"])}
	_battle_goto_floor(e, b, 0)
	_emit({"k": "battle_enter", "dst": id, "name": String(b["name"])})


func cmd_battle_leave(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("battle"):
		return
	_msg(id, "放棄咗戰役")
	_battle_exit(e, "leave")


func _map_def(mid: String) -> Dictionary:
	for m in data.maps:
		if String(m["id"]) == mid:
			return m
	return {}


func _battle_goto_floor(e: Dictionary, b: Dictionary, floor_idx: int) -> void:
	var fl := RulesBattle.floor_of(b, floor_idx)
	var mid := String(fl["map"])
	var md := _map_def(mid)
	var sp: Array = md.get("spawn", [])
	var px := int(sp[0]) if sp.size() >= 2 else int(md.get("ox", 0)) + 2
	var py := int(sp[1]) if sp.size() >= 2 else int(md.get("oy", 0)) + 2
	_battle_clear_mobs(String(b["id"]), true)
	e["x"] = px
	e["tx"] = px
	e["y"] = py
	e["ty"] = py
	e.erase("path")
	e.erase("goto")
	e["atk_target"] = 0
	e["battle"]["floor"] = floor_idx
	var blv := int(data.mob_def(int(fl["monster"]), 0).get("level", 1))
	for pr in fl.get("mobs", []):                        # 層小怪 (離層/離場清走)
		for _i in int(pr[1]):
			var mb: Variant = _spawn_mob(int(pr[0]), mid, maxi(1, blv - 2))
			if mb != null:
				mb["mob"]["battle_mob"] = String(b["id"])
	var boss: Variant = _spawn_mob(int(fl["monster"]), mid)
	if boss != null:
		boss["mob"]["battle_id"] = String(b["id"])
		boss["mob"]["battle_floor"] = floor_idx
	_msg(int(e["id"]), "%s 第 %d 層：%s 出現！" % [String(b["name"]), floor_idx + 1, String(fl["boss"])])


# sim_combat._kill_mob 打死 battle boss 之後叫呢個: 未到尾層 = 過下層，到尾 = 完場
func _battle_on_boss_kill(by: Dictionary, bid: String, floor_idx: int) -> void:
	if not by.has("battle"):
		return
	var b := RulesBattle.find(data.battles, bid)
	if RulesBattle.is_last_floor(b, floor_idx):
		_msg(int(by["id"]), "%s戰役完成！" % String(b["name"]))
		_emit({"k": "battle_win", "dst": int(by["id"]), "name": String(b["name"])})
		_battle_exit(by, "win")
	else:
		_battle_goto_floor(by, b, floor_idx + 1)


# 清戰役遺留怪: 小怪 (battle_mob) 一定清；boss (battle_id) 只喺離場先清
func _battle_clear_mobs(bid: String, mobs_only: bool) -> void:
	var to_erase: Array = []
	for o in ents.values():
		if o["kind"] != "mob":
			continue
		var mb: Dictionary = o.get("mob", {})
		if String(mb.get("battle_mob", "")) == bid or (not mobs_only and String(mb.get("battle_id", "")) == bid):
			to_erase.append(int(o["id"]))
	for oid in to_erase:
		ents.erase(oid)


# 離開戰役 (完成/放棄/死亡都經呢度): 清晒呢場遺留嘅 boss + 傳送返報名點
func _battle_exit(e: Dictionary, _reason: String) -> void:
	var bt: Dictionary = e.get("battle", {})
	if bt.is_empty():
		return
	var bid := String(bt["id"])
	_battle_clear_mobs(bid, false)
	var bx := int(bt.get("back_x", int(e["x"])))
	var byy := int(bt.get("back_y", int(e["y"])))
	e["x"] = bx
	e["tx"] = bx
	e["y"] = byy
	e["ty"] = byy
	e.erase("path")
	e.erase("goto")
	e["atk_target"] = 0
	e.erase("battle")
