class_name AutoPanel
extends GamePanel
# 自動掛機設定 (U-fix): 撳「自動」先彈呢個窗，列附近見到嘅怪名，揀邊幾種先自動打；
# 冇揀（全部剔走）= 打晒（同原本行為一致）。仲有「唔好走出呢個場景」開關 (auto_roam)。

func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "自動掛機設定"
	set_tabs([])


func sig() -> String:
	return JSON.stringify([main.auto, main.auto_whitelist, main.auto_roam, main.ents.size()])


func _nearby_names() -> Array:
	var names := {}
	for e in main.ents:
		if bool(e.get("mob", false)) and int(e.get("hp", 0)) > 0:
			names[str(e["name"])] = true
	var out: Array = names.keys()
	out.sort()
	return out


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	list.add_child(wrap_lbl("揀邊幾種怪先自動打（冇揀 = 打晒附近嘅怪）：", 13, UiTheme.DIM))
	var names := _nearby_names()
	if names.is_empty():
		list.add_child(lbl("（附近見唔到怪，行埋去先揀）", 13, UiTheme.DIM))
	for nm in names:
		var on := bool(main.auto_whitelist.has(nm))
		var b := btn("%s %s" % ["✓" if on else "☆", nm], func() -> void:
			if main.auto_whitelist.has(nm):
				main.auto_whitelist.erase(nm)
			else:
				main.auto_whitelist[nm] = true
			refresh(true))
		list.add_child(b)
	list.add_child(hsep())
	list.add_child(btn("清空白名單（打晒）", func() -> void:
		main.auto_whitelist.clear()
		refresh(true)))
	list.add_child(hsep())
	list.add_child(btn("跨場景搵怪：%s" % ("開" if main.auto_roam else "關（留喺呢個場景）"), func() -> void:
		main.auto_roam = not main.auto_roam
		refresh(true)))
	list.add_child(hsep())
	list.add_child(btn("開始自動掛機", func() -> void:
		main.hud.set_auto(true)
		main._hud_auto(true)
		close(), 200))
