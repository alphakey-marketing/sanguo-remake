extends "res://sim/sim_scene.gd"
# Sim 繼承鏈 第 6 層: 傷害 / 死亡 / 掉落 / 重生排期

# ================= 戰鬥 =================
# 升級提示 (P4): 加咗幾多屬性點、HP/MP 回滿、新解鎖術法/絕招
func _levelup_notice(p: Dictionary, lv0: int) -> void:
	var ch: Dictionary = p["ch"]
	var lv := int(ch["level"])
	var txt := "升級！Lv%d，屬性點 +%d（共 %d），HP/MP/SP 回滿" % [lv, (lv - lv0) * RulesStats.UPGRADE_POINTS, int(ch.get("attrPoints", 0))]
	var hints := RulesStats.unlock_hints(data, str(ch["classId"]), lv0, lv)
	if not hints.is_empty():
		txt += "；" + "、".join(hints)
	_msg(int(p["id"]), txt)


func damage(t: Dictionary, dmg: int, by: Dictionary, crit: bool = false) -> void:
	var cc: Dictionary = data.world["combat"]
	# 吟唱中受擊: castInterruptPct 機率中斷【自訂】(spec 02 §3.1)
	if t.has("casting") and MathX.roll(rng_fn) < float(cc["castInterruptPct"]):
		t.erase("casting")
		_emit({"k": "cast_interrupted", "dst": t["id"], "reason": "hit"})
	if t["kind"] == "player" and dmg > 0 and _friend_effect_active(t, "pain_shield"):   # S07c/U13 戰騎「忠誠」痛楚屏障
		dmg = maxi(1, MathX.js_round(float(dmg) * (1.0 - _friend_pain_shield_pct(t))))
	t["hp"] = maxi(0, int(t["hp"]) - dmg)
	if t["kind"] == "mob" and by.has("id") and dmg > 0:
		# 隊伍經驗池 (S02b): 記低邊個對隻怪出過幾多傷害，死嗰陣按比例分經驗
		var dmg_log: Dictionary = t.get("dmg", {})
		var tid := str(int(by["id"]))
		dmg_log[tid] = int(dmg_log.get(tid, 0)) + dmg
		t["dmg"] = dmg_log
	if t["kind"] == "mob" and by.has("ch"):
		t["mob"]["state"] = "chase"
		t["mob"]["target"] = by["id"]
		if dmg > 0 and int(t["hp"]) > 0:          # 受擊硬直 (P3): 怪下次出手遲啲，暴擊更耐
			var stun := RulesCombat.CRIT_STUN if crit else RulesCombat.HIT_STUN
			t["mob"]["next_atk"] = maxi(int(t["mob"].get("next_atk", 0)), tick + stun)
		var md: Dictionary = data.mob_def(int(t["mob"]["def"]), int(t["mob"].get("lv", 0)))
		# 群居怪【自訂】(spec 04 §3): 打 1 隻，附近 GROUP_RANGE 格內同類一齊仇恨
		if dmg > 0 and bool(md.get("groups", false)):
			for o in ents.values():
				if o["kind"] == "mob" and int(o["id"]) != int(t["id"]) \
						and int(o.get("mob", {}).get("def", -1)) == int(t["mob"]["def"]) \
						and String(o["mob"]["state"]) != "flee" and int(o["hp"]) > 0 \
						and RulesCombat.in_range(t["x"], t["y"], o["x"], o["y"], GROUP_RANGE):
					o["mob"]["state"] = "chase"
					o["mob"]["target"] = int(by["id"])
		# 逃跑【自訂】(spec 04 §3): HP<fleeHpPct 有 fleeChance 機會逃跑；boss/PK 怪 flee=false 唔逃
		if dmg > 0 and int(t["hp"]) > 0 and bool(md.get("flee", true)) \
				and not t["mob"].has("quest_boss") and String(t["mob"]["state"]) != "flee" \
				and int(t["hp"]) < int(t["max_hp"]) * float(cc["fleeHpPct"]) and MathX.roll(rng_fn) < float(cc["fleeChance"]):
			t["mob"]["state"] = "flee"
			t["mob"]["target"] = int(by["id"])
			_emit({"k": "flee", "src": int(t["id"]), "dst": int(by["id"]), "name": str(t["name"])})
	# S03a: 居民被襲擊 -> 反擊 / 逃跑叫衛兵 (spec 03 §2~3)。紅名(殺人魔)亦會主動襲擊玩家 (見 bot_sys.think)
	if t["kind"] == "bot" and by.has("ch") and dmg > 0:
		t["aggressor"] = int(by["id"])              # 記低攻擊者 (反擊/叫衛兵都用)
		if int(t.get("reacted", 0)) == 0:           # 一場打交首次受擊先揀一次反應
			t["reacted"] = 1
			t["atk_target"] = int(by["id"])          # 預設反擊
			if MathX.roll(rng_fn) < float(data.world["bots"]["fleeChance"]):
				t["fleePk"] = true                   # 幾會逃跑: 走去叫衛兵
				t["atk_target"] = 0
	if t.has("ch"):
		t["ch"]["hp"] = t["hp"]
		if dmg > 0:
			_wear_armor_hit(t)          # 防具受擊磨損 (Step 11.6)
	if int(t["hp"]) > 0:
		return
	if t["kind"] == "mob":
		_kill_mob(t, by)
	elif t.get("kind", "") == "bot":
		_kill_bot(t, by)              # S03a: 居民死亡 (唔走返回客棧條玩家死亡流程)
	elif t.get("kind", "") == "beast":
		_kill_beast(t, by)            # S07b: 戰騎倒下 → 忠誠 −1 / 走佬 / 送返馬廄
	elif t.has("ch"):
		_kill_player(t)


