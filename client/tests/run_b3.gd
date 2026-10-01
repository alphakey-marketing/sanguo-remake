extends SceneTree
# 地圖 B3 測試 (Step 16.5, spec 12 §1): 隆中 + 草廬 (地圖/連通/怪/地標/自動尋路) /
# 驛站快速傳送 (純函數、車費、唔喺驛站/唔夠錢/同一站、同伴跟車、斷自動尋路) /
# 三顧茅廬 (一日一顧、同日再去有提示、第三顧先見諸葛亮、孔明將軍令 = 諸葛亮) / 存檔 roundtrip / 決定性
# 跑: Godot --headless --path client --script tests/run_b3.gd   (失敗 exit 1)

var fails := 0
var total := 0

const Q := "hist_longzhong"
const ORDER := 62246            # 孔明將軍令


func _init() -> void:
	var data := GameData.load_all()
	t_maps(data)
	t_goto(data)
	t_station_pure(data)
	t_station(data)
	t_station_companion(data)
	t_quest(data)
	t_roundtrip(data)
	t_determinism(data)
	print("[TEST] b3: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


# ---------- helpers ----------
func _new(data: GameData, seed: int, lv: int = 12) -> Array:
	var sim := Sim.new(data, seed)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = lv
	ch["attrs"]["pol"] = 10      # F4: 三顧茅廬門檻 政治/魅力/等級 各 10+
	ch["attrs"]["cha"] = 10
	sim._sync_quest_npcs()
	var msgs: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "msg" and int(ev.get("dst", -1)) == id:
			msgs.append(str(ev["text"])))
	return [sim, id, ch, msgs]


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y
	e.erase("path")


func _talk(sim: Sim, id: int, npc_id: String) -> void:
	var n: Dictionary = sim.data.quest_npcs[npc_id]
	_put(sim, id, int(n["x"]), int(n["y"]) + 1)
	sim.cmd_quest_talk(id, npc_id)


func _at(sim: Sim, day: int, ke: int) -> void:
	var tpd := 1440 / int(sim.data.world["clock"]["gameMinPerTick"])
	sim.state["tick"] = day * tpd + int(ceil(ke * 15.0 / float(sim.data.world["clock"]["gameMinPerTick"]))) - 1
	sim.step()


func _at_fac(sim: Sim, id: int, key: String) -> void:
	var f: Dictionary = sim.data.facilities[key]
	_put(sim, id, int(f["x"]), int(f["y"]) + 1)


func _map_of(sim: Sim, id: int) -> String:
	var e := sim.ent(id)
	return sim.map_id_at(int(e["x"]), int(e["y"]))


func _count(sim: Sim, ch: Dictionary) -> int:
	return int(ch.get("quests", {}).get(Q, {}).get("flags", {}).get("count", 0))


func _stage(ch: Dictionary) -> int:
	return int(ch.get("quests", {}).get(Q, {}).get("stage", -1))


func _vis(sim: Sim, npc: String) -> bool:
	return bool(sim.state["quest_npcs"].get(npc, {}).get("visible", false))


