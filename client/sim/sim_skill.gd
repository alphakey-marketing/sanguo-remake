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
	if str(def["kind"]) == "heal":
		# 恢復術: target 0 = 自己；唔係就補同伴/玩家 (要有 ch)
		if target != 0:
			var th := ent(target)
			if th.is_empty() or int(th["hp"]) <= 0 or not th.has("ch"):
				return _msg(id, "目標唔啱（要自己或同伴）")
			if not RulesCombat.in_range(e["x"], e["y"], th["x"], th["y"], float(def["range"])):
				return _msg(id, "太遠，施唔到")
			tgt_id = target
	elif str(def["kind"]) != "buff":
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
	var cast_target := int(cs.get("target", 0))
	_spell_prof_bump(p, def)
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
		"heal":
			_spell_heal(p, def, cast_target)


# 恢復術 (美女系, S02c, spec 02 §3.1): 單體補 HP。目標 = 自己 (target 0) 或 同伴/玩家 (要有 ch)。
func _spell_heal(p: Dictionary, def: Dictionary, ct: int = 0) -> void:
	if ct == 0:
		ct = int(p["id"])
	var t := ent(ct)
	if t.is_empty() or int(t["hp"]) <= 0 or not t.has("ch"):
		return _msg(int(p["id"]), "目標唔可以補血")
	if not RulesCombat.in_range(p["x"], p["y"], t["x"], t["y"], 8):
		return _msg(int(p["id"]), "目標行遠咗，術法落空")
	var ch2: Dictionary = t["ch"]
	var heal := maxi(1, MathX.js_round(float(def["power"]) * _spell_prof_mult(p, def) * (1.0 + float(_jewel_bonus(ch2).get("healPct", 0.0)))))
	var before := int(ch2["hp"])
	var max_hp := int(t.get("max_hp", 1))
	ch2["hp"] = mini(max_hp, before + heal)
	var got := int(ch2["hp"]) - before
	_sync_stats(t)
	_emit({"k": "restore", "dst": int(t["id"]), "src": int(p["id"]), "hp": got, "name": str(def["name"])})
	_msg(int(p["id"]), "「%s」回復 %d HP！" % [str(def["name"]), got])


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


# 術法熟練度 (P5): 每次施放記一次，升級有訊息；威力乘 RulesSpell.prof_mult
func _spell_prof_bump(p: Dictionary, def: Dictionary) -> void:
	if str(def["kind"]) != "attack" and str(def["kind"]) != "heal":
		return
	var ch: Dictionary = p["ch"]
	var use: Dictionary = ch.get("spellUse", {})
	var k := str(int(def["item"]))
	var before := int(use.get(k, 0))
	use[k] = before + 1
	ch["spellUse"] = use
	var lv0 := RulesSpell.prof_level(before)
	var lv1 := RulesSpell.prof_level(before + 1)
	if lv1 > lv0:
		_emit({"k": "spell_prof", "dst": int(p["id"]), "book": int(def["item"]), "lv": lv1})
		_msg(int(p["id"]), "「%s」熟練度升至 %d 級（威力 +%d%%）" % [str(def["name"]), lv1, int(round(RulesSpell.PROF_PCT * 100.0 * lv1))])


func _spell_prof_mult(p: Dictionary, def: Dictionary) -> float:
	return RulesSpell.prof_mult(int((p["ch"].get("spellUse", {}) as Dictionary).get(str(int(def["item"])), 0)))


# 傷害術: 大範圍 (aoe>0) = 以目標格為圓心打晒所有怪物；隊友唔受【原】
func _spell_hit(p: Dictionary, def: Dictionary, t: Dictionary) -> void:
	var ch: Dictionary = p["ch"]
	var attr := _eff_attr(ch, str(def["stat"]))
	# 寶石加成 (Step 10, spec 02 §3.2): 兩格屬性石揀同術法元素最強嗰粒 → 石 pct 加成；另加輔助術攻 %
	var stone := _equip_stone(ch, str(def.get("elem", "")))
	var jewel_pct := RulesJewel.spell_jewel_bonus(str(stone.get("elem", "")), str(def.get("elem", "")),
		float(stone.get("pct", 0.0))) - 1.0
	var spell_atk_mult := (1.0 + float(_jewel_bonus(ch).get("spellAtkPct", 0.0))) * _spell_prof_mult(p, def)
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
		var mdef: Dictionary = data.mob_def(int(o["mob"]["def"]), int(o["mob"].get("lv", 0)))
		var dmg := RulesSpell.calc_spell_damage(float(def["power"]) * spell_atk_mult, attr,
			float(mdef.get("spellDef", 0)), str(def["elem"]), str(mdef.get("element", "none")), jewel_pct, rng_fn)
		_emit({"k": "spell_hit", "src": p["id"], "dst": o["id"], "dmg": dmg, "elem": str(def["elem"])})
		damage(o, dmg, p)


