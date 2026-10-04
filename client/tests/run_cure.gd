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
	print("run_cure fails=", fails)
	quit(1 if fails > 0 else 0)
