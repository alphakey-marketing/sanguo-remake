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
	t_relief_data(data)
	t_relief_rules(data)
	t_bulletin(data)
	t_relief_flow(data)
	t_relief_effects(data)
	t_relief_save(data)
	t_comp_data(data)
	t_comp_rules(data)
	t_comp_claim(data)
	t_comp_defend(data)
	t_comp_save(data)
	t_comp_determinism(data)
	t_mil_data(data)
	t_mil_rules(data)
	t_settle(data)
	t_mil_invite(data)
	t_mil_found(data)
	t_mil_save(data)
	t_mil_determinism(data)
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


# 擺喺某張地圖內 (城/野都可用；map_idx 已覆蓋地圖全部格)
func _put_map(sim: Sim, id: int, data: GameData, map_id: String) -> void:
	var z: Dictionary = data.zone_by_id[map_id]
	_put(sim, id, int(z["x0"]) + 1, int(z["y0"]) + 1)


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


func _any(msgs: Array, sub: String) -> bool:
	for m in msgs:
		if String(m).contains(sub):
			return true
	return false


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


# ================= S08c 救災 (spec 08 §6 / 攻略 sy2_8_12) =================

# 喺 state["disasters"] 塞一條天災 (測試用；idx 0=大 1=中 2=細)
func _set_disaster(sim: Sim, disaster_id: String, city: String, size: String, idx: int) -> Dictionary:
	for d in sim.data.world["disasters"]:
		if String(d["id"]) == disaster_id:
			var sz: Dictionary = d["sizes"][idx]
			var dis := {"id": disaster_id, "name": String(d["name"]), "city": city, "size": size,
				"startDay": 0, "endDay": 999,
				"supply": (sz["supply"] as Dictionary).duplicate(),
				"baseSupply": (sz["supply"] as Dictionary).duplicate()}
			sim.state["disasters"].append(dis)
			return dis
	return {}


func t_relief_data(data: GameData) -> void:
	var defs: Array = data.world["disasters"]
	check(defs.size() == 7, "天災 7 種")
	var want := {"locust": 26022, "plague": 26023, "drought": 26024, "typhoon": 26025, "flood": 26026, "blizzard": 26027, "quake": 26028}
	var items: Array = []
	for d in defs:
		var iid := int(d.get("reliefItem", 0))
		items.append(iid)
		check(int(want[String(d["id"])]) == iid, "天災 %s → 救災物品 %d" % [d["id"], iid])
	check(RulesDisaster.relief_items(defs).size() == 7 and items.size() == 7, "7 種救災物品不同")
	var cfg: Dictionary = data.office["relief"]
	check(int(cfg["minTitleRank"]) == 0 and int(cfg["fame"]) == 10 and String(cfg["expert"]) == "jiuzai", "救災設定: 無頭銜限制/名聲+10/救災專長")
	check(int((cfg["workPerSize"] as Dictionary)["細"]) == 10 and int((cfg["workPerSize"] as Dictionary)["中"]) == 20 and int((cfg["workPerSize"] as Dictionary)["大"]) == 30, "救災次數 小10/中20/大30")
	# 設施: 3 城公佈欄 + 3 個救災區
	for k in ["bulletin_xc", "bulletin_xy", "bulletin_xyc"]:
		check(bool((data.facilities[k] as Dictionary).get("bulletin", false)), "%s 有 bulletin flag" % k)
	for k in ["relief_xc", "relief_xy", "relief_xyc"]:
		var f: Dictionary = data.facilities[k]
		check(bool(f.get("relief", false)) and String(f.get("cityId", "")) != "", "%s 有 relief flag + cityId" % k)
	check(String(data.facilities["relief_xc"]["map"]) == "field_1" and String(data.facilities["relief_xy"]["map"]) == "bowang" and String(data.facilities["relief_xyc"]["map"]) == "longzhong", "救災區喺各城腹地")
	# 工具店賣齊 7 種
	for sid in ["tool", "tool_xy", "tool_xyc"]:
		var stock: Array = []
		for s in data.shops:
			if String(s["id"]) == sid:
				stock = s["stock"]
		var n := 0
		for iid in [26022, 26023, 26024, 26025, 26026, 26027, 26028]:
			if stock.has(iid) or stock.has(float(iid)):
				n += 1
		check(n == 7, "工具店 %s 賣齊 7 種救災物品" % sid)


