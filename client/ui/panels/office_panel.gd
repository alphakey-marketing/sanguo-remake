class_name OfficePanel
extends GamePanel
# 官宅面板 (U05，spec 08 §1~2): 頁 0「頭銜」討取 + 俸祿；頁 1「官令」接令/交令/放棄；
# 頁 2「義舉/進貢」繳交義舉證明 + 進貢物資換城池好感；頁 3「名額競爭」顯示每月守位結果。
# 全部讀 sim 既有 read-model（merit_list/city_favor_view/title_contest_view），經 main._send 發意圖。


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "官宅"
	tab_names = ["頭銜", "官令", "義舉/進貢", "名額競爭", "內政"]


func open_tab(i: int) -> void:
	tab = i
	set_tabs(tab_names)
	open()


func sig() -> String:
	var ch: Dictionary = main.ch
	return JSON.stringify([tab, ch.get("titleRank", 0), ch.get("fame", 0), ch.get("gold", 0),
		ch.get("office", {}), main.sim.merit_list(ch), main.sim.city_favor_view(ch),
		main.sim.title_contest_view(main.my_id), main.sim.domestic_view(main.my_id)])


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	match tab:
		0: _build_title(list)
		1: _build_order(list)
		2: _build_merit(list)
		3: _build_contest(list)
		_: _build_domestic(list)


