extends SceneTree
# 職業測試 (S02c, spec 02): 仕女開放 —— 武器 18 系對應 / 特技「開鎖」導師任務學習 + 使用 / 初階三招絕招。
# 跑: Godot --headless --path client --script tests/run_class.gd

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_shinu_enabled(data)
	t_weapon_families(data)
	t_shinu_ultimates(data)
	t_daoshi_ultimates(data)
	t_wunu_ultimates(data)
	t_bianshi_ultimates(data)
	t_bianshi_enabled(data)
	t_unlock_learn(data)
	t_class_skill_use(data)
	t_chaodu_learn(data)
	t_chaodu_use(data)
	t_yinxing_learn(data)
	t_yinxing_use(data)
	t_qieting_learn(data)
	t_qieting_use(data)
	t_arrow_consume(data)
	print("[TEST] class: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y


# wealthier. weapons cat_label 對應 (cat 1~18)
const CAT_TO_LABEL := {1: "刀", 2: "錘", 3: "槍矛", 4: "劍", 5: "爪", 6: "環",
	7: "扇", 8: "筆", 9: "弩", 10: "鞭", 11: "棍杖", 12: "卷軸",
	13: "幡", 14: "拂塵", 15: "符咒", 16: "袖帶", 17: "匕首", 18: "琴"}


func t_shinu_enabled(data: GameData) -> void:
	check(bool(data.classes["shinu"].get("enabled", false)), "仕女已開放")
	check(bool(data.classes["yishi"].get("enabled", false)), "義士仍然開放")
	check(bool(data.classes["daoshi"].get("enabled", false)), "道士維持開放")
	check(bool(data.classes["wunu"].get("enabled", false)), "巫女已開放")
	check(bool(data.classes["bianshi"].get("enabled", false)), "辯士已開放")
	check(not bool(data.classes["meinu"].get("enabled", false)), "美女未開放")
	var st: Dictionary = data.starter.get("shinu", {})
	check(not st.is_empty(), "仕女有起始裝備")
	check(int(data.cats.get(int(st.get("weapon", 0)), 0)) == 4, "仕女起始武器係劍系 (cat 4)")
	check(int(st["gold"]) >= 100, "仕女起始金錢正常")


func t_weapon_families(data: GameData) -> void:
	# 六職武器系 -> cat 集合（items.json cat_label 同 classes.weapons 對應）
	var want := {"yishi": [1, 2, 3], "shinu": [4, 5, 6], "wunu": [10, 11, 12],
		"bianshi": [7, 8, 9], "daoshi": [13, 14, 15], "meinu": [16, 17, 18]}
	for cid in want:
		var cls: Dictionary = data.classes[cid]
		var labels: Array = cls.get("weapons", [])
		var cats: Array = []
		for l in labels:
			for c in CAT_TO_LABEL:
				if String(CAT_TO_LABEL[c]) == String(l):
					cats.append(int(c))
		cats.sort()
		check(cats.size() == 3, "%s 武器系有 3 類" % cls.get("name", cid))
		var exp: Array = want[cid]
		exp.sort()
		var ok := cats.size() == exp.size()
		if ok:
			for i in cats.size():
				if int(cats[i]) != int(exp[i]):
					ok = false
		check(ok, "%s 武器 cat = %s (想 %s)" % [cls.get("name", cid), str(cats), str(exp)])
	# 每系至少要有一件武器道具 (撳第一件嚟驗證 cat_label 有解)
	for c in CAT_TO_LABEL:
		var found := false
		for iid in data.item_ids:
			if int(data.cats.get(int(iid), 0)) == int(c):
				found = true
				break
		check(found, "cat %d (%s) 有武器道具" % [int(c), CAT_TO_LABEL[c]])


func t_shinu_ultimates(data: GameData) -> void:
	check(data.ult_by_id.has("huxiao") and data.ult_by_id.has("jinhu") and data.ult_by_id.has("jinghua"), "仕女初階三招已定義")
	var tmpl := {"huxiao": {"tier": 1, "mult": 2.0, "range": 2, "mp": 15, "sp": 20, "cd": 300},
		"jinhu": {"tier": 2, "mult": 2.5, "range": 2, "mp": 20, "sp": 30, "cd": 360},
		"jinghua": {"tier": 3, "mult": 3.0, "range": 3, "mp": 25, "sp": 40, "cd": 420}}
	for uid in tmpl:
		var u: Dictionary = data.ult_by_id.get(String(uid), {})
		var t: Dictionary = tmpl[String(uid)]
		check(String(u.get("class", "")) == "shinu", "%s 係仕女招式" % u.get("name", uid))
		check(int(u.get("tier", 0)) == int(t["tier"]), "%s tier = %d" % [u.get("name", uid), int(t["tier"])])
		check(absf(float(u.get("mult", 0)) - float(t["mult"])) < 0.001, "%s 倍率 x%.1f" % [u.get("name", uid), float(t["mult"])])
		check(int(u.get("range", 0)) == int(t["range"]), "%s 範圍 %d" % [u.get("name", uid), int(t["range"])])
		check(int(u.get("mp", 0)) == int(t["mp"]) and int(u.get("sp", 0)) == int(t["sp"]), "%s MP/SP 消耗" % u.get("name", uid))
		check(int(u.get("cd", 0)) == int(t["cd"]), "%s 冷卻 %d" % [u.get("name", uid), int(t["cd"])])
		check(int(u.get("weaponCat", 0)) == 6, "%s 需要環武器 (cat 6)" % u.get("name", uid))
	# 初階三招 = 無職階/等級要求
	var ch := {"tier": 0, "level": 1}
	check(bool(RulesClass.ultimate_usable(ch, data.ult_by_id["huxiao"])["ok"]), "一招: 初階 Lv1 用得")
	check(bool(RulesClass.ultimate_usable(ch, data.ult_by_id["jinghua"])["ok"]), "三招: 初階都用得 (冇 reqTier)")
	# 四招起先要職階 (同義士機制)
	var ch4 := {"tier": 0, "level": 50}
	check(not bool(RulesClass.ultimate_usable(ch4, data.ult_by_id["fengyi"])["ok"]), "四招: 未二轉用唔到 (仕女都受)")



func t_unlock_learn(data: GameData) -> void:
	var sim := Sim.new(data, 31)
	var id := sim.spawn_player("t", "shinu")
	var ch: Dictionary = sim.player_ch()
	# 導師 minLevel 5: Lv1 睇唔到
	check(not bool((sim.state["quest_npcs"] as Dictionary).get("shinu_master", {}).get("visible", false)), "Lv1: 睇唔到黃師姐")
	ch["level"] = 5
	sim._sync_stats(sim.ent(id))
	sim._sync_quest_npcs()
	check(bool((sim.state["quest_npcs"] as Dictionary).get("shinu_master", {}).get("visible", false)), "Lv5: 黃師姐出現")
	# 未學 → 用唔到
	sim.cmd_use_skill(id, "unlock")
	check(String(ch.get("classSkill", "")) == "", "未學開鎖: 冇學到嘢")
	check(bool(RulesClassSkill.can_use(data, ch, "unlock").get("ok", false)) == false, "未學開鎖: Rules 擋")
	# 接任務 + 答題
	var npc: Dictionary = data.quest_npcs["shinu_master"]
	_put(sim, id, int(npc["x"]) + 1, int(npc["y"]))
	sim.cmd_quest_talk(id, "shinu_master")
	check((ch.get("quests", {}) as Dictionary).has("skill_unlock_shinu"), "傾偈 = 接咗開鎖任務")
	sim.cmd_quest_answer(id, "skill_unlock_shinu", 0)          # 答錯
	check(not bool(ch.get("questDone", {}).get("skill_unlock_shinu", false)), "答錯: 未完成")
	sim.cmd_quest_answer(id, "skill_unlock_shinu", 1)          # 答啱
	check(bool(ch.get("questDone", {}).get("skill_unlock_shinu", false)), "答啱: 任務完成")
	check(String(ch.get("classSkill", "")) == "unlock", "任務獎勵: 學識開鎖")
	check(RulesClassSkill.learned(ch, "unlock"), "learned() 讀到")
	# 非仕女學唔到 (pre classId 擋)
	var sim2 := Sim.new(data, 32)
	var id2 := sim2.spawn_player("t2", "yishi")
	var ch2: Dictionary = sim2.player_ch()
	ch2["level"] = 5
	sim2._sync_stats(sim2.ent(id2))
	sim2._sync_quest_npcs()
	var npc2: Dictionary = data.quest_npcs["shinu_master"]
	_put(sim2, id2, int(npc2["x"]) + 1, int(npc2["y"]))
	sim2.cmd_quest_talk(id2, "shinu_master")
	check(not (ch2.get("quests", {}) as Dictionary).has("skill_unlock_shinu"), "義士同黃師姐傾偈: 唔接開鎖任務")
	# 存檔 roundtrip: classSkill 保留
	var s := sim.save_string()
	var sim3 := Sim.load_string(data, s)
	check(sim3 != null and String(sim3.player_ch().get("classSkill", "")) == "unlock", "存檔 roundtrip: classSkill 保留")


func t_class_skill_use(data: GameData) -> void:
	var sim := Sim.new(data, 34)
	var id := sim.spawn_player("t", "shinu")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 5
	sim._sync_stats(sim.ent(id))
	ch["classSkill"] = "unlock"
	_put(sim, id, 60, 60)                                   # 野外
	# 附近冇寶箱 → 提示
	sim.cmd_use_skill(id, "unlock")
	check(String(ch.get("classSkill", "")) == "unlock", "用錯唔會學走特技")
	# 擺一個鎖住寶箱喺隔籬 → unlock_open 事件 + 面板掣路徑
	var ents: Dictionary = sim.state["ents"]
	ents[9000] = {"id": 9000, "kind": "chest", "name": "試煉寶箱", "x": 60, "y": 61, "locked": true, "key": 1}
	var got_open: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "unlock_open" and int(ev.get("chest", 0)) == 9000:
			got_open.append(true))
	sim.cmd_use_skill(id, "unlock")
	check(not got_open.is_empty(), "有寶箱: 發出 unlock_open 事件")
	# 揀錯鑰匙 → 寶箱仲鎖住；揀啱 → 開 + unlock_done
	sim.cmd_skill_pick(id, 9000, 0)
	check(bool(ents[9000].get("locked", true)), "揀錯: 寶箱未開")
	var got_done: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "unlock_done" and bool(ev.get("ok", false)):
			got_done.append(true))
	sim.cmd_skill_pick(id, 9000, 1)
	check(not bool(ents[9000].get("locked", true)), "揀啱: 寶箱開咗")
	check(not got_done.is_empty(), "開箱: 發出 unlock_done 事件")
	# 開完再用 → 提示已開
	sim.cmd_skill_pick(id, 9000, 1)
	check(not bool(ents[9000].get("locked", true)), "開完再撳: 唔會翻開")