# exp_mult: 同伴代打 → 主公分經驗 (Step 13.5)
func _kill_mob(m: Dictionary, by: Dictionary, exp_mult: float = 1.0) -> void:
	var d: Dictionary = data.mob_def(int(m["mob"]["def"]), int(m["mob"].get("lv", 0)))
	# 任務 boss (PK 戰, Step 10): 唔掉落/唔重生，轉交 quest 推進
	var quest_boss := str(m.get("mob", {}).get("quest_boss", ""))
	if quest_boss != "":
		_emit({"k": "mob_died", "dst": int(by.get("id", 0)), "name": str(m["name"])})
		var q := _quest_by_id(quest_boss)
		if not q.is_empty() and by.has("ch"):
			var res := RulesQuest.on_fight_win(data, by["ch"], q)
			if bool(res.get("changed", false)):
				_quest_emit(by, q, res)
		_remove_ent(int(m["id"]))
		return
	var battle_id := str(m.get("mob", {}).get("battle_id", ""))   # 戰役 boss (Step 19): 掉落照常，但唔重生 + 打完自動過層
	var scene_id := str(m.get("mob", {}).get("scene_id", ""))     # S04d 特殊場景怪: 同戰役（唔重生 + 打完過層）
	if by.has("ch"):
		var w := BotSys.W_SEE_KILL if RulesKarma.tier(int(by["ch"]["karma"])) < 5 else -BotSys.W_SEE_KILL
		_witness_nearby(m, int(by["id"]), "see_kill", w)
	_remove_ent(int(m["id"]))
	if battle_id == "" and scene_id == "":
		_schedule_respawn(m, d)
	if not by.has("ch"):
		return
	var ch: Dictionary = by["ch"]
	var gold := RulesCombat.roll_gold(d["gold"], rng_fn)
	var items := RulesCombat.roll_drops(d["drops"], rng_fn)
	items.append_array(RulesCombat.roll_drops(d.get("rareDrops", []), rng_fn))   # 稀有掉落 (Step 11, spec 11 §2)
	ch["gold"] = int(ch["gold"]) + gold
	# S04a (spec 04 §6)【原=跌落地】: 野外地圖物品以「跌落地」實體出現，行埋邊拾取。
	# 戰役/特殊場景落場 (battle_id/scene_id != "") 例外: 過層即傳走，唔返頭執 → 掉寶照直入袋 (保留獎勵)
	if battle_id != "" or scene_id != "":
		for it in items:
			RulesShop.add_item(ch["bag"], int(it), 1)
	elif not items.is_empty():
		var counts := {}
		for it in items:
			counts[int(it)] = int(counts.get(int(it), 0)) + 1
		var di: Array = []
		for k in counts:
			di.append({"id": int(k), "n": int(counts[k])})
		_drop_items(int(m["x"]), int(m["y"]), di)
	ch["karma"] = RulesCombat.karma_after_kill(int(ch["karma"]), d["alignment"])
	var base_exp := MathX.js_round(float(d["exp"]) * exp_mult)
	var dmg_log: Dictionary = m.get("dmg", {})
	if dmg_log.is_empty():           # 冇打過就死 (即死/狀態致死等)：全歸擊殺者
		dmg_log = {str(int(by["id"])): 1}
	var shares := RulesGeneral.team_exp_split(base_exp, dmg_log)   # 隊伍經驗池 (S02b, spec 02 §8)
	var ups := 0
	for id_str in shares.keys():
		var member := ent(int(id_str))
		if member.is_empty() or not member.has("ch"):
			continue
		var mch: Dictionary = member["ch"]
		var e := int(shares[id_str])
		if member.get("kind", "") == "player":
			e = MathX.js_round(float(e) * _friend_exp_mult(member))   # U13 戰騎「神獸/王者」加成友好技
		var mlv0 := int(mch["level"])
		var mups := RulesStats.gain_exp(data, mch, e)
		if mups > 0 and member.get("kind", "") == "player":
			_levelup_notice(member, mlv0)
		if mups > 0 and member.get("kind", "") in ["bot", "gen"]:   # 機械人/同伴冇人幫手派點: 直接按建議比例自動派
			RulesStats.auto_assign_points(mch, data.classes[mch["classId"]])
		_sync_stats(member)
		if int(member["id"]) == int(by["id"]):
			ups = mups
	_comm_on_kill(by, int(m["mob"]["def"]))      # 居民委託打怪計數 (Step 16)
	_beast_on_mob_kill(by, base_exp)              # S07b: 出戰戰騎吸 exp
	if ups > 0:
		_sync_quest_npcs()          # 升級可能改變任務 NPC 可見性 (神秘老人/流浪狗)
	_emit({"k": "kill", "src": by["id"], "dst": m["id"], "exp": int(d["exp"]), "gold": gold, "items": items,
		"lvUp": int(ch["level"]) if ups > 0 else 0})
	if battle_id != "":
		_battle_on_boss_kill(by, battle_id, int(m["mob"].get("battle_floor", 0)))
	if scene_id != "" and bool(m.get("mob", {}).get("scene_boss", false)):
		_scene_on_boss_kill(by, scene_id, int(m["mob"].get("scene_layer", 0)))


