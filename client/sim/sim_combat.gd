extends "res://sim/sim_econ.gd"
# Sim 繼承鏈 第 5 層: 傷害 / 死亡 / 掉落 / 重生排期

# ================= 戰鬥 =================
func damage(t: Dictionary, dmg: int, by: Dictionary) -> void:
	# 吟唱中受擊: 30% 有機率中斷【自訂】(spec 02 §3.1)
	if t.has("casting") and MathX.roll(rng_fn) < 0.3:
		t.erase("casting")
		_emit({"k": "cast_interrupted", "dst": t["id"], "reason": "hit"})
	t["hp"] = maxi(0, int(t["hp"]) - dmg)
	if t["kind"] == "mob" and by.has("ch"):
		t["mob"]["state"] = "chase"
		t["mob"]["target"] = by["id"]
		var md: Dictionary = data.monsters[int(t["mob"]["def"])]
		# 群居怪【自訂】(spec 04 §3): 打 1 隻，附近 GROUP_RANGE 格內同類一齊仇恨
		if dmg > 0 and bool(md.get("groups", false)):
			for o in ents.values():
				if o["kind"] == "mob" and int(o["id"]) != int(t["id"]) \
						and int(o.get("mob", {}).get("def", -1)) == int(t["mob"]["def"]) \
						and String(o["mob"]["state"]) != "flee" and int(o["hp"]) > 0 \
						and RulesCombat.in_range(t["x"], t["y"], o["x"], o["y"], GROUP_RANGE):
					o["mob"]["state"] = "chase"
					o["mob"]["target"] = int(by["id"])
		# 逃跑【自訂】(spec 04 §3): HP<20% 有 15% 機會逃跑；boss/PK 怪 flee=false 唔逃
		if dmg > 0 and int(t["hp"]) > 0 and bool(md.get("flee", true)) \
				and not t["mob"].has("quest_boss") and String(t["mob"]["state"]) != "flee" \
				and int(t["hp"]) < int(t["max_hp"]) * 0.2 and MathX.roll(rng_fn) < 0.15:
			t["mob"]["state"] = "flee"
			t["mob"]["target"] = int(by["id"])
			_emit({"k": "flee", "src": int(t["id"]), "dst": int(by["id"]), "name": str(t["name"])})
	if t.has("ch"):
		t["ch"]["hp"] = t["hp"]
	if int(t["hp"]) > 0:
		return
	if t["kind"] == "mob":
		_kill_mob(t, by)
	elif t.has("ch"):
		_kill_player(t)


