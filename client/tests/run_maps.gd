extends SceneTree
# 地圖世界測試 (spec 12 §7): 地圖檔格式 / 數據落點 / 連通 / A* / 自動過圖 / 跨圖路由 / 地標 / 存檔。
# B2 (Step 11.7): 新地圖連通/傳送點成對 / 大地圖自動尋路 / 新野客棧/商店 / 死亡返最近客棧。
# B2.5 (Step 16 前置): 陳留/于毒山寨/小沛/汝南城/丁府/宛城/荊州地界/港口/樊城/漢水渡口/襄陽/監獄/長沙。
# 跑: Godot --headless --path client --script tests/run_maps.gd   (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_files(data)
	t_gaps(data)
	t_placements(data)
	t_connected(data)
	t_astar(data)
	t_move_across_river(data)
	t_auto_portal(data)
	t_route_bots(data)
	t_landmark(data)
	t_zone_area(data)
	t_path_save(data)
	t_art(data)
	t_old_save(data)
	t_b2_links(data)
	t_goto(data)
	t_goto_save(data)
	t_xinye(data)
	t_b25(data)
	t_b25_goto(data)
	print("[TEST] maps: %d, fail %d" % [total, fails])
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
	e.erase("path")


func _portal(data: GameData, id: String) -> Dictionary:
	for p in data.travel_points:
		if String(p["id"]) == id:
			return p
	return {}


# 地圖檔: 每行等闊、字元全部喺 legend、ASCII
func t_files(data: GameData) -> void:
	for md in data.maps:
		var rows := FileAccess.get_file_as_string("res://data/maps/%s.txt" % md["id"]).replace("\r", "").split("\n", false)
		var bad_w := 0
		var bad_c := {}
		for r in rows:
			if r.length() != int(md["w"]):
				bad_w += 1
			for i in r.length():
				if not data.legend.has(r[i]):
					bad_c[r[i]] = true
		check(bad_w == 0, "%s: 每行一樣闊 (%d 行唔啱)" % [md["id"], bad_w])
		check(bad_c.is_empty(), "%s: 字元全部喺 legend (%s)" % [md["id"], bad_c.keys()])


# 地圖之間最少隔 20 格 (怪仇恨/術法範圍唔會跨圖)
func t_gaps(data: GameData) -> void:
	for i in data.maps.size():
		for j in range(i + 1, data.maps.size()):
			var a: Dictionary = data.maps[i]
			var b: Dictionary = data.maps[j]
			var ra := Rect2i(int(a.ox), int(a.oy), int(a.w), int(a.h)).grow(10)
			var rb := Rect2i(int(b.ox), int(b.oy), int(b.w), int(b.h)).grow(10)
			check(not ra.intersects(rb), "地圖間隔 ≥ 20: %s / %s" % [a.id, b.id])