# ---------- 隆中 + 草廬 ----------
func t_maps(data: GameData) -> void:
	var sim := Sim.new(data, 31)
	for mid in ["longzhong", "caolu"]:
		check(data.map_by_id.has(mid), "B3 地圖存在: %s" % mid)
	var cl: Dictionary = data.map_by_id["caolu"]
	check(String(cl["kind"]) == "house" and String(cl["parent"]) == "longzhong" and bool(cl["safe"]), "草廬: 室內 + parent 隆中 + 安全")
	check(not bool(data.map_by_id["longzhong"]["safe"]), "隆中: 野外 (唔安全)")
	var nd: Array = data.world_map["nodes"].filter(func(n): return String(n["id"]) == "longzhong")
	check(nd.size() == 1 and nd[0].get("map") != null and String(nd[0]["map"]) == "longzhong", "天下: 隆中節點開放")
	check(sim.map_hops("xiangyang", "longzhong") == 1, "襄陽 → 隆中 過 1 次圖")
	check(sim.map_hops("xiangyang", "caolu") == 2, "襄陽 → 草廬 過 2 次圖")
	check(sim.map_hops("xuchang", "longzhong") == 9, "許昌 → 隆中 過 9 次圖 (%d)" % sim.map_hops("xuchang", "longzhong"))
	check(String(sim.next_portal("xiangyang", "longzhong").get("id", "")) == "xyc_west", "路由: 襄陽 → 隆中 = 西門")
	check(String(sim.next_portal("xiangyang", "changsha").get("id", "")) == "xyc_south", "路由: 襄陽 → 長沙 仍然 = 南門")
	# 西門兩邊落地格行得、踩中即過圖
	for pid in ["xyc_west", "lz_east", "lz_caolu", "cl_door"]:
		var p := sim.travel_point_by_id(pid)
		check(not p.is_empty() and sim.is_free(int(p["x"]), int(p["y"])), "傳送點 %s 行得" % pid)
	# 怪: 隆中 Lv14~18；草廬冇怪；入口 2 格內冇 spawn 區
	var lvs: Array = []
	var lz := sim.travel_point_by_id("lz_east")
	for sp in data.spawns:
		if String(sp["zone"]) == "caolu":
			check(false, "草廬唔應該有怪")
		if String(sp["zone"]) != "longzhong":
			continue
		lvs.append(int(data.monsters[int(sp["monster"])]["level"]))
		var a: Array = sp["area"]
		var dx := maxi(0, maxi(int(a[0]) - int(lz["x"]), int(lz["x"]) - int(a[2])))
		var dy := maxi(0, maxi(int(a[1]) - int(lz["y"]), int(lz["y"]) - int(a[3])))
		check(maxi(dx, dy) > 2, "隆中入口 2 格內冇 spawn 區 (%s)" % sp["monster"])
	check(lvs.size() >= 3 and lvs.min() >= 14 and lvs.max() <= 18, "隆中怪 Lv14~18 (%s)" % [lvs])
	sim.init_mobs()
	var n := 0
	for e in sim.ents.values():
		if e["kind"] == "mob" and sim.map_id_at(int(e["x"]), int(e["y"])) == "longzhong":
			n += 1
			check(sim.is_free(int(e["x"]), int(e["y"])), "隆中怪企喺行得嘅格")
	check(n >= 10, "隆中有怪 spawn (%d)" % n)
	# 地標 + 任務 NPC 落喺啱嘅地圖、行得嘅格
	for lid in ["wolong_gang", "longzhong_dui"]:
		var lm: Array = data.landmarks.filter(func(x): return String(x["id"]) == lid)
		check(lm.size() == 1 and sim.is_free(int(lm[0]["x"]), int(lm[0]["y"])), "地標 %s 行得" % lid)
	for nid in ["simahui", "caolu_boy", "zhugeliang"]:
		var qn: Dictionary = data.quest_npcs[nid]
		check(sim.map_id_at(int(qn["x"]), int(qn["y"])) == String(qn["map"]), "%s 喺 %s" % [nid, qn["map"]])


# 大地圖撳隆中/草廬 → 自動尋路由襄陽行過去
func t_goto(data: GameData) -> void:
	for pair in [["longzhong", 1], ["caolu", 2]]:
		var r := _new(data, 32)
		var sim: Sim = r[0]
		var id: int = r[1]
		var inn: Dictionary = data.inns.filter(func(x): return String(x["id"]) == "xiangyang")[0]
		_put(sim, id, int(inn["x"]), int(inn["y"]) + 1)
		var n_travel := [0]
		sim.event_emitted.connect(func(ev: Dictionary) -> void:
			if ev["k"] == "travel":
				n_travel[0] += 1)
		sim.cmd_goto_map(id, String(pair[0]))
		var n := 0
		while n < 6000 and sim.ent(id).has("goto"):
			sim.step()
			n += 1
		check(_map_of(sim, id) == String(pair[0]), "尋路: 襄陽 → %s 到達 (%d tick)" % [pair[0], n])
		check(n_travel[0] == int(pair[1]), "尋路: 襄陽 → %s 過 %d 次圖 (%d)" % [pair[0], pair[1], n_travel[0]])


