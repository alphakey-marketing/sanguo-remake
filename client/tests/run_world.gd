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
	t_set_home(data)
	t_trade_cities(data)
	t_orig_map(data)
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
	var exp0 := int(ch["exp"])
	var lv0 := int(ch["level"])
	var hp0 := int(ch["hp"])
	var sp0 := int(ch["sp"])
	sim.cmd_facility(id, "training")
	check(int(ch["level"]) > lv0 or int(ch["exp"]) > exp0, "練兵場: 直接加 EXP")
	check(int(ch["hp"]) < hp0 and int(ch["sp"]) < sp0, "練兵場: 扣 HP/SP")
	var exp1 := int(ch["exp"])
	sim.cmd_facility(id, "training")
	check(int(ch["exp"]) == exp1, "練兵場: 冷卻期間做唔到")
	var sc: Dictionary = data.facilities["school"]
	_put(sim, id, int(sc["x"]), int(sc["y"]))
	var pol0 := int(ch["attrs"]["pol"])
	var gold0 := int(ch["gold"])
	var mp0 := int(ch["mp"])
	var sp1 := int(ch["sp"])
	sim.cmd_facility(id, "school")
	check(int(ch["attrs"]["pol"]) == pol0 + 1, "私塾: 政治 +1")
	check(int(ch["gold"]) == gold0, "私塾: 新手第一次免費 (quest, spec 06 §2)")
	check(int(ch["mp"]) < mp0 and int(ch["sp"]) < sp1, "私塾: 扣 SP/MP")
	sim.cmd_facility(id, "school")
	check(int(ch["gold"]) == gold0 - int(sc["gold"]), "私塾: 第二次先扣金")
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
	check(int(ch["gold"]) == 1000, "寺廟: 新手第一次免費 (quest, spec 06 §2)")


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
	var ip := sim.inn_pos
	check(sim.is_safe(ip.x, ip.y), "安全區: 城內 (客棧) 係安全")
	check(not sim.is_safe(30, 30), "戰鬥區: 野地 (30,30) 唔安全")
	# 城入面追怪唔會真係出手
	_put(sim, id, ip.x, ip.y)
	sim._spawn_mob(1001, "field_1")
	var mob_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob": mob_id = int(e["id"])
	_put(sim, mob_id, ip.x + 1, ip.y)
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


# 建角揀新手城 (spec 12 §1): 3 城可揀、Lv1 先改得、搬去嗰城客棧
func t_set_home(data: GameData) -> void:
	var sim := Sim.new(data, 61)
	var orig_ids: Array = sim.newbie_cities()
	check(bool(data.world.get("origStart", false)) and orig_ids.size() == 1, "原版開局: 只得原版許昌一個新手城")
	var id0 := sim.spawn_player_orig("o")
	check(sim.map_id_at(int(sim.ent(id0)["x"]), int(sim.ent(id0)["y"])) == "xuchang_o", "原版開局: 出生喺 xuchang_o")
	data.world["origStart"] = false      # 以下測舊圖路徑: 新手城都係淨得許昌
	var id := sim.spawn_player("t")
	var ids: Array = []
	for c in sim.newbie_cities():
		ids.append(String(c["id"]))
	check(ids == ["xuchang"], "揀城: 新手城淨係許昌")
	sim.cmd_set_home(id, "xiangyang")
	var ch: Dictionary = sim.player_ch()
	check(String(ch.get("homeCity", "")) != "xiangyang", "揀城: 襄陽唔係新手城，拒絕")
	sim.cmd_set_home(id, "xuchang")
	check(String(ch.get("homeCity", "")) == "xuchang", "揀城: ch.homeCity = 許昌")
	ch["level"] = 2
	sim.cmd_set_home(id, "xuchang")
	check(String(ch.get("homeCity", "")) == "xuchang", "揀城: 出發後 (Lv>1) 仍然係許昌")


