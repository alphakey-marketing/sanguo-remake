class_name CharPanel
extends GamePanel
# 角色面板: 左 = 屬性 + 分配點數（＋/－ 先暫存，撳「確認分配」先送 sim）；右 = 角色資料。
# 「建議分配」係玩家自己撳嘅選項（按職業比例派晒），唔會自動派。政治/魅力唔用得點數，放右邊資料。
# 頁籤「裝備」= 紙娃娃 (Step 11.6): 頭/身/靴/戒/項鍊 + 武器 3 槽 + 寶石 2 格；撳格揀中 → 右邊詳情 + 卸下/切換

const ATTR_NAMES := {"str": "武力", "agi": "敏捷", "int": "智力", "spi": "靈力", "pol": "政治", "cha": "魅力"}
var pending := {}             # attr -> 暫存加咗幾多
var sel_slot := ""            # 裝備頁揀中格: head/body/boots/ring/necklace/w0..w2/j0/j1


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "角色"
	set_tabs(["屬性", "裝備", "技能", "專長"])


func open() -> void:
	pending = {}
	super()


func sig() -> String:
	var ch: Dictionary = main.ch
	return JSON.stringify([tab, sel_slot, ch.get("equip", {}), ch.get("workLv", {}), ch.get("tools", {}), pending, ch.get("attrs", {}), ch.get("attrPoints", 0), ch.get("level", 1), ch.get("hp", 0),
		ch.get("mp", 0), ch.get("sp", 0), ch.get("gold", 0), ch.get("karma", 0), ch.get("lilian", 0), ch.get("title", ""), ch.get("fame", 0), ch.get("ap", 0), ch.get("chaExp", 0),
		ch.get("titleRank", 0), ch.get("thirst", 0), ch.get("contrib", 0), ch.get("polExp", 0), ch.get("expert", {})])


func _left() -> int:
	var used := 0
	for k in pending:
		used += int(pending[k])
	return int(main.ch.get("attrPoints", 0)) - used


func _build_body() -> void:
	var ch: Dictionary = main.ch
	if ch.is_empty():
		return
	if tab == 1:
		_build_equip(ch)
		return
	if tab == 2:
		_build_work(ch)
		return
	if tab == 3:
		_build_expert(ch)
		return
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var sc := scroll()
	row.add_child(sc)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(right)
	var left_n := _left()
	left.add_child(lbl("可分配點數 %d" % left_n, 16, UiTheme.GOOD if left_n > 0 else UiTheme.DIM))
	var gs := scroll()
	left.add_child(gs)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 3)
	gs.add_child(grid)
	var attrs: Dictionary = ch.get("attrs", {})
	for k in RulesStats.RAIDABLE:
		var base := int(attrs.get(k, 0))
		var add := int(pending.get(k, 0))
		grid.add_child(lbl(String(ATTR_NAMES[k]), 16))
		var v := lbl(str(base + add) + (" (+%d)" % add if add > 0 else ""), 16, UiTheme.GOOD if add > 0 else UiTheme.TEXT)
		v.custom_minimum_size.x = 76
		grid.add_child(v)
		var mb := btn("－", func() -> void:
			pending[k] = maxi(0, add - 1)
			refresh(true), 48)
		mb.disabled = add <= 0
		grid.add_child(mb)
		var pb := btn("＋", func() -> void:
			pending[k] = add + 1
			refresh(true), 48)
		pb.disabled = left_n <= 0 or base + add >= RulesStats.ATTR_CAP
		grid.add_child(pb)
	var h := HBoxContainer.new()
	var ok := btn("確認分配", _confirm)
	ok.disabled = left_n == int(ch.get("attrPoints", 0))
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ok)
	var rs := btn("重設", func() -> void:
		pending = {}
		refresh(true), 64)
	h.add_child(rs)
	if int(ch.get("attrPoints", 0)) > 0:
		h.add_child(btn("建議分配", func() -> void:
			pending = {}
			main._send({"t": "auto_assign"}), 96))
	left.add_child(h)
	# 右: 資料
	var lv := int(ch["level"])
	var cls: Dictionary = main.data.classes.get(str(ch.get("classId", "")), {})
	right.add_child(lbl("%s  Lv%d %s" % [str(ch.get("name", "")), lv, str(cls.get("name", ""))], 17, UiTheme.GOLD))
	var lines := [
		"稱號「%s」" % (str(ch.get("title", "")) if str(ch.get("title", "")) != "" else "未設"),
		"善惡 %s (%d)" % [RulesKarma.tier_name(int(ch.get("karma", 0))), int(ch.get("karma", 0))],
		"理念 %s" % (str(ch.get("ideology", "")) if str(ch.get("ideology", "")) != "" else "未測"),
		"生日 %d月%d日" % [int(ch.get("birthMonth", 1)), int(ch.get("birthDay", 1))],
		"政治 %d  魅力 %d（私塾/寺廟修練）" % [int(attrs.get("pol", 0)), int(attrs.get("cha", 0))],
		"HP %d/%d" % [int(ch["hp"]), RulesStats.max_hp(lv, attrs)],
		"MP %d/%d" % [int(ch["mp"]), RulesStats.max_mp(lv, attrs)],
		"SP %d/%d" % [int(ch["sp"]), RulesStats.max_sp(lv, attrs)],
		"經驗 %d/%d" % [int(ch.get("exp", 0)), RulesStats.exp_to_next(lv)],
		"歷練 %d/100" % int(ch.get("lilian", 0)),
		"頭銜 %s（第 %d 階）" % [RulesTitle.name_of(main.data.titles, int(ch.get("titleRank", 0))), int(ch.get("titleRank", 0))],
		"名聲 %d　行動力 %d/%d" % [int(ch.get("fame", 0)), main.sim.ap_of(ch), main.sim.ap_max(ch)],
		"飲水度 %d/%d　官宅貢獻 %d" % [main.sim.thirst_of(ch), int(main.data.world["thirst"]["max"]), int(ch.get("contrib", 0))],
		"政治經驗 %d/%d（官令）" % [int(ch.get("polExp", 0)), int(main.data.office["polExpPerPoint"])],
		"魅力經驗 %d/%d（捐獻）" % [int(ch.get("chaExp", 0)), int(main.data.donation["chaExpPerPoint"])],
		"金 %d" % int(ch.get("gold", 0)),
		"武器 %s" % (item_name(int(ch.get("equip", {}).get("weapon", 0))) if int(ch.get("equip", {}).get("weapon", 0)) > 0 else "（冇）"),
	]
	for l in lines:
		right.add_child(lbl(str(l), 14))


