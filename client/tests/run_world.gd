extends SceneTree
# 世界基建測試 (Step 4): 時鐘/夜晚怪/設施/天災/市場/存檔。
# 跑: Godot --headless --path client --script tests/run_world.gd   (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_clock_pure()
	t_clock_sim(data)
	t_night_mobs(data)
	t_facilities(data)
	t_market_bounds(data)
	t_market_disaster(data)
	t_save_file(data)
	t_zones_travel(data)
	print("[TEST] world: %d, fail %d" % [total, fails])
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


func _step_days(sim: Sim, days: int) -> void:
	var per_day := 1440 / int(sim.data.world["clock"]["gameMinPerTick"])
	for i in days:
		for j in per_day:
			sim.step()


# ---------- 時鐘 (純函數) ----------
func t_clock_pure() -> void:
	check(RulesClock.ke_of_tick(0, 2) == 0, "clock: tick 0 → ke 0")
	check(RulesClock.ke_of_tick(48, 2) == 6, "clock: 48 tick (96分) → ke 6")
	check(RulesClock.ke_of_tick(720, 2) == 0, "clock: 720 tick (1440分) = 隔日 ke 0")
	check(RulesClock.day_of_tick(719, 2) == 0 and RulesClock.day_of_tick(720, 2) == 1, "clock: 一日 = 720 tick")
	check(RulesClock.shichen_of_ke(0) == 0 and RulesClock.shichen_of_ke(80) == 10, "clock: ke→時辰 (子/戌)")
	check(RulesClock.season_of_day(0, 30) == 0 and RulesClock.season_of_day(30, 30) == 1 and RulesClock.season_of_day(90, 30) == 3, "clock: 30 日一季")
	check(RulesClock.is_night(80, 80, 24) and RulesClock.is_night(95, 80, 24) and RulesClock.is_night(23, 80, 24), "clock: 夜 = ke 80..23")
	check(not RulesClock.is_night(24, 80, 24) and not RulesClock.is_night(79, 80, 24), "clock: 日 = ke 24..79")
	check(RulesClock.format_ke(0) == "子時 1 刻", "clock: format ke0 = 子時 1 刻")
	check(RulesClock.format(8, 4, 30) == "丑時 1 刻 · 第 5 日 · 春", "clock: format 全日")


# ---------- 時鐘 (sim 整合) ----------
func t_clock_sim(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	sim.add_bots(1)
	for i in 720:
		sim.step()
	var cv := sim.clock_view()
	check(int(cv["day"]) == 1 and int(cv["ke"]) == 0, "sim: 720 tick 後 = 第 2 日 子時 1 刻 (got %s)" % cv["text"])
	var days := [0]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "day":
			days[0] += 1)
	for i in 720:
		sim.step()
	check(days[0] >= 1, "sim: 每日發出 day 事件 (got %d)" % days[0])


# ---------- 夜怪 ----------
func t_night_mobs(data: GameData) -> void:
	var sim := Sim.new(data, 3)
	sim.init_mobs()
	var clk: Dictionary = sim.state["clock"]
	clk["is_night"] = false
	sim._sync_night_spawns()
	var n_day := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			n_day += 1
	clk["ke"] = 80
	clk["is_night"] = true
	sim._sync_night_spawns()
	var n_night := 0
	var night_mobs := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			n_night += 1
			if sim.data.monsters[int(e["mob"]["def"])].get("night", false):
				night_mobs += 1
	check(night_mobs == 4, "夜: 4 隻夜狼出場 (got %d)" % night_mobs)
	check(n_night > n_day, "夜: 總怪數增加 (day %d → night %d)" % [n_day, n_night])
	clk["is_night"] = false
	sim._sync_night_spawns()
	var n_morning := 0
	for e in sim.ents.values():
		if e["kind"] == "mob":
			n_morning += 1
	check(n_morning == n_day, "日: 夜怪消失 (got %d, expect %d)" % [n_morning, n_day])