# 城際貿易 (spec 05 §6): 平城買、貴城賣，買賣價跟所屬城市場 pf，賺差價
func t_trade_cities(data: GameData) -> void:
	var sim := Sim.new(data, 62)
	var id := sim.spawn_player("t")
	var a := {}
	var b := {}
	var item := 0
	for s1 in data.shops:
		if String(s1.get("map", "")) == "":
			continue
		for s2 in data.shops:
			if String(s2.get("map", "")) == "" or sim._shop_city(String(s2["map"])) == sim._shop_city(String(s1["map"])):
				continue
			for it in s1["stock"]:
				if (s2["stock"] as Array).has(it) and float(data.prices.get(int(it), 0.0)) >= 100.0:
					a = s1
					b = s2
					item = int(it)
					break
			if item != 0:
				break
		if item != 0:
			break
	check(item != 0, "貿易: 搵到兩城同賣一件貨")
	if item == 0:
		return
	var cat := str(int(data.cats.get(item, 0)))
	sim.market_city(sim._shop_city(String(a["map"])), cat)["pf"] = 0.6
	sim.market_city(sim._shop_city(String(b["map"])), cat)["pf"] = 1.9
	check(absf(sim._shop_pf(a, item) - 0.6) < 0.001 and absf(sim._shop_pf(b, item) - 1.9) < 0.001, "貿易: _shop_pf 跟所屬城市場價")
	var ch: Dictionary = sim.player_ch()
	ch["gold"] = 100000
	_put(sim, id, int(a["x"]), int(a["y"]))
	sim.cmd_buy(id, item, 1)
	var g1 := int(ch["gold"])
	var cost := 100000 - g1
	check(cost > 0, "貿易: 平城買到 (花 %d)" % cost)
	_put(sim, id, int(b["x"]), int(b["y"]))
	sim.cmd_sell(id, item, 1)
	var gain := int(ch["gold"]) - g1
	check(gain > cost, "貿易: 貴城賣賺差價 (買 %d 賣 %d)" % [cost, gain])


# 原版許昌測試地圖 (xuchang_o): 邏輯層由原版行走層生成 + 視覺層 OrigMap 載入
func t_orig_map(data: GameData) -> void:
	var md: Dictionary = data.map_by_id.get("xuchang_o", {})
	check(not md.is_empty(), "原版許昌: maps.json 有 xuchang_o")
	if md.is_empty():
		return
	check(int(md["w"]) == 251 and int(md["h"]) == 188, "原版許昌: 格數 251x188 (=4000x3000 px / 16)")
	var om := OrigMap.load_map(String(md.get("orig", "")))
	check(om != null, "原版許昌: OrigMap 載入 (atlas + 物件圖)")
	if om == null:
		return
	check(om.cols == 84 and om.rows == 63 and om.tiles.size() == 84 * 63, "原版許昌: 地形 84x63 格")
	check(om.objs.size() >= 500, "原版許昌: 物件 >= 500 (%d)" % om.objs.size())
	var sp: Array = md["spawn"]
	var gx := int(sp[0])   # spawn 載入後已係全域座標
	var gy := int(sp[1])
	var sim := Sim.new(data, 1)
	check(sim.is_free(gx, gy), "原版許昌: 出生點可行走")
	check(String(data.map_at(gx, gy).get("id", "")) == "xuchang_o", "原版許昌: map_at 對返 xuchang_o")
	var blocked := 0
	for i in range(int(md["w"]) * int(md["h"])):
		var x := int(md["ox"]) + i % int(md["w"])
		var y := int(md["oy"]) + i / int(md["w"])
		if not sim.is_free(x, y):
			blocked += 1
	check(blocked > 15000 and blocked < 35000, "原版許昌: 阻擋格數合理 (%d)" % blocked)
	# 步驟 3: 連通性 + A* 尋路 (出生點 flood fill; 最遠可達格 A* 要搵到路)
	var W := GameData.WORLD_W
	var ow := int(md["w"])
	var oh := int(md["h"])
	var ox := int(md["ox"])
	var oy := int(md["oy"])
	var seen := {}
	var q: Array = [gy * W + gx]
	seen[q[0]] = true
	var far: int = q[0]
	var qi := 0
	while qi < q.size():
		var c: int = q[qi]
		qi += 1
		far = c
		var cx := c % W
		var cy := c / W
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + d[0]
			var ny: int = cy + d[1]
			if nx < ox or ny < oy or nx >= ox + ow or ny >= oy + oh:
				continue
			var nc := ny * W + nx
			if not seen.has(nc) and data.walk[nc] != 0:
				seen[nc] = true
				q.append(nc)
	var open_total := ow * oh - blocked
	check(seen.size() * 100 >= open_total * 70, "原版許昌: 出生點連通 >=70%% 可行走格 (%d/%d)" % [seen.size(), open_total])
	var t0 := Time.get_ticks_msec()
	var pth := RulesPath.find(data.walk, W, gy * W + gx, far, 200000, data.portal_at)
	check(not RulesPath.find(data.walk, W, gy * W + gx, far, Sim.PATH_CAP, data.portal_at).is_empty(), "原版許昌: 預設 PATH_CAP 搵得到最遠路")
	_orig_interiors(data, seen)
	var st_o: Dictionary = data.facilities.get("station_xc", {})
	check(not st_o.is_empty() and seen.has(int(st_o.y) * W + int(st_o.x)), "原版許昌: 驛站位行得到")
	check(not pth.is_empty(), "原版許昌: A* 出生點 → 最遠可達格 (路長 %d, %d ms)" % [pth.size(), Time.get_ticks_msec() - t0])

