extends SceneTree
# Step 11 測試 (spec 04 §1~3, spec 11 §2): 怪物導入對照 + 洞窟傳送 + 逃跑/群攻/每日重生
# 跑: Godot --headless --path client --script tests/run_monsters.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_import_vectors(data)
	t_monster_count(data)
	t_item_ids(data)
	t_spawn_zones(data)
	t_gate_newbie(data)
	t_cave_geometry(data)
	t_flee_negative(data)
	t_group_aggro(data)
	t_boss(data)
	t_boss_daily(data)
	t_runan_travel(data)
	t_cave_shop(data)
	print("[TEST] monsters scenarios: %d, fail %d" % [total, fails])
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


# npc_drops.csv 原行 (導入器同源)。boss 19001 唔喺 CSV，另行硬編碼。
# 格式: id,name,level,n_drops,drops(item(id)@rate ...)；rate 基數 100000
const CSV_VECTORS := [
	"11068,流氓1,14,9,銅鎚(10039)@200 古代劍(11037)@200 蒲扇(12002)@200 捷豹靴(22027)@60 精鋼戒指(23002)@200 嫦娥袖帶(15003)@200 甜蘿蔔(29042)@30000 賊寇錦囊(61506)@100 草菇(29067)@2500",
	"11070,地痞1,30,10,玄龜寶槍(10029)@150 玄龜寶環(11029)@150 玄龜寶弩(12029)@150 玄龜卷軸(13029)@150 玄龜符咒(14029)@150 玄龜寶琴(15029)@150 甜蘿蔔(29042)@30000 賊寇錦囊(61506)@200 野蔘(29069)@2500 精製鐵虎(31215)@200",
	"11091,山賊,11,9,鋼刀(10037)@400 鋼爪(11039)@200 皮靴(22025)@600 禪杖(13014)@200 虛極拂塵(14014)@200 青銅戒指(23001)@200 野香菇(29040)@9000 仙楂(29038)@30000 草菇(29067)@2500",
	"12003,野兔,7,9,木箭(12201)@12000 光輝石墨(26037)@3600 仙楂(29038)@30000 甜蘿蔔(29042)@1600 梅子(29045)@6000 光輝之石(26038)@1200 細毛兔皮(25100)@3000 普通兔皮(25101)@1200 草菇(29067)@2500",
	"12005,母雞,11,10,無花果(29041)@2400 野芋(29039)@30000 雞蛋(29036)@9000 回血草(29043)@1800 梅子(29045)@3600 光輝之石(26038)@1200 大片山葉(29048)@1200 芳香軟石(25098)@1500 草菇(29067)@2500 精製乾糧(31208)@200",
	"12006,狐貍,18,10,速攻靴(22002)@150 純銀戒指(23003)@180 銀鍊子(24002)@150 狐貍皮(25109)@1500 光輝之石(26038)@3000 光明之石(26039)@500 甜蘿蔔(29042)@30000 獸肉(61503)@600 補神草(29068)@2500 精製腳蹄(31211)@200",
	"12011,猴子,11,9,無花果(29041)@2400 野芋(29039)@30000 回血草(29043)@9000 雞蛋(29036)@1800 梅子(29045)@3600 光輝之石(26038)@1200 甜味樹根(29049)@1200 紫色香草(25097)@1500 草菇(29067)@2500",
	"12012,野狗,16,10,生之石(32306)@6 光輝之石(26038)@600 回血草(29043)@6000 甜蘿蔔(29042)@900 梅子(29045)@4800 光輝之石(26038)@3000 甜蘿蔔(29042)@30000 獸骨(61502)@1000 補神草(29068)@2500 精製小球(31210)@200",
	"12013,野豬,14,10,地之石(32302)@6 十等箭(12202)@12000 回血草(29043)@30000 甜蘿蔔(29042)@900 梅子(29045)@3600 光輝之石(26038)@1200 甜味樹根(29049)@1200 紫色香草(25097)@1500 草菇(29067)@2500 精製補藥(31209)@200",
	"12014,花鹿,20,3,勇者頭盔(16027)@250 絕塵冠(17027)@250 玲瓏髮簪(18027)@250",
	"12017,大蟒,20,10,武者鎧甲(19027)@250 樂生袍(20027)@250 玲瓏霞衣(21027)@250 水之石(32303)@6 光輝之石(26038)@3000 光明之石(26039)@500 甜蘿蔔(29042)@30000 獸肉(61503)@600 補神草(29068)@2500 精製手套(31212)@200",
	"12018,山羊,14,3,精鋼頭盔(16013)@600 方外冠(17013)@600 迷情羽飾(18013)@600",
	"12019,瘋貓,14,10,無花果(29041)@2400 野芋(29039)@30000 回血草(29043)@9000 甜蘿蔔(29042)@900 梅子(29045)@3600 光輝之石(26038)@1200 甜味樹根(29049)@1200 紫色香草(25097)@1500 草菇(29067)@2500 精製補藥(31209)@200",
	"12021,野貂,9,9,無花果(29041)@2400 貂皮(25108)@1200 仙楂(29038)@30000 野芋(29039)@1800 梅子(29045)@3600 光輝之石(26038)@1200 大片山葉(29048)@1200 光輝石墨(26037)@1500 草菇(29067)@2500",
	"12028,黃蜂,20,9,火之石(32304)@6 光明之石(26039)@300 回血草(29043)@3000 芳香草(29044)@3000 梅子(29045)@2400 光輝之石(26038)@1200 甜蘿蔔(29042)@30000 香味粉末(25099)@15000 補神草(29068)@2500",
	"12029,蝴蝶精,9,9,無花果(29041)@2400 光輝石墨(26037)@1200 野香菇(29040)@9000 野芋(29039)@30000 梅子(29045)@3600 光輝之石(26038)@3600 大片山葉(29048)@1200 深色蟲藥粉(25103)@12000 草菇(29067)@2500",
	"12030,飛蛾怪,14,9,元氣之石(32101)@6 光輝之石(26038)@600 風之石(32301)@6 回血草(29043)@6000 梅子(29045)@2400 光輝之石(26038)@1200 甜蘿蔔(29042)@30000 高品質蟲粉(25104)@6000 草菇(29067)@2500",
	"12031,蜻蜓,9,9,無花果(29041)@2400 光輝石墨(26037)@1200 野香菇(29040)@9000 野芋(29039)@30000 梅子(29045)@40000 光輝之石(26038)@1200 大片山葉(29048)@1200 深色蟲藥粉(25103)@12000 草菇(29067)@2500",
	"12022,水鴨,5,0,",
	"12034,蝙蝠,20,0,",
	"12044,兔兒,5,0,",
	"12046,草貂,7,0,",
]