func t_relief_rules(data: GameData) -> void:
	var defs: Array = data.world["disasters"]
	var cfg: Dictionary = data.office["relief"]
	check(RulesDisaster.relief_item_of(defs, "locust") == 26022 and RulesDisaster.relief_item_of(defs, "quake") == 26028, "relief_item_of")
	check(RulesDisaster.relief_item_of(defs, "nope") == 0, "未知天災 = 0")
	check(RulesDisaster.relief_need("細", cfg) == 10 and RulesDisaster.relief_need("中", cfg) == 20 and RulesDisaster.relief_need("大", cfg) == 30, "relief_need")
	var d := {"supply": {"43": 0.5, "44": 1.0}, "baseSupply": {"43": 0.5, "44": 1.0}}
	RulesDisaster.relief_weaken(d, 5, 10)
	check(absf(float(d["supply"]["43"]) - 0.75) < 1e-9 and absf(float(d["supply"]["44"]) - 1.0) < 1e-9, "減弱 50%: 0.5 → 0.75 (1.0 不變)")
	RulesDisaster.relief_weaken(d, 10, 10)
	check(absf(float(d["supply"]["43"]) - 1.0) < 1e-9, "做完: factor → 1.0 (冇天災影響)")
	RulesDisaster.relief_weaken(d, 99, 10)
	check(absf(float(d["supply"]["43"]) - 1.0) < 1e-9, "超出需求 clamp 1.0")
	check(absf(float((d["baseSupply"] as Dictionary)["43"]) - 0.5) < 1e-9, "baseSupply 保留原值")