# ===== 道士 (S02c): 快期三招絕招 (符咒 cat 15) =====
func t_daoshi_ultimates(data: GameData) -> void:
	check(data.ult_by_id.has("xuwu") and data.ult_by_id.has("ruhuan") and data.ult_by_id.has("shenyou"), "道士初階三招已定義")
	var tmpl := {"xuwu": {"tier": 1, "mult": 2.0, "range": 2, "mp": 15, "sp": 20, "cd": 300},
		"ruhuan": {"tier": 2, "mult": 2.5, "range": 2, "mp": 20, "sp": 30, "cd": 360},
		"shenyou": {"tier": 3, "mult": 3.0, "range": 3, "mp": 25, "sp": 40, "cd": 420}}
	for uid in tmpl:
		var u: Dictionary = data.ult_by_id.get(String(uid), {})
		var t: Dictionary = tmpl[String(uid)]
		check(String(u.get("class", "")) == "daoshi", "%s 係道士招式" % u.get("name", uid))
		check(int(u.get("tier", 0)) == int(t["tier"]), "%s tier = %d" % [u.get("name", uid), int(t["tier"])])
		check(absf(float(u.get("mult", 0)) - float(t["mult"])) < 0.001, "%s 倍率 x%.1f" % [u.get("name", uid), float(t["mult"])])
		check(int(u.get("range", 0)) == int(t["range"]), "%s 範圍 %d" % [u.get("name", uid), int(t["range"])])
		check(int(u.get("mp", 0)) == int(t["mp"]) and int(u.get("sp", 0)) == int(t["sp"]), "%s MP/SP 消耗" % u.get("name", uid))
		check(int(u.get("cd", 0)) == int(t["cd"]), "%s 冷卻 %d" % [u.get("name", uid), int(t["cd"])])
		check(int(u.get("weaponCat", 0)) == 15, "%s 需要符咒武器 (cat 15)" % u.get("name", uid))
	# 初階三招 = 無職階/等級要求
	var ch := {"tier": 0, "level": 1}
	check(bool(RulesClass.ultimate_usable(ch, data.ult_by_id["xuwu"])["ok"]), "道士一招: 初階 Lv1 用得")
	check(bool(RulesClass.ultimate_usable(ch, data.ult_by_id["shenyou"])["ok"]), "道士三招: 初階都用得 (冇 reqTier)")