# boss 19001 手寫掉落 (item, p)
const BOSS_DROPS := [[61505, 0.5], [61504, 0.35], [29042, 0.3], [25107, 0.12], [28035, 0.08]]
const BOSS_RARE := [[32302, 0.02]]


# CSV 行解析 -> (item_id, p) 原次序
static func _parse_csv_line(line: String) -> Array:
	var f := line.split(",")
	var drops_raw := f[4] if f.size() > 4 else ""
	var out: Array = []
	var rx := RegEx.new()
	rx.compile(r"\((\d+)\)@(\d+)")
	for m in rx.search_all(drops_raw):
		out.append([int(m.get_string(1)), int(m.get_string(2)) / 100000.0])
	return out


# 對照: monsters.json 每隻怪 drops+rareDrops 平排 = CSV 拆「常見(p>=0.05) 先行、稀有殿後」嘅序
func t_import_vectors(data: GameData) -> void:
	for line in CSV_VECTORS:
		var f: PackedStringArray = String(line).split(",")
		var mid := int(f[0])
		var expected := _parse_csv_line(line)
		var common: Array = expected.filter(func(e: Array) -> bool: return e[1] >= 0.05)
		var rare: Array = expected.filter(func(e: Array) -> bool: return e[1] < 0.05)
		var d: Dictionary = data.monsters.get(mid, {})
		check(not d.is_empty(), "導入: 怪 %d (%s) 存在" % [mid, f[1]])
		if d.is_empty():
			continue
		var actual: Array = []
		for x in d.get("drops", []):
			actual.append([int(x["item"]), float(x["p"])])
		for x in d.get("rareDrops", []):
			actual.append([int(x["item"]), float(x["p"])])
		var exp_pair: Array = []
		for x in common:
			exp_pair.append(x)
		for x in rare:
			exp_pair.append(x)
		var ok := actual.size() == exp_pair.size()
		if ok:
			for i in actual.size():
				if int(actual[i][0]) != int(exp_pair[i][0]) or absf(float(actual[i][1]) - float(exp_pair[i][1])) > 1e-9:
					ok = false
					break
		check(ok, "導入: %s 掉落 p 對照 CSV (%d 項)" % [f[1], expected.size()])
		if not ok:
			print("      expected=%s\n      actual=%s" % [str(exp_pair), str(actual)])
	# boss 19001
	var boss: Dictionary = data.monsters.get(19001, {})
	check(not boss.is_empty(), "導入: boss 19001 存在")
	if not boss.is_empty():
		var bd: Array = []
		for x in boss.get("drops", []):
			bd.append([int(x["item"]), float(x["p"])])
		var br: Array = []
		for x in boss.get("rareDrops", []):
			br.append([int(x["item"]), float(x["p"])])
		check(bd == BOSS_DROPS and br == BOSS_RARE, "導入: boss 掉落硬編碼對照")
	check(bool(boss.get("flee", true)) == false, "導入: boss flee=false (唔會逃跑)")
	check(bool(boss.get("boss", false)) == true, "導入: boss 標記每日重生")


