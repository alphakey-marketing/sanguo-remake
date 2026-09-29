extends SceneTree
# Step 13.5 測試 (spec 09 §2~3): 登用武將 — 導入數據 / 理念 5×3 / 等級邊界 / Tier1 時辰出現
# 跑: Godot --headless --path client --script tests/run_recruit.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_ideology(data)
	t_level(data)
	t_tier1_window(data)
	t_general_talk(data)
	t_survey_limits(data)
	t_candidates(data)
	t_arena_win(data)
	t_arena_lose(data)
	t_arena_fight(data)
	t_arena_walk_away(data)
	t_quiz(data)
	t_quiz_fail(data)
	t_save_roundtrip(data)
	t_determinism(data)
	t_comp_follow(data)
	t_comp_orders(data)
	t_comp_kill_credit(data)
	t_comp_hunt(data)
	t_comp_expire(data)
	t_comp_loyalty(data)
	t_comp_ko(data)
	t_comp_gift_dismiss(data)
	t_comp_cross_map(data)
	t_comp_save(data)
	t_recruit_view(data)
	print("[TEST] recruit scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _new(data: GameData, seed: int = 135) -> Array:
	var sim := Sim.new(data, seed)
	var pid := sim.spawn_player("t", "yishi")
	var ch := sim.player_ch()
	var msgs: Array = []
	var evs: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		evs.append(ev)
		if String(ev.get("k", "")) == "msg":
			msgs.append(String(ev["text"])))
	return [sim, pid, ch, msgs, evs]


func _last(msgs: Array) -> String:
	return String(msgs[-1]) if not msgs.is_empty() else ""


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	e.erase("path")


# 跳去第 day 日第 ke 刻 (gameMinPerTick = 2 → 1 刻 = 7.5 tick)
func _at(sim: Sim, day: int, ke: int) -> void:
	var tpd := 1440 / int(sim.data.world["clock"]["gameMinPerTick"])
	sim.state["tick"] = day * tpd + int(ceil(ke * 15.0 / float(sim.data.world["clock"]["gameMinPerTick"]))) - 1
	sim.step()


func _gen(data: GameData, gname: String) -> Dictionary:
	for g in data.generals_t1:
		if String(g["name"]) == gname:
			return g
	return {}


func t_data(data: GameData) -> void:
	check(data.generals.size() == 1261, "導入: 1261 武將 (而家 %d)" % data.generals.size())
	check(data.generals_t1.size() >= 10 and data.generals_t1.size() <= 20, "導入: Tier1 10~20 人 (而家 %d)" % data.generals_t1.size())
	check(data.quiz_generals.size() >= 30, "題庫 ≥ 30 題")
	var bad_q := 0
	for q in data.quiz_generals:
		if (q["opts"] as Array).size() != 4 or int(q["a"]) < 0 or int(q["a"]) > 3:
			bad_q += 1
	check(bad_q == 0, "題庫: 每題 4 選項 + 答案 index 合法")
	var bad := 0
	var n_free := 0
	for g in data.generals:
		if int(g["lv"]) < 1 or int(g["lv"]) > 100 or not ["wu", "wen"].has(String(g["type"])) or (g["skills"] as Array).size() > 9:
			bad += 1
		if String(g["ideo"]) == RulesRecruit.FREE_IDEO:
			n_free += 1
		elif not RulesRecruit.IDEOLOGIES.has(String(g["ideo"])):
			bad += 1
	check(bad == 0, "導入: 戰等 1~100 / 類型 / 理念 / 技能 ≤9 合法")
	check(n_free > 500, "導入: 出仕 ≈ 一半 (攻略 600+，而家 %d)" % n_free)
	# 攻略 sy2_6_2 戰等【原】對拍幾個
	check(int(_gen(data, "蔡邕")["lv"]) == 6 and int(_gen(data, "郭嘉")["lv"]) == 20 and int(_gen(data, "糜竺")["lv"]) == 19,
		"導入: 戰等 = 攻略表 (蔡邕 6 / 郭嘉 20 / 糜竺 19)")
	# Tier1 站位: 行得 + 喺城地圖 + 已轉全域
	var bad_pos := 0
	for g in data.generals_t1:
		var md: Dictionary = data.map_at(int(g["x"]), int(g["y"]))
		if data.walk[int(g["y"]) * GameData.WORLD_W + int(g["x"])] != 1 or String(md.get("id", "")) != String(g["map"]) \
				or String(md.get("kind", "")) != "city":
			bad_pos += 1
	check(bad_pos == 0, "Tier1: 站位行得 + 喺城內")
	# 擂台 def
	var d := data.mob_def(RulesRecruit.ARENA_DEF_BASE + int(_gen(data, "郭嘉")["id"]))
	check(int(d.get("hp", 0)) == 20 * 20 and not bool(d["flee"]) and int(d["aggroRange"]) == 0, "擂台 def: HP = 戰等×20、唔逃、唔主動仇恨")
	check(data.mob_def(RulesRecruit.ARENA_DEF_BASE + 999999).is_empty(), "擂台 def: 唔存在嘅武將 = {}")


