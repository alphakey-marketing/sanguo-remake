class_name SangoJoystick
extends Control
# 浮動虛擬搖桿（三國群英傳M 風格）: 喺 zone 內按下 → 搖桿彈出喺手指位;
# 拖動 → get_direction() 回傳 0..1 方向; 放手 → released(dir)。
# input 由 MobileHud 路由（handle_event），唔自己掛 _input，避免同按鈕爭食。
# use_touch=true: Android（emulate_mouse_from_touch）用 ScreenTouch/ScreenDrag；
# false: 桌面用 mouse 模擬（左鍵拖 = 搖桿），方便未接真機前試手感。

signal moved(dir: Vector2)
signal released(dir: Vector2)

const RADIUS := 38.0
const KNOB := 17.0
const DEAD := 7.0

var zone := Rect2()          # 搖桿區（screen 座標，每次事件前由 HUD 更新）
var use_touch := false

var active := false
var idx := -1
var base := Vector2.ZERO     # 搖桿彈出位置（手指落點）
var off := Vector2.ZERO      # 搖桿芯偏移

func get_direction() -> Vector2:
	if not active:
		return Vector2.ZERO
	var d := off.length()
	if d < DEAD:
		return Vector2.ZERO
	return off / d * clampf(d / RADIUS, 0.0, 1.0)

# 回傳 true = 已處理（HUD 要 consume）。冇關嘅事件一律唔理，放行俾世界點擊。
func handle_event(ev: InputEvent) -> bool:
	var handled := false
	if use_touch:
		if ev is InputEventScreenTouch:
			var t := ev as InputEventScreenTouch
			if t.pressed:
				if active:
					pass                       # 第二隻手指唔搶走搖桿（放行做世界點擊）
				elif zone.has_point(t.position):
					_start(t.position, t.index)
					handled = true
			elif active and t.index == idx:
				_end()
				handled = true
		elif ev is InputEventScreenDrag:
			var d := ev as InputEventScreenDrag
			if active and d.index == idx:
				_update(d.position)
				handled = true
		return handled
	# 桌面 mouse 模擬
	if ev is InputEventMouseButton:
		var m := ev as InputEventMouseButton
		if m.button_index != MOUSE_BUTTON_LEFT:
			return false
		if m.pressed:
			if zone.has_point(m.position):
				_start(m.position, -99)
				handled = true
		elif active:
			_end()
			handled = true
	elif ev is InputEventMouseMotion and active:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_update((ev as InputEventMouseMotion).position)
			handled = true
	return handled

func _start(p: Vector2, i: int) -> void:
	base = p
	off = Vector2.ZERO
	idx = i
	active = true
	queue_redraw()

func _update(p: Vector2) -> void:
	var v: Vector2 = p - base
	if v.length() > RADIUS:
		v = v.normalized() * RADIUS
	off = v
	queue_redraw()
	moved.emit(get_direction())

func _end() -> void:
	var dir := get_direction()
	active = false
	idx = -1
	off = Vector2.ZERO
	queue_redraw()
	released.emit(dir)

func _draw() -> void:
	if not active:
		# idle 提示圈（zone 左下角，淡）
		if zone.size.x > 0:
			var c := zone.position + Vector2(58, 58)
			draw_circle(c, 24, Color(1, 1, 1, 0.07))
			draw_arc(c, 24, 0, TAU, 48, Color(1, 1, 1, 0.14), 2.0)
		return
	draw_circle(base, RADIUS, Color(1, 1, 1, 0.10))
	draw_arc(base, RADIUS, 0, TAU, 64, Color(1, 1, 1, 0.75), 2.5)
	draw_circle(base + off, KNOB, Color(1, 1, 1, 0.85))
	draw_arc(base + off, KNOB, 0, TAU, 40, Color(0.2, 0.2, 0.2, 0.5), 1.5)