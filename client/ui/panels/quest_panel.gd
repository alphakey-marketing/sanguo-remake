class_name QuestPanel
extends GamePanel
# 記事面板: 進行中任務（全文提示，可以拖捲）/ 已完成。

func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "記事"
	set_tabs(["進行中", "完成", "戰役", "場景"])


func sig() -> String:
	return JSON.stringify([tab, main.sim.view_quests(), main.sim.view_commissions(),
		main.sim.view_battles(main.my_id), main.sim.view_scenes(main.my_id)])


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
	if tab == 0:                           # 居民委託 (Step 16)
		for c in main.sim.view_commissions():
			n += 1
			list.add_child(lbl("◆ 委託・%s" % c["name"], 16, UiTheme.GOLD))
			list.add_child(wrap_lbl("　%s%s（仲有 %d 日，報酬 %s）" % [c["text"], "　可以覆命" if bool(c["ready"]) else "",
				int(c["left"]), c["reward"]], 14, UiTheme.TEXT))
	if n == 0 and tab < 2:
		list.add_child(lbl("未有任務 — 去城門口搵神秘老人" if tab == 0 else "未完成任何任務", 14, UiTheme.DIM))
	if tab == 2:                           # 戰役日程 (S04c, spec 06 §7 / spec 04 §5)
		_battle_section(list)
	if tab == 3:                           # 特殊場景日程 (S04d, spec 04 §4)
		_scene_section(list)


func _battle_section(list: Node) -> void:
	var vb: Dictionary = main.sim.view_battles(main.my_id)
	list.add_child(lbl("今日戰役（每日窗口重開，武等上限內先入得）", 14, UiTheme.TEXT))
	for b in vb["list"]:
		var open := bool(b["open"])
		list.add_child(lbl("%s%s　%s（武≤%d）　%s" % ["● " if open else "○ ", b["name"],
			RulesClock.format_ke(int(b["startKe"])), int(b["maxLevel"]),
			RulesClock.format_ke(int(b["endKe"]))], 15, UiTheme.GOLD if open else UiTheme.TEXT))
	if bool(vb["inBattle"]):
		list.add_child(lbl("── 而家喺戰役入面 ──", 15, UiTheme.GOLD))
		list.add_child(wrap_lbl("%s 第 %d/%d 層，打完自動離場；內陣亡唔跌經驗/物品" % [vb["battleName"],
			int(vb["floor"]), int(vb["totalFloors"])], 14, UiTheme.TEXT))
	else:
		list.add_child(wrap_lbl("去許昌城上方「義勇士兵」（開窗時出現）報名，打贏尾層大頭目即完成。", 14, UiTheme.DIM))


# 特殊場景日程 (S04d, spec 04 §4): game 日曆窗口開門 + 玩家進度
func _scene_section(list: Node) -> void:
	var vs: Dictionary = main.sim.view_scenes(main.my_id)
	list.add_child(lbl("特殊場景（game 日曆開門）　今日 = %d日" % int(vs["dayOfMonth"]), 14, UiTheme.TEXT))
	for s in vs["list"]:
		var open := bool(s["open"])
		list.add_child(lbl("%s%s　（武等 ≥%d，每月%s）" % ["● " if open else "○ ", s["name"],
			int(s["minLevel"]), s["openDays"]], 15, UiTheme.GOLD if open else UiTheme.TEXT))
	if bool(vs["inScene"]):
		list.add_child(lbl("── 而家喺場景入面 ──", 15, UiTheme.GOLD))
		list.add_child(wrap_lbl("%s 第 %d/%d 層；打完每層大頭目過下一層，尾層打完自動離開；內陣亡唔跌經驗/物品" % [
			vs["sceneName"], int(vs["layer"]), int(vs["totalLayers"])], 14, UiTheme.TEXT))
	else:
		list.add_child(wrap_lbl("去荊州港口搵場景入口（開門日先入得）。", 14, UiTheme.DIM))
