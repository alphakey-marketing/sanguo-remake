class_name RecruitPanel
extends GamePanel
# 登用面板 (Step 13.5, spec 09 §3): 調查 → 揀候選 → 擂台/問答；有同伴就顯示同伴 + 戰鬥指令 + 送補品 + 解散。
# Step 15: 候選「持令/金牌」+ 特技；同伴 MP/SP、特技、術法、寶物 2 格 + 贈與寶物、武將補品。
# 全部讀 sim.recruit_view()，經 main._send 發意圖。

func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "登用"


func sig() -> String:
	var v: Dictionary = main.sim.recruit_view()
	var c: Dictionary = v.get("comp", {})
	if not c.is_empty():            # HP 郁得好密: 只取整數 10% 級數，唔好每下重砌
		c = c.duplicate()
		c["hp"] = int(c["hp"]) * 10 / maxi(1, int(c["maxHp"]))
		c["mp"] = int(c.get("mp", 0)) * 10 / maxi(1, int(c.get("maxMp", 1)))
		c["sp"] = int(c.get("sp", 0)) * 10 / maxi(1, int(c.get("maxSp", 1)))
		v["comp"] = c
	var pt: Array = []
	for pm in v.get("party", []):        # 隊伍列唔睇 HP，免每下重砌
		pt.append([pm["id"], pm["lv"], pm["sel"]])
	v["party"] = pt
	return JSON.stringify([v, _gifts().size(), _treasures().size()])


func _build_body() -> void:
	var v: Dictionary = main.sim.recruit_view()
	if v.is_empty():
		return
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	if not (v["quiz"] as Dictionary).is_empty():
		_build_quiz(list, v["quiz"])
	elif String(v["pending"]) == "arena":
		list.add_child(wrap_lbl("擂台 PK 緊：%s\n打到佢 HP 0 就制服；你 HP 0 或者走開太遠 = 輸（唔會死）。" % v["pendingName"], 15))
		list.add_child(btn("返去打", func() -> void: main.hud.close_panels()))
		list.add_child(btn("認輸", func() -> void: main._send({"t": "recruit_cancel"})))
	elif not (v["comp"] as Dictionary).is_empty():
		_build_party(list, v)
		_build_comp(list, v["comp"])
		if String(v["block"]) == "":
			list.add_child(HSeparator.new())
			_build_survey(list, v)
	else:
		_build_survey(list, v)


# 隊伍列: 揀邊位同伴落指令 (上限 partyMax)
func _build_party(list: VBoxContainer, v: Dictionary) -> void:
	var party: Array = v.get("party", [])
	list.add_child(lbl("隊伍 %d/%d 位同伴" % [party.size(), int(v.get("partyMax", 5))], 14, UiTheme.DIM))
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 6)
	list.add_child(h)
	for pm in party:
		var cid: int = int(pm["id"])
		h.add_child(btn("%s%s Lv%d" % ["● " if bool(pm["sel"]) else "", pm["name"], int(pm["lv"])],
			func() -> void: main._send({"t": "companion_select", "cid": cid})))


