extends SceneTree
# 特殊場景測試 (S04d，spec 04 §4): 純函數 (日曆開門/資格/層) + 資料完整性 +
# sim 整合 (桃花渡 5 層入/過層/完場/死亡唔跌/離開/等级閘/關門日/存檔 roundtrip/決定性) + 七彩奪寶陣
# 跑: Godot --headless --path client --script tests/run_scene.gd   (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_rules(data)
	t_data(data)
	t_enter(data)
	t_full_run_taohuadu(data)
	t_qicai_bosses(data)
	t_death_no_loss(data)
	t_leave(data)
	t_closed(data)
	t_roundtrip(data)
	t_determinism(data)
	print("[TEST] scene: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


# ---------- helpers ----------
func _new(data: GameData, seed: int, lv: int = 80) -> Array:
	var sim := Sim.new(data, seed)
	var id := sim.spawn_player("t")
	var ch: Dictionary = sim.player_ch()
	ch["level"] = lv
	sim._sync_quest_npcs()
	var msgs: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev["k"] == "msg" and int(ev.get("dst", -1)) == id:
			msgs.append(str(ev["text"])))
	return [sim, id, ch, msgs]


# 季頭 (day 0 = 初一) 一定有開門日；用 day 直接 set (模擬 _clock()["day"])
func _set_day(sim: Sim, day: int) -> void:
	sim.state["clock"]["day"] = day


# 玩家搬到場景入口 NPC 度 (map 相同 + near)
func _goto_gate(sim: Sim, id: int, sid: String) -> void:
	var n: Dictionary = sim._scene_gate(sid)
	var e := sim.ent(id)
	e["x"] = int(n["x"])
	e["tx"] = int(e["x"])
	e["y"] = int(n["y"]) + 1
	e["ty"] = int(e["y"])
	e.erase("path")


func _scene_mobs(sim: Sim, sid: String) -> Array:
	var out: Array = []
	for e in sim.ents.values():
		if e["kind"] == "mob" and str(e.get("mob", {}).get("scene_id", "")) == sid:
			out.append(e)
	return out


func _find_boss(sim: Sim, sid: String) -> Dictionary:
	for e in sim.ents.values():
		if e["kind"] == "mob" and str(e.get("mob", {}).get("scene_id", "")) == sid \
				and bool(e.get("mob", {}).get("scene_boss", false)):
			return e
	return {}


# ---------- 純函數 ----------
func t_rules(data: GameData) -> void:
	var sc := RulesScene.find(data.scenes, "taohuadu")
	check(not sc.is_empty(), "桃花渡場景存在")
	check(RulesScene.is_open(sc, 0, 30), "初一 (day0) 開門")
	check(RulesScene.is_open(sc, 2, 30), "初三 (day2) 開門")
	check(not RulesScene.is_open(sc, 3, 30), "初四 (day3) 唔開")
	check(RulesScene.is_open(sc, 14, 30), "十五 (day14) 開門")
	check(RulesScene.is_open(sc, 16, 30), "十七 (day16) 開門")
	check(not RulesScene.is_open(sc, 17, 30), "十八 (day17) 唔開")
	check(RulesScene.can_enter(sc, 75, 0, 30) == "", "桃花渡 75 級初一入得")
	check(RulesScene.can_enter(sc, 74, 0, 30) != "", "桃花渡 74 級唔夠")
	check(RulesScene.can_enter(sc, 75, 3, 30) != "", "桃花渡初四唔開")
	check(RulesScene.layer_count(sc) == 5, "桃花渡 5 層")
	check(not RulesScene.is_last_layer(sc, 3), "桃花渡第 4 層唔係尾")
	check(RulesScene.is_last_layer(sc, 4), "桃花渡第 5 層 = 尾層")
	check(RulesScene.day_of_month(0, 30) == 1, "day0 = 初一 (1 日)")
	check(RulesScene.day_of_month(29, 30) == 30, "day29 = 三十 (30 日)")
	var qc := RulesScene.find(data.scenes, "qicai")
	check(not qc.is_empty(), "七彩奪寶陣存在")
	check(RulesScene.layer_count(qc) == 7, "七彩奪寶陣 7 層")
	check(RulesScene.can_enter(qc, 70, 0, 30) == "", "七彩奪寶陣 70 級初一入得")


