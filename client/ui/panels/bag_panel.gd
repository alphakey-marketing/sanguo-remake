class_name BagPanel
extends GamePanel
# 背包面板: 頁籤 背包 / 天地商行(倉庫)。左 = 物品格；右 = 詳情 + 動作掣（裝備/卸下一律喺呢度即撳即做）。
# 裝備格紙娃娃睇 char_panel「裝備」頁 (U16: 拆走呢度重複嘅裝備列，避免兩個面板都有一份)。
# 一切由玩家揀、玩家撳確認（冇「自動裝第一件」）。filter="spell" = 由空快捷格撳入嚟，只顯示術書。

const CELL := 58.0
var sel := 0                  # 揀中物品 id（0 = 冇）
var filter := ""
var show_all_weapons := false
var want_slot := -1           # 由快捷格入嚟: 裝落邊格


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "背包"
	set_tabs(["背包", "天地商行", "腳伕"])


func open_filter(f: String, slot := -1) -> void:
	filter = f
	want_slot = slot
	sel = 0
	tab = 0
	set_tabs(tab_names)
	open()


func set_tab(i: int) -> void:
	sel = 0
	super(i)


func close() -> void:
	filter = ""
	want_slot = -1
	super()


func sig() -> String:
	var ch: Dictionary = main.ch
	return JSON.stringify([tab, sel, filter, ch.get("bag", []), ch.get("storage", []), ch.get("equip", {}),
		ch.get("gold", 0), ch.get("storageSub", false), ch.get("tools", {}), ch.get("level", 1), ch.get("tiandi", {}), show_all_weapons])


func _build_body() -> void:
	var ch: Dictionary = main.ch
	if ch.is_empty():
		return
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.4
	row.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	if tab == 0:
		if filter == "spell":
			left.add_child(btn("只顯示術書  ✕ 顯示全部", func() -> void:
				filter = ""
				refresh(true)))
		var hidden := _hidden_weapon_count(ch)
		if hidden > 0 or show_all_weapons:
			left.add_child(btn("顯示全部武器 ✓" if show_all_weapons else "已隱藏 %d 件本職唔可裝武器（撳顯示）" % hidden, func() -> void:
				show_all_weapons = not show_all_weapons
				refresh(true)))
		_build_grid(left, _bag_list(ch))
		_build_detail(right, ch)
	elif tab == 1:
		_build_storage(left, right, ch)
	else:
		_build_porter(left, right, ch)


func _bag_list(ch: Dictionary) -> Array:
	var out: Array = []
	for b in ch["bag"]:
		if filter == "spell" and not main.data.spell_by_item.has(int(b["id"])):
			continue
		if not show_all_weapons and not _weapon_usable(ch, int(b["id"])):
			continue                                  # S2-10: 預設唔顯示本職著唔到嘅武器
		out.append(b)
	return out


func _weapon_usable(ch: Dictionary, id: int) -> bool:
	var d: GameData = main.data
	if not d.weapons.has(id):
		return true
	var cls: Dictionary = d.classes.get(str(ch.get("classId", "")), {})
	return (cls.get("weapons", []) as Array).has(str(d.info.get(id, {}).get("cat_label", "")))


func _hidden_weapon_count(ch: Dictionary) -> int:
	var n := 0
	for b in ch["bag"]:
		if not _weapon_usable(ch, int(b["id"])):
			n += 1
	return n


func _build_grid(parent: Control, items: Array) -> void:
	var sc := scroll()
	parent.add_child(sc)
	var g := GridContainer.new()
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	var w := win.size.x * 0.55
	g.columns = maxi(3, int(w / (CELL + 4)))
	sc.add_child(g)
	if items.is_empty():
		parent.add_child(lbl("（空）", 14, UiTheme.DIM))
		return
	var worn := _worn_ids(main.ch) if tab == 0 else []
	for b in items:
		var id := int(b["id"])
		var cell := btn("%s\nx%d%s" % [item_name(id).substr(0, 4), int(b["n"]), " 裝" if worn.has(id) else ""], func() -> void:
			sel = id
			refresh(true), CELL)
		cell.custom_minimum_size = Vector2(CELL, CELL)
		cell.add_theme_font_size_override("font_size", 12)
		cell.add_theme_color_override("font_color", _kind_color(id))
		cell.toggle_mode = true
		cell.set_pressed_no_signal(sel == id)
		g.add_child(cell)


# 身上著緊/裝緊嘅 item id (武器 3 槽 + 5 部位)
func _worn_ids(ch: Dictionary) -> Array:
	var eq: Dictionary = ch.get("equip", {})
	var out: Array = (eq.get("weapons", []) as Array).duplicate()
	for s in RulesEquip.SLOTS:
		out.append(int(eq.get(s, 0)))
	return out


