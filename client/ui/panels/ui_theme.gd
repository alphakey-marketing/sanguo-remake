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

# 原版皮 (assets_orig/ui，A3): 有素材先生效；user://settings.cfg [ui] skin="flat" 可強制用返舊墨啡金邊
static var skin_orig := true
static var _theme: Theme
static var _font_installed := false
static var _cjk: Font


static func sb(bg: Color, border: Color, bw := 2, radius := 6, pad := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


static func get_theme() -> Theme:
	install_font()
	if _theme != null:
		return _theme
	var t := Theme.new()
	_read_skin_setting()
	t.default_font_size = FONT
	t.default_font = _cjk_font()   # panel Label/Button 字形
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
	if skin_orig and AssetLib.ui("panel") != null and AssetLib.ui("btn_n") != null:
		_apply_orig_skin(t)
	_theme = t
	return t


static func _read_skin_setting() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		skin_orig = str(cf.get_value("ui", "skin", "orig")) != "flat"


static func tex_sb(tex: Texture2D, margin: int, content: int, tint := Color.WHITE) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.set_texture_margin_all(margin)
	s.set_content_margin_all(content)
	s.modulate_color = tint
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return s


# 原版木板視窗 + 羊皮紙掣；視窗壓暗 (亮字要夠對比)，掣字改深啡色
static func _apply_orig_skin(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", tex_sb(AssetLib.ui("panel"), 24, 14, Color(0.5, 0.42, 0.36)))
	var dark := Color(0.2, 0.1, 0.03)
	# 掣: 單色羊皮紙 + 細深啡邊 (原版掣圖字燒死、難睇)
	var edge := Color(0.36, 0.24, 0.1)
	t.set_stylebox("normal", "Button", sb(Color(0.9, 0.8, 0.58), edge, 1, 3, 8))
	t.set_stylebox("hover", "Button", sb(Color(0.97, 0.88, 0.66), edge, 1, 3, 8))
	t.set_stylebox("pressed", "Button", sb(Color(0.78, 0.66, 0.44), edge, 1, 3, 8))
	t.set_stylebox("hover_pressed", "Button", sb(Color(0.78, 0.66, 0.44), edge, 1, 3, 8))
	t.set_stylebox("disabled", "Button", sb(Color(0.62, 0.58, 0.5), Color(0.4, 0.37, 0.32), 1, 3, 8))
	t.set_color("font_color", "Button", dark)
	t.set_color("font_hover_color", "Button", Color.BLACK)
	t.set_color("font_pressed_color", "Button", Color(0.45, 0.05, 0.02))
	t.set_color("font_hover_pressed_color", "Button", Color(0.45, 0.05, 0.02))
	t.set_color("font_disabled_color", "Button", Color(0.35, 0.32, 0.3))


static func _cjk_font() -> Font:
	if _cjk == null:
		_cjk = load("res://assets_placeholder/fonts/NotoSansTC-VF.ttf") as Font
	return _cjk


# Embed 中文字體（Noto Sans TC, OFL）。Web/iOS/Android 唔靠系統中文字形 fallback（會缺口），
# 直接 embed CJK 字，set 去 ThemeDB fallback（main 畫 HUD 名嗰啲 UI 都用佢）。
static func install_font() -> void:
	if _font_installed:
		return
	var f := _cjk_font()
	if f != null:
		ThemeDB.set_fallback_font(f)
	_font_installed = true