# ---------- 驛站: 純函數 ----------
func t_station_pure(data: GameData) -> void:
	var cfg: Dictionary = data.world["station"]
	var b := int(cfg["base"])
	var p := int(cfg["perHop"])
	check(RulesStation.fare(0, cfg) == b and RulesStation.fare(8, cfg) == b + 8 * p and RulesStation.fare(-3, cfg) == b, "車費 = base + perHop × 過圖")
	var keys := RulesStation.keys(data.facilities)
	check(keys == ["station_xc", "station_xy", "station_rn", "station_wc", "station_xyc"], "5 個驛站 (檔案順序) %s" % [keys])
	var f := data.facilities
	check(RulesStation.check("", "station_xy", f, 3, 999, cfg) == "要去驛站先得", "check: 唔喺驛站")
	check(RulesStation.check("station_xc", "training", f, 3, 999, cfg) == "冇呢個驛站", "check: 目的地唔係驛站")
	check(RulesStation.check("station_xc", "nope", f, 3, 999, cfg) == "冇呢個驛站", "check: 目的地唔存在")
	check(RulesStation.check("station_xc", "station_xc", f, 0, 999, cfg) == "你已經喺呢個驛站", "check: 同一站")
	check(RulesStation.check("station_xc", "station_xy", f, -1, 999, cfg).begins_with("去唔到"), "check: 冇路")
	check(RulesStation.check("station_xc", "station_xy", f, 5, b + 5 * p - 1, cfg).contains("唔夠錢"), "check: 差 1 金都唔得")
	check(RulesStation.check("station_xc", "station_xy", f, 5, b + 5 * p, cfg) == "", "check: 啱啱夠錢")
	var sim := Sim.new(data, 33)
	for k in keys:
		var d: Dictionary = f[k]
		var md := sim.map_at(int(d["x"]), int(d["y"]))
		check(String(md.get("kind", "")) == "city" and String(md["id"]) == String(d["map"]), "%s 喺城入面" % k)
		check(sim.is_free(int(d["x"]), int(d["y"])), "%s 企喺行得嘅格" % k)
		for k2 in keys:
			if k2 != k:
				check(sim._station_hops(k, k2) > 0, "%s → %s 有路" % [k, k2])