func _kill_mob(m: Dictionary, by: Dictionary) -> void:
	var d: Dictionary = data.monsters[int(m["mob"]["def"])]
	# 任務 boss (PK 戰, Step 10): 唔掉落/唔重生，轉交 quest 推進
	var quest_boss := str(m.get("mob", {}).get("quest_boss", ""))
	if quest_boss != "":
		_emit({"k": "mob_died", "dst": int(by.get("id", 0)), "name": str(m["name"])})
		var q := _quest_by_id(quest_boss)
		if not q.is_empty() and by.has("ch"):
			var res := RulesQuest.on_fight_win(data, by["ch"], q)
			if bool(res.get("changed", false)):
				_quest_emit(by, q, res)
		ents.erase(m["id"])
		for e in ents.values():
			if int(e["atk_target"]) == int(m["id"]):
				e["atk_target"] = 0
		return
	if by.has("ch"):
		var w := BotSys.W_SEE_KILL if RulesKarma.tier(int(by["ch"]["karma"])) < 5 else -BotSys.W_SEE_KILL
		_witness_nearby(m, int(by["id"]), "see_kill", w)
	ents.erase(m["id"])
	_schedule_respawn(m, d)
	for e in ents.values():
		if int(e["atk_target"]) == int(m["id"]):
			e["atk_target"] = 0
	if not by.has("ch"):
		return
	var ch: Dictionary = by["ch"]
	var gold := RulesCombat.roll_gold(d["gold"], rng_fn)
	var items := RulesCombat.roll_drops(d["drops"], rng_fn)
	items.append_array(RulesCombat.roll_drops(d.get("rareDrops", []), rng_fn))   # 稀有掉落 (Step 11, spec 11 §2)
	ch["gold"] = int(ch["gold"]) + gold
	for it in items:
		RulesShop.add_item(ch["bag"], int(it), 1)
	ch["karma"] = RulesCombat.karma_after_kill(int(ch["karma"]), d["alignment"])
	var exp_gain := int(d["exp"])
	if by.get("kind", "") == "player":          # 福日【自訂】：生日嗰日練功 exp +10% (spec 01 §1)
		var clk: Dictionary = data.world["clock"]
		exp_gain = MathX.js_round(float(exp_gain) * RulesStats.birthday_exp_mult(int(_clock()["day"]),
			int(clk.get("yearDays", 360)), int(clk.get("monthDays", 30)),
			int(ch.get("birthMonth", 1)), int(ch.get("birthDay", 1))))
	var ups := RulesStats.gain_exp(data, ch, exp_gain)
	if ups > 0:
		_sync_quest_npcs()          # 升級可能改變任務 NPC 可見性 (神秘老人/流浪狗)
	if ups > 0 and by.get("kind", "") == "bot":   # 機械人冇人幫手派點: 直接按建議比例自動派
		RulesStats.auto_assign_points(ch, data.classes[ch["classId"]])
	_sync_stats(by)
	_emit({"k": "kill", "src": by["id"], "dst": m["id"], "exp": int(d["exp"]), "gold": gold, "items": items,
		"lvUp": int(ch["level"]) if ups > 0 else 0})


# 重生排期: 普通怪定時重生，boss 每日一次【自訂】(spec 04 §3)。zone 用 mob spawn 嗰層，免得同 def 多層混亂
func _schedule_respawn(m: Dictionary, d: Dictionary) -> void:
	var zone_id := String(m.get("mob", {}).get("zone", DEFAULT_ZONE))
	var delay := 200
	for sp in data.spawns:
		if int(sp["monster"]) == int(d["id"]) and String(sp.get("zone", DEFAULT_ZONE)) == zone_id:
			delay = int(sp["respawnTicks"])
			break
	if bool(d.get("boss", false)):
		var tpd := int(1440.0 / float(int(data.world["clock"]["gameMinPerTick"])))
		delay = tpd - (tick % tpd)                       # 下一個子時先重生 (每日一次)
	state["respawns"].append({"at": tick + delay, "def": int(d["id"]), "zone": zone_id})


func _kill_player(p: Dictionary) -> void:
	var ch: Dictionary = p["ch"]
	ch["exp"] = maxi(0, int(ch["exp"]) - RulesCombat.death_exp_loss(int(ch["karma"]), RulesStats.exp_to_next(int(ch["level"]))))
	var lost := RulesCombat.roll_death_drop(int(ch["karma"]), ch["bag"], rng_fn)
	if lost > 0:
		RulesShop.remove_item(ch["bag"], lost, 1)
	_cleanup_fused(ch)              # 跌走咗武器 → 清除融合記錄
	_full_heal(ch)
	ch["status"] = {}
	p.erase("casting")
	ch.erase("fusing")
	p["x"] = inn_pos.x
	p["tx"] = inn_pos.x
	p["y"] = inn_pos.y
	p["ty"] = inn_pos.y
	p.erase("path")
	p["atk_target"] = 0
	_sync_stats(p)
	_emit({"k": "die", "dst": p["id"], "lost": lost})


# 逃跑怪消失: 排重生 + 清 atk_target (冇掉落/善惡/經驗)
func _erase_flee(m: Dictionary, d: Dictionary) -> void:
	_schedule_respawn(m, d)
	var id := int(m["id"])
	ents.erase(id)
	for e in ents.values():
		if int(e["atk_target"]) == id:
			e["atk_target"] = 0
