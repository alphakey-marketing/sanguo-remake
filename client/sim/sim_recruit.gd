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
	_office_on_talk(e, "g:%d" % gid, int(g["x"]), int(g["y"]))
	var pool: Array = g.get("idle", [])
	var text := String(pool[rng.below(pool.size())]) if not pool.is_empty() else "……"
	if not _sip_thirst(e):          # 口渴 (Step 14): 只講模板客套話
		text = THIRSTY_LINE
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


# pass = 要用嘅憑證 ("medal"/"order"/"")，UI 顯示「持令」
func _gen_view(g: Dictionary, ch: Dictionary = {}) -> Dictionary:
	var pn := _pass_need(ch, g) if not ch.is_empty() else ""
	return {"id": int(g["id"]), "name": g["name"], "lv": int(g["lv"]), "type": g["type"], "sub": g["sub"],
		"ideo": g["ideo"], "t1": int(g["tier"]) == 1, "pass": pn if pn != "x" else "",
		"skill": String(_gskill_def(RulesGeneral.skill_for(g, data.gen_skills, data.gen_skill_override, data.gen_draw_pool, data.gen_skill_pin)).get("name", ""))}


# ================= 將軍令 / 御賜金牌 (Step 15, spec 09 §3.1) =================
func _has_medal(ch: Dictionary) -> bool:
	return RulesShop.count_item(ch["bag"], int(data.gen2_cfg["goldMedal"])) > 0


func _has_order(ch: Dictionary, g: Dictionary) -> bool:
	var it := int(data.general_order_item.get(String(g["name"]), 0))
	return it != 0 and order_count(ch, it) > 0          # 背包 + 收集冊 (Step 16)


# 登用呢位要唔要用憑證: "" = 唔使 (正常條件過)；"medal"/"order" = 要用；"x" = 用都唔得
# 將軍令 = 無視理念/等級/頭銜；金牌 = 再加無視時辰 (Tier1 時辰外都得)
func _pass_need(ch: Dictionary, g: Dictionary) -> String:
	var ok := RulesRecruit.check(g, ch, data.recruit_cfg).is_empty()
	var hidden := int(g["tier"]) == 1 and not general_visible(g)
	if ok and not hidden:
		return ""
	var pk := RulesGeneral.pass_kind(not hidden and _has_order(ch, g), _has_medal(ch))
	return pk if pk != "" else "x"


# 登用唔得嘅原因 ("" = 得)
func _recruit_why(ch: Dictionary, g: Dictionary) -> String:
	if _pass_need(ch, g) != "x":
		return ""
	var why := RulesRecruit.check(g, ch, data.recruit_cfg)
	return why if why != "" else "而家搵唔到呢位人才"


# 背包/收集冊有將軍令嘅人才: 一定入候選 (放最前)；同名揀 Tier1 (要見到或者有金牌)，否則 Tier0 最細 id
func _order_cands(ch: Dictionary, kind: String, gone: Dictionary, cands: Array) -> Array:
	var names := {}
	for g in cands:
		names[String(g["name"])] = true
	var front: Array = []
	var held: Array = []                          # 背包 + 收集冊 (Step 16) 嘅將軍令
	for b in ch["bag"]:
		if int(b["n"]) > 0:
			held.append(int(b["id"]))
	for k in ch.get("orderBook", {}):
		held.append(int(k))
	for it in held:
		var gname := RulesGeneral.order_general_name(String(data.names.get(it, "")), String(data.gen2_cfg["orderSuffix"]), data.gen2_cfg.get("orderAlias", {}))
		if gname == "" or names.has(gname):
			continue
		var g := _order_general(gname)
		if g.is_empty() or String(g["type"]) != kind or gone.has(int(g["id"])) or _pass_need(ch, g) == "x":
			continue
		names[gname] = true
		front.append(g)
	return front + cands


func _order_general(gname: String) -> Dictionary:
	var best := {}
	for g in data.generals:
		if String(g["name"]) != gname or int(g["tier"]) < 0:
			continue
		if int(g["tier"]) == 1:
			return g
		if best.is_empty():
			best = g
	return best


# 登用成功: 用咗嘅憑證消失【原】(用完即消)
func _consume_pass(pe: Dictionary, g: Dictionary) -> void:
	var rec := _rec(pe["ch"])
	var ps: Dictionary = rec.get("pass", {})
	rec.erase("pass")
	if ps.is_empty() or int(ps["gid"]) != int(g["id"]):
		return
	var it := int(data.gen2_cfg["goldMedal"]) if String(ps["kind"]) == "medal" else int(data.general_order_item.get(String(g["name"]), 0))
	if it != 0 and (_order_consume(pe["ch"], it) if String(ps["kind"]) == "order" else RulesShop.remove_item(pe["ch"]["bag"], it, 1)):
		_msg(int(pe["id"]), "「%s」用咗" % data.names.get(it, str(it)))


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
	var medal := _has_medal(ch)
	var vis := {}
	for g in data.generals_t1:        # 御賜金牌【原】: 子午時 (時辰外) 嘅人才都搵到
		if String(g["map"]) == String(md["id"]) and (general_visible(g) or (medal and not _general_away(int(g["id"])))):
			vis[int(g["id"])] = true
	var gone := _gone_ids()
	var cands := RulesRecruit.candidates(data.generals, ch, kind, day, vis, gone, data.recruit_cfg, medal)
	cands = _order_cands(ch, kind, gone, cands)
	rec["kind"] = kind
	rec["cands"] = []
	var views: Array = []
	for g in cands:
		rec["cands"].append(int(g["id"]))
		views.append(_gen_view(g, ch))
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
	var why := _recruit_why(ch, g)
	if not why.is_empty():
		return _msg(id, "%s：%s" % [g["name"], why])
	var pn := _pass_need(ch, g)
	if pn != "":
		rec["pass"] = {"gid": gid, "kind": pn}
		_msg(id, "你出示「%s」，%s無話可說" % [data.names.get(int(data.gen2_cfg["goldMedal"]) if pn == "medal"
			else int(data.general_order_item.get(String(g["name"]), 0)), ""), g["name"]])
	else:
		rec.erase("pass")
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