# 重生排期: 普通怪定時重生，boss 每日一次【自訂】(spec 04 §3)。zone 用 mob spawn 嗰層，免得同 def 多層混亂
func _schedule_respawn(m: Dictionary, d: Dictionary) -> void:
	var zone_id := String(m.get("mob", {}).get("zone", DEFAULT_ZONE))
	var delay := int(data.world["combat"]["respawnTicksDefault"])
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
	ch["hp"] = 0
	p["hp"] = 0
	var bt: Dictionary = p.get("battle", {})
	var sc: Dictionary = p.get("scene", {})
	# 戰役內陣亡唔跌經驗/物品【原 sy3_8】(除非個別場 dropOnDeath=true, Step 19)；特殊場景 (S04d) 照樣唔跌
	var skip_drop := (not bt.is_empty() and not RulesBattle.drop_on_death(RulesBattle.find(data.battles, String(bt.get("id", "")))) \
		or not sc.is_empty())
	# S03c 死亡道具 (spec 03 §4)【自訂】——死亡流程 6 步順序照 §4.3:
	# 1 扣經驗 → 2 掉物品(幸運符擋) → 3 傳客棧回一半 → 4 目擊好感 → 5 耐久-10% → 6 天譴先判

	# 0. 還魂丹【原】「死亡啱復活」: 死亡即喺客棧復活，物品/經驗照常掉；冇死唔消耗；天譴無效 (唔消耗)
	#    (正常死亡流已經返客棧，故消耗係可見效果；天譴唔行 _kill_player，invariant 由 _tianqian_reprisal 保證)
	var revived := false
	if not bool(ch.get("tianqian", false)):
		if _friend_effect_active(p, "revive_elixir"):        # S07c 殘影豹「還魂」友好技
			revived = true
		elif RulesShop.has_item(ch["bag"], RulesCombat.REVIVE_PILL, 1):
			RulesShop.remove_item(ch["bag"], RulesCombat.REVIVE_PILL, 1)
			revived = true

	# 1. 扣經驗 (護身符 / 戰騎「護身」減半，道具先扣)
	var exp_lost := 0
	var huhushen := false
	var prot_friend := false
	if not skip_drop:
		prot_friend = _friend_effect_active(p, "protect_charm")
		huhushen = prot_friend or RulesShop.has_item(ch["bag"], RulesCombat.PROTECTION_CHARM, 1)
		exp_lost = RulesCombat.death_exp_loss_protected(int(ch["karma"]), RulesStats.exp_to_next(int(ch["level"])), huhushen)
		ch["exp"] = maxi(0, int(ch["exp"]) - exp_lost)
		if huhushen and not prot_friend:
			RulesShop.remove_item(ch["bag"], RulesCombat.PROTECTION_CHARM, 1)

	# 2. 掉物品 (幸運符擋，消耗 1)
	var lucky := false
	var dropped: Array = []
	if not skip_drop:
		# 身上裝備唔會跌【自訂】: 只喺「未裝備」嘅件數入面擲 (spec 03 §4.1「優先裝備槽」→ 單機化唔跌裝)
		var loose: Array = []
		for b in ch["bag"]:
			var free := int(b["n"]) - _equipped_n(ch, int(b["id"]))
			if free > 0:
				loose.append({"id": int(b["id"]), "n": free})
		if _friend_effect_active(p, "lucky_charm"):        # S07c 殘影豹「幸運」友好技
			lucky = true
		elif RulesShop.has_item(ch["bag"], RulesCombat.LUCKY_CHARM, 1):
			lucky = true
			RulesShop.remove_item(ch["bag"], RulesCombat.LUCKY_CHARM, 1)
		else:
			dropped = RulesCombat.roll_death_drop_items(int(ch["karma"]), loose, rng_fn)
			for it in dropped:
				RulesShop.remove_item(ch["bag"], int(it["id"]), int(it["n"]))
			# S04a (spec 04 §6)【原=跌落地】: 死亡掉出嚟嘅物品留喺死位，唔係消失
			if not dropped.is_empty():
				_drop_items(int(p["x"]), int(p["y"]), dropped)
			_cleanup_dur(ch)

	# 3. 復活: 還魂丹/「還魂」友好技 → 即刻返客棧回半血 (唔入倒地)；
	#    否則入「倒地」狀態【自訂新增】: 原地企(死位)，強制 5 秒 → 5~300 秒可回城/復活丹/道士超渡就地復活 → 300 秒到期強制回城
	var die_x := int(p["x"])
	var die_y := int(p["y"])
	var down := false
	if revived:
		_death_return_to_town(p)
	else:
		p["down"] = true
		p["downAt"] = tick
		down = true
	# 4. 目擊死亡: 死亡嗰位附近有記憶表嘅 NPC 記低 (好感微升: 同情 +2【自訂】, spec 03 §4.3)
	_witness_nearby({"x": die_x, "y": die_y}, int(p["id"]), "die", BotSys.W_SEE_DIE)

	# 5. 裝備耐久: 每件扣 10% 耐久 (spec 03 §4.3, 同時係修理服務需求根源) —— 即時，唔理倒唔倒地
	_wear_armor_death(ch)
	_cleanup_fused(ch)              # 跌走咗武器 → 清除融合記錄
	ch["status"] = {}
	p.erase("casting")
	ch.erase("fusing")
	_mount_drop(p, "die")           # 死亡落馬 (Step 17a)
	p.erase("path")
	p.erase("goto")
	p["atk_target"] = 0
	_sync_stats(p)
	var cc: Dictionary = data.world["combat"]
	var self_at := (tick + int(cc.get("playerDownSelfTicks", 50))) if down else 0
	var down_until := (tick + int(cc.get("playerDownMaxTicks", 3000))) if down else 0
	_emit({"k": "die", "dst": p["id"], "exp_lost": exp_lost, "dropped": dropped,
		"revived": revived, "lucky": lucky, "huhushen": huhushen,
		"down": down, "selfAt": self_at, "downUntil": down_until})


