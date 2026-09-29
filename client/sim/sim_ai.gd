extends "res://sim/sim_skill.gd"
# Sim 繼承鏈 第 7 層: 怪物 AI + 玩家/機械人自動戰鬥 (Step 11 主要改呢度)

# 怪物 AI: 遊蕩 / 仇恨追擊 / 脫戰回歸 / 術法吟唱 (Step 9) / 逃跑 (Step 11)
func _think_mob(m: Dictionary) -> void:
	var s: Dictionary = m["mob"]
	var d: Dictionary = data.mob_def(int(s["def"]))
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
		# ---- 術法怪 / boss 技能揀選 (S04b, spec 04 §3) ----
		# boss 用 `skills` 表輪流放；其他術法怪用單一 `spell`（有冷卻 next_spell）
		var skills: Array = (d.get("skills", []) as Array)
		var picked := ""
		var picked_i := -1
		var sdef: Dictionary = {}
		if skills.size() > 0:
			var scd: Dictionary = s.get("skill_cd", {})
			var n := int(s.get("skill_i", 0))
			for k in range(skills.size()):
				var i := (n + k) % skills.size()
				var sk: Dictionary = skills[i]
				if tick >= int(scd.get(str(i), 0)):
					picked = str(sk["spell"])
					picked_i = i
					s["skill_i"] = i
					break
			if picked != "":
				sdef = data.spell_by_id.get(picked, {})
		else:
			picked = str(d.get("spell", ""))
			if picked != "":
				sdef = data.spell_by_id.get(picked, {})
				if sdef.is_empty() or tick < int(s.get("next_spell", 0)):
					picked = ""
		# 喺術法距離內就可吟唱（唔使埋到身），吟唱 = 鎖定落點 = 開始時目標企位（走位可躲）
		var in_spell := (not sdef.is_empty()) and RulesCombat.in_range(m["x"], m["y"], tgt["x"], tgt["y"], float(sdef["range"]))
		if picked != "" and not sdef.is_empty() and in_spell:
			m["tx"] = m["x"]
			m["ty"] = m["y"]
			var cs: Dictionary = {"spell": picked, "target": int(tgt["id"]),
				"done_at": tick + int(sdef["castTicks"]), "x": int(tgt["x"]), "y": int(tgt["y"])}
			if picked_i >= 0:
				cs["sk"] = picked_i
			m["casting"] = cs
			_emit({"k": "cast_start", "src": m["id"], "dst": int(tgt["id"]),
				"book": int(sdef.get("item", 0)), "ticks": int(sdef["castTicks"])})
			return
		if bool(d.get("ranged", false)):
			# 術法怪: 唔埋身近戰；喺術距內就停低等冷卻，未到術距先追
			m["tx"] = m["x"] if in_spell else tgt["x"]
			m["ty"] = m["y"] if in_spell else tgt["y"]
			return
		if RulesCombat.in_range(m["x"], m["y"], tgt["x"], tgt["y"]):
			m["tx"] = m["x"]
			m["ty"] = m["y"]
			if tick >= int(s["next_atk"]):
				s["next_atk"] = tick + int(d["atkInterval"])
				var pch: Dictionary = tgt["ch"]
				# 輔助石: 玩家物防 %/flat + 物迴避 % (Step 10, spec 02 §4)；防具: 物防/物迴避/物理受擊減少 (Step 11.6, spec 02 §9)
				var jb := _jewel_bonus(pch)
				var ab := _armor_bonus(pch)
				var caps: Dictionary = data.equip_cfg["caps"]
				var pdef := RulesCombat.player_def(int(pch["level"])) + int(jb.get("defFlat", 0)) + int(ab["def"])
				var pd := pdef * RulesSpell.def_mult(pch.get("status", {}), tick) * (1.0 + float(jb.get("defPct", 0.0)))
				if int(pch.get("mBlockCharges", 0)) > 0:
					pch["mBlockCharges"] = int(pch["mBlockCharges"]) - 1
					_emit({"k": "hit", "src": m["id"], "dst": tgt["id"], "dmg": 0})     # 馬戰「抵擋」擋咗 (Step 17b)
				elif RulesSpell.has(pch.get("status", {}), "mshield", tick):
					_emit({"k": "hit", "src": m["id"], "dst": tgt["id"], "dmg": 0})     # 馬戰「護盾」全防禦 (Step 17b)
				elif rng.next() < RulesEquip.evade_chance(int(ab["evade"]), float(jb.get("evadePct", 0.0)), int(caps["evadePct"])):
					_emit({"k": "hit", "src": m["id"], "dst": tgt["id"], "dmg": 0})     # 迴避咗
				else:
					var dmg := RulesEquip.reduce_dmg(RulesCombat.calc_mob_damage(RulesCombat.debuffed(d["atk"], m.get("beastDebuff", {}), "atk", tick), pd, rng_fn), int(ab["dmgRed"]), int(caps["dmgRedPct"]))
					_emit({"k": "hit", "src": m["id"], "dst": tgt["id"], "dmg": dmg})
					damage(tgt, dmg, m)
		else:
			if not RulesSpell.blocks_move(m.get("status", {}), tick):   # 中邪定身: 唔可以追
				m["tx"] = tgt["x"]
				m["ty"] = tgt["y"]
		return
	if s["state"] == "return":
		m["hp"] = mini(int(m["max_hp"]), int(m["hp"]) + int(ceil(int(m["max_hp"]) / float(data.world["combat"]["returnRegenDiv"]))))    # 脫戰回血
		if int(m["x"]) == int(s["home_x"]) and int(m["y"]) == int(s["home_y"]):
			s["state"] = "wander"
		return
	if RulesSpell.blocks_move(m.get("status", {}), tick):   # 中邪: 遊蕩都要停
		return
	# wander: 搵仇恨目標，否則隨機遊蕩
	var aggro := int(d["aggroRange"])
	if aggro > 0:
		var best := {}
		var best_d := 1 << 30
		var mx := int(m["x"])
		var my := int(m["y"])
		for pid in _actor_ids_on_map(data.map_index(mx, my)):
			var p: Dictionary = ents.get(pid, {})
			if p.is_empty():
				continue
			# 潛行 (巫女): 主動怪唔會揀佢做仇恨目標 (S02c)
			if p.has("ch") and RulesSpell.has(p["ch"].get("status", {}), "stealth", tick):
				continue
			var dist := maxi(absi(int(p["x"]) - mx), absi(int(p["y"]) - my))
			if dist <= aggro and dist < best_d and int(p["hp"]) > 0:
				best = p
				best_d = dist
		if not best.is_empty():
			s["state"] = "chase"
			s["target"] = best["id"]
			return
	var cc: Dictionary = data.world["combat"]
	if int(m["x"]) == int(m["tx"]) and int(m["y"]) == int(m["ty"]) and rng.next() < float(cc["wanderChance"]):
		var wr := int(cc["wanderRadius"])
		var nx := int(s["home_x"]) + rng.below(wr * 2 + 1) - wr
		var ny := int(s["home_y"]) + rng.below(wr * 2 + 1) - wr
		if is_free(nx, ny):
			m["tx"] = nx
			m["ty"] = ny


