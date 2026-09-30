class_name GamePanel
extends Control
# 正式面板基底（三國群英傳M 風格）: 半透明遮罩 + 中央視窗 + 標題 + 頁籤 + 右上 ✕。
# 撳遮罩 / ✕ / Android 返回鍵 / Esc = 關。子類 override _build_body()，用 sig() 判斷要唔要重砌。
# UI 只經 main._send 發意圖（sim 權威）；面板唔直接改 ch。

signal closed

var main: Node                 # ui/main.gd
var win: PanelContainer
var title_lbl: Label
var tabs_box: HBoxContainer
var body: VBoxContainer
var tab := 0
var tab_names: Array = []
var _last_sig := ""
var _t := 0.0
var margin := 10.0             # 視窗離屏幕邊（細視窗例如對話框會改）


func _init(m: Node) -> void:
	main = m
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(dim)
	win = PanelContainer.new()
	add_child(win)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	win.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	title_lbl = Label.new()
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", UiTheme.GOLD)
	title_lbl.custom_minimum_size.x = 80
	top.add_child(title_lbl)
	tabs_box = HBoxContainer.new()
	tabs_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_box.add_theme_constant_override("separation", 4)
	top.add_child(tabs_box)
	var x := btn("✕", close, 48)
	top.add_child(x)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	v.add_child(body)
	hide()


func open() -> void:
	_last_sig = ""
	show()
	_layout_win()
	refresh(true)


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _layout_win() -> void:
	var vs := get_viewport_rect().size
	var safe: Rect2 = main.hud.safe_rect() if main != null and main.hud != null else Rect2(Vector2.ZERO, vs)
	var r := _win_rect(safe)
	win.position = r.position
	win.size = r.size


# 預設: 差唔多成個安全區（子類可以 override 做細視窗）
func _win_rect(safe: Rect2) -> Rect2:
	return safe.grow(-margin)


func set_tabs(names: Array) -> void:
	tab_names = names
	for c in tabs_box.get_children():
		c.queue_free()
	for i in names.size():
		var b := btn(String(names[i]), func() -> void: set_tab(i), 72)
		b.toggle_mode = true
		b.button_pressed = i == tab
		tabs_box.add_child(b)


func set_tab(i: int) -> void:
	tab = i
	for j in tabs_box.get_child_count():
		(tabs_box.get_child(j) as Button).set_pressed_no_signal(j == i)
	refresh(true)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 0.2:
		_t = 0.0
		_layout_win()
		refresh(false)


# 狀態有變先重砌（唔會每幀砌，撳緊嘅掣唔會無端端消失）
func refresh(force: bool) -> void:
	var s := sig()
	if not force and s == _last_sig:
		return
	_last_sig = s
	# 定期自動 refresh 會整個 body 拆咗再砌過 (包括入面嘅 ScrollContainer)，
	# 唔記住捲軸位就會每次彈返去最頂 —— 玩家手指拖緊都會被打斷。
	# 記低拖緊嗰個 scrollbar 位，砌完之後（等一幀 layout 好）先擺返轉去。
	var scroll_pos := _find_scroll_v()
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_build_body()
	if scroll_pos >= 0.0:
		call_deferred("_restore_scroll_v", scroll_pos)


func _find_scroll_v() -> float:
	for c in body.get_children():
		if c is ScrollContainer:
			return (c as ScrollContainer).scroll_vertical
	return -1.0


func _restore_scroll_v(v: float) -> void:
	for c in body.get_children():
		if c is ScrollContainer:
			(c as ScrollContainer).scroll_vertical = int(v)
			return


func sig() -> String:
	return ""


func _build_body() -> void:
	pass


# ---- 小工具 ----
func btn(text: String, cb: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, UiTheme.BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		if main != null and main.hud != null:
			main.hud.haptic()
		cb.call())
	return b


# 道具圖示 (AssetLib, 冇圖返 null → 純文字 fallback)
func item_icon_btn(b: Button, id: int, vertical := false) -> void:
	var t := AssetLib.item_icon(id)
	if t == null:
		return
	b.icon = t
	b.expand_icon = false
	if vertical:
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	else:
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT


# 原版 NPC/武將頭像 (按名; 冇就 null)
func portrait(npc_name: String, px := 56) -> TextureRect:
	var t := AssetLib.face_by_name(npc_name)
	if t == null:
		return null
	var r := TextureRect.new()
	r.texture = t
	r.custom_minimum_size = Vector2(px * 0.9, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return r


# 標題行: 大圖 (100px 縮 56) + 名，冇圖只出名
func item_title(id: int, sz := 18) -> Control:
	var t := AssetLib.item_icon(id, true)
	if t == null:
		return lbl(item_name(id), sz, UiTheme.GOLD)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var r := TextureRect.new()
	r.texture = t
	r.custom_minimum_size = Vector2(56, 56)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(r)
	var l := lbl(item_name(id), sz, UiTheme.GOLD)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h


func lbl(text: String, sz := UiTheme.FONT, col := UiTheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l


func wrap_lbl(text: String, sz := UiTheme.FONT, col := UiTheme.TEXT) -> Label:
	var l := lbl(text, sz, col)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


# 可以用手指拖嘅直向捲動區
func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.scroll_deadzone = 8
	# VScrollBar 預設闊度得 10~16px，手指好難撳中；theme stylebox 改唔到 widget
	# 本身闊度，要直接摞返個 v scrollbar node 加大佢 custom_minimum_size。
	var vbar := s.get_v_scroll_bar()
	if vbar:
		vbar.custom_minimum_size.x = 36.0
	return s


func hsep() -> HSeparator:
	return HSeparator.new()


# 數量選擇器 [-] n [+] [最多]；on_change(n)
func stepper(n: int, max_n: int, on_change: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.add_child(btn("－", func() -> void: on_change.call(maxi(1, n - 1)), 48))
	var l := lbl(str(n), 18)
	l.custom_minimum_size.x = 40
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(l)
	h.add_child(btn("＋", func() -> void: on_change.call(mini(maxi(1, max_n), n + 1)), 48))
	h.add_child(btn("最多", func() -> void: on_change.call(maxi(1, max_n)), 56))
	return h


func item_name(id: int) -> String:
	return str(main.item_names.get(id, str(id)))


# 物品說明行: 類別 / 等級要求 / 效果
func item_desc(id: int) -> Array:
	var out: Array = []
	var inf: Dictionary = main.data.info.get(id, {})
	var head := str(inf.get("cat_label", ""))
	if int(inf.get("req_lv", 0)) > 1:
		head += "   需要 Lv%d" % int(inf["req_lv"])
	if head != "":
		out.append(head)
	var heal: Dictionary = main.data.heals.get(id, {})
	if not heal.is_empty():
		var p: Array = []
		for k in ["hp", "mp", "sp"]:
			if int(heal.get(k, 0)) > 0:
				p.append("%s +%d" % [k.to_upper(), int(heal[k])])
		out.append("回復 " + " ".join(p))
	var sp: Dictionary = main.data.spell_by_item.get(id, {})
	if not sp.is_empty():
		out.append("術法「%s」 MP %d  Lv%d" % [sp.get("name", "?"), int(sp.get("mp", 0)), int(sp.get("lv", 1))])
	var jd: Dictionary = main.data.jewel_by_item.get(id, {})
	if not jd.is_empty():
		out.append("寶石「%s」" % str(jd.get("name", "?")))
	for e in inf.get("effects", []):
		var lab := str(e["label"])
		if lab == "" or int(e["type"]) in [14, 16]:
			continue
		var val := int(e["value"])
		out.append(lab if val == 0 else "%s %d" % [lab, val])
	return out


# ---- 裝備 (Step 11.6) ----
const ARMOR_STAT_NAMES := [["def", "物防"], ["evade", "物迴避%"], ["sdef", "術防"], ["sevade", "術迴避%"],
	["str", "武力"], ["agi", "敏捷"], ["int", "智力"], ["spi", "靈力"], ["dmgRed", "物理受擊-%"], ["sdmgRed", "術法受擊-%"]]


func slot_name(slot: String) -> String:
	return str(main.data.equip_cfg["slotNames"].get(slot, slot))


# 防具/武器耐久 (Step 12 武器都有)
func armor_dur_text(ch: Dictionary, id: int) -> String:
	var mx := int(main.data.armors.get(id, main.data.weapons.get(id, {})).get("max_dur", 0))
	var cur := int(ch.get("equip", {}).get("dur", {}).get(str(id), mx))
	return "耐久 %d/%d%s" % [cur, mx, "（減半）" if cur <= 0 else ""]


# 防具同身上同部位嗰件比較: [[text, color]]，↑ 綠 ↓ 紅
func armor_compare(ch: Dictionary, id: int) -> Array:
	var ad: Dictionary = main.data.armors.get(id, {})
	if ad.is_empty():
		return []
	var cur_id := int(ch.get("equip", {}).get(str(ad["slot"]), 0))
	var cur: Dictionary = main.data.armors.get(cur_id, {}).get("stats", {})
	var out: Array = []
	for pair in ARMOR_STAT_NAMES:
		var k: String = pair[0]
		var nv := int(ad["stats"].get(k, 0))
		var ov := int(cur.get(k, 0)) if cur_id != id else nv
		if nv == 0 and ov == 0:
			continue
		var diff := nv - ov
		var t := "%s %d" % [pair[1], nv]
		if diff != 0:
			t += "  (%s%d)" % ["↑" if diff > 0 else "↓", absi(diff)]
		out.append([t, UiTheme.GOOD if diff > 0 else UiTheme.BAD if diff < 0 else UiTheme.TEXT])
	return out