func t_ideology(_data: GameData) -> void:
	# 【原】5×3 表: 每個理念可登 3 種 (自己 + 兩個相鄰)，其餘 2 種唔得
	var want := {
		"義理": ["義理", "霸權", "治國"], "霸權": ["霸權", "義理", "權謀"], "權謀": ["權謀", "霸權", "隱遁"],
		"隱遁": ["隱遁", "權謀", "治國"], "治國": ["治國", "隱遁", "義理"]}
	var ok := 0
	for p in RulesRecruit.IDEOLOGIES:
		for g in RulesRecruit.IDEOLOGIES:
			if RulesRecruit.ideology_ok(p, g) == (want[p] as Array).has(g):
				ok += 1
	check(ok == 25, "理念 5×3 表: 25 組合全對 (%d/25)" % ok)
	var free_ok := true
	for p in RulesRecruit.IDEOLOGIES + [""]:
		free_ok = free_ok and RulesRecruit.ideology_ok(p, "出仕")
	check(free_ok, "理念: 出仕人人可登用 (包括未定理念)")
	check(not RulesRecruit.ideology_ok("", "義理"), "理念: 未定理念只可以登出仕")


func t_level(data: GameData) -> void:
	var cfg := data.recruit_cfg
	check(RulesRecruit.level_ok(15, 5, int(cfg["levelGap"])), "等級: 玩家 5 級可登 15 級 (+10 邊界)")
	check(not RulesRecruit.level_ok(16, 5, int(cfg["levelGap"])), "等級: 玩家 5 級唔可以登 16 級")
	check(RulesRecruit.level_ok(1, 50, int(cfg["levelGap"])), "等級: 低等武將冇下限")
	var g := {"ideo": "出仕", "lv": 30}
	check(RulesRecruit.check(g, {"level": 20, "ideology": "義理"}, cfg) == "", "check: 出仕 + 20 級登 30 級 OK")
	check(RulesRecruit.check(g, {"level": 19, "ideology": "義理"}, cfg) == "等級差太遠", "check: 19 級登 30 級 = 等級差太遠")
	check(RulesRecruit.check({"ideo": "權謀", "lv": 1}, {"level": 50, "ideology": "義理"}, cfg) == "理念唔合", "check: 義理登權謀 = 理念唔合")
	check(RulesRecruit.title_ok({"lv": 50}, {"level": 1}, cfg), "頭銜: 50 級人才白身都得")
	check(not RulesRecruit.title_ok({"lv": 90}, {"level": 90}, cfg), "頭銜: 90 級人才 (40 階) 白身唔得 (Step 14)")
	check(RulesRecruit.title_ok({"lv": 90}, {"level": 90, "titleRank": 35}, cfg), "頭銜: 90 級人才 35 階得 (差 5)")
	check(RulesRecruit.check({"ideo": "出仕", "lv": 90}, {"level": 90, "ideology": "義理", "titleRank": 34}, cfg) == "頭銜唔夠", "check: 差 6 階 = 頭銜唔夠")


