class_name QuestPanel
extends GamePanel
# 記事面板: 進行中任務（全文提示，可以拖捲）/ 已完成。

func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "記事"
	set_tabs(["進行中", "完成"])


func sig() -> String:
	return JSON.stringify([tab, main.sim.view_quests()])


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	var n := 0
	for q in main.sim.view_quests():
		var act := bool(q.get("active", false))
		var done := bool(q.get("done", false))
		if (tab == 0 and not act) or (tab == 1 and not done):
			continue
		n += 1
		list.add_child(lbl(("● " if act else "✓ ") + str(q["name"]), 16, UiTheme.GOLD if act else UiTheme.GOOD))
		if act and str(q.get("hint", "")) != "":
			list.add_child(wrap_lbl("　" + str(q["hint"]), 14, UiTheme.TEXT))
	if n == 0:
		list.add_child(lbl("未有任務 — 去城門口搵神秘老人" if tab == 0 else "未完成任何任務", 14, UiTheme.DIM))