# ---------- 城內設施 ----------
func t_facilities(data: GameData) -> void:
	var sim := Sim.new(data, 6)
	var id := sim.spawn_player("測試")
	sim.add_bots(1)
	var sid := 0
	for e in sim.ents.values():
		if e["kind"] == "bot":
			sid = int(e["id"])
	var f: Dictionary = data.facilities["training"]
	_put(sim, id, int(f["x"]), int(f["y"]))
	_put(sim, sid, int(f["x"]) + 1, int(f["y"]))
	var ch := sim.player_ch()
	ch["gold"] = 1000
	var lilian0 := int(ch.get("lilian", 0))
	var hp0 := int(ch["hp"])
	var sp0 := int(ch["sp"])
	sim.cmd_facility(id, "training")
	check(int(ch.get("lilian", 0)) == lilian0 + 10, "練兵場: 歷練 +10")
	check(int(ch["hp"]) < hp0 and int(ch["sp"]) < sp0, "練兵場: 扣 HP/SP")
	var lilian1 := int(ch["lilian"])
	sim.cmd_facility(id, "training")
	check(int(ch["lilian"]) == lilian1, "練兵場: 冷卻期間做唔到")
	var sc: Dictionary = data.facilities["school"]
	_put(sim, id, int(sc["x"]), int(sc["y"]))
	var pol0 := int(ch["attrs"]["pol"])
	var gold0 := int(ch["gold"])
	var mp0 := int(ch["mp"])
	var sp1 := int(ch["sp"])
	sim.cmd_facility(id, "school")
	check(int(ch["attrs"]["pol"]) == pol0 + 1, "私塾: 政治 +1")
	check(int(ch["gold"]) == gold0 - int(sc["gold"]), "私塾: 扣金")
	check(int(ch["mp"]) < mp0 and int(ch["sp"]) < sp1, "私塾: 扣 SP/MP")
	ch["gold"] = 0
	var pol1 := int(ch["attrs"]["pol"])
	sim.cmd_facility(id, "school")
	check(int(ch["attrs"]["pol"]) == pol1, "私塾: 冇金做唔到")
	var tm: Dictionary = data.facilities["temple"]
	_put(sim, id, int(tm["x"]), int(tm["y"]))
	ch["gold"] = 1000
	var cha0 := int(ch["attrs"]["cha"])
	sim.cmd_facility(id, "temple")
	check(int(ch["attrs"]["cha"]) == cha0 + 1, "寺廟: 魅力 +1")


# ---------- 市場: 100 日有界 ----------
func t_market_bounds(data: GameData) -> void:
	var sim := Sim.new(data, 9)
	for day in 100:
		sim._market_daily(day % 4)
	var cfg: Dictionary = data.world["market"]
	for c in data.world["cities"]:
		var cm: Dictionary = sim.state["market"][c.id]
		for k in cm:
			var m: Dictionary = cm[k]
			var pf := float(m["pf"])
			var st := float(m["stock"])
			var vol := float(cfg["cats"][k]["vol"])
			check(pf >= float(cfg["minFactor"]) and pf <= float(cfg["maxFactor"]), "市場: %s/%s pf 有界 %.2f" % [c.id, k, pf])
			check(st >= 0 and st <= vol * float(cfg["stockCap"]), "市場: %s/%s 庫存有界 %.0f" % [c.id, k, st])
	check(absf(float(sim.market_city("xuchang", "43")["pf"]) - 1.0) < 0.15, "市場: 無天災 100 日後糧價貼近 1 (got %.3f)" % float(sim.market_city("xuchang", "43")["pf"]))


# ---------- 天災 → 市場反應 ----------
func t_market_disaster(data: GameData) -> void:
	var sim := Sim.new(data, 10)
	for day in 10:
		sim._market_daily(day % 4)
	var pf0 := float(sim.market_city("xuchang", "43")["pf"])
	sim.state["disasters"].append({"id": "locust", "name": "蝗災", "city": "xuchang", "size": "大",
		"startDay": 0, "endDay": 15, "supply": {"43": 0.25, "44": 0.5}})
	for day in 8:
		sim._market_daily(day % 4)
	var pf1 := float(sim.market_city("xuchang", "43")["pf"])
	check(pf1 > pf0 + 0.05, "天災: 蝗災後糧價上升 (%.3f → %.3f)" % [pf0, pf1])
	# 純函數: 防災度 50 → 大蝗災 糧供給 = 1.1(夏) × (1-(1-0.25)*0.5) = 0.6875
	var m := RulesMarket.supply_mods(1, data.world["market"]["seasonSupply"],
		[{"supply": {"43": 0.25}}], {"pop": 800, "defense": 50})
	check(absf(float(m["43"]) - 0.6875) < 0.001, "天災: 防災度減輕效果 (got %.3f)" % float(m.get("43", 0.0)))
	# 地震 → 礦石供給上升
	RulesDisaster.expire(sim.state["disasters"], 30)
	check(sim.state["disasters"].is_empty(), "天災: 到期自動消失")


