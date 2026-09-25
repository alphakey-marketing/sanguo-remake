extends SceneTree
# Step 15 測試 (spec 09 §3.1/3.3/3.4 + §7): 登用 v2 — 將軍令/御賜金牌 / 武將寶物 2 格 / 藥膳師補品 / 特技 / 絕招術法指令
# 跑: Godot --headless --path client --script tests/run_general.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_rules(data)
	t_order_bypass(data)
	t_order_fail_keeps(data)
	t_medal(data)
	t_treasure(data)
	t_tonic(data)
	t_skill_self(data)
	t_skill_owner(data)
	t_skill_misc(data)
	t_comp_ult(data)
	t_comp_spell(data)
	t_team_exp_split()
	t_view(data)
	t_save(data)
	t_old_save(data)
	print("[TEST] general scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


# ---------------- helpers (同 run_recruit 一樣) ----------------
func _new(data: GameData, seed: int = 150) -> Array:
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


func _at(sim: Sim, day: int, ke: int) -> void:
	var tpd := 1440 / int(sim.data.world["clock"]["gameMinPerTick"])
	sim.state["tick"] = day * tpd + int(ceil(ke * 15.0 / float(sim.data.world["clock"]["gameMinPerTick"]))) - 1
	sim.step()


func _setup(data: GameData, lv: int, ideo: String, ke: int = 40, seed: int = 150) -> Array:
	var r := _new(data, seed)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	ch["level"] = lv
	ch["ideology"] = ideo
	_at(sim, 1, ke)
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


# 最近 3 句訊息有冇 text (忠誠訊息會跟喺後面)
func _recent(msgs: Array, text: String) -> bool:
	for i in range(maxi(0, msgs.size() - 3), msgs.size()):
		if String(msgs[i]).contains(text):
			return true
	return false


func _find(cands: Array, gname: String) -> Dictionary:
	for c in cands:
		if String(c["name"]) == gname:
			return c
	return {}


func _answer(sim: Sim, pid: int, right: bool) -> void:
	var qv := sim.recruit_quiz_view()
	var q: Dictionary = {}
	for x in sim.data.quiz_generals:
		if String(x["q"]) == String(qv["q"]):
			q = x
	sim.cmd_recruit_answer(pid, int(q["a"]) if right else (int(q["a"]) + 1) % 4)


# 登用鍾繇 (文官問答全啱) → 放出野外 + 清走附近怪；回 r + [gid, comp]
func _comp_setup(data: GameData, seed: int = 150) -> Array:
	var r := _setup(data, 5, "義理", 40, seed)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var gid := int(_find(_survey(sim, pid, "wen"), "鍾繇").get("id", 0))
	sim.cmd_recruit_pick(pid, gid)
	for i in 10:
		if sim.recruit_quiz_view().is_empty():
			break
		_answer(sim, pid, true)
	var c := sim.ent(int(r[2]["recruit"]["comp"]))
	r.append(gid)
	r.append(c)
	var z := sim.zone_by_id("field_1")
	var p := sim._free_near(int(z["x0"]) + 40, int(z["y0"]) + 30)
	_put(sim, pid, p.x, p.y)
	var q := sim._free_near(p.x, p.y)
	_put(sim, int(c["id"]), q.x, q.y)
	for m in sim.ents.values():
		if m["kind"] == "mob":
			var f := sim._free_near(p.x + 60, p.y + 30)
			_put(sim, int(m["id"]), f.x, f.y)
			m["mob"]["home_x"] = f.x
			m["mob"]["home_y"] = f.y
			m["mob"]["state"] = "wander"
	return r


func _mob_at(sim: Sim, x: int, y: int, hp: int = 5000) -> Dictionary:
	var m: Dictionary = sim._spawn_mob(1001, "field_1")
	var p := sim._free_near(x, y)
	_put(sim, int(m["id"]), p.x, p.y)
	m["mob"]["home_x"] = p.x
	m["mob"]["home_y"] = p.y
	m["hp"] = hp
	m["max_hp"] = hp
	return m


# 將軍令對應武將: 揀一個戰等高 (玩家 5 級登唔到) 嘅武將
func _order_target(sim: Sim, kind: String) -> Dictionary:
	for gname in sim.data.general_order_item:
		var g := sim._order_general(String(gname))
		if not g.is_empty() and String(g["type"]) == kind and int(g["lv"]) >= 40 and int(g["tier"]) == 0:
			return g
	return {}


# ---------------- S02b: 隊伍經驗池 (spec 02 §8) ----------------
func t_team_exp_split() -> void:
	check(RulesGeneral.team_exp_split(100, {}).is_empty(), "隊伍經驗: 冇傷害紀錄 = 空")
	check(RulesGeneral.team_exp_split(0, {"1": 5}).is_empty(), "隊伍經驗: total<=0 = 空")
	var solo := RulesGeneral.team_exp_split(100, {"1": 50})
	check(int(solo["1"]) == 100, "隊伍經驗: 單人打晒 = 攞晒 100%")
	var half := RulesGeneral.team_exp_split(100, {"1": 50, "2": 50})
	check(int(half["1"]) == 50 and int(half["2"]) == 50, "隊伍經驗: 傷害對半 = exp 對半")
	var skew := RulesGeneral.team_exp_split(100, {"1": 90, "2": 10})   # 70%按 9:1 分 + 30%對半
	check(int(skew["1"]) == MathX.js_round(70.0 * 0.9) + 15 and int(skew["2"]) == MathX.js_round(70.0 * 0.1) + 15,
		"隊伍經驗: 70%%按傷害比例 + 30%%平分 (%d/%d)" % [int(skew["1"]), int(skew["2"])])
	var many := {}
	for i in range(8):
		many[str(i)] = 10 * (i + 1)     # 8 個貢獻者，only top 6 by dmg 分到
	var capped := RulesGeneral.team_exp_split(120, many)
	check(capped.size() == 6 and not capped.has("0") and not capped.has("1"),
		"隊伍經驗: 貢獻者多過上限 6 = 淨取傷害最高 6 個")


# ---------------- A: 資料 ----------------
func t_data(data: GameData) -> void:
	check(data.gen_skills.size() == 70, "特技: 共 70 項【原】(而家 %d)" % data.gen_skills.size())
	var n_impl := 0
	var ids := {}
	for s in data.gen_skills:
		ids[int(s["id"])] = true
		if bool(s["impl"]):
			n_impl += 1
			check(not (s.get("eff", {}) as Dictionary).is_empty(), "特技 %s: impl 要有 eff" % s["name"])
	check(ids.size() == 70 and n_impl == 20, "特技: id 唔重複 + 已實作 20 項 (而家 %d)" % n_impl)
	var bad_ov := 0
	for nm in data.gen_skill_override:
		var s: Dictionary = data.gen_skill_by_id.get(int(data.gen_skill_override[nm]), {})
		var g: Dictionary = {}
		for x in data.generals_t1:
			if String(x["name"]) == String(nm):
				g = x
		if s.is_empty() or g.is_empty() or not bool(s["impl"]) or not (s["types"] as Array).has(String(g["type"])):
			bad_ov += 1
	check(bad_ov == 0 and data.gen_skill_override.size() == data.generals_t1.size(), "特技 override: Tier1 全部指定 + 已實作 + 類型啱")
	check(data.general_order_item.size() >= 100 and data.general_order_item.has("呂布"), "將軍令: ≥100 款，有呂布將軍令")
	check(String(data.names.get(int(data.gen2_cfg["goldMedal"]), "")) == "御賜金牌", "御賜金牌 item id 啱")
	var tcount := {}
	for it in data.item_ids:
		var t := RulesGeneral.treasure_of(int(data.cats.get(it, 0)), data.info[it]["effects"], data.gen2_cfg)
		if not t.is_empty():
			tcount[String(t["type"])] = int(tcount.get(String(t["type"]), 0)) + 1
	# 【原】sy2_6_6: 速度 5 / 兵量 1 / 物攻 6 / 物防 3 / 術攻 6 / 術防 3 / 武材 5 / 軍略 5 (+ 迴避 5)
	check(int(tcount.get("78", 0)) == 5 and int(tcount.get("79", 0)) == 6 and int(tcount.get("80", 0)) == 3
		and int(tcount.get("81", 0)) == 6 and int(tcount.get("82", 0)) == 3 and int(tcount.get("84", 0)) == 5
		and int(tcount.get("85", 0)) == 5 and int(tcount.get("83", 0)) >= 1, "寶物: 種類數目 = 攻略 (%s)" % str(tcount))
	var herb: Dictionary = {}
	for s in data.shops:
		if String(s["id"]) == "herbalist":
			herb = s
	check(not herb.is_empty() and String(herb["map"]) == "xuchang" and data.walk[int(herb["y"]) * GameData.WORLD_W + int(herb["x"])] == 1,
		"藥膳師: 許昌市集，站位行得")
	check((herb.get("stock", []) as Array).has(30015.0) and float(data.prices[30015]) > 0, "藥膳師: 賣武將體力丸 + 有價")


# ---------------- 純函數 ----------------
func t_rules(data: GameData) -> void:
	var cfg := data.gen2_cfg
	check(RulesGeneral.order_general_name("呂布將軍令", "將軍令") == "呂布" and RulesGeneral.order_general_name("將軍令", "將軍令") == ""
		and RulesGeneral.order_general_name("趙將軍令牌", "將軍令") == "", "將軍令名 → 武將名")
	check(RulesGeneral.pass_kind(true, true) == "medal" and RulesGeneral.pass_kind(true, false) == "order"
		and RulesGeneral.pass_kind(false, false) == "", "憑證: 金牌優先")
	var atk1 := RulesGeneral.treasure_of(221, [{"type": 79, "value": 5}], cfg)
	check(String(atk1["type"]) == "79" and int(atk1["value"]) == 5, "treasure_of: 物攻之石")
	check(RulesGeneral.treasure_of(43, [{"type": 79, "value": 5}], cfg).is_empty(), "treasure_of: cat 唔啱 = 唔係")
	var r := RulesGeneral.treasure_put([], 54807, atk1, 2)
	check(String(r["res"]) == "add" and (r["slots"] as Array).size() == 1, "寶物: 空格 → add")
	var r2 := RulesGeneral.treasure_put(r["slots"], 54808, {"type": "79", "value": 10}, 2)
	check(String(r2["res"]) == "replace" and int(r2["old"]) == 54807 and int(r2["slots"][0]["value"]) == 10, "寶物: 同類高取代低")
	var r3 := RulesGeneral.treasure_put(r2["slots"], 54807, atk1, 2)
	check(String(r3["res"]) == "lost" and int(r3["slots"][0]["value"]) == 10, "寶物: 同類低 → 新嘅消失")
	var r4 := RulesGeneral.treasure_put(r2["slots"], 54801, {"type": "78", "value": 13}, 2)
	var r5 := RulesGeneral.treasure_put(r4["slots"], 54816, {"type": "81", "value": 5}, 2)
	check(String(r4["res"]) == "add" and String(r5["res"]) == "full" and (r5["slots"] as Array).size() == 2, "寶物: 最多 2 種")
	var tb := RulesGeneral.treasure_bonus([{"item": 1, "type": "79", "value": 10}, {"item": 2, "type": "78", "value": 13},
		{"item": 3, "type": "83", "value": 1}, {"item": 4, "type": "86", "value": 20}], cfg)
	check(int(tb["bonus"]["strFlat"]) == 10 and int(tb["flat"]["agi"]) == 7 and int(tb["stats"]["troops"]) == 7000
		and is_equal_approx(float(tb["bonus"]["evadePct"]), 0.02), "寶物加成: 物攻 flat / 速度 → 敏捷 ×0.5 / 兵量 = 7000 / 迴避 ‰")
	var g_wu := {"id": 777, "name": "某甲", "type": "wu"}
	var s1 := RulesGeneral.skill_for(g_wu, data.gen_skills, data.gen_skill_override)
	check(s1 == RulesGeneral.skill_for(g_wu, data.gen_skills, data.gen_skill_override)
		and (data.gen_skill_by_id[s1]["types"] as Array).has("wu") and bool(data.gen_skill_by_id[s1]["impl"]), "特技分配: 固定 + 類型啱 + 已實作")
	check(RulesGeneral.skill_for({"id": 1, "name": "關羽", "type": "wu"}, data.gen_skills, data.gen_skill_override) == 3, "特技分配: 名將 override (關羽 = 勇猛)")
	var spread := {}
	for i in 200:
		spread[RulesGeneral.skill_for({"id": i + 1000, "name": "x", "type": "wen"}, data.gen_skills, data.gen_skill_override)] = true
	check(spread.size() >= 8, "特技分配: 文官分散 (%d 種)" % spread.size())
	check(RulesGeneral.loyalty_delta(-5, {"loyaltyLossMul": 0.5}) == -2 and RulesGeneral.loyalty_delta(-1, {"loyaltyLossMul": 0.5}) == -1
		and RulesGeneral.loyalty_delta(2, {"loyaltyLossMul": 0.5}) == 2 and RulesGeneral.loyalty_delta(-5, {}) == -5, "忠義: 跌減半 (最少 1)")
	check(is_equal_approx(RulesGeneral.exp_share(0.5, {"expShareAdd": 0.25}), 0.75), "教導: 經驗分成 +25%")
	var sp := RulesGeneral.spell_of({"skills": [[3, 4], [1, 2], [5, 3]]}, cfg["tactics"], data.general_skill_names)
	check(String(sp["name"]) == "落雷" and String(sp["elem"]) == "wind", "同伴術法: 揀最高等級攻擊戰術 (落雷)")
	check(String(RulesGeneral.spell_of({"skills": [[7, 4]]}, cfg["tactics"], data.general_skill_names)["name"]) == "計略", "同伴術法: 冇攻擊戰術 = 計略")
	check(RulesGeneral.skill_pick("ult", 0, 20, 10, 20, true) == "ult" and RulesGeneral.skill_pick("ult", 99, 19, 10, 20, true) == ""
		and RulesGeneral.skill_pick("spell", 10, 0, 10, 20, true) == "spell" and RulesGeneral.skill_pick("spell", 9, 99, 10, 20, true) == ""
		and RulesGeneral.skill_pick("ult", 99, 99, 10, 20, false) == "", "指令: 唔夠 MP/SP 或冷卻中 → 普通攻擊")


# ---------------- B: 將軍令 / 御賜金牌 ----------------
func t_order_bypass(data: GameData) -> void:
	var r := _setup(data, 5, "義理")
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var g := _order_target(sim, "wu")
	check(not g.is_empty(), "將軍令: 搵到高等武將 (%s)" % g.get("name", ""))
	var it := int(data.general_order_item[String(g["name"])])
	check(_find(_survey(sim, pid, "wu"), String(g["name"])).is_empty(), "冇將軍令: %s 唔會出現" % g["name"])
	ch["recruit"].erase("surveyDay")
	RulesShop.add_item(ch["bag"], it, 1)
	var c := _find(_survey(sim, pid, "wu"), String(g["name"]))
	check(not c.is_empty() and String(c["pass"]) == "order", "有將軍令: 出現喺候選 + 標記持令")
	check(String(sim.recruit_view()["cands"][0]["why"]) == "", "有將軍令: 無視等級 (why 空)")
	sim.cmd_recruit_pick(pid, int(c["id"]))
	var m := sim.ent(int(ch["recruit"]["pending"]["mob"]))
	check(not m.is_empty() and RulesShop.count_item(ch["bag"], it) == 1, "將軍令: 開擂台，令未消耗")
	sim.damage(m, 999999, sim.ent(pid))
	check(int(ch["recruit"].get("comp", 0)) != 0 and RulesShop.count_item(ch["bag"], it) == 0, "將軍令: 登用成功 → 令用完即消【原】")
	check(not ch["recruit"].has("pass"), "將軍令: 清 pass 記錄")


func t_order_fail_keeps(data: GameData) -> void:
	var r := _setup(data, 5, "義理")
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var g := _order_target(sim, "wu")
	var it := int(data.general_order_item[String(g["name"])])
	RulesShop.add_item(ch["bag"], it, 1)
	var c := _find(_survey(sim, pid, "wu"), String(g["name"]))
	sim.cmd_recruit_pick(pid, int(c["id"]))
	sim.cmd_recruit_cancel(pid)
	check(RulesShop.count_item(ch["bag"], it) == 1 and int(ch["recruit"].get("comp", 0)) == 0 and not ch["recruit"].has("pass"),
		"將軍令: 考驗失敗唔消耗")
	# 普通登用 (唔需要令) 唔會消耗令
	var r2 := _setup(data, 5, "義理")
	var sim2: Sim = r2[0]
	var ch2: Dictionary = r2[2]
	if data.general_order_item.has("鍾繇"):
		RulesShop.add_item(ch2["bag"], int(data.general_order_item["鍾繇"]), 1)
	var cz := _find(_survey(sim2, int(r2[1]), "wen"), "鍾繇")
	check(not cz.is_empty() and String(cz["pass"]) == "", "條件夠: 唔使用令 (pass 空)")


func t_medal(data: GameData) -> void:
	var r := _setup(data, 5, "義理", 10)          # 子時後 (10 刻) → Tier1 未出現
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var xhd: Dictionary = {}
	for g in data.generals_t1:
		if String(g["name"]) == "夏侯惇":
			xhd = g
	check(not sim.general_visible(xhd), "金牌: 10 刻夏侯惇未出現")
	check(_find(_survey(sim, pid, "wu"), "夏侯惇").is_empty(), "冇金牌: 搵唔到時辰外 + 高等武將")
	ch["recruit"].erase("surveyDay")
	var medal := int(data.gen2_cfg["goldMedal"])
	RulesShop.add_item(ch["bag"], medal, 1)
	var cands := _survey(sim, pid, "wu")
	var c := _find(cands, "夏侯惇")
	check(not c.is_empty() and String(c["pass"]) == "medal", "御賜金牌: 時辰外 + 無視等級/理念都搵到夏侯惇")
	var high := 0
	for x in cands:
		if int(x["lv"]) > 15:
			high += 1
	check(high >= 1, "御賜金牌: 候選包括高等人才")
	sim.cmd_recruit_pick(pid, int(c["id"]))
	sim.damage(sim.ent(int(ch["recruit"]["pending"]["mob"])), 999999, sim.ent(pid))
	check(int(ch["recruit"].get("comp", 0)) != 0 and RulesShop.count_item(ch["bag"], medal) == 0, "御賜金牌: 登用成功 → 金牌用咗")


# ---------------- C: 寶物 / 補品 ----------------
func t_treasure(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var c: Dictionary = r[6]
	var cch: Dictionary = c["ch"]
	var bag: Array = ch["bag"]
	for it in [54807, 54808, 54807, 54801, 54816, 54806]:
		RulesShop.add_item(bag, it, 1)
	var str0 := int(sim._jewel_bonus(cch)["strFlat"])
	var loy0 := int(c["gen"]["loyalty"])
	sim.cmd_companion_treasure(pid, 54807)
	check((cch["genTreasures"] as Array).size() == 1 and int(sim._jewel_bonus(cch)["strFlat"]) == str0 + 5, "寶物: 物攻之石I → 物攻 +5")
	check(int(c["gen"]["loyalty"]) == loy0 + 2 and RulesShop.count_item(bag, 54807) == 1, "寶物: 忠誠 +2 + 扣背包")
	sim.cmd_companion_treasure(pid, 54808)
	check(int(sim._jewel_bonus(cch)["strFlat"]) == str0 + 10 and _recent(msgs, "取代"), "寶物: 物攻之石II 取代 I (舊嘅消失)")
	sim.cmd_companion_treasure(pid, 54807)
	check(int(sim._jewel_bonus(cch)["strFlat"]) == str0 + 10 and RulesShop.count_item(bag, 54807) == 0 and _recent(msgs, "消失"),
		"寶物: 低值同類 → 新嘅消失，加成唔變")
	var agi0 := sim._eff_attr(cch, "agi")
	sim.cmd_companion_treasure(pid, 54801)
	check(is_equal_approx(sim._eff_attr(cch, "agi"), agi0 + 7), "寶物: 速度之石I → 敏捷 +7 (13×0.5)")
	sim.cmd_companion_treasure(pid, 54816)
	check((cch["genTreasures"] as Array).size() == 2 and RulesShop.count_item(bag, 54816) == 1 and _last(msgs).contains("滿"),
		"寶物: 第 3 種 → 格滿，唔扣")
	sim.cmd_companion_treasure(pid, 29042)
	check(_last(msgs).contains("唔係武將寶物"), "寶物: 普通物品唔收")
	var o := sim.ent(pid)
	_put(sim, pid, int(o["x"]) + 8, int(o["y"]))
	sim.cmd_companion_treasure(pid, 54816)
	check(_last(msgs).contains("行近"), "寶物: 要行近")
	var cv := sim.companion_view()
	check((cv["treasures"] as Array).size() == 2 and String(cv["treasures"][0]["type"]) == "物攻", "companion_view: 寶物清單")
	# 登用完跟武將走【原】: 解散後寶物唔返背包
	sim.cmd_companion_dismiss(pid)
	check(RulesShop.count_item(bag, 54808) == 0 and RulesShop.count_item(bag, 54801) == 0, "寶物: 同伴走咗，寶物跟住走")


func t_tonic(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var c: Dictionary = r[6]
	var herb: Dictionary = {}
	for s in data.shops:
		if String(s["id"]) == "herbalist":
			herb = s
	var o := sim.ent(pid)
	var home := Vector2i(int(o["x"]), int(o["y"]))
	_put(sim, pid, int(herb["x"]), int(herb["y"]) + 1)
	ch["gold"] = 1000
	sim.cmd_buy(pid, 30015, 2)
	check(RulesShop.count_item(ch["bag"], 30015) == 2 and int(ch["gold"]) < 1000, "藥膳師: 買到武將體力丸")
	sim.cmd_use_item(pid, 30015)
	check(RulesShop.count_item(ch["bag"], 30015) == 2, "武將補品: 主公自己食唔到")
	_put(sim, pid, home.x, home.y)
	var cch: Dictionary = c["ch"]
	cch["sp"] = 0
	cch["hp"] = 1
	sim._sync_stats(c)
	var loy0 := int(c["gen"]["loyalty"])
	sim.cmd_companion_gift(pid, 30015)
	var want_sp := MathX.js_round(sim._eff_max_sp(cch) * 0.5)
	var want_hp := 1 + MathX.js_round(sim._eff_max_hp(cch) * 0.3)
	check(int(cch["sp"]) == want_sp and int(cch["hp"]) == want_hp, "武將體力丸: 回 SP 50%% + HP 30%% (sp %d/%d hp %d/%d)" % [int(cch["sp"]), want_sp, int(cch["hp"]), want_hp])
	check(int(c["gen"]["loyalty"]) > loy0 and RulesShop.count_item(ch["bag"], 30015) == 1, "武將補品: 忠誠 + / 扣一粒")


# ---------------- D: 特技 ----------------
func _with_skill(c: Dictionary, sid: int) -> void:
	c["ch"]["genSkill"] = sid


func t_skill_self(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var c: Dictionary = r[6]
	var cch: Dictionary = c["ch"]
	check(int(cch["genSkill"]) == 2 and String(sim.companion_view()["skill"]) == "辯才", "鍾繇 = 辯才 (override)")
	_with_skill(c, 0)
	var hp0 := sim._eff_max_hp(cch)
	var agi0 := sim._eff_attr(cch, "agi")
	var sp0 := sim._sp_cost(cch, 20)
	_with_skill(c, 3)
	check(is_equal_approx(float(sim._jewel_bonus(cch)["atkPct"]), 0.15), "勇猛: 物攻 +15%")
	_with_skill(c, 4)
	check(is_equal_approx(float(sim._jewel_bonus(cch)["defPct"]), 0.15), "堅守: 物防 +15%")
	_with_skill(c, 5)
	check(is_equal_approx(float(sim._jewel_bonus(cch)["hitPct"]), 0.10), "神射: 命中 +10%")
	_with_skill(c, 6)
	check(is_equal_approx(float(sim._jewel_bonus(cch)["spellAtkPct"]), 0.20), "奇謀: 術法 +20%")
	_with_skill(c, 7)
	check(sim._eff_max_hp(cch) == MathX.js_round(hp0 * 1.2), "鐵骨: HP 上限 ×1.2")
	_with_skill(c, 10)
	check(sim._sp_cost(cch, 20) == 14 and sp0 == 20, "豪氣: 絕招 SP 20 → 14")
	_with_skill(c, 11)
	check(sim._mp_cost(cch, 10) == 7, "軍師: 術法 MP 10 → 7")
	_with_skill(c, 18)
	check(is_equal_approx(sim._eff_attr(cch, "agi"), agi0 + 8), "疾風: 敏捷 +8")
	_with_skill(c, 21)
	check(sim._jewel_bonus(cch)["atkPct"] == 0.0 and sim._comp_eff(c).is_empty(), "未實作特技 = 冇效果")
	# 回春/冥想/養氣: 戰鬥中都回
	_with_skill(c, 1)
	cch["hp"] = 1
	sim._sync_stats(c)
	c["atk_target"] = 12345
	sim.state["tick"] = 1000
	sim._skill_regen(c, sim.ent(int(r[1])))
	check(int(cch["hp"]) == 1 + MathX.js_round(sim._eff_max_hp(cch) * 0.03), "回春: 每刻回 HP 3% (戰鬥中)")
	_with_skill(c, 8)
	cch["mp"] = 0
	sim._skill_regen(c, sim.ent(int(r[1])))
	check(int(cch["mp"]) >= 1, "冥想: 回 MP")
	_with_skill(c, 9)
	cch["sp"] = 0
	sim._skill_regen(c, sim.ent(int(r[1])))
	check(int(cch["sp"]) >= 1, "養氣: 回 SP")
	sim.state["tick"] = 1001
	cch["sp"] = 0
	sim._skill_regen(c, sim.ent(int(r[1])))
	check(int(cch["sp"]) == 0, "特技回復: 每 regenTicks 先回")


func t_skill_owner(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var c: Dictionary = r[6]
	var o := sim.ent(pid)
	_with_skill(c, 12)
	check(is_equal_approx(float(sim._jewel_bonus(ch)["atkPct"]), 0.05), "督戰: 同伴附近主公物攻 +5%")
	var p := sim._free_near(int(o["x"]) + 10, int(o["y"]))
	_put(sim, int(c["id"]), p.x, p.y)
	check(is_equal_approx(float(sim._jewel_bonus(ch)["atkPct"]), 0.0), "督戰: 同伴 >4 格冇效")
	var q := sim._free_near(int(o["x"]), int(o["y"]))
	_put(sim, int(c["id"]), q.x, q.y)
	_with_skill(c, 13)
	check(is_equal_approx(float(sim._jewel_bonus(ch)["defPct"]), 0.05), "護主: 主公物防 +5%")
	_with_skill(c, 14)
	ch["hp"] = 1
	sim._sync_stats(o)
	sim.state["tick"] = 2000
	sim._skill_regen(c, o)
	check(int(ch["hp"]) > 1 and int(o["hp"]) == int(ch["hp"]), "醫術: 主公附近每刻回 HP")
	_with_skill(c, 20)
	check(sim._office_ap_cost(ch) == MathX.js_round(int(data.office["apCost"]) * 0.5), "政才: 官令行動力減半")
	_with_skill(c, 3)
	check(sim._office_ap_cost(ch) == int(data.office["apCost"]), "冇政才: 行動力原價")
	# 辯才: 發話唔扣飲水度
	_with_skill(c, 2)
	ch["thirst"] = 50
	check(sim._sip_thirst(o) and int(ch["thirst"]) == 50, "辯才: 發話唔扣飲水度【原例】")
	ch["thirst"] = 0
	check(not sim._sip_thirst(o), "辯才: 飲水度 0 照樣口渴")
	_with_skill(c, 3)
	ch["thirst"] = 50
	sim._sip_thirst(o)
	check(int(ch["thirst"]) < 50, "冇辯才: 照扣飲水度")


func t_skill_misc(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var c: Dictionary = r[6]
	var gn: Dictionary = c["gen"]
	_with_skill(c, 16)
	gn["loyalty"] = 60
	sim._loyalty_change(c, -10)
	check(int(gn["loyalty"]) == 55, "忠義: -10 → -5")
	_with_skill(c, 17)
	RulesShop.add_item(ch["bag"], 29042, 1)
	sim.cmd_companion_gift(pid, 29042)
	check(int(gn["loyalty"]) == 55 + 2 + 2, "仁德: 送補品忠誠 +4")
	_with_skill(c, 19)
	var cid := int(c["id"])
	sim._kill_player(c)
	check(int(gn["loyalty"]) == 59 and not sim.ent(cid).is_empty(), "堅忍: 倒下唔扣忠誠")
	_with_skill(c, 3)
	sim._kill_player(c)
	check(int(gn["loyalty"]) == 59 + int(data.recruit_cfg["loyalty"]["ko"]), "冇堅忍: 倒下扣忠誠")
	# S02b: 隊伍經驗池按傷害分 — 教導特技暫時無效果(留返 Spec09)，同伴自己出晒力就自己攞晒經驗
	_put(sim, cid, int(sim.ent(pid)["x"]) + 1, int(sim.ent(pid)["y"]))
	_with_skill(c, 15)
	ch["level"] = 1
	ch["exp"] = 0
	c["ch"]["level"] = 1
	c["ch"]["exp"] = 0
	var m := _mob_at(sim, int(sim.ent(pid)["x"]) + 3, int(sim.ent(pid)["y"]), 10)
	var d := data.mob_def(int(m["mob"]["def"]))
	sim.damage(m, 99999, c)
	check(int(ch["exp"]) == 0, "S02b: 主公冇分傷害 = 冇經驗")
	check(int(c["ch"]["exp"]) == int(d["exp"]), "S02b: 同伴自己攞晒經驗 (%d)" % int(c["ch"]["exp"]))


# ---------------- E: 絕招 / 術法指令 ----------------
func t_comp_ult(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var evs: Array = r[4]
	var c: Dictionary = r[6]
	var cch: Dictionary = c["ch"]
	_with_skill(c, 3)
	sim.cmd_companion_order(pid, "ult")
	check(String(c["gen"]["order"]) == "ult", "指令: 絕招攻擊")
	cch["sp"] = 100
	var m := _mob_at(sim, int(c["x"]) + 1, int(c["y"]))
	var m2 := _mob_at(sim, int(c["x"]), int(c["y"]) + 1)
	var used := 0
	for i in 60:
		sim.step()
		for ev in evs:
			if String(ev.get("k", "")) == "comp_skill" and String(ev["skill"]) == "ult":
				used += 1
		evs.clear()
		if used > 0:
			break
	check(used == 1 and int(cch["sp"]) == 80, "絕招: 夠 SP 自動出招，扣 20 SP (sp %d)" % int(cch["sp"]))
	check(int(m["hp"]) < 5000 and int(m2["hp"]) < 5000, "絕招: 範圍打中 2 隻")
	check(int(c["gen"]["skillCd"]) > sim.tick, "絕招: 入冷卻")
	# SP 唔夠 → 普通攻擊【原】
	cch["sp"] = 0
	c["gen"]["skillCd"] = 0
	var normal := 0
	var ult := 0
	for i in 60:
		sim.step()
	for ev in evs:
		if String(ev.get("k", "")) == "hit" and int(ev["src"]) == int(c["id"]):
			normal += 1
		if String(ev.get("k", "")) == "comp_skill":
			ult += 1
	check(normal > 0 and ult == 0, "絕招: SP 唔夠 → 普通攻擊 (hit %d)" % normal)


func t_comp_spell(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var evs: Array = r[4]
	var c: Dictionary = r[6]
	var cch: Dictionary = c["ch"]
	_with_skill(c, 3)
	sim.cmd_companion_order(pid, "spell")
	cch["mp"] = 100
	var m := _mob_at(sim, int(c["x"]) + 3, int(c["y"]))
	var sp := sim._comp_spell(c)
	var need := RulesGeneral.spell_mp(int(cch["level"]), data.gen2_cfg["spell"])
	var hits := 0
	var elem := ""
	for i in 60:
		sim.step()
		for ev in evs:
			if String(ev.get("k", "")) == "spell_hit" and int(ev["src"]) == int(c["id"]):
				hits += 1
				elem = String(ev["elem"])
		evs.clear()
		if hits > 0:
			break
	check(hits == 1 and int(cch["mp"]) == 100 - need and int(m["hp"]) < 5000, "術法: 5 格內出招，扣 %d MP" % need)
	check(elem == String(sp["elem"]), "術法: 元素跟武將戰術 (%s %s)" % [sp["name"], elem])
	# 協助主公: 主公打緊另一隻 → 同伴轉打嗰隻
	var m2 := _mob_at(sim, int(sim.ent(pid)["x"]) + 2, int(sim.ent(pid)["y"]) + 2)
	sim.ent(pid)["atk_target"] = int(m2["id"])
	sim.step()
	check(int(c["atk_target"]) == int(m2["id"]), "術法指令: 優先協助主公目標")


# ---------------- UI 讀取 / 存檔 ----------------
func t_view(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var cv := sim.companion_view()
	check(cv.has("skill") and cv.has("skillDesc") and cv.has("spell") and cv.has("treasures") and cv.has("maxMp") and cv.has("maxSp"),
		"companion_view: 特技/術法/寶物/MP/SP")
	check(String(cv["skillDesc"]) != "" and String(cv["spell"]) != "", "companion_view: 特技說明 + 術法名")
	var r2 := _setup(data, 5, "義理")
	var sim2: Sim = r2[0]
	sim2.cmd_recruit_survey(int(r2[1]), "wen")
	var v := sim2.recruit_view()
	check(not (v["cands"] as Array).is_empty() and v["cands"][0].has("pass") and v["cands"][0].has("skill"), "recruit_view: 候選有 pass/特技")


func t_save(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	RulesShop.add_item(ch["bag"], 54808, 1)
	sim.cmd_companion_treasure(pid, 54808)
	sim.cmd_companion_order(pid, "spell")
	for i in 20:
		sim.step()
	var s1 := sim.save_string()
	var l := Sim.load_string(data, s1)
	check(l.save_string() == s1, "存檔: 寶物/特技/指令 roundtrip")
	check((l.companion_view()["treasures"] as Array).size() == 1 and String(l.companion_view()["order"]) == "spell", "存檔: 寶物 + 術法指令保留")
	for i in 40:
		sim.step()
		l.step()
	check(l.save_string() == sim.save_string(), "存檔: 讀返之後一齊行 40 tick 一樣")
	# 決定性: 同種子同操作 → 同結果
	var a := _comp_setup(data, 77)
	var b := _comp_setup(data, 77)
	for x in [a, b]:
		(x[0] as Sim).cmd_companion_order(int(x[1]), "ult")
		x[6]["ch"]["sp"] = 100
		_mob_at(x[0], int(x[6]["x"]) + 1, int(x[6]["y"]))
		for i in 80:
			(x[0] as Sim).step()
	check((a[0] as Sim).save_string() == (b[0] as Sim).save_string(), "決定性: 絕招戰鬥同種子一樣")


# 舊存檔 (Step 13.5 同伴冇 genSkill/genTreasures) 照讀照行
func t_old_save(data: GameData) -> void:
	var r := _comp_setup(data)
	var sim: Sim = r[0]
	var c: Dictionary = r[6]
	c["ch"].erase("genSkill")
	c["ch"].erase("genTreasures")
	c["gen"].erase("skillCd")
	var l := Sim.load_string(data, sim.save_string())
	var cv := l.companion_view()
	check(not cv.is_empty() and String(cv["skill"]) == "" and (cv["treasures"] as Array).is_empty(), "舊存檔: 同伴冇特技/寶物照顯示")
	l.cmd_companion_order(int(r[1]), "ult")
	for i in 30:
		l.step()
	check(not l.companion_view().is_empty(), "舊存檔: 絕招指令照行")
