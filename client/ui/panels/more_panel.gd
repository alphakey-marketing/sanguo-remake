class_name MorePanel
extends GamePanel
# 「更多」選單: 設定（震動）+ 測試用功能（成品前換走）。

const DEBUG_ACTIONS := [
	{"action": "greet", "label": "問好"},
	{"action": "use", "label": "試食(測試)"},
	{"action": "work_mining", "label": "採礦(測試)"},
	{"action": "work_lv", "label": "生產+10級(測試)"},
	{"action": "learn_ults", "label": "學分階絕招(測試)"},
	{"action": "learn_skill", "label": "學特技(測試)"},
]

var _test_open := false


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "更多"


func sig() -> String:
	return JSON.stringify([main.hud.vibrate_on, main.debug_speed, _test_open])


# 2 欄 grid，掣撐滿闊度
func _grid(list: Control) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	list.add_child(g)
	return g


func _gbtn(g: Control, text: String, cb: Callable) -> void:
	var b := btn(text, cb)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(b)


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	var hud = main.hud
	list.add_child(lbl("人物", 16, UiTheme.GOLD))
	var g := _grid(list)
	_gbtn(g, "座騎", func() -> void: hud.mount_panel().open_tab(0))
	_gbtn(g, "戰騎", func() -> void: hud.war_beast_panel().open_tab(0))
	_gbtn(g, "結婚", func() -> void: hud.marriage_panel().open_tab(0))
	_gbtn(g, "登用人才 / 同伴", func() -> void: hud.open_panel("recruit"))
	list.add_child(lbl("勢力", 16, UiTheme.GOLD))
	g = _grid(list)
	_gbtn(g, "官宅", func() -> void: hud.office_panel().open_tab(0))
	_gbtn(g, "義勇軍", func() -> void: hud.militia_panel().open_tab(0))
	_gbtn(g, "營地", func() -> void: hud.camp_panel().open_tab(0))
	_gbtn(g, "民心/法令", func() -> void: hud.civic_panel().open())
	list.add_child(lbl("資訊", 16, UiTheme.GOLD))
	g = _grid(list)
	_gbtn(g, "情報冊 / 傳聞", func() -> void: hud.open_panel("rumor"))
	_gbtn(g, "掉寶表", func() -> void: hud.drop_panel().open())
	_gbtn(g, "完整日誌", func() -> void: hud.log_panel().open())
	_gbtn(g, "說明（新手教程）", func() -> void: hud.help_panel().open())
	list.add_child(lbl("其他", 16, UiTheme.GOLD))
	g = _grid(list)
	_gbtn(g, "貨金商城", func() -> void: hud.mall_panel().open())
	_gbtn(g, "LLM 設定 / 對話", func() -> void: hud.llm_panel().open_tab(0))
	list.add_child(hsep())
	list.add_child(lbl("角色 / 存檔", 16, UiTheme.GOLD))
	g = _grid(list)
	_gbtn(g, "立即存檔（上次：%s）" % SaveSys.ts_text(main.last_save_ts), func() -> void:
		main.save_now()
		refresh(true))
	_gbtn(g, "切換角色 / 存檔位", func() -> void: hud.open_panel("title"))
	_gbtn(g, "設定快捷補品欄", func() -> void: hud.open_panel("potion_setup"))
	list.add_child(hsep())
	list.add_child(lbl("設定", 16, UiTheme.GOLD))
	g = _grid(list)
	_gbtn(g, "移動方式：%s" % ("搖桿" if main.move_mode == "stick" else "撳地行"), func() -> void:
		main._set_move_mode("tap" if main.move_mode == "stick" else "stick")
		main._log("移動方式 %s" % ("搖桿" if main.move_mode == "stick" else "撳地行"))
		refresh(true))
	_gbtn(g, "撳掣震動：%s" % ("開" if hud.vibrate_on else "關"), func() -> void:
		hud.vibrate_on = not hud.vibrate_on
		refresh(true))
	_gbtn(g, "打人模式：%s" % ("開" if main.pk_mode else "關"), func() -> void:
		main.pk_mode = not main.pk_mode
		main._log("打人模式 %s" % ("開" if main.pk_mode else "關"))
		refresh(true))
	list.add_child(wrap_lbl("打人模式：開 = 所有怪/NPC 都可以 target 攻擊；關 = 淨係怪 + 敵對 NPC", 11, UiTheme.DIM))
	list.add_child(hsep())
	list.add_child(btn("測試功能（成品前會換走）  %s" % ("▲ 收起" if _test_open else "▼ 展開"), func() -> void:
		_test_open = not _test_open
		refresh(true)))
	if not _test_open:
		return
	var tg := GridContainer.new()
	tg.columns = 3
	tg.add_theme_constant_override("h_separation", 6)
	list.add_child(tg)
	for a in DEBUG_ACTIONS:
		var act := String(a["action"])
		tg.add_child(btn(String(a["label"]), func() -> void: main._on_debug_pressed(act), 120))
	tg.add_child(btn("升 1 級(測試)", func() -> void: main._on_debug_pressed("level_up"), 120))
	tg.add_child(btn("升 10 級(測試)", func() -> void: main._on_debug_pressed("level_up10"), 120))
	tg.add_child(btn("時間 ×%d(測試)" % main.debug_speed, func() -> void:
		main._on_debug_pressed("speed")
		refresh(true), 120))