func t_chaodu_learn(data: GameData) -> void:
	var sim := Sim.new(data, 36)
	var id := sim.spawn_player("t", "daoshi")
	var ch: Dictionary = sim.player_ch()
	check(not bool((sim.state["quest_npcs"] as Dictionary).get("daoshi_master", {}).get("visible", false)), "Lv1: 睇唔到玄真道人")
	ch["level"] = 5
	sim._sync_stats(sim.ent(id))
	sim._sync_quest_npcs()
	check(bool((sim.state["quest_npcs"] as Dictionary).get("daoshi_master", {}).get("visible", false)), "Lv5: 玄真道人出現")
	sim.cmd_use_skill(id, "chaodu")
	check(String(ch.get("classSkill", "")) == "", "未學超渡: 冇學到嘢")
	check(bool(RulesClassSkill.can_use(data, ch, "chaodu").get("ok", false)) == false, "未學超渡: Rules 擋")
	var npc: Dictionary = data.quest_npcs["daoshi_master"]
	_put(sim, id, int(npc["x"]) + 1, int(npc["y"]))
	sim.cmd_quest_talk(id, "daoshi_master")
	check((ch.get("quests", {}) as Dictionary).has("skill_unlock_daoshi"), "傾偈 = 接咗超渡任務")
	sim.cmd_quest_answer(id, "skill_unlock_daoshi", 0)          # 答錯
	check(not bool(ch.get("questDone", {}).get("skill_unlock_daoshi", false)), "答錯: 未完成")
	sim.cmd_quest_answer(id, "skill_unlock_daoshi", 1)          # 答啱
	check(bool(ch.get("questDone", {}).get("skill_unlock_daoshi", false)), "答啱: 任務完成")
	check(String(ch.get("classSkill", "")) == "chaodu", "任務獎勵: 學識超渡")
	check(RulesClassSkill.learned(ch, "chaodu"), "learned() 讀到")
	# 非道士學唔到 (pre classId 擋)
	var sim2 := Sim.new(data, 37)
	var id2 := sim2.spawn_player("t2", "yishi")
	var ch2: Dictionary = sim2.player_ch()
	ch2["level"] = 5
	sim2._sync_stats(sim2.ent(id2))
	sim2._sync_quest_npcs()
	var npc2: Dictionary = data.quest_npcs["daoshi_master"]
	_put(sim2, id2, int(npc2["x"]) + 1, int(npc2["y"]))
	sim2.cmd_quest_talk(id2, "daoshi_master")
	check(not (ch2.get("quests", {}) as Dictionary).has("skill_unlock_daoshi"), "義士同玄真道人傾偈: 唔接超渡任務")
	# 存檔 roundtrip: classSkill 保留
	var s := sim.save_string()
	var sim3 := Sim.load_string(data, s)
	check(sim3 != null and String(sim3.player_ch().get("classSkill", "")) == "chaodu", "存檔 roundtrip: classSkill 保留")


