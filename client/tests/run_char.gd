extends SceneTree
# 角色成長場景測試 (spec 01, S01)。跑: Godot --headless --path client --script tests/run_char.gd
# S01a: 安全區自動回復、練兵場小兵免費回 SP、5 級前免費補 HP、HUD 鍵數跟等級

var fails := 0
var total := 0


func _init() -> void:
	var data := GameData.load_all()
	t_safe_regen(data)
	t_wild_no_regen(data)
	t_trainer_restsp(data)
	t_hud_skill_cap()
	t_expert_rules(data)
	t_expert_trade(data)
	t_expert_weather_geo(data)
	print("[TEST] char: %d, fail %d" % [total, fails])
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


func t_safe_regen(data: GameData) -> void:
	var sim := Sim.new(data, 1)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	_put(sim, id, sim.inn_pos.x, sim.inn_pos.y)     # 客棧一帶 = 安全區
	check(sim.is_safe(int(ch_ent(sim, id)["x"]), int(ch_ent(sim, id)["y"])), "客棧係安全區")
	var mhp := RulesStats.max_hp(int(ch["level"]), ch["attrs"])
	ch["hp"] = 1
	var ticks := int(data.world["regen"]["ticks"])
	for i in ticks:
		sim.step()
	check(int(ch["hp"]) > 1, "安全區: 每 %d tick 回 HP" % ticks)
	ch["hp"] = mhp
	for i in ticks:
		sim.step()
	check(int(ch["hp"]) == mhp, "安全區: 回復封頂喺 max_hp")


func t_wild_no_regen(data: GameData) -> void:
	var sim := Sim.new(data, 2)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	_put(sim, id, 60, 60)                           # 野外 (非安全區)
	check(not sim.is_safe(60, 60), "60,60 係野外")
	ch["hp"] = 1
	var ticks := int(data.world["regen"]["ticks"])
	for i in ticks * 2:
		sim.step()
	check(int(ch["hp"]) == 1, "野外: 唔會自動回復")


func ch_ent(sim: Sim, id: int) -> Dictionary:
	return sim.ent(id)


func t_trainer_restsp(data: GameData) -> void:
	var sim := Sim.new(data, 3)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	var f: Dictionary = data.facilities["trainer"]
	_put(sim, id, int(f["x"]), int(f["y"]))
	var msp := RulesStats.max_sp(int(ch["level"]), ch["attrs"])
	ch["sp"] = 1
	sim.cmd_facility(id, "trainer")
	check(int(ch["sp"]) == msp, "練兵場小兵: 免費回滿 SP")
	ch["sp"] = 1
	sim.cmd_facility(id, "trainer")
	check(int(ch["sp"]) == 1, "練兵場小兵: 冷卻中唔可以再用")


func t_hud_skill_cap() -> void:
	check(HudLayout.skill_cap(1) == 4, "5 級前 4 鍵")
	check(HudLayout.skill_cap(4) == 4, "5 級前 4 鍵 (4 級)")
	check(HudLayout.skill_cap(5) == 6, "5 級後 6 鍵")
	check(HudLayout.skill_cap(50) == 6, "5 級後 6 鍵 (高級)")


# ================= S01c 專長 (spec 01 §8) =================
func t_expert_rules(data: GameData) -> void:
	check(RulesExpert.cap_of(data.experts, "yishi", "kaiken") == 4, "義士開墾上限 4")
	check(RulesExpert.cap_of(data.experts, "yishi", "zhaolai") == 2, "義士招徠上限 2")
	check(RulesExpert.cap_of(data.experts, "yishi", "zhentan") == 0, "偵查表冇 = 未解鎖 (0)")
	var le: Array = data.experts["levelExp"]
	check(RulesExpert.level_of_exp(0, le) == 0, "0 exp = 0 級")
	check(RulesExpert.level_of_exp(9, le) == 0, "未夠門檻 = 0 級")
	check(RulesExpert.level_of_exp(10, le) == 1, "夠 10 = 1 級")
	check(RulesExpert.level_of_exp(100, le) == 4, "夠 100 = 頂級 4")
	check(RulesExpert.eff_level(data.experts, "yishi", "zhaolai", 100) == 2, "生效等級封頂喺職業上限 (100exp 本身 4 級但上限 2)")
	check(RulesExpert.eff_level(data.experts, "yishi", "kaiken", 30) == 2, "生效等級: 30exp = 2 級 (上限 4 夠用)")


func t_expert_trade(data: GameData) -> void:
	var sim := Sim.new(data, 11)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	ch["gold"] = 100000
	var item := 0
	for k in data.prices:
		if float(data.prices[k]) > 0:
			item = int(k)
			break
	check(item != 0, "搵到有價道具做測試")
	check(sim.expert_lv(ch, "jiaoyi") == 0, "未學交易 = 0 級")
	var cost0 := RulesShop.buy_price(data.prices[item], float(ch["attrs"]["cha"]), 0, sim.expert_lv(ch, "jiaoyi"))
	RulesExpert.add_exp(ch, data.experts, "jiaoyi", 100)
	check(sim.expert_lv(ch, "jiaoyi") == RulesExpert.cap_of(data.experts, String(ch["classId"]), "jiaoyi"), "加滿 exp = 封頂喺職業上限")
	var cost1 := RulesShop.buy_price(data.prices[item], float(ch["attrs"]["cha"]), 0, sim.expert_lv(ch, "jiaoyi"))
	check(cost1 <= cost0, "交易專長: 買入價唔會貴過未學")
	if sim.expert_lv(ch, "jiaoyi") > 0:
		check(cost1 < cost0, "交易專長: 有級數就買平啲")
	var sell0 := RulesShop.sell_price(data.prices[item], 0)
	var sell1 := RulesShop.sell_price(data.prices[item], sim.expert_lv(ch, "jiaoyi"))
	check(sell1 >= sell0, "交易專長: 賣出價唔會平過未學")


func t_expert_weather_geo(data: GameData) -> void:
	var sim := Sim.new(data, 12)
	var id := sim.spawn_player("t")
	var ch := sim.player_ch()
	check(sim.view_weather().is_empty(), "未學天文 + 冇渾天儀 = 睇唔到天氣")
	check(not sim.geo_unlocked(), "未學地理 = 未解鎖")
	RulesExpert.add_exp(ch, data.experts, "tianwen", 100)
	check(sim.view_weather().is_empty(), "有天文冇渾天儀 = 都係睇唔到")
	RulesShop.add_item(ch["bag"], sim.WEATHER_ITEM, 1)
	var w := sim.view_weather()
	check(not w.is_empty(), "天文 lv≥1 + 帶渾天儀 = 睇到各城天氣")
	check(w.size() == data.world["cities"].size(), "天氣情報涵蓋全部城池")
	RulesExpert.add_exp(ch, data.experts, "dili", 100)
	check(sim.geo_unlocked(), "學咗地理 = 解鎖")
