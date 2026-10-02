extends SceneTree
# Step 14 測試 (spec 08 §1~3, spec 06 §3, spec 01 §9~10): 頭銜 60 階 + 官宅討取/俸祿 + 官令 7 條 + 行動力/行動丹 + 飲水度/喝茶
#   + 登用頭銜條件 + S08a 義舉證明 20 項 + 存檔 roundtrip/舊存檔 + 決定性
#   (城池進貢/好感 → tests/run_militia.gd)
# 跑: Godot --headless --path client --script tests/run_title.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_rules(data)
	t_claim(data)
	t_salary(data)
	t_ap_pill(data)
	t_tool_redeem(data)
	t_order_supply(data)
	t_order_letter(data)
	t_order_census(data)
	t_order_abandon(data)
	t_order_buy(data)
	t_order_recruit(data)
	t_order_escort(data)
	t_order_rescue(data)
	t_merit(data)
	t_merit_turnin(data)
	t_thirst(data)
	t_recruit_title(data)
	t_save_roundtrip(data)
	t_determinism(data)
	print("[TEST] title scenarios: %d, fail %d" % [total, fails])
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


func _new(data: GameData, seed: int = 14) -> Array:
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


func _gen(data: GameData, gname: String) -> Dictionary:
	for g in data.generals_t1:
		if String(g["name"]) == gname:
			return g
	return {}


func t_data(data: GameData) -> void:
	var tt: Array = data.titles
	check(tt.size() == 60, "頭銜 60 階 (got %d)" % tt.size())
	check(String(tt[0]["name"]) == "校尉" and int(tt[0]["fame"]) == 500 and int(tt[0]["ap"]) == 102, "1 階校尉 名聲 500 行動力 102【原】")
	check(String(tt[49]["name"]) == "征東將軍" and int(tt[49]["ap"]) == 200 and int(tt[49]["salary"]) == 5000, "50 階征東將軍 行動力 200 俸祿 5000【原】")
	check(String(tt[59]["name"]) == "大將軍" and int(tt[59]["fame"]) == 60000 and int(tt[59]["ap"]) == 220, "60 階大將軍【原】")
	check(int(tt[40]["salary"]) == 4100 and int(tt[40]["salaryGuide"]) == 4900, "41 階俸祿筆誤修正 4900 → 4100")
	check(int(tt[4]["salary"]) == 0 and int(tt[5]["salary"]) == 600, "5 階冇俸祿、6 階 600【原】")
	check(data.office["orders"].size() == 7, "官令 7 條 (S06a 加訂製軍備/官員護衛/朝廷求才/流落官員)")
	check(String(data.office["orders"][1]["rankName"]) == "南中郎將", "遞送軍函 = 南中郎將 (6 階) 解鎖")
	var offs := 0
	for k in data.facilities:
		if data.facilities[k] is Dictionary and bool(data.facilities[k].get("office", false)):
			offs += 1
	check(offs == 20, "官宅 20 間")