# ================= 絕招 (Step 10, spec 02 §5) =================
# 大範圍即時傷害 (冇吟唱): 耗 MP+SP、冷卻、需要對應武器 (ultimates.json weaponCat)
# 武器 cat 對應嘅類名 (items.json cat_label)，錯誤訊息用
func _cat_label(cat: int) -> String:
	for item in data.cats:
		if int(data.cats[item]) == cat:
			return str(data.info.get(item, {}).get("cat_label", "對應武器"))
	return "對應武器"


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
	var climit := RulesClass.ultimate_usable(ch, ult)   # S01d: 四招起要二轉/五·六招要三轉【原】
	if not bool(climit["ok"]):
		return _msg(id, str(climit["why"]))
	var w := int(ch["equip"].get("weapon", 0))
	if w == 0 or int(data.cats.get(w, 0)) != int(ult["weaponCat"]):
		return _msg(id, "要裝備%s先用得「%s」" % [_cat_label(int(ult["weaponCat"])), ult["name"]])
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
	var ult_stat := str(ult.get("stat", "str"))     # 術法職絕招跟智力/靈力 (P1)；武職跟武力
	var eff_str := _eff_attr(ch, ult_stat) + (float(_jewel_bonus(ch).get("strFlat", 0)) if ult_stat == "str" else 0.0)
	_emit({"k": "ult", "src": id, "ult": ult_id, "name": str(ult["name"]), "mp": mp_cost, "sp": sp_cost})
	_msg(id, "「%s」！" % ult["name"])
	for o in targets:
		var mdef: Dictionary = data.mob_def(int(o["mob"]["def"]), int(o["mob"].get("lv", 0)))
		var elem_mult := _phys_elem_mult(ch, str(mdef.get("element", "none")))
		var dmg0 := RulesCombat.calc_damage(eff_str, wdef["power"], mdef["def"], rng_fn, atk_mult, 1.0)
		var dmg := MathX.js_round(dmg0 * float(ult["mult"]) * elem_mult)
		_emit({"k": "ult_hit", "src": id, "dst": o["id"], "dmg": dmg, "ult": ult_id})
		damage(o, dmg, e)
		var sfx := str(ult.get("sfxStatus", ""))          # 六招特效【自訂】: 玄冰麒麟凍結 (spec 02 §5 "含特效")
		if sfx != "" and int(o["hp"]) > 0:
			if not o.has("status"):
				o["status"] = {}
			RulesSpell.add_status(o["status"], sfx, int(ult.get("sfxTicks", 300)), tick)



# ================= 職業特技 (S02c, spec 02 §6) =================
# 學到 -> ch.classSkill = skill id (導師任務獎勵)；而家得 開鎖（仕女）。
# sim 指令 + 事件 + UI 已接通；進階開鎖（任務寶箱）留 S06 任務寶箱批次。
# T-07 隨機寶箱已實作（見 _spawn_random_chests）。

