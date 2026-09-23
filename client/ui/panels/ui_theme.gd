class_name UiTheme
extends RefCounted
# 面板主題（三國風: 墨啡底 + 金邊）。掣最細 44px 高，字 15 號，手機睇得清撳得中。

const BG := Color(0.10, 0.08, 0.06, 0.97)
const GOLD := Color(0.85, 0.68, 0.35)
const TEXT := Color(0.98, 0.92, 0.78)
const DIM := Color(0.70, 0.64, 0.55)
const GOOD := Color(0.65, 1.0, 0.6)
const BAD := Color(1.0, 0.5, 0.45)
const FONT := 15
const BTN_H := 44.0

static var _theme: Theme


static func sb(bg: Color, border: Color, bw := 2, radius := 6, pad := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = FONT
	# 掣
	t.set_stylebox("normal", "Button", sb(Color(0.22, 0.16, 0.10), Color(0.6, 0.48, 0.28)))
	t.set_stylebox("hover", "Button", sb(Color(0.30, 0.22, 0.13), GOLD))
	t.set_stylebox("pressed", "Button", sb(Color(0.50, 0.33, 0.12), Color(1, 0.85, 0.45)))
	t.set_stylebox("hover_pressed", "Button", sb(Color(0.50, 0.33, 0.12), Color(1, 0.85, 0.45)))
	t.set_stylebox("disabled", "Button", sb(Color(0.14, 0.13, 0.12), Color(0.3, 0.28, 0.25)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.47, 0.42))
	# 文字
	t.set_color("font_color", "Label", TEXT)
	# 視窗
	t.set_stylebox("panel", "PanelContainer", sb(BG, GOLD, 2, 8, 10))
	# 捲動條闊啲，手指撳得到
	var grab := sb(Color(0.6, 0.48, 0.28, 0.8), Color(0, 0, 0, 0), 0, 4, 0)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", sb(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0, 4, 3))
	_theme = t
	return t
