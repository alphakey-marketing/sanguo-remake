extends SceneTree
# Step 13 測試 (spec 05 §3/§7, spec 08 §1): 天地商行自動化 (自動存/賣材料、自動買賣工具、小屋休息) + 捐贈官令 + 行動力
# 跑: Godot --headless --path client --script tests/run_tiandi.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_rules(data)
	t_settings(data)
	t_haul(data)
	t_haul_storage_full(data)
	t_haul_off(data)
	t_tools(data)
	t_rest(data)
	t_donate_gold(data)
	t_donate_items(data)
	t_ap_daily(data)
	t_save_roundtrip(data)
	t_determinism(data)
	print("[TEST] tiandi scenarios: %d, fail %d" % [total, fails])
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


func _new(data: GameData, seed: int = 13) -> Array:
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


func _work_n(sim: Sim, pid: int, ch: Dictionary, skill: String, n: int) -> void:
	for i in n:
		ch["sp"] = 999999
		sim.cmd_work(pid, skill)


func t_data(data: GameData) -> void:
	check(data.donation_rates.size() == 66, "捐獻表: 6 類 × 11 = 66 項 (got %d)" % data.donation_rates.size())
	check(int(data.donation_rates.get(25064, 0)) == 1 and int(data.donation_rates.get(25074, 0)) == 100, "農產: 蕃薯 1、仙桃 100【原】")
	check(int(data.donation_rates.get(25008, 0)) == 7 and int(data.donation_rates.get(25011, 0)) == 100, "礦: 龍骨化石 7、彩虹鑽石 100【原】")
	check(int(data.donation_rates.get(25040, 0)) == 10 and int(data.donation_rates.get(25060, 0)) == 7, "鯊魚 10、千年神杉 7【原】")
	check(int(data.donation_rates.get(25049, 0)) == 7 and int(data.donation_rates.get(25022, 0)) == 100, "冬虫夏草 7、千年蛇膽 100【原】")
	var names_ok := true
	for cat in data.donation["table"]:
		for row in data.donation["table"][cat]:
			if String(data.names.get(int(row["id"]), "")) != String(row["name"]):
				names_ok = false
	check(names_ok, "捐獻表 id ↔ 名同 items.json 一致")
	check(String(data.mat_skill.get(25001, "")) == "mining" and String(data.mat_skill.get(25064, "")) == "farming", "mat_skill: 石頭 = 採礦、蕃薯 = 農耕")
	var n_don := 0
	for k in data.facilities:
		if data.facilities[k] is Dictionary and bool(data.facilities[k].get("donation", false)):
			n_don += 1
	check(n_don == 3, "捐獻處: 許昌 + 新野 + 陳留")


func t_rules(_data: GameData) -> void:
	var ms := {1: "mining", 2: "farming", 3: "mining"}
	var bag := [{"id": 1, "n": 60}, {"id": 99, "n": 5}, {"id": 2, "n": 30}, {"id": 3, "n": 20}]
	check(RulesTiandi.mat_load(bag, ms) == 110, "mat_load 只計材料")
	var p := RulesTiandi.plan_haul(bag, ms, ["mining"], 950, 1000)
	check(str(p["deposit"]) == str([[1, 50]]) and str(p["sell"]) == str([[1, 10], [2, 30], [3, 20]]),
		"plan_haul: 勾咗嘅入倉到滿、其餘賣 (%s)" % str(p))
	var p2 := RulesTiandi.plan_haul(bag, ms, [], 0, 1000)
	check((p2["deposit"] as Array).is_empty() and (p2["sell"] as Array).size() == 3, "plan_haul: 冇勾 = 全賣")
	check(RulesTiandi.tool_resale(100, 2, 200) == 0 and RulesTiandi.tool_resale(300, 100, 200) == 75, "工具轉賣價 = 原價×耐久%/2")
	var cfg := {"goldMin": 3000, "goldMax": 50000, "goldPerFame": 1000, "unitsPerFame": 200, "chaExpPerPoint": 100, "chaCap": 99}
	check(not RulesTiandi.gold_ok(2999, cfg) and RulesTiandi.gold_ok(3000, cfg) and RulesTiandi.gold_ok(50000, cfg) and not RulesTiandi.gold_ok(50001, cfg), "捐金錢範圍 3000~50000")
	check(RulesTiandi.donation_fame("gold", 3500, cfg) == 3 and RulesTiandi.donation_fame("units", 399, cfg) == 1, "名聲換算")
	check(RulesTiandi.donation_units({25064: 50, 25074: 2, 1: 999}, {25064: 1, 25074: 100}) == 250, "物資單位: 表外 = 0")
	var r := RulesTiandi.cha_gain(10, 50, 260, cfg)
	check(int(r["cha"]) == 13 and int(r["exp"]) == 10 and int(r["ups"]) == 3, "魅力經驗: 50+260 → +3 剩 10")
	var r2 := RulesTiandi.cha_gain(98, 0, 500, cfg)
	check(int(r2["cha"]) == 99 and int(r2["exp"]) == 0 and int(r2["ups"]) == 1, "魅力到 99 封頂，exp 歸 0")


