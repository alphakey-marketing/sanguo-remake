class_name TitlePanel
extends GamePanel
# 存檔/角色主頁面 (U-fix): 三個 slot，撳有存檔嗰個 = 載入並切去果個角色；
# 撳空 slot = 用嗰個 slot 開新角色 (建角面板)。攞唔到就喺「更多」面板入去。
# 呢個 panel 唔會逼玩家一定行（唔似 CreatePanel 咁 close() 攔住），淨係俾用家自己揀。

var _busy := false


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "選擇角色"
	set_tabs([])


func sig() -> String:
	return JSON.stringify([main.cur_slot])


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	sc.add_child(list)
	list.add_child(lbl("揀一個角色位開始遊戲：", 15, UiTheme.GOLD))
	for info in SaveSys.slot_summaries(main.data):
		var n := int(info["n"])
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		list.add_child(row)
		if bool(info["exists"]):
			var b := btn("角色位 %d：%s（Lv.%d，第 %d 日）" % [n, str(info["name"]), int(info["level"]), int(info["day"])],
				func() -> void: _load_slot(n), 0)
			row.add_child(b)
			row.add_child(btn("　刪除呢個角色位", func() -> void:
				SaveSys.delete_slot(n)
				refresh(true), 0))
		else:
			row.add_child(btn("角色位 %d：（空）－ 新建角色" % n, func() -> void: _new_slot(n), 0))


func _load_slot(n: int) -> void:
	if _busy:
		return
	_busy = true
	close()
	main.switch_to_slot(n, false)


func _new_slot(n: int) -> void:
	if _busy:
		return
	_busy = true
	close()
	main.switch_to_slot(n, true)