func t_rules(data: GameData) -> void:
	var tt: Array = data.titles
	check(RulesTitle.fame_rank(tt, 499) == 0 and RulesTitle.fame_rank(tt, 500) == 1 and RulesTitle.fame_rank(tt, 3100) == 6, "fame_rank 邊界")
	check(RulesTitle.fame_rank(tt, 999999) == 60, "fame_rank 封頂 60")
	check(RulesTitle.claim_check(tt, 1, 0, 500, 500) == "", "討取校尉: 名聲/資金啱啱好")
	check(RulesTitle.claim_check(tt, 1, 0, 499, 500).begins_with("名聲不足"), "討取: 名聲不足")
	check(RulesTitle.claim_check(tt, 1, 0, 500, 499).begins_with("資金不足"), "討取: 資金不足")
	check(RulesTitle.claim_check(tt, 1, 1, 500, 500).begins_with("你已經係"), "討取: 唔可以討同階/低階")
	check(RulesTitle.claim_check(tt, 6, 0, 3000, 3000) == "", "討取: 可以跳階")
	check(RulesTitle.claim_check(tt, 61, 0, 99999, 99999) == "冇呢個頭銜", "討取: 61 階唔存在")
	check(RulesTitle.ap_max(tt, 0, 100) == 100 and RulesTitle.ap_max(tt, 6, 100) == 112, "行動力上限: 白身 100、6 階 112")
	check(RulesTitle.name_of(tt, 0) == "白身", "0 階 = 白身")
	check(not RulesTitle.is_month_start(0, 30) and RulesTitle.is_month_start(30, 30) and not RulesTitle.is_month_start(31, 30), "月初: day 30/60…")
	var cfg: Dictionary = data.recruit_cfg
	check(RulesTitle.general_rank(49, cfg) == 0 and RulesTitle.general_rank(60, cfg) == 10 and RulesTitle.general_rank(200, cfg) == 60, "人才頭銜 = 戰等 - 50 (0~60)")
	check(RulesTitle.recruit_ok(49, 0, cfg) and RulesTitle.recruit_ok(55, 0, cfg) and not RulesTitle.recruit_ok(56, 0, cfg), "登用頭銜: 55 白身得、56 唔得")
	var o: Dictionary = data.office["orders"][0]
	check(RulesTitle.order_block(o, 1, 100, 3, {}, 10).begins_with("要裨將軍"), "官令: 頭銜未夠")
	check(RulesTitle.order_block(o, 2, 100, 3, {}, 10) == "", "官令: 得")
	check(RulesTitle.order_block(o, 2, 100, 3, {"orderDay": 3}, 10).begins_with("今日已經"), "官令: 每日 1 次")
	check(RulesTitle.order_block(o, 2, 100, 4, {"orderDay": 3, "order": {"id": "arms"}}, 10).begins_with("手上仲有"), "官令: 手上有未完成")
	check(RulesTitle.order_block(o, 2, 9, 3, {}, 10).begins_with("行動力不足"), "官令: 行動力 < 10")
	var th: Dictionary = data.world["thirst"]
	check(RulesTitle.drink(70, th) == 100 and RulesTitle.drink(20, th) == 70, "喝茶 +50 封頂 100【原】")
	check(RulesTitle.sip(1, th) == 0 and RulesTitle.sip(0, th) == 0, "搭話扣 1，最低 0")


