class_name MobileHud
extends Control
# 手機操控層（三國群英傳M 風格）: 浮動搖桿 + 右下 普攻/自動 + 右上 背包 +
# 左上角色框（頭像/HP/MP/SP/EXP/金/善惡）+ 頂中目標框 + 底部日誌 + 開場提示。
# 覆蓋喺 main.gd 之上（Control 後畫 → 蓋住世界）。input 喺 _input 路由:
#   搖桿區 / 按鈕 → consume；其餘放行俾 main.gd _unhandled_input 做世界點擊（多點觸控都得）。
# 桌面用滑鼠模擬: 左鍵拖左下 = 搖桿，點怪 = 攻擊，右鍵 = 自動。

signal attack_pressed
signal auto_toggled(on: bool)
signal bag_pressed
signal travel_pressed
signal quest_pressed                      # 記事掣 (Step 8)
signal create_done                        # 建角面板完成 (Step 8)
signal debug_pressed(action: String)      # 手機冇鍵盤，用呢排掣代替 H/U/Y/C/V/W debug 鍵

var main: Node2D           # 引用 main.gd: 讀 ch/ents/faces/log_lines，用 _bar/_txt 畫
var joy: SangoJoystick
var auto := false
var use_touch := false
var _t := 0.0              # 開場提示計時
# ---- 建角面板 (Step 8, spec 01 §1/§2; Step 7.5 UI 遺留) ----
var creation_mode := false
var quiz_mode := false
var quiz_i := 0            # 進行中題目 index 0..11
var quiz_answers: Array = []
var title_edit: LineEdit   # 稱號輸入（唯一要打字嘅位）

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)   # size 跟 viewport，唔係 0

func setup(m: Node2D) -> void:
	main = m
	use_touch = Input.is_emulating_mouse_from_touch()
	joy = SangoJoystick.new()
	joy.use_touch = use_touch
	joy.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(joy)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_auto(v: bool) -> void:
	auto = v
	queue_redraw()

func joy_active() -> bool:
	return joy != null and joy.active

func joy_dir() -> Vector2:
	return joy.get_direction() if joy != null else Vector2.ZERO

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _input(ev: InputEvent) -> void:
	if creation_mode:
		_handle_create_input(ev)
		return
	joy.zone = _zone()
	if joy.handle_event(ev):
		get_viewport().set_input_as_handled()
		return
	if use_touch:
		if ev is InputEventScreenTouch and ev.pressed:
			if _button_hit(ev.position):
				get_viewport().set_input_as_handled()
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if _button_hit(ev.position):
			get_viewport().set_input_as_handled()

# 搖桿區: 開咗商店/客棧面板就縮細，留位俾面板點擊
# 桌面滑鼠模擬: zone 細啲(左下一細塊)，留返成個地圖俾單擊行路/攻擊，唔好成幅畫面都撳唔到地
func _zone() -> Rect2:
	var s := get_viewport_rect().size
	if main != null and (main._near_shop() or main._near_inn()):
		return Rect2(0, s.y * 0.64, s.x * 0.45, s.y * 0.36)
	if not use_touch:
		return Rect2(0, s.y - 140, 140, 140)
	return Rect2(0, s.y * 0.38, s.x * 0.55, s.y * 0.62)

func _attack_rect() -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(s.x - 116, s.y - 116, 88, 88)

func _auto_rect() -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(s.x - 92, s.y - 210, 60, 60)

func _bag_rect() -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(s.x - 66, 6, 60, 40)

# 傳送掣: 淨係行近城門/傳送點先顯示 (main._near_travel() 唔係空)，右上背包掣下面
func _travel_rect() -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(s.x - 96, 50, 90, 40)

# 記事掣 (Step 8): 背包掣下面
func _quest_rect() -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(s.x - 66, 52, 60, 40)

func _near_travel_point() -> Dictionary:
	return main.call("_near_travel") if main != null else {}

