extends "res://sim/sim_skill.gd"
# Sim 繼承鏈 第 7 層: 怪物 AI + 玩家/機械人自動戰鬥 (Step 11 主要改呢度)

# 怪物 AI: 遊蕩 / 仇恨追擊 / 脫戰回歸 / 術法吟唱 (Step 9) / 逃跑 (Step 11)
func _think_mob(m: Dictionary) -> void:
	var s: Dictionary = m["mob"]
	var d: Dictionary = data.monsters[int(s["def"])]
	var tgt := ent(int(s["target"]))
	# 術法怪吟唱中: 停低，tick 到生效；受擊中斷喺 damage() 處理
	if m.has("casting"):
		_resolve_mob_cast(m, s, d, tgt)
		return
	# 逃跑中 (spec 04 §3): 唔打唔追，只顧走；離開 home 超過 leash 就消失
	if s["state"] == "flee":
		var ftgt := ent(int(s["target"]))
		if ftgt.is_empty() or not ftgt.has("ch") or int(ftgt["hp"]) <= 0:
			_erase_flee(m, d)                       # 目標冇咗 = 成功逃咗
			return
		if maxi(absi(int(m["x"]) - int(s["home_x"])), absi(int(m["y"]) - int(s["home_y"]))) > int(d["leash"]):
			_erase_flee(m, d)                       # 走甩咗
			return
		if RulesSpell.blocks_move(m.get("status", {}), tick):
			return                                  # 中邪: 郁唔到
		var away := Vector2i(signi(int(m["x"]) - int(ftgt["x"])), signi(int(m["y"]) - int(ftgt["y"])))
		var spd := 2 if tick % 2 == 0 else 1       # 移速 ×1.5 (double-move 一半機率)
		var nx := int(m["x"]) + away.x
		var ny := int(m["y"]) + away.y
		if spd == 2 and is_free(nx + away.x, ny) and is_free(nx, ny + away.y):
			nx += away.x
			ny += away.y
		m["tx"] = nx if is_free(nx, ny) else int(m["x"])
		m["ty"] = ny if is_free(nx, ny) else int(m["y"])
		return
	if s["state"] == "chase":
		var lost := tgt.is_empty() or not tgt.has("ch") or int(tgt["hp"]) <= 0 \
			or maxi(absi(int(m["x"]) - int(s["home_x"])), absi(int(m["y"]) - int(s["home_y"]))) > int(d["leash"])
		if lost:
			s["state"] = "return"
			s["target"] = 0
			m["tx"] = s["home_x"]
			m["ty"] = s["home_y"]
			return
		if RulesCombat.in_range(m["x"], m["y"], tgt["x"], tgt["y"]):
			m["tx"] = m["x"]
			m["ty"] = m["y"]
			# 術法怪: 喺術法距離內就吟唱 (有冷卻)
			var spell_id := str(d.get("spell", ""))
			if spell_id != "" and tick >= int(s.get("next_spell", 0)):
				var sdef: Dictionary = data.spell_by_id.get(spell_id, {})
				if not sdef.is_empty() and RulesCombat.in_range(m["x"], m["y"], tgt["x"], tgt["y"], float(sdef["range"])):
					m["casting"] = {"spell": spell_id, "target": int(tgt["id"]), "done_at": tick + int(sdef["castTicks"])}
					_emit({"k": "cast_start", "src": m["id"], "dst": int(tgt["id"]),
						"book": int(sdef.get("item", 0)), "ticks": int(sdef["castTicks"])})
					return
			if tick >= int(s["next_atk"]):
				s["next_atk"] = tick + int(d["atkInterval"])
				var pch: Dictionary = tgt["ch"]
				# 輔助石: 玩家物防 %/flat + 物迴避 % (Step 10, spec 02 §4)；防具: 物防/物迴避/物理受擊減少 (Step 11.6, spec 02 §9)
				var jb := _jewel_bonus(pch)
				var ab := _armor_bonus(pch)
				var caps: Dictionary = data.equip_cfg["caps"]
				var pdef := RulesCombat.player_def(int(pch["level"])) + int(jb.get("defFlat", 0)) + int(ab["def"])
				var pd := pdef * RulesSpell.def_mult(pch.get("status", {}), tick) * (1.0 + float(jb.get("defPct", 0.0)))
				if rng.next() < RulesEquip.evade_chance(int(ab["evade"]), float(jb.get("evadePct", 0.0)), int(caps["evadePct"])):
					_emit({"k": "hit", "src": m["id"], "dst": tgt["id"], "dmg": 0})     # 迴避咗
				else:
					var dmg := RulesEquip.reduce_dmg(RulesCombat.calc_mob_damage(d["atk"], pd, rng_fn), int(ab["dmgRed"]), int(caps["dmgRedPct"]))
					_emit({"k": "hit", "src": m["id"], "dst": tgt["id"], "dmg": dmg})
					damage(tgt, dmg, m)
		else:
			if not RulesSpell.blocks_move(m.get("status", {}), tick):   # 中邪定身: 唔可以追
				m["tx"] = tgt["x"]
				m["ty"] = tgt["y"]
		return
	if s["state"] == "return":
		m["hp"] = mini(int(m["max_hp"]), int(m["hp"]) + int(ceil(int(m["max_hp"]) / 20.0)))    # 脫戰回血
		if int(m["x"]) == int(s["home_x"]) and int(m["y"]) == int(s["home_y"]):
			s["state"] = "wander"
		return
	if RulesSpell.blocks_move(m.get("status", {}), tick):   # 中邪: 遊蕩都要停
		return
	# wander: 搵仇恨目標，否則隨機遊蕩
	if int(d["aggroRange"]) > 0:
		var best := {}
		var best_d := 1 << 30
		for p in ents.values():
			if not p.has("ch") or int(p["hp"]) <= 0:
				continue
			var dist := maxi(absi(int(p["x"]) - int(m["x"])), absi(int(p["y"]) - int(m["y"])))
			if dist <= int(d["aggroRange"]) and dist < best_d:
				best = p
				best_d = dist
		if not best.is_empty():
			s["state"] = "chase"
			s["target"] = best["id"]
			return
	if int(m["x"]) == int(m["tx"]) and int(m["y"]) == int(m["ty"]) and rng.next() < 0.05:
		var nx := int(s["home_x"]) + rng.below(7) - 3
		var ny := int(s["home_y"]) + rng.below(7) - 3
		if is_free(nx, ny):
			m["tx"] = nx
			m["ty"] = ny


