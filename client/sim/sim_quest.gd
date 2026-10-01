extends "res://sim/sim_core.gd"
# Sim 繼承鏈 第 2 層: 任務系統 (Step 8) + 任務 PK 戰 + 任務讀取

func spawn_player(pname: String, class_id: String = "yishi", spawn_range: Array = []) -> int:
	var e := _spawn_actor(pname, "player", class_id, spawn_range)
	state["player_id"] = e["id"]
	_sync_quest_npcs()
	return int(e["id"])



# 原版世界開局 (maps.json world.origStart): 只喺原版許昌出生，唔放舊 ASCII 圖嘅怪/居民/捕快 (舊邏輯抽起，唔實裝)
func spawn_player_orig(pname: String, class_id: String = "yishi") -> int:
	var md: Dictionary = data.map_by_id.get(String(data.world.get("origHome", "xuchang_o")), {})
	return spawn_player(pname, class_id, (md.get("spawn", []) as Array))


# ================= 任務系統 (Step 8, spec 06 §1~2) =================

# 任務 NPC 可見性同步（時辰/等級/任務狀態變化時）; state["quest_npcs"] = {npc_id: {"visible": bool}}
func _sync_quest_npcs() -> void:
	var ch := player_ch()
	var ke := int(_clock()["ke"])
	var day := int(_clock()["day"])
	var qn: Dictionary = state["quest_npcs"]
	var changed := false
	for n in data.quest_npc_list:
		var nid := String(n["id"])
		var vis := RulesQuest.npc_shown(n, ch, ke, data.quests, day)
		var cur := bool(qn.get(nid, {}).get("visible", false))
		if vis != cur:
			qn[nid] = {"visible": vis}
			changed = true
	if changed:
		_emit({"k": "quest_npcs", "npcs": view_quest_npcs()})


func _quest_by_id(quest_id: String) -> Dictionary:
	for q in data.quests:
		if String(q["id"]) == quest_id:
			return q
	return {}


# quest 進度事件統一出口: 播對話 + emit + 獎勵訊息
# merge() 喺 Godot4 返 void，唔可以畀值用；呢度手動合埋兩個 dict (後覆蓋前)。
static func dict_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for k in over:
		out[k] = over[k]
	return out


func _quest_emit(e: Dictionary, q: Dictionary, res: Dictionary, speaker: String = "") -> void:
	var id := int(e["id"])
	var dlg: Array = res.get("dialog", [])
	for line in dlg:
		_msg(id, str(line))
	var payload := {"dst": id, "quest": q["id"], "dialog": dlg}
	if speaker != "":
		payload["speaker"] = speaker
	if bool(res.get("started", false)):
		payload["started"] = true
		payload["stage"] = int(res.get("stage", 0))
		_emit(dict_merge({"k": "quest"}, payload))
	elif bool(res.get("done", false)):
		_sync_stats(e)
		payload["done"] = true
		payload["reward"] = res.get("reward", {})
		_emit(dict_merge({"k": "quest"}, payload))
		_on_militia_quest_done(q)      # S08f: 團體任務完成 → 義勇軍績效 (sim_office override)
	else:
		payload["stage"] = int(res.get("stage", 0))
		_emit(dict_merge({"k": "quest"}, payload))
	_sync_quest_npcs()          # 開始/推進/完成都可能改 NPC 常駐 (questOnly boss/內應, Step 16)
	if not str(res.get("msg", "")).is_empty():
		_msg(id, str(res["msg"]))