func _build_survey(list: VBoxContainer, v: Dictionary) -> void:
	var ch: Dictionary = main.ch
	list.add_child(wrap_lbl("理念「%s」　Lv%d\n喺城池街道「調查」搵人才：每日 1 次；登用後隔 1 日可再調查，隊伍最多 5 位同伴。武將要擂台 PK，文官要答三國問答（10 題啱 8）。" %
		[str(ch.get("ideology", "")) if str(ch.get("ideology", "")) != "" else "未定（只登得出仕人才）", int(ch.get("level", 1))], 14, UiTheme.DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	list.add_child(h)
	var blocked := String(v["block"]) != ""
	for k in [["wu", "調查武將"], ["wen", "調查文官"]]:
		var kind: String = k[0]
		var b := btn(k[1], func() -> void: main._send({"t": "recruit_survey", "kind": kind}))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = blocked
		h.add_child(b)
	if blocked:
		list.add_child(lbl(String(v["block"]), 14, UiTheme.BAD))
	var cands: Array = v["cands"]
	if cands.is_empty():
		return
	list.add_child(hsep())
	list.add_child(lbl("候選人才（揀一位接受考驗）", 15, UiTheme.GOLD))
	for c in cands:
		var gid := int(c["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var tag := String({"order": "【持令】", "medal": "【金牌】"}.get(String(c.get("pass", "")), ""))
		var info := wrap_lbl("%s%s%s　戰等 %d　%s%s　%s　特技:%s" % [tag, "★" if bool(c["t1"]) else "", c["name"], int(c["lv"]),
			RulesRecruit.type_name(String(c["type"])), c["sub"], c["ideo"], String(c.get("skill", ""))], 14)
		row.add_child(info)
		var b := btn("PK" if String(c["type"]) == "wu" else "問答", func() -> void: main._send({"t": "recruit_pick", "gid": gid}), 72)
		b.disabled = String(c.get("why", "")) != ""
		row.add_child(b)
		list.add_child(row)


func _build_quiz(list: VBoxContainer, q: Dictionary) -> void:
	list.add_child(lbl("%s 考你三國問答　第 %d/%d 題　答啱 %d" % [q["name"], int(q["i"]) + 1, int(q["n"]), int(q["ok"])], 15, UiTheme.GOLD))
	list.add_child(wrap_lbl(str(q["q"]), 17))
	var opts: Array = q["opts"]
	for i in opts.size():
		var idx := i
		var b := btn("%s. %s" % ["ABCD"[i], opts[i]], func() -> void: main._send({"t": "recruit_answer", "answer": idx}))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(b)
	list.add_child(btn("放棄", func() -> void: main._send({"t": "recruit_cancel"})))


func _build_comp(list: VBoxContainer, c: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var pt := portrait(String(c["name"]), 56)
	if pt != null:
		head.add_child(pt)
	head.add_child(lbl("%s　Lv%d　%s%s" % [c["name"], int(c["lv"]), RulesRecruit.type_name(String(c["type"])), c["sub"]], 17, UiTheme.GOLD))
	list.add_child(head)
	list.add_child(lbl("HP %d/%d　忠誠 %d　剩 %d 日" % [int(c["hp"]), int(c["maxHp"]), int(c["loyalty"]), int(c["daysLeft"])], 15,
		UiTheme.BAD if int(c["loyalty"]) < 40 else UiTheme.TEXT))
	list.add_child(lbl("MP %d/%d　SP %d/%d　術法:%s" % [int(c.get("mp", 0)), int(c.get("maxMp", 0)), int(c.get("sp", 0)),
		int(c.get("maxSp", 0)), String(c.get("spell", ""))], 14))
	if String(c.get("skill", "")) != "":
		list.add_child(wrap_lbl("特技「%s」：%s" % [c["skill"], c.get("skillDesc", "")], 14, UiTheme.GOLD))
	var mul: Dictionary = c.get("classSkillMul", {})
	if float(mul.get("cd", 1.0)) != 1.0 or float(mul.get("cost", 1.0)) != 1.0:
		list.add_child(lbl("職業特技（同伴隨行加成）：冷卻 ×%.1f　消耗 ×%.1f" % [float(mul.get("cd", 1.0)), float(mul.get("cost", 1.0))], 13, UiTheme.DIM))
	_build_active_skill(list, c)
	list.add_child(lbl("戰鬥指令", 14, UiTheme.DIM))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	list.add_child(g)
	for o in RulesRecruit.ORDERS:
		var order: String = o
		var b := btn(("● " if order == String(c["order"]) else "") + str(RulesRecruit.ORDER_NAMES[order]),
			func() -> void: main._send({"t": "companion_order", "order": order}))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
	list.add_child(lbl("招式（絕招/術法）", 14, UiTheme.DIM))
	var g2 := GridContainer.new()
	g2.columns = 2
	g2.add_theme_constant_override("h_separation", 6)
	g2.add_theme_constant_override("v_separation", 6)
	list.add_child(g2)
	for m in RulesRecruit.SKILL_MODES:
		var mode: String = m
		var bm := btn(("● " if mode == String(c.get("skillMode", "off")) else "") + str(RulesRecruit.SKILL_MODE_NAMES[mode]),
			func() -> void: main._send({"t": "companion_skill_mode", "mode": mode}))
		bm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g2.add_child(bm)
	_build_treasure(list, c)
	var gifts := _gifts()
	if not gifts.is_empty():
		list.add_child(lbl("送補品（回血 + 忠誠）", 14, UiTheme.DIM))
		for it in gifts.slice(0, 3):
			var item: int = it
			list.add_child(btn("送 %s ×%d" % [item_name(item), RulesShop.count_item(main.ch.get("bag", []), item)],
				func() -> void: main._send({"t": "companion_gift", "item": item})))
	list.add_child(hsep())
	list.add_child(btn("解散（叫佢返去）", func() -> void: main._send({"t": "companion_dismiss"})))


# 同伴主動特技: 遁地(burrow)/挑釁(taunt)/急救(heal)；冷卻中顯示剩餘秒數
const ACTIVE_SKILL_NAMES := {"burrow": "遁地", "taunt": "挑釁", "heal": "急救"}
const ACTIVE_SKILL_DESC := {"burrow": "同伴帶主公傳送去最近城池", "taunt": "同伴引附近敵怪仇恨", "heal": "同伴急救主公一部分 HP"}


func _build_active_skill(list: VBoxContainer, c: Dictionary) -> void:
	var kind := String(c.get("activeKind", ""))
	if kind == "" or not ACTIVE_SKILL_NAMES.has(kind):
		return
	var cd_left := int(c.get("activeCdLeft", 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	list.add_child(row)
	var label := "%s%s" % [String(ACTIVE_SKILL_NAMES[kind]), ("（冷卻 %ds）" % [cd_left / 10] if cd_left > 0 else "")]
	var b := btn(label, func() -> void: main._send({"t": "companion_skill", "kind": kind}))
	b.disabled = cd_left > 0
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(b)
	list.add_child(wrap_lbl(String(ACTIVE_SKILL_DESC[kind]), 13, UiTheme.DIM))


# 武將寶物 2 格【原】: 放咗攞唔返；同類高取代低 (低嘅消失)
func _build_treasure(list: VBoxContainer, c: Dictionary) -> void:
	var trs: Array = c.get("treasures", [])
	var slots := int(main.data.gen2_cfg["treasureSlots"])
	var names: Array = []
	for i in slots:
		names.append("%s(%s+%d)" % [trs[i]["name"], trs[i]["type"], int(trs[i]["value"])] if i < trs.size() else "（空）")
	list.add_child(lbl("武將寶物：" + "　".join(names), 14))
	var st: Dictionary = c.get("stats", {})
	if not st.is_empty():
		list.add_child(lbl("兵量 %d　武材 +%d　軍略 +%d" % [int(st.get("troops", 0)), int(st.get("wucai", 0)), int(st.get("junlue", 0))], 13, UiTheme.DIM))
	var mine := _treasures()
	if mine.is_empty():
		return
	list.add_child(lbl("贈與寶物（攞唔返；同類低值會消失）", 14, UiTheme.DIM))
	for it in mine.slice(0, 4):
		var item: int = it
		list.add_child(btn("贈 %s ×%d" % [item_name(item), RulesShop.count_item(main.ch.get("bag", []), item)],
			func() -> void: main._send({"t": "companion_treasure", "item": item})))


# 背包入面嘅回復品 (補品) + 武將補品 (藥膳師)
func _gifts() -> Array:
	var out: Array = []
	var tonics: Dictionary = main.data.gen2_cfg["tonics"]
	for b in main.ch.get("bag", []):
		var id := int(b["id"])
		if (main.data.heals.has(id) or tonics.has(str(id))) and not out.has(id):
			out.append(id)
	return out


# 背包入面嘅武將寶物
func _treasures() -> Array:
	var out: Array = []
	for b in main.ch.get("bag", []):
		var id := int(b["id"])
		if not out.has(id) and not RulesGeneral.treasure_of(int(main.data.cats.get(id, 0)),
				main.data.info.get(id, {}).get("effects", []), main.data.gen2_cfg).is_empty():
			out.append(id)
	return out
