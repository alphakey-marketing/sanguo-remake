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


var _confirm_del := 0     # 等緊確認刪除嘅角色位 (0 = 冇)


func sig() -> String:
	return JSON.stringify([main.cur_slot, _confirm_del])


func _build_body() -> void:
	compact(12, 34.0)
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	list.add_child(lbl("揀一個角色位開始遊戲：", 14, UiTheme.GOLD))
	for info in SaveSys.slot_summaries(main.data):
		var n := int(info["n"])
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		list.add_child(row)
		var st := str(info["state"])
		if st == "none":
			row.add_child(btn("角色位 %d：（空）－ 新建角色" % n, func() -> void: _new_slot(n), 0))
			continue
		if st == "bad":
			row.add_child(lbl("角色位 %d：存檔損壞，原檔已保留（唔會覆蓋）" % n, 12, Color(1, 0.5, 0.45)))
		else:
			var cur := " ◀目前" if n == main.cur_slot and not main.awaiting_slot_pick else ""
			row.add_child(btn("角色位 %d：%s  Lv.%d %s%s" % [n, str(info["name"]), int(info["level"]), str(info["cls"]), cur],
				func() -> void: _load_slot(n), 0))
			var sub := "第 %d 日　%s　金 %d" % [int(info["day"]), str(info["place"]), int(info["gold"])]
			sub += "　存於 %s" % SaveSys.ts_text(int(info["ts"]))
			if st == "bak":
				sub += "　（用備份檔）"
			row.add_child(lbl(sub, 11, UiTheme.DIM))
		if _confirm_del == n:
			var hb := HBoxContainer.new()
			hb.add_child(btn("確定刪除（無得還原）", func() -> void:
				SaveSys.delete_slot(n)
				_confirm_del = 0
				refresh(true), 0))
			hb.add_child(btn("取消", func() -> void:
				_confirm_del = 0
				refresh(true), 0))
			row.add_child(hb)
		else:
			row.add_child(btn("　刪除呢個角色位", func() -> void:
				_confirm_del = n
				refresh(true), 0))


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
