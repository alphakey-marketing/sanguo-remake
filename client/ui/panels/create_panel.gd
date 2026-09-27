class_name CreatePanel
extends GamePanel
# 建角面板（S01b，正式化取代 mobile_hud 舊 debug 建角覆蓋層；U-fix: 7 tab 精簡做 2 頁）
# 第 1 頁「基本資料」= 姓名+稱號+生日+職業+臉譜合埋一版；第 2 頁答理念測驗（12題必答）
# 答完自動變確認畫面，撳「出發！」先完成。
# sim 權威：改動經 main._send 行 sim.cmd_set_*；理念測驗答案喺呢度暫存，答滿 12 題先一次過交。
# 未撳「出發！」唔可以關（✕ / 撳遮罩都冇效），逼玩家行完全部步。

const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const FACE_NAMES := {"hair": "頭髮", "brow": "眉毛", "nose": "鼻", "mouth": "嘴", "beard": "鬍鬚", "shape": "臉型", "neck": "頸", "bg": "背景"}

var _confirmed := false
var quiz_i := 0
var quiz_answers: Array = []
var name_edit: LineEdit
var title_edit: LineEdit


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "建角"
	set_tabs(["基本資料", "理念 + 確認"])


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
	return JSON.stringify([tab, ch.get("name", ""), ch.get("nameLocked", false), ch.get("title", ""),
		ch.get("birthMonth", 1), ch.get("birthDay", 1), ch.get("classId", ""), ch.get("face", {}),
		ch.get("ideology", ""), quiz_i, quiz_answers])


func _build_body() -> void:
	var ch: Dictionary = main.ch
	if ch.is_empty():
		return
	if tab == 0:
		_build_basic(ch)
		return
	# 第二頁: 理念未答完先答問卷，答完就直接顯示確認資料 + 出發
	if str(ch.get("ideology", "")) == "":
		_build_quiz(ch)
	else:
		_build_confirm(ch)


# 第一頁: 姓名/稱號/生日/職業/臉譜合埋一版，撳完即刻見到效果，減少嚟回切 tab
func _build_basic(ch: Dictionary) -> void:
	var sc := scroll()
	body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	sc.add_child(list)
	_build_name(ch, list)
	list.add_child(hsep())
	_build_title(ch, list)
	list.add_child(hsep())
	_build_birth(ch, list)
	list.add_child(hsep())
	_build_class(ch, list)
	list.add_child(hsep())
	_build_face(ch, list)
	list.add_child(hsep())
	list.add_child(btn("下一步：理念測驗 →", func() -> void:
		tab = 1
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


# ---- 稱號（隨時可改） ----
func _build_title(ch: Dictionary, parent: Control) -> void:
	parent.add_child(lbl("稱號（隨時可以改）", 15, UiTheme.GOLD))
	parent.add_child(lbl("而家：「%s」" % (str(ch.get("title", "")) if str(ch.get("title", "")) != "" else "未設"), 14))
	title_edit = LineEdit.new()
	title_edit.max_length = 8
	title_edit.placeholder_text = "稱號 1~8 字"
	title_edit.text = str(ch.get("title", ""))
	parent.add_child(title_edit)
	parent.add_child(btn("確定", func() -> void: main._send({"t": "set_title", "title": title_edit.text}), 120))


# ---- 生日（影響福日 exp +10%，隨時可改） ----
func _build_birth(ch: Dictionary, parent: Control) -> void:
	var m := int(ch.get("birthMonth", 1))
	var d := int(ch.get("birthDay", 1))
	parent.add_child(lbl("生日（福日嗰日練功 exp +10%，隨時可改）", 15, UiTheme.GOLD))
	parent.add_child(lbl("而家：%d 月 %d 日" % [m, d], 16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	row.add_child(lbl("月", 14))
	row.add_child(btn("－", func() -> void: _shift_birth(-1, 0), 48))
	row.add_child(btn("＋", func() -> void: _shift_birth(1, 0), 48))
	row.add_child(lbl("日", 14))
	row.add_child(btn("－", func() -> void: _shift_birth(0, -1), 48))
	row.add_child(btn("＋", func() -> void: _shift_birth(0, 1), 48))


func _shift_birth(dm: int, dd: int) -> void:
	var ch: Dictionary = main.ch
	var m: int = int(ch.get("birthMonth", 1)) + dm
	var d: int = int(ch.get("birthDay", 1)) + dd
	if m < 1: m = 12
	if m > 12: m = 1
	if d < 1: d = 1
	if d > int(MONTH_DAYS[m - 1]): d = int(MONTH_DAYS[m - 1])
	main._send({"t": "set_birth", "month": m, "day": d})


# ---- 職業（六職，未開放灰；只限未出發 Lv1 揀） ----
func _build_class(ch: Dictionary, parent: Control) -> void:
	parent.add_child(lbl("職業（未出發前可以改）", 15, UiTheme.GOLD))
	var cur := str(ch.get("classId", ""))
	var can_change := int(ch.get("level", 1)) == 1
	for cid in main.data.classes:
		var cls: Dictionary = main.data.classes[cid]
		var enabled := bool(cls.get("enabled", false))
		var is_cur := String(cid) == cur
		var t := "%s%s%s" % [str(cls.get("name", cid)), "　（現用）" if is_cur else "", "　未開放" if not enabled else ""]
		var b := btn(t, func() -> void: main._send({"t": "select_class", "class_id": String(cid)}))
		b.disabled = not enabled or is_cur or not can_change
		parent.add_child(b)


# ---- 臉譜（8 部位，款式循環） ----
func _build_face(ch: Dictionary, parent: Control) -> void:
	parent.add_child(lbl("臉譜（撳格循環款式）", 15, UiTheme.GOLD))
	var face: Dictionary = ch.get("face", {})
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
		"稱號「%s」" % (str(ch.get("title", "")) if str(ch.get("title", "")) != "" else "未設"),
		"生日 %d月%d日" % [int(ch.get("birthMonth", 1)), int(ch.get("birthDay", 1))],
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