func t_chaodu_use(data: GameData) -> void:
	var sim := Sim.new(data, 38)
	var id := sim.spawn_player("t", "daoshi")
	var pe: Dictionary = sim.ent(id)
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 5
	ch["classSkill"] = "chaodu"
	var g: Dictionary = data.generals[0]
	var c0: Dictionary = sim._spawn_companion(pe, g)          # 同伴跟住主公
	var cid := int(c0["id"])
	var c: Dictionary = sim.ent(cid)
	_put(sim, id, 60, 60)                                      # 野外 (唔受安全區)
	var q := sim._free_near(60, 60)
	_put(sim, cid, q.x, q.y)
	sim._sync_stats(pe)
	sim._sync_stats(c)
	# 冇倒下 → 用超渡: 提示, 唔會扣血
	var mh := int(ch["hp"])
	sim.cmd_use_skill(id, "chaodu")
	check(int(ch["hp"]) == mh, "冇同伴倒下: 超渡唔會扣血")
	# 同伴倒下 (唔會死/唔會飛返客棧, 原地 down)
	var loy := int(c["gen"]["loyalty"])
	var cpos_x := int(c["x"])
	var cpos_y := int(c["y"])
	sim._kill_player(c)
	c = sim.ent(cid)
	check(int(c["hp"]) == 0 and bool(c.get("down", false)), "同伴被打低: 進入倒下狀態")
	check(int(c["x"]) == cpos_x and int(c["y"]) == cpos_y, "同伴倒下: 留喺原地 (等超渡)")
	# 靈力唔夠 → 擋
	ch["hp"] = 5000
	ch["mp"] = 1
	sim._sync_stats(pe)
	var got_no_mp: Array = []
	sim.cmd_use_skill(id, "chaodu")
	check(bool(sim.ent(cid).get("down", false)) and int(sim.ent(cid)["hp"]) == 0, "靈力唔夠: 同伴未復活 (仍倒下)")
	# 夠 MP → 復活 + 扣自己
	ch["mp"] = 1000
	ch["hp"] = 5000
	sim._sync_stats(pe)
	var max_hp := int(pe["max_hp"])
	var max_mp := RulesStats.max_mp(int(ch["level"]), ch["attrs"])
	var chan := int(ch["hp"])
	var got_revive: Array = [false, 0]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "revive" and int(ev.get("id", 0)) == cid:
			got_revive[0] = true
			got_revive[1] = int(ev.get("id", 0)))
	c = sim.ent(cid)
	sim.cmd_use_skill(id, "chaodu")
	c = sim.ent(cid)
	check(not bool(c.get("down", false)) and int(c["hp"]) == int(c["max_hp"]), "超渡: 同伴起返身回滿血")
	check(bool(got_revive[0]) and got_revive[1] == cid, "超渡: 發出 revive 事件")
	check(int(ch["hp"]) == chan - int(ceil(max_hp * 0.2)), "超渡: 扣自己 HP 20%%")
	check(int(ch["mp"]) == 1000 - int(ceil(max_mp * 0.3)), "超渡: 扣自己 MP 30%%")
	check(int(c["gen"]["loyalty"]) == loy, "超渡復活: 忠誠唔跌")
	# 再救冇倒下 → 冇嘢發生
	var chan2 := int(ch["hp"])
	sim.cmd_use_skill(id, "chaodu")
	check(int(ch["hp"]) == chan2, "同伴已救返: 唔會再扣血")
	# 超時未救兜底: 重新打倒, downAt 推返去 → 返客棧 + 忠誠 -ko
	sim._kill_player(c)
	c = sim.ent(cid)
	c["downAt"] = sim.state["tick"] - int(data.world["combat"]["compDownTicks"]) - 10
	var loy2 := int(c["gen"]["loyalty"])
	var inn := sim.nearest_inn(sim.map_id_at(int(c["x"]), int(c["y"])))
	sim._down_bailout()
	var c_after := sim.ent(cid)
	check(not bool(c_after.get("down", false)) and int(c_after["hp"]) == int(c_after["max_hp"]), "超時未救: 退返客棧回滿")
	check(int(c_after["x"]) == int(inn["x"]) and int(c_after["y"]) == int(inn["y"]), "超時未救: 返最近客棧")
	check(int(c_after["gen"]["loyalty"]) < loy2, "超時未救: 忠誠扣減 (忠義特技會減半)")