func t_tier1_window(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var gj := _gen(data, "郭嘉")      # 午~亥 (48 ~ 0 跨日)
	var gc := _gen(data, "曹操")      # 辰~酉 (32 ~ 80)
	var gd := _gen(data, "典韋")      # 全日
	_at(sim, 1, 10)
	check(not sim.general_visible(gc) and not sim.general_visible(gj) and sim.general_visible(gd), "時辰: 丑時 曹操/郭嘉唔喺度，典韋全日喺度")
	_at(sim, 1, 40)
	check(sim.general_visible(gc) and not sim.general_visible(gj), "時辰: 巳時 曹操喺度，郭嘉未出")
	_at(sim, 1, 90)
	check(not sim.general_visible(gc) and sim.general_visible(gj), "時辰: 亥時 曹操走咗，郭嘉喺度 (跨日窗口)")
	var ids := {}
	for v in sim.view_generals():
		ids[int(v["id"])] = true
	check(ids.has(int(gj["id"])) and ids.has(int(gd["id"])) and not ids.has(int(gc["id"])), "view_generals: 只列見到嘅")
	# 離開城 (跟緊人/呢個月走咗) = 唔見
	sim.state["generals"] = {str(int(gd["id"])): {"awayMonth": sim._month()}}
	check(not sim.general_visible(gd), "走咗: 呢個月唔再出現")
	_at(sim, 31, 40)
	check(sim.general_visible(gd), "走咗: 下個月返嚟")


func t_general_talk(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var msgs: Array = r[3]
	var evs: Array = r[4]
	var gd := _gen(data, "典韋")
	sim.cmd_general_talk(pid, int(gd["id"]))
	check(_last(msgs).begins_with("要行近"), "傾偈: 要行近")
	_put(sim, pid, int(gd["x"]) + 1, int(gd["y"]))
	sim.cmd_general_talk(pid, int(gd["id"]))
	var said := false
	for ev in evs:
		if String(ev.get("k", "")) == "npc_say" and int(ev.get("general", 0)) == int(gd["id"]):
			said = true
	check(said and _last(msgs).contains("戰等"), "傾偈: 講對白 + 簡介")


# ---------------- B: 調查 / 擂台 / 問答 ----------------
# 開局: 許昌城內，巳時 (Tier1 大部分喺度)，指定等級/理念
func _setup(data: GameData, lv: int, ideo: String, seed: int = 135) -> Array:
	var r := _new(data, seed)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	ch["level"] = lv
	ch["ideology"] = ideo
	_at(sim, 1, 40)
	return r


func _survey(sim: Sim, pid: int, kind: String) -> Array:
	var out: Array = []
	var cb := func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "recruit_survey":
			out.append_array(ev["cands"])
	sim.event_emitted.connect(cb)
	sim.cmd_recruit_survey(pid, kind)
	sim.event_emitted.disconnect(cb)
	return out


func _mob_of(sim: Sim, ch: Dictionary) -> Dictionary:
	return sim.ent(int(ch.get("recruit", {}).get("pending", {}).get("mob", 0)))


func t_survey_limits(data: GameData) -> void:
	var r := _setup(data, 5, "義理")
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var inn := sim.nearest_inn("xuchang")
	var z := sim.zone_by_id("field_1")
	var fp := sim._free_near(int(z["x0"]) + 45, int(z["y0"]) + 20)
	_put(sim, pid, fp.x, fp.y)
	sim.cmd_recruit_survey(pid, "wen")
	check(_last(msgs).contains("城池"), "調查: 野外唔得")
	_put(sim, pid, int(inn["x"]), int(inn["y"]))
	sim.cmd_recruit_survey(pid, "wen")
	check(int(ch.get("recruit", {}).get("surveyDay", -1)) == 1, "調查: 城內 OK，記低日子")
	sim.cmd_recruit_survey(pid, "wu")
	check(_last(msgs).contains("今日已經調查"), "調查: 每日 1 次 (換類別都唔得)")
	_at(sim, 2, 40)
	sim.cmd_recruit_survey(pid, "wen")
	check(int(ch["recruit"]["surveyDay"]) == 2, "調查: 第二日可以再調查")
	ch["recruit"]["recruitLockUntil"] = 3 + int(sim.data.recruit_cfg.get("recruitLockDays", 15))
	_at(sim, 3, 40)
	sim.cmd_recruit_survey(pid, "wen")
	check(_last(msgs).contains("登用鎖緊"), "調查: 登用成功後 recruitLockDays 日內封鎖")
	var unlock_day := 3 + int(sim.data.recruit_cfg.get("recruitLockDays", 15))
	_at(sim, unlock_day, 40)
	sim.cmd_recruit_survey(pid, "wen")
	check(int(ch["recruit"]["surveyDay"]) == unlock_day, "調查: recruitLockDays 日後解封")
	sim.cmd_recruit_pick(pid, 999999)
	check(_last(msgs).contains("要先調查"), "揀人: 唔喺候選 = 唔得")


func t_candidates(data: GameData) -> void:
	var r := _setup(data, 5, "義理")
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var cands := _survey(sim, pid, "wen")
	var cfg := data.recruit_cfg
	var ok := not cands.is_empty()
	var names := {}
	var has_zhong := false
	for c in cands:
		var g: Dictionary = data.general_by_id[int(c["id"])]
		ok = ok and RulesRecruit.check(g, ch, cfg) == "" and String(g["type"]) == "wen"
		ok = ok and int(g["tier"]) >= 0 and (int(g["tier"]) == 1 or int(g["lv"]) >= 5 - int(cfg["poolBelow"]))
		ok = ok and not names.has(String(g["name"]))
		names[String(g["name"])] = true
		if String(g["name"]) == "鍾繇":
			has_zhong = true
		if String(g["name"]) == "蔡邕":
			ok = false          # 隱遁 唔喺義理可登表
	check(ok, "候選: 全部過 check / 啱類別 / 冇同名 / 冇 tier -1")
	check(has_zhong, "候選: 城內見到嘅 Tier1 (鍾繇 9 級治國) 入選")
	check(cands.size() >= int(cfg["surveyMax"]), "候選: 登用池補夠 %d 個" % int(cfg["surveyMax"]))
	# 同一日同一人 → 同一個結果；Tier1 唔見到就唔入
	var vis := {}
	var c2 := RulesRecruit.candidates(data.generals, ch, "wen", 1, vis, {}, cfg)
	var c3 := RulesRecruit.candidates(data.generals, ch, "wen", 1, vis, {}, cfg)
	var same := c2.size() == c3.size()
	var any_t1 := false
	for i in c2.size():
		same = same and int(c2[i]["id"]) == int(c3[i]["id"])
		any_t1 = any_t1 or int(c2[i]["tier"]) == 1
	check(same and not any_t1, "候選: 可重現；Tier1 唔見到就唔入")
	var c4 := RulesRecruit.candidates(data.generals, ch, "wen", 2, vis, {}, cfg)
	var diff := false
	for i in mini(c2.size(), c4.size()):
		diff = diff or int(c2[i]["id"]) != int(c4[i]["id"])
	check(diff, "候選: 唔同日子出唔同人")
	var gone := {int(c2[0]["id"]): true}
	var c5 := RulesRecruit.candidates(data.generals, ch, "wen", 1, vis, gone, cfg)
	var still := false
	for g in c5:
		still = still or int(g["id"]) == int(c2[0]["id"])
	check(not still, "候選: 走咗嘅人唔再出")


# 高等玩家調查武將 → 揀第一個 → 擂台開始
func _arena_setup(data: GameData, seed: int = 135) -> Array:
	var r := _setup(data, 60, "義理", seed)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var cands := _survey(sim, pid, "wu")
	check(not cands.is_empty(), "擂台: 60 級有武將候選")
	sim.cmd_recruit_pick(pid, int(cands[0]["id"]))
	r.append(int(cands[0]["id"]))
	return r


func t_arena_win(data: GameData) -> void:
	var r := _arena_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var evs: Array = r[4]
	var gid: int = r[5]
	var m := _mob_of(sim, ch)
	check(not m.is_empty() and bool(m["mob"].has("arena")) and int(sim.ent(pid)["atk_target"]) == int(m["id"]), "擂台: 生成臨時怪 + 自動鎖定")
	check(String(ch["recruit"]["pending"]["kind"]) == "arena", "擂台: pending = arena")
	var hp0 := int(m["hp"])
	sim.damage(m, 50, {"id": -5, "kind": "bot", "ch": {}})
	check(int(m["hp"]) == hp0, "擂台: 挑戰者以外打唔到")
	sim.damage(m, 999999, sim.ent(pid))
	check(sim.ent(int(m["id"])).is_empty(), "擂台: 打到 0 = 制服 (臨時怪收走)")
	var comp := sim.ent(int(ch["recruit"].get("comp", 0)))
	check(not comp.is_empty() and String(comp["kind"]) == "gen" and int(comp["gen"]["gid"]) == gid, "擂台贏: 生成同伴")
	check(int(ch["recruit"]["recruitLockUntil"]) == int(sim._clock()["day"]) + int(sim.data.recruit_cfg.get("recruitLockDays", 15)) and not ch["recruit"].has("pending"), "擂台贏: 封鎖 recruitLockDays 日 + 清 pending")
	check(bool(sim.state["generals"][str(gid)]["serving"]), "擂台贏: 武將標記跟緊人")
	var won := false
	for ev in evs:
		if String(ev.get("k", "")) == "recruit_result" and bool(ev["ok"]):
			won = true
	check(won, "擂台贏: recruit_result ok")
	var cv := sim.companion_view()
	check(int(cv.get("gid", 0)) == gid and int(cv["daysLeft"]) == int(data.recruit_cfg["serveDays"]) and int(cv["loyalty"]) >= int(data.recruit_cfg["loyalty"]["init"]),
		"companion_view: gid / serveDays 日 / 忠誠")
	sim.cmd_recruit_survey(pid, "wu")
	check(_last(r[3]).contains("已經有人才"), "有同伴: 唔可以再調查")


func t_arena_lose(data: GameData) -> void:
	var r := _arena_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var evs: Array = r[4]
	var gid: int = r[5]
	var m := _mob_of(sim, ch)
	var gold := int(ch["gold"])
	sim.damage(sim.ent(pid), 999999, m)
	var died := false
	for ev in evs:
		if String(ev.get("k", "")) == "die":
			died = true
	check(int(sim.ent(pid)["hp"]) == 1 and not died and int(ch["gold"]) == gold, "擂台輸: 留 1 HP，唔算死冇處分")
	check(sim.ent(int(m["id"])).is_empty() and not ch["recruit"].has("pending") and int(ch["recruit"].get("comp", 0)) == 0, "擂台輸: 武將走人，冇同伴")
	check(sim._general_away(gid), "擂台輸: 武將呢個月唔再出現")
	sim.cmd_recruit_survey(pid, "wu")
	check(_last(r[3]).contains("今日已經調查"), "擂台輸: 調查算用咗")


# 真打: 60 級強化玩家喺城內 (安全區) 擂台照打得
func t_arena_fight(data: GameData) -> void:
	var r := _arena_setup(data, 7)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	for k in ["str", "agi"]:
		ch["attrs"][k] = 99
	var m := _mob_of(sim, ch)
	m["hp"] = mini(int(m["hp"]), 300)
	for i in 600:
		sim.step()
		if not ch["recruit"].has("pending"):
			break
	check(int(ch["recruit"].get("comp", 0)) != 0, "擂台實戰: 安全區都打得，打贏收同伴")


func t_arena_walk_away(data: GameData) -> void:
	var r := _arena_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var e := sim.ent(pid)
	var m := _mob_of(sim, ch)
	var fp := sim._free_near(int(e["x"]) + 20, int(e["y"]))
	_put(sim, int(m["id"]), fp.x, fp.y)
	sim.step()
	check(not ch["recruit"].has("pending") and int(ch["recruit"].get("comp", 0)) == 0, "擂台: 走甩 (>12 格) = 輸")


# 文官問答: 5 級義理調查文官 → 揀鍾繇
func _quiz_setup(data: GameData, seed: int = 135) -> Array:
	var r := _setup(data, 5, "義理", seed)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var gid := 0
	for c in _survey(sim, pid, "wen"):
		if String(c["name"]) == "鍾繇":
			gid = int(c["id"])
	sim.cmd_recruit_pick(pid, gid)
	r.append(gid)
	return r


func _answer(sim: Sim, pid: int, right: bool) -> void:
	var qv := sim.recruit_quiz_view()
	var q: Dictionary = {}
	for x in sim.data.quiz_generals:
		if String(x["q"]) == String(qv["q"]):
			q = x
	sim.cmd_recruit_answer(pid, int(q["a"]) if right else (int(q["a"]) + 1) % 4)


func t_quiz(data: GameData) -> void:
	var r := _quiz_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var gid: int = r[5]
	var qv := sim.recruit_quiz_view()
	check(int(qv.get("n", 0)) == 10 and int(qv["i"]) == 0 and (qv["opts"] as Array).size() == 4, "問答: 10 題，每題 4 選項")
	var seen := {}
	for q in ch["recruit"]["pending"]["qs"]:
		seen[int(q)] = true
	check(seen.size() == 10, "問答: 10 題唔重複")
	_answer(sim, pid, false)
	_answer(sim, pid, false)
	for i in 8:
		_answer(sim, pid, true)
	check(int(ch["recruit"].get("comp", 0)) != 0 and int(sim.ent(int(ch["recruit"]["comp"]))["gen"]["gid"]) == gid, "問答: 錯 2 啱 8 = 過關登用")


func t_quiz_fail(data: GameData) -> void:
	var r := _quiz_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var gid: int = r[5]
	for i in 3:
		_answer(sim, pid, i != 1)
	check(ch["recruit"].has("pending"), "問答: 錯 1 題未完")
	_answer(sim, pid, false)
	_answer(sim, pid, false)
	check(not ch["recruit"].has("pending") and int(ch["recruit"].get("comp", 0)) == 0, "問答: 錯第 3 題即刻失敗")
	check(sim._general_away(gid), "問答失敗: 文官呢個月走人")
	check(sim.recruit_quiz_view().is_empty(), "問答失敗: 冇題目")
	var r2 := _quiz_setup(data, 8)
	var sim2: Sim = r2[0]
	sim2.cmd_recruit_cancel(int(r2[1]))
	check(not r2[2]["recruit"].has("pending") and sim2._general_away(int(r2[5])), "問答: 放棄 = 失敗")


func t_save_roundtrip(data: GameData) -> void:
	var r := _quiz_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	_answer(sim, pid, true)
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	check(loaded.save_string() == s1, "存檔: 問答中 save→load→save 一致")
	check(int(loaded.recruit_quiz_view().get("i", -1)) == 1, "存檔: 問答進度保留")
	for i in 9:
		_answer(loaded, pid, true)
	check(int(loaded.player_ch()["recruit"].get("comp", 0)) != 0, "存檔: 讀返之後答完登用")
	var s2 := loaded.save_string()
	var l2 := Sim.load_string(data, s2)
	check(l2.save_string() == s2 and not l2.companion_view().is_empty(), "存檔: 有同伴 roundtrip")
	var ra := _arena_setup(data)
	var s3: String = ra[0].save_string()
	var l3 := Sim.load_string(data, s3)
	check(l3.save_string() == s3, "存檔: 擂台中 roundtrip")
	l3.step()
	check(not _mob_of(l3, l3.player_ch()).is_empty(), "存檔: 讀返擂台繼續")


func _run_seq(data: GameData) -> String:
	var r := _quiz_setup(data, 99)
	var sim: Sim = r[0]
	var pid: int = r[1]
	for i in 10:
		if sim.recruit_quiz_view().is_empty():
			break
		_answer(sim, pid, i % 5 != 0)
	for i in 50:
		sim.step()
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_run_seq(data) == _run_seq(data), "決定性: 同種子同結果")


# ---------------- C: 同伴 ----------------
# 問答登用鍾繇 (第 1 日) → 回傳 [sim, pid, ch, msgs, evs, gid, comp]；主公同同伴搬去野外 field_1
func _comp_setup(data: GameData, seed: int = 135, to_field: bool = true) -> Array:
	var r := _quiz_setup(data, seed)
	var sim: Sim = r[0]
	var pid: int = r[1]
	for i in 10:
		if sim.recruit_quiz_view().is_empty():
			break
		_answer(sim, pid, true)
	var c := sim.ent(int(r[2]["recruit"]["comp"]))
	r.append(c)
	if to_field:
		var p := _field_spot(sim)
		_put(sim, pid, p.x, p.y)
		var q := sim._free_near(p.x, p.y)
		_put(sim, int(c["id"]), q.x, q.y)
		# 清走附近嘅怪，免得干擾
		for m in sim.ents.values():
			if m["kind"] == "mob":
				var f := sim._free_near(p.x + 60, p.y + 30)
				_put(sim, int(m["id"]), f.x, f.y)
				m["mob"]["home_x"] = f.x
				m["mob"]["home_y"] = f.y
				m["mob"]["state"] = "wander"
	return r


func _field_spot(sim: Sim) -> Vector2i:
	var z := sim.zone_by_id("field_1")
	return sim._free_near(int(z["x0"]) + 40, int(z["y0"]) + 30)


# 喺 (x,y) 放一隻怪 (田鼠 1001)
func _mob_at(sim: Sim, x: int, y: int) -> Dictionary:
	var m: Dictionary = sim._spawn_mob(1001, "field_1")
	var p := sim._free_near(x, y)
	_put(sim, int(m["id"]), p.x, p.y)
	m["mob"]["home_x"] = p.x
	m["mob"]["home_y"] = p.y
	return m


func t_comp_follow(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var c: Dictionary = r[6]
	check(String(c["gen"]["order"]) == "assist", "同伴: 預設協助攻擊")
	var o := sim.ent(pid)
	var p := sim._free_near(int(o["x"]) + 10, int(o["y"]))
	_put(sim, pid, p.x, p.y)
	for i in 40:
		sim.step()
	check(sim._cheb(c, o) <= 2, "跟隨: 主公行開 10 格，同伴跟到 ≤2 格 (而家 %d)" % sim._cheb(c, o))
	sim.cmd_companion_order(pid, "follow")
	var p2 := sim._free_near(int(o["x"]) - 10, int(o["y"]))
	_put(sim, pid, p2.x, p2.y)
	for i in 40:
		sim.step()
	var d := sim._cheb(c, o)
	check(d <= 4 and d >= 2, "遠距跟隨: 保持 ≤4 格 (而家 %d)" % d)


func t_comp_orders(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var evs: Array = r[4]
	var c: Dictionary = r[6]
	var o := sim.ent(pid)
	var m := _mob_at(sim, int(o["x"]) + 3, int(o["y"]))
	m["hp"] = 5000
	m["max_hp"] = 5000
	sim.cmd_attack(pid, int(m["id"]))
	var hit := false
	for i in 80:
		sim.step()
	for ev in evs:
		if String(ev.get("k", "")) == "hit" and int(ev["src"]) == int(c["id"]) and int(ev["dst"]) == int(m["id"]):
			hit = true
	check(hit, "協助攻擊: 同伴打主公鎖定嗰隻怪")
	sim.cmd_companion_order(pid, "stop")
	sim.step()
	check(int(c["atk_target"]) == 0, "停止攻擊: 冇目標")
	sim.cmd_companion_order(pid, "follow")
	sim.step()
	check(int(c["atk_target"]) == 0, "遠距跟隨: 唔打")
	sim.cmd_companion_order(pid, "bogus")
	check(String(c["gen"]["order"]) == "follow", "指令: 唔合法唔改")


func t_comp_hunt(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var c: Dictionary = r[6]
	sim.cmd_companion_order(pid, "active")
	sim.step()
	check(int(c["atk_target"]) == 0, "主動攻擊: 附近冇怪 = 冇目標")
	var m := _mob_at(sim, int(c["x"]) + 4, int(c["y"]))
	m["mob"]["state"] = "wander"
	sim.step()
	check(int(c["atk_target"]) == int(m["id"]), "主動攻擊: 自己搵 8 格內嘅怪")
	# 擂台怪/安全區唔打
	check(not sim._hittable({"kind": "mob", "hp": 10, "mob": {"arena": 1}, "x": m["x"], "y": m["y"]}), "唔打擂台怪")


func t_comp_kill_credit(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var c: Dictionary = r[6]
	var o := sim.ent(pid)
	ch["level"] = 1
	ch["exp"] = 0
	c["ch"]["level"] = 1
	c["ch"]["exp"] = 0
	var m := _mob_at(sim, int(o["x"]) + 3, int(o["y"]))
	var d := data.mob_def(int(m["mob"]["def"]))
	var gold := int(ch["gold"])
	sim.damage(m, 99999, c)
	# S02b: 隊伍經驗池按傷害分 — 冇打過嘅主公分唔到，同伴自己出晒力就自己攞晒經驗/升自己級
	check(int(ch["exp"]) == 0, "同伴殺怪: 主公冇分傷害 = 冇經驗")
	check(int(c["ch"]["exp"]) == int(d["exp"]), "同伴殺怪: 同伴自己有經驗 (S02b)")
	check(int(ch["gold"]) >= gold, "同伴殺怪: 金歸主公")


func t_comp_expire(data: GameData) -> void:
	var r := _comp_setup(data, 135, false)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	var gid: int = r[5]
	var c: Dictionary = r[6]
	var cid := int(c["id"])
	var sd := int(data.recruit_cfg["serveDays"])
	check(int(c["gen"]["until"]) == 1 + sd, "到期: 第 1 日登用 → 第 %d 日子時走" % (1 + sd))
	_at(sim, sd, 90)
	check(not sim.ent(cid).is_empty(), "到期: 第 %d 日亥時仲喺度" % sd)
	_at(sim, 1 + sd, 0)
	check(sim.ent(cid).is_empty() and int(ch["recruit"].get("comp", 0)) == 0, "到期: 第 %d 日子時 0 刻離開" % (1 + sd))
	check(not bool(sim.state["generals"][str(gid)]["serving"]) and not sim._general_away(gid), "到期: 返城 (唔當走人)")
	_at(sim, 1 + sd, 40)
	check(sim.general_visible(data.general_by_id[gid]), "到期: Tier1 返到城內企位")


func t_comp_loyalty(data: GameData) -> void:
	var cfg := data.recruit_cfg
	var li := int(cfg["loyalty"]["init"])
	var lv := int(cfg["loyalty"]["leave"])
	check(RulesRecruit.loyalty_init("治國", "治國", cfg) == li + int(cfg["loyalty"]["sameIdeo"]) and RulesRecruit.loyalty_init("義理", "出仕", cfg) == li, "忠誠: 初始 %d，同理念 +%d" % [li, int(cfg["loyalty"]["sameIdeo"])])
	check(RulesRecruit.loyalty_verdict(lv, cfg) == "stay" and RulesRecruit.loyalty_verdict(lv - 1, cfg) == "leave_daily" \
		and RulesRecruit.loyalty_verdict(0, cfg) == "leave_now", "忠誠: ≥%d 留 / <%d 子時走 / 0 即走" % [lv, lv])
	check(RulesRecruit.loyalty_kill_delta("義理", 100, cfg) < 0 and RulesRecruit.loyalty_kill_delta("霸權", 100, cfg) == 0 \
		and RulesRecruit.loyalty_kill_delta("義理", -100, cfg) == 0, "忠誠: 殺善 → 義理/治國跌，殺惡唔影響")
	# 殺善怪 (臨時改田鼠善惡)
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var c: Dictionary = r[6]
	var o := sim.ent(pid)
	var loy := int(c["gen"]["loyalty"])
	var def: Dictionary = data.monsters[1001]
	var al = def["alignment"]
	def["alignment"] = 100
	var m := _mob_at(sim, int(o["x"]) + 3, int(o["y"]))
	sim.damage(m, 99999, o)
	def["alignment"] = al
	check(int(c["gen"]["loyalty"]) == loy + int(cfg["loyalty"]["badKill"]), "忠誠: 主公殺善怪，治國同伴忠誠 %d" % int(cfg["loyalty"]["badKill"]))
	# < 30 → 子時走 (唔開心: 呢個月唔返城)
	c["gen"]["loyalty"] = lv - 1
	var cid := int(c["id"])
	var gid := int(c["gen"]["gid"])
	_at(sim, 2, 0)
	check(sim.ent(cid).is_empty() and sim._general_away(gid), "忠誠 <%d: 子時離開，呢個月唔返城" % lv)
	# = 0 → 即刻走
	var r2 := _comp_setup(data, 9)
	var sim2: Sim = r2[0]
	var c2: Dictionary = r2[6]
	c2["gen"]["loyalty"] = 3
	sim2._loyalty_change(c2, -5)
	check(sim2.ent(int(c2["id"])).is_empty(), "忠誠 0: 即刻離開")


func t_comp_ko(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var c: Dictionary = r[6]
	var loy := int(c["gen"]["loyalty"])
	var m := _mob_at(sim, int(c["x"]) + 1, int(c["y"]))
	var inn := sim.nearest_inn(sim.map_id_at(int(c["x"]), int(c["y"])))
	var cx := int(c["x"])
	var cy := int(c["y"])
	sim.damage(c, 999999, m)
	check(not sim.ent(int(c["id"])).is_empty() and bool(c.get("down", false)) and int(c["hp"]) == 0, "同伴倒下: 原地進入倒下狀態 (等道士超渡)")
	check(int(c["x"]) == cx and int(c["y"]) == cy, "同伴倒下: 留喺原地")
	check(int(c["gen"]["loyalty"]) == loy, "倒下未救: 忠誠暫時唔跌")
	# 超時未救兜底 → 退返客棧回滿 + 忠誠扣減 (冇道士 / 玩家走咗)
	c["downAt"] = int(sim.state["tick"]) - int(data.world["combat"]["compDownTicks"]) - 5
	sim._down_bailout()
	check(not bool(c.get("down", false)) and int(c["hp"]) == int(c["max_hp"]), "超時未救: 回滿")
	check(int(c["x"]) == int(inn["x"]) and int(c["y"]) == int(inn["y"]), "超時未救: 返最近客棧")
	check(int(c["gen"]["loyalty"]) < loy, "超時未救: 忠誠扣減 (忠義特技減半)")


func t_comp_gift_dismiss(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var gid: int = r[5]
	var c: Dictionary = r[6]
	var heal_id := 0
	for k in data.heals:
		if int(data.heals[k].get("hp", 0)) > 0:
			heal_id = int(k)
			break
	RulesShop.add_item(ch["bag"], heal_id, 1)
	c["ch"]["hp"] = 1
	sim._sync_stats(c)
	var loy := int(c["gen"]["loyalty"])
	sim.cmd_companion_gift(pid, heal_id)
	check(int(c["hp"]) > 1 and int(c["gen"]["loyalty"]) == loy + int(data.recruit_cfg["loyalty"]["gift"]) \
		and RulesShop.count_item(ch["bag"], heal_id) == 0, "送補品: 回血 + 忠誠 +%d + 扣背包" % int(data.recruit_cfg["loyalty"]["gift"]))
	sim.cmd_companion_dismiss(pid)
	check(sim.companion_view().is_empty() and not sim._general_away(gid), "解散: 同伴走，返城 (唔算走人)")


func t_comp_cross_map(data: GameData) -> void:
	var r := _comp_setup(data, 135, false)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var c: Dictionary = r[6]
	var p := _field_spot(sim)
	_put(sim, pid, p.x, p.y)
	check(sim.map_id_at(int(c["x"]), int(c["y"])) == "xuchang", "跨圖: 同伴喺許昌，主公喺野外")
	for i in 600:
		sim.step()
		if sim.map_id_at(int(c["x"]), int(c["y"])) == "field_1":
			break
	check(sim.map_id_at(int(c["x"]), int(c["y"])) == "field_1", "跨圖: 同伴行門口過圖跟上")


func t_comp_save(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	sim.cmd_companion_order(pid, "active")
	for i in 30:
		sim.step()
	var s1 := sim.save_string()
	var l := Sim.load_string(data, s1)
	check(l.save_string() == s1, "存檔: 同伴 (指令/忠誠/到期) roundtrip")
	check(String(l.companion_view().get("order", "")) == "active", "存檔: 指令保留")
	for i in 30:
		sim.step()
		l.step()
	check(l.save_string() == sim.save_string(), "存檔: 讀返之後同原本一齊行 30 tick 結果一樣")


# ---------------- D: UI 讀取 ----------------
func t_recruit_view(data: GameData) -> void:
	var r := _setup(data, 5, "義理")
	var sim: Sim = r[0]
	var pid: int = r[1]
	var v := sim.recruit_view()
	check(bool(v["inCity"]) and String(v["block"]) == "" and (v["cands"] as Array).is_empty(), "recruit_view: 城內可調查、未有候選")
	sim.cmd_recruit_survey(pid, "wen")
	v = sim.recruit_view()
	check(not (v["cands"] as Array).is_empty() and String(v["block"]).contains("今日"), "recruit_view: 調查後有候選 + 今日封鎖")
	sim.cmd_recruit_pick(pid, int(v["cands"][0]["id"]))
	v = sim.recruit_view()
	check(String(v["pending"]) == "quiz" and not (v["quiz"] as Dictionary).is_empty() and String(v["block"]) == "考驗緊人才", "recruit_view: 問答中")
	var z := sim.zone_by_id("field_1")
	var fp := sim._free_near(int(z["x0"]) + 45, int(z["y0"]) + 20)
	var r2 := _setup(data, 5, "義理", 3)
	_put(r2[0], int(r2[1]), fp.x, fp.y)
	check(String(r2[0].recruit_view()["block"]).contains("城池"), "recruit_view: 野外 = 要喺城池")
	var r3 := _comp_setup(data, 4)
	var v3: Dictionary = r3[0].recruit_view()
	check(not (v3["comp"] as Dictionary).is_empty() and String(v3["block"]).contains("已經有人才"), "recruit_view: 有同伴")
	var ents: Array = r3[0].view_ents()
	var has_gen := false
	for e in ents:
		has_gen = has_gen or bool(e.get("gen", false))
	check(has_gen, "view_ents: 同伴標 gen")