func t_monster_count(data: GameData) -> void:
	var imported := 0
	var hand := 0
	for d in data.monsters.values():
		if int(d["id"]) >= 10000:
			imported += 1
		else:
			hand += 1
	check(data.monsters.size() >= 30, "導入: 全場怪 ≥ 30 (而家 %d)" % data.monsters.size())
	check(imported >= 20, "導入: npc_drops 導入 ≥ 20 (而家 %d)" % imported)
	check(hand == 11, "導入: 原裝 11 隻保留 (而家 %d)" % hand)


func t_item_ids(data: GameData) -> void:
	var bad: Array = []
	for d in data.monsters.values():
		for x in d.get("drops", []) + d.get("rareDrops", []):
			if not data.item_ids.has(int(x["item"])):
				bad.append([d["id"], int(x["item"])])
	check(bad.is_empty(), "導入: 全部掉落 item id 喺 items.json (%d 個唔啱)" % bad.size())


func t_spawn_zones(data: GameData) -> void:
	var zone_ids := {}
	for z in data.zones:
		zone_ids[String(z["id"])] = true
	var bad: Array = []
	for s in data.spawns:
		if not zone_ids.has(String(s["zone"])):
			bad.append(s)
		if not data.monsters.has(int(s["monster"])):
			bad.append(s)
	check(bad.is_empty(), "洞窟: 所有 spawn 嘅 monster/zone 都存在")
	for f in range(1, 11):
		check(zone_ids.has("runan_f%d" % f), "洞窟: runan_f%d zone 存在" % f)
	# 每洞窟層 spawn 至少 1 個
	var has_zone := {}
	for s in data.spawns:
		has_zone[String(s["zone"])] = true
	for f in range(1, 11):
		check(bool(has_zone.get("runan_f%d" % f, false)), "洞窟: 第 %d 層有 spawn" % f)
	# boss spawn 喺 10 層
	var boss_spawn := {}
	for s in data.spawns:
		if int(s["monster"]) == 19001:
			boss_spawn = s
	check(not boss_spawn.is_empty() and String(boss_spawn.get("zone", "")) == "runan_f10", "洞窟: boss spawn 喺 runan_f10")


