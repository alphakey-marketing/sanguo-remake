extends "res://sim/sim_mount.gd"
# Sim 繼承鏈: 戰騎 sim 整合 (S07b, spec 07 §8) — 夾喺 sim_mount 同 sim 之間
# 狀態喺 ch: warBeasts = [戰騎 wb] (最多 3 隻)、beastSeq = uid 計數；每隻 wb 加 where("with"/"stable")/stable/hp/mp/sp
# 出戰中嘅戰騎 = kind "beast" 實體 (跟主人、自動攻擊、吸 exp)；規則/數值喺 rules/war_beast.gd + data/war_beasts.json
# 獲得途徑【待決→推薦方針 (S07b)】: 馬廄「戰騎馴養」(買幼獸)；原版捕獲/拍賣場 → NPC 拍賣場 S07d；怪物掉落唔做 (見 PLAN §4)


func _wbcfg() -> Dictionary:
	return data.war_beasts


func _beasts(ch: Dictionary) -> Array:
	if not ch.has("warBeasts"):
		ch["warBeasts"] = []
	return ch["warBeasts"]


func _beast_by_uid(ch: Dictionary, uid: int) -> Dictionary:
	for wb in ch.get("warBeasts", []):
		if int(wb["uid"]) == uid:
			return wb
	return {}


# 出戰中嘅戰騎 (只有一隻)
func active_beast(ch: Dictionary) -> Dictionary:
	for wb in ch.get("warBeasts", []):
		if String(wb.get("where", "stable")) == "with":
			return wb
	return {}


func _beast_of_owner(owner: Dictionary) -> Dictionary:
	return active_beast(owner.get("ch", {})) if owner.has("ch") else {}


func _wrap_wb(cfg: Dictionary, breed: String, uid: int, lvl: int = 1) -> Dictionary:
	var wb := RulesWarBeast.new_beast(cfg, breed, uid)
	if lvl > 1:                                    # S07d 拍賣場 NPC 戰騎標等級
		RulesWarBeast.gain_exp(cfg, wb, RulesWarBeast.exp_total(cfg, lvl))
	var st := RulesWarBeast.stats_for(cfg, wb)
	wb["where"] = "with"
	wb["stable"] = ""
	wb["home"] = ""
	wb["hp"] = int(st["hpMax"])
	wb["mp"] = int(st["mpMax"])
	wb["sp"] = int(st["spMax"])
	return wb


func _beast_stats(wb: Dictionary) -> Dictionary:
	return RulesWarBeast.stats_for(_wbcfg(), wb)


# ================= 友好特技效果 (S07c) =================
# 出戰戰騎學咗嘅效果集；畀其他 sim 系統經 hook 查 (_friend_effect_active/_bag_cap/_friend_regen_mult)
func _friend_effects(e: Dictionary) -> Dictionary:
	if e.is_empty() or not e.has("ch"):
		return {}
	var wb := active_beast(e["ch"])
	if wb.is_empty():
		return {}
	return RulesWarBeast.active_effects(_wbcfg(), wb)


func _friend_effect_active(e: Dictionary, effect: String) -> bool:
	return bool(_friend_effects(e).get(effect, false))


func _friend_regen_mult(e: Dictionary) -> float:
	if e.is_empty() or not e.has("ch"):
		return 1.0
	return RulesWarBeast.regen_mult(_wbcfg(), active_beast(e["ch"]))


# 霸王熊「背負」: 背包負重上限加成 (底 = world.dropped.capBagWeight)
func _bag_cap(ch: Dictionary) -> int:
	var base := int(data.world.get("dropped", {}).get("capBagWeight", 1000))
	var wb := active_beast(ch)
	if wb.is_empty():
		return base
	return int(MathX.js_round(float(base) * RulesWarBeast.bag_cap_mult(_wbcfg(), wb)))


# 出戰戰騎實體 (owner 嘅 active beast entity)，冇 = {}
func beast_ent(owner_id: int) -> Dictionary:
	for e in ents.values():
		if e.get("kind", "") == "beast" and int(e.get("owner", 0)) == owner_id:
			return e
	return {}


func _spawn_beast_ent(o: Dictionary, wb: Dictionary) -> Dictionary:
	var e := _new_ent(RulesWarBeast.display_name(_wbcfg(), wb), "beast", _free_near(int(o["x"]), int(o["y"])))
	var ch := RulesStats.create_character(data, String(e["name"]).substr(0, 8), "yishi")
	ch["bag"] = []
	ch["gold"] = 0
	_ensure_equip(ch)
	e["ch"] = ch
	e["owner"] = int(o["id"])
	e["uid"] = int(wb["uid"])
	e["next_atk"] = 0
	e["skillCd"] = {}
	_sync_beast_ent(e, wb)
	return e


