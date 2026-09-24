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


# ================= 調查 / 考驗 (spec 09 §3.2) =================
# ch.recruit = {surveyDay, lockMonth, kind, cands:[gid], pending:{gid, kind:"arena"/"quiz", ...}, comp: 同伴 ent id}
func _rec(ch: Dictionary) -> Dictionary:
	if not ch.has("recruit"):
		ch["recruit"] = {}
	return ch["recruit"]


func _gen_state(gid: int) -> Dictionary:
	if not state.has("generals"):
		state["generals"] = {}
	var gs: Dictionary = state["generals"]
	if not gs.has(str(gid)):
		gs[str(gid)] = {}
	return gs[str(gid)]


# 呢個月唔喺城 / 跟緊人嘅武將 id (候選排除)
func _gone_ids() -> Dictionary:
	var out := {}
	for k in state.get("generals", {}):
		if _general_away(int(k)):
			out[int(k)] = true
	return out


func _gen_view(g: Dictionary) -> Dictionary:
	return {"id": int(g["id"]), "name": g["name"], "lv": int(g["lv"]), "type": g["type"], "sub": g["sub"],
		"ideo": g["ideo"], "t1": int(g["tier"]) == 1}


# 調查【原】: 城池街道用；每日 1 次 (唔理成敗)；成功登用嗰個月封鎖。kind = "wu" 武將登用 / "wen" 文官登用
func cmd_recruit_survey(id: int, kind: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0 or not ["wu", "wen"].has(kind):
		return
	var md := map_at(int(e["x"]), int(e["y"]))
	if String(md.get("kind", "")) != "city":
		return _msg(id, "要喺城池街道先可以調查")
	var ch: Dictionary = e["ch"]
	var rec := _rec(ch)
	if not (rec.get("pending", {}) as Dictionary).is_empty():
		return _msg(id, "考驗緊人才，未得閒調查")
	if int(rec.get("comp", 0)) != 0:
		return _msg(id, "已經有人才跟緊你")
	var day := int(_clock()["day"])
	var why := RulesRecruit.survey_block(rec, day, _month())
	if not why.is_empty():
		return _msg(id, why)
	rec["surveyDay"] = day
	var vis := {}
	for g in data.generals_t1:
		if String(g["map"]) == String(md["id"]) and general_visible(g):
			vis[int(g["id"])] = true
	var cands := RulesRecruit.candidates(data.generals, ch, kind, day, vis, _gone_ids(), data.recruit_cfg)
	rec["kind"] = kind
	rec["cands"] = []
	var views: Array = []
	for g in cands:
		rec["cands"].append(int(g["id"]))
		views.append(_gen_view(g))
	_emit({"k": "recruit_survey", "dst": id, "kind": kind, "cands": views})
	if views.is_empty():
		_msg(id, "調查咗一輪，搵唔到合適嘅%s" % RulesRecruit.type_name(kind))
	else:
		_msg(id, "調查到 %d 位%s願意見你" % [views.size(), RulesRecruit.type_name(kind)])


# 揀一位候選接受考驗: 武將 = 擂台 PK，文官 = 三國問答。每次調查只可以揀一位
func cmd_recruit_pick(id: int, gid: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var rec := _rec(ch)
	if not (rec.get("cands", []) as Array).has(gid) or not (rec.get("pending", {}) as Dictionary).is_empty():
		return _msg(id, "要先調查，再揀候選人才")
	var g: Dictionary = data.general_by_id.get(gid, {})
	var why := RulesRecruit.check(g, ch, data.recruit_cfg)
	if not why.is_empty():
		return _msg(id, "%s：%s" % [g["name"], why])
	rec["cands"] = []
	if String(g["type"]) == "wu":
		_arena_start(e, g)
	else:
		_quiz_start(e, g)


# ---- 武將: PK 擂台 ----
# 臨時怪喺玩家隔籬出現，只會打挑戰者；打到 0 = 制服 (唔會死)，玩家 HP 到 0 = 輸 (唔死，留 1 HP)
func _arena_start(e: Dictionary, g: Dictionary) -> void:
	var id := int(e["id"])
	var d := data.mob_def(RulesRecruit.ARENA_DEF_BASE + int(g["id"]))
	var pos := _free_near(int(e["x"]), int(e["y"]))
	var m := _new_ent(String(g["name"]), "mob", pos)
	m["face"] = 0
	m["hp"] = int(d["hp"])
	m["max_hp"] = int(d["hp"])
	m["level"] = int(d["level"])
	m["mob"] = {"def": int(d["id"]), "home_x": pos.x, "home_y": pos.y, "state": "chase", "target": id,
		"next_atk": tick + int(d["atkInterval"]), "zone": map_id_at(pos.x, pos.y), "arena": int(g["id"]), "owner": id}
	e["atk_target"] = int(m["id"])
	_rec(e["ch"])["pending"] = {"gid": int(g["id"]), "kind": "arena", "mob": int(m["id"])}
	_emit({"k": "arena_start", "dst": id, "gid": int(g["id"]), "name": String(g["name"]), "mob": int(m["id"])})
	_msg(id, "%s：「想我跟你？先贏咗我再講！」擂台 PK 開始" % g["name"])


# (x,y) 附近搵一格空位 (一圈圈向外)
func _free_near(x: int, y: int) -> Vector2i:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and is_free(x + dx, y + dy):
					return Vector2i(x + dx, y + dy)
	return Vector2i(x, y)


# 擂台結束: 收走臨時怪 + 結算
func _arena_end(pe: Dictionary, win: bool) -> void:
	var rec := _rec(pe["ch"])
	var pend: Dictionary = rec.get("pending", {})
	if pend.is_empty() or String(pend.get("kind", "")) != "arena":
		return
	var mid := int(pend["mob"])
	ents.erase(mid)
	for o in ents.values():
		if int(o["atk_target"]) == mid:
			o["atk_target"] = 0
	rec.erase("pending")
	var g: Dictionary = data.general_by_id[int(pend["gid"])]
	_emit({"k": "arena_end", "dst": int(pe["id"]), "gid": int(g["id"]), "win": win})
	if win:
		_msg(int(pe["id"]), "你制服咗%s！" % g["name"])
		_recruit_success(pe, g)
	else:
		_recruit_fail(pe, g, "擂台輸咗，%s拍拍屁股走人" % g["name"])


# 擂台只可以挑戰者打；武將 HP 到 0 = 制服；玩家 HP 到 0 = 輸 (留 1 HP，唔算死)
func damage(t: Dictionary, dmg: int, by: Dictionary) -> void:
	var tm: Dictionary = t.get("mob", {})
	if tm.has("arena"):
		if int(by.get("id", 0)) != int(tm["owner"]):
			return
		if int(t["hp"]) - dmg <= 0:
			t["hp"] = 0
			_arena_end(ent(int(tm["owner"])), true)
			return
	var bm: Dictionary = by.get("mob", {})
	if bm.has("arena") and t.has("ch") and int(t["hp"]) - dmg <= 0:
		t["hp"] = 1
		t["ch"]["hp"] = 1
		_arena_end(t, false)
		return
	super(t, dmg, by)


# 每 tick: 擂台走甩 (距離 > maxDist) / 武將脫戰 = 輸
func _recruit_tick() -> void:
	var pe := ent(int(state["player_id"]))
	if pe.is_empty():
		return
	var pend: Dictionary = pe["ch"].get("recruit", {}).get("pending", {})
	if pend.is_empty() or String(pend.get("kind", "")) != "arena":
		return
	var m := ent(int(pend["mob"]))
	var far := m.is_empty() or maxi(absi(int(m["x"]) - int(pe["x"])), absi(int(m["y"]) - int(pe["y"]))) \
		> int(data.recruit_cfg["arena"]["maxDist"])
	if int(pe["hp"]) <= 0 or far or String(m.get("mob", {}).get("state", "")) != "chase":
		_arena_end(pe, false)


# ---- 文官: 三國問答 ----
func _quiz_start(e: Dictionary, g: Dictionary) -> void:
	var n := mini(int(data.recruit_cfg["quizN"]), data.quiz_generals.size())
	var idx: Array = range(data.quiz_generals.size())
	for i in n:                                       # Fisher-Yates 抽頭 n 題
		var j := i + rng.below(idx.size() - i)
		var tmp = idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	_rec(e["ch"])["pending"] = {"gid": int(g["id"]), "kind": "quiz", "qs": idx.slice(0, n), "i": 0, "ok": 0}
	_msg(int(e["id"]), "%s：「%d 題之中答啱 %d 題，我就跟你。」" % [g["name"], n, int(data.recruit_cfg["quizPass"])])
	_emit_quiz(e, {})


# 問答進度 → UI: q/opts = 下一題 (冇 = 完)；last = 上一題結果
func _emit_quiz(e: Dictionary, last: Dictionary) -> void:
	var ev := {"k": "recruit_quiz", "dst": int(e["id"]), "last": last}
	ev.merge(recruit_quiz_view(e["ch"]))
	_emit(ev)


# 而家嗰題 (UI 用)；冇問答 = {}
func recruit_quiz_view(ch: Dictionary = {}) -> Dictionary:
	if ch.is_empty():
		ch = player_ch()
	var pend: Dictionary = ch.get("recruit", {}).get("pending", {})
	if pend.is_empty() or String(pend.get("kind", "")) != "quiz":
		return {}
	var q: Dictionary = data.quiz_generals[int(pend["qs"][int(pend["i"])])]
	return {"gid": int(pend["gid"]), "name": data.general_by_id[int(pend["gid"])]["name"], "i": int(pend["i"]),
		"n": (pend["qs"] as Array).size(), "ok": int(pend["ok"]), "q": String(q["q"]), "opts": q["opts"]}


# 答題: 錯多過容許 (n - pass) 即刻失敗；答完 n 題夠 pass 就登用
func cmd_recruit_answer(id: int, choice: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var rec := _rec(e["ch"])
	var pend: Dictionary = rec.get("pending", {})
	if pend.is_empty() or String(pend.get("kind", "")) != "quiz":
		return
	var q: Dictionary = data.quiz_generals[int(pend["qs"][int(pend["i"])])]
	var right := choice == int(q["a"])
	pend["i"] = int(pend["i"]) + 1
	if right:
		pend["ok"] = int(pend["ok"]) + 1
	var n := (pend["qs"] as Array).size()
	var wrong := int(pend["i"]) - int(pend["ok"])
	var g: Dictionary = data.general_by_id[int(pend["gid"])]
	var last := {"right": right, "answer": int(q["a"]), "i": int(pend["i"]), "ok": int(pend["ok"])}
	var done := wrong > n - int(data.recruit_cfg["quizPass"]) or int(pend["i"]) >= n
	if done:
		rec.erase("pending")
	_emit_quiz(e, last)
	if not done:
		return
	if RulesRecruit.quiz_pass(int(pend["ok"]), data.recruit_cfg):
		_msg(id, "%s：「果然高明！」(答啱 %d/%d)" % [g["name"], int(pend["ok"]), n])
		_recruit_success(e, g)
	else:
		_recruit_fail(e, g, "%s搖頭：「學問未夠，恕難從命。」(答啱 %d/%d)" % [g["name"], int(pend["ok"]), int(pend["i"])])


# 放棄考驗 = 失敗 (人才走人)
func cmd_recruit_cancel(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var pend: Dictionary = _rec(e["ch"]).get("pending", {})
	if pend.is_empty():
		return
	if String(pend["kind"]) == "arena":
		_arena_end(e, false)
	else:
		_rec(e["ch"]).erase("pending")
		_recruit_fail(e, data.general_by_id[int(pend["gid"])], "你放棄咗考驗")


# 失敗【原】: 人才走人 (呢個月唔再出現)；調查已經用咗
func _recruit_fail(pe: Dictionary, g: Dictionary, why: String) -> void:
	_gen_state(int(g["id"]))["awayMonth"] = _month()
	_emit({"k": "recruit_result", "dst": int(pe["id"]), "gid": int(g["id"]), "ok": false})
	_msg(int(pe["id"]), why)


# 成功: 封鎖本月調查 + 生成同伴
func _recruit_success(pe: Dictionary, g: Dictionary) -> void:
	var rec := _rec(pe["ch"])
	rec["lockMonth"] = _month()
	var c := _spawn_companion(pe, g)
	rec["comp"] = int(c["id"])
	_gen_state(int(g["id"]))["serving"] = true
	_emit({"k": "recruit_result", "dst": int(pe["id"]), "gid": int(g["id"]), "ok": true, "comp": int(c["id"])})
	_msg(int(pe["id"]), "登用成功！%s會跟你 %d 日" % [g["name"], int(data.recruit_cfg["serveDays"])])


# ================= 同伴 (spec 09 §3.3) =================
# 同伴 = kind "gen" 單位，有 ch (用現成戰鬥/尋路/過圖)；gen = {gid, owner, since, until, loyalty, order}
func _spawn_companion(pe: Dictionary, g: Dictionary) -> Dictionary:
	var c := _new_ent(String(g["name"]), "gen", _free_near(int(pe["x"]), int(pe["y"])))
	var ch := RulesStats.create_character(data, String(g["name"]).substr(0, 8), "yishi")
	ch["level"] = int(g["lv"])
	ch["attrs"] = RulesRecruit.companion_attrs(data.classes["yishi"], g, data.recruit_cfg)
	ch["ideology"] = String(g["ideo"])
	ch["bag"] = []
	ch["gold"] = 0
	ch["equip"]["spellbooks"] = [0, 0, 0]
	ch["equip"]["jewels"] = [0, 0]
	_ensure_equip(ch)
	_full_heal(ch)
	c["ch"] = ch
	var day := int(_clock()["day"])
	c["gen"] = {"gid": int(g["id"]), "owner": int(pe["id"]), "since": day,
		"until": RulesRecruit.until_day(day, data.recruit_cfg),
		"loyalty": RulesRecruit.loyalty_init(String(pe["ch"].get("ideology", "")), String(g["ideo"]), data.recruit_cfg),
		"order": "assist"}
	_sync_stats(c)
	return c


# 同伴視圖 (UI): {} = 冇同伴
func companion_view() -> Dictionary:
	var c := ent(int(player_ch().get("recruit", {}).get("comp", 0)))
	if c.is_empty() or not c.has("gen"):
		return {}
	var gn: Dictionary = c["gen"]
	var g: Dictionary = data.general_by_id[int(gn["gid"])]
	return {"id": int(c["id"]), "gid": int(gn["gid"]), "name": c["name"], "lv": int(c["level"]), "hp": int(c["hp"]),
		"maxHp": int(c["max_hp"]), "loyalty": int(gn["loyalty"]), "order": String(gn["order"]),
		"daysLeft": maxi(0, int(gn["until"]) - int(_clock()["day"])), "type": g["type"], "sub": g["sub"], "face": int(c["face"])}
