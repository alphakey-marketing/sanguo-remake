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


const NEARBY_RANGE := 14   # 揀怪表只顯示呢個 Chebyshev 距離之內嘅怪（同 zone），唔好成張圖咁多

func _nearby_names() -> Array:
	var names := {}
	var me = main._me()
	for e in main.ents:
		if not (bool(e.get("mob", false)) and int(e.get("hp", 0)) > 0):
			continue
		if me != null:
			if str(main.sim.zone_view(int(e.x), int(e.y)).get("id", "")) != str(main.sim.zone_view(int(me.x), int(me.y)).get("id", "")):
				continue
			if main._mob_dist(me, e) > NEARBY_RANGE:
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
		close(), 200))
	body.add_child(btn("清空白名單（打晒附近）", func() -> void:
		main.auto_whitelist.clear()
		refresh(true)))
	body.add_child(btn("跨場景搵怪：%s" % ("開" if main.auto_roam else "關（留喺呢個場景）"), func() -> void:
		main.auto_roam = not main.auto_roam
		refresh(true)))
	body.add_child(hsep())
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	list.add_child(wrap_lbl("揀邊幾種怪先自動打（冇揀 = 打晒附近嘅怪；只顯示附近 %d 格內嘅怪）：" % NEARBY_RANGE, 13, UiTheme.DIM))
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
