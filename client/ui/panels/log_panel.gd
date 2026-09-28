class_name LogPanel
extends GamePanel
# 完整日誌面板 (U16)：撳開睇返 main.log_lines 全部記錄 (HUD 版只顯示最後 3 行)。
# 靜態查詢面板，唔發 sim 意圖。


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "完整日誌"


func sig() -> String:
	return "%d" % main.log_lines.size()


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var lines: Array = main.log_lines
	if lines.is_empty():
		v.add_child(lbl("（暫時冇記錄）", 14, UiTheme.TEXT))
		return
	for i in range(lines.size() - 1, -1, -1):    # 新到舊
		v.add_child(lbl(str(lines[i]), 13, UiTheme.TEXT))
