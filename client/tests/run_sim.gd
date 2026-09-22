extends SceneTree
# sim 場景測試 (headless): 跑 Godot --headless --path client --script tests/run_sim.gd   (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_walk(data)
	t_blocked(data)
	t_kill_mob(data)
	t_death(data)
	t_facilities(data)
	t_determinism(data)
	t_save_roundtrip(data)
	t_bots_live(data)
	t_karma_tiers()
	print("[TEST] sim scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func t_karma_tiers() -> void:
	var cases := [[30000, "大英雄"], [16001, "大英雄"], [16000, "善人"], [8001, "善人"], [8000, "好人"], [1001, "好人"],
		[1000, "中立"], [0, "中立"], [-1000, "中立"], [-1001, "罪犯"], [-8000, "罪犯"], [-8001, "惡人"],
		[-16000, "惡人"], [-16001, "殺人魔"], [-30000, "殺人魔"]]
	for c in cases:
		check(RulesKarma.tier_name(int(c[0])) == c[1], "善惡階 %d → %s" % [c[0], c[1]])


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y


func t_walk(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	var id := sim.spawn_player("t")
	_put(sim, id, 5, 5)
	sim.cmd_move(id, 8, 5)
	sim.step()
	check(int(sim.ent(id)["x"]) == 6, "走路: 一 tick 一格")
	sim.step()
	sim.step()
	check(int(sim.ent(id)["x"]) == 8, "走路: 三 tick 到 8")


func t_blocked(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	var id := sim.spawn_player("t")
	check(not sim.is_free(15, 20), "阻擋格 (15,20)")
	sim.cmd_move(id, 15, 20)
	var e := sim.ent(id)
	check(not (int(e["tx"]) == 15 and int(e["ty"]) == 20), "阻擋格唔可以做目標")


func t_kill_mob(data: GameData) -> void:
	var sim := Sim.new(data, 7)
	var id := sim.spawn_player("t")
	_put(sim, id, 30, 30)
	sim._spawn_mob(1001)       # 田鼠
	var mob_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			mob_id = int(e["id"])
	_put(sim, mob_id, 31, 30)
	sim.ent(mob_id)["mob"]["home_x"] = 31
	sim.ent(mob_id)["mob"]["home_y"] = 30
	var kills := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "kill":
			kills.append(ev))
	sim.cmd_attack(id, mob_id)
	for i in 300:
		sim.step()
		if not kills.is_empty():
			break
	var ch := sim.player_ch()
	check(kills.size() == 1, "殺怪: 收到 kill 事件")
	check(int(ch["exp"]) > 0 or int(ch["level"]) > 1, "殺怪: 經驗增加")
	check(not sim.ents.has(mob_id), "殺怪: 怪已移除")
	check(sim.state["respawns"].size() == 1, "殺怪: 排入重生")


func t_death(data: GameData) -> void:
	var sim := Sim.new(data, 3)
	var id := sim.spawn_player("t")
	_put(sim, id, 30, 30)
	var ch := sim.player_ch()
	ch["hp"] = 1
	sim._sync_stats(sim.ent(id))
	sim._spawn_mob(1005)       # 最強嗰隻
	var mob_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			mob_id = int(e["id"])
	_put(sim, mob_id, 31, 30)
	sim.ent(mob_id)["mob"]["state"] = "chase"
	sim.ent(mob_id)["mob"]["target"] = id
	var died := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "die":
			died.append(ev))
	for i in 100:
		sim.step()
		if not died.is_empty():
			break
	var e := sim.ent(id)
	check(died.size() == 1, "死亡: 收到 die 事件")
	check(int(e["x"]) == sim.inn_pos.x and int(e["y"]) == sim.inn_pos.y, "死亡: 返客棧")
	check(int(e["hp"]) == int(e["max_hp"]), "死亡: 回滿血")


func t_facilities(data: GameData) -> void:
	var sim := Sim.new(data, 5)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	_put(sim, id, 30, 30)
	ch["gold"] = 100
	sim.cmd_rest(id)
	check(int(ch["gold"]) == 100, "休息: 遠離客棧唔扣錢")
	_put(sim, id, sim.inn_pos.x, sim.inn_pos.y)
	ch["hp"] = 1
	sim.cmd_rest(id)
	check(int(ch["gold"]) == 100 - int(data.inn["restCost"]), "休息: 扣住宿費")
	check(int(ch["hp"]) == RulesStats.max_hp(int(ch["level"]), ch["attrs"]), "休息: 回滿 HP")
	var shop: Dictionary = data.shops[0]
	_put(sim, id, int(shop["x"]), int(shop["y"]))
	var item := int(shop["stock"][1])
	ch["gold"] = 100000
	var gold0 := int(ch["gold"])
	var cost := RulesShop.buy_price(data.prices[item], ch["attrs"]["cha"])
	sim.cmd_buy(id, item, 1)
	check(int(ch["gold"]) == gold0 - cost, "買: 扣錢 (魅力折扣價)")
	var have := 0
	for b in ch["bag"]:
		if int(b["id"]) == item:
			have = int(b["n"])
	check(have >= 1, "買: 背包有貨")
	sim.cmd_sell(id, item, 1)
	check(int(ch["gold"]) == gold0 - cost + RulesShop.sell_price(data.prices[item]), "賣: 收 50% 價")


func _run_scripted(data: GameData, seed_value: int, ticks: int) -> Sim:
	var sim := Sim.new(data, seed_value)
	sim.init_mobs()
	sim.add_bots(10)
	var id := sim.spawn_player("玩家")
	sim.cmd_move(id, 35, 35)
	for i in ticks:
		if i % 50 == 0:
			for e in sim.ents.values():
				if e["kind"] == "mob":
					sim.cmd_attack(id, int(e["id"]))
					break
		sim.step()
	return sim


func t_determinism(data: GameData) -> void:
	var a := _run_scripted(data, 42, 600)
	var b := _run_scripted(data, 42, 600)
	var c := _run_scripted(data, 43, 600)
	check(a.save_string() == b.save_string(), "同種子 600 tick 狀態一致")
	check(a.save_string() != c.save_string(), "唔同種子狀態唔同")


func t_save_roundtrip(data: GameData) -> void:
	var a := _run_scripted(data, 9, 300)
	var s := a.save_string()
	var b := Sim.load_string(data, s)
	check(b != null and b.save_string() == s, "存檔 → 讀檔 → 再存檔一致")
	for i in 200:
		a.step()
		b.step()
	check(a.save_string() == b.save_string(), "讀檔後續跑 200 tick 同原本一致")


func t_bots_live(data: GameData) -> void:
	var sim := Sim.new(data, 11)
	sim.init_mobs()
	sim.add_bots(10)
	var kills := [0]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "kill":
			kills[0] += 1)
	for i in 3000:
		sim.step()
	check(kills[0] > 0, "機械人 3000 tick 內有殺怪 (kills=%d)" % kills[0])
