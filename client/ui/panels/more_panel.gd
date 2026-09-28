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


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "更多"


func sig() -> String:
	return JSON.stringify([main.hud.vibrate_on, main.debug_speed])


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	list.add_child(btn("登用人才 / 同伴", func() -> void: main.hud.open_panel("recruit")))
	list.add_child(btn("座騎", func() -> void: main.hud.mount_panel().open_tab(0)))
	list.add_child(btn("戰騎", func() -> void: main.hud.war_beast_panel().open_tab(0)))
	list.add_child(btn("官宅", func() -> void: main.hud.office_panel().open_tab(0)))
	list.add_child(btn("義勇軍", func() -> void: main.hud.militia_panel().open_tab(0)))
	list.add_child(btn("營地", func() -> void: main.hud.camp_panel().open_tab(0)))
	list.add_child(btn("民心/法令", func() -> void: main.hud.civic_panel().open()))
	list.add_child(btn("情報冊（竊聽）", func() -> void: main.hud.open_panel("rumor")))
	list.add_child(btn("LLM 設定 / 對話", func() -> void: main.hud.llm_panel().open_tab(0)))
	list.add_child(btn("結婚", func() -> void: main.hud.marriage_panel().open_tab(0)))
	list.add_child(btn("掉寶表", func() -> void: main.hud.drop_panel().open()))
	list.add_child(btn("完整日誌", func() -> void: main.hud.log_panel().open()))
	list.add_child(hsep())
	list.add_child(lbl("角色 / 存檔", 16, UiTheme.GOLD))
	list.add_child(btn("切換角色 / 選擇存檔位", func() -> void: main.hud.open_panel("title")))
	list.add_child(btn("設定快捷補品欄", func() -> void: main.hud.open_panel("potion_setup")))
	list.add_child(hsep())
	list.add_child(lbl("設定", 16, UiTheme.GOLD))
	var hud = main.hud
	list.add_child(btn("撳掣震動：%s" % ("開" if hud.vibrate_on else "關"), func() -> void:
		hud.vibrate_on = not hud.vibrate_on
		refresh(true)))
	list.add_child(btn("打人模式：%s（開 = 所有怪/NPC 都可以 target 攻擊；關 = 淨係怪 + 敵對 NPC）" % ("開" if main.pk_mode else "關"), func() -> void:
		main.pk_mode = not main.pk_mode
		main._log("打人模式 %s" % ("開" if main.pk_mode else "關"))
		refresh(true)))
	list.add_child(hsep())
	list.add_child(lbl("測試功能（成品前會換走）", 16, UiTheme.GOLD))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 6)
	list.add_child(g)
	for a in DEBUG_ACTIONS:
		var act := String(a["action"])
		var b := btn(String(a["label"]), func() -> void: main._on_debug_pressed(act), 120)
		g.add_child(b)
	g.add_child(btn("升 1 級(測試)", func() -> void: main._on_debug_pressed("level_up"), 120))
	g.add_child(btn("升 10 級(測試)", func() -> void: main._on_debug_pressed("level_up10"), 120))
	g.add_child(btn("時間 ×%d(測試)" % main.debug_speed, func() -> void:
		main._on_debug_pressed("speed")
		refresh(true), 120))