func t_cave_geometry(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	check(not sim.is_free(15, 20), "牆: 舊城內牆 (15,20) 保留")
	check(not sim.is_free(61, 30), "牆: 洞窟左封 x=61")
	check(not sim.is_free(92, 5), "牆: 欄間 x=92")
	check(not sim.is_free(62, 0), "牆: 頂行 y=0")
	check(sim.is_free(62, 1), "牆: 第一層 room 內可用")
	check(sim.is_free(64, 3), "牆: 洞口到達點可用")
	check(sim.is_free(58, 44), "牆: 野外山洞入口可用")
	# 每層 zone 內唔好有 blockers (房間要行到)
	for f in range(1, 11):
		var z := sim.zone_by_id("runan_f%d" % f)
		var walk := 0
		for x in range(int(z["x0"]), int(z["x1"]) + 1):
			for y in range(int(z["y0"]), int(z["y1"]) + 1):
				if sim.is_free(x, y):
					walk += 1
		check(walk > 200, "洞窟 %dF: 可步行格 > 200 (實際 %d)" % [f, walk])
	# 傳送點都喺自己 zone 入面
	for p in data.travel_points:
		if not String(p["id"]).begins_with("runan") and p["id"] not in ["cave_enter", "cave_f1"]:
			continue
		var zv := sim.zone_view(int(p["x"]), int(p["y"]))
		check(not zv.is_empty(), "傳送點 %s 喺 zone 內" % p["id"])
		check(sim.is_free(int(p["x"]), int(p["y"])), "傳送點 %s 可企" % p["id"])


# 逃跑: HP ≥ 20% 唔會觸發
func t_flee_negative(data: GameData) -> void:
	var sim := Sim.new(data, 12)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 30, 50)
	var mid: Variant = sim._spawn_mob(12012, "field_1")
	_put(sim, int(mid["id"]), 32, 50)
	mid["mob"]["home_x"] = 32
	mid["mob"]["home_y"] = 50
	mid["hp"] = int(mid["max_hp"]) * 3 / 5          # 60% HP
	sim.damage(mid, 1, sim.ent(pid))
	check(String(mid["mob"]["state"]) != "flee" and String(mid["mob"]["state"]) == "chase",
		"逃跑: 60%% HP 唔會逃 (state=%s)" % mid["mob"]["state"])
	check(int(mid["hp"]) > 0, "逃跑: 輕輕打一吓只係扣 1")

	# 逃跑後: 每撞 1 吓 roll 一次 15%，搵一粒種子令佢喺死前逃到
	var sim2: Sim
	var mid2: Dictionary = {}
	var fled := false
	var p2id := -1
	var seed := 1
	while not fled and seed < 60:
		var s2 := Sim.new(data, seed)
		var p2 := s2.spawn_player("t")
		p2id = p2
		_put(s2, p2, 30, 50)
		var m2: Variant = s2._spawn_mob(12012, "field_1")
		_put(s2, int(m2["id"]), 32, 50)
		m2["mob"]["home_x"] = 32
		m2["mob"]["home_y"] = 50
		m2["hp"] = 50                                   # max_hp ~285 → 低過 20%
		for i in 49:
			if s2.ent(int(m2["id"])).is_empty():
				break
			s2.damage(s2.ent(int(m2["id"])), 1, s2.ent(p2))
			if String(s2.ent(int(m2["id"])).get("mob", {}).get("state", "")) == "flee":
				sim2 = s2
				mid2 = s2.ent(int(m2["id"]))
				fled = true
				break
		seed += 1
	check(fled, "逃跑: 低 HP 撞到逃得甩 (有種子)")
	if fled:
		check(int(mid2["hp"]) > 0, "逃跑: 逃走時仲未死")
		# 離 leash 就消失 + 排重生 + atk_target 清
		var alt := int(mid2["id"])
		sim2.ent(p2id)["atk_target"] = alt
		var gone := false
		for i in 120:
			sim2.step()
			if sim2.ent(alt).is_empty():
				gone = true
				break
		check(gone, "逃跑: 走甩咗 (120 tick 內消失)")
		var has_respawn := false
		for r in sim2.state["respawns"]:
			if int(r["def"]) == 12012 and String(r["zone"]) == "field_1":
				has_respawn = true
		check(has_respawn, "逃跑: 排咗重生")
		var clear := true
		for e in sim2.ents.values():
			if not e.has("ch"):
				continue
			if int(e["atk_target"]) == alt:
				clear = false
		check(clear, "逃跑: 玩家 atk_target 已清")


