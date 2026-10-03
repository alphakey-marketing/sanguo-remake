extends SceneTree
# 戰鬥手感 (P3 暴擊/閃避/硬直) + 術法熟練度 (P5) + 絕招屬性/訊息 (P1)
var fails := 0
var total := 0

func check(c: bool, m: String) -> void:
	total += 1
	if not c:
		fails += 1
		print("[FAIL] " + m)

func _init() -> void:
	var data := GameData.load_all()
	# 純函數
	check(is_equal_approx(RulesCombat.crit_chance(0), 0.05), "crit 底 5%")
	check(RulesCombat.crit_chance(9999) == RulesCombat.CRIT_CAP, "crit 夾上限")
	check(RulesCombat.base_dodge(9999) == RulesCombat.DODGE_CAP, "dodge 夾上限")
	check(RulesSpell.prof_level(9) == 0 and RulesSpell.prof_level(10) == 1 and RulesSpell.prof_level(9999) == 10, "熟練等級")
	check(is_equal_approx(RulesSpell.prof_mult(9999), 1.3), "熟練上限 +30%")
	# 絕招資料: 術法職跟智/靈，武職跟力
	for u in data.ultimates:
		var want: String = {"yishi": "str", "shinu": "str", "daoshi": "int", "wunu": "spi", "bianshi": "int", "meinu": "spi"}[u["class"]]
		check(str(u.get("stat", "")) == want, "%s stat=%s" % [u["id"], want])
		check(data.quests.any(func(q): return q["id"] == u["quest"]), "%s 任務 %s 存在" % [u["id"], u["quest"]])
	# 術法熟練: 連放記數 + 升級
	var sim := Sim.new(data, 7)
	var id := sim.spawn_player("t", "daoshi")
	var ch: Dictionary = sim.player_ch()
	var def: Dictionary = data.spell_by_id["ye_s"]
	for i in 10:
		sim._spell_prof_bump(sim.ent(id), def)
	check(int(ch["spellUse"][str(int(def["item"]))]) == 10, "施放記數 10")
	check(sim._spell_prof_mult(sim.ent(id), def) > 1.0, "熟練 +%")
	# 暴擊: 普攻事件有 crit 欄
	print("[TEST] feel: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)