func t_settings(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	check(ch["tiandi"]["deposit"].is_empty() and not bool(ch["tiandi"]["buyTool"]), "新角色: 天地商行設定全關")
	sim.cmd_tiandi_set(pid, "deposit:mining", true)
	sim.cmd_tiandi_set(pid, "deposit:mining", true)
	sim.cmd_tiandi_set(pid, "deposit:herbalism", true)
	sim.cmd_tiandi_set(pid, "deposit:bogus", true)
	check(str(ch["tiandi"]["deposit"]) == str(["mining", "herbalism"]), "勾存材料: 唔重複、唔收假技能")
	sim.cmd_tiandi_set(pid, "deposit:mining", false)
	sim.cmd_tiandi_set(pid, "buyTool", true)
	check(str(ch["tiandi"]["deposit"]) == str(["herbalism"]) and bool(ch["tiandi"]["buyTool"]), "取消勾 + 開自動買工具")
	ch.erase("tiandi")
	check(sim.tiandi_cfg(ch)["deposit"].is_empty(), "舊存檔冇 tiandi → 補預設")


func t_haul(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_put(sim, pid, 60, 35)          # 東山丘林 = 採礦工作區 (spec 05)
	ch["storageSub"] = true
	sim.cmd_tiandi_set(pid, "deposit:mining", true)
	RulesShop.add_item(ch["bag"], 25001, 60)        # 石頭 (採礦)
	RulesShop.add_item(ch["bag"], 25073, 40)        # 小麥 (農耕，冇勾；價 200)
	RulesShop.add_item(ch["bag"], 10001, 1)         # 武器唔係材料
	var w0 := RulesShop.count_item(ch["bag"], 10001)
	_equip_tool(sim, pid, ch, "mining", 26003)
	var gold0 := int(ch["gold"])
	var hauled := [0]
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "tiandi_haul":
			hauled[0] += 1)
	# 工作 1 次 → 材料 > 100 件 (成功) → 腳伕出動；失手就再做
	var tries := 0
	while hauled[0] == 0 and tries < 10:
		_work_n(sim, pid, ch, "mining", 1)
		tries += 1
	check(hauled[0] == 1, "負重滿 (材料 > 100) → 腳伕出動")
	check(RulesTiandi.mat_load(ch["bag"], data.mat_skill) == 0, "背包材料搬清")
	check(RulesShop.count_item(ch["bag"], 10001) == w0, "非材料 (武器) 唔郁")
	check(RulesShop.count_item(ch["storage"], 25001) >= 61, "勾咗採礦 → 石頭入倉 (%d)" % RulesShop.count_item(ch["storage"], 25001))
	check(RulesShop.count_item(ch["storage"], 25073) == 0, "冇勾農耕 → 小麥唔入倉")
	check(int(ch["gold"]) > gold0, "小麥賣咗錢 (%d → %d)" % [gold0, int(ch["gold"])])
	check(_last(msgs).begins_with("天地商行腳伕"), "有腳伕訊息")
	# 未滿唔郁
	RulesShop.add_item(ch["bag"], 25064, 10)
	_work_n(sim, pid, ch, "mining", 1)
	check(hauled[0] == 1 and RulesShop.count_item(ch["bag"], 25064) == 10, "未滿 100 件唔會搬")


func t_haul_storage_full(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_put(sim, pid, 60, 35)          # 採礦工作區
	ch["storageSub"] = true
	sim.cmd_tiandi_set(pid, "deposit:mining", true)
	RulesShop.add_item(ch["storage"], 10001, 995)   # 倉庫剩 5 格
	RulesShop.add_item(ch["bag"], 25005, 120)       # 金礦石 (採礦，價 10)
	_equip_tool(sim, pid, ch, "mining", 26003)
	var gold0 := int(ch["gold"])
	_work_n(sim, pid, ch, "mining", 1)
	check(RulesTiandi.stack_total(ch["storage"]) == 1000, "倉滿: 只入到 5 件 (總數 %d)" % RulesTiandi.stack_total(ch["storage"]))
	check(RulesShop.count_item(ch["bag"], 25005) == 0 and int(ch["gold"]) > gold0, "倉滿: 入唔落嘅賣市集")
	# 手動存都擋
	RulesShop.add_item(ch["bag"], 25001, 1)
	sim.cmd_storage_deposit(pid, 25001, 1)
	check(RulesShop.count_item(ch["bag"], 25001) == 1 and _last(msgs).begins_with("倉庫滿咗"), "倉滿: 手動存都擋")


func t_haul_off(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put(sim, pid, 60, 35)          # 採礦工作區
	sim.cmd_tiandi_set(pid, "deposit:mining", true)
	RulesShop.add_item(ch["bag"], 25001, 150)
	_equip_tool(sim, pid, ch, "mining", 26003)
	_work_n(sim, pid, ch, "mining", 2)
	check(RulesShop.count_item(ch["bag"], 25001) >= 150 and ch["storage"].is_empty(), "未訂閱: 腳伕唔做嘢")
	# 任務道具唔郁 (新野客棧掌櫃要仙楂)
	ch["storageSub"] = true
	# 開返訂閱 → 搬材料，但任務道具唔郁
	var qitem := 0
	for k in data.cats:
		if RulesQuest.is_quest_item(data, int(k)):
			qitem = int(k)
			break
	RulesShop.add_item(ch["bag"], qitem, 5)
	_work_n(sim, pid, ch, "mining", 1)
	check(qitem > 0 and RulesShop.count_item(ch["bag"], qitem) == 5 and RulesShop.count_item(ch["bag"], 25001) == 0,
		"訂閱後搬材料、任務道具唔郁")


func t_tools(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put(sim, pid, 60, 35)          # 採礦工作區
	ch["storageSub"] = true
	ch["gold"] = 100000
	# 自動買: 耐久 1 → 用完爛 → 買返新
	_equip_tool(sim, pid, ch, "mining", 26003)
	ch["tools"]["mining"]["dur"] = 1
	sim.cmd_tiandi_set(pid, "buyTool", true)
	var g0 := int(ch["gold"])
	_work_n(sim, pid, ch, "mining", 1)
	var t: Dictionary = ch["tools"].get("mining", {})
	check(not t.is_empty() and int(t["item"]) == 26003 and int(t["dur"]) == 200, "自動買: 爛咗即買返新 (耐久 200)")
	var price := RulesShop.buy_price(data.prices.get(26003, 0.0) * sim.market_factor(26003), ch["attrs"]["cha"], int(ch["karma"]))
	check(g0 - int(ch["gold"]) == price, "自動買: 扣商店價 %d" % price)
	# 新手工具買返新手工具 (耐久 50)
	ch["tools"].erase("farming")
	_equip_tool(sim, pid, ch, "farming", 26031)
	ch["tools"]["farming"]["dur"] = 1
	_put(sim, pid, 70, 15)          # 許下屯田 = 農耕工作區
	_work_n(sim, pid, ch, "farming", 1)
	check(int(ch["tools"]["farming"]["item"]) == 26031 and int(ch["tools"]["farming"]["dur"]) == 50, "自動買: 新手工具 → 新手工具")
	# 自動賣: 耐久剩 2 → 賣
	sim.cmd_tiandi_set(pid, "buyTool", false)
	sim.cmd_tiandi_set(pid, "sellTool", true)
	_put(sim, pid, 60, 35)          # 返採礦工作區 (下面自動賣都係採礦)
	ch["tools"]["mining"]["dur"] = 3
	g0 = int(ch["gold"])
	_work_n(sim, pid, ch, "mining", 1)
	check(not ch["tools"].has("mining"), "自動賣: 耐久剩 2 → 賣走 (手上冇工具)")
	check(int(ch["gold"]) - g0 == RulesTiandi.tool_resale(int(data.prices.get(26003, 0.0)), 2, 200), "自動賣: 得轉賣價")
	# 買 + 賣都開: 賣完即買新
	sim.cmd_tiandi_set(pid, "buyTool", true)
	_equip_tool(sim, pid, ch, "mining", 26003)
	ch["tools"]["mining"]["dur"] = 3
	_work_n(sim, pid, ch, "mining", 1)
	check(int(ch["tools"].get("mining", {}).get("dur", 0)) == 200, "買賣都開: 剩 2 賣走 + 買新")
	# 唔夠錢
	ch["gold"] = 0
	ch["tools"]["mining"]["dur"] = 3
	_work_n(sim, pid, ch, "mining", 1)
	check(not ch["tools"].has("mining") and int(ch["gold"]) >= 0, "唔夠錢: 賣咗但買唔到")
	# 未訂閱唔郁
	ch["storageSub"] = false
	ch["gold"] = 100000
	_equip_tool(sim, pid, ch, "mining", 26003)
	ch["tools"]["mining"]["dur"] = 1
	_work_n(sim, pid, ch, "mining", 1)
	check(not ch["tools"].has("mining") and int(ch["gold"]) == 100000, "未訂閱: 爛咗就冇 (唔自動買)")


func t_rest(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	ch["gold"] = 100
	ch["sp"] = 1
	_put(sim, pid, 30, 30)
	sim.cmd_storage_rest(pid)
	check(int(ch["sp"]) == 1 and int(ch["gold"]) == 100, "小屋: 未訂閱唔得")
	ch["storageSub"] = true
	sim.cmd_storage_rest(pid)
	var cost := int(data.world["tiandi"]["restCost"])
	check(int(ch["sp"]) == sim._eff_max_sp(ch) and int(ch["gold"]) == 100 - cost, "小屋: 城外回滿 + 扣 %d 金" % cost)
	_put_fac(sim, pid, data, "temple")
	ch["sp"] = 1
	sim.cmd_storage_rest(pid)
	check(int(ch["sp"]) == 1 and _last(msgs).begins_with("小屋喺城外"), "小屋: 城內唔得")
	_put(sim, pid, 30, 30)
	ch["gold"] = cost - 1
	sim.cmd_storage_rest(pid)
	check(int(ch["sp"]) == 1, "小屋: 唔夠錢唔得")


func t_donate_gold(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	ch["gold"] = 200000
	ch["attrs"]["cha"] = 10
	_put(sim, pid, 30, 30)
	sim.cmd_donate_gold(pid, 3000)
	check(int(ch["gold"]) == 200000 and _last(msgs).begins_with("要去官府"), "捐金: 要喺捐獻處")
	_put_fac(sim, pid, data, "donate_xc")
	sim.cmd_donate_gold(pid, 2999)
	sim.cmd_donate_gold(pid, 50001)
	check(int(ch["gold"]) == 200000, "捐金: 3000~50000 以外唔收")
	sim.cmd_donate_gold(pid, 3000)
	check(int(ch["gold"]) == 197000 and int(ch.get("fame", 0)) == 3, "捐 3000 → 名聲 +3")
	check(int(ch["ap"]) == 90 and int(ch["chaExp"]) == 30, "扣 10 行動力 + 30 魅力經驗")
	sim.cmd_donate_gold(pid, 50000)
	check(int(ch["fame"]) == 53 and int(ch["attrs"]["cha"]) == 15 and int(ch["chaExp"]) == 30, "捐 50000 → 名聲 +50、魅力 +5 (cha %d exp %d)" % [int(ch["attrs"]["cha"]), int(ch["chaExp"])])
	ch["gold"] = 1000
	sim.cmd_donate_gold(pid, 3000)
	check(int(ch["fame"]) == 53 and _last(msgs) == "金錢不足", "捐金: 唔夠錢")
	ch["gold"] = 100000
	ch["ap"] = 9
	sim.cmd_donate_gold(pid, 3000)
	check(int(ch["fame"]) == 53 and _last(msgs).begins_with("行動力不足"), "捐金: 行動力唔夠")
	# 新野捐獻處都得【原=任何城池】
	ch["ap"] = 100
	_put_fac(sim, pid, data, "donate_xy")
	sim.cmd_donate_gold(pid, 10000)
	check(int(ch["fame"]) == 63, "新野捐獻處都捐得")


func t_donate_items(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_put_fac(sim, pid, data, "donate_xc")
	RulesShop.add_item(ch["bag"], 25064, 99)       # 蕃薯 ×99 = 99 單位
	sim.cmd_donate_items(pid, [[25064, 99]])
	check(RulesShop.count_item(ch["bag"], 25064) == 99 and _last(msgs).begins_with("物資要 100"), "捐物資: 99 單位唔夠")
	sim.cmd_donate_items(pid, [[25064, 200]])
	check(RulesShop.count_item(ch["bag"], 25064) == 99 and _last(msgs).begins_with("背包冇咁多"), "捐物資: 背包唔夠")
	RulesShop.add_item(ch["bag"], 25074, 3)        # 仙桃 ×3 = 300
	RulesShop.add_item(ch["bag"], 10001, 1)        # 表外
	var w0 := RulesShop.count_item(ch["bag"], 10001)
	check(str(sim.donatable_items(ch)) == str([[25064, 99], [25074, 3]]), "donatable_items: 只列表內物資")
	sim.cmd_donate_items(pid, [[25064, 99], [25074, 3], [10001, 1]])
	check(RulesShop.count_item(ch["bag"], 25064) == 0 and RulesShop.count_item(ch["bag"], 25074) == 0, "捐物資: 扣晒")
	check(RulesShop.count_item(ch["bag"], 10001) == w0, "捐物資: 表外物品唔收")
	check(int(ch.get("fame", 0)) == 1 and int(ch["ap"]) == 90, "399 單位 → 名聲 +1、扣行動力")


func t_ap_daily(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	check(int(ch["ap"]) == 100 and sim.ap_max(ch) == 100, "新角色行動力 100")
	ch["ap"] = 5
	sim._daily_hook(1)
	check(int(ch["ap"]) == 100, "子時行動力回滿")
	ch.erase("ap")
	check(sim.ap_of(ch) == 100, "舊存檔冇 ap → 當滿")


func t_save_roundtrip(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	sim.cmd_tiandi_set(pid, "deposit:fishing", true)
	sim.cmd_tiandi_set(pid, "sellTool", true)
	ch["ap"] = 42
	ch["chaExp"] = 17
	ch["fame"] = 8
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	var lch := loaded.player_ch()
	check(str(lch["tiandi"]["deposit"]) == str(["fishing"]) and bool(lch["tiandi"]["sellTool"]), "存檔: 天地商行設定保留")
	check(int(lch["ap"]) == 42 and int(lch["chaExp"]) == 17 and int(lch["fame"]) == 8, "存檔: 行動力/魅力經驗/名聲保留")
	check(loaded.save_string() == s1, "存檔: save→load→save 一致")
	# 舊存檔
	var d: Dictionary = JSON.parse_string(s1)
	for e in d["state"]["ents"].values():
		if e.has("ch"):
			e["ch"].erase("tiandi")
			e["ch"].erase("ap")
			e["ch"].erase("chaExp")
	var old := Sim.load_string(data, JSON.stringify(d))
	var och := old.player_ch()
	old.cmd_tiandi_set(pid, "buyTool", true)
	check(old.ap_of(och) == 100 and old.tiandi_cfg(och).has("deposit"), "舊存檔: 補行動力 + 設定")


func _run_seq(data: GameData) -> String:
	var r := _new(data, 77)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put(sim, pid, 60, 35)          # 採礦工作區
	ch["storageSub"] = true
	ch["gold"] = 50000
	sim.cmd_tiandi_set(pid, "deposit:mining", true)
	sim.cmd_tiandi_set(pid, "buyTool", true)
	sim.cmd_tiandi_set(pid, "sellTool", true)
	RulesShop.add_item(ch["bag"], 25064, 90)
	_equip_tool(sim, pid, ch, "mining", 26003)
	ch["tools"]["mining"]["dur"] = 20
	_work_n(sim, pid, ch, "mining", 40)
	return JSON.stringify([ch["bag"], ch["storage"], ch["tools"], ch["gold"], ch["workLv"]])


func t_determinism(data: GameData) -> void:
	check(_run_seq(data) == _run_seq(data), "決定性: 同種子同結果")
