extends SceneTree
# 角色成長場景測試 (spec 01, S01)。跑: Godot --headless --path client --script tests/run_char.gd
# S01a: 安全區自動回復、練兵場小兵免費回 SP、5 級前免費補 HP、HUD 鍵數跟等級

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_safe_regen(data)
	t_wild_no_regen(data)
	t_trainer_restsp(data)
	t_hud_skill_cap()
	print("[TEST] char: %d, fail %d" % [total, fails])
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


func t_safe_regen(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	_put(sim, id, sim.inn_pos.x, sim.inn_pos.y)     # 客棧一帶 = 安全區
	check(sim.is_safe(int(ch_ent(sim, id)["x"]), int(ch_ent(sim, id)["y"])), "客棧係安全區")
	var mhp := RulesStats.max_hp(int(ch["level"]), ch["attrs"])
	ch["hp"] = 1
	var ticks := int(data.world["regen"]["ticks"])
	for i in ticks:
		sim.step()
	check(int(ch["hp"]) > 1, "安全區: 每 %d tick 回 HP" % ticks)
	ch["hp"] = mhp
	for i in ticks:
		sim.step()
	check(int(ch["hp"]) == mhp, "安全區: 回復封頂喺 max_hp")


func t_wild_no_regen(data: GameData) -> void:
	var sim := Sim.new(data, 2)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	_put(sim, id, 60, 60)                           # 野外 (非安全區)
	check(not sim.is_safe(60, 60), "60,60 係野外")
	ch["hp"] = 1
	var ticks := int(data.world["regen"]["ticks"])
	for i in ticks * 2:
		sim.step()
	check(int(ch["hp"]) == 1, "野外: 唔會自動回復")


func ch_ent(sim: Sim, id: int) -> Dictionary:
	return sim.ent(id)


func t_trainer_restsp(data: GameData) -> void:
	var sim := Sim.new(data, 3)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	var f: Dictionary = data.facilities["trainer"]
	_put(sim, id, int(f["x"]), int(f["y"]))
	var msp := RulesStats.max_sp(int(ch["level"]), ch["attrs"])
	ch["sp"] = 1
	sim.cmd_facility(id, "trainer")
	check(int(ch["sp"]) == msp, "練兵場小兵: 免費回滿 SP")
	ch["sp"] = 1
	sim.cmd_facility(id, "trainer")
	check(int(ch["sp"]) == 1, "練兵場小兵: 冷卻中唔可以再用")


func t_hud_skill_cap() -> void:
	check(HudLayout.skill_cap(1) == 4, "5 級前 4 鍵")
	check(HudLayout.skill_cap(4) == 4, "5 級前 4 鍵 (4 級)")
	check(HudLayout.skill_cap(5) == 6, "5 級後 6 鍵")
	check(HudLayout.skill_cap(50) == 6, "5 級後 6 鍵 (高級)")