# ---------- 存檔 (檔案 roundtrip + 可重現) ----------
func t_save_file(data: GameData) -> void:
	var slot := "user://save/test_world.json"
	var a := Sim.new(data, 21)
	a.init_mobs()
	a.add_bots(2)
	var id := a.spawn_player("存檔測試")
	a.cmd_move(id, 30, 30)
	for i in 500:
		a.step()
	check(SaveSys.save(a, slot), "存檔: 寫入成功")
	check(SaveSys.has(slot), "存檔: 檔案存在")
	var b := SaveSys.read_sim(data, slot)
	check(b != null, "存檔: 可以讀返")
	var same := false
	if b != null:
		same = b.save_string() == a.save_string()
	check(same, "存檔: 讀出嚟狀態一致")
	if b != null:
		var out := []
		b.event_emitted.connect(func(ev: Dictionary) -> void:
			out.append(ev["k"]))
		for i in 300:
			a.step()
			b.step()
		check(a.save_string() == b.save_string(), "存檔: 續跑 300 tick 一致")
	# autosave 同 slot
	check(SaveSys.autosave(a), "存檔: autosave 寫入")
	check(SaveSys.read_autosave(data) != null, "存檔: autosave 讀返")


# ---------- 安全區/戰鬥區 + 傳送點 ----------
func t_zones_travel(data: GameData) -> void:
	var sim := Sim.new(data, 5)
	var id := sim.spawn_player("t")
	check(sim.is_safe(10, 10), "安全區: 城內 (10,10) 係安全")
	check(not sim.is_safe(30, 30), "戰鬥區: 野地 (30,30) 唔安全")
	# 城入面追怪唔會真係出手
	_put(sim, id, 10, 10)
	sim._spawn_mob(1001, "field_1")
	var mob_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob": mob_id = int(e["id"])
	_put(sim, mob_id, 11, 10)
	sim.ent(mob_id)["mob"]["state"] = "chase"
	sim.ent(mob_id)["mob"]["target"] = id
	var hp0 := int(sim.ent(mob_id)["hp"])
	sim.cmd_attack(id, mob_id)
	for i in 30:
		sim.step()
	check(int(sim.ent(mob_id)["hp"]) == hp0, "安全區: 追到都唔出手 (怪血量不變)")
	# 傳送點: 城內 -> 城外
	var gate_out: Dictionary = sim.travel_point_by_id("gate_out")
	_put(sim, id, int(gate_out["x"]), int(gate_out["y"]))
	var events := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "travel": events.append(ev))
	sim.cmd_travel(id, "gate_out")
	var e := sim.ent(id)
	var gate_in: Dictionary = sim.travel_point_by_id("gate_in")
	check(int(e["x"]) == int(gate_in["x"]) and int(e["y"]) == int(gate_in["y"]), "傳送: 到達對面城門")
	check(not sim.is_safe(int(e["x"]), int(e["y"])), "傳送: 落地喺戰鬥區")
	check(events.size() == 1, "傳送: 發出 travel 事件")
	# 唔喺傳送點附近 = 唔會傳送
	var sim2 := Sim.new(data, 6)
	var id2 := sim2.spawn_player("t2")
	_put(sim2, id2, 0, 0)
	sim2.cmd_travel(id2, "gate_out")
	var e2 := sim2.ent(id2)
	check(int(e2["x"]) == 0 and int(e2["y"]) == 0, "傳送: 唔近傳送點就唔會傳送")