# ---------- 驛站: sim ----------
func t_station(data: GameData) -> void:
	var r := _new(data, 34)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var cfg: Dictionary = data.world["station"]
	var fare := RulesStation.fare(sim.map_hops("xuchang", "xiangyang"), cfg)
	check(fare == int(cfg["base"]) + 8 * int(cfg["perHop"]), "許昌 → 襄陽 車費 = base + 8 × perHop (%d)" % fare)
	# 唔喺驛站
	ch["gold"] = 1000
	var e := sim.ent(id)
	var x0 := int(e["x"])
	sim.cmd_station(id, "station_xyc")
	check(int(e["x"]) == x0 and int(ch["gold"]) == 1000 and msgs.back() == "要去驛站先得", "唔喺驛站: 搭唔到")
	check(String(sim.station_view(id)["from"]) == "", "視圖: 唔喺驛站 from = \"\"")
	# 喺許昌驛站: 視圖
	_at_fac(sim, id, "station_xc")
	var v := sim.station_view(id)
	check(String(v["from"]) == "station_xc" and (v["list"] as Array).size() == 4, "視圖: 許昌驛站列 4 個目的地")
	var row: Array = (v["list"] as Array).filter(func(x): return String(x["key"]) == "station_xyc")
	check(row.size() == 1 and int(row[0]["fare"]) == fare and String(row[0]["why"]) == "", "視圖: 襄陽車費 %d、可以搭" % fare)
	# 唔夠錢
	ch["gold"] = fare - 1
	sim.cmd_station(id, "station_xyc")
	check(_map_of(sim, id) == "xuchang_o" and int(ch["gold"]) == fare - 1 and String(msgs.back()).contains("唔夠錢"), "唔夠錢: 搭唔到、唔扣錢")
	check(String(sim.station_view(id)["list"].filter(func(x): return String(x["key"]) == "station_xyc")[0]["why"]).contains("唔夠錢"), "視圖: 唔夠錢有原因")
	# 同一站 / 亂嚟
	ch["gold"] = 1000
	sim.cmd_station(id, "station_xc")
	check(_map_of(sim, id) == "xuchang_o" and int(ch["gold"]) == 1000, "同一站: 唔郁")
	sim.cmd_station(id, "training")
	check(_map_of(sim, id) == "xuchang_o" and int(ch["gold"]) == 1000, "目的地唔係驛站: 唔郁")
	# 成功: 扣錢、去到襄陽驛站隔籬、travel 事件、斷自動尋路/攻擊
	var evs: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "travel":
			evs.append(ev))
	e["goto"] = "xinye"
	e["atk_target"] = 99
	sim.cmd_station(id, "station_xyc")
	check(_map_of(sim, id) == "xiangyang" and int(ch["gold"]) == 1000 - fare, "成功: 去到襄陽、扣 %d 金" % fare)
	check(sim.station_near(e) == "station_xyc" and sim.is_free(int(e["x"]), int(e["y"])), "成功: 企喺襄陽驛站隔籬行得嘅格")
	check(evs.size() == 1 and bool(evs[0].get("station", false)) and String(evs[0]["map"]) == "xiangyang", "成功: travel 事件")
	check(not e.has("goto") and int(e["atk_target"]) == 0 and int(e["tx"]) == int(e["x"]), "成功: 取消自動尋路/攻擊/行路")
	# 返程 + 死咗搭唔到
	var back := RulesStation.fare(sim.map_hops("xiangyang", "xinye"), cfg)
	var g0 := int(ch["gold"])
	sim.cmd_station(id, "station_xy")
	check(_map_of(sim, id) == "xinye" and int(ch["gold"]) == g0 - back, "襄陽 → 新野 扣 %d 金" % back)
	e["hp"] = 0
	sim.cmd_station(id, "station_xc")
	check(_map_of(sim, id) == "xinye", "死咗搭唔到")


# 同伴跟埋上車 (唔使行 8 張圖)
func t_station_companion(data: GameData) -> void:
	var r := _new(data, 35)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	_at_fac(sim, id, "station_xc")
	sim._recruit_success(sim.ent(id), data.general_by_id[161])
	var c := sim._companion_of(sim.ent(id))
	check(not c.is_empty(), "有同伴")
	ch["gold"] = 1000
	sim.cmd_station(id, "station_wc")
	check(_map_of(sim, id) == "wancheng", "去到宛城")
	check(sim.map_id_at(int(c["x"]), int(c["y"])) == "wancheng" and sim._cheb(c, sim.ent(id)) <= 3, "同伴一齊到宛城、企喺隔籬")
	check(not (int(c["x"]) == int(sim.ent(id)["x"]) and int(c["y"]) == int(sim.ent(id)["y"])), "同伴唔會同主公疊埋")


