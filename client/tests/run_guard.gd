extends SceneTree
# 捕快 NPC 測試【自訂】: guards.json / RulesGuard 純函數 / 每城 spawn / 巡邏·企定位 / 見紅名主動打。
# 跑: Godot --headless --path client --script tests/run_guard.gd  (失敗 exit 1)

var fails := 0
var total := 0
var G: Dictionary = {}     # guards.json cfg


func _init() -> void:
	var data := GameData.load_all()
	G = RulesGuard.cfg(data.guards)
	t_data()
	t_level()
	t_patrol_time()
	t_stand_pos()
	t_patrol_point()
	t_red_target()
	t_spawn(data)
	t_patrol_vs_stand(data)
	t_aggro_lock(data)
	print("[TEST] guard scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


# ================= 純函數 =================

func t_data() -> void:
	check(not G.is_empty(), "捕快: guards.json cfg 載入")
	check(int(G.get("perCity", 0)) == 2, "捕快: 每城 2 隻")
	check(int(G.get("levelMin", 0)) == 50 and int(G.get("levelMax", 0)) == 75, "捕快: 等級 50~75")


func t_level() -> void:
	check(RulesGuard.level_of(G, 0, 2) == 50, "等級: 第 0 隻 = 50")
	check(RulesGuard.level_of(G, 1, 2) == 75, "等級: 第 1 隻 = 75")
	check(RulesGuard.level_of(G, 0, 1) == 50, "等級: perCity=1 用 levelMin")


func t_patrol_time() -> void:
	for s in G.get("patrolShichen", []):
		check(RulesGuard.is_patrol_time(G, int(s)), "巡邏時辰: %d 係巡邏時辰" % int(s))
	check(not RulesGuard.is_patrol_time(G, 0), "巡邏時辰: 子時 (0) 唔係巡邏時辰")
	check(not RulesGuard.is_patrol_time(G, 11), "巡邏時辰: 亥時 (11) 唔係巡邏時辰")


func t_stand_pos() -> void:
	var p := RulesGuard.stand_pos(10, 20, G)
	var off: Array = G.get("standOffset", [3, 3])
	check(p.x == 10 + int(off[0]) and p.y == 20 + int(off[1]), "企定位: 客棧 + standOffset")


func t_patrol_point() -> void:
	var stand := Vector2i(50, 50)
	var seen := {}
	for i in 4:
		var pt := RulesGuard.patrol_point(stand, 6, i)
		seen[pt] = true
	check(seen.size() == 4, "巡邏點: 4 個方向點各不同")
	check(RulesGuard.patrol_point(stand, 6, 0) == RulesGuard.patrol_point(stand, 6, 4), "巡邏點: 循環 (step 0 = step 4)")


func t_red_target() -> void:
	check(RulesGuard.is_red_target({"criminal": true}, false), "紅名判定: 罪犯居民")
	check(not RulesGuard.is_red_target({"criminal": false}, false), "紅名判定: 非罪犯居民")
	check(RulesGuard.is_red_target({"karma": -20000}, true), "紅名判定: 玩家殺人魔階")
	check(not RulesGuard.is_red_target({"karma": -10000}, true), "紅名判定: 玩家惡人階唔算紅名")


# ================= sim spawn =================

func t_spawn(data: GameData) -> void:
	var sim := Sim.new(data, 9)
	sim.add_guards()
	var per_city := int(G.get("perCity", 2))
	var maps := []
	for md in data.maps:
		if String(md.get("kind", "")) == "city":
			maps.append(md)
	var by_city := {}
	var n := 0
	for id in sim.state["bots"]:
		var e: Dictionary = sim.ent(int(id))
		var ch: Dictionary = e.get("ch", {})
		if String(ch.get("role", "")) != "constable":
			continue
		n += 1
		var lv := int(ch["level"])
		check(lv >= 50 and lv <= 75, "spawn: 捕快等級喺 50~75 (got %d)" % lv)
		check(ch.has("standPos"), "spawn: 捕快有企定位")
		var cid := String(ch.get("homeCity", ""))
		by_city[cid] = int(by_city.get(cid, 0)) + 1
	check(n == per_city * maps.size(), "spawn: 全部城捕快總數 = %d (got %d)" % [per_city * maps.size(), n])
	check(by_city.size() == maps.size(), "spawn: 每張 city 地圖都有捕快")
	for md in maps:
		var cid := String(md.get("city", ""))
		check(int(by_city.get(cid, 0)) == per_city, "spawn: %s 捕快數 = %d" % [cid, per_city])


# ================= 行為: 巡邏 vs 企定位 =================

func t_patrol_vs_stand(data: GameData) -> void:
	var sim := Sim.new(data, 9)
	sim.add_guards()
	var gid := 0
	for id in sim.state["bots"]:
		if String(sim.ent(int(id)).get("ch", {}).get("role", "")) == "constable":
			gid = int(id)
			break
	check(gid != 0, "行為: 搵到一隻捕快")
	var e: Dictionary = sim.ent(gid)
	var ch: Dictionary = e["ch"]
	var sp: Dictionary = ch["standPos"]
	var stand := Vector2i(int(sp["x"]), int(sp["y"]))
	var clk: Dictionary = sim.state["clock"]
	# 非巡邏時辰 (子時): 已經企喺企定位 (spawn 就喺附近) -> _constable_tick 唔應該設新目的地離開
	e["x"] = stand.x
	e["y"] = stand.y
	e["tx"] = stand.x
	e["ty"] = stand.y
	clk["ke"] = 0   # 子時 (shichen 0)，唔喺 patrolShichen
	BotSys._constable_tick(sim, gid, e, {})
	check(int(e["tx"]) == stand.x and int(e["ty"]) == stand.y, "行為: 非巡邏時辰留喺企定位")
	# 推入巡邏時辰: 應該設新目的地離開企定位去巡邏
	clk["ke"] = 8 * 3   # shichen 3 (卯)，喺 patrolShichen
	BotSys._constable_tick(sim, gid, e, {})
	check(int(e["tx"]) != stand.x or int(e["ty"]) != stand.y, "行為: 巡邏時辰設目的地離開企定位")


# ================= 行為: 見紅名主動打 =================

func t_aggro_lock(data: GameData) -> void:
	var sim := Sim.new(data, 9)
	sim.add_guards()
	var gid := 0
	for id in sim.state["bots"]:
		if String(sim.ent(int(id)).get("ch", {}).get("role", "")) == "constable":
			gid = int(id)
			break
	var e: Dictionary = sim.ent(gid)
	var pid := sim.spawn_player("賊")
	var pe: Dictionary = sim.ent(pid)
	pe["ch"]["karma"] = -20000    # 殺人魔階 = 紅名
	# 城內唔打人: 紅名同捕快都喺城 (安全區) → 唔鎖定
	pe["x"] = int(e["x"])
	pe["y"] = int(e["y"])
	pe["tx"] = int(e["x"])
	pe["ty"] = int(e["y"])
	BotSys._constable_tick(sim, gid, e, {})
	check(int(e["atk_target"]) == 0, "城內: 捕快唔鎖定城內紅名玩家")
	# 野外: 兩個都放喺野區 → 鎖定
	var z: Dictionary = sim.zone_by_id(String(e["ch"]["homeZone"]))
	var wx := (int(z["x0"]) + int(z["x1"])) / 2
	var wy := (int(z["y0"]) + int(z["y1"])) / 2
	for ent_ in [e, pe]:
		ent_["x"] = wx
		ent_["y"] = wy
		ent_["tx"] = wx
		ent_["ty"] = wy
	check(not sim.is_safe(wx, wy), "野外: 野區中心唔係安全區")
	BotSys._constable_tick(sim, gid, e, {})
	check(int(e["atk_target"]) == pid, "紅名: 捕快喺野外鎖定殺人魔玩家")
	# 攻擊者喺城內 (安全區) → 就算鎖定咗都唔出手，並放棄目標
	var inn: Vector2i = sim.inn_pos
	e["x"] = inn.x
	e["y"] = inn.y
	pe["x"] = inn.x
	pe["y"] = inn.y
	e["atk_target"] = pid
	sim._think_player(e)
	check(int(e["atk_target"]) == 0, "城內: 雙方喺安全區 → 唔出手並放棄目標")
	check(int(pe["hp"]) == int(pe["max_hp"]) if pe.has("max_hp") else true, "城內: 玩家冇受傷")