func _kind_color(id: int) -> Color:
	var d: GameData = main.data
	if main.quest_items.has(id):
		return UiTheme.DIM
	if d.weapons.has(id):
		return Color(1, 0.7, 0.45)
	if d.armors.has(id):
		return Color(0.6, 0.85, 1.0)
	if d.heals.has(id):
		return UiTheme.GOOD
	if d.spell_by_item.has(id):
		return Color(0.85, 0.7, 1.0)
	if d.jewel_by_item.has(id):
		return Color(1, 0.95, 0.5)
	return UiTheme.TEXT


func _build_detail(p: Control, ch: Dictionary) -> void:
	if sel == 0:
		p.add_child(lbl("撳物品睇詳情", 14, UiTheme.DIM))
		p.add_child(lbl("金 %d" % int(ch.get("gold", 0)), 15, Color(1, 0.9, 0.5)))
		return
	var d: GameData = main.data
	p.add_child(lbl(item_name(sel), 18, UiTheme.GOLD))
	var sc := scroll()
	sc.custom_minimum_size.y = 60
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(info)
	var desc := item_desc(sel)
	if d.armors.has(sel) and desc.size() > 0:
		desc = [desc[0]]              # 防具數值喺下面比較行顯示，唔重複
	for s in desc:
		info.add_child(wrap_lbl(str(s), 13, UiTheme.DIM))
	if main.quest_items.has(sel):
		info.add_child(lbl("任務道具（唔賣得）", 13, UiTheme.BAD))
	p.add_child(sc)
	var eq: Dictionary = ch.get("equip", {})
	var id := sel
	var lv_ok := int(ch.get("level", 1)) >= int(d.info.get(id, {}).get("req_lv", 0))
	if d.weapons.has(id):
		var cls: Dictionary = d.classes.get(str(ch.get("classId", "")), {})
		if not (cls.get("weapons", []) as Array).has(str(d.info.get(id, {}).get("cat_label", ""))):
			p.add_child(lbl("%s用唔到呢類武器" % str(cls.get("name", "")), 13, UiTheme.BAD))
		else:
			var on := int(eq.get("weapon", 0)) == id
			var b := btn("裝備緊" if on else "裝備武器", func() -> void: main._send({"t": "equip", "item": id}))
			b.disabled = on or not lv_ok
			p.add_child(b)
			# 武器 3 槽【原】: 直接裝落指定槽
			var hw := HBoxContainer.new()
			var ws: Array = eq.get("weapons", [eq.get("weapon", 0), 0, 0])
			for i in ws.size():
				var in_slot := int(ws[i]) == id
				var bw := btn("槽%d%s" % [i + 1, "✓" if in_slot else ""], func() -> void: main._send({"t": "equip", "item": id, "wslot": i}), 56)
				bw.disabled = in_slot or not lv_ok
				hw.add_child(bw)
			p.add_child(lbl("裝落武器槽:", 13))
			p.add_child(hw)
	if d.armors.has(id):
		var ad: Dictionary = d.armors[id]
		var slot := str(ad["slot"])
		var worn := int(eq.get(slot, 0)) == id
		var cur := int(eq.get(slot, 0))
		p.add_child(lbl("部位: %s   %s" % [slot_name(slot), armor_dur_text(ch, id)], 13))
		p.add_child(lbl("身上: %s" % (item_name(cur) if cur > 0 else "（空）"), 13, UiTheme.DIM))
		for c in armor_compare(ch, id):
			p.add_child(lbl(str(c[0]), 13, c[1]))
		if worn:
			p.add_child(btn("卸下%s" % slot_name(slot), func() -> void: main._send({"t": "unequip", "part": slot})))
		else:
			var ba := btn("裝備（%s）" % slot_name(slot), func() -> void: main._send({"t": "equip", "item": id}))
			ba.disabled = not lv_ok
			p.add_child(ba)
		if not lv_ok:
			p.add_child(lbl("等級唔夠", 13, UiTheme.BAD))
	if id == int(d.comm["book"]["item"]):                       # 武將收集冊 (Step 16)
		p.add_child(btn("查閱", func() -> void: main.hud.open_dialog(func() -> Dictionary: return ContextActions.book_dialog(main))))
	if d.heals.has(id) or id == int(d.office["pillItem"]):      # 行動丹 = 回滿行動力 (Step 14)
		p.add_child(btn("使用", func() -> void: main._send({"t": "use_item", "item": id})))
	if d.spell_by_item.has(id):
		var h := HBoxContainer.new()
		for i in 3:
			var b := btn("快%d" % (i + 1), func() -> void:
				main._send({"t": "equip_spellbook", "item": id, "slot": i})
				if want_slot >= 0:
					close(), 50)
			if want_slot == i:
				b.add_theme_color_override("font_color", UiTheme.GOOD)
			h.add_child(b)
		p.add_child(lbl("裝落快捷列:", 13))
		p.add_child(h)
	if d.jewel_by_item.has(id):
		var h2 := HBoxContainer.new()
		var jews: Array = eq.get("jewels", [0, 0])
		for i in 2:
			var on := int(jews[i]) == id
			var b := btn("石%d%s" % [i + 1, "✓" if on else ""], func() -> void: main._send({"t": "equip_jewel", "item": id, "slot": i}), 64)
			b.disabled = on
			h2.add_child(b)
		p.add_child(lbl("裝落寶石欄:", 13))
		p.add_child(h2)
	if d.tool_skill.has(id):         # 初階/進階工具 (Step 12)
		var sk := String(d.tool_skill[id])
		var w: Dictionary = d.work.get(sk, d.work_adv.get(sk, {}))
		p.add_child(btn("裝備%s工具" % str(w.get("name", sk)), func() -> void: main._send({"t": "equip_tool", "skill": sk, "item": id})))
	if bool(ch.get("storageSub", false)) and not main.quest_items.has(id):
		p.add_child(btn("存入天地商行 x1", func() -> void: main._send({"t": "storage_deposit", "item": id, "n": 1})))
	if not main.quest_items.has(id):
		p.add_child(btn("丟低 x1（S08g 城內丟物）", func() -> void: main._send({"t": "drop_item", "item": id, "n": 1})))