# 手機冇鍵盤，臨時 debug 掣 (未有正式面板嘅工作/天地商行/食物/打招呼)，成品前會換走
const DEBUG_ACTIONS := [
	{"action": "greet", "label": "問好"},
	{"action": "use", "label": "食嘢"},
	{"action": "storage_sub", "label": "商行"},
	{"action": "deposit", "label": "存倉"},
	{"action": "withdraw", "label": "攞倉"},
	{"action": "work_mining", "label": "採礦"},
]

# 一橫排放喺狀態框右邊、傳送/背包掣下面嘅空位，避開左下搖桿區(觸控 zone 由 s.y*0.38 開始)
func _debug_rect(i: int) -> Rect2:
	return Rect2(256 + i * 47, 8, 44, 26)

func _button_hit(pos: Vector2) -> bool:
	if _attack_rect().has_point(pos):
		attack_pressed.emit()
		return true
	if _auto_rect().has_point(pos):
		auto = not auto
		queue_redraw()
		auto_toggled.emit(auto)
		return true
	if _spell_bar_hit(pos):
		return true
	if _bag_rect().has_point(pos):
		bag_pressed.emit()
		return true
	if _quest_rect().has_point(pos):
		quest_pressed.emit()
		return true
	if not _near_travel_point().is_empty() and _travel_rect().has_point(pos):
		travel_pressed.emit()
		return true
	for i in DEBUG_ACTIONS.size():
		if _debug_rect(i).has_point(pos):
			debug_pressed.emit(String(DEBUG_ACTIONS[i]["action"]))
			return true
	return false

# ================= 建角面板 (Step 8; Step 7.5 UI 遺留: 稱號/生日/臉譜/理念測驗) =================
# sim 權威: 所有改動經 main._send 行 sim.cmd_set_*；呢度淨係輸入/顯示。

const FACE_NAMES := {"hair": "頭髮", "brow": "眉毛", "nose": "鼻", "mouth": "嘴", "beard": "鬍鬚", "shape": "臉型", "neck": "頸", "bg": "背景"}


func _create_panel() -> Rect2:
	var s := get_viewport_rect().size
	var ph := mini(560.0, float(s.y) - 4.0)   # 橫屏 360 高都裝得落 (Step 9 建角壓縮)
	return Rect2(s.x / 2 - 240, maxf(0.0, float(s.y) / 2.0 - ph / 2.0), 480, ph)


func _handle_create_input(ev: InputEvent) -> void:
	var pos := Vector2.ZERO
	var pressed := false
	if ev is InputEventScreenTouch:
		pos = ev.position
		pressed = ev.pressed
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		pos = ev.position
		pressed = ev.pressed
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	_create_action(_create_hit(pos))


func _face_btn_rect(i: int) -> Rect2:
	var r := _create_panel()
	var col := i / 4
	var row := i % 4
	return Rect2(r.position.x + 30 + col * 230, r.position.y + 152 + row * 30, 210, 26)


func _create_hit(pos: Vector2) -> String:
	var r := _create_panel()
	if not r.has_point(pos):
		return ""
	if quiz_mode:
		if Rect2(r.position.x + 330, r.position.y + 58, 130, 26).has_point(pos): return "skip_quiz"
		if Rect2(r.position.x + 40, r.position.y + 210, r.size.x - 80, 46).has_point(pos): return "quiz_0"
		if Rect2(r.position.x + 40, r.position.y + 272, r.size.x - 80, 46).has_point(pos): return "quiz_1"
		return ""
	if Rect2(r.position.x + 330, r.position.y + 44, 90, 26).has_point(pos): return "edit_title"
	if Rect2(r.position.x + 120, r.position.y + 74, 44, 24).has_point(pos): return "bmonth_dec"
	if Rect2(r.position.x + 196, r.position.y + 74, 44, 24).has_point(pos): return "bmonth_inc"
	if Rect2(r.position.x + 300, r.position.y + 74, 44, 24).has_point(pos): return "bday_dec"
	if Rect2(r.position.x + 376, r.position.y + 74, 44, 24).has_point(pos): return "bday_inc"
	if Rect2(r.position.x + 120, r.position.y + 104, 300, 28).has_point(pos): return "class_toggle"
	for i in 8:
		if _face_btn_rect(i).has_point(pos): return "face_%d" % i
	if Rect2(r.position.x + 90, r.position.y + 282, 300, 32).has_point(pos): return "start_quiz"
	if Rect2(r.position.x + 90, r.position.y + 322, 300, 32).has_point(pos): return "start_game"
	return ""