# ===== 巫女 (S02c): 初階三招絕招 (卷軸 cat 12) =====
func t_wunu_ultimates(data: GameData) -> void:
	check(data.ult_by_id.has("candeng") and data.ult_by_id.has("danchan") and data.ult_by_id.has("guiku"), "巫女初階三招已定義")
	var tmpl := {"candeng": {"tier": 1, "mult": 2.0, "range": 2, "mp": 15, "sp": 20, "cd": 300},
		"danchan": {"tier": 2, "mult": 2.5, "range": 2, "mp": 20, "sp": 30, "cd": 360},
		"guiku": {"tier": 3, "mult": 3.0, "range": 3, "mp": 25, "sp": 40, "cd": 420}}
	for uid in tmpl:
		var u: Dictionary = data.ult_by_id.get(String(uid), {})
		var t: Dictionary = tmpl[String(uid)]
		check(String(u.get("class", "")) == "wunu", "%s 係巫女招式" % u.get("name", uid))
		check(int(u.get("tier", 0)) == int(t["tier"]), "%s tier = %d" % [u.get("name", uid), int(t["tier"])])
		check(absf(float(u.get("mult", 0)) - float(t["mult"])) < 0.001, "%s 倍率 x%.1f" % [u.get("name", uid), float(t["mult"])])
		check(int(u.get("range", 0)) == int(t["range"]), "%s 範圍 %d" % [u.get("name", uid), int(t["range"])])
		check(int(u.get("mp", 0)) == int(t["mp"]) and int(u.get("sp", 0)) == int(t["sp"]), "%s MP/SP 消耗" % u.get("name", uid))
		check(int(u.get("cd", 0)) == int(t["cd"]), "%s 冷卻 %d" % [u.get("name", uid), int(t["cd"])])
		check(int(u.get("weaponCat", 0)) == 12, "%s 需要卷軸武器 (cat 12)" % u.get("name", uid))
	# 初階三招 = 無職階/等級要求
	var ch := {"tier": 0, "level": 1}
	check(bool(RulesClass.ultimate_usable(ch, data.ult_by_id["candeng"])["ok"]), "巫女一招: 初階 Lv1 用得")
	check(bool(RulesClass.ultimate_usable(ch, data.ult_by_id["guiku"])["ok"]), "巫女三招: 初階都用得 (冇 reqTier)")


# ===== 巫女特技「潛行」: 導師學習 =====
func t_yinxing_learn(data: GameData) -> void:
	var sim := Sim.new(data, 41)
	var id := sim.spawn_player("t", "wunu")
	var ch: Dictionary = sim.player_ch()
	check(not bool((sim.state["quest_npcs"] as Dictionary).get("wunu_master", {}).get("visible", false)), "Lv1: 睇唔到巫姬婆")
	ch["level"] = 5
	sim._sync_stats(sim.ent(id))
	sim._sync_quest_npcs()
	check(bool((sim.state["quest_npcs"] as Dictionary).get("wunu_master", {}).get("visible", false)), "Lv5: 巫姬婆出現")
	check(int(data.starter.get("wunu", {}).get("weapon", 0)) == 13038, "巫女起始武器係卷軸 (13038)")
	sim.cmd_use_skill(id, "yinxing")
	check(String(ch.get("classSkill", "")) == "", "未學潛行: 冇學到嘢")
	check(bool(RulesClassSkill.can_use(data, ch, "yinxing").get("ok", false)) == false, "未學潛行: Rules 擋")
	var npc: Dictionary = data.quest_npcs["wunu_master"]
	_put(sim, id, int(npc["x"]) + 1, int(npc["y"]))
	sim.cmd_quest_talk(id, "wunu_master")
	check((ch.get("quests", {}) as Dictionary).has("skill_unlock_wunu"), "傾偈 = 接咗潛行任務")
	sim.cmd_quest_answer(id, "skill_unlock_wunu", 0)          # 答錯
	check(not bool(ch.get("questDone", {}).get("skill_unlock_wunu", false)), "答錯: 未完成")
	sim.cmd_quest_answer(id, "skill_unlock_wunu", 1)          # 答啱
	check(bool(ch.get("questDone", {}).get("skill_unlock_wunu", false)), "答啱: 任務完成")
	check(String(ch.get("classSkill", "")) == "yinxing", "任務獎勵: 學識潛行")
	check(RulesClassSkill.learned(ch, "yinxing"), "learned() 讀到")
	# 非巫女學唔到 (pre classId 擋)
	var sim2 := Sim.new(data, 42)
	var id2 := sim2.spawn_player("t2", "yishi")
	var ch2: Dictionary = sim2.player_ch()
	ch2["level"] = 5
	sim2._sync_stats(sim2.ent(id2))
	sim2._sync_quest_npcs()
	var npc2: Dictionary = data.quest_npcs["wunu_master"]
	_put(sim2, id2, int(npc2["x"]) + 1, int(npc2["y"]))
	sim2.cmd_quest_talk(id2, "wunu_master")
	check(not (ch2.get("quests", {}) as Dictionary).has("skill_unlock_wunu"), "義士同巫姬婆傾偈: 唔接潛行任務")
	# 存檔 roundtrip: classSkill + stealthCd 保留
	var s := sim.save_string()
	var sim3 := Sim.load_string(data, s)
	check(sim3 != null and String(sim3.player_ch().get("classSkill", "")) == "yinxing", "存檔 roundtrip: classSkill 保留")