# 天地商行頁: 訂閱開關 + 倉庫格 + 攞返 / 代賣
func _build_storage(left: Control, right: Control, ch: Dictionary) -> void:
	var sub := bool(ch.get("storageSub", false))
	left.add_child(btn("退訂天地商行" if sub else "訂閱天地商行（存材料/代賣）", func() -> void:
		main._send({"t": "storage_sub", "on": not sub})))
	if not sub:
		right.add_child(wrap_lbl("訂閱之後可以喺任何地方存/攞材料同代賣。", 14, UiTheme.DIM))
		return
	var st: Array = ch.get("storage", [])
	_build_grid(left, st)
	var n := 0
	for b in st:
		if int(b["id"]) == sel:
			n = int(b["n"])
	if sel == 0 or n == 0:
		right.add_child(lbl("撳倉庫物品", 14, UiTheme.DIM))
		return
	var id := sel
	right.add_child(lbl("%s x%d" % [item_name(id), n], 17, UiTheme.GOLD))
	for s in item_desc(id):
		right.add_child(wrap_lbl(str(s), 13, UiTheme.DIM))
	right.add_child(btn("攞返 x1", func() -> void: main._send({"t": "storage_withdraw", "item": id, "n": 1})))
	right.add_child(btn("全部攞返 x%d" % n, func() -> void: main._send({"t": "storage_withdraw", "item": id, "n": n})))
	right.add_child(btn("代賣 x1  (%d 金)" % main._sell_price(id), func() -> void: main._send({"t": "storage_sell", "item": id, "n": 1})))


# 腳伕頁 (Step 13): 負重滿自動存邊啲材料 + 自動買/賣工具 + 工作區小屋休息
func _build_porter(left: Control, right: Control, ch: Dictionary) -> void:
	var d: GameData = main.data
	var cfg: Dictionary = d.world["tiandi"]
	if not bool(ch.get("storageSub", false)):
		left.add_child(wrap_lbl("要先喺「天地商行」頁訂閱，腳伕先會幫你做嘢。", 14, UiTheme.DIM))
		return
	var td: Dictionary = ch.get("tiandi", {})
	var dep: Array = td.get("deposit", [])
	left.add_child(wrap_lbl("材料多過 %d 件 = 負重滿：勾咗嘅入倉，其餘賣市集" % int(cfg["bagMatCap"]), 13, UiTheme.DIM))
	for sk in d.work:
		var skill := String(sk)
		var on := dep.has(skill)
		left.add_child(btn(("✔ 存 " if on else "　存 ") + str(d.work[sk]["name"]), func() -> void:
			main._send({"t": "tiandi_set", "key": "deposit:" + skill, "on": not on})))
	var buy := bool(td.get("buyTool", false))
	var sell := bool(td.get("sellTool", false))
	right.add_child(lbl("倉庫 %d / %d 件" % [RulesTiandi.stack_total(ch.get("storage", [])), int(cfg["storageCap"])], 15, UiTheme.GOLD))
	right.add_child(btn(("✔ " if buy else "　") + "自動買工具（爛咗買新）", func() -> void:
		main._send({"t": "tiandi_set", "key": "buyTool", "on": not buy})))
	right.add_child(btn(("✔ " if sell else "　") + "自動賣工具（耐久剩 %d）" % int(cfg["toolSellAt"]), func() -> void:
		main._send({"t": "tiandi_set", "key": "sellTool", "on": not sell})))
	right.add_child(hsep())
	right.add_child(btn("工作區小屋休息 (%d 金)" % int(cfg["restCost"]), func() -> void: main._send({"t": "storage_rest"})))
	right.add_child(wrap_lbl("城外先用得；回滿 HP/MP/SP", 12, UiTheme.DIM))