func _create_action(a: String) -> void:
	if a == "":
		return
	if a.begins_with("face_"):
		var parts: Array = []
		for k in main.data.face_parts:
			parts.append(k)
		var part := String(parts[int(a.trim_prefix("face_"))])
		var cur: int = int(main.ch["face"].get(part, 1))
		var cnt: int = int(main.data.face_parts[part])
		main._send({"t": "set_face", "part": part, "value": cur % cnt + 1})
		return
	match a:
		"edit_title": _open_title_edit()
		"bmonth_dec": _shift_birth(-1, 0)
		"bmonth_inc": _shift_birth(1, 0)
		"bday_dec": _shift_birth(0, -1)
		"bday_inc": _shift_birth(0, 1)
		"start_quiz":
			quiz_mode = true
			quiz_i = 0
			quiz_answers = []
		"quiz_0": _quiz_answer(0)
		"quiz_1": _quiz_answer(1)
		"skip_quiz":
			quiz_mode = false
			quiz_i = 0
			quiz_answers = []
		"class_toggle": _toggle_class()
		"start_game":
			_close_title_edit()
			creation_mode = false
			create_done.emit()


func _shift_birth(dm: int, dd: int) -> void:
	var m: int = int(main.ch.get("birthMonth", 1)) + dm
	var d: int = int(main.ch.get("birthDay", 1)) + dd
	var days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if m < 1: m = 12
	if m > 12: m = 1
	if d < 1: d = 1
	if d > int(days[m - 1]): d = int(days[m - 1])
	main._send({"t": "set_birth", "month": m, "day": d})


func _quiz_answer(c: int) -> void:
	quiz_answers.append(c)
	quiz_i += 1
	var n := (main.data.quiz as Array).size()
	if quiz_i >= n:
		main._send({"t": "submit_quiz", "answers": quiz_answers})
		quiz_mode = false
		quiz_i = 0


func _open_title_edit() -> void:
	if title_edit == null:
		title_edit = LineEdit.new()
		title_edit.max_length = 8
		title_edit.placeholder_text = "稱號 1~8 字"
		title_edit.text_submitted.connect(func(t: String) -> void:
			main._send({"t": "set_title", "title": t})
			title_edit.hide())
		add_child(title_edit)
	var r := _create_panel()
	title_edit.position = Vector2(r.position.x + 40, r.position.y + 46).floor()
	title_edit.size = Vector2(240, 26).floor()
	title_edit.text = str(main.ch.get("title", ""))
	title_edit.show()
	title_edit.grab_focus()


func _close_title_edit() -> void:
	if title_edit != null:
		title_edit.hide()


# 建角轉職業 (Step 9): sim.cmd_select_class 只容許未出發 (Lv1)；而家有義士/道士
const CLASS_IDS := ["yishi", "daoshi"]


func _toggle_class() -> void:
	var cur := str(main.ch.get("classId", "yishi"))
	var next := "yishi"
	for i in CLASS_IDS.size():
		if String(CLASS_IDS[i]) == cur:
			next = String(CLASS_IDS[(i + 1) % CLASS_IDS.size()])
	main._send({"t": "select_class", "class_id": next})