# 原版室內圖: 城內門 <-> 室內出口成對、踩門入屋、踩出口返城、客棧喺 xc1902 內
func _orig_interiors(data: GameData, city_seen: Dictionary) -> void:
	var W := GameData.WORLD_W
	var n_pair := 0
	for p in data.travel_points:
		var pid := String(p["id"])
		if not pid.begins_with("xc_in_"):
			continue
		n_pair += 1
		var back := data.tp_by_id.get(String(p["to"]), {}) as Dictionary
		check(not back.is_empty() and String(back["to"]) == pid, "原版室內: %s 成對" % pid)
		var land: Array = back["land"]
		check(data.walk[int(land[1]) * W + int(land[0])] == 1 and not data.portal_at.has(int(land[1]) * W + int(land[0])), "原版室內: %s 落地點行得且唔係觸發格" % pid)
		var cl: Array = p["land"]
		check(city_seen.has(int(cl[1]) * W + int(cl[0])), "原版室內: %s 返城落地點喺城內連通區" % pid)
	check(n_pair >= 20, "原版室內: 入屋門 >= 20 (%d)" % n_pair)
	var inn_o: Dictionary = {}
	for iv in data.inns:
		if String(iv.get("map", "")) == "xc1902":
			inn_o = iv
	check(not inn_o.is_empty() and data.walk[int(inn_o.y) * W + int(inn_o.x)] == 1, "原版室內: 客棧喺 xc1902 內行得到")
	var sim := Sim.new(data, 1)
	var door := data.tp_by_id.get("xc_in_1902", {}) as Dictionary
	var rc: Array = door["rect"]
	var id := sim.spawn_player("入屋")
	var e := sim.ent(id)
	for cy in range(int(rc[1]), int(rc[3]) + 1):
		for cx in range(int(rc[0]), int(rc[2]) + 1):
			if data.portal_at.get(cy * W + cx, "") == "xc_in_1902":
				e["x"] = cx
				e["y"] = cy
				sim._on_moved(e)
				check(String(data.map_at(int(e["x"]), int(e["y"])).get("id", "")) == "xc1902", "原版室內: 踩客棧門 → 入 xc1902")
				sim._on_moved(e)
				check(String(data.map_at(int(e["x"]), int(e["y"])).get("id", "")) == "xc1902", "原版室內: 落地後唔會即刻彈返")
				return
