extends SceneTree
# S08 測試 (spec 08 §1): 城池進貢 + 城池好感 (S08a)。義舉證明喺 tests/run_title.gd。
# 進貢 = 捐獻處交物資 (捐獻單位) → 名聲 + 該城好感【自訂 ×0.01】；唔扣行動力；好感封頂。
# 跑: Godot --headless --path client --script tests/run_militia.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_data(data)
	t_rules(data)
	t_city_data(data)
	t_city_rules(data)
	t_domestic(data)
	t_domestic_expert(data)
	t_domestic_effects(data)
	t_tribute(data)
	t_cap(data)
	t_save_roundtrip(data)
	t_city_save(data)
	t_determinism(data)
	print("[TEST] militia (tribute/favor) scenarios: %d, fail %d" % [total, fails])
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


# data.shops 座標已經係 GameData 全域轉換後嘅值
func _put_shop(sim: Sim, id: int, data: GameData, shop_id: String) -> void:
	for s in data.shops:
		if String(s["id"]) == shop_id:
			_put(sim, id, int(s["x"]), int(s["y"]))
			return


func _new(data: GameData, seed: int = 8) -> Array:
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


func t_data(data: GameData) -> void:
	var cfg: Dictionary = data.office["tribute"]
	check(int(cfg["favorCap"]) == 100 and int(cfg["unitsPerFavor"]) == 100 and int(cfg["unitsPerFame"]) == 100, "進貢設定 unitsPerFavor/unitsPerFame=100 favorCap=100")


func t_rules(data: GameData) -> void:
	var cfg: Dictionary = data.office["tribute"]
	check(RulesMerit.favor_gain(0, cfg) == 0 and RulesMerit.favor_gain(99, cfg) == 0, "好感: <100 單位 = 0")
	check(RulesMerit.favor_gain(100, cfg) == 1 and RulesMerit.favor_gain(250, cfg) == 2, "好感: 100 單位 = 1 (×0.01)")
	check(RulesMerit.tribute_fame(100, cfg) == 1 and RulesMerit.tribute_fame(199, cfg) == 1, "名聲: 100 單位 = 1")
	check(RulesMerit.favor_cap(98, cfg) == 98 and RulesMerit.favor_cap(120, cfg) == 100, "好感封頂 100")


