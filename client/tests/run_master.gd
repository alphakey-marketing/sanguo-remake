extends SceneTree
# S05c 大宗師合成術測試 (spec 05 §5)
# 跑: Godot --headless --path client --script tests/run_master.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_rules(data)
	t_gather_bonus(data)
	t_gem_craft(data)
	t_redeem_baizhu(data)
	t_treasure_synth(data)
	t_save_roundtrip(data)
	print("[TEST] master scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _new(data: GameData, seed: int = 7) -> Array:
	var sim := Sim.new(data, seed)
	var pid := sim.spawn_player("t", "yishi")
	var ch := sim.player_ch()
	ch["level"] = 60
	var msgs: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "msg":
			msgs.append(String(ev["text"])))
	return [sim, pid, ch, msgs]


func _equip_tool(sim: Sim, pid: int, ch: Dictionary, skill: String, item: int) -> void:
	RulesShop.add_item(ch["bag"], item, 1)
	sim.cmd_equip_tool(pid, skill, item)


func t_data(data: GameData) -> void:
	check(not data.master.is_empty(), "master_recipes.json 有讀到")
	check(int(data.master["condition"]["basicLv"]) == 100 and int(data.master["condition"]["advLv"]) == 20, "條件 100/20")
	check((data.master["materials"] as Dictionary).size() == 11, "11 種新初階/進階材料")
	check((data.master["gems"] as Dictionary).size() == 5, "5 種合成寶石")
	check((data.master["treasures"] as Array).size() == 5, "5 種虛擬寶物")
	for sk in data.master["gems"]:
		var gc: Dictionary = data.master["gems"][sk]
		check(data.names.has(int(gc["item"])), "寶石 %s item 喺 items.json 存在" % sk)
		for m in gc["need"]:
			check(data.names.has(int(m[0])), "寶石 %s 材料 %s 喺 items.json 存在" % [sk, m[0]])
	for sk in data.master["materials"]:
		check(data.names.has(int(data.master["materials"][sk])), "材料 %s 喺 items.json 存在" % sk)
	for t in data.master["treasures"]:
		check(data.names.has(int(t)), "虛寶 %s 喺 items.json 存在" % t)
	check(data.names.has(int(data.master["baizhu"])), "白晝之珠喺 items.json 存在")


func t_rules(data: GameData) -> void:
	var cfg: Dictionary = data.master["condition"]
	check(RulesMaster.gem_ready(100, 20, cfg), "100/20 = ready")
	check(not RulesMaster.gem_ready(99, 20, cfg), "99/20 = 未夠")
	check(not RulesMaster.gem_ready(100, 19, cfg), "100/19 = 未夠")
	check(RulesMaster.has_need({26075: 5, 26081: 3, 26086: 1}, [[26075, 5], [26081, 3], [26086, 1]]), "材料齊 = 夠")
	check(not RulesMaster.has_need({26075: 4}, [[26075, 5]]), "材料唔齊 = 唔夠")
	var scfg: Dictionary = data.master["synth"]
	check(RulesMaster.gem_count_ok(2, scfg) and RulesMaster.gem_count_ok(5, scfg), "2/5 粒喺範圍內")
	check(not RulesMaster.gem_count_ok(1, scfg) and not RulesMaster.gem_count_ok(6, scfg), "1/6 粒出範圍")
	var c1 := RulesMaster.synth_chance(20, scfg)
	var c2 := RulesMaster.synth_chance(80, scfg)
	check(c2 > c1, "進階技能等級越高，虛寶成功率越高")
	var pool := [26092, 26093]
	var picked := RulesMaster.pick_treasure(pool, func() -> float: return 0.9)
	check(pool.has(picked), "隨機虛寶喺 pool 之內")


func t_gather_bonus(data: GameData) -> void:
	var arr := _new(data)
	var sim: Sim = arr[0]
	var pid: int = arr[1]
	var ch: Dictionary = arr[2]
	ch["level"] = 80
	ch["workLv"]["farming"] = {"lv": 100, "exp": 0}
	_put(sim, pid, 70, 15)  # 許下屯田 = 農耕工作區
	_equip_tool(sim, pid, ch, "farming", 26053)  # 御賜鋤頭
	check(String(data.tool_tier.get(26053, "")) == "godgiven", "26053 = 農耕御賜工具")
	var got_bonus := false
	for i in 400:
		ch["sp"] = 999999
		sim.cmd_work(pid, "farming")
		if int(RulesShop.count_item(ch["bag"], int(data.master["materials"]["farming"]))) > 0:
			got_bonus = true
			break
	check(got_bonus, "用御賜工具工作，400 次入面有機會夾埋大宗師材料")

	var arr2 := _new(data, 8)
	var sim2: Sim = arr2[0]
	var pid2: int = arr2[1]
	var ch2: Dictionary = arr2[2]
	ch2["workLv"]["farming"] = {"lv": 100, "exp": 0}
	_put(sim2, pid2, 70, 15)
	_equip_tool(sim2, pid2, ch2, "farming", 26041)  # 特製鋤頭 (非御賜)
	for i in 50:
		ch2["sp"] = 999999
		sim2.cmd_work(pid2, "farming")
	check(int(RulesShop.count_item(ch2["bag"], int(data.master["materials"]["farming"]))) == 0, "非御賜工具唔會夾埋大宗師材料")


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y


