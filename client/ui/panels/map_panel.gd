class_name MapPanel
extends GamePanel
# 地圖面板 (spec 12 §6)。撳小地圖開。
#   區域: 當前地圖全圖 + 地標/門口/設施/任務 NPC/自己；已到過嘅地標有名，未到過 = 「？」
#   天下: 豫州荊州城池節點 + 路線；自己所在發光；未開放 = 灰 (B3 開)；撳已開放節點 →「自動前往」(sim.cmd_goto_map)

var _info := ""                  # 天下頁: 撳咗邊個節點嘅說明
var _sel_map := ""               # 天下頁: 撳咗嘅已開放節點對應地圖 ("" = 冇 / 而家喺度)


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "地圖"
	set_tabs(["區域", "天下"])


func sig() -> String:
	var me = main._me()
	return JSON.stringify([tab, _info, _sel_map, main.cur_map.get("id", ""), int(me.x) if me != null else 0, int(me.y) if me != null else 0])


func _build_body() -> void:
	var view := Control.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(view)
	if tab == 0:
		view.draw.connect(func() -> void: _draw_area(view))
	else:
		view.draw.connect(func() -> void: _draw_world(view))
		view.gui_input.connect(func(ev: InputEvent) -> void: _world_tap(view, ev))
		var row := HBoxContainer.new()
		row.add_child(wrap_lbl(_info if _info != "" else "撳城池睇詳情。灰色 = 未開放（之後版本開通）", 13, UiTheme.DIM))
		if _sel_map != "":
			row.add_child(btn("自動前往", func() -> void: goto_sel(), 120))
		body.add_child(row)


# ---- 區域 ----
func _fit(view: Control, md: Dictionary) -> Array:
	var ms := Vector2(float(md.w), float(md.h))
	var k := minf(view.size.x / ms.x, view.size.y / ms.y)
	var off := (view.size - ms * k) / 2.0
	return [k, off]