# ---------- 資料完整性 ----------
func t_data(data: GameData) -> void:
	check(data.scenes.size() == 2, "首批 2 個特殊場景資料齊")
	for s in data.scenes:
		var sid := String(s["id"])
		check(not String(s["name"]).is_empty(), "%s 有名" % sid)
		check(RulesScene.layer_count(s) > 0, "%s 有層" % sid)
		check(not String(s.get("entryMap", "")).is_empty(), "%s 有入口地圖" % sid)
		for layer in s.get("layers", []):
			var mid := String(layer["map"])
			var found := false
			for m in data.maps:
				if String(m["id"]) == mid:
					found = true
			check(found, "%s 層地圖存在 (%s)" % [sid, mid])
			for mid2 in layer.get("monsters", []):
				check(data.mob_def(int(mid2)).get("_scene", "") == sid or not data.mob_def(int(mid2)).is_empty(),
					"%s 層怪物 %d 存在" % [sid, int(mid2)])
	# 場景怪物至少有一款 boss
	for sc in data.scenes:
		var sid := String(sc["id"])
		var has_boss := false
		for md in sc.get("monsters", []):
			if bool(md.get("boss", false)):
				has_boss = true
		check(has_boss, "%s 有 boss" % sid)
		# 每個場景入口 NPC 存在
		check(not sim0_gate(data, sid).is_empty(), "%s 入口 NPC 存在")


func sim0_gate(data: GameData, sid: String) -> Dictionary:
	for n in data.quest_npc_list:
		if String(n.get("scene", "")) == sid:
			return n
	return {}


# ---------- sim: 入場基本流程 ----------
func t_enter(data: GameData) -> void:
	var r := _new(data, 1)
	var sim: Sim = r[0]; var id: int = r[1]; var msgs: Array = r[3]
	sim.cmd_scene_enter(id, "taohuadu")
	check(not sim.ent(id).has("scene"), "唔喺入口附近入唔到")
	check(msgs.size() > 0, "有提示")
	msgs.clear()
	_goto_gate(sim, id, "taohuadu")
	_set_day(sim, 3)     # 初四 → 唔開
	sim.cmd_scene_enter(id, "taohuadu")
	check(not sim.ent(id).has("scene"), "關門日入唔到")
	msgs.clear()
	_set_day(sim, 0)     # 初一 → 開
	sim.cmd_scene_enter(id, "taohuadu")
	check(sim.ent(id).has("scene"), "初一喺入口入到桃花渡")
	check(String(sim.ent(id)["scene"]["id"]) == "taohuadu", "入咗桃花渡")
	check(int(sim.ent(id)["scene"]["layer"]) == 0, "入場喺第 1 層 (idx0)")
	# 第 1 層應該出啲怪 (boss 款+一般款 density)
	var mobs := _scene_mobs(sim, "taohuadu")
	check(mobs.size() >= 3, "桃花渡第 1 層有怪物 (≥3)")


# ---------- sim: 打齊 5 層完場，回傳入口 ----------
func t_full_run_taohuadu(data: GameData) -> void:
	var r := _new(data, 2)
	var sim: Sim = r[0]; var id: int = r[1]
	_set_day(sim, 0)
	_goto_gate(sim, id, "taohuadu")
	var g: Dictionary = sim._scene_gate("taohuadu")
	var gx := int(g["x"]); var gy := int(g["y"])
	var md := sim._map_def(String(g["map"]))
	var bx := int(g["x"]); var by := int(g["y"])
	sim.cmd_scene_enter(id, "taohuadu")
	var sc := RulesScene.find(data.scenes, "taohuadu")
	for li in 5:
		# 每層殺 boss
		var b0 := _find_boss(sim, "taohuadu")
		check(not b0.is_empty(), "桃花渡第 %d 層 boss 存在" % (li + 1))
		check(int(b0["mob"]["scene_layer"]) == li, "boss scene_layer 啱 (%d)" % li)
		sim._kill_mob(b0, sim.ent(id))
	check(not sim.ent(id).has("scene"), "打完 5 層自動離場")
	check(int(sim.ent(id)["x"]) == bx and int(sim.ent(id)["y"]) == by, "完場傳返入口原位")
	check(_scene_mobs(sim, "taohuadu").is_empty(), "完場冇殘留場景怪")
	# 掉落直入袋 (神行符 65008 / 迷宮戒指 65012 掉過)
	var bag: Array = sim.player_ch()["bag"]
	check(bag.size() >= 5, "桃花渡打完有攞到掉落")


