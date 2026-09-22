extends SceneTree
# rules 對拍: 讀 tests/vectors/rules.json (由 tools/export_vectors.ts 由 TS 版產生)
# 跑: Godot --headless --path client --script tests/run_rules.gd   (失敗 exit 1)


func _init() -> void:
	var path := ProjectSettings.globalize_path("res://") + "../tests/vectors/rules.json"
	var vecs: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	var data := GameData.load_all()
	var fails := 0
	for i in vecs.size():
		var v: Dictionary = vecs[i]
		var got: Variant = _call(v, data)
		if not _eq(got, v["expect"]):
			fails += 1
			if fails <= 15:
				print("[FAIL] #%d %s args=%s rng=%s\n   expect=%s\n   got   =%s" % [i, v["fn"], v["args"], v.get("rng", []), v["expect"], got])
	print("[TEST] rules vectors: %d, fail %d" % [vecs.size(), fails])
	quit(1 if fails > 0 else 0)


func _rng(seq: Array) -> Callable:
	var idx := [0]
	return func() -> float:
		var x: float = float(seq[idx[0] % seq.size()])
		idx[0] += 1
		return x


func _call(v: Dictionary, data: GameData) -> Variant:
	var a: Array = v["args"]
	var r: Callable = _rng(v["rng"]) if v.has("rng") else Callable()
	match v["fn"]:
		"attackInterval": return RulesCombat.attack_interval(a[0])
		"playerDef": return RulesCombat.player_def(int(a[0]))
		"calcDamage": return RulesCombat.calc_damage(a[0], a[1], a[2], r)
		"calcMobDamage": return RulesCombat.calc_mob_damage(a[0], a[1], r)
		"hitChance": return RulesCombat.hit_chance(a[0], a[1], a[2])
		"inRange": return RulesCombat.in_range(a[0], a[1], a[2], a[3], a[4])
		"rollDrops": return RulesCombat.roll_drops(a[0], r)
		"rollGold": return RulesCombat.roll_gold(a[0], r)
		"karmaAfterKill": return RulesCombat.karma_after_kill(int(a[0]), a[1])
		"deathExpLoss": return RulesCombat.death_exp_loss(int(a[0]), a[1])
		"rollDeathDrop": return RulesCombat.roll_death_drop(int(a[0]), a[1], r)
		"buyPrice": return RulesShop.buy_price(a[0], a[1])
		"sellPrice": return RulesShop.sell_price(a[0])
		"bag_add":
			var bag: Array = a[0].duplicate(true)
			for op in a[1]:
				RulesShop.add_item(bag, int(op[0]), int(op[1]))
			return bag
		"bag_remove":
			var bag2: Array = a[0].duplicate(true)
			var res: Array = []
			for op in a[1]:
				res.append(RulesShop.remove_item(bag2, int(op[0]), int(op[1])))
			return {"bag": bag2, "results": res}
		"maxHp": return RulesStats.max_hp(int(a[0]), a[1])
		"maxMp": return RulesStats.max_mp(int(a[0]), a[1])
		"maxSp": return RulesStats.max_sp(int(a[0]), a[1])
		"expToNext": return RulesStats.exp_to_next(int(a[0]))
		"attrsAt": return RulesStats.attrs_at(data.classes[a[0]], int(a[1]))
		"createCharacter": return RulesStats.create_character(data, a[0], a[1])
		"gainExp":
			var ch: Dictionary = a[0].duplicate(true)
			var ups := RulesStats.gain_exp(data, ch, int(a[1]))
			return {"ch": ch, "ups": ups}
	push_error("未知 fn: " + String(v["fn"]))
	return null


# 數值容差比較；Dictionary/Array 遞迴
func _eq(x: Variant, y: Variant) -> bool:
	var tx := typeof(x)
	var ty := typeof(y)
	var nx := tx == TYPE_INT or tx == TYPE_FLOAT
	var ny := ty == TYPE_INT or ty == TYPE_FLOAT
	if nx and ny:
		return absf(float(x) - float(y)) < 1e-9
	if tx == TYPE_DICTIONARY and ty == TYPE_DICTIONARY:
		if x.size() != y.size():
			return false
		for k in x:
			if not y.has(k) or not _eq(x[k], y[k]):
				return false
		return true
	if tx == TYPE_ARRAY and ty == TYPE_ARRAY:
		if x.size() != y.size():
			return false
		for i in x.size():
			if not _eq(x[i], y[i]):
				return false
		return true
	return x == y
