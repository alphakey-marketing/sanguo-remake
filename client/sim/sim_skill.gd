extends "res://sim/sim_combat.gd"
# Sim 繼承鏈 第 6 層: 術法 (Step 9) / 絕招 / 融合 (Step 10) / 術法怪吟唱

# ================= 術法 (Step 9, spec 02 §3) =================

# 術書裝備去快捷列 (3 格切換【原】)；item=0 = 清空。要喺背包，裝備唔消耗本體
func cmd_equip_spellbook(id: int, item: int, slot: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if slot < 0 or slot > 2:
		return _msg(id, "快捷列得 3 格")
	var ch: Dictionary = e["ch"]
	if item == 0:
		ch["equip"]["spellbooks"][slot] = 0
		_emit({"k": "spellbook", "src": id, "slot": slot, "item": 0})
		return _msg(id, "快捷列 %d 已清空" % (slot + 1))
	var def: Dictionary = data.spell_by_item.get(item, {})
	if def.is_empty():
		return _msg(id, "呢件唔係術書")
	if not (def["classes"] as Array).has(str(ch["classId"])):
		return _msg(id, "你嘅職業用唔到呢本術書")
	var in_bag := false
	for b in ch["bag"]:
		if int(b["id"]) == item and int(b["n"]) > 0:
			in_bag = true
			break
	if not in_bag:
		return _msg(id, "背包冇呢本術書")
	ch["equip"]["spellbooks"][slot] = item
	_emit({"k": "spellbook", "src": id, "slot": slot, "item": item})
	_msg(id, "「%s」已裝備落快捷列 %d" % [def["name"], slot + 1])


# 施展快捷列 slot 嘅術法。attack/status 要 target；buff 自動施自己。開始吟唱，tick 到先生效。
# 吟唱期間移動取消【原】；受擊 30% 中斷【自訂】；封咒中唔可以施【原】
func cmd_cast_spell(id: int, slot: int, target: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var books: Array = ch["equip"].get("spellbooks", [0, 0, 0])
	if slot < 0 or slot >= books.size():
		return
	var item := int(books[slot])
	if item == 0:
		return _msg(id, "快捷列 %d 未裝備術書" % (slot + 1))
	var def: Dictionary = data.spell_by_item.get(item, {})
	if def.is_empty():
		return
	if not (def["classes"] as Array).has(str(ch["classId"])):
		return _msg(id, "你嘅職業用唔到呢本術書")
	if int(ch["level"]) < int(def["lv"]):
		return _msg(id, "要 Lv%d 先用得「%s」" % [int(def["lv"]), def["name"]])
	if RulesSpell.blocks_cast(ch.get("status", {}), tick):
		return _msg(id, "封咒緊，施唔到術法")
	if e.has("casting"):
		return _msg(id, "正在吟唱")
	var need_jewel := str(def.get("jewel", ""))
	if need_jewel != "" and not _has_special_jewel(ch, need_jewel):
		return _msg(id, "需要裝備「%s」先施得 (元素術大範圍施放【原】)" % _special_jewel_name(need_jewel))
	var mp_cost := _mp_cost(ch, int(def["mp"]))
	if int(ch["mp"]) < mp_cost:
		return _msg(id, "靈力不足 (要 %d MP)" % mp_cost)
	var tgt_id := 0
	if str(def["kind"]) != "buff":
		var t := ent(target)
		if t.is_empty() or int(t["hp"]) <= 0 or (t.get("kind", "") != "mob" and not t.has("ch")):
			return _msg(id, "目標唔啱")
		if not RulesCombat.in_range(e["x"], e["y"], t["x"], t["y"], float(def["range"])):
			return _msg(id, "太遠，施唔到")
		tgt_id = target
	e["casting"] = {"book": item, "target": tgt_id, "done_at": tick + int(def["castTicks"]), "slot": slot}
	_emit({"k": "cast_start", "src": id, "dst": tgt_id, "book": item, "ticks": int(def["castTicks"])})
	_msg(id, "吟唱「%s」…（移動取消）" % str(def["name"]))



# ---- 術法生效 (Step 9, spec 02 §3): 吟唱完結先扣 MP + 出效果 ----
func _resolve_cast(p: Dictionary) -> void:
	var cs: Dictionary = p["casting"]
	if tick < int(cs["done_at"]):
		return
	p.erase("casting")
	var ch: Dictionary = p["ch"]
	var def: Dictionary = data.spell_by_item.get(int(cs["book"]), {})
	if def.is_empty():
		return
	if RulesSpell.blocks_cast(ch.get("status", {}), tick):
		return _msg(int(p["id"]), "封咒緊，術法失效")
	var mp_cost := _mp_cost(ch, int(def["mp"]))
	if int(ch["mp"]) < mp_cost:
		return _msg(int(p["id"]), "靈力唔夠，術法取消")
	ch["mp"] = int(ch["mp"]) - mp_cost
	_emit({"k": "cast", "src": p["id"], "book": int(cs["book"]), "kind": str(def["kind"])})
	match str(def["kind"]):
		"attack":
			var t := ent(int(cs["target"]))
			if t.is_empty() or int(t["hp"]) <= 0:
				return _msg(int(p["id"]), "目標死咗，術法落空")
			if not RulesCombat.in_range(p["x"], p["y"], t["x"], t["y"], float(def["range"])):
				return _msg(int(p["id"]), "目標行遠咗，術法落空")
			_spell_hit(p, def, t)
		"status", "cure":
			var t2 := ent(int(cs["target"]))
			if t2.is_empty() or int(t2["hp"]) <= 0:
				return _msg(int(p["id"]), "目標死咗，術法落空")
			if not RulesCombat.in_range(p["x"], p["y"], t2["x"], t2["y"], float(def["range"])):
				return _msg(int(p["id"]), "目標行遠咗，術法落空")
			_spell_status(p, def, t2)
		"buff":
			_spell_buff(p, def)


# 特殊石: 施法時裝備咗對應元素 (spells.json jewel 欄 = 元素名) 嘅 special 石先得 (Step 10)
func _has_special_jewel(ch: Dictionary, elem: String) -> bool:
	for it in ch["equip"].get("jewels", [0, 0]) as Array:
		var jd: Dictionary = data.jewel_by_item.get(int(it), {})
		if not jd.is_empty() and str(jd.get("kind", "")) == "special" and str(jd.get("elem", "")) == elem:
			return true
	return false


func _special_jewel_name(elem: String) -> String:
	for jd in data.jewels.get("special", []):
		if str(jd["elem"]) == elem:
			return str(jd["name"])
	return elem + "之石"


# 消耗類成本: 輔助石 MP/SP 耗損減免 (effects 63/65) 乘落去
func _mp_cost(ch: Dictionary, base: int) -> int:
	return maxi(1, MathX.js_round(float(base) * float(_jewel_bonus(ch).get("mpCostMul", 1.0))))


func _sp_cost(ch: Dictionary, base: int) -> int:
	return maxi(1, MathX.js_round(float(base) * float(_jewel_bonus(ch).get("spCostMul", 1.0))))


# 傷害術: 大範圍 (aoe>0) = 以目標格為圓心打晒所有怪物；隊友唔受【原】
func _spell_hit(p: Dictionary, def: Dictionary, t: Dictionary) -> void:
	var ch: Dictionary = p["ch"]
	var attr := _eff_attr(ch, str(def["stat"]))
	# 寶石加成 (Step 10, spec 02 §3.2): 裝備 slot 0 屬性石同術法元素相同 → 石 pct 加成；另加輔助術攻 %
	var stone := _equip_stone(ch)
	var jewel_pct := RulesJewel.spell_jewel_bonus(str(stone.get("elem", "")), str(def.get("elem", "")),
		float(stone.get("pct", 0.0))) - 1.0
	var spell_atk_mult := 1.0 + float(_jewel_bonus(ch).get("spellAtkPct", 0.0))
	var aoe := int(def.get("aoe", 0))
	var targets: Array = []
	if aoe > 0:
		for o in ents.values():
			if o["kind"] == "mob" and int(o["hp"]) > 0 \
					and RulesCombat.in_range(t["x"], t["y"], o["x"], o["y"], aoe):
				targets.append(o)
	else:
		targets.append(t)
	for o in targets:
		var mdef: Dictionary = data.mob_def(int(o["mob"]["def"]))
		var dmg := RulesSpell.calc_spell_damage(float(def["power"]) * spell_atk_mult, attr,
			float(mdef.get("spellDef", 0)), str(def["elem"]), str(mdef.get("element", "none")), jewel_pct, rng_fn)
		_emit({"k": "spell_hit", "src": p["id"], "dst": o["id"], "dmg": dmg, "elem": str(def["elem"])})
		damage(o, dmg, p)


# ================= 絕招 (Step 10, spec 02 §5) =================
# 大範圍即時傷害 (冇吟唱): 耗 MP+SP、冷卻、需要對應武器 (ultimates.json weaponCat)
func cmd_use_ultimate(id: int, ult_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	if not (ch.get("ultimates", []) as Array).has(ult_id):
		return _msg(id, "未學呢招絕招")
	var ult: Dictionary = data.ult_by_id.get(ult_id, {})
	if ult.is_empty():
		return
	if str(ult["class"]) != str(ch["classId"]):
		return _msg(id, "你嘅職業用唔到呢招")
	var w := int(ch["equip"].get("weapon", 0))
	if w == 0 or int(data.cats.get(w, 0)) != int(ult["weaponCat"]):
		return _msg(id, "要用矛類武器先用得「%s」" % ult["name"])
	var cd: Dictionary = ch.get("ultCd", {})
	if tick < int(cd.get(ult_id, 0)):
		return _msg(id, "「%s」冷卻中 (%d tick)" % [ult["name"], int(cd.get(ult_id, 0)) - tick])
	var mp_cost := _mp_cost(ch, int(ult["mp"]))
	var sp_cost := _sp_cost(ch, int(ult["sp"]))
	if int(ch["mp"]) < mp_cost:
		return _msg(id, "靈力不足 (要 %d MP)" % mp_cost)
	if int(ch["sp"]) < sp_cost:
		return _msg(id, "體力不足 (要 %d SP)" % sp_cost)
	if is_safe(int(e["x"]), int(e["y"])):
		return _msg(id, "要出城先用得絕招")
	var rng_cells := int(ult["range"])
	var targets: Array = []
	for o in ents.values():
		if o["kind"] == "mob" and int(o["hp"]) > 0 \
				and RulesCombat.in_range(e["x"], e["y"], o["x"], o["y"], rng_cells):
			targets.append(o)
	if targets.is_empty():
		return _msg(id, "附近冇怪")
	ch["mp"] = int(ch["mp"]) - mp_cost
	ch["sp"] = int(ch["sp"]) - sp_cost
	cd[ult_id] = tick + int(ult["cd"])
	ch["ultCd"] = cd
	var wdef: Dictionary = _weapon_def(ch)     # 耐久 0 = 威力減半 (Step 12)
	var atk_mult := RulesSpell.atk_mult(ch.get("status", {}), tick) * (1.0 + float(_jewel_bonus(ch).get("atkPct", 0.0)))
	var eff_str := _eff_attr(ch, "str") + float(_jewel_bonus(ch).get("strFlat", 0))
	_emit({"k": "ult", "src": id, "ult": ult_id, "name": str(ult["name"]), "mp": mp_cost, "sp": sp_cost})
	_msg(id, "「%s」！" % ult["name"])
	for o in targets:
		var mdef: Dictionary = data.mob_def(int(o["mob"]["def"]))
		var elem_mult := _phys_elem_mult(ch, str(mdef.get("element", "none")))
		var dmg0 := RulesCombat.calc_damage(eff_str, wdef["power"], mdef["def"], rng_fn, atk_mult, 1.0)
		var dmg := MathX.js_round(dmg0 * float(ult["mult"]) * elem_mult)
		_emit({"k": "ult_hit", "src": id, "dst": o["id"], "dmg": dmg, "ult": ult_id})
		damage(o, dmg, e)



# ================= 融合 (義士特技, Step 10, spec 02 §6) =================
func _near_forge(e: Dictionary) -> bool:
	var f: Dictionary = data.facilities.get("forge", {})
	return not f.is_empty() and _near(e, int(f["x"]), int(f["y"]))


# 融合開始: 打鐵鋪度撳，義士 Lv10+，揀裝緊嗰件武器 + 背包第一粒屬性石
func cmd_fusion_start(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if not _near_forge(e):
		return _msg(id, "要喺打鐵鋪附近先融合得")
	var ch: Dictionary = e["ch"]
	if str(ch.get("classId", "")) != "yishi":
		return _msg(id, "融合係義士特技")
	if int(ch["level"]) < 10:
		return _msg(id, "要 10 級先學得融合")
	if not (ch.get("fusing", {}) as Dictionary).is_empty():
		return _msg(id, "正在融合緊")
	var w := int(ch["equip"].get("weapon", 0))
	if w == 0:
		return _msg(id, "未裝備武器")
	if (ch.get("fusedJewels", {}) as Dictionary).has(w):
		return _msg(id, "呢把武器已經嵌咗寶石 (只能 1 粒)")
	var jewel := 0
	for b in ch["bag"]:
		var jd: Dictionary = data.jewel_by_item.get(int(b["id"]), {})
		if not jd.is_empty() and str(jd.get("kind", "")) == "stone":
			jewel = int(b["id"])
			break
	if jewel == 0:
		return _msg(id, "背包要有一粒屬性石先融合得")
	ch["fusing"] = {"weapon": w, "jewel": jewel, "start": tick}
	_emit({"k": "fusion", "src": id, "state": "start", "weapon": w, "jewel": jewel,
		"target": RulesJewel.FUSION_TARGET, "window": RulesJewel.FUSION_WINDOW})
	_msg(id, "集氣棒起動 — 喺 50%%±20%% 嗰時撳實！（%d 秒）" % int(RulesJewel.FUSION_SECONDS))


# 融合敲實: 集氣棒位置 = f(tick - start)；hit 判定成功 → 扣屬性石 + 武器嵌石
func cmd_fusion_hit(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var fs: Dictionary = ch.get("fusing", {})
	if fs.is_empty():
		return _msg(id, "未開始融合 — 去打鐵鋪撳融合")
	ch.erase("fusing")
	var elapsed := tick - int(fs["start"])
	if RulesJewel.fusion_hit(elapsed):
		var jewel := int(fs["jewel"])
		var jd: Dictionary = data.jewel_by_item.get(jewel, {})
		RulesShop.remove_item(ch["bag"], jewel, 1)
		var wp := int(fs["weapon"])
		ch["fusedJewels"][wp] = {"elem": str(jd.get("elem", "none")), "pct": float(int(jd["pct"])) / 100.0}
		_emit({"k": "fusion", "src": id, "state": "ok", "weapon": wp, "elem": str(jd.get("elem", "")), "pct": int(jd["pct"])})
		_msg(id, "融合成功！%s 燒入咗武器（%s+%d%%）" % [jd["name"], jd.get("elem", ""), int(jd["pct"])])
	else:
		_emit({"k": "fusion", "src": id, "state": "fail"})
		_msg(id, "撳早/撳遲咗，再試下")


# 狀態術: status = 加狀態；cure = 解除對方狀態【原】
func _spell_status(p: Dictionary, def: Dictionary, t: Dictionary) -> void:
	var cure := str(def.get("cure", ""))
	var id := str(def.get("status", ""))
	if cure != "":
		var st: Dictionary
		if t["kind"] == "mob":
			if not t.has("status"):
				t["status"] = {}
			st = t["status"]
		else:
			if not (t["ch"] as Dictionary).has("status"):
				t["ch"]["status"] = {}
			st = t["ch"]["status"]
		if not RulesSpell.has(st, cure, tick):
			p["ch"]["mp"] = int(p["ch"]["mp"]) + _mp_cost(p["ch"], int(def["mp"]))    # 白費: 退款
			return _msg(int(p["id"]), "目標冇%s狀態，術法白費" % cure)
		RulesSpell.clear_status(st, cure)
		_emit({"k": "status", "dst": t["id"], "id": cure, "until": 0, "applied": false})
		_msg(int(p["id"]), "解咗%s狀態" % cure)
		return
	if id == "":
		return
	var ticks := RulesSpell.status_ticks(id)
	if t["kind"] == "mob":
		if not t.has("status"):
			t["status"] = {}
		RulesSpell.add_status(t["status"], id, ticks, tick)
	else:
		var ch2: Dictionary = t["ch"]
		if not ch2.has("status"):
			ch2["status"] = {}
		RulesSpell.add_status(ch2["status"], id, ticks, tick)
	_emit({"k": "status", "dst": t["id"], "id": id, "until": tick + ticks, "applied": true})
	_msg(int(p["id"]), "「%s」生效" % str(def["name"]))


# 增益術: 施自己 (聚力/強力/神力/護甲/護鏡系, spec 02 §7)
func _spell_buff(p: Dictionary, def: Dictionary) -> void:
	var ch: Dictionary = p["ch"]
	var id := str(def.get("status", ""))
	if id == "":
		return
	var ticks := RulesSpell.status_ticks(id)
	if not ch.has("status"):
		ch["status"] = {}
	RulesSpell.add_status(ch["status"], id, ticks, tick)
	_emit({"k": "status", "dst": p["id"], "id": id, "until": tick + ticks, "applied": true})
	_msg(int(p["id"]), "施咗「%s」（%d tick）" % [str(def["name"]), ticks])


# 術法怪吟唱生效: 傷害 (aoe = 打晒附近 ch) / 狀態 (打目標)
func _resolve_mob_cast(m: Dictionary, s: Dictionary, d: Dictionary, tgt: Dictionary) -> void:
	var cs: Dictionary = m["casting"]
	if tick < int(cs["done_at"]):
		m["tx"] = m["x"]
		m["ty"] = m["y"]
		return
	m.erase("casting")
	var sdef: Dictionary = data.spell_by_id.get(str(cs["spell"]), {})
	if sdef.is_empty():
		return
	if tgt.is_empty() or int(tgt["hp"]) <= 0 \
			or not RulesCombat.in_range(m["x"], m["y"], tgt["x"], tgt["y"], float(sdef["range"])):
		s["next_spell"] = tick + int(d.get("spellCd", 600))
		return
	match str(sdef["kind"]):
		"attack":
			var aoe := int(sdef.get("aoe", 0))
			var targets: Array = []
			if aoe > 0:
				for o in ents.values():
					if o.has("ch") and int(o["hp"]) > 0 \
							and RulesCombat.in_range(tgt["x"], tgt["y"], o["x"], o["y"], aoe):
						targets.append(o)
			else:
				targets.append(tgt)
			for o in targets:
				var pch: Dictionary = o["ch"]
				# 防具: 術防 flat + 術迴避 + 術法受擊減少 (Step 11.6)；冇術迴避就唔擲骰 (保持舊重播一致)
				var ab := _armor_bonus(pch)
				var caps: Dictionary = data.equip_cfg["caps"]
				var pd := (RulesStats.player_spell_def(int(pch["level"]), int(_eff_attr(pch, "spi"))) + int(ab["sdef"])) \
					* RulesSpell.spell_def_mult(pch.get("status", {}), tick)
				if int(ab["sevade"]) > 0 and rng.next() < RulesEquip.evade_chance(int(ab["sevade"]), 0.0, int(caps["evadePct"])):
					_emit({"k": "spell_hit", "src": m["id"], "dst": o["id"], "dmg": 0, "elem": str(sdef["elem"])})    # 術迴避
					continue
				var dmg := RulesEquip.reduce_dmg(RulesSpell.calc_spell_damage(float(sdef["power"]), float(d["level"]), pd,
					str(sdef["elem"]), "none", 0.0, rng_fn), int(ab["sdmgRed"]), int(caps["dmgRedPct"]))
				_emit({"k": "spell_hit", "src": m["id"], "dst": o["id"], "dmg": dmg, "elem": str(sdef["elem"])})
				damage(o, dmg, m)
		"status":
			var sid := str(sdef.get("status", ""))
			if sid != "" and not tgt.is_empty() and tgt.has("ch"):
				var pch2: Dictionary = tgt["ch"]
				# 防具迴避異常狀態 34~37/39 (Step 11.6)
				var res := int(_armor_bonus(pch2)["resist"].get(sid, 0))
				if res > 0 and rng.next() < minf(res, int(data.equip_cfg["caps"]["resistPct"])) / 100.0:
					_emit({"k": "status", "dst": tgt["id"], "id": sid, "until": 0, "applied": false, "resisted": true})
					s["next_spell"] = tick + int(d.get("spellCd", 600))
					return
				if not pch2.has("status"):
					pch2["status"] = {}
				RulesSpell.add_status(pch2["status"], sid, RulesSpell.status_ticks(sid), tick)
				_emit({"k": "status", "dst": tgt["id"], "id": sid, "until": tick + RulesSpell.status_ticks(sid), "applied": true})
	s["next_spell"] = tick + int(d.get("spellCd", 600))