# ===== 巫女特技「潛行」: 行車 QTE + 潛行避免仇恨 =====
func t_yinxing_use(data: GameData) -> void:
	var sim := Sim.new(data, 43)
	var id := sim.spawn_player("t", "wunu")
	var pe: Dictionary = sim.ent(id)
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 5
	ch["classSkill"] = "yinxing"
	_put(sim, id, 60, 60)                                     # 野外
	sim._sync_stats(pe)
	# 用一次: 開行車 QTE (emit stealth_open + 記錄 stealthCd)
	var got_open: Array = [false, 0]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "stealth_open" and int(ev.get("dst", 0)) == id:
			got_open[0] = true
			got_open[1] = int(ev.get("gaps", 0)))
	sim.cmd_use_skill(id, "yinxing")
	check(bool(got_open[0]) and got_open[1] == RulesStealth.GAP_COUNT, "潛行: 發出 stealth_open (3 卡車)")
	var g: Dictionary = ch.get("stealthGame", {})
	check(not g.is_empty(), "潛行: 起咗行車小遊戲")
	# 未開始前撳穿 -> 而家喺 pattern 週期, gap0 window 未到 -> fail
	var pat: Array = g["pattern"]
	var start := int(g["start"])
	var crossed0 := 0
	# 逐卡車喺 gap window 入面穿 -> 成功
	var got_done: Array = [false, 0]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "stealth_done" and int(ev.get("dst", 0)) == id:
			got_done[0] = true
			got_done[1] = int(ev.get("until", 0)))
	for i in RulesStealth.GAP_COUNT:
		var off := int(pat[i])
		sim.state["tick"] = start + i * RulesStealth.CART_PERIOD + off
		sim.cmd_stealth_cross(id)
	check(bool(got_done[0]), "穿晒 %d 卡: 發出 stealth_done" % RulesStealth.GAP_COUNT)
	check((ch.get("stealthGame", {}) as Dictionary).is_empty(), "穿晒: 小遊戲完結")
	check(RulesSpell.has(ch.get("status", {}), "stealth", sim.tick), "穿晒: 入咗潛行狀態")
	check(int(ch.get("stealthCd", 0)) > sim.tick, "穿晒: 設咗 CD (1 game 日)")
	check(RulesStealth.is_stealth(ch.get("status", {}), sim.tick), "is_stealth() 讀到")
	# 潛行中再用 -> 擋 (已潛行)
	sim.cmd_use_skill(id, "yinxing")
	check(RulesSpell.has(ch.get("status", {}), "stealth", sim.tick), "潛行中: 再撳唔會重開")
	# CD 未完再試: 取消潛行狀態 + 留 CD -> 擋 (CD 未過)
	ch["status"] = {}
	sim.cmd_use_skill(id, "yinxing")
	check((ch.get("stealthGame", {}) as Dictionary).is_empty(), "CD 未過: 唔會開新遊戲")
	# 過 CD 再試 + 撞車失敗
	ch["stealthCd"] = 0
	sim.cmd_use_skill(id, "yinxing")
	var g2: Dictionary = ch.get("stealthGame", {})
	var start2 := int(g2["start"])
	var pat2: Array = g2["pattern"]
	var got_fail: Array = [false]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "stealth_fail" and int(ev.get("dst", 0)) == id:
			got_fail[0] = true)
	# 撞車: 揀 gap0 空隙之前嗰格 (空隙前 1 tick)
	var before := start2 + int(pat2[0]) - 1
	sim.state["tick"] = before
	sim.cmd_stealth_cross(id)
	check(bool(got_fail[0]), "撞車: 發出 stealth_fail")
	check((ch.get("stealthGame", {}) as Dictionary).is_empty(), "撞車: 遊戲終止")
	check(not RulesSpell.has(ch.get("status", {}), "stealth", sim.tick), "撞車: 唔會入潛行")

	# ---- 潛行避免主動怪仇恨 ----
	var sim2 := Sim.new(data, 44)
	var pid2 := sim2.spawn_player("t2", "wunu")
	var pe2: Dictionary = sim2.ent(pid2)
	var ch2: Dictionary = sim2.player_ch()
	_put(sim2, pid2, 28, 30)
	sim2._sync_stats(pe2)
	var m: Variant = sim2._spawn_mob(1005, "field_1")          # 野狼 aggroRange 6
	_put(sim2, int(m["id"]), 30, 30)
	m["mob"]["home_x"] = 30
	m["mob"]["home_y"] = 30
	# 冇潛行: step 後會 aggro 追
	sim2.step()
	check(String(sim2.ent(int(m["id"]))["mob"]["state"]) == "chase", "冇潛行: 主動怪仇恨玩家")

	var sim3 := Sim.new(data, 45)
	var pid3 := sim3.spawn_player("t3", "wunu")
	var pe3: Dictionary = sim3.ent(pid3)
	var ch3: Dictionary = sim3.player_ch()
	_put(sim3, pid3, 28, 30)
	sim3._sync_stats(pe3)
	var m3: Variant = sim3._spawn_mob(1005, "field_1")
	_put(sim3, int(m3["id"]), 30, 30)
	m3["mob"]["home_x"] = 30
	m3["mob"]["home_y"] = 30
	# 直接設潛行狀態 (等效 QTE 成功)
	ch3["status"] = {"stealth": sim3.tick + RulesStealth.STEALTH_TICKS}
	sim3.step()
	var m3e := sim3.ent(int(m3["id"]))
	check(String(m3e["mob"]["state"]) == "wander", "潛行中: 主動怪唔會仇恨玩家 (仍遊蕩)")
	check(int(m3e["mob"]["target"]) == 0, "潛行中: 冇設仇恨目標")


