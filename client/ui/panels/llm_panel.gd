class_name LlmPanel
extends GamePanel
# LLM 設定 + 對話面板 (U11，spec 09 §5): 頁 0「設定」API Key/模型/啟用開關（key 存本機
# user://llm.cfg，唔入 sim 存檔）；頁 1「對話」顯示最近 LLM 驅動嘅 NPC 說話 + 用量/錯誤。
# 全部經 main.llm_client（本機 key）+ main._send({"t":"llm_config"}) 發意圖、讀 sim.llm_view()。


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "LLM 設定"
	tab_names = ["設定", "對話"]


func open_tab(i: int) -> void:
	tab = i
	set_tabs(tab_names)
	open()


func sig() -> String:
	return JSON.stringify([tab, main.sim.llm_view(), main.llm_log.size()])


func _build_body() -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	match tab:
		0: _build_config(list)
		_: _build_chat(list)


# ---- 頁 0: 設定 ----
func _build_config(list: VBoxContainer) -> void:
	var v: Dictionary = main.sim.llm_view()
	var on := bool(v.get("enabled", false))
	list.add_child(wrap_lbl("狀態：%s" % ("已啟用" if on else "未啟用"), 15, UiTheme.GOOD if on else UiTheme.DIM))
	if on and not main.llm_client.has_key():
		list.add_child(wrap_lbl("已啟用但未設定 API Key，NPC 會用模板句代替。", 12, UiTheme.BAD))
	list.add_child(hsep())
	list.add_child(lbl("OpenRouter API Key（只存本機，唔入存檔）", 14, UiTheme.GOLD))
	_key_edit = _key_edit if _key_edit != null else LineEdit.new()
	_key_edit.secret = true
	_key_edit.placeholder_text = "sk-or-..."
	if _key_edit.text == "" and main.llm_client.has_key():
		_key_edit.text = String(main.llm_client.cfg.get("key", ""))
	list.add_child(_key_edit)
	list.add_child(lbl("模型名（OpenRouter model id）", 14, UiTheme.GOLD))
	_model_edit = _model_edit if _model_edit != null else LineEdit.new()
	_model_edit.placeholder_text = "e.g. anthropic/claude-haiku-4.5"
	if _model_edit.text == "":
		_model_edit.text = String(v.get("model", ""))
	list.add_child(_model_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(btn("儲存", func() -> void:
		main.llm_client.save_cfg(_key_edit.text, _model_edit.text)
		main._send({"t": "llm_config", "enabled": on, "model": _model_edit.text}), 96))
	row.add_child(btn("關閉" if on else "啟用", func() -> void:
		main._send({"t": "llm_config", "enabled": not on, "model": _model_edit.text}), 96))
	list.add_child(row)
	list.add_child(hsep())
	var used: Dictionary = v.get("used", {})
	list.add_child(wrap_lbl("今日用量：對話 %d/%d　反思 %d/%d" %
		[int(used.get("calls", 0)), int(v.get("budgetPerDay", 0)), int(used.get("reflect", 0)), int(v.get("reflectPerDay", 0))], 13))
	var err := String(v.get("lastError", ""))
	if err != "":
		list.add_child(wrap_lbl("上次錯誤：%s" % err, 12, UiTheme.BAD))


# ---- 頁 1: 對話 ----
func _build_chat(list: VBoxContainer) -> void:
	if main.llm_log.is_empty():
		list.add_child(wrap_lbl("暫時未有 LLM 驅動嘅對話（同 NPC 搭訕先會觸發）。", 14, UiTheme.DIM))
		return
	for i in range(main.llm_log.size() - 1, -1, -1):
		list.add_child(wrap_lbl(String(main.llm_log[i]), 13))


var _key_edit: LineEdit
var _model_edit: LineEdit