func _draw_cbtn(pos: Vector2, sz: Vector2, label: String) -> void:
	draw_rect(Rect2(pos, sz), Color(0.18, 0.18, 0.24, 0.95))
	draw_rect(Rect2(pos, sz), Color(1, 1, 1, 0.45), false, 1.5)
	_txt_center(pos.y + sz.y / 2 + 4, label, Color.WHITE, 13, sz.x - 8, pos.x + 4)


# 建角面板繪畫（全屏遮罩 + 中央面板）
func _draw_create(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.88))
	var r := _create_panel()
	draw_rect(r, Color(0.08, 0.09, 0.12, 0.98))
	draw_rect(r, Color(1, 0.85, 0.4), false, 2.0)
	var ch: Dictionary = main.ch
	if ch.is_empty():
		return
	var cls0: Dictionary = main.data.classes.get(str(ch.get("classId", "yishi")), {})
	_txt(r.position + Vector2(20, 30), "建角 — %s (Lv1 %s)" % [str(ch.get("name", "")), str(cls0.get("name", "?"))], Color(1, 0.9, 0.5), 18)
	if quiz_mode:
		_draw_quiz(r, ch)
		return
	# 稱號
	_txt(r.position + Vector2(20, 52), "稱號「%s」" % str(ch.get("title", "未設")), Color.WHITE, 13)
	_draw_cbtn(r.position + Vector2(330, 44), Vector2(90, 26), "改")
	# 生日
	_txt(r.position + Vector2(20, 84), "生日  %d月%d日" % [int(ch.get("birthMonth", 1)), int(ch.get("birthDay", 1))], Color.WHITE, 13)
	_draw_cbtn(r.position + Vector2(120, 74), Vector2(44, 24), "月-")
	_draw_cbtn(r.position + Vector2(196, 74), Vector2(44, 24), "月+")
	_draw_cbtn(r.position + Vector2(300, 74), Vector2(44, 24), "日-")
	_draw_cbtn(r.position + Vector2(376, 74), Vector2(44, 24), "日+")
	# 職業 (Step 9)
	_txt(r.position + Vector2(20, 112), "職業", Color(0.85, 0.9, 1.0), 12)
	_draw_cbtn(r.position + Vector2(120, 104), Vector2(300, 28), "點擊切換：%s" % str(cls0.get("name", "?")))
	# 臉譜
	_txt(r.position + Vector2(20, 138), "臉譜（點擊循環款式）", Color(0.8, 0.9, 1.0), 12)
	var parts: Array = []
	for k in main.data.face_parts:
		parts.append(k)
	for i in 8:
		var part := String(parts[i])
		var fname: String = String(FACE_NAMES.get(part, part))
		var cur: int = int(ch["face"].get(part, 1))
		var cnt: int = int(main.data.face_parts[part])
		var b := _face_btn_rect(i)
		draw_rect(b, Color(0.15, 0.16, 0.22, 0.95))
		draw_rect(b, Color(1, 1, 1, 0.35), false, 1.0)
		_txt(b.position + Vector2(8, 17), "%s 款式 %d/%d" % [fname, cur, cnt], Color(0.9, 0.95, 1.0), 11)
	# 理念測驗
	_txt(r.position + Vector2(20, 272), "理念：%s" % str(ch.get("ideology", "未測")), Color(0.85, 1.0, 0.75), 13)
	if str(ch.get("ideology", "")) == "":
		_draw_cbtn(r.position + Vector2(90, 282), Vector2(300, 32), "開始理念測驗 (12 題)")
	# 出發
	_draw_cbtn(r.position + Vector2(90, 322), Vector2(300, 32), "出發！")
	_txt(r.position + Vector2(20, r.size.y - 4), "稱號/生日/臉譜可隨時改；理念一測就唔改得", Color(0.6, 0.65, 0.75), 9)


