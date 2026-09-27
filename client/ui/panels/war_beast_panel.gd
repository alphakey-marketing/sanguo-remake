class_name WarBeastPanel
extends GamePanel
# 戰騎面板 (U01，spec 07 §8/§9): 頁 0「戰騎」= 出戰嗰隻嘅狀態 + 加點 + 練戰鬥/友好特技；
# 頁 1「馬廄」= 全部戰騎 + 出戰/收回/賣出 + 馴養買新 + NPC 拍賣場（戰騎部分）。
# 全部讀 sim.beast_view()/sim.auction_view()，經 main._send 發意圖。


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "戰騎"
	tab_names = ["戰騎", "馬廄"]


func open_tab(i: int) -> void:
	tab = i
	set_tabs(tab_names)
	open()


func _view() -> Dictionary:
	return main.sim.beast_view(main.my_id)


func _aview() -> Dictionary:
	return main.sim.auction_view(main.my_id)


func sig() -> String:
	return JSON.stringify([tab, _view(), _aview()])


func _wcfg() -> Dictionary:
	return main.data.war_beasts


func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	return g


func _fill(b: Button) -> Button:
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _build_body() -> void:
	var v := _view()
	if v.is_empty():
		return
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	if tab == 0:
		_build_active(list, v)
	else:
		_build_stable(list, v)


func _active(v: Dictionary) -> Dictionary:
	var active_uid := int(v.get("active", 0))
	if active_uid == 0:
		return {}
	for wb in v["list"]:
		if int(wb["uid"]) == active_uid:
			return wb
	return {}