# 擂台結束: 收走臨時怪 + 結算
func _arena_end(pe: Dictionary, win: bool) -> void:
	var rec := _rec(pe["ch"])
	var pend: Dictionary = rec.get("pending", {})
	if pend.is_empty() or String(pend.get("kind", "")) != "arena":
		return
	var mid := int(pend["mob"])
	_remove_ent(mid)
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
	_down_bailout()                     # 同伴倒下超時未救 → 返客棧 (S02c)
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
	_rec(pe["ch"]).erase("pass")          # 失敗唔消耗將軍令/金牌【自訂】
	_gen_state(int(g["id"]))["awayMonth"] = _month()
	_emit({"k": "recruit_result", "dst": int(pe["id"]), "gid": int(g["id"]), "ok": false})
	_msg(int(pe["id"]), why)


# 成功: 封鎖本月調查 + 生成同伴
func _recruit_success(pe: Dictionary, g: Dictionary) -> void:
	var rec := _rec(pe["ch"])
	rec["lockMonth"] = _month()
	_consume_pass(pe, g)
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
	ch["genSkill"] = RulesGeneral.skill_for(g, data.gen_skills, data.gen_skill_override, data.gen_draw_pool, data.gen_skill_pin)   # 特技 (Step 15; S07d 固定池)
	ch["genTreasures"] = []                                                              # 寶物 2 格
	_ensure_equip(ch)
	_full_heal(ch)
	c["ch"] = ch
	var day := int(_clock()["day"])
	c["gen"] = {"gid": int(g["id"]), "owner": int(pe["id"]), "since": day,
		"until": RulesRecruit.until_day(day, data.recruit_cfg),
		"loyalty": RulesRecruit.loyalty_init(String(pe["ch"].get("ideology", "")), String(g["ideo"]), data.recruit_cfg),
		"order": "assist", "skillCd": 0}
	_sync_stats(c)
	return c


# 同伴視圖 (UI): {} = 冇同伴
func companion_view() -> Dictionary:
	var c := ent(int(player_ch().get("recruit", {}).get("comp", 0)))
	if c.is_empty() or not c.has("gen"):
		return {}
	var gn: Dictionary = c["gen"]
	var g: Dictionary = data.general_by_id[int(gn["gid"])]
	var ch: Dictionary = c["ch"]
	var sk := _gskill_def(int(ch.get("genSkill", 0)))
	var trs: Array = []
	for t in ch.get("genTreasures", []):
		trs.append({"item": int(t["item"]), "name": data.names.get(int(t["item"]), ""), "value": int(t["value"]),
			"type": String(data.gen2_cfg["treasure"][String(t["type"])]["name"])})
	return {"id": int(c["id"]), "gid": int(gn["gid"]), "name": c["name"], "lv": int(c["level"]), "hp": int(c["hp"]),
		"maxHp": int(c["max_hp"]), "exp": int(ch["exp"]), "needExp": RulesStats.exp_to_next(int(c["level"])),
		"loyalty": int(gn["loyalty"]), "order": String(gn["order"]),
		"daysLeft": maxi(0, int(gn["until"]) - int(_clock()["day"])), "type": g["type"], "sub": g["sub"], "face": int(c["face"]),
		"mp": int(ch["mp"]), "maxMp": _eff_max_mp(ch), "sp": int(ch["sp"]), "maxSp": _eff_max_sp(ch),
		"skill": String(sk.get("name", "")), "skillDesc": String(sk.get("desc", "")),
		"spell": String(_comp_spell(c)["name"]), "treasures": trs,
		"stats": RulesGeneral.treasure_bonus(ch.get("genTreasures", []), data.gen2_cfg)["stats"]}


# 登用面板視圖 (UI): 城內? / 調查封鎖原因 / 上次候選 / 考驗中 / 同伴
func recruit_view() -> Dictionary:
	var pe := ent(int(state["player_id"]))
	if pe.is_empty():
		return {}
	var rec: Dictionary = pe["ch"].get("recruit", {})
	var in_city := String(map_at(int(pe["x"]), int(pe["y"])).get("kind", "")) == "city"
	var block := RulesRecruit.survey_block(rec, int(_clock()["day"]), _month())
	if not (rec.get("pending", {}) as Dictionary).is_empty():
		block = "考驗緊人才"
	elif int(rec.get("comp", 0)) != 0:
		block = "已經有人才跟緊你"
	elif block.is_empty() and not in_city:
		block = "要喺城池街道先可以調查"
	var cands: Array = []
	for gid in rec.get("cands", []):
		var g: Dictionary = data.general_by_id.get(int(gid), {})
		if not g.is_empty():
			var v := _gen_view(g, pe["ch"])
			v["why"] = _recruit_why(pe["ch"], g)
			cands.append(v)
	var pend: Dictionary = rec.get("pending", {})
	return {"inCity": in_city, "block": block, "kind": String(rec.get("kind", "")), "cands": cands,
		"pending": String(pend.get("kind", "")), "pendingName": String(data.general_by_id.get(int(pend.get("gid", 0)), {}).get("name", "")),
		"quiz": recruit_quiz_view(pe["ch"]), "comp": companion_view()}


func _companion_of(owner: Dictionary) -> Dictionary:
	if not owner.has("ch"):
		return {}
	var c := ent(int(owner["ch"].get("recruit", {}).get("comp", 0)))
	return c if c.has("gen") else {}


func _cheb(a: Dictionary, b: Dictionary) -> int:
	return maxi(absi(int(a["x"]) - int(b["x"])), absi(int(a["y"]) - int(b["y"])))