func cmd_use_skill(id: int, skill_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var r := RulesClassSkill.can_use(data, ch, skill_id)
	if not bool(r["ok"]):
		return _msg(id, str(r["why"]))
	_use_skill_effect(id, skill_id)


# 職業特技施展 (唔帶「已學」門檻，供職業丹用): 系統判定要由 caller 做 (已學 / 職業丹嗰支丹)。
func _use_skill_effect(id: int, skill_id: String) -> void:
	match skill_id:
		"unlock":
			var chest := _near_locked_chest(ent(id))
			if chest.is_empty():
				return _msg(id, "附近冇鎖住嘅寶箱（野外每張地圖有，每日換位）")
			_emit({"k": "unlock_open", "dst": id, "chest": chest["id"]})
			_msg(id, "揀真鑰匙…三支得一支啱")
		"chaodu":
			_try_chaodu(id)
		"yinxing":
			_try_yinxing(id)
		"qieting":
			_try_qieting(id)
		"toushi":
			_try_toushi(id)
		_:
			_msg(id, "嗰招特技而家用唔到")


# 職業丹 (S11, spec 11 §11)：食丹 → 施展對應職業特技（要對應職業；唔使已由導師學到）。
# 扣丹由呢度做；main.gd use_item 對呢 5 件 id 改路由到呢度。
const PILL_UNLOCK := 30055
const PILL_QIETING := 30056
const PILL_YINXING := 30057
const PILL_CHAODU := 30058
const PILL_TOUSHI := 30059
const PILL_SKILL_IDS := {
	PILL_UNLOCK: "unlock", PILL_QIETING: "qieting",
	PILL_YINXING: "yinxing", PILL_CHAODU: "chaodu", PILL_TOUSHI: "toushi",
}

func cmd_use_class_pill(id: int, item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var skill_id: String = PILL_SKILL_IDS.get(item, "")
	if skill_id == "":
		return _msg(id, "呢件唔係職業丹")
	var ch: Dictionary = e["ch"]
	var def: Dictionary = RulesClassSkill.def_of(data, skill_id)
	if def.is_empty() or String(def.get("class", "")) != String(ch.get("classId", "")):
		return _msg(id, "你職業用唔到呢粒丹")
	if not RulesShop.remove_item(ch["bag"], item, 1):
		return _msg(id, "背包冇呢件")
	_msg(id, "食咗%s，施展「%s」" % [data.names.get(item, str(item)), String(def.get("name", skill_id))])
	_use_skill_effect(id, skill_id)
# 行車空隙 pattern 用 SimRng 生成 (可重現)；sim 權威判定穿越成敗。
func _try_yinxing(id: int) -> void:
	var e := ent(id)
	var ch: Dictionary = e["ch"]
	if RulesSpell.has(ch.get("status", {}), "stealth", tick):
		return _msg(id, "已喺潛行緊")
	if tick < int(ch.get("stealthCd", 0)):
		return _msg(id, "潛行冷卻中（%d tick 後再用得）" % [int(ch.get("stealthCd", 0)) - tick])
	if not (ch.get("stealthGame", {}) as Dictionary).is_empty():
		return _msg(id, "仲睇緊張車，未郁就做嘢")
	var pattern := RulesStealth.make_pattern(rng_fn)
	ch["stealthGame"] = {"pattern": pattern, "start": tick, "crossed": 0}
	_emit({"k": "stealth_open", "dst": id, "pattern": pattern,
		"period": RulesStealth.CART_PERIOD, "gaps": RulesStealth.GAP_COUNT, "gapW": RulesStealth.GAP_W, "start": tick})
	_msg(id, "車要嚟喇——揀啱每卡車之間嗰下空隙穿過！（%d 卡）" % RulesStealth.GAP_COUNT)


# 行車小遊戲穿越一下 (stealth_panel「穿過」掣)
func cmd_stealth_cross(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var g: Dictionary = ch.get("stealthGame", {})
	if g.is_empty():
		return _msg(id, "冇行車睇緊")
	var pattern: Array = g["pattern"]
	var start := int(g["start"])
	var crossed := int(g.get("crossed", 0))
	if crossed >= RulesStealth.GAP_COUNT:
		ch.erase("stealthGame")
		return _msg(id, "已經穿晒")
	if RulesStealth.cross_pattern(pattern, start, crossed, tick):
		g["crossed"] = crossed + 1
		_msg(id, "穿過咗第 %d 卡車之間！" % (crossed + 1))
		if crossed + 1 >= RulesStealth.GAP_COUNT:
			ch.erase("stealthGame")
			if not ch.has("status"):
				ch["status"] = {}
			RulesSpell.add_status(ch["status"], "stealth", RulesStealth.STEALTH_TICKS, tick)
			ch["stealthCd"] = tick + MathX.js_round(RulesStealth.STEALTH_CD_TICKS * float(_companion_class_skill_mul(e)["cd"]))    # 22 職業特技
			_sync_stats(e)
			_emit({"k": "stealth_done", "dst": id, "until": tick + RulesStealth.STEALTH_TICKS})
			_msg(id, "潛行！10 分鐘內主動怪唔會仇恨你（CD 1 日）")
		else:
			_emit({"k": "stealth_prog", "dst": id, "crossed": int(g["crossed"])})
	else:
		ch.erase("stealthGame")
		_emit({"k": "stealth_fail", "dst": id})
		_msg(id, "撞埋車——被發現，潛行失敗！")


# 竊聽 (辯士, S02c, spec 02 §6【自訂】單機化): 喺居民側邊竊聽對話 -> 得傳聞線索（耳邊「…」）。
# 居民 = 附近 bot (野區居民, bot_sys.gd) 或附近任務 NPC；傳聞記入 ch.rumors (情報冊)。
func _try_qieting(id: int) -> void:
	var e := ent(id)
	var ch: Dictionary = e["ch"]
	if tick < int(ch.get("qietingCd", 0)):
		return _msg(id, "啱啱竊聽完，耳邊仲嗡嗡作響（%d tick 後先用得）" % [int(ch.get("qietingCd", 0)) - tick])
	# 搵附近居民 (bot 實體 或 任務 NPC)
	var best := ""
	var best_d := 1 << 30
	for o in ents.values():
		if String(o.get("kind", "")) != "bot":
			continue
		var d: int = maxi(absi(int(o["x"]) - int(e["x"])), absi(int(o["y"]) - int(e["y"])))
		if d <= RulesQieting.QIETING_RANGE and d < best_d:
			best_d = d
			best = str(o.get("name", "居民"))
	for n in data.quest_npc_list:
		if String(n.get("map", "")) != map_id_at(int(e["x"]), int(e["y"])):
			continue
		var d2: int = maxi(absi(int(n["x"]) - int(e["x"])), absi(int(n["y"]) - int(e["y"])))
		if d2 <= RulesQieting.QIETING_RANGE and d2 < best_d:
			best_d = d2
			best = str(n.get("name", "居民"))
	if best == "":
		return _msg(id, "附近冇居民喺度傾偈，偷聽唔到嘢")
	var line := RulesQieting.pick_unheard(data, ch, rng_fn)
	if line == "":
		return _msg(id, "冇傳聞值得竊聽")
	ch["qietingCd"] = tick + RulesQieting.QIETING_CD_TICKS
	var rumors: Array = ch.get("rumors", [])
	if not rumors.has(line):
		rumors.append(line)
		ch["rumors"] = rumors
	_emit({"k": "qieting", "dst": id, "who": best, "text": line, "total": rumors.size()})
	_msg(id, "【%s 耳邊「…」】%s" % [best, line])


# 透視 (美女, S02c, spec 02 §6【自訂】單機化): 對喺範圍內最近嘅 NPC/怪用 -> 顯示隱藏資訊
# （HP/MP/等級/弱點屬性），並入「洞悉」狀態 +20% 攻擊力（戰鬥優勢）。有冷卻。
func _try_toushi(id: int) -> void:
	var e := ent(id)
	var ch: Dictionary = e["ch"]
	if tick < int(ch.get("toushiCd", 0)):
		return _msg(id, "啱啱透視過，眼前仲有撻痕（%d tick 後先用得）" % [int(ch.get("toushiCd", 0)) - tick])
	# 揀喺範圍內最近嘅目標 (怪物 或 居民/NPC 實體)
	var best: Dictionary = {}
	var best_d := 1 << 30
	for o in ents.values():
		var k := str(o.get("kind", ""))
		if k != "mob" and k != "bot" and k != "gen":
			continue
		if k == "mob" and int(o["hp"]) <= 0:
			continue
		var d: int = maxi(absi(int(o["x"]) - int(e["x"])), absi(int(o["y"]) - int(e["y"])))
		if d <= RulesToushi.TOUSHI_RANGE and d < best_d:
			best_d = d
			best = o
	if best.is_empty():
		return _msg(id, "附近冇可以透視嘅目標")
	# 收集隱藏資訊
	var k := str(best.get("kind", ""))
	var info := {"name": str(best.get("name", "目標")), "level": int(best.get("level", 0)),
		"hp": int(best.get("hp", 0)), "maxHp": int(best.get("max_hp", 0)),
		"mp": 0, "maxMp": 0, "elem": "none", "weakness": ""}
	if k == "mob":
		var mdef: Dictionary = data.mob_def(int(best["mob"]["def"]), int(best["mob"].get("lv", 0)))
		info["elem"] = str(mdef.get("element", "none"))
	else:
		# 居民/NPC: 有 ch 先顯示藝/靈力 (bot 無 ch)
		var bch: Dictionary = best.get("ch", {})
		if not bch.is_empty():
			info["mp"] = int(bch.get("mp", 0))
			info["maxMp"] = RulesStats.max_mp(int(bch.get("level", 0)), bch.get("attrs", {}))
	info["weakness"] = RulesToushi.weakness_of(String(info["elem"]))
	ch["toushiCd"] = tick + MathX.js_round(RulesToushi.TOUSHI_CD_TICKS * float(_companion_class_skill_mul(e)["cd"]))    # 22 職業特技
	if not ch.has("status"):
		ch["status"] = {}
	RulesSpell.add_status(ch["status"], "insight", RulesToushi.INSIGHT_TICKS, tick)
	_sync_stats(e)
	_emit({"k": "toushi", "dst": id, "info": info, "insight_until": tick + RulesToushi.INSIGHT_TICKS})
	var wk := String(info["weakness"])
	_msg(id, "透視【%s】Lv%d HP %d/%d · 弱點：%s（入洞悉 +%d%% 攻擊）" % [info["name"], int(info["level"]),
			int(info["hp"]), int(info["maxHp"]), wk if wk != "" else "無", int(RulesSpell.INSIGHT_ATK_MULT * 100)])
const REVIVE_RANGE := 5
func _try_chaodu(id: int) -> void:
	var e := ent(id)
	var ch: Dictionary = e["ch"]
	var target: Dictionary = {}
	for o in ents.values():
		var kind := String(o.get("kind", ""))
		if (kind == "gen" or kind == "player") and int(o["id"]) != id and bool(o.get("down", false)) and int(o["hp"]) <= 0 \
				and RulesCombat.in_range(e["x"], e["y"], o["x"], o["y"], REVIVE_RANGE):
			target = o
			break
	if target.is_empty():
		return _msg(id, "附近冇倒下嘅人（同伴/主公倒下先可以超渡）")
	var max_hp := maxi(1, int(e.get("max_hp", 1)))
	var max_mp := maxi(1, RulesStats.max_mp(int(ch["level"]), ch["attrs"]))
	var cmul := float(_companion_class_skill_mul(e)["cost"])    # 22 職業特技
	var hp_cost := int(ceil(max_hp * 0.2 * cmul))
	var mp_cost := int(ceil(max_mp * 0.3 * cmul))
	if int(ch["hp"]) <= hp_cost:
		return _msg(id, "自己體力唔夠做超渡（要留 %d HP）" % hp_cost)
	if int(ch["mp"]) < mp_cost:
		return _msg(id, "自己靈力唔夠做超渡（要 %d MP）" % mp_cost)
	ch["hp"] = int(ch["hp"]) - hp_cost
	ch["mp"] = int(ch["mp"]) - mp_cost
	_sync_stats(e)
	_revive_onsite(target)          # 原地回滿血 + 清倒地狀態【自訂新增，同復活丹共用】
	_emit({"k": "revive", "dst": id, "id": int(target["id"]), "name": str(target["name"])})
	_msg(id, "超渡！「%s」起返身回滿血（扣自己 %d HP．%d MP）" % [target["name"], hp_cost, mp_cost])


# 隨機寶箱 (T-07, spec 02 §6)【自訂】: 野外每張地圖 spawn 一個鎖住寶箱，每日子時更新位置（全地圖每日換位）。
# 開鎖實體: {kind:"chest", locked, key(0..2), drop={items/gold}}；開岩鎖匙得賞、開錯留返再試。
# CHEST_KEYS / CHEST_RANGE 定義喺 sim_core.gd (父類，唔好重複宣告)


# 開鎖小遊戲揀鑰匙（unlock_panel 三掣）: key_idx 啱 -> 寶箱開，得賞；錯 -> 留喺度再試
func cmd_skill_pick(id: int, chest_id: int, key_idx: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	if String(ch.get("classSkill", "")) != "unlock":
		return _msg(id, "未學「開鎖」")
	var chest: Dictionary = ents.get(chest_id, {})
	if chest.is_empty() or String(chest.get("kind", "")) != "chest":
		return _msg(id, "寶箱唔喺度")
	if not bool(chest.get("locked", true)):
		return _msg(id, "寶箱已經開咗")
	if int(chest.get("key", 0)) != key_idx:
		return _msg(id, "揀錯鑰匙，%s 紋紋唔肯郁…（再試）" % str(chest.get("name", "寶箱")))
	_chest_open(id, e, chest_id, chest, false)


# 寶箱開 (開鎖揀啱鑰匙 / 硬撬打爛): 鎖開 + 得賞 + 收箱 + 任務推進
func _chest_open(id: int, e: Dictionary, chest_id: int, chest: Dictionary, pried: bool) -> void:
	var ch: Dictionary = e["ch"]
	chest["locked"] = false
	var name := str(chest.get("name", "寶箱"))
	_emit({"k": "unlock_done", "dst": id, "chest": chest_id, "ok": true, "name": name})
	_msg(id, ("砰！%s 俾你撬爛咗！" if pried else "咔！%s 開咗！") % name)
	var dp: Dictionary = chest.get("drop", {})
	var items: Array = []
	for it in dp.get("items", []) as Array:
		items.append({"id": int(it["id"]), "n": int(it.get("n", 1))})
	var gold := int(dp.get("gold", 0))
	if not items.is_empty():
		# 背包物直接落袋（寶箱唔好似野外怪咁跌落地）
		for it in items:
			RulesShop.add_item(ch["bag"], int(it["id"]), int(it["n"]))
			_msg(id, "寶箱出到「%s」×%d！" % [data.names.get(int(it["id"]), str(it["id"])), int(it["n"])])
	if gold > 0:
		ch["gold"] = int(ch["gold"]) + gold
		_msg(id, "寶箱出到金 %d！" % gold)
	if items.is_empty() and gold == 0:
		_msg(id, "寶箱空蕩蕩…")
	_remove_ent(chest_id)
	var cq := String(chest.get("quest", ""))
	if cq != "":                                       # 任務寶箱: 開到 → 推進任務
		var q := _quest_by_id(cq)
		if not q.is_empty():
			var res := RulesQuest.on_chest_open(data, ch, q)
			if bool(res.get("changed", false)):
				_quest_emit(e, q, res)
	_emit({"k": "chest_loot", "dst": id, "chest": chest_id, "items": items, "gold": gold})


# 附近鎖住嘅寶箱實體（開鎖特技喺寶箱旁先用得）
# 冇開鎖技能都得: 狂打寶箱 (固定硬度 CHEST_PRY_HITS 下先爛，每下 CHEST_PRY_CD tick)；由 sim_ai 玩家攻擊迴圈叫
const CHEST_PRY_HITS := 12
const CHEST_PRY_CD := 8
func _pry_chest(p: Dictionary, t: Dictionary) -> void:
	p["next_atk"] = tick + CHEST_PRY_CD
	t["pry"] = int(t.get("pry", CHEST_PRY_HITS)) - 1
	_emit({"k": "hit", "src": p["id"], "dst": t["id"], "dmg": 1, "crit": false})
	if int(t["pry"]) > 0:
		return
	p["atk_target"] = 0
	_chest_open(int(p["id"]), p, int(t["id"]), t, true)


func _near_locked_chest(e: Dictionary) -> Dictionary:
	for o in ents.values():
		if String(o.get("kind", "")) == "chest" and bool(o.get("locked", true)) \
				and RulesCombat.in_range(e["x"], e["y"], o["x"], o["y"], CHEST_RANGE):
			return o
	return {}


# 每日子時刷新: 清晒現有寶箱再重新 spawn（全地圖換位）
func _chest_daily(day: int) -> void:
	var gone: Array = []
	for o in ents.values():
		if String(o.get("kind", "")) == "chest":
			gone.append(int(o["id"]))
	_remove_ents(gone)
	_spawn_random_chests()


# 喺每張野外（非安全）地圖 spawn 一個隨機寶箱；用 RNG 揀位 + 揀鎖匙，決定性可重現。
# debug: 直接學絕招/特技（成品前移除；S02c 絕招任務鏈喺 S06d，先畀手機測招式）
func cmd_debug_learn(id: int, kind: String, what: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	match kind:
		"ult":
			var ults: Array = ch.get("ultimates", [])
			if not ults.has(what):
				ults.append(what)
				ch["ultimates"] = ults
				_msg(id, "debug: 學識絕招「%s」" % str(data.ult_by_id.get(what, {}).get("name", what)))
			else:
				_msg(id, "已學過嗰招")
		"skill":
			ch["classSkill"] = what
			_msg(id, "debug: 學識特技「%s」" % str((data.class_skills as Dictionary).get(what, {}).get("name", what)))

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


# 術法怪吟唱生效 (S04b): aoe 打「吟唱開始時目標企位」(走位可躲)；單體打 chase 目標走甩術距就 miss
func _resolve_mob_cast(m: Dictionary, s: Dictionary, d: Dictionary, tgt: Dictionary) -> void:
	var cs: Dictionary = m["casting"]
	if tick < int(cs["done_at"]):
		m["tx"] = m["x"]
		m["ty"] = m["y"]
		return
	m.erase("casting")
	var sdef: Dictionary = data.spell_by_id.get(str(cs["spell"]), {})
	if sdef.is_empty():
		_mobcast_cd(s, d, cs)
		return
	var aoe := int(sdef.get("aoe", 0))
	if aoe > 0:
		# 彈道落點 = 吟唱開始時鎖定嘅格；範圍內嘅 ch 都食到 (行開躲到)
		var cx := int(cs.get("x", int(m["x"])))
		var cy := int(cs.get("y", int(m["y"])))
		var targets: Array = []
		for o in ents.values():
			if o.has("ch") and int(o["hp"]) > 0 and RulesCombat.in_range(cx, cy, o["x"], o["y"], aoe):
				targets.append(o)
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
		_mobcast_cd(s, d, cs)
		return
	# ---- 單體 (aoe==0): 目標死咗 / 行甩咗術距 -> miss (唔打) ----
	if tgt.is_empty() or int(tgt["hp"]) <= 0 \
			or not RulesCombat.in_range(m["x"], m["y"], tgt["x"], tgt["y"], float(sdef["range"])):
		_mobcast_cd(s, d, cs)
		return
	match str(sdef["kind"]):
		"attack":
			var o: Dictionary = tgt
			var pch: Dictionary = o["ch"]
			var ab := _armor_bonus(pch)
			var caps: Dictionary = data.equip_cfg["caps"]
			var pd := (RulesStats.player_spell_def(int(pch["level"]), int(_eff_attr(pch, "spi"))) + int(ab["sdef"])) \
				* RulesSpell.spell_def_mult(pch.get("status", {}), tick)
			if int(ab["sevade"]) > 0 and rng.next() < RulesEquip.evade_chance(int(ab["sevade"]), 0.0, int(caps["evadePct"])):
				_emit({"k": "spell_hit", "src": m["id"], "dst": o["id"], "dmg": 0, "elem": str(sdef["elem"])})
			else:
				var dmg := RulesEquip.reduce_dmg(RulesSpell.calc_spell_damage(float(sdef["power"]), float(d["level"]), pd,
					str(sdef["elem"]), "none", 0.0, rng_fn), int(ab["sdmgRed"]), int(caps["dmgRedPct"]))
				_emit({"k": "spell_hit", "src": m["id"], "dst": o["id"], "dmg": dmg, "elem": str(sdef["elem"])})
				damage(o, dmg, m)
		"status":
			var sid := str(sdef.get("status", ""))
			if sid != "" and not tgt.is_empty() and tgt.has("ch"):
				var pch2: Dictionary = tgt["ch"]
				# 防具迴避異常狀態 34~37/39 (Step 11.6)
				var res := int(_armor_bonus(pch2)["resist"].get(sid, 0)) + int(_jewel_bonus(pch2)["resist"].get(sid, 0))   # 防具 + 輔助石
				if res > 0 and rng.next() < minf(res, int(data.equip_cfg["caps"]["resistPct"])) / 100.0:
					_emit({"k": "status", "dst": tgt["id"], "id": sid, "until": 0, "applied": false, "resisted": true})
					_mobcast_cd(s, d, cs)
					return
				if not pch2.has("status"):
					pch2["status"] = {}
				RulesSpell.add_status(pch2["status"], sid, RulesSpell.status_ticks(sid), tick)
				_emit({"k": "status", "dst": tgt["id"], "id": sid, "until": tick + RulesSpell.status_ticks(sid), "applied": true})
	_mobcast_cd(s, d, cs)


# 術法怪 / boss 技能冷卻: boss 用 skill_cd[sk]，其他用 next_spell
func _mobcast_cd(s: Dictionary, d: Dictionary, cs: Dictionary) -> void:
	if cs.has("sk"):
		if not s.has("skill_cd"):
			s["skill_cd"] = {}
		var sk: Dictionary = (d.get("skills", []) as Array)[int(cs["sk"])]
		s["skill_cd"][str(int(cs["sk"]))] = tick + int(sk.get("cd", int(d.get("spellCd", 600))))
	else:
		s["next_spell"] = tick + int(d.get("spellCd", 600))