func _confirm() -> void:
	for k in pending:
		for i in int(pending[k]):
			main._send({"t": "raise_attr", "attr": k})
	pending = {}
	refresh(true)


# ================= 裝備頁 (紙娃娃) =================
func _slot_item(eq: Dictionary, key: String) -> int:
	if key.begins_with("w"):
		return int((eq.get("weapons", [eq.get("weapon", 0), 0, 0]) as Array)[int(key.substr(1))])
	if key.begins_with("j"):
		return int((eq.get("jewels", [0, 0]) as Array)[int(key.substr(1))])
	return int(eq.get(key, 0))


func _slot_btn(eq: Dictionary, key: String, label: String) -> Button:
	var id := _slot_item(eq, key)
	var b := btn("%s
%s" % [label, item_name(id).substr(0, 4) if id > 0 else "—"], func() -> void:
		sel_slot = key
		refresh(true), 84)
	b.custom_minimum_size.y = 54
	b.add_theme_font_size_override("font_size", 13)
	b.toggle_mode = true
	b.set_pressed_no_signal(sel_slot == key)
	if id > 0 and main.data.armors.has(id) and int(eq.get("dur", {}).get(str(id), 1)) <= 0:
		b.add_theme_color_override("font_color", UiTheme.BAD)      # 耐久用盡
	return b


func _build_equip(ch: Dictionary) -> void:
	var eq: Dictionary = ch.get("equip", {})
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var sc := scroll()
	row.add_child(sc)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(right)
	# 紙娃娃: 3 欄 (頭/項鍊/戒) (身/靴)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	left.add_child(g)
	for s in ["head", "necklace", "ring", "body", "boots"]:
		g.add_child(_slot_btn(eq, s, slot_name(s)))
	left.add_child(lbl("武器（★ = 現用）", 13, UiTheme.DIM))
	var hw := HBoxContainer.new()
	hw.add_theme_constant_override("separation", 4)
	left.add_child(hw)
	for i in RulesEquip.WEAPON_SLOTS:
		hw.add_child(_slot_btn(eq, "w%d" % i, "武%d%s" % [i + 1, "★" if int(eq.get("wslot", 0)) == i else ""]))
	var hj := HBoxContainer.new()
	hj.add_theme_constant_override("separation", 4)
	left.add_child(hj)
	for i in 2:
		hj.add_child(_slot_btn(eq, "j%d" % i, "石%d" % (i + 1)))
	# 右: 總計 + 揀中格詳情
	var ab: Dictionary = main.sim._armor_bonus(ch) if main.sim != null else {}
	var lv := int(ch.get("level", 1))
	right.add_child(lbl("物防 %d  物迴避 %d%%" % [RulesCombat.player_def(lv) + int(ab.get("def", 0)), int(ab.get("evade", 0))], 15, UiTheme.GOLD))
	right.add_child(lbl("術防 %d  術迴避 %d%%" % [RulesStats.player_spell_def(lv, int(ch["attrs"].get("spi", 0))) + int(ab.get("sdef", 0)),
		int(ab.get("sevade", 0))], 15, UiTheme.GOLD))
	right.add_child(hsep())
	if sel_slot == "":
		right.add_child(wrap_lbl("撳左邊格睇詳情；換裝去背包揀件防具撳「裝備」。", 13, UiTheme.DIM))
		right.add_child(btn("開背包", func() -> void:
			close()
			main.hud.bag_panel().open_filter("")))
		return
	var id := _slot_item(eq, sel_slot)
	if id == 0:
		right.add_child(lbl("（空格）", 15, UiTheme.DIM))
		if sel_slot.begins_with("w"):
			_weapon_switch_btn(right, eq, int(sel_slot.substr(1)))
		right.add_child(btn("開背包揀", func() -> void:
			close()
			main.hud.bag_panel().open_filter("")))
		return
	right.add_child(lbl(item_name(id), 17, UiTheme.GOLD))
	for s in item_desc(id):
		right.add_child(wrap_lbl(str(s), 13, UiTheme.DIM))
	if main.data.armors.has(id):
		right.add_child(lbl(armor_dur_text(ch, id), 13))
		right.add_child(btn("卸下", func() -> void: main._send({"t": "unequip", "part": sel_slot})))
	elif sel_slot.begins_with("w"):
		var ws := int(sel_slot.substr(1))
		right.add_child(lbl(armor_dur_text(ch, id), 13))
		_weapon_switch_btn(right, eq, ws)
		right.add_child(btn("卸下", func() -> void: main._send({"t": "unequip", "part": "weapon", "wslot": ws})))
	elif sel_slot.begins_with("j"):
		var js := int(sel_slot.substr(1))
		right.add_child(btn("卸下", func() -> void: main._send({"t": "equip_jewel", "item": 0, "slot": js})))


