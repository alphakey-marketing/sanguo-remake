extends SceneTree
# S08g 測試 (spec 08 §9 民心 + §10 城池法令 / 攻略 sy2_8_14, sy2_8_5 尾)。
# 民心/法令要有城池（城主）先啟動；單機未有佔城系統 → 測試直接 city_gov_init 當佔城。
# 跑: Godot --headless --path client --script tests/run_civic.gd  (失敗 exit 1)

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_morale_data(data)
	t_morale_rules(data)
	t_law_data(data)
	t_law_rules(data)
	t_gate_default(data)
	t_gov_init(data)
	t_tax(data)
	t_law_cmd(data)
	t_morale_daily(data)
	t_pop_flow(data)
	t_market_morale(data)
	t_recruit_mult(data)
	t_fame_gain(data)
	t_shop_law(data)
	t_guard_law(data)
	t_drop_law(data)
	t_save_roundtrip(data)
	t_old_save(data)
	t_determinism(data)
	print("[TEST] civil (morale/law) scenarios: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("[FAIL] " + msg)


func _new(data: GameData, seed: int = 8) -> Array:
	var sim := Sim.new(data, seed)
	var pid := sim.spawn_player("t", "yishi")
	var ch := sim.player_ch()
	ch["level"] = 20
	var msgs: Array = []
	var events: Array = []
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		events.append(ev)
		if String(ev.get("k", "")) == "msg":
			msgs.append(String(ev["text"])))
	return [sim, pid, ch, msgs, events]


func _last(msgs: Array) -> String:
	return String(msgs[-1]) if not msgs.is_empty() else ""


func _any(msgs: Array, sub: String) -> bool:
	for m in msgs:
		if String(m).contains(sub):
			return true
	return false


func _put(sim: Sim, id: int, x: int, y: int) -> void:
	var e := sim.ent(id)
	e["x"] = x
	e["y"] = y
	e["tx"] = x
	e["ty"] = y


func _put_fac(sim: Sim, id: int, data: GameData, key: String) -> void:
	var f: Dictionary = data.facilities[key]
	_put(sim, id, int(f["x"]), int(f["y"]) + 1)


func _put_map(sim: Sim, id: int, data: GameData, map_id: String) -> void:
	var z: Dictionary = data.zone_by_id[map_id]
	_put(sim, id, int(z["x0"]) + 1, int(z["y0"]) + 1)


# 當玩家佔咗某城（城主任命）：定居 + hasCity + 建 gov
func _own(sim: Sim, ch: Dictionary, city: String) -> void:
	ch["homeCity"] = city
	ch["militia"] = {"founded": true, "name": "忠義軍", "password": "x", "city": city, "hasCity": true}
	sim.city_gov_init(city)


# ================= 民心 =================

func t_morale_data(data: GameData) -> void:
	var cfg: Dictionary = data.world["cityMorale"]
	check(int(cfg["initial"]) == 100 and int(cfg["cap"]) == 100, "民心設定 initial/cap = 100")
	check(int((cfg["taxDrop"] as Dictionary)["high"]) == 4 and int((cfg["taxDrop"] as Dictionary)["low"]) == 0, "高稅 −4 / 低稅 0")
	check(bool(cfg.has("famePerMorale")) and bool(cfg.has("monthlyGainCap")) and bool(cfg.has("popLossRate")), "單機化欄齊")