# ===== 辯士 (S02c): 初階三招絕招 (琴? 弩 cat 9) + 起始弩 =====
func t_bianshi_ultimates(data: GameData) -> void:
	check(data.ult_by_id.has("tiandao") and data.ult_by_id.has("tuohuo") and data.ult_by_id.has("sanfen"), "辯士初階三招已定義")
	var tmpl := {"tiandao": {"tier": 1, "mult": 2.0, "range": 2, "mp": 15, "sp": 20, "cd": 300},
		"tuohuo": {"tier": 2, "mult": 2.5, "range": 2, "mp": 20, "sp": 30, "cd": 360},
		"sanfen": {"tier": 3, "mult": 3.0, "range": 3, "mp": 25, "sp": 40, "cd": 420}}
	for uid in tmpl:
		var u: Dictionary = data.ult_by_id.get(String(uid), {})
		var t: Dictionary = tmpl[String(uid)]
		check(String(u.get("class", "")) == "bianshi", "%s 係辯士招式" % u.get("name", uid))
		check(int(u.get("tier", 0)) == int(t["tier"]), "%s tier = %d" % [u.get("name", uid), int(t["tier"])])
		check(absf(float(u.get("mult", 0)) - float(t["mult"])) < 0.001, "%s 倍率 x%.1f" % [u.get("name", uid), float(t["mult"])])
		check(int(u.get("range", 0)) == int(t["range"]), "%s 範圍 %d" % [u.get("name", uid), int(t["range"])])
		check(int(u.get("mp", 0)) == int(t["mp"]) and int(u.get("sp", 0)) == int(t["sp"]), "%s MP/SP 消耗" % u.get("name", uid))
		check(int(u.get("cd", 0)) == int(t["cd"]), "%s 冷卻 %d" % [u.get("name", uid), int(t["cd"])])
		check(int(u.get("weaponCat", 0)) == 9, "%s 需要弩武器 (cat 9)" % u.get("name", uid))
	var ch := {"tier": 0, "level": 1}
	check(bool(RulesClass.ultimate_usable(ch, data.ult_by_id["tiandao"])["ok"]), "辯士一招: 初階 Lv1 用得")
	check(bool(RulesClass.ultimate_usable(ch, data.ult_by_id["sanfen"])["ok"]), "辯士三招: 初階都用得 (冇 reqTier)")


func t_bianshi_enabled(data: GameData) -> void:
	check(bool(data.classes["bianshi"].get("enabled", false)), "辯士職業已開放")
	var st: Dictionary = data.starter.get("bianshi", {})
	check(not st.is_empty(), "辯士有起始裝備")
	check(int(data.cats.get(int(st.get("weapon", 0)), 0)) == 9, "辯士起始武器係弩系 (cat 9)")
	var has_arrow := false
	for it in st.get("items", []):
		if int(data.cats.get(int(it["id"]), 0)) == RulesAmmo.ARROW_CAT and int(it["n"]) > 0:
			has_arrow = true
	check(has_arrow, "辯士起始帶箭矢")


# ===== 辯士特技「竊聽」: 導師學習 =====
func t_qieting_learn(data: GameData) -> void:
	var sim := Sim.new(data, 51)
	var id := sim.spawn_player("t", "bianshi")
	var ch: Dictionary = sim.player_ch()
	# 初始: classSkill 空 + rumors 有 array
	check(String(ch.get("classSkill", "")) == "", "辯士: 初始未學竊聽")
	check(ch.get("rumors", null) is Array, "辯士: rumors 有初始 []")
	check(not bool((sim.state["quest_npcs"] as Dictionary).get("bianshi_master", {}).get("visible", false)), "Lv1: 睇唔到蔡師傅")
	ch["level"] = 5
	sim._sync_stats(sim.ent(id))
	sim._sync_quest_npcs()
	check(bool((sim.state["quest_npcs"] as Dictionary).get("bianshi_master", {}).get("visible", false)), "Lv5: 蔡師傅出現")
	sim.cmd_use_skill(id, "qieting")
	check(String(ch.get("classSkill", "")) == "", "未學竊聽: 冇學到嘢")
	check(bool(RulesClassSkill.can_use(data, ch, "qieting").get("ok", false)) == false, "未學竊聽: Rules 擋")
	var npc: Dictionary = data.quest_npcs["bianshi_master"]
	_put(sim, id, int(npc["x"]) + 1, int(npc["y"]))
	sim.cmd_quest_talk(id, "bianshi_master")
	check((ch.get("quests", {}) as Dictionary).has("skill_unlock_bianshi"), "傾偈 = 接咗竊聽任務")
	sim.cmd_quest_answer(id, "skill_unlock_bianshi", 0)          # 答錯
	check(not bool(ch.get("questDone", {}).get("skill_unlock_bianshi", false)), "答錯: 未完成")
	sim.cmd_quest_answer(id, "skill_unlock_bianshi", 1)          # 答啱
	check(bool(ch.get("questDone", {}).get("skill_unlock_bianshi", false)), "答啱: 任務完成")
	check(String(ch.get("classSkill", "")) == "qieting", "任務獎勵: 學識竊聽")
	check(RulesClassSkill.learned(ch, "qieting"), "learned() 讀到")
	# 非辯士學唔到 (pre classId 擋)
	var sim2 := Sim.new(data, 52)
	var id2 := sim2.spawn_player("t2", "yishi")
	var ch2: Dictionary = sim2.player_ch()
	ch2["level"] = 5
	sim2._sync_stats(sim2.ent(id2))
	sim2._sync_quest_npcs()
	var npc2: Dictionary = data.quest_npcs["bianshi_master"]
	_put(sim2, id2, int(npc2["x"]) + 1, int(npc2["y"]))
	sim2.cmd_quest_talk(id2, "bianshi_master")
	check(not (ch2.get("quests", {}) as Dictionary).has("skill_unlock_bianshi"), "義士同蔡師傅傾偈: 唔接竊聽任務")
	# 存檔 roundtrip: classSkill + rumors 保留
	var s := sim.save_string()
	var sim3 := Sim.load_string(data, s)
	check(sim3 != null and String(sim3.player_ch().get("classSkill", "")) == "qieting", "存檔 roundtrip: classSkill 保留")