# 專長頁 (S01c, spec 01 §8): 12 項專長，等級 1~4 = 藍/綠/紅/紫，顯示上限；天文 lv≥1 + 帶渾天儀顯示各城天氣
const EXPERT_LV_COLOR := [Color(0.6, 0.6, 0.6), Color(0.4, 0.6, 1.0), Color(0.4, 0.85, 0.4), Color(0.95, 0.35, 0.3), Color(0.75, 0.4, 0.95)]

func _build_expert(ch: Dictionary) -> void:
	var d = main.data
	var cls_id := str(ch.get("classId", ""))
	var sc := scroll()
	body.add_child(sc)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 4)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(g)
	var exp: Dictionary = ch.get("expert", {})
	for sk in d.experts.get("skills", {}):
		var def: Dictionary = d.experts["skills"][sk]
		var cap: int = RulesExpert.cap_of(d.experts, cls_id, sk)
		var lv: int = main.sim.expert_lv(ch, sk) if main.sim != null else 0
		g.add_child(lbl(String(def["name"]), 14))
		if cap <= 0:
			g.add_child(lbl("未解鎖", 13, UiTheme.DIM))
			g.add_child(lbl("", 13))
		else:
			g.add_child(lbl("Lv%d / 上限%d" % [lv, cap], 14, EXPERT_LV_COLOR[lv]))
			g.add_child(lbl("%d/%d exp" % [int(exp.get(sk, 0)), int(d.experts["levelExp"][cap - 1])], 12, UiTheme.DIM))
	body.add_child(hsep())
	var weather: Array = main.sim.view_weather() if main.sim != null else []
	if weather.is_empty():
		body.add_child(wrap_lbl("天文 lv≥1 + 帶渾天儀（可睇各城天氣/天災情報）", 13, UiTheme.DIM))
	else:
		body.add_child(lbl("各城天氣（渾天儀）", 15, UiTheme.GOLD))
		for w in weather:
			body.add_child(lbl("%s：%s" % [str(w["name"]), str(w["disaster"]) if str(w["disaster"]) != "" else "平靜"], 13))


# 生產技能頁 (Step 12): 初階 6 項 + 進階 5 項 等級/經驗/工具
func _build_work(ch: Dictionary) -> void:
	var d = main.data
	var sc := scroll()
	body.add_child(sc)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 4)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(g)
	var cfg: Dictionary = d.work_meta["level"]
	var keys: Array = d.work.keys() + d.work_adv.keys()
	for sk in keys:
		var def: Dictionary = d.work.get(sk, d.work_adv.get(sk, {}))
		var lv: int = main.sim.work_lv(ch, sk)
		var w: Dictionary = ch.get("workLv", {}).get(sk, {})
		var tool: Dictionary = ch.get("tools", {}).get(sk, {})
		var t := "%s  " % def["name"]
		if lv <= 0:
			t += "未解鎖（初階 %d 級）" % int(def.get("unlockLv", 50))
		else:
			t += "Lv%d  %d/%d" % [lv, int(w.get("exp", 0)), RulesWork.exp_to_next(lv, cfg)]
		if not tool.is_empty():
			t += "   工具耐久 %d" % int(tool["dur"])
		g.add_child(lbl(t, 14, UiTheme.DIM if lv <= 0 else UiTheme.GOLD if d.work_adv.has(sk) else UiTheme.TEXT))
	body.add_child(wrap_lbl("初階: 城外用工具工作。進階: 初階 50 級解鎖，去許昌廚房/藥房/工房做；工具店有工具賣。", 13, UiTheme.DIM))


func _weapon_switch_btn(p: Control, eq: Dictionary, ws: int) -> void:
	var cur := int(eq.get("wslot", 0)) == ws
	var b := btn("現用緊" if cur else "切換做現用", func() -> void: main._send({"t": "switch_weapon", "wslot": ws}))
	b.disabled = cur
	p.add_child(b)