# 所有傳送點/商店/客棧/設施/任務 NPC/地標 落喺行得嘅格；spawn area 有行得格
func t_placements(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	var pts: Array = [["客棧", data.inn]]
	for s in data.shops:
		pts.append(["商店 " + str(s["id"]), s])
	for k in data.facilities:
		if data.facilities[k] is Dictionary:
			pts.append(["設施 " + str(k), data.facilities[k]])
	for n in data.quest_npc_list:
		pts.append(["NPC " + str(n["id"]), n])
	for p in data.travel_points:
		pts.append(["傳送點 " + str(p["id"]), p])
	for lm in data.landmarks:
		pts.append(["地標 " + str(lm["id"]), lm])
	for it in pts:
		var o: Dictionary = it[1]
		check(sim.is_free(int(o["x"]), int(o["y"])), "%s (%d,%d) 行得" % [it[0], int(o["x"]), int(o["y"])])
		if o.has("map"):
			check(sim.map_id_at(int(o["x"]), int(o["y"])) == String(o["map"]), "%s 喺 %s 入面" % [it[0], o["map"]])
	for sp in data.spawns:
		var a: Array = sp["area"]
		var n := 0
		for x in range(int(a[0]), int(a[2]) + 1):
			for y in range(int(a[1]), int(a[3]) + 1):
				if sim.is_free(x, y) and sim.map_id_at(x, y) == String(sp["zone"]):
					n += 1
		check(n >= 10, "spawn %s@%s 有行得格 (%d)" % [sp["monster"], sp["zone"], n])
	# PK 任務 boss 出喺 NPC 隔籬 (+1,+1)
	var so: Dictionary = data.quest_npcs["stray_soldier"]
	check(sim.is_free(int(so["x"]) + 1, int(so["y"]) + 1), "守門流浪兵隔籬 (boss 位) 行得")
	# 城內出生範圍
	var md: Dictionary = data.map_by_id["xuchang"]
	var s: Array = md["spawn"]
	check(sim.is_free(int(s[0]), int(s[1])) or sim.is_free(int(s[2]), int(s[3])), "許昌出生範圍有行得格")


# 每張地圖行得嘅格全部連通
func t_connected(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	for md in data.maps:
		var start := Vector2i(-1, -1)
		var total_walk := 0
		for y in int(md.h):
			for x in int(md.w):
				if sim.is_free(int(md.ox) + x, int(md.oy) + y):
					total_walk += 1
					if start.x < 0:
						start = Vector2i(int(md.ox) + x, int(md.oy) + y)
		var seen := {start: true}
		var q: Array = [start]
		while not q.is_empty():
			var c: Vector2i = q.pop_back()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if not seen.has(n) and sim.is_free(n.x, n.y):
					seen[n] = true
					q.append(n)
		check(seen.size() == total_walk, "%s: 行得格全部連通 (%d/%d)" % [md.id, seen.size(), total_walk])


# A*: 繞過潁水 (經橋)、決定性、唔經 auto 傳送點、每步相鄰
func t_astar(data: GameData) -> void:
	var W := GameData.WORLD_W
	var from := 30 * W + 30                   # 許田圍場 (北岸)
	var to := 70 * W + 80                     # 潁水南岸
	var p1 := RulesPath.find(data.walk, W, from, to, 20000, data.portal_at)
	var p2 := RulesPath.find(data.walk, W, from, to, 20000, data.portal_at)
	check(not p1.is_empty(), "A*: 北岸 → 南岸 搵到路")
	check(p1 == p2, "A*: 決定性 (兩次一樣)")
	var ok := true
	var prev := from
	var bridge := false
	for c in p1:
		if absi(int(c) - prev) != 1 and absi(int(c) - prev) != W:
			ok = false
		if data.walk[int(c)] != 1:
			ok = false
		if char(data.tiles[int(c)]) == "b":
			bridge = true
		prev = int(c)
	check(ok, "A*: 每步相鄰 + 行得")
	check(bridge, "A*: 過河經橋")
	check(not p1.is_empty() and int(p1[-1]) == to, "A*: 終點啱")
	# 唔經傳送點: 由洞口隔籬行去另一邊，路徑唔包 cave_enter (終點除外)
	var ce := _portal(data, "cave_enter")
	var cc := int(ce["y"]) * W + int(ce["x"])
	var p3 := RulesPath.find(data.walk, W, cc + W * 0 - 1, 40 * W + 40, 20000, data.portal_at)
	check(not p3.has(cc), "A*: 唔經 auto 傳送點")
	check(RulesPath.find(data.walk, W, from, from, 100).is_empty(), "A*: 起點 = 終點 → 空")
	check(RulesPath.find(data.walk, W, from, 2 * W + 0, 20000).is_empty(), "A*: 終點行唔到 → 空")
	check(RulesPath.find(data.walk, W, from, to, 50).is_empty(), "A*: 超過節點上限 → 空")


# 實際行: cmd_move 過河，有限 tick 內到達
func t_move_across_river(data: GameData) -> void:
	var sim := Sim.new(data, 3)
	var id := sim.spawn_player("t")
	_put(sim, id, 30, 30)
	sim.cmd_move(id, 80, 70)
	check(sim.ent(id).has("path"), "行路: 直線唔通 → 有 A* 路徑")
	for i in 400:
		sim.step()
		var e := sim.ent(id)
		if int(e["x"]) == 80 and int(e["y"]) == 70:
			break
	var e2 := sim.ent(id)
	check(int(e2["x"]) == 80 and int(e2["y"]) == 70, "行路: 過咗河到達 (而家 %d,%d)" % [int(e2["x"]), int(e2["y"])])
	check(not e2.has("path"), "行路: 到咗清路徑")
	# 手動改目的地 → 舊路徑作廢
	sim.cmd_move(id, 30, 30)
	sim.ent(id)["tx"] = 71
	sim.step()
	check(not sim.ent(id).has("path"), "行路: 目的地被改 → 路徑作廢")


# 踩城門自動過圖；落地唔會即刻彈返轉頭
func t_auto_portal(data: GameData) -> void:
	var sim := Sim.new(data, 4)
	var id := sim.spawn_player("t")
	var go := _portal(data, "gate_out")
	var gi := _portal(data, "gate_in")
	_put(sim, id, int(go["x"]), int(go["y"]) - 1)
	var travels := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "travel":
			travels.append(ev))
	sim.cmd_move(id, int(go["x"]), int(go["y"]))
	for i in 3:
		sim.step()
	var e := sim.ent(id)
	check(travels.size() == 1 and sim.map_id_at(int(e["x"]), int(e["y"])) == "field_1", "過圖: 踩南門 → 潁川郊外")
	check(int(e["x"]) == int(gi["x"]) and int(e["y"]) == int(gi["y"]), "過圖: 落地喺北口")
	check(travels.size() == 1 and String(travels[0].get("map", "")) == "field_1", "過圖: travel 事件帶 map")
	for i in 10:
		sim.step()
	check(travels.size() == 1, "過圖: 企喺落地點唔會彈返")
	# 行開再踩返 = 返城
	sim.cmd_move(id, int(gi["x"]), int(gi["y"]) + 2)
	for i in 4:
		sim.step()
	sim.cmd_move(id, int(gi["x"]), int(gi["y"]))
	for i in 4:
		sim.step()
	check(travels.size() == 2 and sim.map_id_at(int(sim.ent(id)["x"]), int(sim.ent(id)["y"])) == "xuchang", "過圖: 行返北口 → 返許昌")
	# 怪唔會過圖
	var mob: Variant = sim._spawn_mob(1002, "field_1")
	_put(sim, int(mob["id"]), int(gi["x"]), int(gi["y"]) + 1)
	sim.ent(int(mob["id"]))["tx"] = int(gi["x"])
	sim.ent(int(mob["id"]))["ty"] = int(gi["y"])
	sim.step()
	check(sim.map_id_at(int(mob["x"]), int(mob["y"])) == "field_1", "過圖: 怪唔會踩門口過圖")


# 居民由城入面自己經門口出野外；next_portal 啱
func t_route_bots(data: GameData) -> void:
	var sim := Sim.new(data, 8)
	check(String(sim.next_portal("xuchang", "field_1").get("id", "")) == "gate_out", "路由: 許昌 → 郊外 = 南門")
	check(String(sim.next_portal("xuchang", "runan_f3").get("id", "")) == "gate_out", "路由: 許昌 → 洞窟 3F 第一跳 = 南門")
	check(String(sim.next_portal("runan_f3", "xuchang").get("id", "")) == "f3_up", "路由: 洞窟 3F → 許昌 第一跳 = 上層")
	check(sim.next_portal("xuchang", "xuchang").is_empty(), "路由: 同一張圖 = 冇")
	sim.init_mobs()
	sim.add_bots(4)
	for i in 300:
		sim.step()
	var out := 0
	for id in sim.state["bots"]:
		var e := sim.ent(int(id))
		if sim.map_id_at(int(e["x"]), int(e["y"])) != "xuchang":
			out += 1
	check(out >= 3, "居民: 300 tick 內自己出城 (%d/4)" % out)


# 地標: 第一次行近先彈；記入 ch.landmarks
func t_landmark(data: GameData) -> void:
	var sim := Sim.new(data, 5)
	var id := sim.spawn_player("t")
	var lm: Dictionary = {}
	for x in data.landmarks:
		if String(x["id"]) == "xutian":
			lm = x
	var evs := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "landmark":
			evs.append(ev))
	_put(sim, id, int(lm["x"]) - 10, int(lm["y"]))
	sim.cmd_move(id, int(lm["x"]), int(lm["y"]))
	for i in 12:
		sim.step()
	check(evs.size() == 1 and String(evs[0]["id"]) == "xutian", "地標: 行近彈典故")
	check((sim.player_ch().get("landmarks", []) as Array).has("xutian"), "地標: 記入 ch.landmarks")
	sim.cmd_move(id, int(lm["x"]) - 10, int(lm["y"]))
	for i in 12:
		sim.step()
	sim.cmd_move(id, int(lm["x"]), int(lm["y"]))
	for i in 12:
		sim.step()
	check(evs.size() == 1, "地標: 第二次唔再彈")