func t_morale_rules(data: GameData) -> void:
	var cfg: Dictionary = data.world["cityMorale"]
	check(RulesCivic.cap(cfg) == 100 and RulesCivic.initial(cfg) == 100, "cap/initial")
	check(RulesCivic.clamp_morale(-5, cfg) == 0 and RulesCivic.clamp_morale(150, cfg) == 100, "民心 clamp 0~100")
	check(RulesCivic.tax_drop("high", cfg) == 4 and RulesCivic.tax_drop("low", cfg) == 0 and RulesCivic.tax_drop("normal", cfg) == 0, "稅率 → 加減")
	# 每 10 名聲 +0.1 = fame × 0.01
	check(absf(RulesCivic.morale_gain(10, 0.0, cfg) - 0.1) < 1e-9, "10 名聲 → +0.1 民心")
	check(absf(RulesCivic.morale_gain(300, 0.0, cfg) - 3.0) < 1e-9, "300 名聲 → +3")
	check(absf(RulesCivic.morale_gain(1000, 0.0, cfg) - 10.0) < 1e-9, "上限 +10/月")
	check(absf(RulesCivic.morale_gain(1000, 9.9, cfg) - 0.1) < 1e-6, "本月已得 9.9 → 淨 +0.1")
	check(absf(RulesCivic.morale_gain(10, 10.0, cfg)) < 1e-9, "滿咗唔再加")
	check(absf(RulesCivic.prod_mult(100, cfg) - 1.0) < 1e-9 and absf(RulesCivic.prod_mult(50, cfg) - 0.5) < 1e-9, "prod = 民心/100")
	check(absf(RulesCivic.recruit_mult(100, cfg) - 1.0) < 1e-9 and absf(RulesCivic.recruit_mult(0, cfg) - float(cfg["recruitFloor"])) < 1e-9, "兵源乘數地板")
	check(RulesCivic.pop_after(80, 800, cfg) == 800, "民心高 → 人口不變")
	check(RulesCivic.pop_after(0, 800, cfg) == 800 - int(round(800 * float(cfg["popLossRate"]))), "民心 0 → 每 100 人口失 popLossRate")


# ================= 法令 =================

func t_law_data(data: GameData) -> void:
	var cfg: Dictionary = data.world["cityLaw"]
	check(int(cfg["apCost"]) == 100 and int(cfg["perMonth"]) == 1, "法令：行動力 100 + 每月 1 次")
	var ids := RulesCivic.law_ids(cfg)
	for want in ["crafts", "guard", "caveShops", "cityPk", "dangerEntry", "cityDrop"]:
		check(ids.has(want), "法令保留 %s" % want)
	check(ids.size() == 6, "6 條法令（spec 頭寫 4 但表 ✔ 6）")


func t_law_rules(data: GameData) -> void:
	var cfg: Dictionary = data.world["cityLaw"]
	var def := RulesCivic.default_laws(cfg)
	check(bool(def["crafts"]) and bool(def["guard"]) and not bool(def["cityPk"]), "預設開關")
	check(RulesCivic.change_block(-1, 5, cfg) == "", "未改過 → 得")
	check(RulesCivic.change_block(29, 30, cfg) == "", "跨月 → 得")
	check(RulesCivic.change_block(5, 6, cfg) != "", "同一曆月改第 2 次 → 唔得")
	check(RulesCivic.change_block(4, 34, cfg) == "", "隔月 → 得")
	check(RulesCivic.ap_cost(cfg) == 100, "ap_cost 100")
	check(RulesCivic.law_def(cfg, "nope").is_empty(), "冇嘅法令 = {}")


# ================= 未佔城 = 零改變 =================