# HP/MP/SP 回一半 (聖靈友好技回滿) + 傳返最近客棧 / 戰役報名點 / 場景入口【自訂】
# (還魂丹即死路徑 + 玩家自己「回城復活」/ 逾時強制回城 共用)
func _death_return_to_town(p: Dictionary) -> void:
	var ch: Dictionary = p["ch"]
	if _friend_effect_active(p, "holy_elixir"):    # U13 戰騎「聖靈」友好技: 回滿代替回半
		ch["hp"] = _eff_max_hp(ch)
		ch["mp"] = _eff_max_mp(ch)
		ch["sp"] = _eff_max_sp(ch)
	else:
		_half_heal(ch)
	var bt: Dictionary = p.get("battle", {})
	var sc: Dictionary = p.get("scene", {})
	if bt.is_empty() and sc.is_empty():
		var inn := nearest_inn(map_id_at(int(p["x"]), int(p["y"])))    # 返最近客棧 (過圖次數最少) (Step 11.7)
		p["x"] = int(inn["x"])
		p["tx"] = int(inn["x"])
		p["y"] = int(inn["y"])
		p["ty"] = int(inn["y"])
	else:
		if not bt.is_empty():
			_battle_exit(p, "died")     # 戰役內死亡: 傳送返報名點 + 清晒呢場遺留 boss (Step 19)
		if not sc.is_empty():
			_scene_exit(p, "died")      # S04d: 特殊場景內死亡: 傳送返入口 + 清晒呢場遺留怪