func _draw_area(view: Control) -> void:
	var md: Dictionary = main.cur_map
	if md.is_empty():
		return
	var f := _fit(view, md)
	var k: float = f[0]
	var off: Vector2 = f[1]
	var ms := Vector2(float(md.w), float(md.h))
	view.draw_texture_rect(MapArt.minimap(main.data, md), Rect2(off, ms * k), false)
	view.draw_rect(Rect2(off, ms * k), UiTheme.GOLD, false, 1.5)
	var font := ThemeDB.fallback_font
	var at := func(x: int, y: int) -> Vector2:
		return off + (Vector2(x - int(md.ox), y - int(md.oy)) + Vector2(0.5, 0.5)) * k
	var seen: Array = main.ch.get("landmarks", [])
	for lm in main.data.landmarks:
		if String(lm["map"]) != String(md.id):
			continue
		var p: Vector2 = at.call(int(lm.x), int(lm.y))
		var known := seen.has(String(lm["id"]))
		view.draw_circle(p, 4, Color(0.95, 0.75, 0.3) if known else Color(0.6, 0.6, 0.6))
		view.draw_string(font, p + Vector2(6, 4), String(lm["name"]) if known else "？", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.92, 0.7))
	for fc in main.facilities:
		if not Rect2i(int(md.ox), int(md.oy), int(md.w), int(md.h)).has_point(Vector2i(int(fc.x), int(fc.y))):
			continue
		var p: Vector2 = at.call(int(fc.x), int(fc.y))
		view.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), fc.color)
		view.draw_string(font, p + Vector2(5, -3), str(fc.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.95, 0.9))
	for qn in main.quest_npcs:
		if main.sim.map_id_at(int(qn.x), int(qn.y)) == String(md.id):
			view.draw_circle(at.call(int(qn.x), int(qn.y)), 3, Color(0.4, 0.75, 1.0))
	var me = main._me()
	if me != null:
		var mp: Vector2 = at.call(int(me.x), int(me.y))
		view.draw_circle(mp, 5, Color(1, 0.9, 0.2))
		view.draw_arc(mp, 8, 0, TAU, 20, Color(1, 0.9, 0.2, 0.7), 1.5)
	view.draw_string(font, off + Vector2(4, 16), String(md.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.GOLD)


# ---- 天下 ----
func _node_pos(view: Control, n: Dictionary) -> Vector2:
	var pad := Vector2(40, 16)
	return pad + Vector2(float(n.x), float(n.y)) * (view.size - pad * 2)


func _draw_world(view: Control) -> void:
	var w: Dictionary = main.data.world_map
	if w.is_empty():
		return
	var font := ThemeDB.fallback_font
	var nodes := {}
	for n in w["nodes"]:
		nodes[String(n.id)] = n
	# 州界示意: 上半豫州、下半荊州
	view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(0.18, 0.15, 0.1, 0.6))
	view.draw_string(font, Vector2(view.size.x - 60, 20), "豫州", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.7, 0.5, 0.6))
	view.draw_string(font, Vector2(view.size.x - 60, view.size.y - 10), "荊州", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.7, 0.5, 0.6))
	for e in w["edges"]:
		var a: Dictionary = nodes[String(e[0])]
		var b: Dictionary = nodes[String(e[1])]
		var open := a.get("map") != null and b.get("map") != null
		view.draw_line(_node_pos(view, a), _node_pos(view, b), Color(0.85, 0.7, 0.4) if open else Color(0.45, 0.42, 0.38), 2.0 if open else 1.0)
	var here := _here_node()
	for n in w["nodes"]:
		var p := _node_pos(view, n)
		var open: bool = n.get("map") != null
		var city := bool(n.get("city", false))
		var col := Color(0.95, 0.8, 0.4) if open else Color(0.5, 0.48, 0.45)
		if city:
			view.draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), col)
			view.draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), Color(0.2, 0.1, 0.05), false, 1.5)
		else:
			view.draw_circle(p, 5, col)
		if String(n.id) == here:
			view.draw_arc(p, 12, 0, TAU, 24, Color(1, 0.95, 0.3), 2.0)
		view.draw_string(font, p + Vector2(10, 5), String(n.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE if open else Color(0.65, 0.62, 0.58))


# 自己所在節點: 洞窟各層都算汝南山洞；室內 (house) 算所屬城池 (parent)
func _here_node() -> String:
	var mid := String(main.cur_map.get("parent", main.cur_map.get("id", "")))
	for n in main.data.world_map.get("nodes", []):
		var m = n.get("map")
		if m != null and (String(m) == mid or (mid.begins_with("runan_f") and String(m).begins_with("runan_f"))):
			return String(n.id)
	return ""


func _world_tap(view: Control, ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	for n in main.data.world_map.get("nodes", []):
		if _node_pos(view, n).distance_to(ev.position) <= 18:
			var open: bool = n.get("map") != null
			select_node(String(n.id))
			return


# 揀節點: 顯示說明；已開放又唔喺度 = 可以自動前往
func select_node(node_id: String) -> void:
	for n in main.data.world_map.get("nodes", []):
		if String(n.id) != node_id:
			continue
		var open: bool = n.get("map") != null
		var here := String(n.id) == _here_node()
		var md: Dictionary = main.data.map_by_id.get(String(n.map), {}) if open else {}
		_info = "%s（%s）— %s" % [n.name, n.province, ("而家喺度" if here else String(md.get("name", ""))) if open else "未開放"]
		if open:
			_info += _lv_text(String(n.map))
		_sel_map = String(n.map) if open and not here else ""
		refresh(true)


# 地圖怪物等級範圍 (洞窟當汝南成條計)；冇怪 = 安全
func _lv_text(map_id: String) -> String:
	var lo := 999
	var hi := 0
	for sp in main.data.spawns:
		var z := String(sp["zone"])
		if z == map_id or (map_id.begins_with("runan_f") and z.begins_with("runan_f")):
			var lv := int(main.data.monsters[int(sp["monster"])]["level"])
			lo = mini(lo, lv)
			hi = maxi(hi, lv)
	return "　（安全）" if hi == 0 else "　怪物 Lv%d~%d" % [lo, hi]


func goto_sel() -> void:
	if _sel_map == "":
		return
	main._send({"t": "goto_map", "map": _sel_map})
	_sel_map = ""
	_info = ""
	main.hud.close_panels()
