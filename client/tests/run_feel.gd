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
	# 升級提示 (P4)
	var h := RulesStats.unlock_hints(data, "daoshi", 0, 100)
	check(h.size() > 0 and h.any(func(x): return "絕招" in str(x)), "unlock_hints 有術法+絕招")
	check(RulesStats.unlock_hints(data, "daoshi", 100, 100).is_empty(), "同級冇提示")
	var lv0 := int(ch["level"])
	ch["level"] = lv0 + 5
	sim._levelup_notice(sim.ent(id), lv0)
	check(sim.ent(id) != null, "levelup_notice 唔 crash")
	# 輔助石: 全部 support 石可以裝上玩家 + 效果進 bonus (含 34~38 迴避 / 64 吸取)
	var sim2 := Sim.new(data, 9)
	var id2 := sim2.spawn_player("j", "yishi")
	var ch2: Dictionary = sim2.player_ch()
	var n_eq := 0
	var n_sup := 0
	for jd in data.jewel_by_item.values():
		if str(jd.get("kind", "")) != "support":
			continue
		n_sup += 1
		ch2["bag"].append({"id": int(jd["item"] if jd.has("item") else jd["id"]), "n": 1})
		sim2.cmd_equip_jewel(id2, int(jd["item"] if jd.has("item") else jd["id"]), 0)
		if int(ch2["equip"]["jewels"][0]) == int(jd["item"] if jd.has("item") else jd["id"]):
			n_eq += 1
	check(n_sup > 100 and n_eq == n_sup, "輔助石全部裝得上玩家 (%d/%d)" % [n_eq, n_sup])
	sim2.cmd_equip_jewel(id2, 32307, 0)
	sim2.cmd_equip_jewel(id2, 32056, 1)
	var jbn: Dictionary = sim2._jewel_bonus(ch2)
	check(int(jbn["resist"].get("hex", 0)) == 25, "防邪之石 迴避中邪 25 (%s)" % str(jbn["resist"]))
	check(is_equal_approx(float(jbn["lifeSteal"]), 0.02), "吸魂之石 吸取 2%")
	# 屬性石兩格都認
	var sim3 := Sim.new(data, 11)
	var id3 := sim3.spawn_player("s", "yishi")
	var ch3: Dictionary = sim3.player_ch()
	var stones: Array = []
	for jd in data.jewel_by_item.values():
		if str(jd.get("kind", "")) == "stone" and (str(jd["elem"]) == "fire" or str(jd["elem"]) == "water") and int(jd["pct"]) == 50:
			stones.append(int(jd["id"]))
	for it in stones:
		ch3["bag"].append({"id": it, "n": 1})
	sim3.cmd_equip_jewel(id3, int(stones[0]), 0)
	sim3.cmd_equip_jewel(id3, int(stones[1]), 1)
	check(sim3._equip_stones(ch3).size() == 2, "兩格屬性石都認")
	var wst := sim3._equip_stone(ch3, "fire") if sim3._equip_stone(ch3, "fire").is_empty() == false else sim3._equip_stone(ch3, "water")
	check(not wst.is_empty(), "按術法屬性揀石")
	check(sim3._phys_elem_mult(ch3, "wind") > 1.0 or sim3._phys_elem_mult(ch3, "fire") > 1.0, "兩格石物理相剋有加成")
	# 怪物屬性規則表
	var n_el := 0
	for mid in data.monsters:
		if str(data.monsters[mid].get("element", "none")) in ["wind", "earth", "water", "fire"]:
			n_el += 1
	check(n_el >= 60, "怪物有屬性 (%d)" % n_el)
	check(str(data.mob_def(12022, 0).get("element", "")) == "water", "水鴨=水")
	check(str(data.mob_def(1007, 0).get("element", "")) == "fire", "妖法師仍=火")
	print("[TEST] feel: %d, fail %d" % [total, fails])
	quit(1 if fails > 0 else 0)
