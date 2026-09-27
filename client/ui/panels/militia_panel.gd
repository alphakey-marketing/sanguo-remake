class_name MilitiaPanel
extends GamePanel
# 義勇軍面板 (U08，spec 08 §6~7): 頁 0「定居」揀城池定居；頁 1「義勇軍」擁護者/成立條件/
# 已成立後顯示名號/根據地/階級/帶兵量。遊說擁護者長按居民另有掣（main._open_npc_attack 旁），
# 呢度淨係顯示擁護者清單。全部讀 sim 既有 read-model（settle_view/militia_view），經 main._send 發意圖。


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "義勇軍"
	tab_names = ["定居", "義勇軍"]


func open_tab(i: int) -> void:
	tab = i
	set_tabs(tab_names)
	open()


func sig() -> String:
	return JSON.stringify([tab, main.sim.settle_view(main.my_id), main.sim.militia_view(main.my_id)])


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	match tab:
		0: _build_settle(list)
		_: _build_militia(list)


# ---- 頁 0: 定居 ----
func _build_settle(list: VBoxContainer) -> void:
	var v: Dictionary = main.sim.settle_view(main.my_id)
	if v.is_empty():
		return
	var home := String(v.get("home", ""))
	var at := String(v.get("at", ""))
	if home != "":
		list.add_child(wrap_lbl("目前定居：%s" % _city_name(v, home), 15, UiTheme.GOLD))
	else:
		list.add_child(wrap_lbl("未定居。企喺城池入面撳「定居」。", 14, UiTheme.DIM))
	list.add_child(hsep())
	for c in (v.get("cities", []) as Array):
		var cid := String(c["id"])
		var here := at == cid
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(wrap_lbl("%s%s" % [String(c["name"]), "（新手城）" if bool(c.get("newbie", false)) else ""], 14))
		var why := "" if here else "要行去嗰度"
		if cid == home:
			why = "已定居"
		var b := btn("定居" if why == "" else why, func() -> void: main._send({"t": "settle", "city": cid}), 96)
		b.disabled = why != ""
		row.add_child(b)
		list.add_child(row)


func _city_name(v: Dictionary, id: String) -> String:
	for c in (v.get("cities", []) as Array):
		if String(c["id"]) == id:
			return String(c["name"])
	return id


# ---- 頁 1: 義勇軍 ----
func _build_militia(list: VBoxContainer) -> void:
	var v: Dictionary = main.sim.militia_view(main.my_id)
	if v.is_empty():
		return
	if bool(v.get("founded", false)):
		list.add_child(wrap_lbl("「%s」　根據地 %s　階級 %s" %
			[String(v["name"]), String(v["cityName"]), String(v["gradeName"])], 15, UiTheme.GOLD))
		list.add_child(wrap_lbl("帶兵量上限 %d　擁護者 %d 人" % [int(v["soldiers"]), int(v.get("supporterCount", 0))], 14))
		list.add_child(hsep())
		list.add_child(lbl("成員", 15, UiTheme.GOLD))
		for s in (v.get("supporters", []) as Array):
			list.add_child(wrap_lbl(String((s as Dictionary).get("name", "")), 14))
		if (v.get("supporters", []) as Array).is_empty():
			list.add_child(wrap_lbl("暫時冇成員。", 14, UiTheme.DIM))
		return
	list.add_child(lbl("成立條件", 15, UiTheme.GOLD))
	for c in (v.get("conditions", []) as Array):
		var ok := bool((c as Dictionary).get("ok", false))
		list.add_child(wrap_lbl(("✔ " if ok else "✘ ") + String((c as Dictionary)["text"]), 14, UiTheme.GOOD if ok else UiTheme.BAD))
	list.add_child(hsep())
	list.add_child(lbl("擁護者（長按居民 → 遊說）", 15, UiTheme.GOLD))
	for s in (v.get("supporters", []) as Array):
		list.add_child(wrap_lbl(String((s as Dictionary).get("name", "")), 14))
	if (v.get("supporters", []) as Array).is_empty():
		list.add_child(wrap_lbl("暫時冇擁護者。", 14, UiTheme.DIM))
	list.add_child(hsep())
	var all_ok := true
	for c in (v.get("conditions", []) as Array):
		if not bool((c as Dictionary).get("ok", false)):
			all_ok = false
	_name_edit = _name_edit if _name_edit != null else LineEdit.new()
	_name_edit.placeholder_text = "義勇軍名號"
	list.add_child(_name_edit)
	_pw_edit = _pw_edit if _pw_edit != null else LineEdit.new()
	_pw_edit.placeholder_text = "暗號"
	list.add_child(_pw_edit)
	var b := btn("起義成立" if all_ok else "未達成立條件", func() -> void:
		main._send({"t": "militia_found", "name": _name_edit.text, "password": _pw_edit.text}), 120)
	b.disabled = not all_ok
	list.add_child(b)


var _name_edit: LineEdit
var _pw_edit: LineEdit
