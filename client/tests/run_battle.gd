extends SceneTree
# 戰役任務測試 (Step 19，spec 06 §7/spec 04 §5): 純函數 (窗口/報名資格/層數) +
# sim 整合 (張牛角 4 層報名/過層/完場/死亡唔跌經驗物品/放棄/存檔 roundtrip/決定性)
# 跑: Godot --headless --path client --script tests/run_battle.gd   (失敗 exit 1)

var fails := 0
var total := 0

const HERALD_ID := "battle_herald"


func _init() -> void:
	var data := GameData.load_all()
	t_rules(data)
	t_data(data)
	t_enter(data)
	t_full_run(data)
	t_five_battles(data)
	t_death_no_loss(data)
	t_leave(data)
	t_level_gate(data)
	t_floor_mobs(data)
	t_roundtrip(data)
	t_determinism(data)
	print("[TEST] battle: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


# ---------- helpers ----------
func _new(data: GameData, seed: int, lv: int = 10) -> Array:
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


func _herald(sim: Sim) -> Dictionary:
	return sim.data.quest_npcs[HERALD_ID]


func _goto_herald(sim: Sim, id: int) -> void:
	var n := _herald(sim)
	var e := sim.ent(id)
	e["x"] = int(n["x"])
	e["tx"] = int(n["x"])
	e["y"] = int(n["y"]) + 1
	e["ty"] = int(n["y"]) + 1
	e.erase("path")


func _set_ke(sim: Sim, ke: int) -> void:
	sim.state["clock"]["ke"] = ke


func _cur_boss(sim: Sim, bid: String) -> Dictionary:
	for e in sim.ents.values():
		if e["kind"] == "mob" and str(e.get("mob", {}).get("battle_id", "")) == bid:
			return e
	return {}


# ---------- 純函數 ----------
func t_rules(data: GameData) -> void:
	check(RulesBattle.open_id(data.battles, 80) == "zhangniujiao", "戌時 0 刻 = 張牛角窗")
	check(RulesBattle.open_id(data.battles, 87) == "zhangniujiao", "戌時 7 刻仍係張牛角窗")
	check(RulesBattle.open_id(data.battles, 88) != "zhangniujiao", "戌時 8 刻已經過咗窗")
	check(RulesBattle.open_id(data.battles, 0) == "chufeiyan", "子時 0 刻 = 褚飛燕窗")
	check(RulesBattle.open_id(data.battles, 16) == "lidamu", "寅時 0 刻 = 李大目窗")
	check(RulesBattle.open_id(data.battles, 32) == "zhangbaiqi", "辰時 0 刻 = 張白騎窗")
	check(RulesBattle.open_id(data.battles, 48) == "huanglong", "午時 0 刻 = 黃龍窗")
	check(RulesBattle.open_id(data.battles, 64) == "shichangshi", "申時 0 刻 = 十常侍窗")
	check(RulesBattle.open_id(data.battles, 90) == "", "戌時 10 刻 (窗與窗之間) 冇戰役開放")
	var znj := RulesBattle.find(data.battles, "zhangniujiao")
	check(RulesBattle.can_enter(znj, 20) == "", "武等 20 剛好入得張牛角")
	check(RulesBattle.can_enter(znj, 21) != "", "武等 21 超過上限")
	var cfy := RulesBattle.find(data.battles, "chufeiyan")
	check(RulesBattle.can_enter(cfy, 10) == "", "褚飛燕 (≤30) 武等 10 入得")
	check(RulesBattle.can_enter(cfy, 31) != "", "褚飛燕武等 31 超上限")
	check(RulesBattle.can_enter({}, 10) != "", "冇開場 = 入唔到")
	check(RulesBattle.floor_count(znj) == 4, "張牛角 4 層")
	check(not RulesBattle.is_last_floor(znj, 2), "第 3 層 (idx2) 唔係尾層")
	check(RulesBattle.is_last_floor(znj, 3), "第 4 層 (idx3) = 尾層")
	check(not RulesBattle.drop_on_death(znj), "張牛角戰役死亡唔跌經驗/物品")


# ---------- 資料完整性 ----------
func t_data(data: GameData) -> void:
	check(data.battles.size() == 6, "6 場戰役資料齊")
	for b in data.battles:
		check(not String(b["id"]).is_empty(), "battle id 唔空")
		check((b["floors"] as Array).size() > 0, "%s 有層數" % String(b["id"]))
		check(bool(b.get("playable", false)), "%s 已 playable" % String(b["id"]))
		var bc: int = (b["floors"] as Array).size()
		for i in bc:
			var fl: Dictionary = b["floors"][i]
			check(data.monsters.has(int(fl["monster"])), "%s 第 %d 層怪物存在" % [String(b["id"]), i + 1])
			var mid := String(fl["map"])
			var found := false
			for m in data.maps:
				if String(m["id"]) == mid:
					found = true
			check(found, "%s 第 %d 層地圖存在 (%s)" % [String(b["id"]), i + 1, mid])


# ---------- sim: 報名基本流程 ----------
func t_enter(data: GameData) -> void:
	var r := _new(data, 1)
	var sim: Sim = r[0]; var id: int = r[1]; var msgs: Array = r[3]
	_set_ke(sim, 10)     # 窗與窗之間 (子 9 刻)，冇戰役開
	_goto_herald(sim, id)
	sim.cmd_battle_enter(id)
	check(not sim.ent(id).has("battle"), "無開窗報名唔到")
	check(msgs.size() > 0, "有提示訊息")
	msgs.clear()
	_set_ke(sim, 0)      # 子時 = 褚飛燕窗，而家 playable
	var e := sim.ent(id)
	e["x"] = 0; e["tx"] = 0; e["y"] = 0; e["ty"] = 0; e.erase("path")   # 遠離義勇士兵
	sim.cmd_battle_enter(id)
	check(not sim.ent(id).has("battle"), "唔喺義勇士兵附近報名唔到")
	_goto_herald(sim, id)
	sim.cmd_battle_enter(id)
	check(sim.ent(id).has("battle"), "喺義勇士兵附近 + 開窗 = 報名成功")
	check(String(sim.ent(id)["battle"]["id"]) == "chufeiyan", "入咗褚飛燕戰役")
	check(int(sim.ent(id)["battle"]["floor"]) == 0, "報名成功喺第 1 層 (idx0)")
	var boss := _cur_boss(sim, "chufeiyan")
	check(not boss.is_empty() and String(boss["name"]) == "百夫長", "褚飛燕第 1 層 boss = 百夫長")
	check(int(boss["mob"]["battle_floor"]) == 0, "boss 記低 battle_floor 0")
	sim.cmd_battle_enter(id)
	check(int(sim.ent(id)["battle"]["floor"]) == 0, "已經喺戰役入面唔會再報名一次")


# ---------- sim: 打齊 4 層完場，回報返報名點，boss 冇殘留 ----------
func t_full_run(data: GameData) -> void:
	var r := _new(data, 2)
	var sim: Sim = r[0]; var id: int = r[1]
	_set_ke(sim, 80)
	_goto_herald(sim, id)
	var h := _herald(sim)
	var bx := int(h["x"]); var by := int(h["y"])
	sim.cmd_battle_enter(id)
	for floor_i in 4:
		var boss := _cur_boss(sim, "zhangniujiao")
		check(not boss.is_empty(), "第 %d 層 boss 存在" % (floor_i + 1))
		check(int(boss["mob"]["battle_floor"]) == floor_i, "boss battle_floor 啱 (%d)" % floor_i)
		sim._kill_mob(boss, sim.ent(id))
	check(not sim.ent(id).has("battle"), "打完 4 層自動離場")
	check(int(sim.ent(id)["x"]) == bx and int(sim.ent(id)["y"]) == by, "完場傳送返義勇士兵原位")
	check(_cur_boss(sim, "zhangniujiao").is_empty(), "完場冇殘留 boss")
	var bag: Array = sim.player_ch()["bag"]
	var got := {}
	for b in bag:
		got[int(b["id"])] = int(b["n"])
	for iid in [65099, 32041, 30565, 23073, 30575, 23074, 30566, 30576]:
		check(got.get(iid, 0) >= 1, "4 層掉寶 item %d 攞齊" % iid)


# ---------- sim: 其餘 5 場戰役 (褚飛燕/李大目/張白騎/黃龍/十常侍) 全部 playable 逐層打死完場 + 掉寶齊 ----------
func t_five_battles(data: GameData) -> void:
	var wins := 0
	var seed := 50
	for b in data.battles:
		var bid := String(b["id"])
		if bid == "zhangniujiao":
			continue
		var r := _new(data, seed)
		seed += 1
		var sim: Sim = r[0]; var id: int = r[1]
		_set_ke(sim, int(b["window"]["startKe"]) + 1)
		_goto_herald(sim, id)
		var h := _herald(sim)
		var bx := int(h["x"]); var by := int(h["y"])
		sim.cmd_battle_enter(id)
		check(sim.ent(id).has("battle"), "%s 喺窗口時報名成功" % bid)
		var fc: int = RulesBattle.floor_count(b)
		for fi in fc:
			var boss := _cur_boss(sim, bid)
			check(not boss.is_empty(), "%s 第 %d 層 boss 存在" % [bid, fi + 1])
			check(int(boss["mob"]["battle_floor"]) == fi, "%s boss battle_floor 啱 (%d)" % [bid, fi])
			sim._kill_mob(boss, sim.ent(id))
		check(not sim.ent(id).has("battle"), "%s 打完 %d 層自動離場" % [bid, fc])
		check(int(sim.ent(id)["x"]) == bx and int(sim.ent(id)["y"]) == by, "%s 完場傳返義勇士兵原位" % bid)
		check(_cur_boss(sim, bid).is_empty(), "%s 完場冇殘留 boss" % bid)
		var bag: Array = sim.player_ch()["bag"]
		var got := {}
		for it2 in bag:
			got[int(it2["id"])] = int(it2["n"])
		var want := {}
		for fl in b["floors"]:
			for dd in fl["drops"]:
				want[int(dd[0])] = int(want.get(int(dd[0]), 0)) + 1
		for iid in want.keys():
			check(got.get(int(iid), 0) >= int(want[int(iid)]), "%s 掉寶 item %d 攞齊" % [bid, iid])
		wins += 1
	check(wins == 5, "其餘 5 場戰役全部驗到")


# ---------- sim: 死亡唔跌經驗/物品，傳送返報名點 ----------
func t_death_no_loss(data: GameData) -> void:
	var r := _new(data, 3)
	var sim: Sim = r[0]; var id: int = r[1]; var ch: Dictionary = r[2]
	ch["exp"] = 500
	ch["bag"] = [{"id": 10001, "n": 3}]
	_set_ke(sim, 80)
	_goto_herald(sim, id)
	var h := _herald(sim)
	var bx := int(h["x"]); var by := int(h["y"])
	sim.cmd_battle_enter(id)
	var boss := _cur_boss(sim, "zhangniujiao")
	sim._kill_player(sim.ent(id))
	check(int(sim.player_ch()["exp"]) == 500, "戰役內死亡唔跌經驗")
	var n := 0
	for b in sim.player_ch()["bag"]:
		if int(b["id"]) == 10001:
			n = int(b["n"])
	check(n == 3, "戰役內死亡唔跌物品")
	# 冇復活道具 → 死亡入倒地狀態【自訂新增】，仍留喺戰役入面 (死位)，等回城復活先真正離開
	check(bool(sim.ent(id).get("down", false)) and sim.ent(id).has("battle"), "戰役內死亡: 先倒地，未即刻離開戰役")
	for _i in int(data.world["combat"]["playerDownSelfTicks"]):
		sim.step()
	sim.cmd_self_revive(id)
	check(not sim.ent(id).has("battle"), "回城復活: 自動離開戰役")
	check(int(sim.ent(id)["x"]) == bx and int(sim.ent(id)["y"]) == by, "回城復活: 傳送返義勇士兵原位")
	check(_cur_boss(sim, "zhangniujiao").is_empty(), "回城復活後殘留 boss 清晒")
	check(int(sim.ent(id)["hp"]) > 0, "回城復活: 回半血")


# ---------- sim: 放棄戰役 ----------
func t_leave(data: GameData) -> void:
	var r := _new(data, 4)
	var sim: Sim = r[0]; var id: int = r[1]
	_set_ke(sim, 80)
	_goto_herald(sim, id)
	sim.cmd_battle_enter(id)
	check(sim.ent(id).has("battle"), "報名成功")
	sim.cmd_battle_leave(id)
	check(not sim.ent(id).has("battle"), "放棄成功離場")
	check(_cur_boss(sim, "zhangniujiao").is_empty(), "放棄後殘留 boss 清晒")


# ---------- sim: 武等超標入唔到 ----------
func t_level_gate(data: GameData) -> void:
	var r := _new(data, 5, 25)
	var sim: Sim = r[0]; var id: int = r[1]
	_set_ke(sim, 80)
	_goto_herald(sim, id)
	sim.cmd_battle_enter(id)
	check(not sim.ent(id).has("battle"), "武等 25 超過張牛角上限 20，報名唔到")


# ---------- 存檔 roundtrip (戰役進行中) ----------
func t_roundtrip(data: GameData) -> void:
	var r := _new(data, 6)
	var sim: Sim = r[0]; var id: int = r[1]
	_set_ke(sim, 80)
	_goto_herald(sim, id)
	sim.cmd_battle_enter(id)
	var boss := _cur_boss(sim, "zhangniujiao")
	sim._kill_mob(boss, sim.ent(id))      # 行到第 2 層先存
	var s1 := sim.save_string()
	var sim2 := Sim.load_string(data, s1)
	check(sim2 != null and sim2.save_string() == s1, "save -> load -> save 字串一致")
	check(int(sim2.ent(id)["battle"]["floor"]) == 1, "load 返嚟仲喺第 2 層 (idx1)")


# ---------- 決定性 ----------
func t_determinism(data: GameData) -> void:
	var r1 := _new(data, 7)
	var r2 := _new(data, 7)
	var sim1: Sim = r1[0]; var id1: int = r1[1]
	var sim2: Sim = r2[0]; var id2: int = r2[1]
	_set_ke(sim1, 80); _set_ke(sim2, 80)
	_goto_herald(sim1, id1); _goto_herald(sim2, id2)
	sim1.cmd_battle_enter(id1)
	sim2.cmd_battle_enter(id2)
	for i in 4:
		sim1._kill_mob(_cur_boss(sim1, "zhangniujiao"), sim1.ent(id1))
		sim2._kill_mob(_cur_boss(sim2, "zhangniujiao"), sim2.ent(id2))
	check(sim1.save_string() == sim2.save_string(), "同種子同動作 = 完全一致")


# ---------- 原版地圖 instance + 層小怪 ----------
func t_floor_mobs(data: GameData) -> void:
	var zbq := RulesBattle.find(data.battles, "zhangbaiqi")
	check(RulesBattle.floor_count(zbq) == 5, "張白騎對原版 5 層 (攻略 5+6 併)")
	check(RulesBattle.find(data.battles, "huanglong")["floors"].size() == 5, "黃龍 5 層")
	for b in data.battles:
		for fl in b["floors"]:
			check(String(fl["map"]).begins_with("bt_") and String(data.map_by_id[fl["map"]].get("orig", "")) == String(fl["tpl"]), "%s instance 用原版 template" % String(fl["map"]))
	var r := _new(data, 7)
	var sim: Sim = r[0]; var id: int = r[1]
	_set_ke(sim, 0)
	_goto_herald(sim, id)
	sim.cmd_battle_enter(id)
	var n := 0
	for e in sim.ents.values():
		if e["kind"] == "mob" and String(e["mob"].get("battle_mob", "")) == "chufeiyan":
			n += 1
	check(n == 5, "褚飛燕第 1 層生 5 隻小怪 (%d)" % n)
	var pe := sim.ent(id)
	check(sim.map_id_at(int(pe["x"]), int(pe["y"])) == "bt_chufeiyan_f1", "傳入 instance 第 1 層")
	check(sim.is_free(int(pe["x"]), int(pe["y"])), "入層落喺可行走格")
	var boss := _cur_boss(sim, "chufeiyan")
	sim._kill_mob(boss, pe)
	n = 0
	for e in sim.ents.values():
		if e["kind"] == "mob" and String(e["mob"].get("battle_mob", "")) == "chufeiyan":
			n += 1
	check(String(pe["battle"]["id"]) == "chufeiyan" and int(pe["battle"]["floor"]) == 1, "殺 boss 過第 2 層")
	check(n == 6, "第 2 層換 6 隻小怪，上層清走 (%d)" % n)
	sim.cmd_battle_leave(id)
	n = 0
	for e in sim.ents.values():
		if e["kind"] == "mob" and String(e["mob"].get("battle_mob", "")) == "chufeiyan":
			n += 1
	check(n == 0, "離場清晒小怪")
