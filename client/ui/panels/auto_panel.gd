class_name AutoPanel
extends GamePanel
# 自動掛機設定 (U-fix): 撳「自動」先彈呢個窗，列附近見到嘅怪名，揀邊幾種先自動打；
# 冇揀（全部剔走）= 打晒（同原本行為一致）。仲有「唔好走出呢個場景」開關 (auto_roam)。

func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "自動掛機設定"
	compact()
	set_tabs([])


func sig() -> String:
	return JSON.stringify([main.auto, main.auto_whitelist, main.auto_roam, main.auto_skill, main.pk_mode, main.ents.size()])


func _nearby_names() -> Array:
	var names := {}
	var me = main._me()
	for e in main.ents:
		if not (main._is_targetable(e) and int(e.get("hp", 0)) > 0):
			continue
		if me != null:
			if str(main.sim.zone_view(int(e.x), int(e.y)).get("id", "")) != str(main.sim.zone_view(int(me.x), int(me.y)).get("id", "")):
				continue
		names[str(e["name"])] = true
	var out: Array = names.keys()
	out.sort()
	return out


func _build_body() -> void:
	# 開關掣放最頂，唔使拉晒成頁怪先撳到（之前個 bug：撳「自動」淨係見到揀怪表，冇開關）
	body.add_child(btn("開始自動掛機", func() -> void:
		main.hud.set_auto(true)
		main._hud_auto(true)
		close(), 160))
	body.add_child(btn("清空白名單（打晒附近）", func() -> void:
		main.auto_whitelist.clear()
		refresh(true)))
	body.add_child(btn("跨場景搵怪：%s" % ("開" if main.auto_roam else "關（留喺呢個場景）"), func() -> void:
		main.auto_roam = not main.auto_roam
		refresh(true)))
	body.add_child(hsep())
	body.add_child(wrap_lbl("自動放招（剔咗先放；攻擊術同絕招，入射程 + MP/SP/冷卻夠）：", 11, UiTheme.DIM))
	for sl in main.hud.skill_slots():
		var key := ""
		var nm := ""
		if String(sl["kind"]) == "spell" and int(sl["item"]) > 0:
			var def: Dictionary = main.data.spell_by_item.get(int(sl["item"]), {})
			if String(def.get("kind", "")) != "attack":
				continue
			key = "s%d" % int(sl["slot"])
			nm = "術 " + String(def.get("name", "?"))
		elif String(sl["kind"]) == "ult" and String(sl["ult"]) != "":
			key = "u:%s" % String(sl["ult"])
			nm = "絕 " + String(sl["label"])
		if key == "":
			continue
		var k: String = key
		body.add_child(btn("%s %s" % ["✓" if bool(main.auto_skill.get(k, false)) else "☆", nm], func() -> void:
			main.auto_skill[k] = not bool(main.auto_skill.get(k, false))
			refresh(true)))
	body.add_child(hsep())
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	list.add_child(wrap_lbl("揀邊幾種怪先自動打（冇揀 = 打晒附近嘅怪；顯示當前場景所有怪）：", 11, UiTheme.DIM))
	var names := _nearby_names()
	if names.is_empty():
		list.add_child(lbl("（當前場景冇怪）", 11, UiTheme.DIM))
	for nm in names:
		var on := bool(main.auto_whitelist.has(nm))
		var b := btn("%s %s" % ["✓" if on else "☆", nm], func() -> void:
			if main.auto_whitelist.has(nm):
				main.auto_whitelist.erase(nm)
			else:
				main.auto_whitelist[nm] = true
			refresh(true))
		list.add_child(b)
