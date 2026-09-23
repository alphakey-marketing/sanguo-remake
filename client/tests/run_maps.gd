extends SceneTree
# 地圖世界測試 (spec 12 §7): 地圖檔格式 / 數據落點 / 連通 / A* / 自動過圖 / 跨圖路由 / 地標 / 存檔。
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
