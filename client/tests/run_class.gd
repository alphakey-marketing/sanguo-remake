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
	t_unlock_learn(data)
	t_class_skill_use(data)
	t_chaodu_learn(data)
	t_chaodu_use(data)
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
	check(not bool(data.classes["wunu"].get("enabled", false)), "巫女未開放")
	check(not bool(data.classes["bianshi"].get("enabled", false)), "辯士未開放")
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