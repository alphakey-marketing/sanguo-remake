extends SceneTree
# 市場 1000 日模擬器 (Step 4.4 驗收): 用真 RulesMarket + RulesDisaster 跑 1000 日，
# 檢查: (a) 所有價格因子有界 [min,max] (b) 無長期通脹/崩盤 (c) 天災後價格短暫上升會回落
# (d) 玩家式大量出貨 → 價格下跌後回歸。
# 跑: Godot --headless --path client --script tools/market_sim.gd

var fails := 0


func _init() -> void:
	var data := GameData.load_all()
	var cfg: Dictionary = data.world["market"]
	var rng := SimRng.new(20260921)
	var rng_fn := Callable(rng, "next")
	var cities: Array = data.world["cities"]
	var disasters: Array = []
	# 初始市場: 每城每 cat
	var mk := {}
	for c in cities:
		var cm := {}
		for k in cfg["cats"]:
			cm[k] = {"stock": float(cfg["cats"][k]["vol"]), "pf": 1.0}
		mk[c.id] = cm

	var worst := 0.0
	var worst_at := ""
	var n_dis := [0]
	var dump_pf := {}
	for day in 1000:
		var season := RulesClock.season_of_day(day, int(data.world["clock"]["seasonDays"]))
		# 天災
		RulesDisaster.expire(disasters, day)
		for c in cities:
			var d := RulesDisaster.roll_day(rng_fn, day, season, String(c.id), data.world["disasters"])
			if not d.is_empty():
				disasters.append(d)
				n_dis[0] += 1
		# 玩家式干預: 第 300~330 日喺許昌大攰出貨 5000 糧 (模擬玩家賣材料)
		if day >= 300 and day < 330:
			var m: Dictionary = mk["xuchang"]["43"]
			m["stock"] = float(m["stock"]) + 5000.0 / 330.0
		# 日結
		for c in cities:
			var city_dis := []
			for d in disasters:
				if str(d["city"]) == str(c.id):
					city_dis.append(d)
			var sm := RulesMarket.supply_mods(season, cfg["seasonSupply"], city_dis, c)
			var dm := RulesMarket.demand_mods(season, cfg["seasonDemand"])
			RulesMarket.daily(c, mk[c.id], cfg, sm, dm)
		# 統計
		for c in cities:
			for k in mk[c.id]:
				var pf := float(mk[c.id][k]["pf"])
				if pf < float(cfg["minFactor"]) - 1e-9 or pf > float(cfg["maxFactor"]) + 1e-9:
					fails += 1
					print("[FAIL] 第 %d 日 %s/%s pf=%.4f 超出界線" % [day, c.id, k, pf])
					quit(1)
				if absf(pf - 1.0) > worst:
					worst = absf(pf - 1.0)
					worst_at = "%d %s/%s pf=%.3f" % [day, c.id, k, pf]
				if day == 310:
					dump_pf["%s/%s" % [c.id, k]] = pf
	# 天災停晒再多跑 200 日 → 價格應該回歸 1
	for day in 200:
		var season := RulesClock.season_of_day(day + 1000, int(data.world["clock"]["seasonDays"]))
		for c in cities:
			var sm := RulesMarket.supply_mods(season, cfg["seasonSupply"], [], c)
			var dm := RulesMarket.demand_mods(season, cfg["seasonDemand"])
			RulesMarket.daily(c, mk[c.id], cfg, sm, dm)
	var food_end := float(mk["xuchang"]["43"]["pf"])
	var food_dump := float(dump_pf.get("xuchang/43", 1.0))
	print("[MARKET] 1000 日: 天災 %d 次, 最大偏移 %.3f (%s), 出貨期糧 pf=%.3f, 靜止 200 日後=%.3f"
		% [n_dis[0], worst, worst_at, food_dump, food_end])
	if worst > 1.0 + 1e-6:
		fails += 1
		print("[FAIL] 有 cat 去到界線以外 (唔應該發生，有 clamp 都出界)")
	if food_dump > 0.95:
		fails += 1
		print("[FAIL] 玩家出貨 5000 糧期間價格冇明顯下跌 (%.3f)" % food_dump)
	if food_end > 1.15 or food_end < 0.85:
		fails += 1
		print("[FAIL] 天災停 + 200 日後糧價冇回歸 1 (%.3f): 市場有結構性偏差" % food_end)
	if n_dis[0] == 0:
		print("[FAIL] 1000 日冇任何天災 (機率問題?)")
		fails += 1
	if fails == 0:
		print("[MARKET] PASS: 有界、出貨跌價、天災後回歸、無暴走")
	quit(1 if fails > 0 else 0)