# ---------- 三顧茅廬 ----------
func t_quest(data: GameData) -> void:
	var r := _new(data, 36, 9)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var fame0 := int(ch.get("fame", 0))
	_at(sim, 0, 40)
	_talk(sim, id, "simahui")
	check(_stage(ch) == -1, "9 級接唔到三顧茅廬")
	ch["level"] = 10
	check(not _vis(sim, "zhugeliang"), "諸葛亮: 未接任務唔見")
	_talk(sim, id, "simahui")
	check(_stage(ch) == 1, "司馬徽: 接任務 → 去草廬")
	_talk(sim, id, "caolu_boy")
	check(_count(sim, ch) == 1 and msgs.has(String(data.quests.filter(func(q): return q["id"] == Q)[0]["stages"][1]["dialogs"][0])), "第一顧: 書童話先生出咗門")
	check(not _vis(sim, "zhugeliang"), "第一顧: 諸葛亮唔喺度")
	msgs.clear()
	_talk(sim, id, "caolu_boy")
	check(_count(sim, ch) == 1, "同日再去唔計")
	check(msgs.size() == 1 and String(msgs[0]).contains("聽日再嚟"), "同日再去: 書童有提示 (%s)" % [msgs])
	_at(sim, 1, 40)
	_talk(sim, id, "caolu_boy")
	check(_count(sim, ch) == 2 and _stage(ch) == 1, "第二顧: 又唔喺度")
	_talk(sim, id, "zhugeliang")
	check(_stage(ch) == 1, "未夠三顧傾唔到諸葛亮")
	_at(sim, 2, 40)
	_talk(sim, id, "caolu_boy")
	check(_stage(ch) == 2, "第三顧: 書童入去通傳")
	check(_vis(sim, "zhugeliang"), "第三顧: 諸葛亮出現")
	_talk(sim, id, "zhugeliang")
	check(bool(ch.get("questDone", {}).get(Q, false)), "見諸葛亮: 任務完成")
	check(RulesShop.count_item(ch["bag"], ORDER) == 1 and RulesShop.count_item(ch["bag"], 29017) == 5, "獎勵: 孔明將軍令 + 戰國七雄×5")
	check(int(ch["fame"]) == fame0 + 30, "獎勵: 名聲 +30")
	check(not _vis(sim, "zhugeliang"), "完成後諸葛亮唔見")
	_talk(sim, id, "simahui")
	check(RulesShop.count_item(ch["bag"], ORDER) == 1, "完成咗唔可以重接")
	# 孔明將軍令 = 諸葛亮 (字號對照)
	check(int(data.general_order_item.get("諸葛亮", 0)) == ORDER, "將軍令對照: 諸葛亮 = 孔明將軍令")
	check(RulesGeneral.order_general_name("孔明將軍令", "將軍令", data.gen2_cfg["orderAlias"]) == "諸葛亮", "字號 → 名")
	check(RulesGeneral.order_general_name("呂布將軍令", "將軍令", data.gen2_cfg["orderAlias"]) == "呂布", "冇字號照舊")
	var g := sim._order_general("諸葛亮")
	check(not g.is_empty() and sim._has_order(ch, g), "有孔明將軍令 = 可以無視條件登用諸葛亮")


# ---------- 存檔 ----------
func t_roundtrip(data: GameData) -> void:
	var r := _new(data, 37)
	var sim: Sim = r[0]
	var id: int = r[1]
	_at(sim, 0, 40)
	_talk(sim, id, "simahui")
	_talk(sim, id, "caolu_boy")
	_at(sim, 1, 40)
	_talk(sim, id, "caolu_boy")
	_at_fac(sim, id, "station_xyc")
	var s1 := sim.save_string()
	var sim2 := Sim.load_string(data, s1)
	check(sim2 != null and sim2.save_string() == s1, "save → load → save 字串一致")
	var ch2: Dictionary = sim2.player_ch()
	var id2 := int(sim2.state["player_id"])
	check(_count(sim2, ch2) == 2 and _stage(ch2) == 1, "載入: 兩顧進度")
	_talk(sim2, id2, "caolu_boy")
	check(_count(sim2, ch2) == 2, "載入: 同日仍然唔計")
	_at(sim2, 2, 40)
	_talk(sim2, id2, "caolu_boy")
	_talk(sim2, id2, "zhugeliang")
	check(bool(ch2.get("questDone", {}).get(Q, false)), "載入後繼續完成三顧茅廬")
	_at_fac(sim2, id2, "station_xyc")
	ch2["gold"] = 1000
	sim2.cmd_station(id2, "station_xc")
	check(_map_of(sim2, id2) == "xuchang_o", "載入後搭驛站")


# ---------- 決定性 ----------
func _script(data: GameData) -> String:
	var r := _new(data, 138)
	var sim: Sim = r[0]
	var id: int = r[1]
	var ch: Dictionary = r[2]
	sim.init_mobs()
	ch["gold"] = 2000
	_at_fac(sim, id, "station_xc")
	sim.cmd_station(id, "station_xyc")
	_talk(sim, id, "simahui")
	for i in 40:
		sim.step()
	sim.cmd_goto_map(id, "longzhong")
	for i in 400:
		sim.step()
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_script(data) == _script(data), "同種子同操作 → 存檔一致")
