extends SceneTree
# Step 12 測試 (spec 05 §2/§4): 配方導入 / 工作技能等級 / 進階解鎖 / 製作 / 武器耐久 / 自己修理 / 修理服務 / 工具店 / 存檔 / 決定性
# 跑: Godot --headless --path client --script tests/run_craft.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_work_levels(data)
	t_unlock(data)
	t_craft(data)
	t_craft_food(data)
	t_weapon_dur(data)
	t_repair_self(data)
	t_repair_service(data)
	t_tool_shop(data)
	t_save_roundtrip(data)
	t_determinism(data)
	print("[TEST] craft scenarios: %d, fail %d" % [total, fails])
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


func _put_fac(sim: Sim, id: int, data: GameData, key: String) -> void:
	var f: Dictionary = data.facilities[key]
	_put(sim, id, int(f["x"]), int(f["y"]) + 1)


func _new(data: GameData, seed: int = 11) -> Array:
	var sim := Sim.new(data, seed)
	var pid := sim.spawn_player("t", "yishi")
	var ch := sim.player_ch()
	ch["level"] = 20
	var msgs: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "msg":
			msgs.append(String(ev["text"])))
	return [sim, pid, ch, msgs]


func _last(msgs: Array) -> String:
	return String(msgs[-1]) if not msgs.is_empty() else ""


func _equip_tool(sim: Sim, pid: int, ch: Dictionary, skill: String, item: int) -> void:
	RulesShop.add_item(ch["bag"], item, 1)
	sim.cmd_equip_tool(pid, skill, item)


func t_data(data: GameData) -> void:
	check(data.recipes.size() == 2318, "配方: 2318 個 (got %d)" % data.recipes.size())
	var r: Dictionary = data.recipes.get(10001, {})
	check(String(r.get("skill", "")) == "smithing" and int(r["lv"]) == 1 and int(r["need"][0][0]) == 25001 and int(r["need"][0][1]) == 5,
		"配方: 柳葉刀 = 冶鐵 Lv1 石頭×5【原】")
	check(String(data.recipes[29021]["skill"]) == "cooking" and String(data.recipes[28019]["skill"]) == "alchemy", "配方: 宮保雞丁 = 廚藝、狗皮膏藥 = 煉丹")
	check(String(data.recipes[12105]["skill"]) == "carpentry", "配方: 穿心箭 = 木匠")
	var sizes := {}
	for sk in data.recipes_by_skill:
		sizes[sk] = (data.recipes_by_skill[sk] as Array).size()
	check(sizes == {"cooking": 29, "alchemy": 25, "carpentry": 637, "smithing": 629, "mending": 998}, "配方: 各技能數量 %s" % [sizes])
	var sorted_ok := true
	for sk in data.recipes_by_skill:
		var prev := 0
		for rr in data.recipes_by_skill[sk]:
			if int(rr["lv"]) < prev:
				sorted_ok = false
			prev = int(rr["lv"])
	check(sorted_ok, "配方: 按等級排")
	check(String(data.tool_skill.get(26005, "")) == "cooking" and String(data.tool_skill.get(26033, "")) == "mining"
		and String(data.tool_skill.get(26004, "")) == "smithing", "工具對照: 鍋子→廚藝、新手十字鎬→採礦、鐵鎚→冶鐵")
	var bad := 0
	for id in data.recipes:
		for m in data.recipes[id]["need"]:
			if not data.item_ids.has(int(m[0])):
				bad += 1
	check(bad == 0, "配方: 材料全部喺 items.json")
	check(int(data.weapons[10001]["max_dur"]) == 55, "武器耐久上限: 柳葉刀 Lv1 = 55")
	for k in ["kitchen", "pharmacy", "workshop", "smithy_xy"]:
		var f: Dictionary = data.facilities[k]
		check(data.walk[int(f["y"]) * GameData.WORLD_W + int(f["x"])] == 1, "設施 %s 企得落" % k)