# 同伴每 tick (之後 _think_player 負責追/打): 回血 → 跨圖跟主公 → 按指令揀目標 → 冇目標就跟隨
func _think_companion(c: Dictionary) -> void:
	var gn: Dictionary = c["gen"]
	if bool(gn.get("office", false)):        # 官令護衛/救援 NPC (S06a)：走另一套簡化 tick
		_think_office_npc(c)
		return
	var o := ent(int(gn["owner"]))
	if o.is_empty() or int(c["hp"]) <= 0:
		return
	var cfg: Dictionary = data.recruit_cfg["companion"]
	var ch: Dictionary = c["ch"]
	if int(c["atk_target"]) == 0 and tick % int(cfg["regenTicks"]) == 0 and int(ch["hp"]) < int(c["max_hp"]):
		ch["hp"] = mini(int(c["max_hp"]), int(ch["hp"]) + maxi(1, int(ceil(int(c["max_hp"]) * float(cfg["regenPct"])))))
		_sync_stats(c)
	_skill_regen(c, o)
	var omap := map_id_at(int(o["x"]), int(o["y"]))
	if map_id_at(int(c["x"]), int(c["y"])) != omap:
		c["atk_target"] = 0
		if not _route_to_map(c, omap):         # 行唔到 (冇路) → 直接跳去主公隔籬
			var p := _free_near(int(o["x"]), int(o["y"]))
			_put_ent(c, p.x, p.y)
		return
	var d := _cheb(c, o)
	var order := String(gn["order"])
	var tgt := ent(int(c["atk_target"]))
	if d > int(cfg["leashOwner"]) or order == "stop" or order == "follow" or not _hittable(tgt):
		c["atk_target"] = 0
	var skill_order := order == "ult" or order == "spell"     # 絕招/術法: 幫主公打，冇就自己搵 (Step 15)
	if order == "assist" or skill_order:
		var ot := ent(int(o["atk_target"]))
		if _hittable(ot):
			c["atk_target"] = int(ot["id"])
		elif int(c["atk_target"]) == 0:
			c["atk_target"] = _attacker_of(o)      # 主公被打就幫手
	if (order == "active" or skill_order) and int(c["atk_target"]) == 0 and d <= int(cfg["leashOwner"]):
		c["atk_target"] = _hunt_target(c, int(cfg["huntRange"]))
		if int(c["atk_target"]) == 0:
			c["atk_target"] = _attacker_of(o)
	if int(c["atk_target"]) != 0:
		if skill_order:
			_comp_skill(c, ent(int(c["atk_target"])))
		return
	var want := int(cfg["farFollow"]) if order == "follow" else int(cfg["follow"])
	if d <= want:
		c["tx"] = c["x"]
		c["ty"] = c["y"]
		c.erase("path")
	elif maxi(absi(int(c["tx"]) - int(o["x"])), absi(int(c["ty"]) - int(o["y"]))) > want \
			or (int(c["tx"]) == int(c["x"]) and int(c["ty"]) == int(c["y"])):
		_set_dest(c, int(o["x"]), int(o["y"]), CHASE_CAP)


func _put_ent(e: Dictionary, x: int, y: int) -> void:
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	e.erase("path")


# 同伴可以打嘅怪: 生存 + 唔係擂台 + 唔喺安全區
func _hittable(m: Dictionary) -> bool:
	return not m.is_empty() and m["kind"] == "mob" and int(m["hp"]) > 0 and not m["mob"].has("arena") \
		and not is_safe(int(m["x"]), int(m["y"]))


# 追緊 owner 嘅最近怪 (0 = 冇)
func _attacker_of(o: Dictionary) -> int:
	var best := 0
	var best_d := 1 << 30
	for m in ents.values():
		if m["kind"] != "mob" or String(m["mob"]["state"]) != "chase" or int(m["mob"]["target"]) != int(o["id"]) or not _hittable(m):
			continue
		var d := _cheb(m, o)
		if d < best_d:
			best = int(m["id"])
			best_d = d
	return best


# 主動攻擊: 同一張圖、r 格內最近嘅怪
func _hunt_target(c: Dictionary, r: int) -> int:
	var my_map := map_id_at(int(c["x"]), int(c["y"]))
	var best := 0
	var best_d := r + 1
	for m in ents.values():
		if not _hittable(m) or (m["kind"] == "mob" and String(m["mob"]["state"]) == "flee"):
			continue
		var d := _cheb(m, c)
		if d < best_d and map_id_at(int(m["x"]), int(m["y"])) == my_map:
			best = int(m["id"])
			best_d = d
	return best


# 戰鬥指令 (spec 09 §3.3): active 主動 / assist 協助 / stop 停止 / follow 遠距跟隨
func cmd_companion_order(id: int, order: String) -> void:
	var c := _companion_of(ent(id))
	if c.is_empty() or not RulesRecruit.ORDERS.has(order):
		return
	c["gen"]["order"] = order
	c["atk_target"] = 0
	_emit({"k": "companion", "dst": id, "comp": companion_view()})
	_msg(id, "%s：遵命！(%s)" % [c["name"], RulesRecruit.ORDER_NAMES[order]])


# 送補品: 主公背包嘅回復品用喺同伴身上，忠誠 +gift (要行近)
func cmd_companion_gift(id: int, item: int) -> void:
	var o := ent(id)
	var c := _companion_of(o)
	if c.is_empty() or int(o["hp"]) <= 0:
		return
	if not _near(o, int(c["x"]), int(c["y"])):
		return _msg(id, "要行近%s先得" % c["name"])
	var ch: Dictionary = c["ch"]
	var heal: Dictionary = data.heals.get(item, {})
	var tonic: Dictionary = data.gen2_cfg["tonics"].get(str(item), {})     # 武將補品 (藥膳師, Step 15): 按上限 %
	if not tonic.is_empty():
		heal = {"hp": MathX.js_round(_eff_max_hp(ch) * float(tonic.get("hpPct", 0.0))),
			"mp": MathX.js_round(_eff_max_mp(ch) * float(tonic.get("mpPct", 0.0))),
			"sp": MathX.js_round(_eff_max_sp(ch) * float(tonic.get("spPct", 0.0)))}
	if heal.is_empty():
		return _msg(id, "呢件唔係補品")
	if not RulesShop.remove_item(o["ch"]["bag"], item, 1):
		return _msg(id, "背包冇呢件")
	ch["hp"] = mini(_eff_max_hp(ch), int(ch["hp"]) + int(heal.get("hp", 0)))
	ch["mp"] = mini(_eff_max_mp(ch), int(ch["mp"]) + int(heal.get("mp", 0)))
	ch["sp"] = mini(_eff_max_sp(ch), int(ch["sp"]) + int(heal.get("sp", 0)))
	_sync_stats(c)
	_msg(id, "%s收下%s" % [c["name"], data.names.get(item, str(item))])
	_loyalty_change(c, int(data.recruit_cfg["loyalty"]["gift"]) + int(_comp_eff(c).get("giftAdd", 0)))