# 玩家/機械人自動追擊 + 出手；吟唱中一律停低等生效
func _think_player(p: Dictionary) -> void:
	if p.has("casting"):
		_resolve_cast(p)
		return
	if int(p["atk_target"]) == 0 or not p.has("ch"):
		return
	var t := ent(int(p["atk_target"]))
	var ch: Dictionary = p["ch"]
	if t.is_empty() or int(t["hp"]) <= 0 or int(p["hp"]) <= 0:
		p["atk_target"] = 0
		return
	if not RulesCombat.in_range(p["x"], p["y"], t["x"], t["y"]):
		if not RulesSpell.blocks_move(ch.get("status", {}), tick):   # 中邪定身: 唔可以追
			_set_dest(p, int(t["x"]), int(t["y"]), CHASE_CAP)          # 被擋就 A* 繞 (spec 12 §3)
		return
	p["tx"] = p["x"]
	p["ty"] = p["y"]
	if is_safe(int(p["x"]), int(p["y"])):
		return     # 安全區唔畀出手 (理論上怪唔會入城，呢度做多重保險)
	if tick < int(p["next_atk"]):
		return
	var w: Dictionary = data.weapons.get(int(ch["equip"].get("weapon", 0)), {"power": 0.0, "hit": 45.0})
	p["next_atk"] = tick + RulesCombat.attack_interval(_eff_attr(ch, "agi"))
	# 輔助石命中率 % (effect 13) (Step 10, spec 02 §4)
	var base_hit := RulesCombat.hit_chance(w["hit"], int(ch["level"]), int(t["level"]))
	var hit := base_hit + float(_jewel_bonus(ch).get("hitPct", 0.0))
	if rng.next() >= hit:
		_emit({"k": "hit", "src": p["id"], "dst": t["id"], "dmg": 0})     # miss
		t["mob"]["state"] = "chase"
		t["mob"]["target"] = p["id"]
		return
	var mdef: Dictionary = data.monsters[int(t["mob"]["def"])]
	# 聚力/強力/神力 buff: 物攻 ×1.15/1.3/1.5 (spec 02 §7) + 輔助石物攻 % (effect 7)
	var atk_mult := RulesSpell.atk_mult(ch.get("status", {}), tick)
	atk_mult = atk_mult * (1.0 + float(_jewel_bonus(ch).get("atkPct", 0.0)))
	var eff_str := _eff_attr(ch, "str") + float(_jewel_bonus(ch).get("strFlat", 0))
	var elem_mult := _phys_elem_mult(ch, str(mdef.get("element", "none")))
	var dmg0 := RulesCombat.calc_damage(eff_str, w["power"], mdef["def"], rng_fn, atk_mult, 1.0)
	var dmg := MathX.js_round(dmg0 * elem_mult)
	_emit({"k": "hit", "src": p["id"], "dst": t["id"], "dmg": dmg})
	damage(t, dmg, p)