func t_work_levels(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	check(sim.work_lv(ch, "mining") == 1 and sim.work_lv(ch, "smithing") == 0, "新角色: 初階 1 級、進階 0 (未解鎖)")
	_put(sim, pid, 30, 30)
	_equip_tool(sim, pid, ch, "mining", 26003)
	var tier0 := int(data.work["mining"]["materials"][0])
	var only_tier0 := true
	var oks := 0
	var got := [false, 0]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "work":
			got[0] = bool(ev["ok"])
			got[1] = int(ev["item"]))
	for i in 40:
		ch["sp"] = 999999
		var lv_before := sim.work_lv(ch, "mining")
		sim.cmd_work(pid, "mining")
		if got[0]:
			oks += 1
			if lv_before < 3 and int(got[1]) != tier0:
				only_tier0 = false
	check(only_tier0, "技能 Lv1~2: 只出第 1 級礦 (tier 按技能等級)")
	check(oks >= 30 and oks < 40 + 1, "初階成功率 ~85%% (40 次成功 %d)" % oks)
	var w: Dictionary = ch["workLv"]["mining"]
	var total_exp := 0
	for lv in range(1, int(w["lv"])):
		total_exp += RulesWork.exp_to_next(lv, data.work_meta["level"])
	total_exp += int(w["exp"])
	check(total_exp == oks * 2 + (40 - oks) * 1, "經驗: 成功 +2 失敗 +1 (total %d)" % total_exp)
	check(int(w["lv"]) > 1, "採礦升咗級 (Lv%d)" % int(w["lv"]))
	# 等級夠 → 高 tier 出現
	ch["workLv"]["mining"] = {"lv": 45, "exp": 0}
	var hi := false
	for i in 60:
		ch["sp"] = 999999
		if not ch["tools"].has("mining"):
			_equip_tool(sim, pid, ch, "mining", 26003)
		sim.cmd_work(pid, "mining")
	for m in (data.work["mining"]["materials"] as Array).slice(3):
		if RulesShop.count_item(ch["bag"], int(m)) > 0:
			hi = true
	check(hi, "採礦 45 級: 出到高 tier 礦")