# 贈與寶物【原】: 武將寶物 2 格；同類高取代低 (低嘅消失)；放咗攞唔返，登用完跟武將走
func cmd_companion_treasure(id: int, item: int) -> void:
	var o := ent(id)
	var c := _companion_of(o)
	if c.is_empty() or int(o["hp"]) <= 0:
		return
	if not _near(o, int(c["x"]), int(c["y"])):
		return _msg(id, "要行近%s先得" % c["name"])
	var t := RulesGeneral.treasure_of(int(data.cats.get(item, 0)), data.info.get(item, {}).get("effects", []), data.gen2_cfg)
	if t.is_empty():
		return _msg(id, "呢件唔係武將寶物")
	if RulesShop.count_item(o["ch"]["bag"], item) <= 0:
		return _msg(id, "背包冇呢件")
	var ch: Dictionary = c["ch"]
	var r := RulesGeneral.treasure_put(ch.get("genTreasures", []), item, t, int(data.gen2_cfg["treasureSlots"]))
	var nm := String(data.names.get(item, str(item)))
	if String(r["res"]) == "full":
		return _msg(id, "%s嘅寶物格滿咗 (最多 %d 種)" % [c["name"], int(data.gen2_cfg["treasureSlots"])])
	RulesShop.remove_item(o["ch"]["bag"], item, 1)
	ch["genTreasures"] = r["slots"]
	_sync_stats(c)
	match String(r["res"]):
		"add":
			_msg(id, "%s收下「%s」" % [c["name"], nm])
		"replace":
			_msg(id, "「%s」取代咗「%s」(舊寶物消失)" % [nm, data.names.get(int(r["old"]), "")])
		"lost":
			_msg(id, "同類寶物數值更高，「%s」消失咗" % nm)
	_emit({"k": "companion", "dst": id, "comp": companion_view()})
	_loyalty_change(c, int(data.recruit_cfg["loyalty"]["gift"]) + int(_comp_eff(c).get("giftAdd", 0)))


# 主動解散 (唔算得罪: 返城，下次仲可以再登)
func cmd_companion_dismiss(id: int) -> void:
	var c := _companion_of(ent(id))
	if not c.is_empty():
		_companion_leave(c, "你叫佢返去", false)


# ===== S09c-b 主動特技 (spec 09 §3.4): 21 無限遁地 / 32 挑釁 / 38 急救 =====
# 主公向同伴落指令 cmd_companion_skill(id, kind)；同伴要有對應主動技 + 冷卻完。
# 22 職業特技 = proximity 被動 (見 _companion_class_skill_mul)，唔經呢個指令。
func cmd_companion_skill(id: int, kind: String) -> void:
	var o := ent(id)
	var c := _companion_of(o)
	if c.is_empty() or int(c["hp"]) <= 0 or o.is_empty() or int(o["hp"]) <= 0:
		return
	var eff := _comp_eff(c)
	var why := RulesGeneral.active_block(eff, c["gen"].get("activeCd", {}), tick)
	if why != "" or RulesGeneral.active_kind(eff) != kind:
		return _msg(id, why if why != "" else "同伴冇呢招主動特技")
	match kind:
		"burrow":
			_comp_burrow(id, o, c, eff)
		"taunt":
			_comp_taunt(id, c, eff)
		"heal":
			_comp_heal(id, o, c, eff)
		_:
			return _msg(id, "同伴冇呢招主動特技")
	var cd := RulesGeneral.active_cd(eff)
	if cd > 0:
		var acd: Dictionary = c["gen"].get("activeCd", {})
		acd[kind] = tick + cd
		c["gen"]["activeCd"] = acd


# 21 無限遁地: 主公 + 同伴即時傳送去最近城池中心 (唔使車費、無限次)。
# 目標城池 = map 圖 BFS 最近嘅 kind:city 地圖；落腳點 = 地圖內最接近中心嘅行得格。
func _comp_burrow(id: int, o: Dictionary, c: Dictionary, _eff: Dictionary) -> void:
	var cur := map_id_at(int(o["x"]), int(o["y"]))
	var md := _nearest_city_map(cur)
	if md.is_empty():
		return _msg(id, "附近冇城池可以遁地返去")
	var p := _city_anchor(md)
	_put_ent(o, p.x, p.y)
	o["atk_target"] = 0
	o.erase("goto")
	if o.has("casting"):
		o.erase("casting")
		_emit({"k": "cast_interrupted", "dst": int(o["id"]), "reason": "travel"})
	if int(c["hp"]) > 0:
		var cp := _free_near(p.x, p.y)
		_put_ent(c, cp.x, cp.y)
		c["atk_target"] = 0
	_emit({"k": "travel", "dst": int(o["id"]), "to": String(md["name"]), "x": o["x"], "y": o["y"],
		"map": map_id_at(int(o["x"]), int(o["y"])), "station": false, "burrow": true})
	_msg(id, "%s遁地！主公一齊返到%s" % [c["name"], String(md["name"])])


# 最近城池地圖 (map 圖 BFS 最短 hop)；去唔到 = {}
func _nearest_city_map(from_map: String) -> Dictionary:
	var best: Dictionary = {}
	var best_hops := 1 << 30
	for md in data.maps:
		if String(md.get("kind", "")) != "city":
			continue
		var h := map_hops(from_map, String(md["id"]))
		if h < 0:
			continue
		if h < best_hops:
			best_hops = h
			best = md
	return best


# 城池落腳點: 地圖範圍內最接近中心嘅行得格 (掃 map rect)
func _city_anchor(md: Dictionary) -> Vector2i:
	var ox := int(md["ox"])
	var oy := int(md["oy"])
	var cx := ox + int(md["w"]) / 2
	var cy := oy + int(md["h"]) / 2
	var best := Vector2i(ox, oy)
	var best_d := 1 << 30
	for y in range(oy, oy + int(md["h"])):
		for x in range(ox, ox + int(md["w"])):
			if not is_free(x, y):
				continue
			var d := absi(x - cx) + absi(y - cy)
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best


