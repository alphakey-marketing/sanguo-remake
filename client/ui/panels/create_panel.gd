class_name CreatePanel
extends GamePanel
# 建角面板（S01b，正式化取代 mobile_hud 舊 debug 建角覆蓋層；U-fix: 7 tab 精簡做 2 頁）
# 第 1 頁「職業介紹」= 獨立職業頁 (F3)；第 2 頁「基本資料」= 姓名+臉譜 (新手城固定許昌，唔再揀)（稱號改做事件獎勵解鎖）；第 3 頁答理念測驗（12題必答）
# 答完自動變確認畫面，撳「出發！」先完成。
# sim 權威：改動經 main._send 行 sim.cmd_set_*；理念測驗答案喺呢度暫存，答滿 12 題先一次過交。
# 未撳「出發！」唔可以關（✕ / 撳遮罩都冇效），逼玩家行完全部步。

const FACE_NAMES := {"set": "臉型組", "hair": "頭髮", "brow": "眉眼", "shape": "臉型", "neck": "頸", "bg": "背景"}

var _confirmed := false
var quiz_i := 0
var quiz_answers: Array = []
var name_edit: LineEdit


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "建角"
	set_tabs(["職業介紹", "基本資料", "理念 + 確認"])


func open() -> void:
	quiz_i = 0
	quiz_answers = []
	_confirmed = false
	super()


func close() -> void:
	if not visible:
		return
	if not _confirmed:
		return   # 建角未完成，撳 ✕/遮罩都唔畀走（撳「出發！」先算數）
	hide()
	closed.emit()


func sig() -> String:
	var ch: Dictionary = main.ch
	return JSON.stringify([tab, ch.get("name", ""), ch.get("nameLocked", false),
		ch.get("classId", ""), ch.get("face", {}),
		ch.get("ideology", ""), quiz_i, quiz_answers])


func _build_body() -> void:
	var ch: Dictionary = main.ch
	if ch.is_empty():
		return
	if tab == 0:
		_build_class_page(ch)
		return
	if tab == 1:
		_build_basic(ch)
		return
	# 第三頁: 理念未答完先答問卷，答完就直接顯示確認資料 + 出發
	if str(ch.get("ideology", "")) == "":
		_build_quiz(ch)
	else:
		_build_confirm(ch)


# 第一頁: 姓名/新手城/職業/臉譜合埋一版，撳完即刻見到效果，減少嚟回切 tab
func _build_basic(ch: Dictionary) -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	sc.add_child(list)
	_build_name(ch, list)
	list.add_child(hsep())
	_build_face(ch, list)
	list.add_child(hsep())
	list.add_child(btn("下一步：理念測驗 →", func() -> void:
		tab = 2
		refresh(true), 200))


# ---- 姓名（最多 8 字，決定後不可改） ----
func _build_name(ch: Dictionary, parent: Control) -> void:
	var locked := bool(ch.get("nameLocked", false))
	parent.add_child(lbl("姓名（最多 8 字，決定後不可改）", 15, UiTheme.GOLD))
	parent.add_child(lbl("而家：「%s」%s" % [str(ch.get("name", "")), "（已鎖定）" if locked else ""], 14))
	if locked:
		return
	name_edit = LineEdit.new()
	name_edit.max_length = 8
	name_edit.placeholder_text = "姓名 1~8 字"
	name_edit.text = str(ch.get("name", ""))
	parent.add_child(name_edit)
	parent.add_child(btn("確定", func() -> void: main._send({"t": "set_name", "name": name_edit.text}), 120))


# 第一頁: 獨立職業介紹頁 (F3)。每職一格: 預留畫圖位 + 介紹 + 武器/特技/轉職路線 + 揀選掣
func _build_class_page(ch: Dictionary) -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	sc.add_child(list)
	list.add_child(lbl("揀職業（未出發前可以改）", 15, UiTheme.GOLD))
	var cur := str(ch.get("classId", ""))
	var can_change := int(ch.get("level", 1)) == 1
	for cid in main.data.classes:
		var cls: Dictionary = main.data.classes[cid]
		var enabled := bool(cls.get("enabled", false))
		var is_cur := String(cid) == cur
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_class_art(String(cid), ch))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(lbl("%s%s" % [str(cls.get("name", cid)), "　（現用）" if is_cur else ""], 15, UiTheme.GOLD))
		col.add_child(wrap_lbl(str(cls.get("desc", "")), 13))
		col.add_child(wrap_lbl("武器：%s　特技：%s
轉職：%s → %s" % [
			"、".join(PackedStringArray(cls.get("weapons", []))), str(cls.get("skill", "")),
			str(cls.get("tier2", {}).get("name", "?")), str(cls.get("tier3", {}).get("name", "?"))], 12, UiTheme.DIM))
		var b := btn("選擇" if enabled else "未開放", func() -> void: main._send({"t": "select_class", "class_id": String(cid)}), 100)
		b.disabled = not enabled or is_cur or not can_change
		col.add_child(b)
		row.add_child(col)
		list.add_child(row)
		list.add_child(hsep())
	list.add_child(btn("下一步：基本資料 →", func() -> void:
		tab = 1
		refresh(true), 200))