func t_tribute(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	RulesShop.add_item(ch["bag"], 25001, 500)
	sim.cmd_city_tribute(pid, [[25001, 100]])
	check(int(sim.city_favor(ch, "xuchang")) == 0 and _last(msgs).contains("捐獻處"), "唔喺捐獻處進貢唔到")
	_put_fac(sim, pid, data, "donate_xc")
	var ap0 := int(ch["ap"])
	var fame0 := int(ch.get("fame", 0))
	sim.cmd_city_tribute(pid, [[25001, 100]])
	check(int(sim.city_favor(ch, "xuchang")) == 1, "許昌進貢 100 單位: 好感 +1")
	check(int(ch["fame"]) == fame0 + 1, "許昌進貢: 名聲 +1")
	check(int(ch["ap"]) == ap0, "進貢唔扣行動力")
	check(RulesShop.count_item(ch["bag"], 25001) == 400, "進貢扣咗 100 石頭")
	check(int(sim.city_favor(ch, "xiangyang")) == 0 and int(sim.city_favor(ch, "xinye")) == 0, "只升進貢嗰個城嘅好感")
	var view := sim.city_favor_view(ch)
	check(view.size() == data.world["cities"].size() and String(view[0]["id"]) == "xuchang" and int(view[0]["favor"]) == 1, "city_favor_view read-model")
	# 新野縣衙 → 新野好感
	_put_fac(sim, pid, data, "donate_xy")
	sim.cmd_city_tribute(pid, [[25001, 200]])
	check(int(sim.city_favor(ch, "xinye")) == 2 and int(sim.city_favor(ch, "xuchang")) == 1, "新野進貢只升新野好感")
	# 背包唔夠 / 冇有效物資
	sim.cmd_city_tribute(pid, [[25001, 99999]])
	check(int(sim.city_favor(ch, "xinye")) == 2 and _last(msgs).contains("背包冇"), "背包唔夠唔進貢")
	sim.cmd_city_tribute(pid, [[61501, 1]])
	check(_last(msgs).contains("冇物資可以進貢"), "任務道具唔算物資")
	sim.cmd_city_tribute(pid, [])
	check(_last(msgs).contains("冇物資可以進貢"), "空清單唔進貢")
	check(int(ch["fame"]) == fame0 + 3, "三次成功進貢名聲 (300+200 單位)")


func t_cap(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_put_fac(sim, pid, data, "donate_xc")
	ch["cityFavor"] = {"xuchang": 99}
	RulesShop.add_item(ch["bag"], 25001, 500)
	sim.cmd_city_tribute(pid, [[25001, 500]])
	check(int(sim.city_favor(ch, "xuchang")) == 100 and _last(msgs).contains("好感 +1"), "好感由 99 進貢到封頂 100")
	ch["cityFavor"] = {"xuchang": 100}
	RulesShop.add_item(ch["bag"], 25001, 500)
	sim.cmd_city_tribute(pid, [[25001, 500]])
	check(int(sim.city_favor(ch, "xuchang")) == 100 and _last(msgs).contains("好感 +0"), "滿咗唔再升 (好感 +0)")


func t_save_roundtrip(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put_fac(sim, pid, data, "donate_xc")
	RulesShop.add_item(ch["bag"], 25001, 300)
	sim.cmd_city_tribute(pid, [[25001, 300]])
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	var lch := loaded.player_ch()
	check(loaded.city_favor(lch, "xuchang") == 3, "存檔: 城池好感保留")
	check(loaded.save_string() == s1, "存檔: save→load→save 一致")
	# 舊存檔: 冇 cityFavor → 0
	var d: Dictionary = JSON.parse_string(s1)
	for e in d["state"]["ents"].values():
		if e.has("ch"):
			e["ch"].erase("cityFavor")
	var old := Sim.load_string(data, JSON.stringify(d))
	var och := old.player_ch()
	check(old.city_favor(och, "xuchang") == 0, "舊存檔: 冇 cityFavor → 0")
	_put_fac(old, pid, data, "donate_xc")
	RulesShop.add_item(och["bag"], 25001, 100)
	old.cmd_city_tribute(pid, [[25001, 100]])
	check(old.city_favor(och, "xuchang") == 1, "舊存檔: 照進貢得")


func _run_seq(data: GameData) -> String:
	var r := _new(data, 88)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put_fac(sim, pid, data, "donate_xc")
	ch["titleRank"] = 1
	sim.cmd_domestic(pid, "kaiken")
	RulesShop.add_item(ch["bag"], 25001, 400)
	sim.cmd_city_tribute(pid, [[25001, 250]])
	for i in 500:
		sim.step()
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_run_seq(data) == _run_seq(data), "決定性: 同種子同操作 → 同存檔")

# ================= S08b 城池屬性 + 官宅內政 6 種 (spec 08 §3) =================

func _city(data: GameData, id: String) -> Dictionary:
	for c in data.world["cities"]:
		if String(c["id"]) == id:
			return c
	return {}


func t_city_data(data: GameData) -> void:
	var cfg: Dictionary = data.world["cityAttrs"]
	check(int(cfg["default"]) == 50 and (cfg["order"] as Array).size() == 8, "cityAttrs: default 50 + order 8 項")
	for c in data.world["cities"]:
		var a: Dictionary = c.get("attrs", {})
		var ok := a.size() == 8
		for k in RulesCity.KEYS:
			if not a.has(k) or int(a[k]) < 0 or int(a[k]) > 100:
				ok = false
		check(ok, "城池 %s: attrs 8 項 0~100" % c["id"])
		check(int(a.get("fangzai", -1)) == int(c.get("defense", -1)), "城池 %s: 防災初值 = 舊 defense" % c["id"])
	check(RulesCity.name_of(cfg, "kaiken") == "開墾" and RulesCity.name_of(cfg, "duanzao") == "鑄造", "屬性中文名")


func t_city_rules(data: GameData) -> void:
	var cfg: Dictionary = data.world["cityAttrs"]
	var d := RulesCity.defaults(cfg)
	check(d.size() == 8 and int(d["kaiken"]) == 50, "defaults = 全 50")
	var init := RulesCity.init_attrs({"attrs": {"kaiken": 130, "zhian": -5}}, cfg)
	check(int(init["kaiken"]) == 100 and int(init["zhian"]) == 0 and int(init["xumu"]) == 50, "init_attrs: clamp + 缺 = default")
	check(RulesCity.attr_of({}, "kaiken", cfg) == 50, "attr_of 空 = default")
	# 市場 prod 連動
	check(absf(RulesCity.prod_mult(d, "43", cfg) - 1.0) < 1e-9, "prod: default = 1.0")
	check(absf(RulesCity.prod_mult({"shangye": 100}, "43", cfg) - 1.3) < 1e-9, "prod: 商業 100 → 43 貨 ×1.3")
	check(absf(RulesCity.prod_mult({"kuangchan": 0}, "32", cfg) - 0.7) < 1e-9, "prod: 礦產 0 → 32 礦石 ×0.7")
	check(absf(RulesCity.prod_mult({"shangye": 100}, "99", cfg) - 1.0) < 1e-9, "prod: 冇對應 cat = 1.0")
	# 防災 / 商店貨單 / 衛兵 / 治安
	check(absf(RulesCity.disaster_mitigation({"fangzai": 80}, cfg) - 0.8) < 1e-9, "防災 80 → 減弱 0.8")
	check(absf(RulesCity.disaster_mitigation({}, cfg, 40.0) - 0.4) < 1e-9, "冇 attrs → 舊 defense 兼容")
	check((RulesCity.shop_extra_items({"duanzao": 50}, cfg) as Array).is_empty(), "鑄造 50: 冇額外貨")
	check((RulesCity.shop_extra_items({"duanzao": 60}, cfg) as Array).size() == 4, "鑄造 60: 多 4 件貨")
	check(RulesCity.guard_warn_ticks({"fangyu": 50}, 120, cfg) == 120, "防禦 50: 衛兵間隔不變")
	check(RulesCity.guard_warn_ticks({"fangyu": 100}, 120, cfg) == 60 and RulesCity.guard_warn_ticks({"fangyu": 0}, 120, cfg) == 180, "防禦影響衛兵間隔")
	check(absf(RulesCity.crime_mult({"zhian": 50}, cfg) - 1.0) < 1e-9 and absf(RulesCity.crime_mult({"zhian": 100}, cfg) - 0.5) < 1e-9, "治安影響犯案率")
	check(RulesCity.attr_gain(2, 1.0) == 2 and RulesCity.attr_gain(2, 1.5) == 3 and RulesCity.attr_gain(2, 0.1) == 1, "attr_gain 完成度倍率")


func t_domestic(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	check((data.office["domestic"]["jobs"] as Array).size() == 6, "內政 6 種")
	# 唔喺官宅
	sim.cmd_domestic(pid, "kaiken")
	check(_last(msgs).contains("官宅"), "唔喺官宅做唔到內政")
	_put_fac(sim, pid, data, "donate_xc")
	# 白身（頭銜 0）
	ch["titleRank"] = 0
	sim.cmd_domestic(pid, "kaiken")
	check(_last(msgs).contains("官身"), "白身做唔到內政")
	ch["titleRank"] = 1
	ch["ap"] = 100
	var view := sim.domestic_view(pid)
	check(String(view["city"]) == "xuchang" and (view["jobs"] as Array).size() == 6 and (view["attrs"] as Array).size() == 8, "domestic_view read-model")
	check(bool((view["jobs"] as Array)[0]["can"]), "有官身: 開墾做得")
	# 做一次開墾
	sim.cmd_domestic(pid, "kaiken")
	var attrs: Dictionary = sim.city_attrs("xuchang")
	check(int(attrs["kaiken"]) == 52, "墾荒種地: 開墾 +2")
	check(int(ch["ap"]) == 90, "內政扣行動力 10")
	check(int(ch["expert"]["kaiken"]) == 3, "內政加開墾專長 exp 3")
	check(int(sim.city_attrs("xinye")["kaiken"]) == 50, "只升做嗰個城")
	# 冇呢種 / 行動力不足 / 封頂
	sim.cmd_domestic(pid, "nope")
	check(_last(msgs).contains("冇呢種內政"), "未知內政")
	ch["ap"] = 5
	sim.cmd_domestic(pid, "shangye")
	check(_last(msgs).contains("行動力不足"), "行動力不足做唔到")
	ch["ap"] = 100
	sim.city_attrs_set("xuchang", {"kaiken": 100, "shangye": 50, "xumu": 50, "kuangchan": 50, "duanzao": 50, "fangyu": 50, "fangzai": 50, "zhian": 50})
	sim.cmd_domestic(pid, "kaiken")
	check(_last(msgs).contains("封頂"), "屬性封頂唔做")
	sim.cmd_domestic(pid, "fangyu")
	check(int(sim.city_attrs("xuchang")["fangyu"]) == 52, "增強防禦: 防禦 +2")
	# 99 → 封頂 100 只加 1
	sim.city_attrs_set("xuchang", {"kaiken": 50, "shangye": 50, "xumu": 50, "kuangchan": 50, "duanzao": 50, "fangyu": 99, "fangzai": 50, "zhian": 50})
	sim.cmd_domestic(pid, "fangyu")
	check(int(sim.city_attrs("xuchang")["fangyu"]) == 100, "99 → 封頂 100")


func t_domestic_expert(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put_fac(sim, pid, data, "donate_xc")
	ch["titleRank"] = 1
	ch["expert"]["kaiken"] = 30    # 2 級 (門檻 10/30) → domestic_mult 1.5
	check(sim.expert_lv(ch, "kaiken") == 2, "開墾專長 2 級")
	sim.cmd_domestic(pid, "kaiken")
	check(int(sim.city_attrs("xuchang")["kaiken"]) == 53, "專長 2 級: 開墾 +3 (base 2 × 1.5)")
	# 專長 exp 升到 4 級 (150) 前封頂喺職業上限
	ch["expert"]["kaiken"] = 210
	sim.cmd_domestic(pid, "kaiken")
	check(int(sim.city_attrs("xuchang")["kaiken"]) == 57, "專長 4 級: 開墾 +4 (base 2 × 2.0)")


func t_domestic_effects(data: GameData) -> void:
	# 商業屬性 → 市場 prod
	var a := _new(data, 5)
	var sa: Sim = a[0]
	var b := _new(data, 5)
	var sb: Sim = b[0]
	sb.city_attrs_set("xuchang", {"kaiken": 50, "shangye": 100, "xumu": 50, "kuangchan": 50, "duanzao": 50, "fangyu": 50, "fangzai": 50, "zhian": 50})
	for i in 4:
		sa._market_daily(i % 4)
		sb._market_daily(i % 4)
	check(float(sb.market_city("xuchang", "43")["stock"]) > float(sa.market_city("xuchang", "43")["stock"]),
		"商業屬性高 → 糧食供應多 (庫存升)")
	# 鑄造屬性 → 商店貨單
	var c := _new(data, 6)
	var sc: Sim = c[0]
	var pc: int = c[1]
	var chc: Dictionary = c[2]
	var msgc: Array = c[3]
	_put_shop(sc, pc, data, "weapon")    # 許昌武器店 (座標由 GameData 轉咗全域)
	chc["gold"] = 99999
	sc.cmd_buy(pc, 10037)
	check(_last(msgc).contains("唔賣"), "鑄造 50: 武器店未賣高階刀")
	sc.city_attrs_set("xuchang", {"kaiken": 50, "shangye": 50, "xumu": 50, "kuangchan": 50, "duanzao": 60, "fangyu": 50, "fangzai": 50, "zhian": 50})
	sc.cmd_buy(pc, 10037)
	check(RulesShop.count_item(chc["bag"], 10037) == 1, "鑄造 60: 武器店賣多咗鋼刀")
	# 防災屬性 → 天災減弱 (sim 層)
	var city := sc._city_with_attrs(_city(data, "xuchang"))
	var m50 := RulesMarket.supply_mods(1, data.world["market"]["seasonSupply"], [{"supply": {"43": 0.25}}], city)
	sc.city_attrs_set("xuchang", {"kaiken": 50, "shangye": 50, "xumu": 50, "kuangchan": 50, "duanzao": 50, "fangyu": 50, "fangzai": 80, "zhian": 50})
	var city2 := sc._city_with_attrs(_city(data, "xuchang"))
	var m80 := RulesMarket.supply_mods(1, data.world["market"]["seasonSupply"], [{"supply": {"43": 0.25}}], city2)
	check(float(m80["43"]) > float(m50["43"]), "防災 80 比 50 少天災減供 (>=)")


func t_city_save(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put_fac(sim, pid, data, "donate_xc")
	ch["titleRank"] = 1
	sim.cmd_domestic(pid, "kaiken")
	sim.cmd_domestic(pid, "duanzao")
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	check(int(loaded.city_attrs("xuchang")["kaiken"]) == 52 and int(loaded.city_attrs("xuchang")["duanzao"]) == 52, "存檔: 城池屬性保留")
	check(loaded.save_string() == s1, "存檔: save→load→save 一致")
	# 舊存檔: 冇 cityAttrs → world 初值
	var d: Dictionary = JSON.parse_string(s1)
	d["state"].erase("cityAttrs")
	var old := Sim.load_string(data, JSON.stringify(d))
	check(int(old.city_attrs("xuchang")["kaiken"]) == 50, "舊存檔: 冇 cityAttrs → 初值 50")
	check(int(old.city_attrs("xiangyang")["fangzai"]) == 45 and int(old.city_attrs("xinye")["fangzai"]) == 30, "舊存檔: 防災初值跟 world")
	ch["titleRank"] = 1
	_put_fac(old, pid, data, "donate_xc")
	old.cmd_domestic(pid, "kaiken")
	check(int(old.city_attrs("xuchang")["kaiken"]) == 52, "舊存檔: 補完 cityAttrs 照做內政")