func t_claim(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	ch["fame"] = 3000
	ch["gold"] = 10000
	sim.cmd_claim_title(pid, 6)
	check(int(ch["titleRank"]) == 0 and _last(msgs).begins_with("要去官宅"), "唔喺官宅唔討得")
	_put_fac(sim, pid, data, "donate_xy")
	sim.cmd_claim_title(pid, 7)
	check(int(ch["titleRank"]) == 0 and _last(msgs).begins_with("名聲不足"), "名聲唔夠 7 階")
	sim.cmd_claim_title(pid, 6)
	check(int(ch["titleRank"]) == 6 and int(ch["gold"]) == 7000, "新野縣衙討南中郎將: 扣 3000 資金")
	check(sim.ap_max(ch) == 112, "6 階行動力上限 112")
	sim.cmd_claim_title(pid, 2)
	check(int(ch["titleRank"]) == 6, "唔可以降階")
	ch["fame"] = 4000
	ch["gold"] = 100
	sim.cmd_claim_title(pid, 8)
	check(int(ch["titleRank"]) == 6 and _last(msgs).begins_with("資金不足"), "資金唔夠唔扣名聲")
	check(int(ch["fame"]) == 4000, "討取唔扣名聲 (名聲唔會降)")


func t_salary(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	ch["gold"] = 0
	sim._daily_hook(30)
	check(int(ch["gold"]) == 0, "白身冇俸祿")
	ch["titleRank"] = 5
	sim._daily_hook(60)
	check(int(ch["gold"]) == 0, "5 階俸祿 0【原】")
	ch["titleRank"] = 10
	sim._daily_hook(61)
	check(int(ch["gold"]) == 0, "月中唔派")
	sim._daily_hook(90)
	check(int(ch["gold"]) == 1000, "月初一 10 階 俸祿 1000")
	check(int(ch["ap"]) == 120, "日結行動力回滿到頭銜上限 120")


func t_ap_pill(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var pill := int(data.office["pillItem"])
	RulesShop.add_item(ch["bag"], pill, 1)
	sim.cmd_use_item(pid, pill)
	check(RulesShop.count_item(ch["bag"], pill) == 1 and _last(msgs) == "行動力已經滿", "行動力滿唔食行動丹")
	ch["ap"] = 3
	sim.cmd_use_item(pid, pill)
	check(RulesShop.count_item(ch["bag"], pill) == 0 and int(ch["ap"]) == 100, "行動丹回滿行動力")
	_put_fac(sim, pid, data, "donate_xc")
	ch["contrib"] = 29
	sim.cmd_office_pill(pid)
	check(RulesShop.count_item(ch["bag"], pill) == 0 and _last(msgs).begins_with("官宅貢獻不足"), "貢獻 29 換唔到")
	ch["contrib"] = 35
	sim.cmd_office_pill(pid)
	check(RulesShop.count_item(ch["bag"], pill) == 1 and int(ch["contrib"]) == 5, "30 貢獻換 1 粒行動丹")


# S05b (spec 05 §2/§5): 御賜工具兌換 = 暫代過渡 (真任務等 S06c)，扣官宅貢獻換 1 件入背包
func t_tool_redeem(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var gg := sim.godgiven_tools()
	check(gg.size() == 11, "御賜工具清單 11 件 (6 初階 + 5 進階)")
	var farming_row := {}
	var smithing_row := {}
	for t in gg:
		if String(t["skill"]) == "farming":
			farming_row = t
		elif String(t["skill"]) == "smithing":
			smithing_row = t
	check(int(farming_row["cost"]) == 200, "初階御賜工具貢獻 200")
	check(int(smithing_row["cost"]) == 400, "進階御賜工具貢獻 400")
	var item := int(farming_row["item"])
	sim.cmd_office_redeem_tool(pid, item)
	check(RulesShop.count_item(ch["bag"], item) == 0 and _last(msgs).contains("要去官宅"), "唔喺官宅兌換唔到")
	_put_fac(sim, pid, data, "donate_xc")
	ch["contrib"] = 100
	sim.cmd_office_redeem_tool(pid, item)
	check(RulesShop.count_item(ch["bag"], item) == 0 and _last(msgs).contains("官宅貢獻不足"), "貢獻唔夠兌換唔到")
	ch["contrib"] = 250
	sim.cmd_office_redeem_tool(pid, item)
	check(RulesShop.count_item(ch["bag"], item) == 1 and int(ch["contrib"]) == 50, "貢獻夠: 兌換成功扣 200")
	sim.cmd_office_redeem_tool(pid, 26001)
	check(RulesShop.count_item(ch["bag"], 26001) == 0 and _last(msgs).contains("唔係御賜工具"), "普通鋤頭兌換唔到")
	# 裝上御賜鋤頭: 耐久/成功率加成
	sim.cmd_equip_tool(pid, "farming", item)
	check(int(ch["tools"]["farming"]["dur"]) == int(data.work_meta["tierBonus"]["godgiven"]["dur"]), "御賜鋤頭耐久 = tierBonus 設定")
	check(String(data.tool_tier.get(item, "")) == "godgiven", "御賜鋤頭 tool_tier = godgiven")


func t_order_supply(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_put_fac(sim, pid, data, "donate_xc")
	ch["titleRank"] = 1
	sim.cmd_office_order(pid, "arms")
	check((ch["office"].get("order", {}) as Dictionary).is_empty() and _last(msgs).begins_with("要裨將軍"), "校尉接唔到軍備動員")
	ch["titleRank"] = 2
	ch["ap"] = 104
	sim.cmd_office_order(pid, "arms")
	check(String(ch["office"]["order"]["id"]) == "arms" and int(ch["ap"]) == 94, "接軍備動員: 扣行動力 10")
	sim.cmd_office_order(pid, "arms")
	check(_last(msgs).begins_with("手上仲有"), "手上有官令唔接得第二條")
	# 25001 = 採礦初階材料 (捐獻單位 1)、25053 = 伐木
	var ore := 25001
	var wood := 25053
	var r_ore := int(data.donation_rates[ore])
	var r_wood := int(data.donation_rates[wood])
	RulesShop.add_item(ch["bag"], ore, 30)
	RulesShop.add_item(ch["bag"], 25064, 500)      # 農產唔計
	sim.cmd_office_turnin(pid)
	check(not (ch["office"]["order"] as Dictionary).is_empty() and _last(msgs).begins_with("物資唔夠"), "物資唔夠唔覆得命 (農產唔計)")
	var need_wood := (100 - 30 * r_ore + r_wood - 1) / r_wood
	RulesShop.add_item(ch["bag"], wood, need_wood + 5)
	var fame0 := int(ch.get("fame", 0))
	var o: Dictionary = data.office["orders"][0]
	var before := sim.supply_units(ch, o)
	sim.cmd_office_turnin(pid)
	var used := before - sim.supply_units(ch, o)
	check((ch["office"]["order"] as Dictionary).is_empty(), "軍備動員覆命完成")
	check(int(ch["fame"]) == fame0 + 20 and int(ch["contrib"]) == 10, "獎勵: 名聲 +20、貢獻 +10")
	check(RulesShop.count_item(ch["bag"], 25064) == 500, "農產冇被收")
	check(used >= 100 and used < 100 + maxi(r_ore, r_wood), "只收啱啱夠 100 單位 (最多多一件嘅零頭) (used %d)" % used)
	sim.cmd_office_order(pid, "arms")
	check(_last(msgs).begins_with("今日已經"), "完成咗今日都唔可以再接")
	sim._daily_hook(1)
	sim.state["clock"]["day"] = 1
	sim.cmd_office_order(pid, "arms")
	check(String(ch["office"]["order"]["id"]) == "arms", "第二日可以再接")


func t_order_letter(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var letter := int(data.office["orders"][1]["item"])
	_put_fac(sim, pid, data, "donate_xc")
	ch["titleRank"] = 5
	sim.cmd_office_order(pid, "letter")
	check(_last(msgs).begins_with("要南中郎將"), "5 階接唔到遞送軍函")
	ch["titleRank"] = 6
	sim.cmd_office_order(pid, "letter")
	check(String(ch["office"]["order"].get("to", "")) == "donate_xy" and RulesShop.count_item(ch["bag"], letter) == 1, "許昌接令 → 送新野縣衙，攞軍函")
	check(RulesQuest.is_quest_item(data, letter), "軍函 = 任務道具 (唔賣得/唔捐得)")
	sim.cmd_office_turnin(pid)
	check(_last(msgs).begins_with("軍函要送去新野縣衙"), "喺許昌覆唔到命")
	_put_fac(sim, pid, data, "donate_xy")
	sim.cmd_office_turnin(pid)
	check((ch["office"]["order"] as Dictionary).is_empty() and RulesShop.count_item(ch["bag"], letter) == 0, "新野縣衙交軍函完成")
	check(int(ch["fame"]) == 30 and int(ch["contrib"]) == 15, "獎勵: 名聲 +30、貢獻 +15")


func t_order_census(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	ch["titleRank"] = 15
	ch["attrs"]["pol"] = 10
	ch["polExp"] = 15
	_put_fac(sim, pid, data, "donate_xc")
	sim.cmd_office_order(pid, "census")
	check(String(ch["office"]["order"]["id"]) == "census", "威南將軍接戶口普查")
	# 真實傾偈: 典韋/許褚 (全日喺許昌)
	for nm in ["典韋", "許褚"]:
		var g := _gen(data, nm)
		_put(sim, pid, int(g["x"]), int(g["y"]) + 1)
		sim.cmd_general_talk(pid, int(g["id"]))
	sim.cmd_general_talk(pid, int(_gen(data, "許褚")["id"]))
	check((ch["office"]["order"]["met"] as Array).size() == 2, "同一個人傾兩次只計一次")
	var e := sim.ent(pid)
	var xy: Dictionary = data.facilities["donate_xy"]
	sim._office_on_talk(e, "q:someone_xy", int(xy["x"]), int(xy["y"]))
	check((ch["office"]["order"]["met"] as Array).size() == 2, "新野嘅人唔計 (要喺接令城)")
	var xc: Dictionary = data.facilities["donate_xc"]
	sim._office_on_talk(e, "q:a", int(xc["x"]), int(xc["y"]))
	sim._office_on_talk(e, "q:b", int(xc["x"]), int(xc["y"]))
	_put_fac(sim, pid, data, "donate_xc")
	sim.cmd_office_turnin(pid)
	check(_last(msgs).begins_with("仲未訪問夠"), "4 人未夠")
	sim._office_on_talk(e, "q:c", int(xc["x"]), int(xc["y"]))
	_put_fac(sim, pid, data, "donate_xy")
	sim.cmd_office_turnin(pid)
	check(_last(msgs).begins_with("返許昌官宅覆命"), "要返接令官宅覆命")
	_put_fac(sim, pid, data, "donate_xc")
	sim.cmd_office_turnin(pid)
	check((ch["office"]["order"] as Dictionary).is_empty() and int(ch["fame"]) == 30, "戶口普查完成: 名聲 +30")
	check(int(ch["attrs"]["pol"]) == 11 and int(ch["polExp"]) == 5, "政治經驗 15+10 = 25 → 政治 +1 餘 5")


func t_order_abandon(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var letter := int(data.office["orders"][1]["item"])
	ch["titleRank"] = 6
	_put_fac(sim, pid, data, "donate_xy")
	sim.cmd_office_order(pid, "letter")
	check(String(ch["office"]["order"]["to"]) == "donate_xc", "新野接令 → 送許昌")
	sim.cmd_office_abandon(pid)
	check((ch["office"]["order"] as Dictionary).is_empty() and RulesShop.count_item(ch["bag"], letter) == 0, "放棄: 收返軍函")
	check(int(ch["ap"]) == 90, "放棄唔退行動力 (100 - 10)")
	sim.cmd_office_order(pid, "arms")
	check(_last(msgs).begins_with("今日已經"), "放棄咗今日都唔接得")


# S06a: 訂製軍備 (kind "buy") — 武器店買指定武器 (10001 柳葉刀) 捐畀官宅
func t_order_buy(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var item := int(sim.order_def("custom_arms")["item"])
	_put_fac(sim, pid, data, "donate_xc")
	ch["titleRank"] = 9
	sim.cmd_office_order(pid, "custom_arms")
	check(_last(msgs).begins_with("要五官中郎將"), "9 階接唔到訂製軍備")
	ch["titleRank"] = 10
	sim.cmd_office_order(pid, "custom_arms")
	check(String(ch["office"]["order"]["id"]) == "custom_arms", "10 階接咗訂製軍備")
	sim.cmd_office_turnin(pid)
	check(_last(msgs).begins_with("仲未買到"), "未買武器覆唔到命")
	RulesShop.add_item(ch["bag"], item, 1)
	sim.cmd_office_turnin(pid)
	check(not (ch["office"]["order"] as Dictionary).is_empty(), "背包有武器但唔係商店買（冇購買記錄）覆唔到命")
	ch["office"]["order"]["bought"] = 1     # 模擬喺武器店買入 (cmd_buy 記數)
	var fame0 := int(ch.get("fame", 0))
	sim.cmd_office_turnin(pid)
	check((ch["office"]["order"] as Dictionary).is_empty() and int(ch["fame"]) == fame0 + 40, "訂製軍備完成: 名聲 +40")
	check(RulesShop.count_item(ch["bag"], item) == 0, "武器已經捐咗")


# S06a: 朝廷求才 (kind "recruit") — 要跟緊 1 位「文官」型同伴先覆得命 (武將唔算數)
func t_order_recruit(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_put_fac(sim, pid, data, "donate_xc")
	ch["titleRank"] = 19
	sim.cmd_office_order(pid, "recruit")
	check(_last(msgs).begins_with("要領軍將軍"), "19 階接唔到朝廷求才")
	ch["titleRank"] = 20
	sim.cmd_office_order(pid, "recruit")
	check(String(ch["office"]["order"]["id"]) == "recruit", "20 階接咗朝廷求才")
	sim.cmd_office_turnin(pid)
	check(_last(msgs).begins_with("要登用緊"), "未登用文官覆唔到命")
	var pe := sim.ent(pid)
	if not ch.has("recruit"):
		ch["recruit"] = {}
	var wu: Dictionary = data.general_by_id[2]
	var cwu := sim._spawn_companion(pe, wu)
	ch["recruit"]["comp"] = int(cwu["id"])
	sim.cmd_office_turnin(pid)
	check(_last(msgs).begins_with("要登用緊"), "跟緊嘅係武將唔算數")
	var wen: Dictionary = data.general_by_id[1]
	var cwen := sim._spawn_companion(pe, wen)
	ch["recruit"]["comp"] = int(cwen["id"])
	ch["office"]["order"]["base"] = int(cwen["id"])
	sim.cmd_office_turnin(pid)
	check(not (ch["office"]["order"] as Dictionary).is_empty(), "接令前已跟緊嘅文官唔算新登用")
	ch["office"]["order"]["base"] = 0
	var fame0 := int(ch.get("fame", 0))
	sim.cmd_office_turnin(pid)
	check((ch["office"]["order"] as Dictionary).is_empty() and int(ch["fame"]) == fame0 + 60, "朝廷求才完成 (文官同伴): 名聲 +60")


# S06a: 官員護衛 (kind "escort") — 護送去 field_1 打怪區保唔死；死咗 (down) → 自動失敗
func t_order_escort(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_put_fac(sim, pid, data, "donate_xc")
	ch["titleRank"] = 24
	sim.cmd_office_order(pid, "escort")
	check(_last(msgs).begins_with("要奮武將軍"), "24 階接唔到官員護衛")
	ch["titleRank"] = 25
	sim.cmd_office_order(pid, "escort")
	var npc_id := int(ch["office"]["order"]["npc"])
	check(npc_id != 0, "接咗官員護衛，生成護衛 NPC")
	var npc := sim.ent(npc_id)
	check(npc.has("gen") and String(npc["gen"]["role"]) == "escort", "護衛 NPC role = escort")
	sim.cmd_office_turnin(pid)
	check(_last(msgs).begins_with("仲未護送到"), "未護送到打怪區覆唔到命")
	sim._put_ent(npc, 60, 10)     # field_1 (潁川郊外) 範圍內
	var fame0 := int(ch.get("fame", 0))
	var gold0 := int(ch.get("gold", 0))
	sim.cmd_office_turnin(pid)
	check((ch["office"]["order"] as Dictionary).is_empty(), "官員護衛完成")
	check(int(ch["fame"]) == fame0 + 50, "官員護衛獎勵: 名聲 +50")
	var pay := RulesTitle.salary(data.titles, int(ch["titleRank"]))
	check(int(ch["gold"]) == gold0 + pay, "官員護衛獎勵: 俸祿 x1 金 (%d)" % pay)
	check(sim.ent(npc_id).is_empty(), "覆命後護衛 NPC 消失")
	# 失敗流程: 護衛 NPC 死咗 (down) → 官令自動失敗，唔退行動力
	sim._daily_hook(1)
	sim.state["clock"]["day"] = 1
	sim.cmd_office_order(pid, "escort")
	var npc2_id := int(ch["office"]["order"]["npc"])
	var npc2 := sim.ent(npc2_id)
	npc2["ch"]["hp"] = 1
	sim._kill_player(npc2)
	sim._office_tick()
	check((ch["office"]["order"] as Dictionary).is_empty() and _last(msgs).begins_with("官令「官員護衛」失敗"), "護衛 NPC 死咗 → 官令自動失敗")
	check(sim.ent(npc2_id).is_empty(), "失敗後護衛 NPC 被清走")


# S06a: 流落官員 (kind "rescue") — 打怪區搵到先跟你，帶返官宅覆命；死咗 (down) → 自動失敗
func t_order_rescue(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_put_fac(sim, pid, data, "donate_xc")
	ch["titleRank"] = 25
	sim.cmd_office_order(pid, "rescue")
	var npc_id := int(ch["office"]["order"]["npc"])
	var npc := sim.ent(npc_id)
	check(String(npc["gen"]["role"]) == "rescue" and not bool(npc["gen"]["rescued"]), "流落官員生成，未搵到")
	sim.cmd_office_turnin(pid)
	check(_last(msgs).begins_with("帶流落官員返"), "未搵到官員覆唔到命")
	var e := sim.ent(pid)
	sim._put_ent(e, int(npc["x"]), int(npc["y"]))
	sim._think_office_npc(npc)
	check(bool(npc["gen"]["rescued"]), "玩家埋身 → 救到，開始跟隨")
	_put_fac(sim, pid, data, "donate_xc")
	var fame0 := int(ch.get("fame", 0))
	sim.cmd_office_turnin(pid)
	check((ch["office"]["order"] as Dictionary).is_empty() and int(ch["fame"]) == fame0 + 50, "流落官員救回完成: 名聲 +50")
	check(sim.ent(npc_id).is_empty(), "覆命後 NPC 消失")
	# 失敗流程: NPC 死咗 (down) → 官令自動失敗
	sim._daily_hook(1)
	sim.state["clock"]["day"] = 1
	sim.cmd_office_order(pid, "rescue")
	var npc2_id := int(ch["office"]["order"]["npc"])
	var npc2 := sim.ent(npc2_id)
	npc2["ch"]["hp"] = 1
	sim._kill_player(npc2)
	sim._office_tick()
	check((ch["office"]["order"] as Dictionary).is_empty() and _last(msgs).begins_with("官令「流落官員」失敗"), "流落官員死咗 → 官令自動失敗")


# S08a (spec 08 §1): 義舉證明四類 20 項 + 頭銜限制 + 固定名聲值
func t_merit(data: GameData) -> void:
	var cfg: Dictionary = data.office["merit"]
	check(String(cfg["imperialOffice"]) == "donate_xc", "義舉證明 = 許昌官宅 (朝廷直轄)")
	check((cfg["items"] as Array).size() == 20, "義舉證明 20 項 (got %d)" % (cfg["items"] as Array).size())
	var per := {}
	for it in cfg["items"]:
		per[String(it["cat"])] = int(per.get(String(it["cat"]), 0)) + 1
	check(int(per["a"]) == 5 and int(per["b"]) == 5 and int(per["c"]) == 5 and int(per["d"]) == 5, "四類各 5 項")
	check(String(RulesMerit.item_def(cfg, 61501)["name"]) == "田鼠碎骨" and RulesMerit.fame_of(cfg, 61501) == 5, "田鼠碎骨 名聲 5")
	check(RulesMerit.item_def(cfg, 99999).is_empty() and RulesMerit.fame_of(cfg, 99999) == 0, "非義舉物品 = 空")
	# 頭銜需求: 為民除害類冇、其餘照攻略表
	check(RulesMerit.block(cfg, 61501, 0, data.titles) == "", "田鼠碎骨白身都收得")
	check(RulesMerit.block(cfg, 61506, 5, data.titles).begins_with("要南中郎將"), "賊寇錦囊要南中郎將")
	check(RulesMerit.block(cfg, 61506, 6, data.titles) == "", "賊寇錦囊 6 階得")
	check(RulesMerit.block(cfg, 61510, 14, data.titles).begins_with("要威南將軍"), "要塞地形圖要威南將軍 (15)")
	check(RulesMerit.block(cfg, 61046, 39, data.titles).begins_with("要左將軍"), "仕女圖要左將軍 (40)")
	check(RulesMerit.block(cfg, 61038, 20, data.titles) == "", "前朝槍兵裝 = 領軍將軍 (20)")
	check(RulesMerit.block(cfg, 99999, 60, data.titles).begins_with("呢件唔係"), "非義舉物品唔收")


func t_merit_turnin(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	var cfg: Dictionary = data.office["merit"]
	# 喺新野縣衙繳唔到 (唔屬朝廷直轄)
	_put_fac(sim, pid, data, "donate_xy")
	RulesShop.add_item(ch["bag"], 61501, 1)
	sim.cmd_merit_turnin(pid, 61501)
	check(RulesShop.count_item(ch["bag"], 61501) == 1 and _last(msgs).contains("只有許昌"), "新野繳唔到義舉證明")
	# 許昌官宅
	_put_fac(sim, pid, data, "donate_xc")
	var ml := sim.merit_list(ch)
	check(ml.size() == 20 and bool(ml[0]["can"]) and int(ml[5]["reqRank"]) == 6, "merit_list read-model")
	sim.cmd_merit_turnin(pid, 61506)
	check(RulesShop.count_item(ch["bag"], 61506) == 0 and _last(msgs).contains("要南中郎將"), "頭銜唔夠唔收")
	sim.cmd_merit_turnin(pid, 99999)
	check(_last(msgs).contains("唔係義舉證明"), "非義舉物品唔收")
	sim.cmd_merit_turnin(pid, 61503)
	check(_last(msgs).contains("背包冇"), "冇貨唔收")
	ch["fame"] = 0
	sim.cmd_merit_turnin(pid, 61501)
	check(RulesShop.count_item(ch["bag"], 61501) == 0 and int(ch["fame"]) == 5, "繳田鼠碎骨: 名聲 +5")
	ch["titleRank"] = 6
	RulesShop.add_item(ch["bag"], 61506, 1)
	sim.cmd_merit_turnin(pid, 61506)
	check(RulesShop.count_item(ch["bag"], 61506) == 0 and int(ch["fame"]) == 25, "6 階繳賊寇錦囊: 名聲 +20")


func t_thirst(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	check(int(ch["thirst"]) == 100, "新角色飲水度 100")
	var says: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if String(ev.get("k", "")) == "npc_say":
			says.append(String(ev["text"])))
	var g := _gen(data, "典韋")
	_put(sim, pid, int(g["x"]), int(g["y"]) + 1)
	sim.cmd_general_talk(pid, int(g["id"]))
	check(int(ch["thirst"]) == 99, "同人才傾偈扣 1")
	# 冇人聽嘅 chat 唔扣
	_put(sim, pid, int(g["x"]), int(g["y"]) + 1)
	sim.cmd_chat(pid, "喂")
	check(int(ch["thirst"]) == 99, "附近冇居民: chat 唔扣")
	sim.add_bots(1)
	var bot := sim.ent(int(sim.state["bots"][0]))
	_put(sim, int(bot["id"]), int(g["x"]) + 1, int(g["y"]) + 1)
	sim.cmd_chat(pid, "你好")
	check(int(ch["thirst"]) == 98, "同居民搭話扣 1")
	sim.cmd_chat(int(bot["id"]), "你好")
	check(int(bot["ch"]["thirst"]) == 100, "居民自己講嘢唔扣")
	ch["thirst"] = 0
	says.clear()
	sim.cmd_general_talk(pid, int(g["id"]))
	check(int(ch["thirst"]) == 0 and says.size() == 1 and String(says[0]) == Sim.THIRSTY_LINE, "口渴: 人才只講模板客套話")
	# 喝茶
	sim.cmd_tea(pid)
	check(_last(msgs).begins_with("要喺客棧"), "唔喺客棧冇茶飲")
	_put(sim, pid, int(data.inn["x"]), int(data.inn["y"]) + 1)
	ch["gold"] = 4
	sim.cmd_tea(pid)
	check(int(ch["thirst"]) == 0, "唔夠 5 金飲唔到")
	ch["gold"] = 100
	ch["mp"] = 0
	sim.cmd_tea(pid)
	var mmp := sim._eff_max_mp(ch)
	check(int(ch["thirst"]) == 50 and int(ch["gold"]) == 95, "喝茶: 飲水度 +50、扣 5 金")
	check(int(ch["mp"]) == mini(mmp, int(round(mmp * 0.3))), "喝茶: 回 30% MP")
	sim.cmd_tea(pid)
	sim.cmd_tea(pid)
	check(int(ch["thirst"]) == 100, "飲水度封頂 100")
	ch.erase("thirst")
	check(sim.thirst_of(ch) == 100, "舊存檔冇 thirst → 當滿")


func t_recruit_title(data: GameData) -> void:
	var cfg: Dictionary = data.recruit_cfg
	var g := {"ideo": "出仕", "lv": 70}
	check(RulesRecruit.check(g, {"level": 70, "ideology": "義理"}, cfg) == "頭銜唔夠", "70 級人才 (20 階) 白身: 頭銜唔夠")
	check(RulesRecruit.check(g, {"level": 70, "ideology": "義理", "titleRank": 15}, cfg) == "", "15 階 (差 5) 得")
	# 調查候選: 冇頭銜 → 高等人才唔入候選
	var r := _new(data)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	ch["level"] = 80
	ch["ideology"] = "義理"
	var n_ok := 0
	var n_bad := 0
	for gg in data.generals:
		if int(gg["tier"]) < 0 or int(gg["lv"]) < 60 or int(gg["lv"]) > 90:
			continue
		if RulesRecruit.check(gg, ch, cfg) == "":
			n_ok += 1
		else:
			n_bad += 1
	check(n_ok == 0 and n_bad > 0, "白身 80 級: 60~90 級人才全部登用唔到 (頭銜)")
	ch["titleRank"] = 60
	var n_ok2 := 0
	for gg in data.generals:
		if int(gg["tier"]) >= 0 and int(gg["lv"]) >= 60 and int(gg["lv"]) <= 90 and RulesRecruit.check(gg, ch, cfg) == "":
			n_ok2 += 1
	check(n_ok2 > 0, "大將軍: 登用得返")


func t_save_roundtrip(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	ch["titleRank"] = 6
	ch["contrib"] = 12
	ch["polExp"] = 3
	ch["thirst"] = 61
	_put_fac(sim, pid, data, "donate_xc")
	sim.cmd_office_order(pid, "letter")
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	var lch := loaded.player_ch()
	check(int(lch["titleRank"]) == 6 and int(lch["contrib"]) == 12 and int(lch["polExp"]) == 3 and int(lch["thirst"]) == 61, "存檔: 頭銜/貢獻/政治經驗/飲水度保留")
	check(String(lch["office"]["order"]["to"]) == "donate_xy" and int(lch["office"]["orderDay"]) == 0, "存檔: 官令進度保留")
	check(loaded.save_string() == s1, "存檔: save→load→save 一致")
	check(loaded.ap_max(lch) == 112, "存檔: 行動力上限跟頭銜")
	# 舊存檔 (Step 13): 冇 titleRank/thirst/office/contrib/polExp
	var d: Dictionary = JSON.parse_string(s1)
	for e in d["state"]["ents"].values():
		if e.has("ch"):
			for k in ["titleRank", "thirst", "office", "contrib", "polExp"]:
				e["ch"].erase(k)
	var old := Sim.load_string(data, JSON.stringify(d))
	var och := old.player_ch()
	check(old.ap_max(och) == 100 and old.thirst_of(och) == 100, "舊存檔: 白身 + 飲水度滿")
	och["fame"] = 1000
	och["gold"] = 1000
	old.cmd_claim_title(pid, 2)
	old.cmd_office_order(pid, "arms")
	check(int(och["titleRank"]) == 2 and String(och["office"]["order"]["id"]) == "arms", "舊存檔: 討取 + 接官令照用得")


func _run_seq(data: GameData) -> String:
	var r := _new(data, 77)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	ch["fame"] = 9000
	ch["gold"] = 20000
	_put_fac(sim, pid, data, "donate_xc")
	sim.cmd_claim_title(pid, 15)
	sim.cmd_office_order(pid, "census")
	for nm in ["典韋", "許褚"]:
		var g := _gen(data, nm)
		_put(sim, pid, int(g["x"]), int(g["y"]) + 1)
		sim.cmd_general_talk(pid, int(g["id"]))
	for i in 800:
		sim.step()
	sim.cmd_tea(pid)
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_run_seq(data) == _run_seq(data), "決定性: 同種子同操作 → 同存檔")