# 32 挑釁: 同伴附近 tauntRange 格內嘅可打怪 → 仇恨轉去同伴 (chase target = 同伴)
func _comp_taunt(id: int, c: Dictionary, eff: Dictionary) -> void:
	var r := RulesGeneral.taunt_range(eff)
	var n := 0
	var cid := int(c["id"])
	var cmap := map_id_at(int(c["x"]), int(c["y"]))
	for m in ents.values():
		if not _hittable(m) or _cheb(m, c) > r or map_id_at(int(m["x"]), int(m["y"])) != cmap:
			continue
		m["mob"]["state"] = "chase"
		m["mob"]["target"] = cid
		n += 1
	_emit({"k": "comp_taunt", "dst": id, "src": cid, "count": n, "range": r})
	_msg(id, "%s大吼一聲，%d 隻怪畀佢引埋去！" % [c["name"], n])


# 38 急救: 同伴喺主公附近 → 即回主公 HP (上限 healPct)，入冷卻
func _comp_heal(id: int, o: Dictionary, c: Dictionary, eff: Dictionary) -> void:
	if not _aura_near(c, o):
		return _msg(id, "要行近同伴先急救到")
	var och: Dictionary = o["ch"]
	if int(och["hp"]) >= _eff_max_hp(och):
		return _msg(id, "主公滿血，唔使急救")
	var amt := RulesGeneral.heal_amount(_eff_max_hp(och), eff)
	och["hp"] = mini(_eff_max_hp(och), int(och["hp"]) + amt)
	_sync_stats(o)
	_emit({"k": "comp_heal", "dst": id, "src": int(c["id"]), "hp": amt})
	_msg(id, "%s施展急救，主公回復 %d HP" % [c["name"], amt])


# 22 職業特技 (override S09c-b hook): 同伴生存 + 同圖 + auraRange 內 → 主公職業特技冷卻/消耗乘數
func _companion_class_skill_mul(e: Dictionary) -> Dictionary:
	var c := ent(int(e.get("ch", {}).get("recruit", {}).get("comp", 0)))
	if c.is_empty() or not c.has("gen") or int(c["hp"]) <= 0:
		return {"cd": 1.0, "cost": 1.0}
	if not _aura_near(c, e):
		return {"cd": 1.0, "cost": 1.0}
	return RulesGeneral.class_skill_mul(_comp_eff(c))


# 忠誠變動 → 0 即刻走 (spec 09 §4)；<leave 喺子時結算
func _loyalty_change(c: Dictionary, delta: int) -> void:
	delta = RulesGeneral.loyalty_delta(delta, _comp_eff(c))     # 忠義: 跌減半 (Step 15)
	if delta == 0:
		return
	var gn: Dictionary = c["gen"]
	gn["loyalty"] = RulesRecruit.loyalty_add(int(gn["loyalty"]), delta)
	var owner := int(gn["owner"])
	_emit({"k": "companion", "dst": owner, "comp": companion_view()})
	_msg(owner, "%s忠誠 %+d → %d" % [c["name"], delta, int(gn["loyalty"])])
	if RulesRecruit.loyalty_verdict(int(gn["loyalty"]), data.recruit_cfg) == "leave_now":
		_companion_leave(c, "忠誠盡失，拂袖而去", true)


# 同伴離開: sulk = 唔開心走 (呢個月唔返城)；否則即刻返城
func _companion_leave(c: Dictionary, why: String, sulk: bool) -> void:
	var gn: Dictionary = c["gen"]
	var gid := int(gn["gid"])
	var st := _gen_state(gid)
	st["serving"] = false
	if sulk:
		st["awayMonth"] = _month()
	var owner := int(gn["owner"])
	var o := ent(owner)
	if not o.is_empty():
		_rec(o["ch"]).erase("comp")
	var cid := int(c["id"])
	_remove_ent(cid)
	_emit({"k": "companion_leave", "dst": owner, "gid": gid, "name": String(c["name"]), "reason": why})
	_msg(owner, "%s離開咗：%s" % [c["name"], why])


# 子時 (新一日): 到期【原】第 30 日子時 0 刻離開；忠誠 < leave 離開
func _recruit_daily(day: int) -> void:
	for id in ents.keys():
		var c: Dictionary = ents.get(id, {})
		if not c.has("gen"):
			continue
		var gn: Dictionary = c["gen"]
		if day >= int(gn["until"]):
			_companion_leave(c, "登用期滿", false)
		elif RulesRecruit.loyalty_verdict(int(gn["loyalty"]), data.recruit_cfg) != "stay":
			_companion_leave(c, "忠誠太低", true)


# S09b (spec 09 §4): 主公謀殺善居民 → 義理念同伴忠誠 −15。
# 只計「玩家先行出手」(initiated)，自衛反殺 / 殺紅名 / 其他理念 唔扣。
func _kill_bot(t: Dictionary, by: Dictionary) -> void:
	var is_player := int(by.get("id", 0)) == int(state["player_id"])
	var red := bool(t.get("ch", {}).get("criminal", false))
	var initiated := is_player and int(ent(int(state["player_id"])).get("atk_target", 0)) == int(t["id"])
	super(t, by)
	if is_player and not red and initiated:
		var c := _companion_of(ent(int(state["player_id"])))
		if not c.is_empty():
			var lcfg: Dictionary = data.recruit_cfg["loyalty"]
			var ideo := String(c["ch"].get("ideology", ""))
			if (lcfg.get("badNpcKillIdeo", []) as Array).has(ideo):
				_loyalty_change(c, int(lcfg.get("badNpcKill", -15)))