func t_gate_default(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	check(not sim.city_gov_active("xuchang"), "未佔城 → gov 未啟動")
	check(sim.city_morale("xuchang") == 100, "未佔城 → 民心 100")
	check(sim.law_allows("xuchang", "crafts") and sim.law_allows("xuchang", "guard"), "未佔城 → 法令全兼容 true")
	check(sim.city_pop("xuchang") == int(_city(data, "xuchang")["pop"]), "未佔城 → 人口 = world 初值")
	check(sim.civic_fame_gain(ch, 10) == 0.0, "未佔城 → 官令唔加民心")


func t_gov_init(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	_own(sim, ch, "xuchang")
	check(sim.city_gov_active("xuchang"), "佔城後 gov 啟動")
	check(sim.city_morale("xuchang") == 100, "佔城民心初始 100")
	var g := sim.city_gov("xuchang")
	check(String(g["tax"]) == "low" and (g["laws"] as Dictionary).size() == 6, "gov 有 tax/laws 6")
	var v := sim.city_gov_view("xuchang")
	check(bool(v["active"]) and int(v["morale"]) == 100 and (v["laws"] as Array).size() == 6, "city_gov_view read-model")
	check(not sim.city_gov_active("xiangyang"), "只有佔嘅城先啟動")


func t_tax(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	# 未佔城唔設定得
	sim.cmd_city_tax(pid, "high")
	check(String(sim.city_gov("xuchang").get("tax", "")) == "" and _last(msgs).contains("要有城池"), "未佔城設唔到稅率")
	_own(sim, ch, "xuchang")
	sim.cmd_city_tax(pid, "high")
	check(String(sim.city_gov("xuchang")["tax"]) == "high", "設高稅")
	sim.cmd_city_tax(pid, "nope")
	check(String(sim.city_gov("xuchang")["tax"]) == "high" and _last(msgs).contains("冇呢個稅率"), "無效稅率唔變")


func t_law_cmd(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	sim.cmd_city_law(pid, "crafts", false)
	check(_last(msgs).contains("要有城池"), "未佔城改唔到法令")
	_own(sim, ch, "xuchang")
	check(sim.law_allows("xuchang", "crafts"), "初始 crafts 開")
	var ap0 := int(ch["ap"])
	sim.cmd_city_law(pid, "crafts", false)
	check(not sim.law_allows("xuchang", "crafts"), "關 crafts 生效")
	check(int(ch["ap"]) == ap0 - 100, "改法令扣行動力 100")
	# 同月再改 → 唔得、唔扣
	sim.cmd_city_law(pid, "guard", false)
	check(sim.law_allows("xuchang", "guard") and _last(msgs).contains("每月"), "同月第 2 次改唔到")
	check(int(ch["ap"]) == ap0 - 100, "改失敗唔扣行動力")
	# 唔夠行動力
	ch["ap"] = 50
	sim.city_gov("xuchang")["lastLawDay"] = -1
	sim.cmd_city_law(pid, "guard", false)
	check(sim.law_allows("xuchang", "guard") and _last(msgs).contains("行動力不足"), "行動力不足改唔到")
	sim.cmd_city_law(pid, "nope", false)
	check(_last(msgs).contains("冇呢條法令"), "冇嘅法令")
	var v := sim.city_gov_view("xuchang")
	var found := false
	for l in v["laws"]:
		if String(l["id"]) == "crafts" and not bool(l["on"]):
			found = true
	check(found, "view 反映 crafts 關咗")


func t_morale_daily(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	_own(sim, ch, "xuchang")
	sim.cmd_city_tax(int(r[1]), "high")
	# 非初一唔評比
	sim._morale_daily(29)
	check(sim.city_morale("xuchang") == 100, "非初一唔評比")
	# 初一：高稅 → −4
	sim._morale_daily(30)
	check(sim.city_morale("xuchang") == 96, "初一高稅 → 民心 −4")
	sim._morale_daily(60)
	check(sim.city_morale("xuchang") == 92, "再過一個月 → 92")
	# 低稅唔跌
	sim.cmd_city_tax(int(r[1]), "low")
	sim.city_gov("xuchang")["lastLawDay"] = -1
	sim._morale_daily(90)
	check(sim.city_morale("xuchang") == 92, "低稅唔跌")


func t_pop_flow(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	_own(sim, ch, "xuchang")
	var pop0 := sim.city_pop("xuchang")
	sim._morale_daily(30)
	check(sim.city_pop("xuchang") == pop0, "民心高 → 人口唔跌")
	sim.city_morale_set("xuchang", 0)
	sim._morale_daily(60)
	check(sim.city_pop("xuchang") < pop0, "民心 0 → 人口流失")
	check(sim.city_pop("xuchang") == RulesCivic.pop_after(0, pop0, data.world["cityMorale"]), "人口流失公式一致")


func t_market_morale(data: GameData) -> void:
	var r_hi := _new(data, 8)
	var sim_hi: Sim = r_hi[0]
	_own(sim_hi, r_hi[2], "xuchang")
	var r_lo := _new(data, 8)
	var sim_lo: Sim = r_lo[0]
	_own(sim_lo, r_lo[2], "xuchang")
	sim_lo.city_morale_set("xuchang", 0)
	for i in 5:
		sim_hi._market_daily(0)
		sim_lo._market_daily(0)
	var hi := float((sim_hi.state["market"]["xuchang"]["43"] as Dictionary)["stock"])
	var lo := float((sim_lo.state["market"]["xuchang"]["43"] as Dictionary)["stock"])
	check(lo < hi, "民心 0 → 市場 prod 跌（庫存更低）")
	# 未佔城 = 100 → 同 baseline
	var r_def := _new(data, 8)
	var sim_def: Sim = r_def[0]
	for i in 5:
		sim_def._market_daily(0)
	check(absf(float((sim_def.state["market"]["xuchang"]["43"] as Dictionary)["stock"]) - hi) < 1e-6, "未佔城市場 = 民心 100 baseline")


func t_recruit_mult(data: GameData) -> void:
	var cfg: Dictionary = data.world["cityMorale"]
	check(absf(RulesCivic.recruit_mult(50, cfg) - 0.5) < 1e-9, "民心 50 → 徵兵 ×0.5")
	check(absf(RulesCivic.recruit_mult(100, cfg) - 1.0) < 1e-9, "民心 100 → ×1.0")


# ================= 單機化：救災/捐贈 +民心 =================

func t_fame_gain(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	_own(sim, ch, "xuchang")
	sim.city_morale_set("xuchang", 80)
	var g1 := sim.civic_fame_gain(ch, 10)
	check(absf(g1 - 0.1) < 1e-9, "10 名聲 → +0.1")
	check(sim.city_morale("xuchang") == 80, "小數未過半 → round 80")
	var g2 := sim.civic_fame_gain(ch, 100)
	check(absf(g2 - 1.0) < 1e-9 and sim.city_morale("xuchang") == 81, "100 名聲 → +1 → 81")
	# 本月上限
	sim.city_gov("xuchang")["moraleGain"] = 9.9
	var g3 := sim.civic_fame_gain(ch, 1000)
	check(absf(g3 - 0.1) < 1e-6, "本月上限封頂")


# ================= 法令掛鈎 =================

func t_shop_law(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_own(sim, ch, "xuchang")
	_put_fac(sim, pid, data, "forge")
	sim.cmd_city_law(pid, "crafts", false)
	sim.cmd_master_gem(pid, "smithing")
	check(_last(msgs).contains("修藝場"), "crafts 關 → 大宗師封")
	sim.city_gov("xuchang")["lastLawDay"] = -1
	ch["ap"] = 200
	sim.cmd_city_law(pid, "crafts", true)
	sim.cmd_master_gem(pid, "smithing")
	check(not _last(msgs).contains("修藝場"), "crafts 開 → 過到法令閘")


func t_guard_law(data: GameData) -> void:
	# guard 關 → 冇衛兵警告
	var r := _new(data, 3)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var events: Array = r[4]
	_own(sim, ch, "xuchang")
	_put_map(sim, pid, data, "xuchang")
	ch["karma"] = -20000
	sim.city_gov("xuchang")["laws"]["guard"] = false
	sim._city_guard_check()
	var warn := false
	for ev in events:
		if String(ev.get("k", "")) == "guard_warn":
			warn = true
	check(not warn, "guard 關 → 冇衛兵警告")
	# guard 開 → 有警告
	var r2 := _new(data, 3)
	var sim2: Sim = r2[0]
	var pid2: int = r2[1]
	var ch2: Dictionary = r2[2]
	var events2: Array = r2[4]
	_own(sim2, ch2, "xuchang")
	_put_map(sim2, pid2, data, "xuchang")
	ch2["karma"] = -20000
	sim2.city_gov("xuchang")["laws"]["guard"] = true
	sim2._city_guard_check()
	var warn2 := false
	for ev in events2:
		if String(ev.get("k", "")) == "guard_warn":
			warn2 = true
	check(warn2, "guard 開 → 殺人魔有衛兵警告")


func t_drop_law(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	var msgs: Array = r[3]
	_own(sim, ch, "xuchang")
	_put_map(sim, pid, data, "xuchang")
	RulesShop.add_item(ch["bag"], 25001, 5)
	sim.city_gov("xuchang")["laws"]["cityDrop"] = false
	sim.cmd_drop_item(pid, 25001, 2)
	check(RulesShop.count_item(ch["bag"], 25001) == 5 and _last(msgs).contains("城內丟物品"), "cityDrop 關 → 丟唔到")
	sim.city_gov("xuchang")["laws"]["cityDrop"] = true
	sim.cmd_drop_item(pid, 25001, 2)
	check(RulesShop.count_item(ch["bag"], 25001) == 3, "cityDrop 開 → 扣背包")
	var drops := 0
	for e in sim.state["ents"].values():
		if String(e.get("kind", "")) == "dropped":
			drops += 1
	check(drops == 1, "地面多咗一件掉落物")
	# 未佔城 = 照舊可丟
	var r2 := _new(data)
	var sim2: Sim = r2[0]
	var pid2: int = r2[1]
	var ch2: Dictionary = r2[2]
	_put_map(sim2, pid2, data, "xuchang")
	RulesShop.add_item(ch2["bag"], 25001, 5)
	sim2.cmd_drop_item(pid2, 25001, 1)
	check(RulesShop.count_item(ch2["bag"], 25001) == 4, "未佔城 → 照舊丟得")


# ================= 存檔 / 兼容 / 決定性 =================

func t_save_roundtrip(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_own(sim, ch, "xuchang")
	sim.city_morale_set("xuchang", 88)
	sim.cmd_city_tax(pid, "high")
	sim.city_gov("xuchang")["laws"]["crafts"] = false
	sim.city_pop_set("xuchang", 777)
	var s1 := sim.save_string()
	var loaded := Sim.load_string(data, s1)
	check(loaded.city_gov_active("xuchang"), "存檔: gov 保留")
	check(loaded.city_morale("xuchang") == 88, "存檔: 民心保留")
	check(String(loaded.city_gov("xuchang")["tax"]) == "high", "存檔: 稅率保留")
	check(not loaded.law_allows("xuchang", "crafts"), "存檔: 法令關保留")
	check(loaded.city_pop("xuchang") == 777, "存檔: 動態人口保留")
	check(loaded.save_string() == s1, "存檔: save→load→save 一致")


func t_old_save(data: GameData) -> void:
	var r := _new(data)
	var sim: Sim = r[0]
	var ch: Dictionary = r[2]
	_own(sim, ch, "xuchang")
	sim.city_pop_set("xuchang", 700)
	var s1 := sim.save_string()
	var d: Dictionary = JSON.parse_string(s1)
	d["state"].erase("cityGov")
	d["state"].erase("cityPop")
	var old := Sim.load_string(data, JSON.stringify(d))
	check(not old.city_gov_active("xuchang"), "舊存檔: 冇 cityGov → 未啟動")
	check(old.city_morale("xuchang") == 100, "舊存檔: 民心 fallback 100")
	check(old.law_allows("xuchang", "crafts"), "舊存檔: 法令 fallback true")
	check(old.city_pop("xuchang") == int(_city(data, "xuchang")["pop"]), "舊存檔: 人口 fallback world")
	# 舊存檔補佔城照用
	old.city_gov_init("xuchang")
	check(old.city_gov_active("xuchang") and old.city_morale("xuchang") == 100, "舊存檔: 補佔城照啟動")


func _run_seq(data: GameData) -> String:
	var r := _new(data, 77)
	var sim: Sim = r[0]
	var pid: int = r[1]
	var ch: Dictionary = r[2]
	_own(sim, ch, "xuchang")
	sim.cmd_city_tax(pid, "high")
	sim.city_morale_set("xuchang", 60)
	sim.cmd_city_law(pid, "crafts", false)
	sim._morale_daily(30)
	sim.civic_fame_gain(ch, 50)
	sim._morale_daily(60)
	return sim.save_string()


func t_determinism(data: GameData) -> void:
	check(_run_seq(data) == _run_seq(data), "決定性: 同種子同操作 → 同存檔")


func _city(data: GameData, id: String) -> Dictionary:
	for c in data.world["cities"]:
		if String(c["id"]) == id:
			return c
	return {}