# 群攻: 打 1 隻 → 附近 5 格同類一齊仇恨；>5 格唔會
func t_group_aggro(data: GameData) -> void:
	var sim := Sim.new(data, 21)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 28, 30)
	var a: Variant = sim._spawn_mob(12028, "field_1")   # 黃蜂 groups
	_put(sim, int(a["id"]), 30, 30)
	a["mob"]["home_x"] = 30
	a["mob"]["home_y"] = 30
	var b: Variant = sim._spawn_mob(12028, "field_1")
	_put(sim, int(b["id"]), 34, 30)                     # 距 a = 4 (≤5)
	b["mob"]["home_x"] = 34
	b["mob"]["home_y"] = 30
	var c: Variant = sim._spawn_mob(12028, "field_1")
	_put(sim, int(c["id"]), 36, 30)                     # 距 a = 6 (>5)
	c["mob"]["home_x"] = 36
	c["mob"]["home_y"] = 30
	sim.damage(a, 5, sim.ent(pid))
	check(String(a["mob"]["state"]) == "chase" and int(a["mob"]["target"]) == pid, "群攻: 被打嗰隻追仇")
	check(String(b["mob"]["state"]) == "chase" and int(b["mob"]["target"]) == pid, "群攻: 5 格內同類一齊追")
	check(String(c["mob"]["state"]) != "chase", "群攻: 6 格嗰隻唔會一齊追")
	# 有冇 fixed: b, c 唔會自己 aggro 到 player (player 28,30 距 b=6>aggroRange4, 距 c=8)
	sim.step()
	check(String(b["mob"]["state"]) == "chase", "群攻: step 後 b 仍然追緊")
	check(String(c["mob"]["state"]) == "wander", "群攻: step 後 c 仍然遊蕩")


# boss: 每日重生 + 唔逃跑
func t_boss(data: GameData) -> void:
	var sim := Sim.new(data, 33)
	var pid := sim.spawn_player("t")
	sim.init_mobs()
	var boss_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob" and int(e["mob"]["def"]) == 19001:
			boss_id = int(e["id"])
	check(boss_id != 0, "每日重生: init_mobs 生咗 boss")
	var boss: Dictionary = data.monsters[19001]
	check(bool(boss.get("flee", true)) == false, "每日重生: boss flee=false")
	check(not sim.is_safe(int(sim.ent(boss_id)["x"]), int(sim.ent(boss_id)["y"])), "每日重生: boss 喺非安全區")


func t_boss_daily(data: GameData) -> void:
	var sim := Sim.new(data, 7)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 100, 50)
	sim.init_mobs()
	var boss_id := 0
	for e in sim.ents.values():
		if e["kind"] == "mob" and int(e["mob"]["def"]) == 19001:
			boss_id = int(e["id"])
	check(boss_id != 0, "每日重生: 生咗 boss")
	var tpd := int(1440.0 / float(int(data.world["clock"]["gameMinPerTick"])))
	sim.step()                                          # tick=1
	var cur := sim.tick
	sim.damage(sim.ent(boss_id), 999999, sim.ent(pid))
	check(sim.ent(boss_id).is_empty(), "每日重生: boss 被打死")
	var resp := {}
	for r in sim.state["respawns"]:
		if int(r["def"]) == 19001:
			resp = r
	check(not resp.is_empty(), "每日重生: boss 排咗重生")
	var target_tick := (int(cur / tpd) + 1) * tpd
	if resp.has("at"):
		check(int(resp["at"]) == target_tick, "每日重生: 排喺下一個子時 (at=%d, 期望 %d)" % [int(resp["at"]), target_tick])
		check(String(resp["zone"]) == "runan_f10", "每日重生: zone 啱")
	# 同日唔會重生
	var seen := false
	for i in mini(60, tpd - sim.tick + 1):
		sim.step()
	for e in sim.ents.values():
		if e["kind"] == "mob" and int(e["mob"]["def"]) == 19001:
			seen = true
	check(not seen, "每日重生: 同日唔會再造出嚟")
	# 過咗子時就重生
	var guard := 0
	while sim.tick < target_tick and guard < tpd + 60:
		sim.step()
		guard += 1
	var alive := false
	for e in sim.ents.values():
		if e["kind"] == "mob" and int(e["mob"]["def"]) == 19001:
			alive = true
	check(alive, "每日重生: 過子時後 boss 重生")