# 同伴倒下 = 唔會死: 原地進入「倒下」狀態 (hp 0, flags down) 等道士「超渡」復活 (S02c)；
# 超過 koTicks 未救 → 當佢退返客棧 (忠誠 -ko, 兜底免得冇道士時同伴永遠倒地)。
func _kill_player(p: Dictionary) -> void:
	if p.get("kind", "") != "gen":
		super(p)
		return
	if bool(p.get("down", false)):
		return                    # 已倒低, 唔重複觸發
	var ch: Dictionary = p["ch"]
	ch["hp"] = 0
	ch["status"] = {}
	p.erase("casting")
	p.erase("path")
	p.erase("goto")
	p["atk_target"] = 0
	p["down"] = true
	p["downAt"] = tick
	_sync_stats(p)
	var owner := int(p["gen"]["owner"])
	_emit({"k": "companion_down", "dst": owner, "id": int(p["id"]), "name": str(p["name"])})
	_msg(owner, "「%s」倒下咗！搵道士用超渡救返佢…" % p["name"])


# 醫生
func _down_bailout() -> void:
	for id in ents.keys():
		var e := ent(int(id))
		if e.is_empty() or e.get("kind", "") != "gen" or not bool(e.get("down", false)):
			continue
		if tick < int(e.get("downAt", 0)) + int(data.world["combat"].get("compDownTicks", 600)):
			continue
		var ch: Dictionary = e["ch"]
		ch["status"] = {}
		_full_heal(ch)
		e.erase("casting")
		e.erase("down")
		e.erase("downAt")
		var inn := nearest_inn(map_id_at(int(e["x"]), int(e["y"])))
		_put_ent(e, int(inn["x"]), int(inn["y"]))
		e["atk_target"] = 0
		_sync_stats(e)
		var owner := int(e["gen"]["owner"])
		_emit({"k": "companion_ko", "dst": owner, "id": int(e["id"])})
		_msg(owner, "%s未及搶救，退返%s休養" % [e["name"], inn.get("name", "客棧")])
		if not bool(_comp_eff(e).get("noKoLoss", false)):     # 堅忍 (Step 15)
			_loyalty_change(e, int(data.recruit_cfg["loyalty"]["ko"]))


# 同伴殺怪: 掉落/金/善惡歸主公，經驗按隊伍經驗池分 (S02b, 同伴有自己 exp/level)；殺善怪 → 義理/治國同伴忠誠跌
func _kill_mob(m: Dictionary, by: Dictionary, exp_mult: float = 1.0) -> void:
	var d := data.mob_def(int(m["mob"]["def"]))
	var killer := by
	if by.get("kind", "") == "gen":
		var o := ent(int(by["gen"]["owner"]))
		if not o.is_empty():
			killer = o                # 掉落/金/善惡仍然歸主公【原】；經驗喺 super() 按各自傷害分（教導特技留返 Spec09 補完期再接）
	super(m, killer, exp_mult)
	var c := _companion_of(killer)
	if not c.is_empty():
		_loyalty_change(c, RulesRecruit.loyalty_kill_delta(String(c["ch"]["ideology"]), float(d.get("alignment", 0)), data.recruit_cfg))


# ================= 特技 / 寶物加成 / 絕招術法 (Step 15, spec 09 §3.3~3.4) =================
func _gskill_def(sid: int) -> Dictionary:
	return data.gen_skill_by_id.get(sid, {})


# 同伴 ch 嘅特技效果 ({} = 冇 / 未實作)
func _skill_eff_of(ch: Dictionary) -> Dictionary:
	return RulesGeneral.skill_eff(_gskill_def(int(ch.get("genSkill", 0))))


func _comp_eff(c: Dictionary) -> Dictionary:
	return _skill_eff_of(c["ch"]) if c.has("ch") else {}


# ===== S09c 內政協助 / 被動特技 (spec 09 §3.3/§3.4) =====
# 主人 ch → 同伴實體 (生存先計)；同伴跟住主公時生效 (唔限距離，同政才/辯才一致)
func _comp_of_ch(ch: Dictionary) -> Dictionary:
	var c := ent(int(ch.get("recruit", {}).get("comp", 0))) if ch.has("recruit") else {}
	if not c.is_empty() and c.has("gen") and int(c["hp"]) > 0:
		return c
	return {}


func _comp_eff_of_ch(ch: Dictionary) -> Dictionary:
	var c := _comp_of_ch(ch)
	return _comp_eff(c) if not c.is_empty() else {}


# 同伴政治 (由武將智力換算)
func _comp_pol_of_ch(ch: Dictionary) -> int:
	var c := _comp_of_ch(ch)
	if c.is_empty():
		return 0
	var g: Dictionary = data.general_by_id.get(int(c["gen"]["gid"]), {})
	return RulesGeneral.pol_of(g, data.gen2_cfg.get("assist", {}))


# 內政協助: 同伴政治 + 內政類特技 → 官宅內政 / 營地內政完成度加成 (override S08b hook)
func _domestic_assist_bonus(ch: Dictionary) -> float:
	return RulesGeneral.assist_bonus(_comp_pol_of_ch(ch), _comp_eff_of_ch(ch), data.gen2_cfg.get("assist", {}))


# 營地監督完成度: 同伴政治加入主公政治 (override S08f hook)
func _companion_pol_bonus(ch: Dictionary) -> int:
	return _comp_pol_of_ch(ch)


# 生產專精 45~48: 對應工作技能經驗倍率
func _work_exp_mult(ch: Dictionary, skill: String) -> float:
	return RulesGeneral.work_exp_mult(_comp_eff_of_ch(ch), skill)


# 生產專精 49~51: 對應進階技能成功率加成
func _craft_rate_add(ch: Dictionary, skill: String) -> float:
	return RulesGeneral.craft_rate_add(_comp_eff_of_ch(ch), skill)


# 商才 43: 買賣價乘數
func _companion_trade_mul(ch: Dictionary) -> Dictionary:
	return RulesGeneral.trade_mul(_comp_eff_of_ch(ch))


# 同伴術法 = 武將最高等級攻擊戰術 (火計/水計/落石…) → {name, elem}
func _comp_spell(c: Dictionary) -> Dictionary:
	var g: Dictionary = data.general_by_id.get(int(c["gen"]["gid"]), {})
	return RulesGeneral.spell_of(g, data.gen2_cfg["tactics"], data.general_skill_names)