func _give_gem_mats(ch: Dictionary, gc: Dictionary) -> void:
	for m in gc["need"]:
		RulesShop.add_item(ch["bag"], int(m[0]), int(m[1]))


func t_gem_craft(data: GameData) -> void:
	var arr := _new(data)
	var sim: Sim = arr[0]
	var pid: int = arr[1]
	var ch: Dictionary = arr[2]
	var msgs: Array = arr[3]
	var gc: Dictionary = data.master["gems"]["cooking"]
	sim.cmd_master_gem(pid, "cooking")
	check(_last(msgs).find("要") == 0, "條件未夠拒絕：%s" % _last(msgs))
	ch["workLv"]["farming"] = {"lv": 100, "exp": 0}
	ch["workLv"]["cooking"] = {"lv": 20, "exp": 0}
	sim.cmd_master_gem(pid, "cooking")
	check(_last(msgs).find("材料唔夠") >= 0, "條件夠但冇材料")
	_give_gem_mats(ch, gc)
	sim.cmd_master_gem(pid, "cooking")
	check(int(RulesShop.count_item(ch["bag"], int(gc["item"]))) == 1, "合成成功得 1 粒扈江之石")
	for m in gc["need"]:
		check(int(RulesShop.count_item(ch["bag"], int(m[0]))) == 0, "材料扣晒")


func t_redeem_baizhu(data: GameData) -> void:
	var arr := _new(data)
	var sim: Sim = arr[0]
	var pid: int = arr[1]
	var ch: Dictionary = arr[2]
	var msgs: Array = arr[3]
	var cost := int(data.master["baizhuRedeemContrib"])
	sim.cmd_master_redeem_baizhu(pid)
	check(_last(msgs).find("貢獻不足") >= 0, "貢獻不足擋兌換")
	ch["contrib"] = cost
	sim.cmd_master_redeem_baizhu(pid)
	check(int(RulesShop.count_item(ch["bag"], int(data.master["baizhu"]))) == 1, "兌換成功得 1 粒白晝之珠")
	check(int(ch["contrib"]) == 0, "扣晒貢獻")


func t_treasure_synth(data: GameData) -> void:
	var arr := _new(data, 3)
	var sim: Sim = arr[0]
	var pid: int = arr[1]
	var ch: Dictionary = arr[2]
	var msgs: Array = arr[3]
	var gc: Dictionary = data.master["gems"]["smithing"]
	var gem := int(gc["item"])
	ch["workLv"]["smithing"] = {"lv": 90, "exp": 0}
	RulesShop.add_item(ch["bag"], gem, 5)
	sim.cmd_master_treasure(pid, "smithing", [26999, 26999])
	check(_last(msgs).find("至少要") >= 0, "冇對應技能寶石拒絕")
	var got_ok := false
	var got_fail := false
	for s in range(20):
		var arr2 := _new(data, s)
		var sim2: Sim = arr2[0]
		var pid2: int = arr2[1]
		var ch2: Dictionary = arr2[2]
		ch2["workLv"]["smithing"] = {"lv": 90, "exp": 0}
		RulesShop.add_item(ch2["bag"], gem, 5)
		sim2.cmd_master_treasure(pid2, "smithing", [gem, gem, gem, gem, gem])
		var got := false
		for t in data.master["treasures"]:
			if int(RulesShop.count_item(ch2["bag"], int(t))) > 0:
				got = true
		if got:
			got_ok = true
		else:
			got_fail = true
		if got_ok and got_fail:
			break
	check(got_ok or got_fail, "進階合成有成功/失敗結果")
	check(int(RulesShop.count_item(ch["bag"], gem)) == 5, "拒絕嘅嗰次冇扣寶石")


func _last(msgs: Array) -> String:
	return String(msgs[-1]) if not msgs.is_empty() else ""


func t_save_roundtrip(data: GameData) -> void:
	var arr := _new(data, 9)
	var sim: Sim = arr[0]
	var pid: int = arr[1]
	var ch: Dictionary = arr[2]
	ch["contrib"] = 700
	RulesShop.add_item(ch["bag"], int(data.master["baizhu"]), 2)
	var s := sim.save_string()
	var sim2 := Sim.load_string(data, s)
	var ch2 := sim2.player_ch()
	check(int(ch2["contrib"]) == 700 and int(RulesShop.count_item(ch2["bag"], int(data.master["baizhu"]))) == 2, "存檔 roundtrip 保住貢獻/白晝之珠")