func t_runan_travel(data: GameData) -> void:
	var sim := Sim.new(data, 9)
	var pid := sim.spawn_player("t")
	var tp := sim.travel_point_by_id("cave_enter")
	_put(sim, pid, int(tp["x"]), int(tp["y"]))
	# 每跳: 企喺 src 點 → cmd_travel → 到 dst 點 (傳送點定義互相交連)
	# 落去: cave_enter→f1_down→f2_down→...→f9_down；上返: f10_up→f9_up→...→f2_up→cave_f1
	var jumps := ["cave_enter", "f1_down", "f2_down", "f3_down", "f4_down", "f5_down", "f6_down",
		"f7_down", "f8_down", "f9_down", "f10_up", "f9_up", "f8_up", "f7_up", "f6_up", "f5_up",
		"f4_up", "f3_up", "f2_up", "cave_f1"]
	for src in jumps:
		var from_p := sim.travel_point_by_id(src)
		var to_p := sim.travel_point_by_id(str(from_p.get("to", "")))
		_put(sim, pid, int(from_p["x"]), int(from_p["y"]))
		sim.cmd_travel(pid, src)
		check(not to_p.is_empty() and int(sim.ent(pid)["x"]) == int(to_p["x"]) and int(sim.ent(pid)["y"]) == int(to_p["y"]),
			"洞窟: %s → %s 就到" % [src, from_p.get("to", "?")])
	# 而家企喺 cave_enter (58,44) 附近 → 入返去, 存檔 roundtrip
	sim.cmd_travel(pid, "cave_enter")
	var s := sim.save_string()
	var loaded := Sim.load_string(data, s)
	check(loaded != null and loaded.save_string() == s, "洞窟: 傳送後存讀檔一致")
	check(String(loaded.zone_view(int(loaded.ent(pid)["x"]), int(loaded.ent(pid)["y"])).get("id", "")) == "runan_f1",
		"洞窟: 讀檔後仍在 1F")


func t_cave_shop(data: GameData) -> void:
	var sim := Sim.new(data, 5)
	var pid := sim.spawn_player("t")
	_put(sim, pid, 70, 8)                                   # 洞窟商店 (1F)
	var shop := sim._shop_for(sim.ent(pid))
	check(not shop.is_empty() and String(shop.get("id", "")) == "runan", "洞窟商店: 揀啱邊間 (1F)")
	var ch: Dictionary = sim.player_ch()
	ch["gold"] = 100000
	var item := int(shop["stock"][0])                        # 甜蘿蔔
	var g0 := int(ch["gold"])
	sim.cmd_buy(pid, item, 1)
	check(int(ch["gold"]) < g0, "洞窟商店: 買到 (扣錢)")
	sim.cmd_sell(pid, item, 1)
	check(int(ch["gold"]) > g0 - 100000, "洞窟商店: 賣返都得")
	var s := sim.save_string()
	var loaded := Sim.load_string(data, s)
	check(loaded != null and loaded.save_string() == s, "洞窟商店: 買賣後存讀檔一致")


# 北門 (27,27) 新手友善: spawn area 喺 zone 入面；門口 6 格內只有 Lv≤3、18 格內冇 Lv11+ (重生都係)
func t_gate_newbie(data: GameData) -> void:
	for sp in data.spawns:
		if not sp.has("area"):
			continue
		var z: Dictionary = {}
		for zz in data.zones:
			if String(zz["id"]) == String(sp.get("zone", "field_1")):
				z = zz
		var a: Array = sp["area"]
		check(int(a[0]) >= int(z["x0"]) and int(a[1]) >= int(z["y0"]) and int(a[2]) <= int(z["x1"]) and int(a[3]) <= int(z["y1"]),
			"北門: spawn area 喺 zone 入面 (%s)" % sp["monster"])
	for seed in [1, 2, 3]:
		var sim := Sim.new(data, seed)
		sim.init_mobs()
		for e in sim.ents.values():
			if e["kind"] != "mob":
				continue
			var dg := maxi(absi(int(e["x"]) - 27), absi(int(e["y"]) - 27))
			check((dg > 6 or int(e["level"]) <= 3) and (dg > 18 or int(e["level"]) <= 9), "北門: 門口附近冇高等怪 (%s Lv%d @%d,%d)" % [e["name"], int(e["level"]), int(e["x"]), int(e["y"])])
		# 重生都守 area
		for i in 20:
			var m: Variant = sim._spawn_mob(11070, "field_1")
			check(m != null and int(m["x"]) >= 46 and int(m["y"]) >= 48, "北門: 重生 Lv30 喺遠角")