# 主公身上嘅特技光環 (督戰/護主): 同伴生存 + 同圖 + auraRange 格內
func _owner_aura(ch: Dictionary) -> Dictionary:
	var c := ent(int(ch.get("recruit", {}).get("comp", 0)))
	if c.is_empty() or not c.has("gen") or int(c["hp"]) <= 0:
		return {}
	var aura: Dictionary = _comp_eff(c).get("owner", {})
	if aura.is_empty():
		return {}
	var o := ent(int(c["gen"]["owner"]))
	if o.is_empty() or not _aura_near(c, o):
		return {}
	return aura


func _aura_near(c: Dictionary, o: Dictionary) -> bool:
	return map_id_at(int(c["x"]), int(c["y"])) == map_id_at(int(o["x"]), int(o["y"])) \
		and _cheb(c, o) <= int(data.gen2_cfg["auraRange"])


# 同伴: 寶物 + 特技 self 加成疊落輔助石加成；主公: 特技光環
func _jewel_bonus(ch: Dictionary) -> Dictionary:
	var b := super(ch)
	var extra: Array = []
	if ch.has("genTreasures"):
		extra.append(RulesGeneral.treasure_bonus(ch["genTreasures"], data.gen2_cfg)["bonus"])
		extra.append(_skill_eff_of(ch).get("self", {}))
	elif ch.has("recruit"):
		var aura := _owner_aura(ch)
		if not aura.is_empty():
			extra.append(aura)
	if extra.is_empty():
		return b
	extra.push_front(b)
	return RulesJewel.sum_bonus(extra)


# 同伴屬性: 寶物 (速度 → 敏捷、術攻 → 智力) + 特技 flat (疾風)
func _eff_attr(ch: Dictionary, k: String, ab: Dictionary = {}) -> float:
	var v := super(ch, k, ab)
	if ch.has("genTreasures"):
		v += float(RulesGeneral.treasure_bonus(ch["genTreasures"], data.gen2_cfg)["flat"].get(k, 0))
		v += float(_skill_eff_of(ch).get("flat", {}).get(k, 0))
	return v


# 特技回復 (回春/冥想/養氣 戰鬥中都回；醫術 = 主公附近回 HP)
func _skill_regen(c: Dictionary, o: Dictionary) -> void:
	if tick % int(data.gen2_cfg["regenTicks"]) != 0:
		return
	var eff := _comp_eff(c)
	if eff.is_empty():
		return
	var ch: Dictionary = c["ch"]
	if eff.has("regenPct"):
		ch["hp"] = mini(_eff_max_hp(ch), int(ch["hp"]) + maxi(1, MathX.js_round(_eff_max_hp(ch) * float(eff["regenPct"]))))
	if eff.has("mpRegenPct"):
		ch["mp"] = mini(_eff_max_mp(ch), int(ch["mp"]) + maxi(1, MathX.js_round(_eff_max_mp(ch) * float(eff["mpRegenPct"]))))
	if eff.has("spRegenPct"):
		ch["sp"] = mini(_eff_max_sp(ch), int(ch["sp"]) + maxi(1, MathX.js_round(_eff_max_sp(ch) * float(eff["spRegenPct"]))))
	_sync_stats(c)
	if eff.has("ownerRegenPct") and int(o["hp"]) > 0 and _aura_near(c, o):
		var och: Dictionary = o["ch"]
		och["hp"] = mini(_eff_max_hp(och), int(och["hp"]) + maxi(1, MathX.js_round(_eff_max_hp(och) * float(eff["ownerRegenPct"]))))
		_sync_stats(o)


# 絕招/術法指令【原】: 夠 SP/MP + 冷卻完就出招；唔夠 = 普通攻擊 (交返 _think_player)
# 絕招 = 以自己為中心範圍物理 ×mult；術法 = 單體戰術 (元素跟武將戰術)，即發
func _comp_skill(c: Dictionary, t: Dictionary) -> void:
	if t.is_empty() or int(t["hp"]) <= 0 or int(c["hp"]) <= 0:
		return
	var gn: Dictionary = c["gen"]
	var ch: Dictionary = c["ch"]
	if tick < int(c["next_atk"]) or tick < int(gn.get("skillCd", 0)) or is_safe(int(c["x"]), int(c["y"])):
		return
	var order := String(gn["order"])
	var uc: Dictionary = data.gen2_cfg["ult"]
	var sc: Dictionary = data.gen2_cfg["spell"]
	var reach := int(uc["range"]) if order == "ult" else int(sc["range"])
	if not RulesCombat.in_range(c["x"], c["y"], t["x"], t["y"], reach):
		return
	var lv := int(ch["level"])
	var mp_need := _mp_cost(ch, RulesGeneral.spell_mp(lv, sc))
	var sp_need := _sp_cost(ch, int(uc["sp"]))
	var pick := RulesGeneral.skill_pick(order, int(ch["mp"]), int(ch["sp"]), mp_need, sp_need, true)
	if pick == "":
		return
	c["tx"] = c["x"]
	c["ty"] = c["y"]
	c["next_atk"] = tick + RulesCombat.attack_interval(_eff_attr(ch, "agi"))
	var owner := int(gn["owner"])
	if pick == "ult":
		ch["sp"] = int(ch["sp"]) - sp_need
		gn["skillCd"] = tick + int(uc["cd"])
		var targets: Array = []
		for o in ents.values():
			if _hittable(o) and RulesCombat.in_range(c["x"], c["y"], o["x"], o["y"], int(uc["range"])):
				targets.append(o)
		var wdef: Dictionary = _weapon_def(ch)
		var atk_mult := RulesSpell.atk_mult(ch.get("status", {}), tick) * (1.0 + float(_jewel_bonus(ch).get("atkPct", 0.0)))
		var eff_str := _eff_attr(ch, "str") + float(_jewel_bonus(ch).get("strFlat", 0))
		_emit({"k": "comp_skill", "src": int(c["id"]), "dst": owner, "skill": "ult", "name": String(uc["name"]), "sp": sp_need})
		for o in targets:
			var mdef: Dictionary = data.mob_def(int(o["mob"]["def"]))
			var dmg := MathX.js_round(RulesCombat.calc_damage(eff_str, wdef["power"], mdef["def"], rng_fn, atk_mult, 1.0) * float(uc["mult"]))
			_emit({"k": "ult_hit", "src": int(c["id"]), "dst": o["id"], "dmg": dmg, "ult": "gen"})
			damage(o, dmg, c)
	else:
		ch["mp"] = int(ch["mp"]) - mp_need
		gn["skillCd"] = tick + int(sc["cd"])
		var sp := _comp_spell(c)
		var mdef2: Dictionary = data.mob_def(int(t["mob"]["def"]))
		var power := RulesGeneral.spell_power(lv, sc) * (1.0 + float(_jewel_bonus(ch).get("spellAtkPct", 0.0)))
		var dmg2 := RulesSpell.calc_spell_damage(power, _eff_attr(ch, "int"), float(mdef2.get("spellDef", 0)),
			String(sp["elem"]), str(mdef2.get("element", "none")), 0.0, rng_fn)
		_emit({"k": "comp_skill", "src": int(c["id"]), "dst": owner, "skill": "spell", "name": String(sp["name"]), "mp": mp_need})
		_emit({"k": "spell_hit", "src": int(c["id"]), "dst": t["id"], "dmg": dmg2, "elem": String(sp["elem"])})
		damage(t, dmg2, c)
	if not ents.has(int(c["id"])):
		return
	_sync_stats(c)