func t_zone_area(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	var zv := sim.zone_view(32, 38)
	check(String(zv.get("id", "")) == "field_1" and String(zv.get("area", "")) == "許田圍場", "區名: (32,38) = 潁川郊外/許田圍場 (%s)" % zv)
	check(String(sim.zone_view(sim.inn_pos.x, sim.inn_pos.y).get("name", "")) == "許昌城", "區名: 客棧喺許昌城")
	check(sim.zone_view(125, 5).is_empty(), "區名: 地圖之間虛空 = {}")
	check(not sim.is_free(125, 5), "虛空行唔到")


# 行路中途存檔 → 讀返續跑一致 (路徑入存檔)
func t_path_save(data: GameData) -> void:
	var a := Sim.new(data, 12)
	var id := a.spawn_player("t")
	_put(a, id, 30, 30)
	a.cmd_move(id, 80, 70)
	for i in 20:
		a.step()
	check(a.ent(id).has("path"), "存檔: 行緊有路徑")
	var s := a.save_string()
	var b := Sim.load_string(data, s)
	check(b != null and b.save_string() == s, "存檔: 帶路徑 roundtrip 一致")
	for i in 200:
		a.step()
		b.step()
	check(a.save_string() == b.save_string(), "存檔: 讀檔後續行一致")
	check(int(b.ent(id)["x"]) == 80 and int(b.ent(id)["y"]) == 70, "存檔: 讀檔後照行到終點")


# 地圖貼圖/小地圖 render 得 (headless 都得)
func t_art(data: GameData) -> void:
	for md in data.maps:
		var img := MapArt._render(data, md, 16)
		check(img.get_width() == int(md.w) * 16 and img.get_height() == int(md.h) * 16, "貼圖尺寸 %s" % md.id)
	var mini := MapArt.minimap(data, data.map_by_id["xuchang"])
	check(mini != null and mini.get_width() == int(data.map_by_id["xuchang"]["w"]), "小地圖尺寸")


# 舊存檔 (舊地圖座標) 讀返: 企錯位嘅人搬返客棧、怪搬返 spawn 範圍
func t_old_save(data: GameData) -> void:
	var a := Sim.new(data, 2)
	a.init_mobs()
	var id := a.spawn_player("t")
	var md: Dictionary = data.map_by_id["xuchang"]
	_put(a, id, int(md["ox"]) + 3, int(md["oy"]) + 20)        # 城牆入面
	var mid := 0
	for e in a.ents.values():
		if e["kind"] == "mob":
			mid = int(e["id"])
	_put(a, mid, 125, 5)                                       # 虛空
	var b := Sim.load_string(data, a.save_string())
	var p := b.ent(id)
	check(int(p["x"]) == b.inn_pos.x and int(p["y"]) == b.inn_pos.y, "舊存檔: 企錯位 → 搬返客棧")
	var m := b.ent(mid)
	check(b.is_free(int(m["x"]), int(m["y"])) and b.map_id_at(int(m["x"]), int(m["y"])) == String(m["mob"]["zone"]), "舊存檔: 怪搬返自己地圖")
	check(Sim.load_string(data, b.save_string()).save_string() == b.save_string(), "舊存檔: 修正後 roundtrip 一致")


# B2: 傳送點成對、全部地圖由許昌去得、大地圖節點地圖存在、新野路線、博望南口新手友善
func t_b2_links(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	var bad := []
	for p in data.travel_points:
		var to := sim.travel_point_by_id(String(p["to"]))
		if to.is_empty() or String(to["to"]) != String(p["id"]):
			bad.append(p["id"])
	check(bad.is_empty(), "傳送點全部成對 (%s)" % [bad])
	for md in data.maps:
		if bool(md.get("instance", false)):
			continue     # 戰役等實例場景 (Step 19): 冇門連去，靠 sim 直接傳送
		check(sim.map_hops("xuchang", String(md["id"])) >= 0, "由許昌去得 %s" % md["id"])
	for n in data.world_map["nodes"]:
		if n.get("map") != null:
			check(data.map_by_id.has(String(n["map"])), "天下節點 %s 地圖存在" % n["id"])
	for e in data.world_map["edges"]:
		var ids: Array = data.world_map["nodes"].map(func(n): return String(n["id"]))
		check(ids.has(String(e[0])) and ids.has(String(e[1])), "天下路線 %s 節點存在" % [e])
	for mid in ["runan_road", "kunyang", "wancheng_road", "bowang", "xinye"]:
		var nd: Array = data.world_map["nodes"].filter(func(n): return n.get("map") != null and String(n["map"]) == mid)
		check(nd.size() == 1, "B2 %s 喺天下已開放" % mid)
	check(sim.map_hops("xuchang", "xinye") == 5, "許昌 → 新野 過 5 次圖 (%d)" % sim.map_hops("xuchang", "xinye"))
	check(String(sim.next_portal("xuchang", "xinye").get("id", "")) == "gate_out", "路由: 許昌 → 新野 第一跳 = 南門")
	check(String(sim.next_portal("xinye", "xuchang").get("id", "")) == "xy_north", "路由: 新野 → 許昌 第一跳 = 北門")
	check(String(sim.next_portal("runan_road", "runan_f1").get("id", "")) == "rr_cave", "路由: 汝南道 → 洞窟 = 後洞")
	check(sim.map_hops("runan_f1", "runan_road") == 1, "洞窟 1F ↔ 汝南道 相連")
	check(data.map_by_id["xinye"]["safe"] and not data.map_by_id["bowang"]["safe"], "新野安全、博望坡野區")
	# 博望坡南口 (新野出城落地點) 6 格內只出 Lv≤2
	var bs := sim.travel_point_by_id("bw_south")
	for sp in data.spawns:
		if String(sp["zone"]) != "bowang" or int(data.monsters[int(sp["monster"])]["level"]) <= 2:
			continue
		var a: Array = sp["area"]
		var dx := maxi(0, maxi(int(a[0]) - int(bs["x"]), int(bs["x"]) - int(a[2])))
		var dy := maxi(0, maxi(int(a[1]) - int(bs["y"]), int(bs["y"]) - int(a[3])))
		check(maxi(dx, dy) > 6, "博望南口 6 格內冇 Lv3+ 怪 (%s)" % sp["monster"])


# 大地圖自動尋路: 許昌 → 新野 (過 5 次圖)、行一步取消、同圖/未知地圖唔理
func t_goto(data: GameData) -> void:
	var sim := Sim.new(data, 21)
	var id := sim.spawn_player("t")
	var evs := []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "goto_done" or ev["k"] == "travel":
			evs.append(ev))
	sim.cmd_goto_map(id, "xinye")
	check(String(sim.ent(id).get("goto", "")) == "xinye", "尋路: 設咗目的地")
	var n := 0
	while n < 3000 and sim.ent(id).has("goto"):
		sim.step()
		n += 1
	var e := sim.ent(id)
	check(sim.map_id_at(int(e["x"]), int(e["y"])) == "xinye", "尋路: 許昌 → 新野 到達 (%d tick, 而家 %s)" % [n, sim.map_id_at(int(e["x"]), int(e["y"]))])
	check(not e.has("goto"), "尋路: 到咗清目的地")
	var travels := evs.filter(func(v): return v["k"] == "travel")
	check(travels.size() == 5, "尋路: 過 5 次圖 (%d)" % travels.size())
	check(evs.size() > 0 and evs[-1]["k"] == "goto_done" and String(evs[-1]["map"]) == "xinye", "尋路: goto_done 事件")
	# 返程再中途手動行 = 取消
	sim.cmd_goto_map(id, "xuchang")
	for i in 20:
		sim.step()
	var x := int(sim.ent(id)["x"])
	var y := int(sim.ent(id)["y"])
	sim.cmd_move(id, x, y)
	check(not sim.ent(id).has("goto"), "尋路: 手動行 = 取消")
	# 同一張圖 / 未知地圖 / 去唔到
	sim.cmd_goto_map(id, sim.map_id_at(x, y))
	check(not sim.ent(id).has("goto"), "尋路: 已經喺目的地圖 = 唔設")
	sim.cmd_goto_map(id, "nowhere")
	check(not sim.ent(id).has("goto"), "尋路: 未知地圖 = 唔設")
	# 死亡取消
	sim.cmd_goto_map(id, "runan_road")
	sim._kill_player(sim.ent(id))
	check(not sim.ent(id).has("goto"), "尋路: 死亡 = 取消")


# 尋路中途存檔 → 讀返續行一致 (有怪有居民)
func t_goto_save(data: GameData) -> void:
	var a := Sim.new(data, 22)
	a.init_mobs()
	var id := a.spawn_player("t")
	a.cmd_goto_map(id, "xinye")
	for i in 150:
		a.step()
	check(a.ent(id).has("goto"), "尋路存檔: 行緊")
	var s := a.save_string()
	var b := Sim.load_string(data, s)
	check(b != null and b.save_string() == s, "尋路存檔: roundtrip 一致")
	for i in 300:
		a.step()
		b.step()
	check(a.save_string() == b.save_string(), "尋路存檔: 讀檔後續行一致")


# 新野: 客棧休息 / 商店買嘢 / 死亡返最近客棧
func t_xinye(data: GameData) -> void:
	var sim := Sim.new(data, 23)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.ent(id)["ch"]
	var inn: Dictionary = data.inns.filter(func(x): return String(x["id"]) == "xinye")[0]
	check(sim.map_id_at(int(inn["x"]), int(inn["y"])) == "xinye", "新野客棧喺新野城")
	_put(sim, id, int(inn["x"]), int(inn["y"]))
	ch["level"] = GameData.NEWBIE_LEVEL
	ch["gold"] = 100
	sim.ent(id)["hp"] = 1
	sim.cmd_rest(id)
	check(int(ch["gold"]) == 100 - int(inn["restCost"]) and int(sim.ent(id)["hp"]) > 1, "新野客棧: 休息扣錢回血")
	var shop: Dictionary = data.shops.filter(func(x): return String(x["id"]) == "weapon_xy")[0]
	_put(sim, id, int(shop["x"]), int(shop["y"]))
	ch["gold"] = 1000
	var item := int(shop["stock"][0])
	sim.cmd_buy(id, item, 1)
	check(RulesShop.count_item(ch["bag"], item) >= 1 and int(ch["gold"]) < 1000, "新野武器店: 買到嘢")
	# 死亡: 冇復活道具 → 先倒地【自訂新增】，撳「回城復活」先傳返最近客棧: 博望坡 → 新野客棧；潁川郊外 → 許昌客棧
	var self_ticks := int(data.world["combat"]["playerDownSelfTicks"])
	var bw: Dictionary = data.map_by_id["bowang"]
	_put(sim, id, int(bw["ox"]) + 48, int(bw["oy"]) + 30)
	sim._kill_player(sim.ent(id))
	for _i in self_ticks: sim.step()
	sim.cmd_self_revive(id)
	check(int(sim.ent(id)["x"]) == int(inn["x"]) and int(sim.ent(id)["y"]) == int(inn["y"]), "死亡: 博望坡 → 返新野客棧")
	_put(sim, id, 30, 30)
	sim._kill_player(sim.ent(id))
	for _i in self_ticks: sim.step()
	sim.cmd_self_revive(id)
	check(int(sim.ent(id)["x"]) == sim.inn_pos.x and int(sim.ent(id)["y"]) == sim.inn_pos.y, "死亡: 潁川郊外 → 返許昌客棧")
	var rr: Dictionary = data.map_by_id["runan_road"]
	_put(sim, id, int(rr["ox"]) + 10, int(rr["oy"]) + 20)
	sim._kill_player(sim.ent(id))
	for _i in self_ticks: sim.step()
	sim.cmd_self_revive(id)
	check(sim.map_id_at(int(sim.ent(id)["x"]), int(sim.ent(id)["y"])) == "runan_city", "死亡: 汝南道 → 返汝南客棧 (B2.5)")


# B2.5: 新地圖開放 / 路線過圖數 / 室內 parent / 新城客棧+商店 / 死亡返最近客棧 / 怪等級帶
func t_b25(data: GameData) -> void:
	var sim := Sim.new(data, 24)
	var new_maps := ["chenliu", "yudu", "xiaopei", "runan_city", "ding_fu", "wancheng", "jingzhou",
		"gangkou", "fancheng", "hanshui", "xiangyang", "xy_prison", "changsha"]
	for mid in new_maps:
		check(data.map_by_id.has(mid), "B2.5 地圖存在: %s" % mid)
		var md: Dictionary = data.map_by_id.get(mid, {})
		if String(md.get("kind", "")) == "house":
			check(data.map_by_id.has(String(md.get("parent", ""))) and bool(md["safe"]), "室內 %s: 有 parent + 安全" % mid)
		else:
			var nd: Array = data.world_map["nodes"].filter(func(n): return n.get("map") != null and String(n["map"]) == mid)
			check(nd.size() == 1, "B2.5 %s 喺天下已開放" % mid)
	var hops := {"chenliu": 1, "yudu": 2, "xiaopei": 2, "runan_city": 3, "ding_fu": 4, "wancheng": 4}
	for mid in hops:
		check(sim.map_hops("xuchang", mid) == int(hops[mid]), "許昌 → %s 過 %d 次圖 (%d)" % [mid, hops[mid], sim.map_hops("xuchang", mid)])
	var hops2 := {"jingzhou": 1, "gangkou": 2, "fancheng": 1, "hanshui": 2, "xiangyang": 3, "xy_prison": 4, "changsha": 4}
	for mid in hops2:
		check(sim.map_hops("xinye", mid) == int(hops2[mid]), "新野 → %s 過 %d 次圖 (%d)" % [mid, hops2[mid], sim.map_hops("xinye", mid)])
	check(sim.map_hops("xuchang", "xinye") == 5, "許昌 → 新野 仍然 5 次")
	check(String(sim.next_portal("xuchang", "chenliu").get("id", "")) == "gate_north", "路由: 許昌 → 陳留 = 北門")
	check(String(sim.next_portal("xinye", "gangkou").get("id", "")) == "xy_west", "路由: 新野 → 港口 = 西門")
	check(String(sim.next_portal("xinye", "xiangyang").get("id", "")) == "xy_south", "路由: 新野 → 襄陽 = 南門")
	check(String(sim.next_portal("runan_road", "runan_f1").get("id", "")) == "rr_cave", "路由: 汝南道 → 洞窟 仍然 = 後洞")
	# 新城客棧休息 + 武器店買嘢
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.ent(id)["ch"]
	for iid in ["runan", "wancheng", "xiangyang"]:
		var inn: Dictionary = data.inns.filter(func(x): return String(x["id"]) == iid)[0]
		_put(sim, id, int(inn["x"]), int(inn["y"]))
		ch["level"] = GameData.NEWBIE_LEVEL
		ch["gold"] = 100
		sim.ent(id)["hp"] = 1
		sim.cmd_rest(id)
		check(int(ch["gold"]) == 100 - int(inn["restCost"]) and int(sim.ent(id)["hp"]) > 1, "%s: 休息扣錢回血" % inn["name"])
	for sid in ["weapon_rn", "armor_wc", "weapon_xyc"]:
		var shop: Dictionary = data.shops.filter(func(x): return String(x["id"]) == sid)[0]
		_put(sim, id, int(shop["x"]), int(shop["y"]))
		ch["gold"] = 1000
		var item := int(shop["stock"][0])
		var before := RulesShop.count_item(ch["bag"], item)
		sim.cmd_buy(id, item, 1)
		check(RulesShop.count_item(ch["bag"], item) == before + 1 and int(ch["gold"]) < 1000, "%s: 買到嘢" % shop["name"])
	# 死亡返最近客棧
	var deaths := {"chenliu": "xuchang", "yudu": "xuchang", "gangkou": "xinye", "fancheng": "xinye",
		"hanshui": "xiangyang", "wancheng_road": "wancheng", "ding_fu": "runan_city"}
	for mid in deaths:
		var md: Dictionary = data.map_by_id[mid]
		var spot := Vector2i(-1, -1)
		for y in int(md["h"]):
			for x in int(md["w"]):
				if spot.x < 0 and sim.is_free(int(md["ox"]) + x, int(md["oy"]) + y):
					spot = Vector2i(int(md["ox"]) + x, int(md["oy"]) + y)
		_put(sim, id, spot.x, spot.y)
		sim._kill_player(sim.ent(id))
		for _i in int(data.world["combat"]["playerDownSelfTicks"]): sim.step()
		sim.cmd_self_revive(id)
		var at := sim.map_id_at(int(sim.ent(id)["x"]), int(sim.ent(id)["y"]))
		check(at == String(deaths[mid]), "死亡: %s → 返 %s 客棧 (%s)" % [mid, deaths[mid], at])
	# 怪物等級帶: 陳留 9~20、山寨 11~14、荊州地界 9~11、港口 12~15、樊城 11~14、漢水 16~20；城/室內冇怪
	var bands := {"chenliu": [9, 20], "yudu": [11, 14], "jingzhou": [9, 11], "gangkou": [12, 15], "fancheng": [11, 14], "hanshui": [16, 20]}
	for mid in new_maps:
		var lvs: Array = []
		for sp in data.spawns:
			if String(sp["zone"]) == mid:
				lvs.append(int(data.monsters[int(sp["monster"])]["level"]))
		if bands.has(mid):
			check(not lvs.is_empty() and lvs.min() >= int(bands[mid][0]) and lvs.max() <= int(bands[mid][1]),
				"%s 怪 Lv%d~%d (%s)" % [mid, bands[mid][0], bands[mid][1], lvs])
		else:
			check(lvs.is_empty() and bool(data.map_by_id[mid]["safe"]), "%s 安全冇怪" % mid)
	# 新怪有掉落 (導入自原版表)
	for mid_ in [11072, 11069, 27248, 27005, 27008]:
		var m: Dictionary = data.monsters.get(mid_, {})
		check(not m.is_empty() and (m.get("drops", []).size() + m.get("rareDrops", []).size()) > 0, "新怪 %d 有掉落" % mid_)
	# 港口東北口 (入口落地) 6 格內冇怪 spawn 區
	var gk := sim.travel_point_by_id("gk_ne")
	for sp in data.spawns:
		if String(sp["zone"]) != "gangkou":
			continue
		var a: Array = sp["area"]
		var dx := maxi(0, maxi(int(a[0]) - int(gk["x"]), int(gk["x"]) - int(a[2])))
		var dy := maxi(0, maxi(int(a[1]) - int(gk["y"]), int(gk["y"]) - int(a[3])))
		check(maxi(dx, dy) > 2, "港口入口 2 格內冇 spawn 區 (%s)" % sp["monster"])


# B2.5 大地圖自動尋路: 許昌 → 襄陽 (8 次過圖)、新野 → 港口、許昌 → 小沛
func t_b25_goto(data: GameData) -> void:
	for pair in [["xuchang", "xiangyang", 8], ["xuchang", "xiaopei", 2], ["xuchang", "yudu", 2]]:
		var sim := Sim.new(data, 25)
		var id := sim.spawn_player("t")
		var n_travel := [0]
		sim.event_emitted.connect(func(ev: Dictionary) -> void:
			if ev["k"] == "travel":
				n_travel[0] += 1)
		sim.cmd_goto_map(id, String(pair[1]))
		var n := 0
		while n < 12000 and sim.ent(id).has("goto"):
			sim.step()
			n += 1
		var e := sim.ent(id)
		check(sim.map_id_at(int(e["x"]), int(e["y"])) == String(pair[1]), "尋路: 許昌 → %s 到達 (%d tick)" % [pair[1], n])
		check(n_travel[0] == int(pair[2]), "尋路: 許昌 → %s 過 %d 次圖 (%d)" % [pair[1], pair[2], n_travel[0]])
