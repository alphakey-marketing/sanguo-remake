extends SceneTree
# 專長效果: 等級/上限/職階、exp 封頂、認證、買賣折扣/加成、內政/義勇軍/救災倍率、技能神丹
# 跑: Godot --headless --path client --script tests/run_expfx.gd
var fails := 0
var total := 0


func check(c: bool, m: String) -> void:
	total += 1
	if not c:
		fails += 1
		print("[FAIL] " + m)


func _init() -> void:
	var data := GameData.load_all()
	var ex: Dictionary = data.experts
	var le: Array = ex["levelExp"]
	# 等級門檻 / 上限 / 職階
	check(RulesExpert.level_of_exp(9, le) == 0 and RulesExpert.level_of_exp(10, le) == 1 and RulesExpert.level_of_exp(210, le) == 6, "exp→級 門檻")
	check(RulesExpert.cap_of(ex, "yishi", "kaiken") == 4 and RulesExpert.cap_of(ex, "yishi", "zhaolai") == 2, "職業上限 (義士 開墾 4 / 招徠 2)")
	check(RulesExpert.cap_of(ex, "yishi", "zhaolai", 1) == 3 and RulesExpert.cap_of(ex, "yishi", "kaiken", 5) == 6, "職階提升上限 + 封頂 6")
	check(RulesExpert.eff_level(ex, "yishi", "zhaolai", 9999) == 2, "exp 夠多都封頂喺職業上限")
	# 每個專長每個職業都有上限，12 專長都有名同分類
	for sid in ex["skills"].keys():
		check(str(ex["skills"][sid].get("cat", "")) != "", "專長 %s 有分類" % sid)
		for cls in ex["caps"].keys():
			check(int(ex["caps"][cls].get(sid, 0)) >= 1, "%s/%s 有上限" % [cls, sid])
	# add_exp 封頂 / certify 唔降級
	var ch := {"classId": "yishi", "expert": {}}
	RulesExpert.add_exp(ch, ex, "zhaolai", 9999)
	check(int(ch["expert"]["zhaolai"]) == int(le[1]), "add_exp 封頂喺上限門檻 (%d)" % int(le[1]))
	RulesExpert.certify(ch, ex, "zhaolai", 1)
	check(int(ch["expert"]["zhaolai"]) == int(le[1]), "certify 唔降級")
	RulesExpert.certify(ch, ex, "kaiken", 9)
	check(RulesExpert.level_of_exp(int(ch["expert"]["kaiken"]), le) == 4, "certify 封頂職業上限")
	# 倍率函數單調
	check(RulesExpert.domestic_mult(0) == 1.0 and RulesExpert.domestic_mult(4) == 2.0, "內政倍率 ×1~×2")
	check(RulesExpert.militia_mult(4) > RulesExpert.militia_mult(1) and RulesExpert.relief_mult(3) > RulesExpert.relief_mult(0), "訓練/救災倍率遞增")
	check(RulesExpert.trade_buy_discount(9) == 0.10 and RulesExpert.trade_sell_bonus(9) == 0.10, "交易折扣/加成封頂 10%")
	check(RulesShop.buy_price(1000.0, 0.0, 0, 5) < RulesShop.buy_price(1000.0, 0.0, 0, 0), "交易專長令買入更平")
	check(RulesShop.sell_price(1000.0, 5) > RulesShop.sell_price(1000.0, 0), "交易專長令賣出更貴")
	# sim: 專長等級經 expert_lv 反映 + 內政收益
	var sim := Sim.new(data, 3)
	var id := sim.spawn_player("t", "yishi")
	var pch: Dictionary = sim.player_ch()
	check(sim.expert_lv(pch, "kaiken") == 0, "新角開墾 0 級")
	var g0 := _gain(sim, id, "kaiken")
	RulesExpert.certify(pch, ex, "kaiken", 4)
	check(sim.expert_lv(pch, "kaiken") == 4, "認證後開墾 4 級")
	var g4 := _gain(sim, id, "kaiken")
	check(g4 > g0, "開墾 4 級內政收益 > 0 級 (%d > %d)" % [g4, g0])
	# sim: 買入實際付費平咗
	var shop: Dictionary = data.shops[0]
	var item := 0
	for it in shop["stock"]:
		item = int(it["id"]) if it is Dictionary else int(it)
		break
	var e := sim.ent(id)
	e["x"] = int(shop["x"])
	e["y"] = int(shop["y"]) + 1
	pch["gold"] = 99999
	var before := int(pch["gold"])
	sim.cmd_buy(id, item, 1)
	var paid0 := before - int(pch["gold"])
	RulesExpert.certify(pch, ex, "jiaoyi", 2)
	pch["gold"] = 99999
	sim.cmd_buy(id, item, 1)
	var paid2 := 99999 - int(pch["gold"])
	check(paid0 > 0 and paid2 < paid0, "交易 2 級買同一件更平 (%d < %d)" % [paid2, paid0])
	# 技能神丹: 已學專長 +50 (封頂)
	var sim2 := Sim.new(data, 4)
	var id2 := sim2.spawn_player("t", "yishi")
	var c2: Dictionary = sim2.player_ch()
	RulesExpert.add_exp(c2, ex, "kaiken", 10)
	RulesShop.add_item(c2["bag"], sim2.ITEM_SKILL_ELIXIR, 1)
	sim2._use_skill_elixir(id2, sim2.ent(id2))
	check(int(c2["expert"]["kaiken"]) > 10, "技能神丹加專長 exp")
	# 效果說明文字
	check(RulesExpert.effect_line("kaiken", 2, 4) == "內政工作收益 ×1.50　→ 下一級 ×1.75", "內政說明 " + RulesExpert.effect_line("kaiken", 2, 4))
	check(RulesExpert.effect_line("kaiken", 4, 4).ends_with("（已達上限）"), "滿級標上限")
	check(RulesExpert.effect_line("jiaoyi", 2, 4).begins_with("買入 -4%　賣出 +4%"), "交易說明")
	check(RulesExpert.effect_line("tianwen", 0, 2).begins_with("Lv1 解鎖") and RulesExpert.effect_line("dili", 1, 2).begins_with("已解鎖"), "天文/地理說明")
	for sid in ex["skills"].keys():
		check(RulesExpert.effect_line(str(sid), 1, 3) != "", "專長 %s 有效果說明" % sid)
	print("[TEST] expfx: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func _gain(sim: Sim, id: int, expert: String) -> int:
	var v: Dictionary = sim.domestic_view(id)
	for j in v.get("jobs", []):
		if str(j["expert"]) == expert:
			return int(j["gain"])
	return -1
