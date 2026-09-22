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

var main: Node2D           # 引用 main.gd: 讀 ch/ents/faces/log_lines，用 _bar/_txt 畫
var joy: SangoJoystick
var auto := false
var use_touch := false
var _t := 0.0              # 開場提示計時

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

func _near_travel_point() -> Dictionary:
	return main.call("_near_travel") if main != null else {}

func _button_hit(pos: Vector2) -> bool:
	if _attack_rect().has_point(pos):
		attack_pressed.emit()
		return true
	if _auto_rect().has_point(pos):
		auto = not auto
		queue_redraw()
		auto_toggled.emit(auto)
		return true
	if _bag_rect().has_point(pos):
		bag_pressed.emit()
		return true
	if not _near_travel_point().is_empty() and _travel_rect().has_point(pos):
		travel_pressed.emit()
		return true
	return false

# ================= 繪畫 =================
func _draw() -> void:
	if main == null:
		return
	var s := get_viewport_rect().size
	_draw_status()
	_draw_target(s)
	_draw_btns(s)
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
	var tp := _near_travel_point()
	if not tp.is_empty():                                    # 行近城門/傳送點先顯示
		var tr := _travel_rect()
		draw_rect(tr, Color(0.2, 0.6, 0.3, 0.85))
		draw_rect(tr, Color(1, 1, 1, 0.8), false, 1.5)
		_txt(Vector2(tr.position.x + 10, tr.position.y + 16), "傳送", Color.WHITE, 13)
		_txt(Vector2(tr.position.x + 10, tr.position.y + 32), String(tp.get("name", "")).substr(0, 8), Color(0.9, 1, 0.9), 9)

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