# ---------- sim: 七彩奪寶陣 7 色孟獲逐層打完 ----------
func t_qicai_bosses(data: GameData) -> void:
	var r := _new(data, 5)
	var sim: Sim = r[0]; var id: int = r[1]
	_set_day(sim, 0)
	_goto_gate(sim, id, "qicai")
	sim.cmd_scene_enter(id, "qicai")
	check(sim.ent(id).has("scene"), "七彩奪寶陣初一入到")
	var sc := RulesScene.find(data.scenes, "qicai")
	for li in 7:
		var b0 := _find_boss(sim, "qicai")
		check(not b0.is_empty(), "七彩奪寶陣第 %d 層 孟獲 存在" % (li + 1))
		sim._kill_mob(b0, sim.ent(id))
	check(not sim.ent(id).has("scene"), "七彩奪寶陣打完自動離場")


# ---------- sim: 場景內死亡唔跌經驗/物品，傳返入口 ----------
func t_death_no_loss(data: GameData) -> void:
	var r := _new(data, 3)
	var sim: Sim = r[0]; var id: int = r[1]; var ch: Dictionary = r[2]
	ch["exp"] = 500
	ch["bag"] = [{"id": 10001, "n": 3}]
	_set_day(sim, 0)
	_goto_gate(sim, id, "taohuadu")
	var g: Dictionary = sim._scene_gate("taohuadu")
	var bx := int(g["x"]); var by := int(g["y"])
	sim.cmd_scene_enter(id, "taohuadu")
	sim._kill_player(sim.ent(id))
	check(int(sim.player_ch()["exp"]) == 500, "場景內死亡唔跌經驗")
	var n := 0
	for b in sim.player_ch()["bag"]:
		if int(b["id"]) == 10001:
			n = int(b["n"])
	check(n == 3, "場景內死亡唔跌物品")
	check(not sim.ent(id).has("scene"), "死亡自動離開場景")
	check(int(sim.ent(id)["x"]) == bx and int(sim.ent(id)["y"]) == by, "死亡傳返入口原位")
	check(_scene_mobs(sim, "taohuadu").is_empty(), "死亡後殘留場景怪清晒")


# ---------- sim: 放棄場景 ----------
func t_leave(data: GameData) -> void:
	var r := _new(data, 4)
	var sim: Sim = r[0]; var id: int = r[1]
	_set_day(sim, 0)
	_goto_gate(sim, id, "taohuadu")
	sim.cmd_scene_enter(id, "taohuadu")
	check(sim.ent(id).has("scene"), "入到先")
	sim.cmd_scene_leave(id)
	check(not sim.ent(id).has("scene"), "離開場景")
	check(_scene_mobs(sim, "taohuadu").is_empty(), "離開後殘留怪清晒")


# ---------- sim: 等級閘 ----------
func t_closed(data: GameData) -> void:
	var r := _new(data, 6, 60)   # 60 級
	var sim: Sim = r[0]; var id: int = r[1]
	_set_day(sim, 0)
	_goto_gate(sim, id, "taohuadu")
	sim.cmd_scene_enter(id, "taohuadu")
	check(not sim.ent(id).has("scene"), "桃花渡 60 級 (<75) 入唔到")


# ---------- sim: 存檔 roundtrip ----------
func t_roundtrip(data: GameData) -> void:
	var r := _new(data, 7)
	var sim: Sim = r[0]; var id: int = r[1]
	_set_day(sim, 0)
	_goto_gate(sim, id, "taohuadu")
	sim.cmd_scene_enter(id, "taohuadu")
	check(sim.ent(id).has("scene"), "入到先 (roundtrip)")
	var save := sim.save_string()
	var sim2 := Sim.load_string(data, save)
	check(sim2 != null, "存檔 load 到")
	check(sim2.ent(id).has("scene"), "場景狀態喺存檔 roundtrip 保留")
	var s2: Dictionary = sim2.ent(id)["scene"]
	check(String(s2.get("id", "")) == "taohuadu", "roundtrip 後場景 id 啱")


# ---------- sim: 決定性 (同 seed 兩次結果一樣) ----------
func t_determinism(data: GameData) -> void:
	var r1 := _new(data, 11, 80)
	var s1: Sim = r1[0]; var id1: int = r1[1]
	_set_day(s1, 0)
	_goto_gate(s1, id1, "taohuadu")
	s1.cmd_scene_enter(id1, "taohuadu")
	var r2 := _new(data, 11, 80)
	var s2: Sim = r2[0]; var id2: int = r2[1]
	_set_day(s2, 0)
	_goto_gate(s2, id2, "taohuadu")
	s2.cmd_scene_enter(id2, "taohuadu")
	var nick1 := s1.save_string()
	var nick2 := s2.save_string()
	check(nick1 == nick2, "場景入場同 seed 決定性 (存取字串一致)")