# ===== 辯士特技「竊聽」: 附近居民竊聽得傳聞線索 =====
func t_qieting_use(data: GameData) -> void:
	var sim := Sim.new(data, 53)
	var id := sim.spawn_player("t", "bianshi")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = 5
	ch["classSkill"] = "qieting"
	_put(sim, id, 27, 30)                                       # 野外居民聚集處
	# 附近冇居民 -> 竊聽唔到
	sim.cmd_use_skill(id, "qieting")
	check((ch.get("rumors", []) as Array).is_empty(), "冇居民: 竊聽唔到嘢 (rumors 仍空)")
	# 放一隻 bot 居民喺側邊 (哨坊)
	var bot := sim._spawn_actor("路人甲", "bot")
	BotSys.init_identity(bot, sim.rng)
	_put(sim, bot["id"], 28, 30)
	var got: Array = [false, ""]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "qieting" and int(ev.get("dst", 0)) == id and str(ev.get("text", "")) != "":
			got[0] = true
			got[1] = str(ev.get("text", "")))
	sim.cmd_use_skill(id, "qieting")
	check(bool(got[0]), "有居民: 竊聽發出 qieting 事件")
	check((ch.get("rumors", []) as Array).has(String(got[1])), "竊聽: 傳聞記入 rumors")
	check(int(ch.get("qietingCd", 0)) > sim.tick, "竊聽: 設咗冷卻")
	# 冷卻未完 -> 擋
	var n0 := (ch.get("rumors", []) as Array).size()
	sim.cmd_use_skill(id, "qieting")
	check((ch.get("rumors", []) as Array).size() == n0, "冷卻中: 唔會再加傳聞")
	# 過冷卻再偷 -> 去重: 全聽晒之前每條都唔重複
	for i in (data.rumors as Array).size() + 2:
		ch["qietingCd"] = 0
		sim.state["tick"] += 10
		sim.cmd_use_skill(id, "qieting")
	var heard: Array = ch.get("rumors", [])
	check(heard.size() <= (data.rumors as Array).size(), "重複偷: rumors 唔會超池大小 (去重)")
	# 聽晒 → 全池都喺情報冊 (假設池唔細)
	check(not heard.is_empty(), "重複偷: 情報冊有傳聞")
	# 存檔 roundtrip: rumors 保留
	var s := sim.save_string()
	var sim2 := Sim.load_string(data, s)
	check(sim2 != null, "竊聽後存檔: 讀得返")
	if sim2 != null:
		check((sim2.player_ch().get("rumors", []) as Array).size() == heard.size(), "存檔 roundtrip: rumors 保留")


# ===== 弩箭消耗 (S02c-辯士, spec 02 §6【原】): 用弩射箭扣箭 / 冇箭出手唔到 =====
func t_arrow_consume(data: GameData) -> void:
	var sim := Sim.new(data, 54)
	var id := sim.spawn_player("t", "bianshi")
	var pe: Dictionary = sim.ent(id)
	var ch: Dictionary = sim.player_ch()
	check(int(data.cats.get(int(ch["equip"]["weapon"]), 0)) == RulesAmmo.NU_WEAPON_CAT, "辯士裝備弩 (cat %d)" % RulesAmmo.NU_WEAPON_CAT)
	var n0 := RulesAmmo.arrow_count(data, ch)
	check(n0 > 0, "起始有箭 (n=%d)" % n0)
	_put(sim, id, 30, 30)
	sim._sync_stats(pe)
	var m: Variant = sim._spawn_mob(1005, "field_1")            # 最強嗰隻, 捱得幾下
	_put(sim, int(m["id"]), 31, 30)
	m["mob"]["home_x"] = 31
	m["mob"]["home_y"] = 30
	check(RulesAmmo.arrow_count(data, ch) == n0, "未出手: 箭未扣")
	sim.cmd_attack(id, int(m["id"]))
	for _i in 80:
		sim.step()
		if RulesAmmo.arrow_count(data, ch) < n0:
			break
	check(RulesAmmo.arrow_count(data, ch) < n0, "用弩射箭: 扣咗箭")
	check(RulesAmmo.consume_arrow(data, ch, 1) == true and RulesAmmo.arrow_count(data, ch) < n0, "consume_arrow 扣咗箭")
	# 冇箭 -> 出手唔到 (clear atk_target): 用新 sim 撇清上一輪狀態
	var simB := Sim.new(data, 55)
	var idB := simB.spawn_player("tB", "bianshi")
	var peB: Dictionary = simB.ent(idB)
	var chB: Dictionary = simB.player_ch()
	chB["bag"] = []                                 # 冇箭
	_put(simB, idB, 30, 30)
	simB._sync_stats(peB)
	var mB: Variant = simB._spawn_mob(1005, "field_1")
	_put(simB, int(mB["id"]), 31, 30)
	mB["mob"]["home_x"] = 31
	mB["mob"]["home_y"] = 30
	peB["atk_target"] = int(mB["id"])
	peB["next_atk"] = 0
	simB.step()
	check(int(simB.ent(idB)["atk_target"]) == 0, "冇箭: 出手唔到 (取消攻擊)")
	check(RulesAmmo.arrow_count(data, chB) == 0, "冇箭: 箭仍然是 0")
	check(RulesAmmo.consume_arrow(data, chB, 1) == false, "冇箭: consume_arrow 回 false")

