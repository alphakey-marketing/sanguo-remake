class_name MapPanel
extends GamePanel
# 地圖面板 (spec 12 §6)。撳小地圖開。
#   區域: 當前地圖全圖 + 地標/門口/設施/任務 NPC/自己；已到過嘅地標有名，未到過 = 「？」
#   天下: 豫州荊州城池節點 + 路線；自己所在發光；未開放 = 灰 (B3 開)；撳已開放節點 →「自動前往」(sim.cmd_goto_map)

var _info := ""                  # 天下頁: 撳咗邊個節點嘅說明
var _sel_map := ""               # 天下頁: 撳咗嘅已開放節點對應地圖 ("" = 冇 / 而家喺度)
var _wz := 2.0                   # 天下頁縮放 (1=塞滿畫面；預設 2 倍，節點唔擠)
var _wpan := Vector2.ZERO        # 天下頁平移 (px)
var _wdrag := false              # 拖動中
var _wmoved := 0.0               # 今次按下後移動距離 (分 tap / 拖)
var _wcentered := false          # 開頁後first次對準自己位置


func _init(m: Node) -> void:
	super(m)
	title_lbl.text = "地圖"
	set_tabs(["區域", "天下", "市價"])


func sig() -> String:
	var me = main._me()
	return JSON.stringify([tab, _info, _sel_map, main.cur_map.get("id", ""), int(me.x) if me != null else 0, int(me.y) if me != null else 0, main.sim.view_market_prices()])


func _build_body() -> void:
	if tab == 2:
		_build_prices()
		return
	var view := Control.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(view)
	if tab == 0:
		view.draw.connect(func() -> void: _draw_area(view))
		view.gui_input.connect(func(ev: InputEvent) -> void: _area_input(view, ev))
	else:
		view.draw.connect(func() -> void: _draw_world(view))
		view.gui_input.connect(func(ev: InputEvent) -> void: _world_input(view, ev))
		view.clip_contents = true
		var row := HBoxContainer.new()
		row.add_child(btn("＋", func() -> void: _zoom_world(view, 1.4), 56))
		row.add_child(btn("－", func() -> void: _zoom_world(view, 1.0 / 1.4), 56))
		row.add_child(btn("定位", func() -> void: _center_here(view), 72))
		row.add_child(wrap_lbl(_info if _info != "" else "撳城池睇詳情。灰色 = 未開放（之後版本開通）", 13, UiTheme.DIM))
		if _sel_map != "":
			row.add_child(btn("自動前往", func() -> void: goto_sel(), 120))
		body.add_child(row)


# ---- 市價 (spec 05 §6【自訂】): 各城代表物資現時市價，睇城際價差 ----
func _build_prices() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	col.add_child(wrap_lbl("各城代表物資市價（因供需/天災浮動 0.5~2.0 倍）：", 13, UiTheme.DIM))
	for row in main.sim.view_market_prices():
		var box := VBoxContainer.new()
		box.add_child(wrap_lbl(String(row["name"]), 15, UiTheme.GOLD))
		var line := ""
		for it in (row["items"] as Array):
			line += "%s %d金　" % [String(it["name"]), int(it["price"])]
		box.add_child(wrap_lbl(line, 13, Color.WHITE))
		col.add_child(box)
		col.add_child(HSeparator.new())


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
	var me0 = main._me()
	if me0 != null:                 # 工作區地圖: 標題寫明可做咩
		var ws: Array = main.sim.work_area_skills(int(me0.x), int(me0.y))
		if not ws.is_empty():
			var wn: Array = []
			for sk in ws:
				wn.append(str(main.data.work[sk]["name"]))
			view.draw_string(font, Vector2(8, 16), "工作區：" + "／".join(wn), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 1, 0.6))
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
	view.draw_string(font, off + Vector2(4, 16), String(md.name) + "　（撳任何位置自動行過去）", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.GOLD)