func _draw_quiz(r: Rect2, ch: Dictionary) -> void:
	var qs: Array = main.data.quiz
	var q: Dictionary = qs[quiz_i]
	_txt(r.position + Vector2(20, 60), "理念測驗  %d/%d" % [quiz_i + 1, qs.size()], Color(1, 0.9, 0.5), 15)
	draw_rect(Rect2(r.position.x + 330, r.position.y + 58, 130, 26), Color(0.15, 0.15, 0.2, 0.95))
	draw_rect(Rect2(r.position.x + 330, r.position.y + 58, 130, 26), Color(1, 1, 1, 0.4), false, 1.5)
	_txt_center(r.position.y + 74, "跳過測驗", Color.WHITE, 12, 114, r.position.x + 338)
	var qtext: String = str(q["q"])
	var lines: Array = []
	while qtext.length() > 20:
		lines.append(qtext.substr(0, 20))
		qtext = qtext.substr(20)
	lines.append(qtext)
	for i in lines.size():
		_txt(r.position + Vector2(20, 92 + 22 * i), str(lines[i]), Color.WHITE, 13)
	var o0: Dictionary = q["opts"][0]
	var o1: Dictionary = q["opts"][1]
	var b0 := Rect2(r.position.x + 40, r.position.y + 210, r.size.x - 80, 46)
	var b1 := Rect2(r.position.x + 40, r.position.y + 272, r.size.x - 80, 46)
	draw_rect(b0, Color(0.18, 0.3, 0.55, 0.95))
	draw_rect(b0, Color(0.6, 0.8, 1.0), false, 1.5)
	_txt_center(b0.position.y + 28, "%s（%s）" % [o0.t, o0.g], Color.WHITE, 14, b0.size.x - 16, b0.position.x + 8)
	draw_rect(b1, Color(0.4, 0.22, 0.4, 0.95))
	draw_rect(b1, Color(1, 0.7, 0.95), false, 1.5)
	_txt_center(b1.position.y + 28, "%s（%s）" % [o1.t, o1.g], Color.WHITE, 14, b1.size.x - 16, b1.position.x + 8)
	_txt(r.position + Vector2(20, r.size.y - 4), "答完 12 題就決定理念，唔改得", Color(0.6, 0.65, 0.75), 9)

# ================= 繪畫 =================
func _draw() -> void:
	if main == null:
		return
	var s := get_viewport_rect().size
	if creation_mode:
		_draw_create(s)
		return
	_draw_status()
	_draw_spell_bar(s)
	_draw_target(s)
	_draw_btns(s)
	_draw_debug_strip()
	_draw_log(s)
	if _t < 12.0:                       # 開場提示，12 秒後淡出
		_txt(Vector2(8, s.y - 12), "拖左下移動 · 點怪攻擊 · 點地行路 · 自動=掛機", Color(1, 1, 1, 0.55), 10)