# 同任務 NPC 對話: 檢查 pre → 觸發/推進 stage。NPC 位置/可見性由 quest_npcs.json 控制
func cmd_quest_talk(id: int, npc_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var npc: Dictionary = data.quest_npcs.get(npc_id, {})
	if npc.is_empty():
		return
	if not _near(e, int(npc["x"]), int(npc["y"])):
		return _msg(id, "要行近%s先得" % npc["name"])
	if not bool(state["quest_npcs"].get(npc_id, {}).get("visible", false)):
		return _msg(id, "呢度搵唔到%s" % npc["name"])
	var ch: Dictionary = e["ch"]
	_office_on_talk(e, "q:" + npc_id, int(npc["x"]), int(npc["y"]))
	# 服務 NPC（密醫免費醫療）
	var sv: Dictionary = npc.get("service", {})
	if not sv.is_empty():
		_quest_service(e, ch, npc)
		return
	var day := int(_clock()["day"])
	var spoke := false
	for q in data.quests:
		var res := RulesQuest.on_npc_talk(data, ch, q, npc_id, day)
		if bool(res.get("blocked", false)):          # 今日拜訪過 / 未帶齊信物: 提示，唔推進
			_msg(int(e["id"]), str(res["msg"]))
			spoke = true
			continue
		if not bool(res.get("changed", false)):
			continue
		spoke = true
		_quest_emit(e, q, res, String(npc.get("name", "")))
	if not spoke:
		spoke = _quest_talk_auto(e, npc_id)
	if not spoke:
		spoke = _comm_on_talk(e, npc_id)       # 居民委託 (Step 16): 送信到手 / 回報
	if not spoke:
		var pool: Array = npc.get("idle", [])
		if not pool.is_empty():
			_emit({"k": "npc_say", "id": 0, "name": str(npc["name"]), "text": str(pool[rng.below(pool.size())]),
				"action": "greet", "x": int(npc["x"]), "y": int(npc["y"])})


# 對話觸發 PK / 交收集品 (Step 16): 當前 stage = fight 且 npc 啱 → 開打；collect 且係 giver/stage npc → 交
func _quest_talk_auto(e: Dictionary, npc_id: String) -> bool:
	var ch: Dictionary = e["ch"]
	for q in data.quests:
		var stage := RulesQuest.stage_of(ch, q)
		if stage.is_empty():
			continue
		match String(stage.get("type", "")):
			"fight":
				if String(stage.get("npc", "")) == npc_id:
					cmd_quest_battle(int(e["id"]), String(q["id"]))
					return true
			"collect":
				if String(stage.get("npc", q.get("giver", ""))) == npc_id:
					cmd_quest_turnin(int(e["id"]), String(q["id"]))
					return true
	return false


# 服務 NPC 功能（密醫【原】: 免費醫療 100 HP，一日 3 次）
func _quest_service(e: Dictionary, ch: Dictionary, npc: Dictionary) -> void:
	var id := int(e["id"])
	var sv: Dictionary = npc["service"]
	if String(sv.get("kind", "")) == "book":       # 許昌老丈 (Step 16): 對話 = 試換收集冊
		cmd_book_exchange(id)
		return
	if String(sv.get("kind", "")) != "heal":
		return _msg(id, "%s：而家冇服務" % npc["name"])
	var qid := ""
	for q in data.quests:
		if String(q.get("type", "")) == "service" and String(q.get("giver", "")) == String(npc["id"]):
			qid = String(q["id"])
			break
	var st: Dictionary = ch.get("quests", {}).get(qid, {})
	var day := int(_clock()["day"])
	var used := 0
	if int(st.get("day", -1)) == day:
		used = int(st.get("used", 0))
	var per_day := int(sv.get("perDay", 3))
	if used >= per_day:
		return _msg(id, "密醫：今日嘅名額用晒喇，聽日再嚟")
	var mhp := _eff_max_hp(ch)
	var gain := mini(int(sv["hp"]), mhp - int(ch["hp"]))
	if gain <= 0:
		return _msg(id, "密醫：你精神飽滿，唔使醫")
	ch["hp"] = int(ch["hp"]) + gain
	e["hp"] = int(ch["hp"])
	ch["quests"][qid] = {"day": day, "used": used + 1}
	_emit({"k": "heal", "dst": id, "hp": gain, "used": used + 1})
	_msg(id, "密醫幫你醫治，回復 %d HP (今日 %d/%d 次)" % [gain, used + 1, per_day])


# 繳交收集道具 (collect stage)
func cmd_quest_turnin(id: int, quest_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var q := _quest_by_id(quest_id)
	if q.is_empty():
		return
	var gv := String(q.get("giver", ""))
	if gv != "":
		var npc: Dictionary = data.quest_npcs.get(gv, {})
		if npc.is_empty() or not _near(e, int(npc["x"]), int(npc["y"])):
			return _msg(id, "要行近交任務嘅 NPC 先得")
	var res := RulesQuest.on_turnin(data, e["ch"], q)
	if not bool(res.get("changed", false)):
		if not str(res.get("msg", "")).is_empty():
			_msg(id, str(res["msg"]))
		return
	var sp := String(data.quest_npcs.get(gv, {}).get("name", ""))
	_quest_emit(e, q, res, sp)


# 答題 (ask stage: 登用問答 / 任務題目)
func cmd_quest_answer(id: int, quest_id: String, answer_idx: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var q := _quest_by_id(quest_id)
	if q.is_empty():
		return
	var res := RulesQuest.on_answer(data, e["ch"], q, answer_idx)
	if not bool(res.get("changed", false)):
		# 答錯: 唔推進，但 NPC 回應對話（如有）照彈 + 信息欄提示（UAT point 2）
		var wdlg: Array = res.get("dialog", [])
		if not wdlg.is_empty():
			_emit({"k": "quest", "dst": id, "quest": q["id"], "dialog": wdlg,
				"speaker": String(data.quest_npcs.get(String(q.get("giver", "")), {}).get("name", ""))})
		if not str(res.get("msg", "")).is_empty():
			_msg(id, str(res["msg"]))
		return
	var spn := String(data.quest_npcs.get(String(q.get("giver", "")), {}).get("name", ""))
	_quest_emit(e, q, res, spn)


# 新手修練退款 (spec 06 §2): facility quest 進行中 → 免費；未開始 + pre ok → 由第一次使用自動觸發
func _fac_ensure_quest(ch: Dictionary, key: String) -> String:
	var day := int(_clock()["day"])
	for q in data.quests:
		var qid := String(q["id"])
		var st: Dictionary = ch.get("quests", {}).get(qid, {})
		if not st.is_empty():
			var stage := RulesQuest.stage_of(ch, q)
			if not stage.is_empty() and String(stage.get("type", "")) == "facility" and String(stage.get("fac", "")) == key:
				return qid
			continue
		var stages: Array = q.get("stages", [])
		if stages.is_empty() or bool(ch.get("questDone", {}).get(qid, false)):
			continue
		var st0: Dictionary = stages[0]
		if String(st0.get("type", "")) != "facility" or String(st0.get("fac", "")) != key:
			continue
		if not RulesQuest.pre_ok(data, q, ch):
			continue
		if not ch.has("quests"):
			ch["quests"] = {}
		ch["quests"][qid] = {"stage": 0, "startDay": day, "flags": {}}
		return qid
	return ""


func _finish_fac_quest(e: Dictionary, ch: Dictionary, qid: String, key: String) -> void:
	var q := _quest_by_id(qid)
	if q.is_empty():
		return
	var res := RulesQuest.on_facility(data, ch, q, key, int(_clock()["day"]))
	if bool(res.get("changed", false)):
		_quest_emit(e, q, res)


# S08f hook: 團體任務完成 → 義勇軍績效；sim_quest 唔識 militia，預設 no-op，由 sim_office override。
func _on_militia_quest_done(_q: Dictionary) -> void:
	pass


# ================= 任務讀取 (UI 記事用) =================
func view_quest_npcs() -> Array:
	var out: Array = []
	for n in data.quest_npc_list:
		var qv: Dictionary = state["quest_npcs"].get(String(n["id"]), {})
		if bool(qv.get("visible", false)):
			out.append({"id": n["id"], "name": n["name"], "x": n["x"], "y": n["y"], "desc": n.get("desc", ""),
				"service": (n.get("service", {}) as Dictionary).size() > 0,
				"svc": String(n.get("service", {}).get("kind", "")), "comm": bool(n.get("commission", false)),
				"battle": bool(n.get("battle", false))})
	return out


# 記事 UI: 地標典籍（spec 12 §5 / UAT-feedback）——探到嘅史蹟地標可重睇典故；唔存 text（data 靜態有），ch.landmarks = 已探 id
func view_landmarks() -> Array:
	var ch := player_ch()
	var seen: Array = (ch.get("landmarks", []) as Array) if ch is Dictionary else []
	var out: Array = []
	for lm in data.landmarks:
		var mid := String(lm["map"])
		var is_seen := false
		for sid in seen:
			if String(sid) == String(lm["id"]):
				is_seen = true
				break
		out.append({"id": String(lm["id"]), "name": String(lm["name"]), "map": mid,
			"mapName": _lm_map_name(mid), "text": String(lm.get("text", "")), "seen": is_seen})
	return out


func _lm_map_name(map_id: String) -> String:
	for md in data.maps:
		if String(md.get("id", "")) == map_id:
			return String(md.get("name", map_id))
	return map_id


func view_quests() -> Array:
	var ch := player_ch()
	var out: Array = []
	for q in data.quests:
		if bool(q.get("hidden", false)):
			continue
		var qid := String(q["id"])
		var entry := {"id": qid, "name": q["name"], "type": q["type"]}
		if bool(ch.get("questDone", {}).get(qid, false)):
			entry["done"] = true
		elif not (ch.get("quests", {}) as Dictionary).is_empty() and (ch["quests"] as Dictionary).has(qid):
			entry["active"] = true
			entry["stage"] = int(ch["quests"][qid].get("stage", 0))
			entry["hint"] = RulesQuest.hint(q, ch)
		else:
			entry["hint"] = RulesQuest.hint(q, ch)   # 未開始: preHint
		out.append(entry)
	return out


# ================= 任務寶箱 (chest stage, S2-2) =================
# 行近指定 NPC 領路 → 喺 NPC 隔籬 spawn 一個鎖住嘅任務寶箱（標 quest）；仕女開鎖打開 → quest 推進
func cmd_quest_chest(id: int, quest_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var q := _quest_by_id(quest_id)
	if q.is_empty():
		return
	var stage := RulesQuest.stage_of(e["ch"], q)
	if stage.is_empty() or String(stage.get("type", "")) != "chest":
		return _msg(id, "而家唔係尋寶箱階段")
	var npc: Dictionary = data.quest_npcs.get(String(stage.get("npc", "")), {})
	if npc.is_empty() or not _near(e, int(npc["x"]), int(npc["y"])):
		return _msg(id, "要行近%s先得" % npc.get("name", ""))
	for o in ents.values():
		if o["kind"] == "chest" and String(o.get("quest", "")) == quest_id:
			return _msg(id, "寶箱仲喺度，用開鎖打開佢")
	var p := _free_near(int(npc["x"]), int(npc["y"]))
	var c := _new_ent(String(stage.get("chestName", "任務寶箱")), "chest", p)
	c["face"] = 0
	c["hp"] = 1
	c["max_hp"] = 1
	c["locked"] = true
	c["key"] = int(floor(rng.next() * CHEST_KEYS))
	c["drop"] = {"gold": 0, "items": []}
	c["quest"] = quest_id
	for line in stage.get("dialog", []):
		_msg(id, str(line))
	_msg(id, "%s出現咗，用「開鎖」打開佢" % c["name"])


# ================= 任務 PK 戰 (fight stage, Step 10, spec 06 §5) =================
# 同指定 NPC 對話後召喚 boss (stage.monster)；打贏 → quest 自動推進 (getItem 派條目)
func cmd_quest_battle(id: int, quest_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var q := _quest_by_id(quest_id)
	if q.is_empty():
		return
	var stage := RulesQuest.stage_of(e["ch"], q)
	if stage.is_empty() or String(stage.get("type", "")) != "fight":
		return _msg(id, "而家唔係 PK 戰階段")
	var npc: Dictionary = data.quest_npcs.get(String(stage.get("npc", "")), {})
	if npc.is_empty() or not _near(e, int(npc["x"]), int(npc["y"])):
		return _msg(id, "要行近%s先得" % npc.get("name", ""))
	for ti in stage.get("takeItems", []):
		if not RulesShop.has_item(e["ch"]["bag"], int(ti[0]), int(ti[1])):
			return _msg(id, "要帶齊%s先開得戰" % data.names.get(int(ti[0]), str(ti[0])))
	var boss_id := int(stage.get("monster", 0))
	if boss_id <= 0 or not data.monsters.has(boss_id):
		return
	var qid := String(q["id"])
	for o in ents.values():
		if o["kind"] == "mob" and str(o.get("mob", {}).get("quest_boss", "")) == qid:
			return _msg(id, "boss 仲喺度！")
	var b: Variant = _spawn_mob(boss_id, DEFAULT_ZONE)
	if b == null:
		return
	b["mob"]["quest_boss"] = qid
	var p := _free_near(int(npc["x"]), int(npc["y"]))     # 放喺 NPC 隔籬行得嘅格
	b["x"] = p.x
	b["y"] = p.y
	b["mob"]["zone"] = map_id_at(p.x, p.y)
	b["tx"] = b["x"]
	b["ty"] = b["y"]
	b["mob"]["home_x"] = b["x"]
	b["mob"]["home_y"] = b["y"]
	for line in stage.get("dialog", []):
		_msg(id, str(line))
	_emit({"k": "quest_battle", "dst": id, "quest": quest_id, "name": str(b["name"]), "id": int(b["id"])})
	_msg(id, "%s出現咗！打定輸贏！" % b["name"])
