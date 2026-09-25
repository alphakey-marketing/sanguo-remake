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
	return JSON.stringify([main.hud.vibrate_on])


func _build_body() -> void:
	body.add_child(btn("登用人才 / 同伴", func() -> void: main.hud.open_panel("recruit")))
	body.add_child(btn("座騎", func() -> void: main.hud.mount_panel().open_tab(0)))
	body.add_child(btn("情報冊（竊聽）", func() -> void: main.hud.open_panel("rumor")))
	body.add_child(hsep())
	body.add_child(lbl("設定", 16, UiTheme.GOLD))
	var hud = main.hud
	body.add_child(btn("撳掣震動：%s" % ("開" if hud.vibrate_on else "關"), func() -> void:
		hud.vibrate_on = not hud.vibrate_on
		refresh(true)))
	body.add_child(hsep())
	body.add_child(lbl("測試功能（成品前會換走）", 16, UiTheme.GOLD))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 6)
	body.add_child(g)
	for a in DEBUG_ACTIONS:
		var act := String(a["action"])
		var b := btn(String(a["label"]), func() -> void: main._on_debug_pressed(act), 120)
		g.add_child(b)