# 左上角色框
func _draw_status() -> void:
	var ch: Dictionary = main.ch
	if ch.is_empty():
		return
	var lv := int(ch.level)
	var mhp := RulesStats.max_hp(lv, ch.attrs)
	var mmp := RulesStats.max_mp(lv, ch.attrs)
	var msp := RulesStats.max_sp(lv, ch.attrs)
	var need := RulesStats.exp_to_next(lv)
	var fr := Rect2(6, 6, 244, 98)
	draw_rect(fr, Color(0, 0, 0, 0.55))
	draw_rect(fr, Color(1, 1, 1, 0.3), false, 1.0)
	# 頭像
	var pr := Rect2(12, 12, 64, 64)
	draw_rect(pr, Color(0, 0, 0, 0.4))
	var me = main._me()
	if me != null:
		var faces: Array = main.faces
		if faces.size() > 0:
			var f = faces[int(me.face) % faces.size()]
			if f != null:
				draw_texture_rect(f, pr, true)
	draw_rect(pr, Color(1, 1, 1, 0.35), false, 1.0)
	# 文字
	_txt(Vector2(84, 20), "%s  Lv%d" % [main.ch.name, lv], Color.WHITE, 13)
	_txt(Vector2(84, 34), "%s" % RulesKarma.tier_name(int(ch.karma)), Color(1, 0.85, 0.4), 9)
	# 四條 bar: HP/MP/SP/EXP（左 label + bar）
	_bar(128, 44, 116, 7, float(ch.hp) / mhp, Color(0.85, 0.2, 0.2)); _txt(Vector2(84, 52), "HP", Color(1, 0.7, 0.7), 9)
	_bar(128, 56, 116, 7, float(ch.mp) / mmp, Color(0.25, 0.45, 0.95)); _txt(Vector2(84, 64), "MP", Color(0.7, 0.8, 1.0), 9)
	_bar(128, 68, 116, 7, float(ch.sp) / msp, Color(0.9, 0.8, 0.2)); _txt(Vector2(84, 76), "SP", Color(1, 0.9, 0.6), 9)
	_bar(128, 80, 116, 7, float(ch.exp) / maxi(1, need), Color(0.7, 0.4, 0.95)); _txt(Vector2(84, 88), "EXP", Color(0.85, 0.7, 1.0), 9)
	_txt(Vector2(12, 94), "金 %d" % int(ch.gold), Color(1, 0.9, 0.5), 10)

# 頂中目標框（點咗怪先有）
func _draw_target(s: Vector2) -> void:
	var t = main.target_ent()
	if t == null:
		return
	var w := 190.0
	var r := Rect2(s.x / 2 - w / 2, 4, w, 34)
	draw_rect(r, Color(0, 0, 0, 0.6))
	draw_rect(r, Color(0.9, 0.35, 0.2), false, 1.5)
	var max_hp := maxi(1, int(t.maxHp))
	_txt(Vector2(r.position.x + 8, r.position.y + 13), "%s  Lv%d" % [t.name, int(t.level)], Color(1, 0.8, 0.7), 11)
	_bar(r.position.x + 8, r.position.y + 26, w - 16, 5, float(t.hp) / max_hp, Color(0.9, 0.25, 0.15))

# 右下按鈕: 普攻(大圓) / 自動(圓) / 右上背包
# 快捷列 (Step 9+10): 術書 3 格 (道士) + 絕招 1 格 (義士) + 寶石 2 格 (全職)
# 撳空格 = 自動裝備背包第一本術書/寶石；撳有嘢格 = 施法 / 用絕招 / 卸寶石
func _spell_bar_y() -> float:
	var s := get_viewport_rect().size
	return (s.y - 196) if not use_touch else (s.y * 0.38 - 54)


func _spell_rect(i: int) -> Rect2:
	return Rect2(8 + i * 58, _spell_bar_y(), 54, 34)


func _spell_books() -> Array:
	if main == null or main.ch.is_empty():
		return [0, 0, 0]
	return (main.ch.get("equip", {}).get("spellbooks", [0, 0, 0])) as Array


func _bar_visible() -> bool:
	if main == null or main.ch.is_empty():
		return false
	var ch: Dictionary = main.ch
	if str(ch.get("classId", "")) == "daoshi" or str(ch.get("classId", "")) == "yishi":
		return true
	return not (ch.get("ultimates", []) as Array).is_empty() or not (ch.get("equip", {}).get("jewels", [0, 0]) as Array).is_empty()


func _spell_bar_hit(pos: Vector2) -> bool:
	if not _bar_visible():
		return false
	for i in 6:
		if _spell_rect(i).has_point(pos):
			_spell_tap(i)
			return true
	return false