func _sync_beast_ent(e: Dictionary, wb: Dictionary) -> void:
	var cfg := _wbcfg()
	var st := RulesWarBeast.stats_for(cfg, wb)
	e["max_hp"] = int(st["hpMax"])
	e["max_mp"] = int(st["mpMax"])
	e["level"] = int(wb["level"])
	e["name"] = RulesWarBeast.display_name(cfg, wb)
	e["hp"] = clampi(int(wb.get("hp", st["hpMax"])), 0, int(st["hpMax"]))
	var ch: Dictionary = e["ch"]
	ch["level"] = int(wb["level"])
	ch["hp"] = int(e["hp"])
	ch["mp"] = clampi(int(wb.get("mp", st["mpMax"])), 0, int(st["mpMax"]))
	ch["sp"] = clampi(int(wb.get("sp", st["spMax"])), 0, int(st["spMax"]))


func _remove_beast_ent(owner_id: int) -> void:
	var e := beast_ent(owner_id)
	if not e.is_empty():
		_remove_ent(int(e["id"]))


# ================= 獲得 / 出戰 / 寄馬廄 / 改名 / 加點 =================
func cmd_beast_adopt(id: int, breed: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var key := stable_near(e)
	if key == "":
		return _msg(id, "要去馬廄先馴養到戰騎")
	var cfg := _wbcfg()
	var bd := RulesWarBeast.breed_def(cfg, breed)
	if bd.is_empty() or not bool(bd.get("enabled", false)):
		return _msg(id, "馬廄冇呢隻戰騎")
	var ch: Dictionary = e["ch"]
	var list := _beasts(ch)
	if list.size() >= int(cfg["maxOwned"]):
		return _msg(id, "最多養 %d 隻戰騎" % int(cfg["maxOwned"]))
	var price := int(bd.get("price", 0))
	if int(ch["gold"]) < price:
		return _msg(id, "馴養要 %d 金" % price)
	ch["gold"] = int(ch["gold"]) - price
	var uid := int(ch.get("beastSeq", 0)) + 1
	ch["beastSeq"] = uid
	var wb := _wrap_wb(cfg, breed, uid)
	wb["home"] = key
	if not active_beast(ch).is_empty():          # 已經有一隻出戰 → 新戰騎寄馬廄
		wb["where"] = "stable"
		wb["stable"] = key
		_sync_riding_after_beast(e)
	else:
		_spawn_beast_ent(e, wb)
	list.append(wb)
	_emit({"k": "beast", "dst": id, "act": "adopt", "uid": uid})
	_msg(id, "馴養咗%s（%d 金）%s" % [RulesWarBeast.display_name(cfg, wb), price,
		"，寄咗喺%s" % data.facilities[key]["name"] if String(wb["where"]) == "stable" else "，跟住你"])


# 出戰 (on=true) / 收回馬廄 (on=false)；都要喺馬廄
func cmd_beast_deploy(id: int, uid: int, on: bool) -> void:
	var r := _player_beast(id, uid)
	if r.is_empty():
		return
	var e: Dictionary = r[0]
	var wb: Dictionary = r[1]
	var ch: Dictionary = e["ch"]
	var key := stable_near(e)
	if key == "":
		return _msg(id, "要去馬廄先出戰／收回戰騎")
	if on:
		if String(wb["where"]) == "with":
			return _msg(id, "%s已經跟緊你" % RulesWarBeast.display_name(_wbcfg(), wb))
		var cur := active_beast(ch)
		if not cur.is_empty():                    # 換出戰：舊嘅返馬廄
			cur["where"] = "stable"
			cur["stable"] = key
			_remove_beast_ent(id)
		wb["where"] = "with"
		wb["stable"] = ""
		if String(wb.get("home", "")) == "":
			wb["home"] = key
		var st := _beast_stats(wb)
		wb["hp"] = int(st["hpMax"])
		wb["mp"] = int(st["mpMax"])
		_spawn_beast_ent(e, wb)
		_sync_riding_after_beast(e)
		_msg(id, "%s出戰！" % RulesWarBeast.display_name(_wbcfg(), wb))
	else:
		if String(wb["where"]) != "with":
			return _msg(id, "%s冇喺出戰" % RulesWarBeast.display_name(_wbcfg(), wb))
		wb["where"] = "stable"
		wb["stable"] = key
		_remove_beast_ent(id)
		_msg(id, "%s返咗%s" % [RulesWarBeast.display_name(_wbcfg(), wb), data.facilities[key]["name"]])
	_emit({"k": "beast", "dst": id, "act": "deploy" if on else "stable", "uid": uid})


func cmd_beast_rename(id: int, uid: int, nick: String) -> void:
	var r := _player_beast(id, uid)
	if r.is_empty():
		return
	var e: Dictionary = r[0]
	var wb: Dictionary = r[1]
	wb["nick"] = nick.strip_edges().substr(0, 8)
	if String(wb.get("where", "")) == "with":
		var be := beast_ent(id)
		if not be.is_empty():
			be["name"] = RulesWarBeast.display_name(_wbcfg(), wb)
	_msg(id, "戰騎改名做「%s」" % RulesWarBeast.display_name(_wbcfg(), wb))


func cmd_beast_point(id: int, uid: int, attr: String) -> void:
	var r := _player_beast(id, uid)
	if r.is_empty():
		return
	var wb: Dictionary = r[1]
	var cfg := _wbcfg()
	var why := RulesWarBeast.point_why(cfg, wb, attr)
	if why != "":
		return _msg(id, why)
	RulesWarBeast.spend_point(cfg, wb, attr)
	_msg(id, "%s %s +1（%d）" % [RulesWarBeast.display_name(cfg, wb), cfg["attrNames"][attr], int(wb["attrs"][attr])])


func cmd_beast_train(id: int, uid: int, skill_id: String) -> void:
	var r := _player_beast(id, uid)
	if r.is_empty():
		return
	var wb: Dictionary = r[1]
	var cfg := _wbcfg()
	var why := RulesWarBeast.battle_train_why(cfg, wb, skill_id)
	if why != "":
		return _msg(id, why)
	RulesWarBeast.battle_train(cfg, wb, skill_id)
	var s := RulesWarBeast.battle_skill_def(cfg, String(wb["breed"]), skill_id)
	_msg(id, "%s練成「%s」%d 級" % [RulesWarBeast.display_name(cfg, wb), s["name"], RulesWarBeast.battle_skill_level(wb, skill_id)])


func cmd_beast_friend_train(id: int, uid: int, breed: String, skill_id: String) -> void:
	var r := _player_beast(id, uid)
	if r.is_empty():
		return
	var wb: Dictionary = r[1]
	var cfg := _wbcfg()
	var why := RulesWarBeast.friend_train_why(cfg, wb, breed, skill_id)
	if why != "":
		return _msg(id, why)
	RulesWarBeast.friend_train(cfg, wb, breed, skill_id)
	var s := RulesWarBeast.friend_skill_def(cfg, breed, skill_id)
	_msg(id, "%s學識友好特技「%s」" % [RulesWarBeast.display_name(cfg, wb), s["name"]])


func cmd_beast_sell(id: int, uid: int) -> void:
	var r := _player_beast(id, uid)
	if r.is_empty():
		return
	var e: Dictionary = r[0]
	var wb: Dictionary = r[1]
	var cfg := _wbcfg()
	var why := RulesWarBeast.sell_why(cfg, wb, int(e["ch"]["level"]))
	if why != "":
		return _msg(id, why)
	var price := RulesWarBeast.sell_price(cfg, wb)
	e["ch"]["gold"] = int(e["ch"]["gold"]) + price
	if String(wb["where"]) == "with":
		_remove_beast_ent(id)
	_beasts(e["ch"]).erase(wb)
	_emit({"k": "beast", "dst": id, "act": "sell", "uid": uid})
	_msg(id, "賣咗%s（%d 金）" % [RulesWarBeast.display_name(cfg, wb), price])


func _player_beast(id: int, uid: int) -> Array:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return []
	var wb := _beast_by_uid(e["ch"], uid)
	if wb.is_empty():
		_msg(id, "冇呢隻戰騎")
		return []
	return [e, wb]


# 出戰/收回後：直接攻擊轉用一般武器（戰騎唔影響馬戰兵器）
func _sync_riding_after_beast(_e: Dictionary) -> void:
	pass


# ================= 每 tick / 出戰實體 =================
func _beast_tick() -> void:
	var cfg := _wbcfg()
	var rc: Dictionary = data.recruit_cfg.get("companion", {})
	var regen_ticks := int(rc.get("regenTicks", 30))
	var regen_pct := float(rc.get("regenPct", 0.05))
	for e in ents.values():
		if not e.has("ch") or e["kind"] == "beast":
			continue
		var ch: Dictionary = e["ch"]
		var id := int(e["id"])
		var wb := active_beast(ch)
		var be := beast_ent(id)
		if wb.is_empty() or int(e["hp"]) <= 0:
			if not be.is_empty():
				_remove_ent(int(be["id"]))
			continue
		if be.is_empty():                          # 載入後／跨圖走失 → 重新生成
			be = _spawn_beast_ent(e, wb)
		# 實體 → wb 回寫（受咗傷）
		wb["hp"] = int(be["hp"])
		wb["mp"] = int(be["ch"]["mp"])
		wb["sp"] = int(be["ch"]["sp"])
		# 脫戰回復
		if int(be["atk_target"]) == 0 and tick % regen_ticks == 0:
			var st := RulesWarBeast.stats_for(cfg, wb)
			if int(be["hp"]) < int(st["hpMax"]):
				be["hp"] = mini(int(st["hpMax"]), int(be["hp"]) + maxi(1, int(ceil(int(st["hpMax"]) * regen_pct))))
			if int(be["ch"]["mp"]) < int(st["mpMax"]):
				var mpg := maxi(1, int(ceil(int(st["mpMax"]) * regen_pct * (1.0 + _beast_buff_sum(be, "mpRegen")))))
				be["ch"]["mp"] = mini(int(st["mpMax"]), int(be["ch"]["mp"]) + mpg)
			if int(be["ch"]["sp"]) < int(st["spMax"]):
				be["ch"]["sp"] = mini(int(st["spMax"]), int(be["ch"]["sp"]) + maxi(1, int(ceil(int(st["spMax"]) * regen_pct))))
			wb["hp"] = int(be["hp"])
			wb["mp"] = int(be["ch"]["mp"])
			wb["sp"] = int(be["ch"]["sp"])
		_sync_beast_ent(be, wb)
		_apply_friend_passives(e)
		if _friend_effect_active(e, "auto_loot"):
			_beast_auto_loot(e)


# 友好特技被動效果 (S07c): 九尾狐「金剛」→ 護甲術 (armor1)；「守護」→ 護鏡術 (mirror1)
# 【自訂簡化】出戰期間持續刷新（每 tick 補回狀態 time），等於常駐。
func _apply_friend_passives(e: Dictionary) -> void:
	var fx := _friend_effects(e)
	if fx.is_empty():
		return
	var status: Dictionary = (e["ch"] as Dictionary).get("status", {})
	if bool(fx.get("armor_skill", false)):
		RulesSpell.add_status(status, "armor1", RulesSpell.status_ticks("armor1"), tick)
	if bool(fx.get("mirror_skill", false)):
		RulesSpell.add_status(status, "mirror1", RulesSpell.status_ticks("mirror1"), tick)
	(e["ch"] as Dictionary)["status"] = status


# 殘影豹「撿寶」: 主人附近嘅地面掉落物自動收進背包 (受負重上限限制)
func _beast_auto_loot(o: Dictionary) -> void:
	var rng_cells := int((_wbcfg().get("friendEffects", {}) as Dictionary).get("autoLootRange", 3))
	var drops: Array = []
	for d in ents.values():
		if d.get("kind", "") == "dropped" and int(d.get("hp", 1)) > 0 \
				and RulesCombat.in_range(int(o["x"]), int(o["y"]), int(d["x"]), int(d["y"]), rng_cells):
			drops.append(int(d["id"]))
	if drops.is_empty():
		return
	var oid := int(o["id"])
	var ch: Dictionary = o["ch"]
	var cap := _bag_cap(ch)
	var wfn := func(i: int) -> int: return int(data.weights.get(i, 0))
	var cfg: Dictionary = data.world.get("dropped", {})
	for did in drops:
		var d := ent(int(did))
		if d.is_empty() or d.get("kind", "") != "dropped":
			continue
		var picked: Array = []
		var leftover: Array = []
		for it in d["drop"]["items"] as Array:
			var iid := int(it["id"])
			var n := int(it["n"])
			if RulesShop.bag_fits(ch["bag"], iid, n, wfn, cap):
				RulesShop.add_item(ch["bag"], iid, n)
				picked.append({"id": iid, "n": n})
			else:
				leftover.append({"id": iid, "n": n})
		if picked.is_empty():
			continue
		if leftover.is_empty():
			_remove_ent(int(d["id"]))
		else:
			d["drop"]["items"] = leftover
			d["drop"]["until"] = tick + int(cfg.get("capTicks", 300))
		for it in picked:
			_msg(oid, "戰騎執到 %s ×%d" % [data.names.get(int(it["id"]), str(it["id"])), int(it["n"])])
		_emit({"k": "beast_loot", "dst": oid, "items": picked})


# 無主實體清理 (主人走佬/死)
func _beast_orphans() -> void:
	for e in ents.values():
		if e.get("kind", "") == "beast":
			var o := ent(int(e.get("owner", 0)))
			if o.is_empty() or not o.has("ch") or active_beast(o["ch"]).is_empty():
				_remove_ent(int(e["id"]))


# ================= 出戰 AI: 跟主人 / 自動攻擊 / 戰鬥特技 =================
func _think_beast(e: Dictionary) -> void:
	var o := ent(int(e.get("owner", 0)))
	if o.is_empty() or not o.has("ch") or int(e["hp"]) <= 0:
		return
	var wb := active_beast(o["ch"])
	if wb.is_empty():
		return
	var cfg := _wbcfg()
	var rc: Dictionary = data.recruit_cfg.get("companion", {})
	var omap := map_id_at(int(o["x"]), int(o["y"]))
	if map_id_at(int(e["x"]), int(e["y"])) != omap:      # 跨圖跟主人
		e["atk_target"] = 0
		if not _route_to_map(e, omap):
			var p := _free_near(int(o["x"]), int(o["y"]))
			_put_ent(e, p.x, p.y)
		return
	var d := _cheb(e, o)
	var tgt := ent(int(e["atk_target"]))
	if d > int(rc.get("leashOwner", 12)) or not _hittable(tgt):
		e["atk_target"] = 0
	if int(e["atk_target"]) == 0:
		var ot := ent(int(o["atk_target"]))               # 幫主人打緊嘅目標
		if _hittable(ot):
			e["atk_target"] = int(ot["id"])
		else:
			e["atk_target"] = _attacker_of(o)             # 主人被打 → 護主
	if int(e["atk_target"]) == 0:
		e["atk_target"] = _hunt_target(e, int(rc.get("hunt", 6)))
	if int(e["atk_target"]) == 0:
		if d <= int(rc.get("follow", 2)):
			e["tx"] = e["x"]
			e["ty"] = e["y"]
			e.erase("path")
		else:
			_set_dest(e, int(o["x"]), int(o["y"]), CHASE_CAP)
		return
	var t := ent(int(e["atk_target"]))
	if t.is_empty() or int(t["hp"]) <= 0:
		e["atk_target"] = 0
		return
	if not RulesCombat.in_range(e["x"], e["y"], t["x"], t["y"]):
		_set_dest(e, int(t["x"]), int(t["y"]), CHASE_CAP)
		return
	e["tx"] = e["x"]
	e["ty"] = e["y"]
	_beast_fire(e, wb, t)


func _beast_target_def(t: Dictionary) -> float:
	var base: float
	if t.get("kind", "") == "mob":
		base = float(data.mob_def(int(t["mob"]["def"]))["def"])
	else:
		base = float(RulesCombat.player_def(int(t.get("level", 1))))
	return RulesCombat.debuffed(base, t.get("beastDebuff", {}), "def", tick)


func _beast_fire(e: Dictionary, wb: Dictionary, t: Dictionary) -> void:
	if tick < int(e.get("next_atk", 0)):
		return
	var cfg := _wbcfg()
	var st := RulesWarBeast.stats_for(cfg, wb)
	e["next_atk"] = tick + int(st["interval"])
	e["level"] = int(wb["level"])
	var cd: Dictionary = e.get("skillCd", {})
	var hp_frac := float(e["hp"]) / float(maxi(1, int(e["max_hp"])))
	var pick := RulesWarBeast.pick_skill(cfg, wb, tick, cd, int(e["ch"]["sp"]), hp_frac)
	if pick.is_empty():
		_beast_normal_hit(e, st, t)
	else:
		_beast_use_skill(e, wb, st, t, pick, cd)


func _beast_normal_hit(e: Dictionary, st: Dictionary, t: Dictionary) -> void:
	var hit := RulesCombat.hit_chance(float(st["hit"]), float(e["level"]), float(t.get("level", 1)))
	if rng.next() >= hit:
		_emit({"k": "hit", "src": int(e["id"]), "dst": int(t["id"]), "dmg": 0})
		return
	var atk_mult := RulesSpell.atk_mult((e["ch"] as Dictionary).get("status", {}), tick)
	var dmg := RulesCombat.calc_mob_damage(float(st["atk"]), _beast_target_def(t), rng_fn, atk_mult)
	_emit({"k": "hit", "src": int(e["id"]), "dst": int(t["id"]), "dmg": dmg})
	damage(t, dmg, e)
	_beast_on_deal(e, dmg)


func _beast_use_skill(e: Dictionary, wb: Dictionary, st: Dictionary, t: Dictionary, pick: Dictionary, cd: Dictionary) -> void:
	var s: Dictionary = pick["skill"]
	var sid := String(s["id"])
	var lv := int(pick["level"])
	var kind := String(s["kind"])
	var val := RulesWarBeast.skill_value(s, lv)
	cd[sid] = tick + int(s.get("cd", 0))
	e["skillCd"] = cd
	(e["ch"] as Dictionary)["sp"] = maxi(0, int(e["ch"]["sp"]) - int(s.get("sp", 0)))
	_emit({"k": "beast_skill", "src": int(e["id"]), "skill": sid, "kind": kind, "dst": int(t["id"])})
	if kind == "heal":
		var heal := maxi(1, MathX.js_round(val * float(st["hpMax"])))
		e["hp"] = mini(int(e["max_hp"]), int(e["hp"]) + heal)
		(e["ch"] as Dictionary)["hp"] = int(e["hp"])
		_msg(int(e.get("owner", 0)), "%s「%s」回復 %d HP" % [String(e["name"]), s["name"], heal])
		return
	if kind in ["buff", "debuff"]:
		# S07b/S07c: buff 對自己（atk/def → 現有狀態；spellAtk/lifesteal/mpRegen → beastBuff）；
		# debuff 對目標（存 t.beastDebuff，def/atk 有下游效果）
		var stat := String(s.get("stat", ""))
		var ticks := int(s.get("ticks", 300))
		if kind == "buff":
			var status: Dictionary = e["ch"]["status"]
			if stat == "atk":
				RulesSpell.add_status(status, "power2", ticks, tick)
			elif stat == "def":
				RulesSpell.add_status(status, "armor2", ticks, tick)
			else:
				_beast_add_buff(e, stat, val, ticks)
		else:
			_apply_beast_debuff(t, stat, val, ticks)
		return
	var atk_mult := RulesSpell.atk_mult((e["ch"] as Dictionary).get("status", {}), tick)
	if kind == "mpNuke":
		var mp := int(e["ch"]["mp"])
		(e["ch"] as Dictionary)["mp"] = 0
		_beast_dmg(e, st, t, val, atk_mult, float(mp) * (1.0 + _beast_buff_sum(e, "spellAtk")))
		return
	if kind == "aoe":
		var r := float(s.get("range", 3))
		for o in ents.values():
			if o.get("kind", "") != "mob" or int(o["hp"]) <= 0:
				continue
			if RulesCombat.in_range(t["x"], t["y"], o["x"], o["y"], r):
				_beast_dmg(e, st, t, val, atk_mult, 0)
		return
	if kind == "combo":
		var hits := int(s.get("hits", 2))
		for _i in range(hits):
			if int(t["hp"]) <= 0:
				break
			_beast_dmg(e, st, t, val, atk_mult, 0)
		return
	_beast_dmg(e, st, t, val, atk_mult, 0)


func _beast_dmg(e: Dictionary, st: Dictionary, target: Dictionary, val: float, atk_mult: float, bonus: float) -> void:
	var hit := RulesCombat.hit_chance(float(st["hit"]), float(e["level"]), float(target.get("level", 1)))
	if rng.next() >= hit:
		_emit({"k": "hit", "src": int(e["id"]), "dst": int(target["id"]), "dmg": 0})
		return
	var atk := float(st["atk"]) * val + bonus
	var dmg := RulesCombat.calc_mob_damage(atk, _beast_target_def(target), rng_fn, atk_mult)
	_emit({"k": "hit", "src": int(e["id"]), "dst": int(target["id"]), "dmg": dmg})
	damage(target, dmg, e)
	_beast_on_deal(e, dmg)


# ================= S07b 戰鬥特技 buff/debuff 下游 (beastBuff / beastDebuff) =================
func _beast_add_buff(e: Dictionary, stat: String, pct: float, ticks: int) -> void:
	var bf: Dictionary = e.get("beastBuff", {})
	bf[stat] = {"val": pct, "until": tick + ticks}
	e["beastBuff"] = bf


# 未過期嘅 buff 值 (冇 = 0.0)
func _beast_buff_sum(e: Dictionary, stat: String) -> float:
	var d = (e.get("beastBuff", {}) as Dictionary).get(stat)
	if d is Dictionary and tick < int(d.get("until", 0)):
		return float(d.get("val", 0.0))
	return 0.0


func _apply_beast_debuff(t: Dictionary, stat: String, pct: float, ticks: int) -> void:
	var db: Dictionary = t.get("beastDebuff", {})
	db[stat] = {"val": pct, "until": tick + ticks}
	t["beastDebuff"] = db


# 「聖血」等吸血 buff: 戰騎造成傷害就回血
func _beast_on_deal(e: Dictionary, dmg: int) -> void:
	var ls := _beast_buff_sum(e, "lifesteal")
	if ls <= 0.0 or dmg <= 0:
		return
	var heal := maxi(1, MathX.js_round(float(dmg) * ls))
	e["hp"] = mini(int(e["max_hp"]), int(e["hp"]) + heal)
	(e["ch"] as Dictionary)["hp"] = int(e["hp"])


# ================= 死亡 / 忠誠 / 吸 exp =================
func _kill_beast(t: Dictionary, _by: Dictionary) -> void:
	var o := ent(int(t.get("owner", 0)))
	var wb: Dictionary = {}
	if o.has("ch"):
		wb = _beast_by_uid(o["ch"], int(t.get("uid", 0)))
	_remove_ent(int(t["id"]))
	if wb.is_empty() or o.is_empty():
		return
	var cfg := _wbcfg()
	var name := RulesWarBeast.display_name(cfg, wb)
	var deserted := RulesWarBeast.on_death(cfg, wb)
	var id := int(o["id"])
	if deserted:
		_beasts(o["ch"]).erase(wb)
		_emit({"k": "beast", "dst": id, "act": "desert", "uid": int(wb["uid"])})
		_msg(id, "%s忠誠盡失，離你而去……" % name)
		return
	var st := RulesWarBeast.stats_for(cfg, wb)
	wb["hp"] = int(st["hpMax"])
	wb["mp"] = int(st["mpMax"])
	wb["where"] = "stable"
	wb["stable"] = String(wb.get("home", ""))
	_emit({"k": "beast", "dst": id, "act": "dead", "uid": int(wb["uid"])})
	_msg(id, "%s受咗重傷倒下（忠誠 %d），送返馬廄休養" % [name, int(wb["loyalty"])])


# 主人（或同伴/戰騎）殺怪 → 出戰戰騎吸 exp (sim_combat._kill_mob 叫)
func _beast_on_mob_kill(by: Dictionary, base_exp: int) -> void:
	var owner := _beast_owner_of(by)
	if owner.is_empty() or not owner.has("ch"):
		return
	var wb := active_beast(owner["ch"])
	if wb.is_empty():
		return
	var cfg := _wbcfg()
	var ups := RulesWarBeast.gain_exp(cfg, wb, RulesWarBeast.exp_share(cfg, base_exp))
	var be := beast_ent(int(owner["id"]))
	if not be.is_empty():
		_sync_beast_ent(be, wb)
	if ups > 0:
		_emit({"k": "beast_levelup", "dst": int(owner["id"]), "uid": int(wb["uid"]), "level": int(wb["level"])})
		_msg(int(owner["id"]), "%s升到 %d 級！" % [RulesWarBeast.display_name(cfg, wb), int(wb["level"])])


func _beast_owner_of(by: Dictionary) -> Dictionary:
	if not by.has("ch"):
		return {}
	if by.get("kind", "") == "player":
		return by
	if by.has("gen"):
		return ent(int(by["gen"]["owner"]))
	if by.get("kind", "") == "beast":
		return ent(int(by.get("owner", 0)))
	return {}


# ================= S07d NPC 拍賣場 (spec 07 §9) =================
# 單機化「拍賣/交易戰騎」= NPC 拍賣場，隨機上架座騎/戰騎。state["auction"] = {day, seq, lots}
# 獨立 SimRng (由 game 日驅動)【自訂】→ 唔佔主 rng 流，唔會影響戰鬥/掉落決定性
# lot = {id, kind("mount"/"beast"), breed, price, sex, tamed, level}
func _aucfg() -> Dictionary:
	return _wbcfg().get("auction", {})


func _auction() -> Dictionary:
	if not state.has("auction"):
		state["auction"] = {"day": -1, "seq": 0, "lots": []}
	return state["auction"]


# 每日子時換貨 (sim.gd _daily_hook 叫)
func _auction_daily(day: int) -> void:
	if int(_auction().get("day", -1)) != day:
		_auction_roll(day)


# 讀/買之前確保當日已有貨 (舊存檔 / 未過子時)
func _auction_ensure() -> void:
	var day := int(_clock()["day"])
	if int(_auction().get("day", -1)) != day:
		_auction_roll(day)


func _auction_roll(day: int) -> void:
	var cfg := _aucfg()
	var a := _auction()
	var arng := SimRng.new(900001 + day * 7919)
	var lots: Array = []
	for _i in int(cfg.get("slots", 6)):
		lots.append(_auction_lot(a, arng))
	a["day"] = day
	a["lots"] = lots
	_emit({"k": "auction", "act": "refresh", "day": day, "n": lots.size()})


func _auction_lot(a: Dictionary, arng: SimRng) -> Dictionary:
	var cfg := _aucfg()
	var lo := float(cfg.get("priceMin", 0.8))
	var hi := float(cfg.get("priceMax", 1.5))
	var pf := lo + arng.next() * (hi - lo)
	a["seq"] = int(a.get("seq", 0)) + 1
	var is_beast := arng.next() < float(cfg.get("beastWeight", 0.5))
	if is_beast:
		var breeds := RulesWarBeast.breeds_enabled(_wbcfg())
		var b: Dictionary = breeds[arng.below(breeds.size())]
		var lv := 1
		if arng.next() < float(cfg.get("beastLevelPct", 0.4)):
			lv = 1 + arng.below(maxi(1, int(cfg.get("beastLevelMax", 15))))
		var base := int(b.get("price", 0))
		if base <= 0:
			base = int(_wbcfg().get("sellBase", 500)) * 20
		var price := MathX.js_round(float(base) * (1.0 + 0.08 * float(lv - 1)) * pf)
		return {"id": int(a["seq"]), "kind": "beast", "breed": String(b["id"]), "name": String(b["name"]),
			"price": price, "sex": "", "tamed": false, "level": lv}
	var mcfg: Dictionary = data.mounts
	var mbreeds: Array = mcfg["breeds"]
	var mb: Dictionary = mbreeds[arng.below(mbreeds.size())]
	var tamed := arng.next() < float(cfg.get("tamedPct", 0.5))
	var mbase := int((mcfg["tamed"] as Dictionary)["price"]) if tamed else int(mcfg["foalPrice"])
	var mprice := MathX.js_round(float(mbase) * pf)
	var sex := "m" if arng.next() < float(cfg.get("malePct", 0.3)) else "f"
	var mname := String(mb.get("adult", mb["name"])) if tamed else String(mb["name"])
	return {"id": int(a["seq"]), "kind": "mount", "breed": String(mb["id"]), "name": mname,
		"price": mprice, "sex": sex, "tamed": tamed, "level": 0}


func _auction_find(a: Dictionary, lot_id: int) -> Dictionary:
	for l in a["lots"]:
		if int(l["id"]) == lot_id:
			return l
	return {}


# 買一件拍賣品 (要喺馬廄)
func cmd_auction_buy(id: int, lot_id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var key := stable_near(e)
	if key == "":
		return _msg(id, "要去馬廄先買到拍賣品")
	_auction_ensure()
	var a := _auction()
	var lot := _auction_find(a, lot_id)
	if lot.is_empty():
		return _msg(id, "呢件拍賣品已經冇咗")
	var ch: Dictionary = e["ch"]
	var price := int(lot["price"])
	if int(ch["gold"]) < price:
		return _msg(id, "買%s要 %d 金" % [lot["name"], price])
	if String(lot["kind"]) == "beast":
		var cfg := _wbcfg()
		var blist := _beasts(ch)
		if blist.size() >= int(cfg["maxOwned"]):
			return _msg(id, "最多養 %d 隻戰騎" % int(cfg["maxOwned"]))
		ch["gold"] = int(ch["gold"]) - price
		var uid := int(ch.get("beastSeq", 0)) + 1
		ch["beastSeq"] = uid
		var wb := _wrap_wb(cfg, String(lot["breed"]), uid, int(lot.get("level", 1)))
		wb["home"] = key
		if not active_beast(ch).is_empty():
			wb["where"] = "stable"
			wb["stable"] = key
		else:
			_spawn_beast_ent(e, wb)
		blist.append(wb)
		_emit({"k": "auction", "act": "buy", "dst": id, "kind": "beast", "uid": uid, "price": price})
		_msg(id, "拍賣買咗%s %d 級（%d 金）" % [RulesWarBeast.display_name(cfg, wb), int(wb["level"]), price])
	else:
		var mcfg: Dictionary = data.mounts
		var ms := _mounts(ch)
		if ms.size() >= int(mcfg["maxOwned"]):
			return _msg(id, "最多養 %d 匹馬" % int(mcfg["maxOwned"]))
		ch["gold"] = int(ch["gold"]) - price
		var muid := int(ch.get("mountSeq", 0)) + 1
		ch["mountSeq"] = muid
		var m := RulesMount.new_mount(mcfg, String(lot["breed"]), muid, bool(lot["tamed"]))
		m["sex"] = String(lot["sex"]) if String(lot["sex"]) != "" else "f"
		if not mount_near_me(ch).is_empty():
			m["where"] = "stable"
			m["stable"] = key
		ms.append(m)
		_emit({"k": "auction", "act": "buy", "dst": id, "kind": "mount", "uid": muid, "price": price})
		_msg(id, "拍賣買咗%s（%d 金）" % [RulesMount.display_name(mcfg, m), price])
	a["lots"].erase(lot)


# UI 讀取: 當日拍賣品 + 玩家容量/金錢
func auction_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	_auction_ensure()
	var a := _auction()
	var ch: Dictionary = e["ch"]
	var lots: Array = []
	for l in a["lots"]:
		lots.append({"id": int(l["id"]), "kind": String(l["kind"]), "breed": String(l["breed"]),
			"name": String(l["name"]), "price": int(l["price"]), "sex": String(l.get("sex", "")),
			"tamed": bool(l.get("tamed", false)), "level": int(l.get("level", 0)),
			"afford": int(ch["gold"]) >= int(l["price"])})
	return {"day": int(a["day"]), "lots": lots, "gold": int(ch["gold"]), "stable": stable_near(e),
		"atStable": stable_near(e) != "",
		"mountCount": _mounts(ch).size(), "mountMax": int((data.mounts as Dictionary)["maxOwned"]),
		"beastCount": _beasts(ch).size(), "beastMax": int(_wbcfg()["maxOwned"])}


# ================= UI 讀取 =================
func beast_view(id: int) -> Dictionary:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return {}
	var ch: Dictionary = e["ch"]
	var cfg := _wbcfg()
	var list: Array = []
	for wb in ch.get("warBeasts", []):
		var st := RulesWarBeast.stats_for(cfg, wb)
		var skills: Array = []
		for s in RulesWarBeast.battle_skills_of(cfg, String(wb["breed"])):
			skills.append({"id": String(s["id"]), "name": String(s["name"]), "kind": String(s["kind"]),
				"level": RulesWarBeast.battle_skill_level(wb, String(s["id"])),
				"why": RulesWarBeast.battle_train_why(cfg, wb, String(s["id"]))})
		var friends: Array = []
		for s in RulesWarBeast.friend_skills_of(cfg, String(wb["breed"])):
			friends.append({"id": String(s["id"]), "name": String(s["name"]), "tier": int(s["tier"]),
				"learned": RulesWarBeast.friend_learned(wb, String(s["id"])),
				"cost": RulesWarBeast.friend_cost(cfg, wb, String(wb["breed"]), String(s["id"]))})
		list.append({"uid": int(wb["uid"]), "name": RulesWarBeast.display_name(cfg, wb), "breed": String(wb["breed"]),
			"breedName": String(RulesWarBeast.breed_def(cfg, String(wb["breed"]))["name"]),
			"level": int(wb["level"]), "exp": int(wb["exp"]), "needExp": RulesWarBeast.exp_to_next(cfg, int(wb["level"])),
			"where": String(wb.get("where", "stable")), "stableName": String(data.facilities.get(String(wb.get("stable", "")), {}).get("name", "")),
			"hp": int(wb.get("hp", st["hpMax"])), "hpMax": int(st["hpMax"]), "mp": int(wb.get("mp", st["mpMax"])), "mpMax": int(st["mpMax"]),
			"atk": int(st["atk"]), "def": int(st["def"]), "attrs": (wb["attrs"] as Dictionary).duplicate(),
			"attrPts": int(wb.get("attrPts", 0)), "battlePts": int(wb.get("battlePts", 0)), "friendPts": int(wb.get("friendPts", 0)),
			"loyalty": int(wb.get("loyalty", 0)), "skills": skills, "friends": friends,
			"effects": RulesWarBeast.active_effects(cfg, wb),
			"sellPrice": RulesWarBeast.sell_price(cfg, wb), "sellWhy": RulesWarBeast.sell_why(cfg, wb, int(ch["level"]))})
	return {"list": list, "maxOwned": int(cfg["maxOwned"]), "active": int(active_beast(ch).get("uid", 0)),
		"stable": stable_near(e), "gold": int(ch["gold"]), "breeds": RulesWarBeast.breeds_enabled(cfg),
		"attrs": cfg["attrs"], "attrNames": cfg["attrNames"],
		"effects": RulesWarBeast.active_effects(cfg, active_beast(ch))}