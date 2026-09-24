class_name BagPanel
extends GamePanel
# 背包面板: 頁籤 背包 / 天地商行(倉庫)。左 = 裝備列 + 物品格；右 = 詳情 + 動作掣。
# 一切由玩家揀、玩家撳確認（冇「自動裝第一件」）。filter="spell" = 由空快捷格撳入嚟，只顯示術書。

const CELL := 58.0
var sel := 0                  # 揀中物品 id（0 = 冇）
var sel_slot := ""            # 揀中裝備格: "weapon" / "jewel0" / "jewel1" / "book0".."book2"
var filter := ""
var want_slot := -1           # 由快捷格入嚟: 裝落邊格


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "背包"
	set_tabs(["背包", "天地商行"])


func open_filter(f: String, slot := -1) -> void:
	filter = f
	want_slot = slot
	sel = 0
	sel_slot = ""
	tab = 0
	set_tabs(tab_names)
	open()


func set_tab(i: int) -> void:
	sel = 0
	sel_slot = ""
	super(i)


func close() -> void:
	filter = ""
	want_slot = -1
	super()


func sig() -> String:
	var ch: Dictionary = main.ch
	return JSON.stringify([tab, sel, sel_slot, filter, ch.get("bag", []), ch.get("storage", []), ch.get("equip", {}),
		ch.get("gold", 0), ch.get("storageSub", false), ch.get("tools", {}), ch.get("level", 1)])


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
		_build_equip_strip(left, ch)
		if filter == "spell":
			left.add_child(btn("只顯示術書  ✕ 顯示全部", func() -> void:
				filter = ""
				refresh(true)))
		_build_grid(left, _bag_list(ch))
		_build_detail(right, ch)
	else:
		_build_storage(left, right, ch)


func _bag_list(ch: Dictionary) -> Array:
	var out: Array = []
	for b in ch["bag"]:
		if filter == "spell" and not main.data.spell_by_item.has(int(b["id"])):
			continue
		out.append(b)
	return out


# 裝備列: 武器 / 寶石 1-2 / 快捷 1-3（術書職業先有）
func _build_equip_strip(parent: Control, ch: Dictionary) -> void:
	var eq: Dictionary = ch.get("equip", {})
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	parent.add_child(h)
	var slots := [["weapon", "武", int(eq.get("weapon", 0))]]
	var jews: Array = eq.get("jewels", [0, 0])
	for i in 2:
		slots.append(["jewel%d" % i, "石%d" % (i + 1), int(jews[i])])
	if main.class_has_spells():
		var books: Array = eq.get("spellbooks", [0, 0, 0])
		for i in 3:
			slots.append(["book%d" % i, "快%d" % (i + 1), int(books[i])])
	for s in slots:
		var id: int = s[2]
		var t: String = s[1] + "\n" + (item_name(id).substr(0, 3) if id > 0 else "—")
		var b := btn(t, func() -> void:
			sel_slot = String(s[0])
			sel = id
			refresh(true), 52)
		b.custom_minimum_size.y = 52
		b.add_theme_font_size_override("font_size", 12)
		b.toggle_mode = true
		b.set_pressed_no_signal(sel_slot == String(s[0]))
		h.add_child(b)


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
			sel_slot = ""
			refresh(true), CELL)
		cell.custom_minimum_size = Vector2(CELL, CELL)
		cell.add_theme_font_size_override("font_size", 12)
		cell.add_theme_color_override("font_color", _kind_color(id))
		cell.toggle_mode = true
		cell.set_pressed_no_signal(sel == id and sel_slot == "")
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
		if sel_slot != "":
			p.add_child(lbl("（空格）", 16, UiTheme.DIM))
			if sel_slot.begins_with("book"):
				p.add_child(btn("揀術書裝落呢格", func() -> void:
					want_slot = int(sel_slot.trim_prefix("book"))
					filter = "spell"
					sel_slot = ""
					refresh(true)))
		else:
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
	# 裝備格揀中: 卸
	if sel_slot.begins_with("jewel"):
		var js := int(sel_slot.trim_prefix("jewel"))
		p.add_child(btn("卸下寶石", func() -> void: main._send({"t": "equip_jewel", "item": 0, "slot": js})))
		return
	if sel_slot.begins_with("book"):
		var bs := int(sel_slot.trim_prefix("book"))
		p.add_child(btn("由快捷 %d 卸下" % (bs + 1), func() -> void: main._send({"t": "equip_spellbook", "item": 0, "slot": bs})))
		return
	if sel_slot == "weapon":
		p.add_child(lbl("裝備緊", 14, UiTheme.GOOD))
		return
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
	if d.heals.has(id):
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