# 玩家/機械人自動追擊 + 出手；吟唱中一律停低等生效
func _think_player(p: Dictionary) -> void:
	if p.has("casting"):
		_resolve_cast(p)
		return
	if int(p["atk_target"]) == 0 and p.has("goto") and int(p["hp"]) > 0 and not RulesSpell.blocks_move(p["ch"].get("status", {}), tick):
		_goto_tick(p)                # 大地圖自動尋路 (Step 11.7)
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
	var tm: Dictionary = t.get("mob", {})
	if (is_safe(int(p["x"]), int(p["y"])) or is_safe(int(t["x"]), int(t["y"]))) and not tm.has("arena") and not tm.has("quest_boss"):
		if t.get("kind", "") != "mob":     # 城內唔准打人: 攻擊者或目標任何一方喺安全區都唔出手，放棄目標 (捕快/紅名都一樣，等出野外先打)
			p["atk_target"] = 0
		return     # 安全區唔畀出手 (登用擂台 / 任務 PK boss 例外: 丁刺史府, Step 13.5/16) (理論上怪唔會入城，呢度做多重保險)
	if tick < int(p["next_atk"]):
		return
	# 騎乘 + 裝備馬戰兵器 = 唔使落馬，用馬戰兵器出手【原】(Step 17b)；否則落馬用一般武器
	var mounted_combat := is_riding(ch) and _mount_weapon_type(ch) != ""
	if not mounted_combat:
		_mount_drop(p, "attack")
	# ---- 弩箭消耗 (S02c-辯士, spec 02 §6【原】): 用弩射箭要有箭。冇箭 -> 唔出手 (miss 都唔燒箭) ----
	if not mounted_combat and int(data.cats.get(int(ch["equip"].get("weapon", 0)), 0)) == RulesAmmo.NU_WEAPON_CAT:
		if not RulesAmmo.has_arrow(data, ch):
			p["atk_target"] = 0
			_msg(int(p["id"]), "弩冇箭！去商店買箭 / 木匠製箭先用得弩")
			return
	var w: Dictionary = _mount_weapon_wdef(ch) if mounted_combat else _weapon_def(ch)     # 耐久 0 = 威力減半 (Step 12)
	var jb := _jewel_bonus(ch)                 # 每下出手計一次 (唔用 RNG)
	var ab := _armor_bonus(ch)
	p["next_atk"] = tick + RulesCombat.attack_interval(_eff_attr(ch, "agi", ab))
	# 輔助石命中率 % (effect 13) (Step 10, spec 02 §4)
	var base_hit := RulesCombat.hit_chance(w["hit"], int(ch["level"]), int(t["level"]))
	var hit := base_hit + float(jb.get("hitPct", 0.0))
	if rng.next() >= hit:
		_emit({"k": "hit", "src": p["id"], "dst": t["id"], "dmg": 0})     # miss
		if not tm.is_empty():                    # 怪先有仇恨/逃跑 state；NPC 冇 (S03a)
			t["mob"]["state"] = "chase"
			t["mob"]["target"] = p["id"]
		return
	# 弩命中 -> 扣 1 箭（有箭先出到呢步，前面已查）
	if not mounted_combat and int(data.cats.get(int(ch["equip"].get("weapon", 0)), 0)) == RulesAmmo.NU_WEAPON_CAT:
		RulesAmmo.consume_arrow(data, ch, 1)
	# 目標防禦 / 元素: 怪睇 mob_def；NPC(居民/玩家/同伴) 用玩家防禦 + 冇元素 (spec 03 §4)
	var t_def := 0.0
	var t_elem := "none"
	if not tm.is_empty():
		var mdef := data.mob_def(int(t["mob"]["def"]))
		t_def = float(mdef["def"])
		t_elem = str(mdef.get("element", "none"))
	else:
		t_def = float(RulesCombat.player_def(int(t.get("level", 1))))
	# 聚力/強力/神力 buff: 物攻 ×1.15/1.3/1.5 (spec 02 §7) + 輔助石物攻 % (effect 7)
	var atk_mult := RulesSpell.atk_mult(ch.get("status", {}), tick)
	atk_mult = atk_mult * (1.0 + float(jb.get("atkPct", 0.0)))
	# 弩箭威力 (S11c): 武器強度 += 箭威力；傷害 x 箭特效% (有弩先計)
	var w_power := float(w["power"])
	if not mounted_combat and int(data.cats.get(int(ch["equip"].get("weapon", 0)), 0)) == RulesAmmo.NU_WEAPON_CAT:
		var arrow_bonus := RulesAmmo.attack_bonus(data, ch)
		w_power += float(arrow_bonus.get("power", 0.0))
		atk_mult = atk_mult * (1.0 + float(arrow_bonus.get("atk_pct", 0.0)) / 100.0)
	var eff_str := _eff_attr(ch, "str", ab) + float(jb.get("strFlat", 0))
	var elem_mult := _phys_elem_mult(ch, t_elem)
	var dmg0 := RulesCombat.calc_damage(eff_str, w_power, t_def, rng_fn, atk_mult, 1.0)
	var dmg := MathX.js_round(dmg0 * elem_mult)
	_emit({"k": "hit", "src": p["id"], "dst": t["id"], "dmg": dmg})
	if not mounted_combat:
		_wear_weapon_hit(p)                     # 武器出手磨損 (Step 12)
	damage(t, dmg, p)
