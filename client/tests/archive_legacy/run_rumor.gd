extends SceneTree
# S09b 測試 (spec 09 §4): 傳聞擴散 (目擊→記憶→每日反思→同城/跨城延遲 1~3 日) + 殺善 NPC 忠誠事件。
# 跑: Godot --headless --path client --script tests/run_rumor.gd  (失敗 exit 1)

var fails := 0
var total := 0
var R: Dictionary = {}


func _init() -> void:
	var data := GameData.load_all()
	R = data.residents
	t_data()
	t_rules()
	t_memory()
	t_witness_seed(data)
	t_kind_map(data)
	t_cross_city(data)
	t_loyalty_npc(data)
	t_view(data)
	t_roundtrip(data)
	t_old_save(data)
	t_determinism(data)
	print("[TEST] rumor scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _city_of(sim: Sim, city: String) -> int:
	for id in sim.state["bots"]:
		if String(sim.ent(int(id)).get("ch", {}).get("homeCity", "")) == city:
			return int(id)
	return 0


func _new(data: GameData, seed_v: int = 41) -> Sim:
	var sim := Sim.new(data, seed_v)
	sim.spawn_player("t", "yishi")
	return sim


# ================= 資料 =================

func t_data() -> void:
	check(not RulesRumor.cfg(R).is_empty(), "資料: residents.json cfg.rumor 載入")
	check(RulesRumor.cap(R) == 16 and RulesRumor.mem_cap(R) == 8, "資料: cap 16 / memCap 8")
	check(RulesRumor.delay_min(R) == 1 and RulesRumor.delay_max(R) == 3, "資料: 跨城延遲 1~3 日")
	check((RulesRumor.cfg(R).get("kindMap", {}) as Dictionary).has("murder"), "資料: kindMap 有 murder")


# ================= 純函數 =================

func t_rules() -> void:
	check(RulesRumor.rumor_kind_of("murder", -4, R) == "killer", "規則: 殺善重量負 → killer")
	check(RulesRumor.rumor_kind_of("murder", 4, R) == "bounty", "規則: 殺紅重量正 → bounty")
	check(RulesRumor.rumor_kind_of("murder", -1, R) == "", "規則: 重量唔夠 → 唔傳")
	check(RulesRumor.rumor_kind_of("greet", -4, R) == "", "規則: greet 唔係傳聞")
	check(RulesRumor.rumor_kind_of("die", -4, R) == "", "規則: die 唔係傳聞")
	check(RulesRumor.rumor_key(7, "killer") == "7:killer", "規則: key 格式")
	var rm := RulesRumor.make_rumor(7, "killer", -4, "xuchang", 3)
	check(String(rm["origin"]) == "xuchang" and (rm["cities"] as Dictionary).has("xuchang"), "規則: make_rumor 起源城即日")
	check(RulesRumor.delay(1, 3, 0) == 1 and RulesRumor.delay(1, 3, 2) == 3 and RulesRumor.delay(1, 3, 3) == 1, "規則: delay wrap")
	check(RulesRumor.delay(1, 3, 99) >= 1 and RulesRumor.delay(1, 3, 99) <= 3, "規則: delay 夾範圍")
	check(RulesRumor.reaches("xuchang", "xiangyang") and not RulesRumor.reaches("xuchang", "xuchang"), "規則: 只傳去唔同城")


# ================= 記憶表 =================

func t_memory() -> void:
	var mem := NpcMemory.init_memory()
	check((mem["rumors"] as Dictionary).is_empty(), "記憶: 初始化有 rumors 欄")
	NpcMemory.add_rumor(mem, "1:killer", {"actor": 1, "kind": "killer", "weight": -4, "origin": "xuchang", "day": 2}, 8)
	check(NpcMemory.has_rumor(mem, "1:killer"), "記憶: add → has")
	check(int(NpcMemory.rumor_of(mem, "1:killer").get("day", -1)) == 2, "記憶: rumor_of day")
	check(NpcMemory.rumor_count(mem) == 1 and NpcMemory.rumor_keys(mem)[0] == "1:killer", "記憶: count/keys")
	NpcMemory.add_rumor(mem, "1:killer", {"actor": 1, "kind": "killer", "weight": -9, "origin": "xuchang", "day": 5}, 8)
	check(int(NpcMemory.rumor_of(mem, "1:killer").get("weight", 0)) == -9 and NpcMemory.rumor_count(mem) == 1, "記憶: 同 key 覆蓋")
	for i in 10:
		NpcMemory.add_rumor(mem, "%d:killer" % (100 + i), {"actor": 100 + i, "kind": "killer", "weight": -4, "origin": "xuchang", "day": 10 + i}, 8)
	check(NpcMemory.rumor_count(mem) <= 8, "記憶: 超 cap 擠走 (got %d)" % NpcMemory.rumor_count(mem))
	var old := {"affinity": {}, "events": []}
	NpcMemory.add_rumor(old, "9:killer", {"actor": 9, "kind": "killer", "day": 1}, 8)
	check(NpcMemory.has_rumor(old, "9:killer"), "記憶: 舊記憶表冇 rumors 欄都寫得")


# ================= 目擊 → 種傳聞 =================

func t_witness_seed(data: GameData) -> void:
	var sim := _new(data, 42)
	var pid := int(sim.state["player_id"])
	var p := sim.ent(pid)
	var b := sim._spawn_actor("見證人", "bot")
	BotSys.init_identity(b, sim.rng)
	b["x"] = int(p["x"]) + 1
	b["y"] = int(p["y"])
	b["tx"] = int(b["x"])
	b["ty"] = int(b["y"])
	sim._witness_nearby(p, pid, "murder", -4)
	check(sim.rumor_view().size() == 1, "目擊: 種一條 killer 傳聞")
	var rv: Dictionary = sim.rumor_view()[0]
	check(String(rv["kind"]) == "killer", "目擊: kind = killer")
	check((rv["cities"] as Array).has("xuchang"), "目擊: 起源城即日揭示")
	check(NpcMemory.has_rumor(b["mem"], "%d:killer" % pid), "目擊: 見證人記憶表有傳聞")
	check(NpcMemory.has_rumor(b["mem"], "%d:killer" % pid) and sim.known_rumors(int(b["id"])).size() == 1, "目擊: known_rumors read-model")
	# 打招呼唔算傳聞
	sim._witness_nearby(p, pid, "greet", 2)
	check(sim.rumor_view().size() == 1, "目擊: greet 唔會種傳聞")
	# 同 actor 同 kind 再一次: 合併 (唔會變兩條)
	sim._witness_nearby(p, pid, "murder", -9)
	check(sim.rumor_view().size() == 1 and int(sim.rumor_view()[0]["weight"]) == -9, "目擊: 同 key 合併更新")


func t_kind_map(data: GameData) -> void:
	var sim := _new(data, 43)
	var pid := int(sim.state["player_id"])
	var p := sim.ent(pid)
	var b := sim._spawn_actor("見證人", "bot")
	BotSys.init_identity(b, sim.rng)
	b["x"] = int(p["x"]) + 1
	b["y"] = int(p["y"])
	sim._witness_nearby(p, pid, "murder", 4)
	check(sim.rumor_view().size() == 1 and String(sim.rumor_view()[0]["kind"]) == "bounty", "類型: 殺紅 → bounty")


# ================= 跨城延遲 =================

func t_cross_city(data: GameData) -> void:
	var sim := _new(data, 44)
	var pid := int(sim.state["player_id"])
	sim.add_residents()
	sim._seed_rumor(pid, "killer", -4, "xuchang", 10)
	var rv: Dictionary = sim.rumor_view()[0]
	var deliver: Dictionary = {}
	for r in sim.state["rumors"]:
		deliver = r["deliver"]
	check(not deliver.is_empty(), "跨城: 有其他城排期")
	var in_range := true
	for cid in deliver:
		var d := int(deliver[cid]) - 10
		if d < 1 or d > 3:
			in_range = false
	check(in_range, "跨城: 每個城延遲 1~3 日 (deliver=%s)" % str(deliver))
	# 另一城居民
	var xy := _city_of(sim, "xiangyang")
	var xc := _city_of(sim, "xuchang")
	check(xy != 0, "跨城: 搵到襄陽居民")
	check(xc != 0 and NpcMemory.has_rumor(sim.ent(xc)["mem"], "%d:killer" % pid), "跨城: 起源城居民即日已知")
	# day 10: 起源城有, 襄陽未有
	sim._rumor_daily(10)
	check(not NpcMemory.has_rumor(sim.ent(xy)["mem"], "%d:killer" % pid), "跨城: day10 襄陽未知")
	# 逐日反思到 day 13: 一定傳到
	for d in [11, 12, 13]:
		sim._rumor_daily(d)
	check(NpcMemory.has_rumor(sim.ent(xy)["mem"], "%d:killer" % pid), "跨城: day13 襄陽已知 (延遲 ≤3)")
	check((sim.rumor_view()[0]["cities"] as Array).size() == 10, "跨城: 最終 10 城都知")


# ================= 殺善 NPC → 義理同伴忠誠 −15 =================

func _loyalty_setup(data: GameData, seed_v: int, ideo: String, criminal: bool) -> Array:
	var sim := Sim.new(data, seed_v)
	var pid := sim.spawn_player("t", "yishi")
	var gid := int(data.general_by_id.keys()[0])
	var c := sim._spawn_companion(sim.ent(pid), data.general_by_id[gid])
	sim.player_ch()["recruit"] = {"comp": int(c["id"])}
	c["ch"]["ideology"] = ideo
	c["ch"]["genSkill"] = 0        # 排除「忠義」忠誠跌減半，測 base -15
	var b := sim._spawn_actor("街坊", "bot")
	BotSys.init_identity(b, sim.rng)
	b["ch"]["criminal"] = criminal
	b["ch"]["align"] = "good"
	var p := sim.ent(pid)
	b["x"] = int(p["x"]) + 1
	b["y"] = int(p["y"])
	b["tx"] = int(b["x"])
	b["ty"] = int(b["y"])
	return [sim, pid, c, b]


func t_loyalty_npc(data: GameData) -> void:
	# 謀殺善 NPC → 義理 −15
	var r := _loyalty_setup(data, 45, "義理", false)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var c: Dictionary = r[2]
	var b: Dictionary = r[3]
	var loy := int(c["gen"]["loyalty"])
	sim.ent(pid)["atk_target"] = int(b["id"])
	sim._kill_bot(b, sim.ent(pid))
	check(int(c["gen"]["loyalty"]) == loy + int(data.recruit_cfg["loyalty"]["badNpcKill"]), "忠誠: 謀殺善 NPC → 義理 %d" % int(data.recruit_cfg["loyalty"]["badNpcKill"]))
	check(int(data.recruit_cfg["loyalty"]["badNpcKill"]) == -15, "忠誠: badNpcKill = -15")
	# 自衛反殺 (冇追擊) → 唔扣
	var r2 := _loyalty_setup(data, 46, "義理", false)
	var sim2: Sim = r2[0]
	var c2: Dictionary = r2[2]
	var b2: Dictionary = r2[3]
	var loy2 := int(c2["gen"]["loyalty"])
	sim2.ent(int(r2[1]))["atk_target"] = 0
	sim2._kill_bot(b2, sim2.ent(int(r2[1])))
	check(int(c2["gen"]["loyalty"]) == loy2, "忠誠: 自衛反殺唔扣")
	# 殺紅名 → 唔扣
	var r3 := _loyalty_setup(data, 47, "義理", true)
	var sim3: Sim = r3[0]
	var c3: Dictionary = r3[2]
	var b3: Dictionary = r3[3]
	var loy3 := int(c3["gen"]["loyalty"])
	sim3.ent(int(r3[1]))["atk_target"] = int(b3["id"])
	sim3._kill_bot(b3, sim3.ent(int(r3[1])))
	check(int(c3["gen"]["loyalty"]) == loy3, "忠誠: 殺紅名唔扣")
	# 非義理念 → 唔扣
	var r4 := _loyalty_setup(data, 48, "霸權", false)
	var sim4: Sim = r4[0]
	var c4: Dictionary = r4[2]
	var b4: Dictionary = r4[3]
	var loy4 := int(c4["gen"]["loyalty"])
	sim4.ent(int(r4[1]))["atk_target"] = int(b4["id"])
	sim4._kill_bot(b4, sim4.ent(int(r4[1])))
	check(int(c4["gen"]["loyalty"]) == loy4, "忠誠: 非義理念唔扣")


# ================= read-model =================

func t_view(data: GameData) -> void:
	var sim := _new(data, 49)
	check(sim.rumor_view().is_empty() and sim.rumor_view("xuchang").is_empty(), "view: 冇傳聞 = 空")
	var pid := int(sim.state["player_id"])
	sim._seed_rumor(pid, "killer", -4, "xuchang", 1)
	check(sim.rumor_view().size() == 1, "view: 全部城 view")
	check(sim.rumor_view("xuchang").size() == 1 and sim.rumor_view("xiangyang").is_empty(), "view: 按城過濾")
	var o: Dictionary = sim.rumor_view()[0]
	check(int(o["actor"]) == pid and String(o["kind"]) == "killer" and int(o["weight"]) == -4, "view: 欄位齊")


# ================= 存檔 =================

func t_roundtrip(data: GameData) -> void:
	var sim := _new(data, 50)
	sim.add_residents()
	var pid := int(sim.state["player_id"])
	sim._seed_rumor(pid, "killer", -4, "xuchang", 3)
	var s1 := sim.save_string()
	var l := Sim.load_string(data, s1)
	check(l != null and l.save_string() == s1, "存檔: save→load→save 一致")
	check(l.rumor_view().size() == sim.rumor_view().size(), "存檔: 傳聞保留")
	var xc := _city_of(l, "xuchang")
	check(xc != 0 and l.known_rumors(xc).size() == 1, "存檔: 居民已知傳聞保留")


func t_old_save(data: GameData) -> void:
	var sim := _new(data, 51)
	sim.add_residents()
	var pid := int(sim.state["player_id"])
	sim._seed_rumor(pid, "killer", -4, "xuchang", 3)
	var d: Dictionary = JSON.parse_string(sim.save_string())
	(d["state"] as Dictionary).erase("rumors")
	(d["state"] as Dictionary).erase("rumorSeq")
	# 拎走一個居民記憶表嘅 rumors 欄 (模擬舊存檔)
	var rid := _city_of(sim, "xuchang")
	var ch: Dictionary = d["state"]["ents"][str(rid)]
	(ch["mem"] as Dictionary).erase("rumors")
	var old := Sim.load_string(data, JSON.stringify(d))
	check(old != null, "舊存檔: 載入唔 crash")
	check(old.rumor_view().is_empty(), "舊存檔: 補返空 rumors")
	check(old.known_rumors(rid).is_empty(), "舊存檔: 記憶表冇 rumors = 空")
	old._seed_rumor(int(old.state["player_id"]), "killer", -4, "xuchang", 3)
	check(old.rumor_view().size() == 1, "舊存檔: 之後種得到傳聞")
	check(old.save_string() != "", "舊存檔: 再存得")


func _run_seq(data: GameData) -> String:
	var sim := _new(data, 77)
	sim.add_residents()
	var pid := int(sim.state["player_id"])
	var p := sim.ent(pid)
	var b := sim._spawn_actor("見證人", "bot")
	BotSys.init_identity(b, sim.rng)
	b["x"] = int(p["x"]) + 1
	b["y"] = int(p["y"])
	sim._witness_nearby(p, pid, "murder", -4)
	for d in range(1, 6):
		sim._rumor_daily(d)
	for _i in 20:
		sim.step()
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_run_seq(data) == _run_seq(data), "決定性: 同種子同操作 → 同存檔")