# 撳區域圖任何一格 → 自動尋路行過去 (A*, sim 處理)；撳中障礙行去最近可行格
func _area_input(view: Control, ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	var md: Dictionary = main.cur_map
	if md.is_empty():
		return
	var f := _fit(view, md)
	var k: float = f[0]
	var rel: Vector2 = (ev.position - (f[1] as Vector2)) / k
	if rel.x < 0 or rel.y < 0 or rel.x >= float(md.w) or rel.y >= float(md.h):
		return
	var tx := int(md.ox) + int(rel.x)
	var ty := int(md.oy) + int(rel.y)
	if not main.sim.is_free(tx, ty):
		var fr: Vector2i = main._free_near(Vector2i(tx, ty), 4)
		if fr.x < 0:
			return
		tx = fr.x
		ty = fr.y
	main._send({"t": "move", "x": tx, "y": ty})
	main.marker = {"pos": Vector2(tx, ty), "t": 1.0}
	main.hud.close_panels()


# ---- 天下 ----
func _node_pos(view: Control, n: Dictionary) -> Vector2:
	var pad := Vector2(40, 16)
	return (pad + Vector2(float(n.x), float(n.y)) * (view.size - pad * 2)) * _wz + _wpan


func _clamp_pan(view: Control) -> void:
	var lo := view.size - view.size * _wz
	_wpan = Vector2(clampf(_wpan.x, minf(lo.x, 0.0), 0.0), clampf(_wpan.y, minf(lo.y, 0.0), 0.0))


func _zoom_world(view: Control, f: float, at := Vector2(-1, -1)) -> void:
	var c := view.size / 2.0 if at.x < 0 else at
	var nz := clampf(_wz * f, 1.0, 4.0)
	_wpan = c - (c - _wpan) * (nz / _wz)
	_wz = nz
	_clamp_pan(view)
	view.queue_redraw()


func _center_here(view: Control) -> void:
	var hn := _here_node()
	for n in main.data.world_map.get("nodes", []):
		if String(n.id) == hn:
			_wpan = Vector2.ZERO
			_wpan = view.size / 2.0 - _node_pos(view, n)
			break
	_clamp_pan(view)
	view.queue_redraw()


func _draw_world(view: Control) -> void:
	var w: Dictionary = main.data.world_map
	if w.is_empty():
		return
	if not _wcentered:
		_wcentered = true
		_center_here(view)
	var font := ThemeDB.fallback_font
	var nodes := {}
	for n in w["nodes"]:
		nodes[String(n.id)] = n
	# 州界示意: 上半豫州、下半荊州
	view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(0.18, 0.15, 0.1, 0.6))
	view.draw_string(font, Vector2(view.size.x - 60, 20), "豫州", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.7, 0.5, 0.6))
	view.draw_string(font, Vector2(view.size.x - 60, view.size.y - 10), "荊州", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.7, 0.5, 0.6))
	# 戰役窗口標示 (S04c): 而家開緊邊場戰役 (許昌北門義勇士兵入場) + 入場進度
	var vb: Dictionary = main.sim.view_battles(main.my_id)
	var bcol := Color(0.95, 0.75, 0.45)
	var btxt := "戰役：而家冇窗口開緊（每場時辰窗口重開）"
	if bool(vb["inBattle"]):
		btxt = "戰役：喺 %s 第 %d/%d 層（許昌北門義勇士兵）" % [vb["battleName"], int(vb["floor"]), int(vb["totalFloors"])]
		bcol = Color(1, 0.9, 0.4)
	elif not String(vb["open"]).is_empty():
		for bb in vb["list"]:
			if bool(bb["open"]):
				btxt = "戰役：%s 開緊（武≤%d）" % [bb["name"], int(bb["maxLevel"])]
				break
	view.draw_rect(Rect2(Vector2(10, 8), Vector2(230, 26)), Color(0.12, 0.1, 0.07, 0.85))
	view.draw_string(font, Vector2(16, 24), btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, bcol)
	# 特殊場景標示 (S04d): 而家開住邊啲場景入口 (荊州港口)
	var vs: Dictionary = main.sim.view_scenes(main.my_id)
	var scols := Color(0.7, 0.85, 0.55)
	var stxt := "特殊場景：而家冇開門…"
	var sopen: Array = []
	for s in vs["list"]:
		if bool(s["open"]):
			sopen.append(str(s["name"]))
	if bool(vs["inScene"]):
		stxt = "特殊場景：喺 %s 第 %d/%d 層" % [str(vs.get("sceneName", "")), int(vs.get("layer", 0)), int(vs.get("totalLayers", 0))]
		scols = Color(0.8, 0.95, 0.6)
	elif not sopen.is_empty():
		stxt = "特殊場景：%s 開緊（荊州港口）" % "、".join(sopen)
		scols = Color(0.8, 0.95, 0.6)
	view.draw_rect(Rect2(Vector2(10, 36), Vector2(230, 26)), Color(0.1, 0.12, 0.09, 0.85))
	view.draw_string(font, Vector2(16, 52), stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, scols)
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
		view.draw_string(font, p + Vector2(10, 5), String(n.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE if open else Color(0.65, 0.62, 0.58))


# 自己所在節點: 洞窟各層都算汝南山洞；室內 (house) 算所屬城池 (parent)
func _here_node() -> String:
	var mid := String(main.cur_map.get("parent", main.cur_map.get("id", "")))
	for n in main.data.world_map.get("nodes", []):
		var m = n.get("map")
		if m != null and (String(m) == mid or (mid.begins_with("runan_f") and String(m).begins_with("runan_f"))):
			return String(n.id)
	return ""


func _world_input(view: Control, ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			_zoom_world(view, 1.2, ev.position)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			_zoom_world(view, 1.0 / 1.2, ev.position)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_wdrag = true
				_wmoved = 0.0
			else:
				_wdrag = false
				if _wmoved < 10.0:
					_world_tap(view, ev.position)
	elif ev is InputEventMouseMotion and _wdrag:
		_wmoved += ev.relative.length()
		_wpan += ev.relative
		_clamp_pan(view)
		view.queue_redraw()


func _world_tap(view: Control, pos: Vector2) -> void:
	var best := ""
	var bd := 28.0                      # 手指粗: 容差大啲，揀最近
	for n in main.data.world_map.get("nodes", []):
		var d := _node_pos(view, n).distance_to(pos)
		if d <= bd:
			bd = d
			best = String(n.id)
	if best != "":
		select_node(best)


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