func t_bulletin(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var v0 := sim.bulletin_view(pid)
	check(not bool(v0["at"]) and (v0["cities"] as Array).size() == 4, "唔喺公佈欄: at=false，4 城 (含陳留)")
	_put_fac(sim, pid, data, "bulletin_xc")
	var v1 := sim.bulletin_view(pid)
	check(bool(v1["at"]), "企喺許昌公佈欄: at=true")
	_set_disaster(sim, "locust", "xuchang", "細", 2)
	var v2 := sim.bulletin_view(pid)
	var rows: Array = []
	for c in v2["cities"]:
		if String(c["id"]) == "xuchang":
			rows = c["disasters"]
	check(rows.size() == 1 and String(rows[0]["name"]) == "蝗災" and String(rows[0]["size"]) == "細" and int(rows[0]["item"]) == 26022, "公佈欄顯示許昌蝗災 + 農藥")


func t_relief_flow(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_put_fac(sim, pid, data, "donate_xc")
	ch["sp"] = 200
	ch["ap"] = 100
	var fame0 := int(ch.get("fame", 0))
	var pol0 := int(ch.get("polExp", 0))
	# 冇天災
	sim.cmd_office_relief(pid)
	check(_last(msgs).contains("冇天災"), "冇天災領唔到救災官令")
	_set_disaster(sim, "locust", "xuchang", "細", 2)
	sim.cmd_office_relief(pid)
	var od: Dictionary = sim.player_ch()["office"]["order"]
	check(String(od.get("id", "")) == "relief" and int(od["need"]) == 10 and int(od["done"]) == 0, "領到救災官令: 細規模需 10 次")
	check(int(ch["ap"]) == 90 and _last(msgs).contains("農藥"), "領令扣行動力 10 + 提示買農藥")
	sim.cmd_office_relief(pid)
	check(_last(msgs).contains("仲有官令"), "已有官令唔可以再接")
	# 救災區: 冇物品
	_put_fac(sim, pid, data, "relief_xc")
	sim.cmd_relief_work(pid)
	check(_last(msgs).contains("冇「農藥」"), "冇救災物品做唔到")
	# 錯區
	_put_fac(sim, pid, data, "relief_xy")
	RulesShop.add_item(ch["bag"], 26022, 10)
	sim.cmd_relief_work(pid)
	check(_last(msgs).contains("唔係許昌"), "唔喺所屬救災區做唔到")
	# 正確區做 1 次
	_put_fac(sim, pid, data, "relief_xc")
	sim.cmd_relief_work(pid)
	var dis := sim._active_disaster("xuchang")
	check(int(od["done"]) == 1 and RulesShop.count_item(ch["bag"], 26022) == 9, "做 1 次: 進度 1 + 用 1 農藥")
	check(int(ch["sp"]) == 190, "救災扣 SP 10")
	check(absf(float(dis["supply"]["43"]) - 0.865) < 1e-9, "1/10 進度令蝗災 supply 0.85 → 0.865 (減弱)")
	check(_last(msgs).contains("1/10"), "進度訊息 1/10")
	# 做埋 9 次
	for i in 9:
		sim.cmd_relief_work(pid)
	check(int(od["done"]) == 10 and absf(float(dis["supply"]["43"]) - 1.0) < 1e-9, "做完 10 次: 蝗災 supply → 1.0")
	sim.cmd_relief_work(pid)
	check(_last(msgs).contains("做完"), "做完唔可以再做")
	# 覆命: 去錯官宅
	_put_fac(sim, pid, data, "donate_xy")
	sim.cmd_office_turnin(pid)
	check(_last(msgs).contains("返許昌官宅"), "要返接令嗰間官宅覆命")
	# 正確覆命
	_put_fac(sim, pid, data, "donate_xc")
	var pol_before := int(ch["attrs"]["pol"])
	sim.cmd_office_turnin(pid)
	check((sim.player_ch()["office"]["order"] as Dictionary).is_empty(), "覆命清咗官令")
	check(int(ch["fame"]) == fame0 + 10, "覆命名聲 +10")
	var pol_gain := (int(ch["attrs"]["pol"]) - pol_before) * int(data.office["polExpPerPoint"]) + (int(ch.get("polExp", 0)) - pol0)
	check(pol_gain == 20, "覆命政治 exp +20 (實得 %d)" % pol_gain)
	check(int(ch["expert"]["jiuzai"]) == 12, "覆命救災專長 exp 12 (而家=%d)" % int(ch["expert"]["jiuzai"]))
	check(_last(msgs).contains("名聲 +10") and _last(msgs).contains("蝗災"), "覆命訊息")
	sim.cmd_relief_work(pid)
	check(_last(msgs).contains("手上冇救災官令"), "冇官令做唔到救災")


func t_relief_effects(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	# 大規模颶風 → 停 cat 40 進貨，但救災物品豁免
	var dis := _set_disaster(sim, "typhoon", "xuchang", "大", 0)
	dis["shutdownEnd"] = 999
	dis["shutdownCats"] = ["43", "44", "40"]
	var shop := {"name": "工具店", "map": "xuchang", "stock": []}
	check(sim._shop_shutdown_reason(shop, 26001).contains("停止進貨"), "普通 cat 40 貨被停進貨")
	check(sim._shop_shutdown_reason(shop, 26022) == "", "救災物品豁免停進貨")
	# 真買得到
	for s in data.shops:
		if String(s["id"]) == "tool":
			_put(sim, pid, int(s["x"]), int(s["y"]))
	ch["gold"] = 9999
	sim.cmd_buy(pid, 26022)
	check(RulesShop.count_item(ch["bag"], 26022) >= 1, "天災期間照買到農藥")


func _relief_seq(data: GameData) -> String:
	var r := _new(data, 77)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put_fac(sim, pid, data, "donate_xc")
	ch["sp"] = 500
	ch["ap"] = 100
	_set_disaster(sim, "drought", "xuchang", "中", 1)
	sim.cmd_office_relief(pid)
	_put_fac(sim, pid, data, "relief_xc")
	RulesShop.add_item(ch["bag"], 26024, 20)
	for i in 7:
		sim.cmd_relief_work(pid)
	_put_fac(sim, pid, data, "donate_xc")
	sim.cmd_office_turnin(pid)
	for i in 300:
		sim.step()
	return sim.save_string()


func t_relief_save(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put_fac(sim, pid, data, "donate_xc")
	ch["sp"] = 500
	ch["ap"] = 100
	_set_disaster(sim, "drought", "xuchang", "中", 1)
	sim.cmd_office_relief(pid)
	_put_fac(sim, pid, data, "relief_xc")
	RulesShop.add_item(ch["bag"], 26024, 20)
	for i in 3:
		sim.cmd_relief_work(pid)
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	var lod: Dictionary = loaded.player_ch()["office"]["order"]
	check(String(lod["id"]) == "relief" and int(lod["done"]) == 3 and int(lod["need"]) == 20, "存檔: 救災官令進度保留")
	check(loaded.save_string() == s1, "存檔: save→load→save 一致")
	var ldis := loaded._active_disaster("xuchang")
	check(absf(float(ldis["supply"]["43"]) - (0.6 + 0.4 * 3.0 / 20.0)) < 1e-9, "存檔: 天災減弱狀態保留")
	# 舊存檔: 冇 baseSupply → 照做到 (以現 supply 做 base)
	var d: Dictionary = JSON.parse_string(s1)
	for e in d["state"]["disasters"]:
		e.erase("baseSupply")
	var old := Sim.load_string(data, JSON.stringify(d))
	var opid := int(old.state["player_id"])
	_put_fac(old, opid, data, "relief_xc")
	old.cmd_relief_work(opid)
	check(int((old.player_ch()["office"]["order"] as Dictionary)["done"]) == 4, "舊存檔: 冇 baseSupply 照做到 4")
	# 決定性
	check(_relief_seq(data) == _relief_seq(data), "決定性: 救災流程同種子同操作 → 同存檔")


# ================= S08d 名額競爭 (spec 08 §2 / 攻略 sy2_8_3) =================

func t_comp_data(data: GameData) -> void:
	var cfg: Dictionary = data.office["competition"]
	check(bool(cfg["enabled"]) and int(cfg["competitors"]) == 3, "名額競爭: enabled + 每階 3 個 NPC")
	check(int(cfg["minRank"]) == 1 and int(cfg["defenderBonus"]) == 0, "名額競爭: minRank 1 / defenderBonus 0")


func t_comp_rules(data: GameData) -> void:
	var cfg: Dictionary = data.office["competition"]
	var c := RulesTitle.comp_cfg(data.office)
	check(RulesTitle.comp_cfg({}) == {} and c.size() == cfg.size(), "comp_cfg 讀 office.competition")
	check(RulesTitle.comp_score(3000, cfg) == 3000 and RulesTitle.comp_score(3000, {"defenderBonus": 100}) == 3100, "comp_score = 名聲 + defenderBonus")
	check(RulesTitle.npc_score(1000, 0.0, cfg) == 850 and RulesTitle.npc_score(1000, 1.0, cfg) == 1050, "npc_score [npcLo, npcHi]")
	check(RulesTitle.npc_score(3000, 0.5, cfg) == 2850, "npc_score 中位數")
	check(RulesTitle.defend_ok(1000, [900, 1000, 950]) and not RulesTitle.defend_ok(999, [900, 1000, 950]), "defend_ok: 打和都算贏")
	check(RulesTitle.defend_ok(1000, []) == true, "defend_ok 冇挑戰者 = 贏")


func t_comp_claim(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put_fac(sim, pid, data, "donate_xc")
	ch["fame"] = 4000
	ch["gold"] = 5000
	check(not bool(ch.get("titleCompete", false)), "討取前未入競爭系統")
	sim.cmd_claim_title(pid, 6)
	check(int(ch["titleRank"]) == 6 and bool(ch["titleCompete"]), "討取頭銜 → 入名額競爭系統")
	var v := sim.title_contest_view(pid)
	check(bool(v["competing"]) and int(v["competitors"]) == 3 and int(v["rank"]) == 6, "title_contest_view read-model")
	check((v["last"] as Dictionary).is_empty(), "未考驗過 = last 空")


func t_comp_defend(data: GameData) -> void:
	# 必輸: 名望低過最弱挑戰者下限 (0.85 × 3000)
	var a := _new(data)
	var sim: Sim = a[0]
	var ch: Dictionary = a[2]
	var msgs: Array = a[3]
	ch["titleRank"] = 6
	ch["fame"] = 2500
	ch["titleCompete"] = true
	sim._daily_hook(30)
	check(int(ch["titleRank"]) == 5, "守位失敗 → 跌返上一階")
	check(_any(msgs, "守位失敗") and int((ch["titleContest"] as Dictionary)["rank"]) == 6, "失敗訊息 + 記錄原階")
	check(bool((ch["titleContest"] as Dictionary)["won"]) == false, "titleContest.won = false")
	# 必贏: 名望高過最強挑戰者上限 (1.05 × 3000)
	var b := _new(data)
	var sb: Sim = b[0]
	var chb: Dictionary = b[2]
	chb["titleRank"] = 6
	chb["fame"] = 3200
	chb["titleCompete"] = true
	sb._daily_hook(60)
	check(int(chb["titleRank"]) == 6 and bool((chb["titleContest"] as Dictionary)["won"]), "名望夠高 → 守位成功")
	check(((chb["titleContest"] as Dictionary)["npc"] as Array).size() == 3, "3 個挑戰者分數留低")
	# 月中唔考驗
	var c := _new(data)
	var sc: Sim = c[0]
	var chc: Dictionary = c[2]
	chc["titleRank"] = 6
	chc["fame"] = 2500
	chc["titleCompete"] = true
	sc._daily_hook(31)
	check(int(chc["titleRank"]) == 6 and not chc.has("titleContest"), "月中唔考驗")
	# 白身 / 未入系統 唔考驗
	var d := _new(data)
	var sd: Sim = d[0]
	var chd: Dictionary = d[2]
	chd["titleRank"] = 6
	chd["fame"] = 2500
	sd._daily_hook(30)
	check(int(chd["titleRank"]) == 6 and not chd.has("titleContest"), "未經討取嘅頭銜唔競爭 (舊存檔兼容)")
	chd["titleCompete"] = true
	chd["titleRank"] = 0
	sd._daily_hook(60)
	check(int(chd["titleRank"]) == 0, "白身唔考驗")


func t_comp_save(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_put_fac(sim, pid, data, "donate_xc")
	ch["fame"] = 2500
	ch["titleRank"] = 6
	ch["titleCompete"] = true
	sim._daily_hook(30)
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	var lch := loaded.player_ch()
	check(bool(lch["titleCompete"]) and int(lch["titleRank"]) == 5, "存檔: 競爭旗標 + 跌階保留")
	check(int((lch["titleContest"] as Dictionary)["day"]) == 30, "存檔: 上次考驗記錄保留")
	check(loaded.save_string() == s1, "存檔: save→load→save 一致")
	# 舊存檔: 冇 titleCompete / titleContest
	var d: Dictionary = JSON.parse_string(s1)
	for e in d["state"]["ents"].values():
		if e.has("ch"):
			e["ch"].erase("titleCompete")
			e["ch"].erase("titleContest")
	var old := Sim.load_string(data, JSON.stringify(d))
	var opid := int(old.state["player_id"])
	var och := old.player_ch()
	och["titleRank"] = 6
	och["fame"] = 2500
	old._daily_hook(90)
	check(int(och["titleRank"]) == 6 and not old.title_competing(och), "舊存檔: 冇 flag 唔競爭")
	# 舊存檔補討取就入系統
	_put_fac(old, opid, data, "donate_xc")
	och["fame"] = 4000
	och["gold"] = 5000
	old.cmd_claim_title(opid, 7)
	check(old.title_competing(och) and int(och["titleRank"]) == 7, "舊存檔: 重新討取即入競爭系統")


func t_comp_determinism(data: GameData) -> void:
	var a := _new(data, 55)
	var sa: Sim = a[0]
	sa.player_ch()["titleRank"] = 6
	sa.player_ch()["fame"] = 2500
	sa.player_ch()["titleCompete"] = true
	sa._daily_hook(30)
	var b := _new(data, 55)
	var sb: Sim = b[0]
	sb.player_ch()["titleRank"] = 6
	sb.player_ch()["fame"] = 2500
	sb.player_ch()["titleCompete"] = true
	sb._daily_hook(30)
	check(JSON.stringify(sa.player_ch()["titleContest"]) == JSON.stringify(sb.player_ch()["titleContest"]), "決定性: 同 day/rank → 同挑戰者分數")
	check(sa.player_ch()["titleRank"] == sb.player_ch()["titleRank"], "決定性: 同結果")


# ================= S08e 義勇軍成立 + 定居 + 帶兵量 (spec 08 §4~§5 / 攻略 sy2_8_2、sy2_9_19) =================

func t_mil_data(data: GameData) -> void:
	var cfg: Dictionary = data.office["militia"]
	check(int(cfg["minTitleRank"]) == 6 and int(cfg["minFame"]) == 3000, "義勇軍: 頭銜南中郎將 + 名聲 3000")
	check(int(cfg["supporterNeed"]) == 10 and int(cfg["supporterLv"]) == 5 and int(cfg["supporterFavor"]) == 50, "義勇軍: 擁護 10 人 (Lv5/好感50)【自訂】")
	check(int(cfg["fund"]) == 200000 and int(cfg["baseSoldiers"]) == 7000, "義勇軍: 經費 20 萬 + 基本帶兵 7000")
	check(int(cfg["capRank"]) == 51 and int(cfg["capSoldiers"]) == 28000, "義勇軍: 51 階起固定 28000")
	check((cfg["newbieCities"] as Array).size() == 3 and (cfg["newbieCities"] as Array).has("xuchang") and (cfg["newbieCities"] as Array).has("xinye"), "新手城 = 許昌/襄陽/新野")
	var grades: Array = cfg["grades"]
	check(grades.size() == 8 and int((grades[0] as Dictionary)["soldiers"]) == 8000 and int((grades[7] as Dictionary)["soldiers"]) == 1000, "階級帶兵 一品 8000 ~ 八品 1000")
	# 頭銜帶兵 (titles.json soldiers 欄，嚟自攻略 sy2_9_19)
	check(int(data.titles[0]["soldiers"]) == 200 and int(data.titles[5]["soldiers"]) == 1200, "頭銜帶兵: 1 階 200 / 6 階 1200")
	check(int(data.titles[49]["soldiers"]) == 13000 and int(data.titles[59]["soldiers"]) == 28000, "頭銜帶兵: 50 階 13000 / 60 階 28000")


func t_mil_rules(data: GameData) -> void:
	var cfg: Dictionary = data.office["militia"]
	var titles: Array = data.titles
	check(RulesMilitia.cfg(data.office).size() == cfg.size() and RulesMilitia.cfg({}) == {}, "cfg 讀 office.militia")
	check(RulesMilitia.grade_soldiers(cfg, 1) == 8000 and RulesMilitia.grade_soldiers(cfg, 8) == 1000, "grade_soldiers 1/8")
	check(RulesMilitia.grade_soldiers(cfg, 0) == 0 and RulesMilitia.grade_soldiers(cfg, 9) == 0, "grade_soldiers 出界 = 0")
	check(RulesMilitia.grade_name(cfg, 1) == "一品" and RulesMilitia.grade_name(cfg, 8) == "八品", "grade_name")
	check(RulesMilitia.title_soldiers(titles, 6) == 1200 and RulesMilitia.title_soldiers(titles, 50) == 13000, "title_soldiers")
	check(RulesMilitia.title_soldiers(titles, 0) == 0 and RulesMilitia.title_soldiers(titles, 61) == 0, "title_soldiers 白身/出界 = 0")
	# spec §5 例: 征東將軍(50) + 一品 = 28000
	check(RulesMilitia.max_soldiers(titles, cfg, 50, 1, 20, true) == 28000, "帶兵量例題: 50 階 + 一品 = 28000")
	check(RulesMilitia.max_soldiers(titles, cfg, 50, 8, 20, true) == 21000, "50 階 + 八品 = 7000+1000+13000")
	check(RulesMilitia.max_soldiers(titles, cfg, 60, 1, 20, true) == 28000, "51 階起固定 28000 (grade 唔再疊)")
	check(RulesMilitia.max_soldiers(titles, cfg, 50, 1, 20, false) == 0, "未入義勇軍 = 0 帶兵量")
	check(RulesMilitia.max_soldiers(titles, cfg, 6, 1, 4, true) == 0, "唔夠 5 級 = 0")
	check(RulesMilitia.max_soldiers(titles, cfg, 6, 1, 5, true) == 16200, "6 階 + 一品 + 基本 = 7000+8000+1200")
	check(RulesMilitia.is_newbie(cfg, "xuchang") and not RulesMilitia.is_newbie(cfg, "wancheng"), "is_newbie")
	check(RulesMilitia.settle_block(cfg, "", "") != "" and RulesMilitia.settle_block(cfg, "wancheng", "wancheng") != "", "settle_block: 非城/已定居")
	check(RulesMilitia.settle_block(cfg, "wancheng", "xuchang") == "", "settle_block: 換城 OK")
	check(RulesMilitia.invite_block(cfg, 5, 50, false, false) == "", "invite_block: 合資格")
	check(RulesMilitia.invite_block(cfg, 4, 50, false, false) != "", "invite_block: 等級不足")
	check(RulesMilitia.invite_block(cfg, 5, 49, false, false) != "", "invite_block: 好感不足")
	check(RulesMilitia.invite_block(cfg, 5, 50, true, false) != "" and RulesMilitia.invite_block(cfg, 5, 50, false, true) != "", "invite_block: 已擁護/已成立")
	check(RulesMilitia.name_block(cfg, "  ") != "" and RulesMilitia.name_block(cfg, "好長嘅名號超晒字數限制喇真係好長") != "", "name_block: 空/太長")
	check(RulesMilitia.name_block(cfg, " 義軍 ") == "", "name_block: 合資格")
	# found_block 逐條
	var ok := {"titleRank": 6, "fame": 3000, "gold": 200000}
	check(RulesMilitia.found_block(titles, cfg, ok, 10, "wancheng") == "", "found_block: 全條件齊")
	check(RulesMilitia.found_block(titles, cfg, {"titleRank": 5, "fame": 3000, "gold": 200000}, 10, "wancheng") != "", "found_block: 頭銜不足")
	check(RulesMilitia.found_block(titles, cfg, {"titleRank": 6, "fame": 2999, "gold": 200000}, 10, "wancheng") != "", "found_block: 名聲不足")
	check(RulesMilitia.found_block(titles, cfg, {"titleRank": 6, "fame": 3000, "gold": 200000}, 9, "wancheng") != "", "found_block: 擁護不足")
	check(RulesMilitia.found_block(titles, cfg, {"titleRank": 6, "fame": 3000, "gold": 199999}, 10, "wancheng") != "", "found_block: 經費不足")
	check(RulesMilitia.found_block(titles, cfg, ok, 10, "") != "", "found_block: 未定居")
	check(RulesMilitia.found_block(titles, cfg, ok, 10, "xuchang") != "", "found_block: 新手城")
	check(RulesMilitia.found_block(titles, cfg, {"titleRank": 6, "fame": 3000, "gold": 200000, "militia": {"founded": true}}, 10, "wancheng") != "", "found_block: 已成立")


func t_settle(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	check(sim.city_at(sim.ent(pid)) == "xuchang", "玩家開局喺許昌")
	var v0 := sim.settle_view(pid)
	check(String(v0["at"]) == "xuchang" and String(v0["home"]) == "" and (v0["cities"] as Array).size() == 10, "settle_view: 10 個城池 + 未定居")
	# 新手城照定居得 (只係唔可以喺度成立)
	sim.cmd_settle(pid, "xuchang")
	check(String(ch["homeCity"]) == "xuchang" and _last(msgs).contains("新手城"), "定居許昌 OK + 提示新手城")
	sim.cmd_settle(pid, "xuchang")
	check(_last(msgs).contains("已經定居"), "重複定居")
	sim.cmd_settle(pid, "wancheng")
	check(_last(msgs).contains("唔喺"), "唔喺目標城池定居唔到")
	_put_map(sim, pid, data, "wancheng")
	var v1 := sim.settle_view(pid)
	check(String(v1["at"]) == "wancheng", "settle_view at = 宛城")
	sim.cmd_settle(pid, "wancheng")
	check(String(ch["homeCity"]) == "wancheng" and _last(msgs).contains("可以"), "定居宛城 OK (非新手城)")
	var v2 := sim.settle_view(pid)
	check(String(v2["home"]) == "wancheng", "settle_view home = 宛城")


func _support(sim: Sim, pid: int, n: int) -> void:
	for i in n:
		var bid := int((sim.state["bots"] as Array)[i])
		var be := sim.ent(bid)
		be["ch"]["level"] = 5
		be["mem"]["affinity"][str(pid)] = 50
		var pe := sim.ent(pid)
		_put(sim, bid, int(pe["x"]), int(pe["y"]))
		sim.cmd_militia_invite(pid, bid)


func t_mil_invite(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var msgs: Array = r[3]
	sim.add_bots(12)
	var bid := int((sim.state["bots"] as Array)[0])
	var be := sim.ent(bid)
	var pe := sim.ent(pid)
	_put(sim, bid, int(pe["x"]) + 10, int(pe["y"]))
	be["ch"]["level"] = 5
	be["mem"]["affinity"][str(pid)] = 50
	sim.cmd_militia_invite(pid, bid)
	check(_last(msgs).contains("行近"), "太遠遊說唔到")
	_put(sim, bid, int(pe["x"]), int(pe["y"]))
	be["ch"]["level"] = 4
	sim.cmd_militia_invite(pid, bid)
	check(_last(msgs).contains("等級不足"), "居民等級不足")
	be["ch"]["level"] = 5
	be["mem"]["affinity"][str(pid)] = 49
	sim.cmd_militia_invite(pid, bid)
	check(_last(msgs).contains("好感不足"), "居民好感不足")
	be["mem"]["affinity"][str(pid)] = 50
	sim.cmd_militia_invite(pid, bid)
	check(int(sim.militia_view(pid)["supporterCount"]) == 1 and _last(msgs).contains("願意擁護"), "遊說成功: 擁護 1/10")
	sim.cmd_militia_invite(pid, bid)
	check(_last(msgs).contains("已經擁護"), "重複遊說")
	sim.cmd_militia_invite(pid, pid)
	check(_last(msgs).contains("唔係居民"), "玩家唔算居民")
	sim.cmd_militia_invite(pid, 99999)
	check(_last(msgs).contains("搵唔到"), "搵唔到嗰個人")
	sim.militia_view(pid)    # read-model 唔應該整壞 state
	check(int(sim.militia_view(pid)["soldiers"]) == 0, "未成立: 帶兵量 0")


func t_mil_found(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	sim.add_bots(12)
	ch["titleRank"] = 6
	ch["fame"] = 3000
	ch["gold"] = 200000
	ch["homeCity"] = "wancheng"
	ch["level"] = 20
	sim.cmd_militia_found(pid, "", "pw")
	check(_last(msgs).contains("名號"), "名號空唔成立")
	sim.cmd_militia_found(pid, "義軍", "pw")
	check(_last(msgs).contains("擁護者不足") and not bool(sim.militia_view(pid)["founded"]), "擁護者不足唔成立")
	_support(sim, pid, 10)
	var v := sim.militia_view(pid)
	check(int(v["supporterCount"]) == 10, "10 個擁護者")
	var all_ok := true
	for cnd in v["conditions"]:
		if not bool(cnd["ok"]):
			all_ok = false
	check(all_ok, "成立前 4 條件全綠")
	sim.cmd_militia_found(pid, " 忠義軍 ", "secret")
	check(bool(ch["militia"]["founded"]) and String(ch["militia"]["name"]) == "忠義軍", "成立成功 + 名號 trim")
	check(int(ch["gold"]) == 0 and String(ch["militia"]["city"]) == "wancheng" and int(ch["militia"]["grade"]) == 1, "扣 20 萬 + 根據地宛城 + 階級一品")
	check((ch["militia"]["supporters"] as Array).size() == 10, "擁護者自動入會")
	check(_last(msgs).contains("忠義軍") and _last(msgs).contains("宛城"), "成立訊息")
	var v2 := sim.militia_view(pid)
	check(bool(v2["founded"]) and int(v2["soldiers"]) == 16200, "成立後帶兵量 = 7000+8000+1200")
	check(String(v2["gradeName"]) == "一品" and String(v2["cityName"]) == "宛城", "read-model 階級/地名")
	sim.cmd_militia_found(pid, "第二隊", "pw2")
	check(_last(msgs).contains("已經成立"), "唔可以成立第二次")
	# S06c 掛鈎: pre.militia 團體任務而家接得
	var mq: Dictionary = {}
	for q in data.quests:
		if bool((q.get("pre", {}) as Dictionary).get("militia", false)):
			mq = q
			break
	check(not mq.is_empty() and RulesQuest.pre_ok(data, mq, ch), "成立後 pre.militia 團體任務接得")


func t_mil_save(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	sim.add_bots(12)
	ch["titleRank"] = 6
	ch["fame"] = 3000
	ch["gold"] = 200000
	ch["homeCity"] = "wancheng"
	ch["level"] = 20
	_support(sim, pid, 10)
	sim.cmd_militia_found(pid, "忠義軍", "secret")
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	var lch := loaded.player_ch()
	check(bool((lch.get("militia", {}) as Dictionary).get("founded", false)) and String((lch["militia"] as Dictionary)["name"]) == "忠義軍", "存檔: 義勇軍保留")
	check(String(lch.get("homeCity", "")) == "wancheng" and (lch["militia"]["supporters"] as Array).size() == 10, "存檔: 定居 + 擁護者保留")
	check(loaded.save_string() == s1, "存檔: save→load→save 一致")
	check(int(loaded.militia_view(int(loaded.state["player_id"]))["soldiers"]) == 16200, "存檔: 帶兵量重算一致")
	# 舊存檔: 冇 militia / homeCity
	var d: Dictionary = JSON.parse_string(s1)
	for e in d["state"]["ents"].values():
		if e.has("ch"):
			e["ch"].erase("militia")
			e["ch"].erase("homeCity")
	var old := Sim.load_string(data, JSON.stringify(d))
	var opid := int(old.state["player_id"])
	var och := old.player_ch()
	check(String(old.home_city(och)) == "" and not bool(old.militia_view(opid)["founded"]), "舊存檔: 未定居/未成立")
	var omq: Dictionary = {}
	for q in data.quests:
		if bool((q.get("pre", {}) as Dictionary).get("militia", false)):
			omq = q
			break
	check(not RulesQuest.pre_ok(data, omq, och), "舊存檔: 冇 militia 接唔到團體任務")
	# 舊存檔補定居照成立得
	_put_map(old, opid, data, "wancheng")
	old.cmd_settle(opid, "wancheng")
	check(String(och["homeCity"]) == "wancheng", "舊存檔: 補定居")


func t_mil_determinism(data: GameData) -> void:
	var a := _new(data, 99)
	var sa: Sim = a[0]
	var pa: int = a[1]
	var cha: Dictionary = a[2]
	sa.add_bots(12)
	cha["titleRank"] = 6
	cha["fame"] = 3000
	cha["gold"] = 200000
	cha["homeCity"] = "wancheng"
	_support(sa, pa, 10)
	sa.cmd_militia_found(pa, "義軍", "pw")
	var b := _new(data, 99)
	var sb: Sim = b[0]
	var pb: int = b[1]
	var chb: Dictionary = b[2]
	sb.add_bots(12)
	chb["titleRank"] = 6
	chb["fame"] = 3000
	chb["gold"] = 200000
	chb["homeCity"] = "wancheng"
	_support(sb, pb, 10)
	sb.cmd_militia_found(pb, "義軍", "pw")
	check(JSON.stringify(cha["militia"]) == JSON.stringify(chb["militia"]), "決定性: 義勇軍狀態一致")
	check(sa.save_string() == sb.save_string(), "決定性: 同種子同操作 → 同存檔")
