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
	check(RulesRecruit.title_ok({"lv": 90}, {"level": 1}, cfg), "頭銜: Step 14 前 stub 永遠過")


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