# 0-2 術書 (道士); 3 = 絕招 (最新一招); 4-5 寶石欄
func _spell_tap(slot: int) -> void:
	var ch: Dictionary = main.ch
	if slot <= 2:
		var books := _spell_books()
		if int(books[slot]) == 0:
			for b in ch["bag"]:
				if not main.data.spell_by_item.has(int(b["id"])):
					continue
				main._send({"t": "equip_spellbook", "item": int(b["id"]), "slot": slot})
				return
			main._log("背包冇術書 (武器店有得買)")
			return
		var t = main.target_ent()
		var tgt := int(t.id) if t != null and bool(t.get("mob", false)) else 0
		main._send({"t": "cast_spell", "slot": slot, "target": tgt})
		return
	if slot == 3:
		var ults: Array = ch.get("ultimates", [])
		if ults.is_empty():
			main._log("未學絕招 (絕招任務: 練兵場門口禁衛大隊長)")
			return
		main._send({"t": "use_ultimate", "ult": str(ults[ults.size() - 1])})
		return
	var jslot := slot - 4
	var jews: Array = ch.get("equip", {}).get("jewels", [0, 0])
	if int(jews[jslot]) != 0:
		main._send({"t": "equip_jewel", "item": 0, "slot": jslot})
	else:
		for b in ch["bag"]:
			if main.data.jewel_by_item.has(int(b["id"])):
				main._send({"t": "equip_jewel", "item": int(b["id"]), "slot": jslot})
				return
		main._log("背包冇寶石 (打怪/商店)")


func _draw_spell_bar(s: Vector2) -> void:
	if not _bar_visible():
		return
	_txt(Vector2(8, _spell_bar_y() - 12), "快捷列 (撳=施/裝/絕招/寶石)", Color(0.85, 0.7, 1.0), 9)
	var books := _spell_books()
	var ch: Dictionary = main.ch
	var jews: Array = ch.get("equip", {}).get("jewels", [0, 0])
	var ults: Array = ch.get("ultimates", [])
	for i in 6:
		var r := _spell_rect(i)
		draw_rect(r, Color(0.12, 0.12, 0.2, 0.85))
		var col: Color = Color(0.75, 0.55, 0.95, 0.9)
		var item := 0
		var nm: String = "空"
		var sub := ""
		if i <= 2:
			item = int(books[i])
			if item > 0:
				nm = str(main.item_names.get(item, str(item)))
				if nm.length() > 4:
					nm = nm.substr(0, 4)
				var sdef: Dictionary = main.data.spell_by_item.get(item, {})
				sub = "MP%d" % int(sdef.get("mp", 0))
			_txt(r.position + Vector2(4, 14), "%d %s" % [i + 1, nm], Color.WHITE, 11)
			_txt(r.position + Vector2(4, 27), sub, Color(0.7, 0.8, 1.0), 9)
		elif i == 3:
			col = Color(1, 0.55, 0.25, 0.95)
			if not ults.is_empty():
				nm = str(main.data.ult_by_id.get(str(ults[ults.size() - 1]), {}).get("name", "絕招"))
				if nm.length() > 4:
					nm = nm.substr(0, 4)
			_txt(r.position + Vector2(4, 14), "絕 %s" % nm, Color(1, 1, 0.9), 11)
			_txt(r.position + Vector2(4, 27), "MP+SP", Color(1, 0.8, 0.6), 9)
		else:
			item = int(jews[i - 4])
			col = Color(0.9, 0.8, 0.4, 0.9)
			if item > 0:
				nm = str(main.item_names.get(item, str(item)))
				if nm.length() > 4:
					nm = nm.substr(0, 4)
				sub = "石"
			_txt(r.position + Vector2(4, 14), "%s" % nm, Color(1, 1, 0.8), 11)
			_txt(r.position + Vector2(4, 27), sub, Color(0.8, 0.8, 0.5), 9)
		draw_rect(r, col, false, 1.5)


