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
	t_tribute(data)
	t_cap(data)
	t_save_roundtrip(data)
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
	RulesShop.add_item(ch["bag"], 25001, 400)
	sim.cmd_city_tribute(pid, [[25001, 250]])
	for i in 500:
		sim.step()
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_run_seq(data) == _run_seq(data), "決定性: 同種子同操作 → 同存檔")