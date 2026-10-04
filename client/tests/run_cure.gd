extends SceneTree
# 解狀態藥 (effect 28~33)
var fails := 0


func check(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("[FAIL] ", m)


func _init() -> void:
	var data := GameData.load_all()
	var sim := Sim.new(data, 1)
	var pid: int = sim.spawn_player("測試")
	var ch: Dictionary = sim.ent(pid)["ch"]
	# 辟邪丹 28014 解中邪
	ch["bag"].append({"id": 28014, "count": 2}) if false else RulesShop.add_item(ch["bag"], 28014, 2)
	sim.cmd_use_item(pid, 28014)
	check(RulesShop.count_item(ch["bag"], 28014) == 2, "冇狀態唔扣藥")
	RulesSpell.add_status(ch["status"], "hex", 300, sim.tick)
	RulesSpell.add_status(ch["status"], "sealed", 600, sim.tick)
	sim.cmd_use_item(pid, 28014)
	check(not RulesSpell.has(ch["status"], "hex", sim.tick), "中邪解咗")
	check(RulesSpell.has(ch["status"], "sealed", sim.tick), "封咒仲喺")
	check(RulesShop.count_item(ch["bag"], 28014) == 1, "扣 1 粒")
	# 崑崙山仙藥 28029 全解
	RulesShop.add_item(ch["bag"], 28029, 1)
	RulesSpell.add_status(ch["status"], "hex", 300, sim.tick)
	sim.cmd_use_item(pid, 28029)
	check(not RulesSpell.has(ch["status"], "hex", sim.tick) and not RulesSpell.has(ch["status"], "sealed", sim.tick), "全解")
	# 限時 buff 丹
	var mhp0: int = sim._eff_max_hp(ch)
	RulesShop.add_item(ch["bag"], 65189, 1)          # 元氣丹I HP上限+1000, 120 分鐘
	sim.cmd_use_item(pid, 65189)
	check(sim._eff_max_hp(ch) == mhp0 + 1000, "元氣丹 HP 上限 +1000")
	RulesShop.add_item(ch["bag"], 65192, 1)          # 霸王丹I 物攻+10%
	sim.cmd_use_item(pid, 65192)
	check(absf(float(sim._jewel_bonus(ch).get("atkPct", 0.0)) - 0.1) < 0.001, "霸王丹 atk +10%")
	RulesShop.add_item(ch["bag"], 65185 + 3, 1)      # 三效仙丹 type 4 x2
	sim.cmd_use_item(pid, 65188)
	check(RulesPill.exp_mult(ch, sim.tick) == 2.0, "三效仙丹 exp x2")
	RulesShop.add_item(ch["bag"], 65334, 1)          # 霸君加持丹
	sim.cmd_use_item(pid, 65334)
	check(float(sim._jewel_bonus(ch).get("spellAtkPct", 0.0)) >= 0.1, "加持丹 術攻")
	sim.state["tick"] = int(sim.state["tick"]) + 120 * 600 + 1
	check(sim._eff_max_hp(ch) == mhp0, "過期 HP 上限回復")
	check(float(sim._jewel_bonus(ch).get("atkPct", 0.0)) == 0.0, "過期 atk 歸零")
	check(RulesPill.exp_mult(ch, sim.tick) == 2.0, "三效 360 分鐘仲有效")
	# 湯/水
	ch["thirst"] = 10
	RulesShop.add_item(ch["bag"], 29035, 1)           # 清水 +50
	sim.cmd_use_item(pid, 29035)
	check(int(ch["thirst"]) == 60, "清水 飲水度 +50")
	# 光
	RulesShop.add_item(ch["bag"], 26016, 1)
	sim.cmd_use_item(pid, 26016)
	check(RulesPill.light_on(ch, sim.tick), "火把 點燈")
	# 丸/速度
	RulesShop.add_item(ch["bag"], 28017, 1)           # 大力丸 物攻+20%
	sim.cmd_use_item(pid, 28017)
	check(float(sim._jewel_bonus(ch).get("atkPct", 0.0)) >= 0.2, "大力丸 atk")
	RulesShop.add_item(ch["bag"], 65165, 1)           # 急速丹 +50%
	sim.cmd_use_item(pid, 65165)
	check(absf(RulesPill.speed_mult(ch, sim.tick) - 1.5) < 0.001, "急速丹 移速 x1.5")
	var e: Dictionary = sim.ent(pid)
	var s := 0
	for _i in 10:
		s += sim._walk_scale(e, 1)
	check(s == 15, "10 tick 行 15 步 (%d)" % s)
	# 行動之戒
	var ap0: int = sim.ap_max(ch)
	ch["equip"]["ring"] = 23089
	check(sim.ap_max(ch) == ap0 + 5, "行動之戒 AP +5")
	print("run_cure fails=", fails)
	quit(1 if fails > 0 else 0)