func _draw_btns(s: Vector2) -> void:
	var ac := Vector2(s.x - 76, s.y - 76)
	draw_circle(ac, 42, Color(0.12, 0.12, 0.12, 0.8))
	draw_arc(ac, 42, 0, TAU, 64, Color(0.95, 0.35, 0.25), 3.0)
	_txt_center(ac.y - 10, "普攻", Color.WHITE, 17, 60, ac.x - 30)
	var ab := Vector2(s.x - 62, s.y - 190)
	draw_circle(ab, 29, Color(0.9, 0.18, 0.1, 0.75) if auto else Color(0.12, 0.12, 0.12, 0.8))
	draw_arc(ab, 29, 0, TAU, 56, Color(1, 0.85, 0.3) if auto else Color(1, 1, 1, 0.7), 2.5)
	_txt_center(ab.y - 8, "自動", Color.WHITE, 12, 44, ab.x - 22)
	var br := Rect2(s.x - 66, 6, 60, 40)
	draw_rect(br, Color(0.12, 0.12, 0.12, 0.8))
	draw_rect(br, Color(1, 1, 1, 0.7), false, 1.5)
	_txt(Vector2(br.position.x + 12, br.position.y + 15), "背包", Color.WHITE, 14)
	var qr := _quest_rect()
	draw_rect(qr, Color(0.12, 0.12, 0.12, 0.8))
	draw_rect(qr, Color(0.9, 0.8, 0.4, 0.9), false, 1.5)
	_txt(Vector2(qr.position.x + 12, qr.position.y + 15), "記事", Color(1, 0.95, 0.7), 13)
	_txt(Vector2(qr.position.x + 12, qr.position.y + 32), "任務", Color(0.9, 0.85, 0.6), 9)
	var tp := _near_travel_point()
	if not tp.is_empty():                                    # 行近城門/傳送點先顯示
		var tr := _travel_rect()
		draw_rect(tr, Color(0.2, 0.6, 0.3, 0.85))
		draw_rect(tr, Color(1, 1, 1, 0.8), false, 1.5)
		_txt(Vector2(tr.position.x + 10, tr.position.y + 16), "傳送", Color.WHITE, 13)
		_txt(Vector2(tr.position.x + 10, tr.position.y + 32), String(tp.get("name", "")).substr(0, 8), Color(0.9, 1, 0.9), 9)

# 手機 debug 掣: 未有正式面板嗰啲功能(工作/天地商行/食物/打招呼)臨時用嚟測試，成品前換走
func _draw_debug_strip() -> void:
	for i in DEBUG_ACTIONS.size():
		var r := _debug_rect(i)
		draw_rect(r, Color(0.1, 0.1, 0.15, 0.75))
		draw_rect(r, Color(1, 1, 1, 0.4), false, 1.0)
		_txt(r.position + Vector2(6, 17), String(DEBUG_ACTIONS[i]["label"]), Color(0.9, 0.9, 1.0), 11)

# 底部日誌（最後 3 行）
func _draw_log(s: Vector2) -> void:
	var lines: Array = main.log_lines
	var n := lines.size()
	if n == 0:
		return
	var show: Array = lines.slice(maxi(0, n - 3))
	for i in show.size():
		_txt(Vector2(s.x / 2 - 208, s.y - 20 - 13 * (show.size() - 1 - i)), str(show[i]), Color(1, 1, 0.7), 11)
	var strip := Rect2(s.x / 2 - 220, s.y - 32 - 13 * show.size(), 440, 8 + 13 * show.size())
	draw_rect(strip, Color(0, 0, 0, 0.35))

# ================= 小工具 (同 main.gd 一致) =================
func _bar(x: float, y: float, w: float, h: float, ratio: float, col: Color) -> void:
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(x, y, w * clampf(ratio, 0.0, 1.0), h), col)

func _txt(pos: Vector2, str_: String, col := Color.WHITE, sz := 12) -> void:
	draw_string(ThemeDB.fallback_font, pos, str_, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _txt_center(y: float, str_: String, col: Color, sz: int, w: float, x: float) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(x, y), str_, HORIZONTAL_ALIGNMENT_CENTER, w, sz, col)