# ---- 頁 0: 出戰嗰隻 ----
func _build_active(list: VBoxContainer, v: Dictionary) -> void:
	var wb := _active(v)
	if wb.is_empty():
		list.add_child(wrap_lbl("身邊冇出戰戰騎。去馬廄馴養或者出戰。", 15, UiTheme.DIM))
		return
	var an: Dictionary = v["attrNames"]
	var uid := int(wb["uid"])
	var effects: Array = []
	for k in (wb["effects"] as Dictionary):
		effects.append(k)
	var lines: Array = [
		"%s（%s・%d 級）" % [wb["name"], wb["breedName"], int(wb["level"])],
		"經驗 %d/%d　忠誠 %d" % [int(wb["exp"]), int(wb["needExp"]), int(wb["loyalty"])],
		"HP %d/%d　MP %d/%d　攻擊 %d　防禦 %d" % [int(wb["hp"]), int(wb["hpMax"]), int(wb["mp"]), int(wb["mpMax"]), int(wb["atk"]), int(wb["def"])],
		"%s %d　%s %d　%s %d　%s %d" % [an["pow"], int(wb["attrs"]["pow"]), an["body"], int(wb["attrs"]["body"]),
			an["spirit"], int(wb["attrs"]["spirit"]), an["agi"], int(wb["attrs"]["agi"])]]
	if not effects.is_empty():
		lines.append("友好效果：" + "、".join(effects))
	list.add_child(wrap_lbl("\n".join(lines), 15))
	# 屬性點
	if int(wb["attrPts"]) > 0:
		list.add_child(hsep())
		list.add_child(lbl("屬性點 %d：揀屬性 +1" % int(wb["attrPts"]), 15, UiTheme.GOLD))
		var pg := _grid(4)
		list.add_child(pg)
		for at in (v["attrs"] as Array):
			var aa: String = at
			pg.add_child(_fill(btn(String(an[aa]).substr(0, 2), func() -> void: main._send({"t": "beast_point", "uid": uid, "attr": aa}))))
	# 戰鬥特技
	list.add_child(hsep())
	list.add_child(lbl("戰鬥特技（戰鬥技點 %d）" % int(wb["battlePts"]), 15, UiTheme.GOLD))
	for s in (wb["skills"] as Array):
		var sid := String(s["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(wrap_lbl("%s（%s）%d 級" % [s["name"], s["kind"], int(s["level"])], 14))
		var b := btn("練" if String(s["why"]) == "" else String(s["why"]), func() -> void: main._send({"t": "beast_train", "uid": uid, "skill": sid}), 96)
		b.disabled = String(s["why"]) != ""
		row.add_child(b)
		list.add_child(row)
	# 友好特技
	list.add_child(hsep())
	list.add_child(lbl("友好特技（友好技點 %d）" % int(wb["friendPts"]), 15, UiTheme.GOLD))
	for s in (wb["friends"] as Array):
		var sid2 := String(s["id"])
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 6)
		var learned := bool(s["learned"])
		row2.add_child(wrap_lbl("%d階 %s%s（%d 技點）" % [int(s["tier"]), s["name"], "（已學）" if learned else "", int(s["cost"])], 14))
		if not learned:
			var b2 := btn("學", func() -> void: main._send({"t": "beast_friend_train", "uid": uid, "breed": String(wb["breed"]), "skill": sid2}), 64)
			row2.add_child(b2)
		list.add_child(row2)
	# 賣出
	list.add_child(hsep())
	var sb := btn("賣出（%d 金）" % int(wb["sellPrice"]) if String(wb["sellWhy"]) == "" else String(wb["sellWhy"]),
		func() -> void: main._send({"t": "beast_sell", "uid": uid}))
	sb.disabled = String(wb["sellWhy"]) != ""
	list.add_child(sb)


# ---- 頁 1: 馬廄 ----
func _build_stable(list: VBoxContainer, v: Dictionary) -> void:
	var cfg := _wcfg()
	var at := String(v["stable"])
	var at_name := String(main.data.facilities.get(at, {}).get("name", ""))
	var ms: Array = v["list"]
	list.add_child(wrap_lbl("%s　金 %d　戰騎 %d/%d" % ["喺" + at_name if at != "" else "唔喺馬廄（出戰/收回/馴養要去馬廄）",
		int(v["gold"]), ms.size(), int(v["maxOwned"])], 15, UiTheme.TEXT if at != "" else UiTheme.DIM))
	for wb in ms:
		var uid := int(wb["uid"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var where: String = {"with": "出戰中", "stable": "寄喺" + String(wb["stableName"])}.get(String(wb["where"]), "")
		row.add_child(wrap_lbl("%s（%s・%d 級）忠誠 %d　%s" % [wb["name"], wb["breedName"], int(wb["level"]), int(wb["loyalty"]), where], 14))
		if at != "":
			if String(wb["where"]) == "stable":
				row.add_child(btn("出戰", func() -> void: main._send({"t": "beast_deploy", "uid": uid, "on": true}), 64))
			else:
				row.add_child(btn("收回", func() -> void: main._send({"t": "beast_deploy", "uid": uid, "on": false}), 64))
		list.add_child(row)
	if at == "":
		return
	list.add_child(hsep())
	var full := ms.size() >= int(v["maxOwned"])
	var gold := int(v["gold"])
	list.add_child(lbl("馴養新戰騎", 15, UiTheme.GOLD))
	var g := _grid(2)
	list.add_child(g)
	for b in (v["breeds"] as Array):
		var bid := String(b["id"])
		var bb := _fill(btn("%s（%s・%d 金）" % [b["name"], b["element"], int(b["price"])], func() -> void: main._send({"t": "beast_adopt", "breed": bid})))
		bb.disabled = full or gold < int(b["price"])
		g.add_child(bb)
	list.add_child(hsep())
	_build_auction(list, full, gold)


# NPC 拍賣場（戰騎部分，S07d）
func _build_auction(list: VBoxContainer, full: bool, gold: int) -> void:
	var a := _aview()
	if a.is_empty():
		return
	list.add_child(lbl("NPC 拍賣場（每日換貨）", 15, UiTheme.GOLD))
	var any := false
	for lot in (a["lots"] as Array):
		if String(lot["kind"]) != "beast":
			continue
		any = true
		var lid := int(lot["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(wrap_lbl("%s %d 級（%d 金）" % [lot["name"], int(lot["level"]), int(lot["price"])], 14))
		var bb := btn("買", func() -> void: main._send({"t": "auction_buy", "lot": lid}), 64)
		bb.disabled = full or not bool(lot["afford"])
		row.add_child(bb)
		list.add_child(row)
	if not any:
		list.add_child(wrap_lbl("今日冇戰騎上架，聽日再嚟。", 14, UiTheme.DIM))
