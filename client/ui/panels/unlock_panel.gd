class_name UnlockPanel
extends GamePanel
# 開鎖小遊戲 (S02c, spec 02 §6【自訂】簡化): 三支鑰匙揀一支（黃師姐教落）。
# sim 權威: cmd_use_skill("unlock") -> 附近鎖寶箱 -> emit unlock_open -> 呢個面板
# -> 撳「鑰匙 X」-> cmd_skill_pick(chest, key) -> 啱埋 unlock_done 事件閂面板，錯留低再試。
# 而家未有任務寶箱實體 (S04/S06 接)，面板由 unlock_open 事件開（測試可直接撳掣驗證）。


func _init(m: Node) -> void:
	super(m)
	margin = 20.0


func _win_rect(safe: Rect2) -> Rect2:
	var w := minf(safe.size.x - 20, 420.0)
	var h := minf(safe.size.y - 20, 240.0)
	return Rect2(safe.position.x + (safe.size.x - w) / 2, safe.end.y - h - 10, w, h)


func sig() -> String:
	return str(int(main._unlock_chest))


func _build_body() -> void:
	title_lbl.text = "開鎖"
	var chest_name := "寶箱"
	if int(main._unlock_chest) > 0:
		var chest: Dictionary = main.sim.ent(int(main._unlock_chest))
		if not chest.is_empty():
			chest_name = str(chest.get("name", "寶箱"))
	body.add_child(wrap_lbl("「%s」鎖住咗。黃師姐教落：三支鑰匙得一支啱，揀錯慢慢再試。" % chest_name, 14))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	body.add_child(g)
	for i in 3:
		var k := int(i)
		var b := btn("鑰匙 %s" % String(["甲", "乙", "丙"][k]), func() -> void:
			main._send({"t": "skill_pick", "chest": int(main._unlock_chest), "key": int(k)}))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(100, 46)
		g.add_child(b)
	body.add_child(lbl("（成功自動閂埋；失敗可以再揀）", 11, UiTheme.GOLD))