# 辯才: 同伴喺身邊 → 主公發話唔扣飲水度 (口渴 0 照樣講唔到)
func _sip_thirst(e: Dictionary) -> bool:
	if String(e.get("kind", "")) == "player" and thirst_of(e["ch"]) > 0:
		var c := _companion_of(e)
		if not c.is_empty() and bool(_comp_eff(c).get("noThirst", false)) and _aura_near(c, e):
			return true
	return super(e)


# 官令行動力消耗 (政才 = 減半)
func _office_ap_cost(ch: Dictionary) -> int:
	var base := int(data.office["apCost"])
	var c := ent(int(ch.get("recruit", {}).get("comp", 0)))
	if c.is_empty() or not c.has("gen"):
		return base
	return MathX.js_round(base * float(_comp_eff(c).get("apCostMul", 1.0)))


# ================= 官員護衛/流落官員 NPC (S06a spec 06 §3): 借用同伴 (gen kind) 嘅過圖/HP/倒下機制 =================
# 生成官員 NPC：escort = 主公隔籬跟隨；rescue = field_1 打怪區隨機一角，等玩家救
func _spawn_office_npc(pe: Dictionary, role: String) -> Dictionary:
	var zone := "field_1"
	for od2 in data.office["orders"]:
		if String(od2["kind"]) == role:
			zone = String(od2["zone"])
	var pos: Vector2i
	if role == "escort":
		pos = _free_near(int(pe["x"]), int(pe["y"]))
	else:
		pos = _pick_free(52, 5, 96, 22)
	var ename := "護衛官員" if role == "escort" else "流落官員"
	var c := _new_ent(ename, "gen", pos)
	var ch := RulesStats.create_character(data, ename.substr(0, 8), "yishi")
	ch["level"] = 15
	ch["bag"] = []
	ch["gold"] = 0
	ch["equip"]["spellbooks"] = [0, 0, 0]
	ch["equip"]["jewels"] = [0, 0]
	_ensure_equip(ch)
	_full_heal(ch)
	c["ch"] = ch
	c["gen"] = {"gid": 0, "owner": int(pe["id"]) if role == "escort" else 0, "office": true,
		"role": role, "rescued": false, "order": "follow", "skillCd": 0}
	_sync_stats(c)
	return c


# 官員 NPC 跟隨: 過圖跟主公 (簡化版 _think_companion, 冇打怪/落指令); rescue 未救到之前企定唔郁
func _think_office_npc(c: Dictionary) -> void:
	var gn: Dictionary = c["gen"]
	if bool(c.get("down", false)):
		return
	if String(gn["role"]) == "rescue" and not bool(gn.get("rescued", false)):
		var pe := ent(int(state["player_id"]))
		var near := not pe.is_empty() and int(pe.get("hp", 0)) > 0 and map_id_at(int(pe["x"]), int(pe["y"])) == map_id_at(int(c["x"]), int(c["y"])) and _cheb(c, pe) <= 3
		if near:
			gn["rescued"] = true
			gn["owner"] = int(pe["id"])
			_msg(int(pe["id"]), "救到流落官員！帶佢返官宅覆命啦。")
		return
	var o := ent(int(gn.get("owner", 0)))
	if o.is_empty():
		return
	var omap := map_id_at(int(o["x"]), int(o["y"]))
	if map_id_at(int(c["x"]), int(c["y"])) != omap:
		if not _route_to_map(c, omap):
			var p := _free_near(int(o["x"]), int(o["y"]))
			_put_ent(c, p.x, p.y)
		return
	var d := _cheb(c, o)
	if d <= 2:
		c["tx"] = c["x"]
		c["ty"] = c["y"]
		c.erase("path")
	elif maxi(absi(int(c["tx"]) - int(o["x"])), absi(int(c["ty"]) - int(o["y"]))) > 2 or (int(c["tx"]) == int(c["x"]) and int(c["ty"]) == int(c["y"])):
		_set_dest(c, int(o["x"]), int(o["y"]), CHASE_CAP)


# UI 用: 護衛/救援官員 NPC 現況一句講
func _office_npc_status(od: Dictionary) -> String:
	var npc := ent(int(od.get("npc", 0)))
	if npc.is_empty() or bool(npc.get("down", false)):
		return "（官員已經死咗，放棄官令再接過）"
	var gn: Dictionary = npc.get("gen", {})
	if String(gn.get("role", "")) == "rescue" and not bool(gn.get("rescued", false)):
		return "（HP %d/%d，未搵到）" % [int(npc["hp"]), int(npc["max_hp"])]
	return "（HP %d/%d，跟緊你）" % [int(npc["hp"]), int(npc["max_hp"])]