# ---- 頁 0: 頭銜 ----
func _build_title(list: VBoxContainer) -> void:
	var ch: Dictionary = main.ch
	var titles: Array = main.data.titles
	var rank := int(ch.get("titleRank", 0))
	list.add_child(wrap_lbl("目前頭銜：%s（第 %d 階）　名聲 %d　金 %d" % [RulesTitle.name_of(titles, rank), rank,
		int(ch.get("fame", 0)), int(ch.get("gold", 0))], 15, UiTheme.GOLD))
	if rank > 0:
		list.add_child(wrap_lbl("行動力上限 %d　每月俸祿 %d" % [RulesTitle.ap_max(titles, rank, 100), RulesTitle.salary(titles, rank)], 14, UiTheme.DIM))
	list.add_child(hsep())
	list.add_child(lbl("討取頭銜", 15, UiTheme.GOLD))
	var shown := 0
	for t in titles:
		var r := int(t["rank"])
		if r <= rank:
			continue
		shown += 1
		if shown > 8:
			break
		var why := RulesTitle.claim_check(titles, r, rank, int(ch.get("fame", 0)), int(ch.get("gold", 0)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(wrap_lbl("第 %d 階「%s」　名聲要 %d　金要 %d" % [r, String(t["name"]), int(t["fame"]), int(t["gold"])], 14))
		var b := btn("討取" if why == "" else why, func() -> void: main._send({"t": "claim_title", "rank": r}), 96)
		b.disabled = why != ""
		row.add_child(b)
		list.add_child(row)
	if shown == 0:
		list.add_child(wrap_lbl("已經係最高階。", 14, UiTheme.DIM))


# ---- 頁 1: 官令 ----
func _build_order(list: VBoxContainer) -> void:
	var ch: Dictionary = main.ch
	var od: Dictionary = (ch.get("office", {}) as Dictionary).get("order", {})
	if not od.is_empty():
		list.add_child(wrap_lbl("手上官令：%s" % main.sim.order_text(ch), 15, UiTheme.GOLD))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_fill(btn("交令", func() -> void: main._send({"t": "office_turnin"}))))
		row.add_child(_fill(btn("放棄", func() -> void: main._send({"t": "office_abandon"}))))
		list.add_child(row)
		return
	list.add_child(wrap_lbl("每日限接一條官令，去官宅先接得。", 14, UiTheme.DIM))
	list.add_child(hsep())
	for o in main.data.office["orders"]:
		var oid := String(o["id"])
		var why := String(main.sim.order_block(ch, oid))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		r.add_child(wrap_lbl("%s：%s" % [String(o["name"]), String(o.get("desc", ""))], 14))
		var b := btn("接" if why == "" else why, func() -> void: main._send({"t": "office_order", "order": oid}), 96)
		b.disabled = why != ""
		r.add_child(b)
		list.add_child(r)


# ---- 頁 2: 義舉/進貢 ----
func _build_merit(list: VBoxContainer) -> void:
	var ch: Dictionary = main.ch
	list.add_child(lbl("義舉證明（許昌朝廷官員受理，換名聲）", 15, UiTheme.GOLD))
	for it in main.sim.merit_list(ch):
		var owned := int(it["owned"])
		if owned <= 0:
			continue
		var iid := int(it["id"])
		var why := String(it["why"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(wrap_lbl("%s（%s）x%d　名聲 +%d" % [it["name"], it["catName"], owned, int(it["fame"])], 14))
		var b := btn("繳交" if why == "" else why, func() -> void: main._send({"t": "merit_turnin", "item": iid}), 96)
		b.disabled = why != ""
		row.add_child(b)
		list.add_child(row)
	list.add_child(hsep())
	list.add_child(lbl("進貢物資（捐獻處，換城池好感）", 15, UiTheme.GOLD))
	for c in main.sim.city_favor_view(ch):
		list.add_child(wrap_lbl("%s：好感 %d" % [c["name"], int(c["favor"])], 14))
	list.add_child(hsep())
	var any := false
	for b in (ch.get("bag", []) as Array):
		var iid2 := int(b["id"])
		if not main.data.donation_rates.has(iid2):
			continue
		any = true
		var n := int(b["n"])
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 6)
		row2.add_child(wrap_lbl("%s x%d" % [item_name(iid2), n], 14))
		row2.add_child(btn("進貢 1 件", func() -> void: main._send({"t": "city_tribute", "items": [[iid2, 1]]}), 96))
		list.add_child(row2)
	if not any:
		list.add_child(wrap_lbl("背包冇可以進貢嘅物資。", 14, UiTheme.DIM))


# ---- 頁 3: 名額競爭 ----
func _build_contest(list: VBoxContainer) -> void:
	var v: Dictionary = main.sim.title_contest_view(main.my_id)
	if v.is_empty():
		list.add_child(wrap_lbl("冇頭銜，唔使競爭名額。", 14, UiTheme.DIM))
		return
	if bool(v.get("competing", false)):
		list.add_child(wrap_lbl("第 %d 階　名聲 %d　挑戰者 %d 位　每月初一評比守位。" % [int(v["rank"]), int(v["fame"]), int(v.get("competitors", 0))], 15))
	else:
		list.add_child(wrap_lbl("暫時唔使競爭名額。", 14, UiTheme.DIM))
	var last: Dictionary = v.get("last", {})
	if not last.is_empty():
		list.add_child(hsep())
		if bool(last.get("won", false)):
			list.add_child(wrap_lbl("上次守位成功（分數 %d，NPC 最高 %d）。" % [int(last.get("score", 0)), int(last.get("npcBest", 0))], 14, UiTheme.GOOD))
		else:
			list.add_child(wrap_lbl("上次守位失敗（分數 %d，NPC 最高 %d），跌落第 %d 階。" %
				[int(last.get("score", 0)), int(last.get("npcBest", 0)), int(last.get("dropTo", 0))], 14, UiTheme.BAD))


# ---- 頁 4: 內政 + 城池屬性 ----
func _build_domestic(list: VBoxContainer) -> void:
	var v: Dictionary = main.sim.domestic_view(main.my_id)
	if v.is_empty() or String(v.get("office", "")) == "":
		list.add_child(wrap_lbl("要去官宅先做得內政。", 14, UiTheme.DIM))
		return
	list.add_child(lbl("%s　城池屬性" % String(v.get("cityName", "")), 15, UiTheme.GOLD))
	for r in (v.get("attrs", []) as Array):
		list.add_child(wrap_lbl("%s：%d" % [String(r["name"]), int(r["val"])], 14))
	list.add_child(hsep())
	list.add_child(lbl("內政工作（每次扣行動力 %d）" % int(v.get("apCost", 0)), 15, UiTheme.GOLD))
	for j in (v.get("jobs", []) as Array):
		var can := bool(j.get("can", false))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(wrap_lbl("%s：%s +%d（%s 專長 %d 級）" % [String(j["name"]), String(j["attrName"]),
			int(j["gain"]), String(j["expert"]), int(j["expertLv"])], 14))
		var b := btn("進行" if can else String(j["why"]), func() -> void: main._send({"t": "domestic", "job": String(j["id"])}), 96)
		b.disabled = not can
		row.add_child(b)
		list.add_child(row)


func _fill(b: Button) -> Button:
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b
