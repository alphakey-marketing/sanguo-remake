extends "res://sim/sim_quest.gd"
# Sim 繼承鏈 第 3 層: 設施 / 升級點數 / 建角欄位 / 移動 / 傳送 / 搭話

# 玩家/機械人 意圖

# 設施互動 (Step 3.2): training=練兵場 school=私塾 temple=寺廟
func cmd_facility(id: int, key: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var f: Dictionary = data.facilities.get(key, {})
	if f.is_empty():
		return
	if not _near(e, int(f["x"]), int(f["y"])):
		return _msg(id, "要行近%s先得" % f["name"])
	var ch: Dictionary = e["ch"]
	match key:
		"training": _fac_training(e, ch, f)
		"school":
			var qid := _fac_ensure_quest(ch, "school")
			if _fac_attr(e, ch, f, "pol", qid != ""):
				if qid != "":
					_finish_fac_quest(e, ch, qid, "school")
		"temple":
			var qid2 := _fac_ensure_quest(ch, "temple")
			if _fac_attr(e, ch, f, "cha", qid2 != ""):
				if qid2 != "":
					_finish_fac_quest(e, ch, qid2, "temple")


# 練兵場【原】: 2 人對練, 扣 HP+SP, +歷練 (升級時武/智/敏/靈提升)
func _fac_training(e: Dictionary, ch: Dictionary, f: Dictionary) -> void:
	var lv := int(ch["level"])
	var mhp := RulesStats.max_hp(lv, ch["attrs"])
	var msp := RulesStats.max_sp(lv, ch["attrs"])
	var id := int(e["id"])
	if tick < int(e.get("train_cd", 0)):
		return _msg(id, "啱啱練完，抖陣先")
	if int(ch["hp"]) < mhp * 0.35:
		return _msg(id, "體力唔夠對練 (HP 要 > 35%)")
	var lilian := int(ch.get("lilian", 0))
	if lilian >= int(f["lilianCap"]):
		return _msg(id, "歷練已滿 (%d)" % int(f["lilianCap"]))
	# 附近要有拍檔 (玩家或 bot)
	var partner := {}
	for b in ents.values():
		if int(b["id"]) == id or not b.has("ch") or int(b["hp"]) <= 0:
			continue
		if _near(e, int(b["x"]), int(b["y"])):
			partner = b
			break
	if partner.is_empty():
		return _msg(id, "附近冇人可以對練")
	ch["hp"] = maxi(1, int(ch["hp"]) - MathX.js_round(mhp * float(f["costHp"])))
	ch["sp"] = maxi(1, int(ch["sp"]) - MathX.js_round(msp * float(f["costSp"])))
	var pch: Dictionary = partner["ch"]
	pch["hp"] = maxi(1, int(pch["hp"]) - MathX.js_round(RulesStats.max_hp(int(pch["level"]), pch["attrs"]) * float(f["costHp"])))
	partner["hp"] = int(pch["hp"])
	_sync_stats(e)
	ch["lilian"] = lilian + int(f["lilian"])
	e["train_cd"] = tick + int(f["cooldownTicks"])
	_emit({"k": "train", "src": id, "partner": partner["name"], "lilian": int(ch["lilian"])})


# 私塾/寺廟【原】: 政治/魅力 +1, 扣 SP (+MP) + 金。free=true = 新手修練退款 (spec 06 §2，第一次唔使金)。
# 回傳成功與否 (新手任務只喺成功時推進)
func _fac_attr(e: Dictionary, ch: Dictionary, f: Dictionary, attr: String, free: bool = false) -> bool:
	var id := int(e["id"])
	var lv := int(ch["level"])
	var cost_gold := 0 if free else int(f.get("gold", 0))
	var cost_sp := MathX.js_round(RulesStats.max_sp(lv, ch["attrs"]) * float(f.get("costSp", 0.0)))
	var cost_mp := MathX.js_round(RulesStats.max_mp(lv, ch["attrs"]) * float(f.get("costMp", 0.0)))
	if int(ch["gold"]) < cost_gold:
		_msg(id, "要 %d 金" % cost_gold)
		return false
	if int(ch["sp"]) < cost_sp or int(ch["mp"]) < cost_mp:
		_msg(id, "精神不足 (要 SP%d/MP%d)" % [cost_sp, cost_mp])
		return false
	var v := int(ch["attrs"][attr])
	if v >= int(f["attrCap"]):
		_msg(id, "屬性已到上限 (%d)" % int(f["attrCap"]))
		return false
	ch["gold"] = int(ch["gold"]) - cost_gold
	ch["sp"] = int(ch["sp"]) - cost_sp
	ch["mp"] = int(ch["mp"]) - cost_mp
	ch["attrs"][attr] = v + 1
	_sync_stats(e)
	var an := "政治" if attr == "pol" else "魅力"
	_emit({"k": "train", "src": id, "type": "attr", "attr": an, "val": v + 1})
	return true


# ================= 升級點數 / 建角欄位 (Step 7.5, spec 01 §1/§2/§5) =================

# 升級自由點數: 扣 1 點，str/agi/int/spi +1；政治/魅力唔可以用升級點 (只能私塾/寺廟)
func cmd_raise_attr(id: int, attr: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var code := RulesStats.can_raise(ch, attr)
	match code:
		1: return _msg(id, "冇可分配點數 (升呢俾 %d 點)" % RulesStats.UPGRADE_POINTS)
		2: return _msg(id, "政治/魅力唔可以用升級點，去私塾/寺廟修練")
		3: return _msg(id, "屬性已到上限 99")
	RulesStats.raise_attr(ch, attr)
	_sync_stats(e)
	_emit({"k": "attr_rise", "src": id, "attr": attr, "val": int(ch["attrs"][attr]), "points": int(ch["attrPoints"])})


# 一鍵自動分配【自訂】: 按 classes.json.growth 建議比例派晒所有點
func cmd_auto_assign(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if int(ch.get("attrPoints", 0)) <= 0:
		return _msg(id, "冇可分配點數")
	RulesStats.auto_assign_points(ch, data.classes[ch["classId"]])
	_sync_stats(e)
	_emit({"k": "attr_auto", "src": id, "points": int(ch["attrPoints"])})
	_msg(id, "自動分配合成 (剩 %d 點)" % int(ch["attrPoints"]))


# 建角期間轉職業 (Step 9): 未出發 (Lv1) 先可以；重新生成角色
func cmd_select_class(id: int, class_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if int(ch["level"]) != 1:
		return _msg(id, "出發咗就唔可以轉職業")
	var cls: Dictionary = data.classes.get(class_id, {})
	if cls.is_empty() or not bool(cls["enabled"]):
		return _msg(id, "職業未開放")
	var name := str(ch["name"])
	ents.erase(id)
	var ne := _spawn_actor(name, "player", class_id)
	state["player_id"] = int(ne["id"])
	_sync_quest_npcs()
	_emit({"k": "reclass", "id": int(ne["id"]), "class": class_id, "name": name})
	_msg(int(ne["id"]), "轉職做「%s」" % cls["name"])


# 稱號【原】: ≤8 字，隨時可改
func cmd_set_title(id: int, title: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	title = title.strip_edges()
	if title.length() < 1 or title.length() > 8:
		return _msg(id, "稱號要 1~8 字")
	e["ch"]["title"] = title
	_msg(id, "稱號改做「%s」" % title)


# 生日: 影響福日 (生日嗰日練功 exp +10%) 同結婚年數
func cmd_set_birth(id: int, month: int, day: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var month_days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month < 1 or month > 12 or day < 1 or day > int(month_days[month - 1]):
		return _msg(id, "生日日期唔啱")
	e["ch"]["birthMonth"] = month
	e["ch"]["birthDay"] = day
	_msg(id, "生日設為 %d月%d日 (福日練功 +10%%)" % [month, day])


# 臉譜: 8 部位，款式 1..count (data/face.json)
func cmd_set_face(id: int, part: String, value: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var count: int = int(data.face_parts.get(part, 0))
	if count <= 0 or value < 1 or value > count:
		return _msg(id, "冇呢個部位/款式")
	e["ch"]["face"][part] = value
	_msg(id, "%s 款式設為 %d" % [part, value])


# 理念測驗: 一次過交答卷 (data/quiz.json 12 題，每題 0/1)，決定理念。決定了就唔可以改
func cmd_submit_quiz(id: int, answers: Array) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if not str(ch.get("ideology", "")).is_empty():
		return _msg(id, "理念已經決定咗，唔可以改")
	if not RulesQuiz.valid_answers(data, answers):
		return _msg(id, "答卷唔啱 (要 %d 題)" % (data.quiz as Array).size())
	var res := RulesQuiz.score(data, answers)
	ch["ideology"] = str(res["ideology"])
	ch["quizAnswers"] = []
	for a in answers:
		ch["quizAnswers"].append(int(a))
	_emit({"k": "quiz", "src": id, "ideology": str(res["ideology"])})
	_msg(id, "理念測驗完成：你嘅理念係「%s」" % str(res["ideology"]))
func cmd_move(id: int, x: int, y: int) -> void:
	var e := ent(id)
	if e.is_empty() or not is_free(x, y):
		return
	var ch: Dictionary = e.get("ch", {})
	if not ch.is_empty() and RulesSpell.blocks_move(ch.get("status", {}), tick):  # 中邪定身【原】
		if e["kind"] == "player":
			_msg(id, "中邪緊，郁唔到")
		return
	if e.has("casting"):                     # 吟唱期間移動 = 取消【原】
		e.erase("casting")
		if e["kind"] == "player":
			_msg(id, "移動取消咗吟唱")
		_emit({"k": "cast_interrupted", "dst": id, "reason": "move"})
	var cap := mini(PATH_CAP, 200 + 40 * (absi(x - int(e["x"])) + absi(y - int(e["y"]))))   # 近路唔使大搜
	_set_dest(e, x, y, cap)
	e["atk_target"] = 0      # 手動行路取消攻擊


func cmd_attack(id: int, target: int) -> void:
	var e := ent(id)
	var t := ent(target)
	if e.has("ch") and int(e["hp"]) > 0 and t.get("kind", "") == "mob":
		e["atk_target"] = target      # 安全區入面都可以追過去，行出安全區先真正出手 (見 _think_player)


# 傳送點 (Step 3.2+): 城內/城外之間即時傳送，要行近出發點
func cmd_travel(id: int, point_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var from_p := travel_point_by_id(point_id)
	if from_p.is_empty():
		return
	if not _near(e, int(from_p["x"]), int(from_p["y"])):
		return _msg(id, "要行近%s先得" % String(from_p["name"]))
	var to_p := travel_point_by_id(String(from_p["to"]))
	if to_p.is_empty():
		return
	e["x"] = int(to_p["x"])
	e["y"] = int(to_p["y"])
	e["tx"] = e["x"]
	e["ty"] = e["y"]
	e.erase("path")
	e["atk_target"] = 0
	if e.has("casting"):                     # 傳送 = 斷吟唱
		e.erase("casting")
		_emit({"k": "cast_interrupted", "dst": id, "reason": "travel"})
	_emit({"k": "travel", "dst": id, "to": String(to_p["name"]), "x": e["x"], "y": e["y"],
		"map": map_id_at(int(e["x"]), int(e["y"]))})


# 行咗一格之後 (step() 叫): 踩中 auto 傳送點 = 過圖；玩家行近史蹟地標 = 第一次彈典故 (spec 12 §4~5)
func _on_moved(e: Dictionary) -> void:
	if not e.has("ch"):
		return
	var pid: String = data.portal_at.get(int(e["y"]) * W + int(e["x"]), "")
	if pid != "":
		cmd_travel(int(e["id"]), pid)
		return
	if e["kind"] != "player":
		return
	for lm in data.landmarks:
		if not RulesCombat.in_range(e["x"], e["y"], int(lm["x"]), int(lm["y"]), float(lm.get("r", 3))):
			continue
		var seen: Array = e["ch"].get("landmarks", [])
		if seen.has(String(lm["id"])):
			continue
		seen.append(String(lm["id"]))
		e["ch"]["landmarks"] = seen
		_emit({"k": "landmark", "dst": int(e["id"]), "id": String(lm["id"]), "name": String(lm["name"]), "text": String(lm["text"])})
		_msg(int(e["id"]), "【%s】%s" % [lm["name"], lm["text"]])


# 跨圖路由 (spec 12 §4): 唔喺 map_id 就行去第一跳嘅門口 (地圖圖 BFS)；返 true = 處理緊 (未到)
func _route_to_map(e: Dictionary, map_id: String) -> bool:
	var cur := map_id_at(int(e["x"]), int(e["y"]))
	if cur == map_id or cur == "":
		return false
	var hop := next_portal(cur, map_id)
	if hop.is_empty():
		return false
	var px := int(hop["x"])
	var py := int(hop["y"])
	if int(e["x"]) == px and int(e["y"]) == py:
		cmd_travel(int(e["id"]), String(hop["id"]))
	elif int(e["tx"]) != px or int(e["ty"]) != py:
		cmd_move(int(e["id"]), px, py)
	return true


# 由 from_map 去 to_map 嘅第一個傳送點 (BFS，傳送點次序固定 → 決定性)
func next_portal(from_map: String, to_map: String) -> Dictionary:
	var first := {from_map: {}}
	var q: Array = [from_map]
	while not q.is_empty():
		var m: String = q.pop_front()
		for p in data.travel_points:
			if String(p["map"]) != m:
				continue
			var nm := String(travel_point_by_id(String(p["to"])).get("map", ""))
			if nm == "" or first.has(nm):
				continue
			first[nm] = p if m == from_map else first[m]
			if nm == to_map:
				return first[nm]
			q.append(nm)
	return {}


func cmd_chat(id: int, text: String) -> void:
	var e := ent(id)
	text = text.strip_edges().substr(0, 60)
	if e.is_empty() or text == "":
		return
	_emit({"k": "chat", "id": id, "name": e["name"], "text": text, "x": e["x"], "y": e["y"]})
	_witness_nearby(e, id, "greet", BotSys.W_GREET)
	_npc_react(e, id)


# 居民對打招呼嘅反應 (Step 5.4): brain 淨係揀白名單動作 + 生成話語，數值(好感)已經由
# _witness_nearby 結算好，brain 唔改任何數值
func _npc_react(actor_e: Dictionary, actor_id: int) -> void:
	var actor_ch: Dictionary = ent(actor_id).get("ch", {})
	var karma_tier := RulesKarma.tier(int(actor_ch.get("karma", 0))) if not actor_ch.is_empty() else 3
	for w in ents.values():
		if int(w["id"]) == actor_id or not w.has("mem"):
			continue
		if not RulesCombat.in_range(actor_e["x"], actor_e["y"], w["x"], w["y"], WITNESS_RANGE):
			continue
		var ctx := {"actor_name": actor_e.get("name", ""), "affinity": NpcMemory.affinity(w["mem"], actor_id), "karma_tier": karma_tier}
		var res := NpcBrain.decide(ctx, rng.below(4))
		if res["action"] == "ignore":
			continue
		_emit({"k": "npc_say", "id": w["id"], "name": w["name"], "text": res["line"], "action": res["action"], "x": w["x"], "y": w["y"]})