func t_unlock(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_put_fac(sim, pid, data, "workshop")
	RulesShop.add_item(ch["bag"], 25001, 5)
	sim.cmd_craft(pid, 10001)
	check(_last(msgs).contains("未解鎖"), "未夠 50 級: 冶鐵未解鎖 (%s)" % _last(msgs))
	check(not sim.adv_unlocked(ch, "smithing"), "採礦 1 級: 冶鐵未解鎖")
	sim.cmd_debug_work_lv(pid, 48)
	check(sim.work_lv(ch, "mining") == 49 and not sim.adv_unlocked(ch, "smithing"), "debug +48 → 採礦 49，未解鎖")
	sim.cmd_debug_work_lv(pid, 1)
	check(sim.adv_unlocked(ch, "smithing") and sim.adv_unlocked(ch, "mending"), "採礦 50: 冶鐵 + 修繕解鎖【原】")
	check(sim.work_lv(ch, "smithing") == 1 and sim.work_lv(ch, "mending") == 1, "解鎖即 1 級")
	check(sim.adv_unlocked(ch, "cooking"), "農耕/釣魚/狩獵任一 50 → 廚藝解鎖")
	var r2 := _new(data)
	var ch2: Dictionary = r2[2]
	ch2["workLv"] = {"fishing": {"lv": 50, "exp": 0}}
	check((r2[0] as Sim).adv_unlocked(ch2, "cooking") and not (r2[0] as Sim).adv_unlocked(ch2, "alchemy"), "淨係釣魚 50: 廚藝開、煉丹未開")
	# 自然升級都會解鎖
	var r3 := _new(data)
	var sim3: Sim = r3[0]
	var ch3: Dictionary = r3[2]
	ch3["workLv"] = {"herbalism": {"lv": 49, "exp": RulesWork.exp_to_next(49, data.work_meta["level"]) - 1}}
	_put(sim3, r3[1], 30, 30)
	_equip_tool(sim3, r3[1], ch3, "herbalism", 26008)
	sim3.cmd_work(r3[1], "herbalism")
	check(sim3.work_lv(ch3, "herbalism") == 50 and sim3.work_lv(ch3, "alchemy") == 1, "採藥做到 50 級 → 煉丹自動解鎖")


func t_craft(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	sim.cmd_debug_work_lv(pid, 49)
	_put(sim, pid, 30, 30)
	RulesShop.add_item(ch["bag"], 25001, 500)
	sim.cmd_craft(pid, 10001)
	check(_last(msgs).contains("工房"), "唔喺工房: 做唔到 (%s)" % _last(msgs))
	_put_fac(sim, pid, data, "kitchen")
	sim.cmd_craft(pid, 10001)
	check(_last(msgs).contains("工房"), "喺廚房: 冶鐵都做唔到")
	_put_fac(sim, pid, data, "workshop")
	sim.cmd_craft(pid, 10001)
	check(_last(msgs).contains("鐵鎚"), "冇工具: 要裝備鐵鎚 (%s)" % _last(msgs))
	_equip_tool(sim, pid, ch, "smithing", 26004)
	check(int(ch["tools"]["smithing"]["dur"]) == 200, "鐵鎚耐久 200")
	sim.cmd_craft(pid, 10003)
	check(_last(msgs).contains("25 級"), "配方等級唔夠: 要 25 級 (%s)" % _last(msgs))
	var w0 := RulesShop.count_item(ch["bag"], 10001)
	var ok_n := 0
	var lost_n := 0
	var n := 60
	var sp_ok := true
	for i in n:
		ch["sp"] = 999999
		var got := [false, false]
		var cb := func(ev: Dictionary) -> void:
			if String(ev.get("k", "")) == "craft":
				got[0] = bool(ev["ok"])
				got[1] = bool(ev["lost"])
		sim.event_emitted.connect(cb)
		sim.cmd_craft(pid, 10001)
		sim.event_emitted.disconnect(cb)
		if got[0]:
			ok_n += 1
		if got[1]:
			lost_n += 1
		if int(ch["sp"]) >= 999999:
			sp_ok = false
	var p := RulesWork.craft_chance(1, 1, data.work_meta["craftRate"])
	check(RulesShop.count_item(ch["bag"], 10001) - w0 == ok_n, "製作: 成品數 = 成功次數 (%d)" % ok_n)
	check(ok_n > n * (p - 0.2) and ok_n < n * (p + 0.2) + 5, "製作成功率 ≈ %.2f (%d/%d)" % [p, ok_n, n])
	check(RulesShop.count_item(ch["bag"], 25001) == 500 - 5 * lost_n, "材料: 成功全扣、失敗有時扣 (扣 %d 次)" % lost_n)
	check(lost_n > ok_n and lost_n < n, "失敗唔一定扣材料")
	check(sp_ok, "製作扣 SP")
	check(int(ch["tools"]["smithing"]["dur"]) == 200 - n, "每次製作工具耐久 -1")
	check(sim.work_lv(ch, "smithing") > 1, "冶鐵升級 (Lv%d)" % sim.work_lv(ch, "smithing"))
	# 材料唔夠
	ch["bag"] = ch["bag"].filter(func(b): return int(b["id"]) != 25001)
	sim.cmd_craft(pid, 10001)
	check(_last(msgs) == "材料唔夠", "材料唔夠: 做唔到")


func t_craft_food(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	ch["workLv"] = {"hunting": {"lv": 50, "exp": 0}, "cooking": {"lv": 30, "exp": 0}}
	_put_fac(sim, pid, data, "kitchen")
	_equip_tool(sim, pid, ch, "cooking", 26005)
	RulesShop.add_item(ch["bag"], 25012, 8 * 20)
	var made := 0
	for i in 20:
		ch["sp"] = 999999
		sim.cmd_craft(pid, 29021)
		made = RulesShop.count_item(ch["bag"], 29021)
		if made > 0:
			break
	check(made > 0, "廚藝: 整到宮保雞丁")
	ch["hp"] = 1
	sim.ent(pid)["hp"] = 1
	sim.cmd_use_item(pid, 29021)
	check(int(ch["hp"]) == 51, "宮保雞丁食咗回 50 HP")


func t_weapon_dur(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var eq: Dictionary = ch["equip"]
	check(int(eq["dur"].get("10001", -1)) == 55, "開場武器有耐久 55")
	var p0 := float(sim._weapon_def(ch)["power"])
	eq["dur"]["10001"] = 0
	check(absf(float(sim._weapon_def(ch)["power"]) - p0 * 0.5) < 1e-9, "武器耐久 0: 威力減半")
	eq["dur"]["10001"] = 55
	for i in 10:
		sim._wear_weapon_hit(sim.ent(pid))
	check(int(eq["dur"]["10001"]) == 54, "打中 10 下: 武器耐久 -1")
	sim._wear_armor_death(ch)
	check(int(eq["dur"]["10001"]) == 54 - 6, "死亡: 武器扣上限 10% (ceil 5.5 = 6)")
	RulesShop.add_item(ch["bag"], 10002, 1)
	ch["level"] = 10
	sim.cmd_equip(pid, 10002, 1)
	check(int(eq["dur"].get("10002", -1)) == int(data.weapons[10002]["max_dur"]), "裝新武器: 開耐久")
	# 實戰: 打怪會磨武器
	var r2 := _new(data, 5)
	var sim2: Sim = r2[0]
	var ch2: Dictionary = r2[2]
	ch2["equip"]["whits"] = 9
	var mob: Dictionary = sim2._spawn_mob(12012, "field_1")
	mob["hp"] = 99999
	mob["max_hp"] = 99999
	_put(sim2, r2[1], int(mob["x"]) + 1, int(mob["y"]))
	sim2.cmd_attack(r2[1], int(mob["id"]))
	for i in 200:
		sim2.step()
		if int(ch2["equip"]["whits"]) >= 10:
			break
	check(int(ch2["equip"]["whits"]) >= 10 and int(ch2["equip"]["dur"]["10001"]) == 54, "實戰: 第 10 下打中武器 -1")


func t_repair_self(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var eq: Dictionary = ch["equip"]
	check(sim.repair_skill(10001) == "smithing" and sim.repair_skill(22001) == "mending" and sim.repair_skill(23057) == "carpentry",
		"修理技能: 武器 = 冶鐵、靴 = 修繕、戒指 = 木匠【原】")
	check(sim.repair_skill(29021) == "", "食物唔修得")
	eq["dur"]["10001"] = 10
	_put_fac(sim, pid, data, "workshop")
	sim.cmd_repair(pid, 10001)
	check(_last(msgs).contains("未解鎖") and int(eq["dur"]["10001"]) == 10, "冶鐵未解鎖: 修唔到")
	ch["workLv"] = {"mining": {"lv": 50, "exp": 0}, "smithing": {"lv": 1, "exp": 0}}
	_equip_tool(sim, pid, ch, "smithing", 26004)
	var sp0 := int(ch["sp"])
	sim.cmd_repair(pid, 10001)
	check(int(eq["dur"]["10001"]) == 55, "自己修: 武器回滿 55")
	check(int(ch["sp"]) < sp0 and int(ch["tools"]["smithing"]["dur"]) == 199, "自己修: 扣 SP + 工具耐久")
	sim.cmd_repair(pid, 10001)
	check(_last(msgs).contains("耐久已滿"), "滿耐久唔使修")
	eq["dur"]["22001"] = 3
	sim.cmd_repair(pid, 22001)
	check(_last(msgs).contains("鉗子"), "修靴要修繕 + 鉗子 (%s)" % _last(msgs))
	_put(sim, pid, 30, 30)
	eq["dur"]["10001"] = 1
	sim.cmd_repair(pid, 10001)
	check(int(eq["dur"]["10001"]) == 1, "唔喺工房唔修得")


func t_repair_service(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var eq: Dictionary = ch["equip"]
	eq["dur"]["10001"] = 30
	var cost := sim.repair_service_cost(ch, 10001)
	check(cost == RulesWork.repair_cost(175.0, 30, 55, 0.3) and cost == 24, "修理費: 175 × 25/55 × 0.3 → 24")
	sim.cmd_repair_service(pid, 10001)
	check(int(eq["dur"]["10001"]) == 30, "唔喺打鐵鋪修唔到")
	_put_fac(sim, pid, data, "forge")
	ch["gold"] = 10
	sim.cmd_repair_service(pid, 10001)
	check(_last(msgs).contains("唔夠錢") and int(eq["dur"]["10001"]) == 30, "唔夠錢修唔到")
	ch["gold"] = 100
	sim.cmd_repair_service(pid, 10001)
	check(int(eq["dur"]["10001"]) == 55 and int(ch["gold"]) == 100 - cost, "許昌打鐵鋪: 收錢修好")
	eq["dur"]["22001"] = 0
	_put_fac(sim, pid, data, "smithy_xy")
	var g0 := int(ch["gold"])
	sim.cmd_repair_service(pid, 22001)
	check(int(eq["dur"]["22001"]) == 50 and int(ch["gold"]) < g0, "新野打鐵鋪: 修靴")


func t_tool_shop(data: GameData) -> void:
	var shop := {}
	for s in data.shops:
		if String(s["id"]) == "tool":
			shop = s
	check(not shop.is_empty(), "許昌有工具店")
	var st: Array = shop.get("stock", [])
	for t in [26031, 26003, 26005, 26012, 26007, 26004, 26010]:
		check(st.has(float(t)) or st.has(t), "工具店有 %d" % t)
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put(sim, pid, int(shop["x"]), int(shop["y"]) + 1)
	ch["gold"] = 5000
	sim.cmd_buy(pid, 26005, 1)
	check(RulesShop.count_item(ch["bag"], 26005) == 1 and int(ch["gold"]) < 5000 and int(ch["gold"]) > 1000, "買到鍋子 (~3000)")


func t_save_roundtrip(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	sim.cmd_debug_work_lv(pid, 49)
	ch["equip"]["dur"]["10001"] = 7
	ch["equip"]["whits"] = 3
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	var lch := loaded.player_ch()
	check(loaded.work_lv(lch, "mining") == 50 and loaded.work_lv(lch, "smithing") == 1, "存檔: 技能等級保留")
	check(int(lch["equip"]["dur"]["10001"]) == 7 and int(lch["equip"]["whits"]) == 3, "存檔: 武器耐久保留")
	check(loaded.save_string() == s1, "存檔: save→load→save 一致")
	# 舊存檔 (冇 workLv / 冇武器耐久)
	var d: Dictionary = JSON.parse_string(s1)
	for e in d["state"]["ents"].values():
		if e.has("ch"):
			e["ch"].erase("workLv")
			e["ch"]["equip"]["dur"].erase("10001")
			e["ch"]["equip"].erase("whits")
	var old := Sim.load_string(data, JSON.stringify(d))
	var och := old.player_ch()
	check(old.work_lv(och, "mining") == 1 and int(och["equip"]["dur"].get("10001", -1)) == 55, "舊存檔: 技能 1 級 + 武器補耐久")


func _run_seq(data: GameData) -> String:
	var r := _new(data, 99)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	sim.cmd_debug_work_lv(pid, 49)
	_put_fac(sim, pid, data, "workshop")
	_equip_tool(sim, pid, ch, "smithing", 26004)
	RulesShop.add_item(ch["bag"], 25001, 100)
	for i in 15:
		ch["sp"] = 999999
		sim.cmd_craft(pid, 10001)
	return JSON.stringify([ch["bag"], ch["workLv"], ch["tools"]])


func t_determinism(data: GameData) -> void:
	check(_run_seq(data) == _run_seq(data), "決定性: 同種子製作結果一樣")
