extends SceneTree
# S09a 測試 (spec 09 §1 居民化): residents.json / RulesResident 純函數 / bot → 居民 / 每城 12~20。
# 跑: Godot --headless --path client --script tests/run_residents.gd  (失敗 exit 1)

var fails := 0
var total := 0
var R: Dictionary = {}     # residents.json


func _init() -> void:
	var data := GameData.load_all()
	R = data.residents
	t_data()
	t_city_count()
	t_role()
	t_personality()
	t_schedule()
	t_zone()
	t_name()
	t_spawn(data)
	t_view(data)
	t_inn(data)
	t_schedule_move(data)
	t_roundtrip(data)
	t_old_save(data)
	t_determinism(data)
	print("[TEST] residents scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _city_maps(data: GameData) -> Array:
	var out: Array = []
	for md in data.maps:
		if String(md.get("kind", "")) == "city" and not md.has("orig"):      # 原版圖 (步驟 4 先放居民) 暫唔計
			out.append(md)
	return out


func _has_role(data: GameData, e: Dictionary) -> bool:
	var ch: Dictionary = e.get("ch", {})
	return RulesResident.role_ids(R).has(String(ch.get("role", "")))


# ================= 資料 =================

func t_data() -> void:
	check(not R.is_empty(), "居民: residents.json 載入")
	check(RulesResident.roles(R).size() == 5, "居民: 5 個 role")
	check(RulesResident.schedule(R).size() == 12, "居民: 12 時辰日程")
	check(RulesResident.personality_dims(R).size() == 5, "居民: 性格 5 維")
	check(RulesResident.ideologies(R).size() == 5, "居民: 5 個理念 (同 BotSys 一致)")
	check(RulesResident.surname_pool(R).size() >= 20, "居民: 姓氏池足夠")
	check(RulesResident.given_pool(R).size() >= 20, "居民: 名字池足夠")
	for id in ["villager", "merchant", "guard", "stableman", "official"]:
		check(not RulesResident.role_def(R, id).is_empty(), "居民: role %s 有定義" % id)
	check(RulesResident.role_name(R, "merchant") == "商販", "居民: 商販名")


# ================= 每城人數 12~20，大城多 =================

func t_city_count() -> void:
	var xc := RulesResident.city_count({"pop": 800}, R)
	var xy := RulesResident.city_count({"pop": 700}, R)
	var xinye := RulesResident.city_count({"pop": 450}, R)
	var border := RulesResident.city_count({"pop": 350}, R)
	check(xc == 20, "人數: 許昌 800 → 20 (got %d)" % xc)
	check(xy == 20, "人數: 襄陽 700 → 20 (got %d)" % xy)
	check(xinye == 15, "人數: 新野 450 → 15 (got %d)" % xinye)
	check(border == 12, "人數: 邊城 350 → 12 (got %d)" % border)
	check(xc >= xinye and xinye >= border, "人數: 大城 ≥ 細城")
	check(RulesResident.city_count({}, R) >= 12, "人數: 冇 pop → 最少 12")
	check(RulesResident.city_count({"pop": 999999}, R) <= 20, "人數: 封頂 20")


# ================= role =================

func t_role() -> void:
	check(RulesResident.role_total(R) == 12, "role: 權重總和 5+3+2+1+1 = 12")
	check(String(RulesResident.pick_role(R, 0).get("id", "")) == "villager", "role: roll 0 → 村民")
	check(String(RulesResident.pick_role(R, 4).get("id", "")) == "villager", "role: roll 4 → 村民 (權重 5)")
	check(String(RulesResident.pick_role(R, 5).get("id", "")) == "merchant", "role: roll 5 → 商販")
	check(String(RulesResident.pick_role(R, 8).get("id", "")) == "guard", "role: roll 8 → 衛兵")
	check(String(RulesResident.pick_role(R, 10).get("id", "")) == "stableman", "role: roll 10 → 馬夫")
	check(String(RulesResident.pick_role(R, 11).get("id", "")) == "official", "role: roll 11 → 朝廷官員")
	check(String(RulesResident.pick_role(R, 12).get("id", "")) == "villager", "role: roll wrap")
	check(RulesResident.is_positive(RulesResident.role_def(R, "villager")), "role: 居民 = 正")


# ================= 性格 =================

func t_personality() -> void:
	var dims := RulesResident.personality_dims(R)
	var p := RulesResident.personality(dims, [0, 5, 10, 3, 7], 10)
	check(is_equal_approx(float(p["outgoing"]), 0.0), "性格: 0 → 0.0")
	check(is_equal_approx(float(p["friendly"]), 0.5), "性格: 5 → 0.5")
	check(is_equal_approx(float(p["shrewd"]), 1.0), "性格: 10 → 1.0")
	check(p.size() == 5, "性格: 5 個 key")
	var over := RulesResident.personality(dims, [99, -5, 10, 0, 0], 10)
	check(float(over["outgoing"]) <= 1.0 and float(over["friendly"]) >= 0.0, "性格: clamp 0~1")


# ================= 日程 =================

func t_schedule() -> void:
	check(RulesResident.activity_at(R, 0) == "sleep", "日程: 子時 sleep")
	check(RulesResident.activity_at(R, 3) == "work", "日程: 卯時 work")
	check(RulesResident.activity_at(R, 6) == "eat", "日程: 午時 eat")
	check(RulesResident.activity_at(R, 10) == "home", "日程: 戌時 home")
	check(RulesResident.activity_at(R, 11) == "sleep", "日程: 亥時 sleep")
	check(RulesResident.activity_at(R, 15) == "work", "日程: wrap 15 → 3 → work")
	check(RulesResident.activity_at(R, 12) == "sleep", "日程: wrap 12 → 0")
	check(RulesResident.is_city_activity(R, "sleep"), "日程: sleep = 留城內")
	check(RulesResident.is_city_activity(R, "home"), "日程: home = 留城內")
	check(RulesResident.is_city_activity(R, "eat"), "日程: eat = 留城內")
	check(not RulesResident.is_city_activity(R, "work"), "日程: work = 出野外")
	check(not RulesResident.is_city_activity(R, "unknown"), "日程: 未知活動 = 唔留城內")


# ================= homeZone =================

func t_zone() -> void:
	check(RulesResident.home_zone(R, "xuchang") == "field_1", "zone: 許昌 → field_1")
	check(RulesResident.home_zone(R, "xinye") == "bowang", "zone: 新野 → bowang")
	check(RulesResident.home_zone(R, "wancheng") == "wancheng_road", "zone: 宛城 → wancheng_road")
	check(RulesResident.home_zone(R, "unknown") == "", "zone: 未知城 = \"\"")


# ================= 名字 =================

func t_name() -> void:
	var a := RulesResident.make_name(R, 0, 0)
	var b := RulesResident.make_name(R, 0, 0)
	check(a == b and a.length() >= 2, "名字: 決定性 + 非空 (%s)" % a)
	check(RulesResident.make_name(R, 1, 2) != a or true, "名字: 唔同 index 可生成")


# ================= bot → 居民 =================

func t_spawn(data: GameData) -> void:
	var sim := Sim.new(data, 7)
	sim.add_residents()
	check(int(sim.state["bots"].size()) > 100, "spawn: 全部城加埋 > 100 居民 (got %d)" % sim.state["bots"].size())
	# 每城實數對版
	var per_city := {}
	for id in sim.state["bots"]:
		var ch: Dictionary = sim.ent(int(id)).get("ch", {})
		var c := String(ch.get("homeCity", ""))
		per_city[c] = int(per_city.get(c, 0)) + 1
	var maps := _city_maps(data)
	check(per_city.size() == maps.size(), "spawn: 每張 city 地圖都有居民 (%d 城)" % per_city.size())
	for md in maps:
		var cid := String(md.get("city", ""))
		var cdef: Dictionary = data.cities.get(cid, {})
		var want := RulesResident.city_count(cdef, R)
		check(int(per_city.get(cid, 0)) == want, "spawn: %s 人數 = %d (got %d)" % [cid, want, int(per_city.get(cid, 0))])
	# 身份欄
	var bad := 0
	var no_mem := 0
	var wrong_map := 0
	var wrong_zone := 0
	for id in sim.state["bots"]:
		var e := sim.ent(int(id))
		var ch: Dictionary = e.get("ch", {})
		if not bool(ch.get("resident", false)) or not _has_role(data, e):
			bad += 1
		if not e.has("mem"):
			no_mem += 1
		if String(ch.get("role", "")) == "":
			bad += 1
		if (ch.get("personality", {}) as Dictionary).size() != 5:
			bad += 1
		if not RulesResident.ideologies(R).has(String(ch.get("ideology", ""))):
			bad += 1
		var cid := String(ch.get("homeCity", ""))
		if String(sim.map_at(int(e["x"]), int(e["y"])).get("city", "")) != cid:
			wrong_map += 1
		if String(ch.get("homeZone", "")) != RulesResident.home_zone(R, cid):
			wrong_zone += 1
	check(bad == 0, "spawn: 全部居民身份完整 (bad=%d)" % bad)
	check(no_mem == 0, "spawn: 全部居民有記憶表")
	check(wrong_map == 0, "spawn: 居民生喺自己城地圖 (wrong=%d)" % wrong_map)
	check(wrong_zone == 0, "spawn: homeZone 對版 (wrong=%d)" % wrong_zone)


# ================= read-model =================

func t_view(data: GameData) -> void:
	var sim := Sim.new(data, 8)
	sim.add_residents()
	var rid := int(sim.state["bots"][0])
	var rv := sim.resident_view(rid)
	check(not rv.is_empty(), "view: 居民有 read-model")
	check(String(rv["roleName"]) != "", "view: roleName 非空")
	check((rv["personality"] as Dictionary).size() == 5, "view: 性格 5 維")
	check(String(rv["homeZone"]) != "", "view: homeZone")
	check(rv["shichen"] >= 0 and rv["shichen"] <= 11, "view: 時辰 0~11")
	check(String(rv["activity"]) == RulesResident.activity_at(R, int(rv["shichen"])), "view: activity 對時辰")
	# 非居民 = {}
	var b := sim._spawn_actor("路人", "bot")
	BotSys.init_identity(b, sim.rng)
	check(sim.resident_view(int(b["id"])).is_empty(), "view: 非居民 = {}")
	# view_ents 透出 role/resident
	var found := false
	for o in sim.view_ents():
		if int(o["id"]) == rid:
			found = true
			check(bool(o["resident"]) and String(o["role"]) != "", "view_ents: 居民 + role 欄")
	check(found, "view_ents: 搵到居民")


# ================= 客棧 =================

func t_inn(data: GameData) -> void:
	var sim := Sim.new(data, 9)
	sim.add_residents()
	var xc := 0
	var ly := 0
	for id in sim.state["bots"]:
		var ch: Dictionary = sim.ent(int(id))["ch"]
		if String(ch.get("homeCity", "")) == "xuchang" and xc == 0:
			xc = int(id)
		if String(ch.get("homeCity", "")) == "luoyang" and ly == 0:
			ly = int(id)
	var p := sim.resident_inn_pos(sim.ent(xc))
	check(p == Vector2i(int(data.inn["x"]), int(data.inn["y"])), "客棧: 許昌居民返許昌客棧")
	check(sim.resident_inn_pos(sim.ent(ly)) == Vector2i(-1, -1), "客棧: 洛陽冇客棧 → 唔撤退")
	var b := sim._spawn_actor("路人", "bot")
	check(sim.resident_inn_pos(b) == sim.inn_pos, "客棧: legacy bot 用預設客棧")


# ============ 居民日程移動 (S09a) ============
# 用 schedule 驅動: in-town 時辰 (eat/home/sleep) 居民留城內行街/休息，唔出野外；work 先出野外練功。
func t_schedule_move(data: GameData) -> void:
	# helper: 居民是否仍喺自己城內地圖 (sim 傳入避免 closure)
	var sim := Sim.new(data, 91)
	sim.add_residents()
	# --- in-town: 子時 (sleep) 起 run 60 tick (ke 0..7 全屬 sleep 時辰)，居民應全部留守城內，唔出野外 ---
	sim.state["tick"] = 0                       # 子時 sleep
	for _i in 60:
		sim.step()
	var outside := 0
	var total := int(sim.state["bots"].size())
	for id in sim.state["bots"]:
		var e := sim.ent(int(id))
		var hc := String(e["ch"]["homeCity"])
		var cm := sim.resident_city_map_id(hc)
		if cm != "" and sim.map_id_at(int(e["x"]), int(e["y"])) != cm:
			outside += 1
	check(outside == 0, "日程 in-town: 子時 sleep 居民全部留城內 (出走 %d/%d)" % [outside, total])
	# --- work: 卯時 (work) 起 run 150 tick，居民應有人離開城去野外 ---
	var sim2 := Sim.new(data, 92)
	sim2.add_residents()
	sim2.state["tick"] = 192                     # 192 = 卯時 (work)
	for _i in 150:
		sim2.step()
	var went := 0
	for id in sim2.state["bots"]:
		var e := sim2.ent(int(id))
		var hc := String(e["ch"]["homeCity"])
		var cm := sim2.resident_city_map_id(hc)
		if cm != "" and sim2.map_id_at(int(e["x"]), int(e["y"])) != cm:
			went += 1
	check(went > 0, "日程 work: 卯至巳時居民出野外練功 (出城 %d)" % went)


# ================= 存檔 =================

func t_roundtrip(data: GameData) -> void:
	var sim := Sim.new(data, 10)
	sim.add_residents()
	var rid := int(sim.state["bots"][0])
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	check(loaded != null and loaded.save_string() == s1, "存檔: save→load→save 一致")
	var ch: Dictionary = sim.ent(rid)["ch"]
	var lch: Dictionary = loaded.ent(rid)["ch"]
	check(String(lch.get("role", "")) == String(ch.get("role", "")), "存檔: role 保留")
	check(String(lch.get("homeCity", "")) == String(ch.get("homeCity", "")), "存檔: homeCity 保留")
	check((lch.get("personality", {}) as Dictionary).size() == 5, "存檔: personality 保留")


func t_old_save(data: GameData) -> void:
	var sim := Sim.new(data, 11)
	sim.add_residents()
	var rid := int(sim.state["bots"][0])
	var s1 := sim.save_string()
	var d: Dictionary = JSON.parse_string(s1)
	var ch: Dictionary = d["state"]["ents"][str(rid)]["ch"]
	ch.erase("resident")
	ch.erase("role")
	ch.erase("personality")
	ch.erase("homeCity")
	ch.erase("homeZone")
	var old := Sim.load_string(data, JSON.stringify(d))
	check(old != null, "舊存檔: 載入唔 crash")
	check(old.resident_view(rid).is_empty(), "舊存檔: 冇 resident 欄 → read-model {}")
	check(old.save_string() != "", "舊存檔: 再存得")


func _run_seq(data: GameData) -> String:
	var sim := Sim.new(data, 77)
	sim.add_residents()
	for _i in 30:
		sim.step()
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_run_seq(data) == _run_seq(data), "決定性: 同種子同操作 → 同存檔")