# 職業圖位: 有 res://assets/class_art/<id>.png 就用 (96x128)；冇就用原版分層 sprite 砌 Lv1 起手造型 (面向鏡頭)
func _class_art(cid: String, ch: Dictionary) -> Control:
	var path := "res://assets/class_art/%s.png" % cid
	if ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.custom_minimum_size = Vector2(96, 128)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tr
	var box := Control.new()
	box.custom_minimum_size = Vector2(96, 128)
	var b := int(main._CLASS_B.get(cid, 0))
	for t in AssetLib.player_preview(b, ch.get("face", {})):
		var tr := TextureRect.new()
		tr.texture = t
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(tr)
	if box.get_child_count() == 0:
		var ph := ColorRect.new()
		ph.color = Color(0.3, 0.3, 0.3)
		ph.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.add_child(ph)
	return box


# ---- 臉譜（8 部位，款式循環） ----
func _build_face(ch: Dictionary, parent: Control) -> void:
	parent.add_child(lbl("臉譜（撳格循環款式）", 15, UiTheme.GOLD))
	var face: Dictionary = ch.get("face", {})
	var pv := Control.new()
	pv.custom_minimum_size = Vector2(144, 160)
	for t in AssetLib.face_layers(face):
		var tr := TextureRect.new()
		tr.texture = t
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pv.add_child(tr)
	parent.add_child(pv)
	for part in main.data.face_parts:
		var cnt := int(main.data.face_parts[part])
		var cur := int(face.get(part, 1))
		var b := btn("%s　款式 %d/%d" % [str(FACE_NAMES.get(part, part)), cur, cnt],
			func() -> void: main._send({"t": "set_face", "part": String(part), "value": cur % cnt + 1}))
		parent.add_child(b)


# ---- 理念測驗（12 題，答滿一次過交，決定咗唔可以改） ----
func _build_quiz(ch: Dictionary) -> void:
	var ideology := str(ch.get("ideology", ""))
	if ideology != "":
		body.add_child(lbl("理念：%s（已決定，唔可以改）" % ideology, 16, UiTheme.GOLD))
		return
	var qs: Array = main.data.quiz
	if quiz_i >= qs.size():
		quiz_i = 0
	var q: Dictionary = qs[quiz_i]
	body.add_child(lbl("理念測驗  %d/%d" % [quiz_i + 1, qs.size()], 15, UiTheme.GOLD))
	body.add_child(wrap_lbl(str(q["q"]), 14))
	var o0: Dictionary = q["opts"][0]
	var o1: Dictionary = q["opts"][1]
	body.add_child(btn("%s（%s）" % [str(o0["t"]), str(o0["g"])], func() -> void: _quiz_pick(0)))
	body.add_child(btn("%s（%s）" % [str(o1["t"]), str(o1["g"])], func() -> void: _quiz_pick(1)))
	if quiz_i > 0:
		body.add_child(btn("重新作答", func() -> void:
			quiz_i = 0
			quiz_answers = []
			refresh(true)))
	body.add_child(wrap_lbl("答完 12 題就決定理念，唔改得。", 13, UiTheme.DIM))


func _quiz_pick(choice: int) -> void:
	quiz_answers.append(choice)
	quiz_i += 1
	if quiz_i >= (main.data.quiz as Array).size():
		main._send({"t": "submit_quiz", "answers": quiz_answers})
		quiz_i = 0
		quiz_answers = []
	refresh(true)


# ---- 確認：撳「出發！」先算完成建角 ----
func _build_confirm(ch: Dictionary) -> void:
	var cls: Dictionary = main.data.classes.get(str(ch.get("classId", "")), {})
	body.add_child(lbl("確認資料", 15, UiTheme.GOLD))
	var lines := [
		"姓名「%s」" % str(ch.get("name", "")),
		"職業 %s" % str(cls.get("name", "?")),
		"理念 %s" % (str(ch.get("ideology", "")) if str(ch.get("ideology", "")) != "" else "未測（可以出發後喺角色面板都測唔到，理念只可以呢度測）"),
	]
	for l in lines:
		body.add_child(lbl(str(l), 14))
	body.add_child(hsep())
	body.add_child(btn("出發！", _confirm_and_close, 200))


func _confirm_and_close() -> void:
	_confirmed = true
	close()
	main.hud.create_done.emit()