# 倒地狀態清理【自訂新增】: 回城/就地復活共用嘅尾段 (清狀態/goto/atk_target/同步)
func _revive_finish(p: Dictionary) -> void:
	var ch: Dictionary = p["ch"]
	ch["status"] = {}
	p.erase("down")
	p.erase("downAt")
	p.erase("casting")
	p.erase("path")
	p.erase("goto")
	p["atk_target"] = 0
	_sync_stats(p)


# 就地復活【自訂新增】: 原地回滿血，唔傳送 (復活丹 / 道士超渡共用)
func _revive_onsite(p: Dictionary) -> void:
	_full_heal(p["ch"])
	_revive_finish(p)


# 玩家自己撳「回城復活」【自訂新增】: 倒地滿 5 秒 (playerDownSelfTicks) 先准
func cmd_self_revive(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or not bool(e.get("down", false)):
		return
	var cc: Dictionary = data.world["combat"]
	var self_at := int(e.get("downAt", 0)) + int(cc.get("playerDownSelfTicks", 50))
	if tick < self_at:
		return _msg(id, "倒地未夠 5 秒，未可以回城復活")
	_death_return_to_town(e)
	_revive_finish(e)
	_emit({"k": "revive_self", "dst": id, "onsite": false})
	_msg(id, "返到客棧，精神返嚟（HP/MP/SP 回一半）")


# 用「復活丹」就地復活【自訂新增】: 倒地期間隨時可用 (唔使等 5 秒)，消耗 1
func cmd_revive_pill(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or not bool(e.get("down", false)):
		return
	var ch: Dictionary = e["ch"]
	if not RulesShop.has_item(ch["bag"], RulesCombat.ONSITE_REVIVE_PILL, 1):
		return _msg(id, "冇復活丹")
	RulesShop.remove_item(ch["bag"], RulesCombat.ONSITE_REVIVE_PILL, 1)
	_revive_onsite(e)
	_emit({"k": "revive_self", "dst": id, "onsite": true})
	_msg(id, "服咗復活丹，原地起返身（消耗 1）")


# 倒地逾時未救兜底【自訂新增】: 300 秒 (playerDownMaxTicks) 到期強制回城復活，免得冇道士/復活丹時卡死
func _player_down_tick() -> void:
	var pe := ent(int(state.get("player_id", 0)))
	if pe.is_empty() or not bool(pe.get("down", false)):
		return
	var cc: Dictionary = data.world["combat"]
	if tick < int(pe.get("downAt", 0)) + int(cc.get("playerDownMaxTicks", 3000)):
		return
	_death_return_to_town(pe)
	_revive_finish(pe)
	_emit({"k": "revive_self", "dst": int(pe["id"]), "onsite": false, "timeout": true})
	_msg(int(pe["id"]), "倒地太耐，強制送返客棧")


# S03a: 殺死居民/紅名(殺人魔) NPC (spec 03 §2, §4)。
# 善惡: 殺善一次過 -1000 / 紅殺紅 +300 / 反擊成功 +100；目擊；居民唔重生、冇掉落。
# S03b: 殺善居民(非自衛/非紅名) → 即時天譴 (雷劈 50% HP + 傳送客棧 + 公告)。
func _kill_bot(t: Dictionary, by: Dictionary) -> void:
	if by.is_empty() or not by.has("ch"):
		_remove_ent(int(t["id"]))
		return
	var is_player := int(by["id"]) == int(state["player_id"])
	var red := bool(t.get("ch", {}).get("criminal", false))
	# 反擊判定: 玩家而家追擊緊呢隻 bot = 玩家先行出手 (謀殺 / 紅殺)；
	# 玩家冇追緊 = 呢隻 bot 主動襲擊玩家而玩家自衛反殺 -> 反擊成功 +100
	var initiated := is_player and int(ent(int(state["player_id"])).get("atk_target", 0)) == int(t["id"])
	var counter := is_player and not initiated
	if is_player:
		var pch: Dictionary = by["ch"]
		pch["karma"] = RulesKarma.karma_after_kill_npc(int(pch["karma"]), {"good": not red, "red": red})
		if counter:
			pch["karma"] = RulesKarma.counter_kill(int(pch["karma"]))
		# 目擊: 附近有記憶表嘅 NPC 記錄玩家做咗嘢 (好感/傳聞, Spec 09)
		_witness_nearby(t, int(by["id"]), "murder", BotSys.W_KILL_NPC if not red else BotSys.W_KILL_RED)
		# S03b 天譴: 殺善居民 (非紅名) 且玩家先行出手 (非自衛) → 雷劈 50% HP + 傳送客棧 + 公告
		var tianqian := not red and initiated
		if tianqian:
			_tianqian_reprisal(by, str(t["name"]))
		_msg(int(by["id"]), "你殺咗%s！%s" % [str(t["name"]), ("（除害）" if red else "（罪案）")])
	state["bots"].erase(int(t["id"]))
	_remove_ent(int(t["id"]))
	var ev := {"k": "kill_npc", "dst": int(by["id"]), "name": str(t["name"]), "red": red, "counter": counter}
	if is_player:
		ev["karma"] = int(by["ch"]["karma"])
		ev["kind"] = "murder" if not red else "bounty"
		ev["tianqian"] = not red and initiated
	_emit(ev)


# S03b 天譴 (spec 03 §3)【自訂】: 殺善居民(非自衛)後即時雷劈——現有 HP×50% + 世界公告
# 「XXX 因作惡多端遭到天譴」；原地捱雷劈唔傳送；冇得用還魂丹 (ch.tianqian 旗留俾 S03c 還魂丹檢查, 有測試)。
func _tianqian_reprisal(p: Dictionary, victim: String) -> void:
	var ch: Dictionary = p["ch"]
	var hp_before := int(ch["hp"])
	ch["hp"] = RulesKarma.tianqian_hp(hp_before)
	ch["status"] = {}          # 雷劈清狀態
	ch["tianqian"] = true       # S03c 還魂丹對天譴無效 (RulesKarma.tianqian_blocks_revive)
	_sync_stats(p)
	var pid := int(p["id"])
	_msg(pid, "你天譴上身：雷劈扣 %d HP！" % (hp_before - int(ch["hp"])))
	_emit({"k": "tianqian", "dst": pid, "name": str(p["name"]), "victim": victim,
		"hp": int(ch["hp"]), "announce": RulesKarma.tianqian_announce(str(p["name"]))})


# 逃跑怪消失: 排重生 + 清 atk_target (冇掉落/善惡/經驗)
func _erase_flee(m: Dictionary, d: Dictionary) -> void:
	_schedule_respawn(m, d)
	_remove_ent(int(m["id"]))


# S04a 拾取地面掉落物 (spec 04 §6): 行埋邊 (NEAR 格) 撳拾取 → 收進背包。
# 背包滿 (總重超 capBagWeight) → 提示 + 留落地；逐件試，裝唔落嗰啲留低。
func cmd_pick(id: int, drop_id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var d := ent(drop_id)
	if d.is_empty() or d["kind"] != "dropped":
		return _msg(id, "呢度冇嘢執")
	if not _near(e, int(d["x"]), int(d["y"])):
		return _msg(id, "太遠喎，行埋啲先")
	var ch: Dictionary = e["ch"]
	var cfg: Dictionary = data.world.get("dropped", {})
	var cap := _bag_cap(ch)
	var wfn := func(i: int) -> int: return int(data.weights.get(i, 0))
	var picked: Array = []
	var leftover: Array = []
	var full := false
	for it in d["drop"]["items"] as Array:
		var iid := int(it["id"])
		var n := int(it["n"])
		if RulesShop.bag_fits(ch["bag"], iid, n, wfn, cap):
			RulesShop.add_item(ch["bag"], iid, n)
			picked.append({"id": iid, "n": n})
		else:
			full = true
			leftover.append({"id": iid, "n": n})
	var dxy := [int(d["x"]), int(d["y"])]
	if leftover.is_empty():
		_remove_ent(drop_id)
	else:
		d["drop"]["items"] = leftover
		d["drop"]["until"] = tick + int(cfg.get("capTicks", 300))
	if full:
		_msg(id, "背包滿，裝唔落，留返喺地下")
	for it in picked:
		_msg(id, "執到 %s ×%d" % [data.names.get(int(it["id"]), str(it["id"])), int(it["n"])])
	_emit({"k": "picked", "dst": id, "drop": drop_id, "items": picked, "full": full,
		"x": int(dxy[0]), "y": int(dxy[1])})
