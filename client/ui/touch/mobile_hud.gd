class_name MobileHud
extends Control
# 手機操控層（三國群英傳M 風格）。版面由 HudLayout 計（畫 + 判定共用，有測試）:
#   左上角色框（撳 = 角色面板）+ 日誌；右上選單列 背包/角色/記事/更多 + 區名/時辰
#   左下浮動搖桿；右下 普攻大圓 + 技能扇形 + 切換目標 + 自動 + 互動掣（行近 NPC/商店先出）
# 手感: 撳住高亮 + 震動；戰鬥掣一撳即發、按住普攻連打；選單/互動掣放手先發（滑走 = 取消）
# 正式面板 (ui/panels/) 開住時 HUD 唔路由 input，交俾 Control 處理（可以拖捲）。
# 桌面用滑鼠模擬: 左鍵拖左下 = 搖桿，點怪 = 攻擊，右鍵 = 自動。

signal attack_pressed
signal auto_toggled(on: bool)
signal target_cycle
signal skill_pressed(slot: Dictionary)
signal context_pressed(act: Dictionary)
signal create_done                        # 建角面板完成 (Step 8)

const COMBAT_IDS := ["attack", "skill0", "skill1", "skill2", "skill3", "target", "auto"]
const ATK_REPEAT := 0.45                  # 按住普攻: 每幾秒再發一次
const MOUSE_IDX := -99

var main: Node2D           # 引用 main.gd: 讀 ch/ents/faces/log_lines
var joy: SangoJoystick
var auto := false
var use_touch := false     # 最近用緊觸控（收到 ScreenTouch 就 true；真滑鼠就 false）: 震動/提示用
var vibrate_on := true
var _t := 0.0              # 開場提示計時
var layout: Dictionary = {}
var ctx: Dictionary = {}   # 目前互動掣動作 (ContextActions.find)
var _ctx_t := 0.0
var pressed := {}          # touch index -> 撳緊嘅元件 id
var _atk_idx := -1000      # 按住普攻嘅 touch index（-1000 = 冇）
var _atk_t := 0.0
var panels := {}           # name -> GamePanel（第一次用先起）
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
	joy = SangoJoystick.new()
	joy.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(joy)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relayout()

func set_auto(v: bool) -> void:
	auto = v
	queue_redraw()

func joy_active() -> bool:
	return joy != null and joy.active

func joy_dir() -> Vector2:
	return joy.get_direction() if joy != null else Vector2.ZERO

func haptic() -> void:
	if vibrate_on and use_touch:
		Input.vibrate_handheld(12)

# 瀏海/圓角安全區（viewport 虛擬 px）。桌面 = 成個 viewport
func safe_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var full := Rect2(Vector2.ZERO, vs)
	if not OS.has_feature("mobile"):
		return full
	var ws := Vector2(DisplayServer.window_get_size())
	if ws.x <= 0 or ws.y <= 0:
		return full
	var sa := DisplayServer.get_display_safe_area()
	var k := vs / ws
	var r := Rect2(Vector2(sa.position) * k, Vector2(sa.size) * k).intersection(full)
	return r if r.size.x > vs.x * 0.6 and r.size.y > vs.y * 0.6 else full

func _relayout() -> void:
	var s := get_viewport_rect().size
	var sr := safe_rect()
	layout = HudLayout.build(s, sr)
	if joy != null:
		joy.zone = HudLayout.joy_zone(s, sr)

# ================= 面板 =================
func _panel(name_: String) -> GamePanel:
	if not panels.has(name_):
		var p: GamePanel
		match name_:
			"bag": p = BagPanel.new(main)
			"shop": p = ShopPanel.new(main)
			"char": p = CharPanel.new(main)
			"quest": p = QuestPanel.new(main)
			"more": p = MorePanel.new(main)
			"map": p = MapPanel.new(main)
			_: p = DialogPanel.new(main)
		add_child(p)
		panels[name_] = p
	return panels[name_]

func bag_panel() -> BagPanel:
	return _panel("bag") as BagPanel

func shop_panel() -> ShopPanel:
	close_panels()
	return _panel("shop") as ShopPanel

func open_panel(name_: String) -> void:
	close_panels()
	_panel(name_).open()

func open_dialog(src: Callable) -> void:
	close_panels()
	(_panel("dialog") as DialogPanel).open_with(src)

func close_panels() -> void:
	for k in panels:
		(panels[k] as GamePanel).close()

func any_panel_open() -> bool:
	for k in panels:
		if (panels[k] as GamePanel).visible:
			return true
	return false

# ================= 輸入 =================
func _process(delta: float) -> void:
	_t += delta
	_relayout()
	_ctx_t += delta
	if _ctx_t >= 0.2 and main != null and not creation_mode:
		_ctx_t = 0.0
		ctx = ContextActions.find(main)
	if _atk_idx != -1000:
		_atk_t += delta
		if _atk_t >= ATK_REPEAT:
			_atk_t = 0.0
			attack_pressed.emit()
	queue_redraw()

# 顯示緊嘅元件（次序 = 判定優先）
func visible_ids() -> Array:
	var ids: Array = []
	if not ctx.is_empty():
		ids.append("context")
	ids.append("attack")
	var slots := skill_slots()
	for i in slots.size():
		ids.append("skill%d" % i)
	ids.append_array(["target", "auto"])
	ids.append_array(HudLayout.MENU)
	ids.append("minimap")
	ids.append("portrait")
	return ids

func _input(ev: InputEvent) -> void:
	if creation_mode:
		_handle_create_input(ev)
		return
	if any_panel_open():
		if ev.is_action_pressed("ui_cancel"):
			close_panels()
			get_viewport().set_input_as_handled()
		return                                   # 面板自己食 input
	var idx := MOUSE_IDX
	var pos := Vector2.ZERO
	var is_press := false
	var is_release := false
	if ev is InputEventMouse and ev.device == InputEvent.DEVICE_ID_EMULATION:
		return                                   # 觸控模擬出嚟嘅 mouse: 已經由 ScreenTouch 處理
	if ev is InputEventScreenTouch:
		use_touch = true
		idx = ev.index
		pos = ev.position
		is_press = ev.pressed
		is_release = not ev.pressed
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		use_touch = false
		pos = ev.position
		is_press = ev.pressed
		is_release = not ev.pressed
	if is_press:
		var id := HudLayout.hit(layout, visible_ids(), pos)
		if id != "":
			pressed[idx] = id
			haptic()
			if id in COMBAT_IDS:
				_fire(id)
				if id == "attack":
					_atk_idx = idx
					_atk_t = 0.0
			get_viewport().set_input_as_handled()
			return
	elif is_release and pressed.has(idx):
		var id := String(pressed[idx])
		pressed.erase(idx)
		if idx == _atk_idx:
			_atk_idx = -1000
		if not (id in COMBAT_IDS) and HudLayout.hit(layout, [id], pos) == id:
			_fire(id)                              # 放手仍喺掣入面先算（滑走 = 取消）
		get_viewport().set_input_as_handled()
		return
	if joy.handle_event(ev):
		get_viewport().set_input_as_handled()

func _fire(id: String) -> void:
	match id:
		"attack": attack_pressed.emit()
		"target": target_cycle.emit()
		"auto":
			auto = not auto
			auto_toggled.emit(auto)
		"context":
			if not ctx.is_empty():
				context_pressed.emit(ctx)
		"menu_bag":
			close_panels()
			bag_panel().open_filter("")
		"menu_char", "portrait": open_panel("char")
		"menu_quest": open_panel("quest")
		"menu_more": open_panel("more")
		"minimap": open_panel("map")
		_:
			if id.begins_with("skill"):
				var slots := skill_slots()
				var i := int(id.trim_prefix("skill"))
				if i < slots.size():
					skill_pressed.emit(slots[i])
	queue_redraw()

# 技能扇形內容: 術書 3 格（職業用得術法先有）+ 絕招 1 格（職業有絕招先有）
func skill_slots() -> Array:
	var out: Array = []
	if main == null or main.ch.is_empty():
		return out
	var ch: Dictionary = main.ch
	var d: GameData = main.data
	var tick: int = main.sim.tick
	if main.class_has_spells():
		var books: Array = ch.get("equip", {}).get("spellbooks", [0, 0, 0])
		var cs: Dictionary = main.sim.ent(main.my_id).get("casting", {})
		for i in 3:
			var item := int(books[i])
			var def: Dictionary = d.spell_by_item.get(item, {})
			var ready := item > 0 and int(ch["mp"]) >= int(def.get("mp", 0)) and int(ch["level"]) >= int(def.get("lv", 1))
			out.append({"kind": "spell", "slot": i, "item": item,
				"label": str(def.get("name", "")).substr(0, 2) if item > 0 else "＋",
				"sub": "MP%d" % int(def.get("mp", 0)) if item > 0 else "術書",
				"ready": ready, "cd": 0.0, "casting": not cs.is_empty() and int(cs.get("slot", -1)) == i})
	if main.class_has_ults():
		var ults: Array = ch.get("ultimates", [])
		if ults.is_empty():
			out.append({"kind": "ult", "ult": "", "label": "絕", "sub": "未學", "ready": false, "cd": 0.0, "casting": false})
		else:
			var uid := str(ults[ults.size() - 1])
			var u: Dictionary = d.ult_by_id.get(uid, {})
			var left := int(ch.get("ultCd", {}).get(uid, 0)) - tick
			var ready := left <= 0 and int(ch["mp"]) >= int(u.get("mp", 0)) and int(ch["sp"]) >= int(u.get("sp", 0))
			out.append({"kind": "ult", "ult": uid, "label": str(u.get("name", "絕")).substr(0, 2), "sub": "絕招",
				"ready": ready, "cd": clampf(float(left) / maxf(1.0, float(u.get("cd", 1))), 0.0, 1.0), "casting": false})
	return out.slice(0, HudLayout.SKILL_ANGLES.size())

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
	if ev is InputEventMouse and ev.device == InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()    # 觸控模擬 mouse: 唔好一撳觸發兩次
		return
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
	var sr := safe_rect()
	_draw_status()
	_draw_log(sr)
	_draw_target(s)
	_draw_info(sr)
	_draw_menu()
	_draw_combat()
	if _t < 12.0:                       # 開場提示，12 秒後淡出
		_txt(Vector2(sr.position.x + 10, sr.end.y - 8), "拖左下移動 · 點怪攻擊 · 點地行路 · 按住普攻連打", Color(1, 1, 1, 0.6), 11)

func _is_down(id: String) -> bool:
	return pressed.values().has(id)

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
	var fr: Rect2 = layout["portrait"]["rect"]
	var o := fr.position
	draw_rect(fr, Color(0, 0, 0, 0.7 if _is_down("portrait") else 0.55))
	draw_rect(fr, Color(1, 1, 1, 0.3), false, 1.0)
	# 頭像
	var pr := Rect2(o + Vector2(6, 6), Vector2(64, 64))
	draw_rect(pr, Color(0, 0, 0, 0.4))
	var me = main._me()
	if me != null:
		var faces: Array = main.faces
		if faces.size() > 0:
			var f = faces[int(me.face) % faces.size()]
			if f != null:
				draw_texture_rect(f, pr, true)
	draw_rect(pr, Color(1, 1, 1, 0.35), false, 1.0)
	_txt(o + Vector2(78, 15), "%s  Lv%d" % [main.ch.name, lv], Color.WHITE, 13)
	_txt(o + Vector2(78, 29), "%s" % RulesKarma.tier_name(int(ch.karma)), Color(1, 0.85, 0.4), 11)
	var rows := [["HP", float(ch.hp) / mhp, Color(0.85, 0.2, 0.2)], ["MP", float(ch.mp) / mmp, Color(0.25, 0.45, 0.95)],
		["SP", float(ch.sp) / msp, Color(0.9, 0.8, 0.2)], ["EXP", float(ch.exp) / maxi(1, need), Color(0.7, 0.4, 0.95)]]
	for i in rows.size():
		var y := o.y + 36 + 13 * i
		_txt(Vector2(o.x + 78, y + 9), rows[i][0], Color(0.95, 0.95, 0.95), 11)
		_bar(o.x + 114, y + 1, 124, 8, rows[i][1], rows[i][2])
	_txt(o + Vector2(6, 92), "金 %d" % int(ch.gold), Color(1, 0.9, 0.5), 11)

# 頂中目標框（揀咗怪先有）
func _draw_target(s: Vector2) -> void:
	var t = main.target_ent()
	if t == null:
		return
	var w := 190.0
	var r := Rect2(s.x / 2 - w / 2, 4, w, 36)
	draw_rect(r, Color(0, 0, 0, 0.6))
	draw_rect(r, Color(0.9, 0.35, 0.2), false, 1.5)
	var max_hp := maxi(1, int(t.maxHp))
	_txt(Vector2(r.position.x + 8, r.position.y + 15), "%s  Lv%d" % [t.name, int(t.level)], Color(1, 0.8, 0.7), 12)
	_bar(r.position.x + 8, r.position.y + 25, w - 16, 6, float(t.hp) / max_hp, Color(0.9, 0.25, 0.15))

# 右上小地圖: 當前地圖縮圖 (以自己為中心) + 怪/NPC/自己點 + 區名/時辰 (spec 12 §6)
func _draw_info(_sr: Rect2) -> void:
	var r: Rect2 = layout["minimap"]["rect"]
	draw_rect(r, Color(0, 0, 0, 0.75 if _is_down("minimap") else 0.6))
	var me = main._me()
	var md: Dictionary = main.cur_map
	if me != null and not md.is_empty():
		const K := 2.0                              # 每格 2px
		var inner := r.grow(-2)
		var view := inner.size / K                  # 睇到幾多格
		var mx := float(me.x) - float(md.ox)
		var my := float(me.y) - float(md.oy)
		var src := Rect2(Vector2(clampf(mx - view.x / 2, 0, maxf(0, float(md.w) - view.x)), clampf(my - view.y / 2, 0, maxf(0, float(md.h) - view.y))), view)
		src.size = src.size.min(Vector2(float(md.w), float(md.h)) - src.position)
		var dst := Rect2(inner.position, src.size * K)
		draw_texture_rect_region(MapArt.minimap(main.data, md), dst, src, Color(1, 1, 1, 0.9))
		var org := inner.position - src.position * K
		for e in main.ents:
			var p := org + (Vector2(float(e.x) - float(md.ox), float(e.y) - float(md.oy)) + Vector2(0.5, 0.5)) * K
			if not dst.has_point(p) or int(e.id) == main.my_id:
				continue
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(0.95, 0.25, 0.2) if e.get("mob", false) else Color(0.9, 0.9, 0.9))
		for qn in main.quest_npcs:
			var q := org + (Vector2(float(qn.x) - float(md.ox), float(qn.y) - float(md.oy)) + Vector2(0.5, 0.5)) * K
			if dst.has_point(q):
				draw_rect(Rect2(q - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.4, 0.75, 1.0))
		for f in main.facilities:
			if String(f.kind) == "travel":
				var tp := org + (Vector2(float(f.x) - float(md.ox), float(f.y) - float(md.oy)) + Vector2(0.5, 0.5)) * K
				if dst.has_point(tp):
					draw_circle(tp, 2.5, Color(0.5, 1.0, 0.4))
		draw_circle(org + (Vector2(mx, my) + Vector2(0.5, 0.5)) * K, 2.5, Color(1, 0.9, 0.2))
		var zv: Dictionary = main.sim.zone_view(int(me.x), int(me.y))
		var nm := str(zv.get("area", "")) if str(zv.get("area", "")) != "" else str(zv.get("name", ""))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 14)), Color(0, 0, 0, 0.55))
		_txt_right(Vector2(r.end.x - 4, r.position.y + 11), nm, Color(0.95, 0.88, 0.7), 11)
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - 13), Vector2(r.size.x, 13)), Color(0, 0, 0, 0.55))
	_txt_right(Vector2(r.end.x - 4, r.end.y - 3), ("夜 " if main.night_on else "") + str(main.clock_str), Color(1, 0.95, 0.65), 10)
	draw_rect(r, UiTheme.GOLD if _is_down("minimap") else Color(1, 1, 1, 0.35), false, 1.0)

func _draw_menu() -> void:
	for id in HudLayout.MENU:
		var r: Rect2 = layout[id]["rect"]
		var down := _is_down(id)
		draw_rect(r, Color(0.3, 0.22, 0.12, 0.95) if down else Color(0.12, 0.1, 0.08, 0.85))
		draw_rect(r, UiTheme.GOLD, false, 1.5)
		_txt_center(r.position.y + r.size.y / 2 + 5, String(HudLayout.MENU_LABELS[id]), Color.WHITE, 14, r.size.x, r.position.x)
	# 有未分配點數: 角色掣紅點
	if int(main.ch.get("attrPoints", 0)) > 0:
		var cr: Rect2 = layout["menu_char"]["rect"]
		draw_circle(cr.position + Vector2(cr.size.x - 4, 4), 6, Color(0.95, 0.2, 0.15))

func _circle_btn(id: String, fill: Color, ring: Color, ring_w := 2.5) -> void:
	var el: Dictionary = layout[id]
	var c: Vector2 = el["c"]
	var r := float(el["r"]) * (0.93 if _is_down(id) else 1.0)
	draw_circle(c, r, fill.lightened(0.25) if _is_down(id) else fill)
	draw_arc(c, r, 0, TAU, 64, ring, ring_w)

func _draw_combat() -> void:
	# 普攻
	var ac: Vector2 = layout["attack"]["c"]
	_circle_btn("attack", Color(0.12, 0.12, 0.12, 0.8), Color(0.95, 0.35, 0.25), 3.5)
	_txt_center(ac.y + 7, "攻擊", Color.WHITE, 20, 80, ac.x - 40)
	if _atk_idx != -1000:                              # 按住連打: 外圈轉
		var a := fmod(_t * 6.0, TAU)
		draw_arc(ac, HudLayout.ATK_R + 5, a, a + 1.6, 24, Color(1, 0.8, 0.3, 0.9), 3.0)
	# 技能扇形
	var slots := skill_slots()
	for i in slots.size():
		var sl: Dictionary = slots[i]
		var id := "skill%d" % i
		var c: Vector2 = layout[id]["c"]
		var r := HudLayout.SKILL_R
		var ult := String(sl["kind"]) == "ult"
		var ring := Color(1, 0.55, 0.25) if ult else Color(0.75, 0.55, 0.95)
		_circle_btn(id, Color(0.1, 0.1, 0.16, 0.85), ring if bool(sl["ready"]) else Color(0.45, 0.45, 0.45))
		if float(sl["cd"]) > 0.0:                       # 冷卻: 扇形遮罩
			_draw_sector(c, r - 2, float(sl["cd"]), Color(0, 0, 0, 0.6))
		if bool(sl["casting"]):
			var a2 := fmod(_t * 8.0, TAU)
			draw_arc(c, r + 3, a2, a2 + 2.2, 24, Color(0.9, 0.7, 1.0), 3.0)
		var tc := Color.WHITE if bool(sl["ready"]) else Color(0.65, 0.65, 0.65)
		_txt_center(c.y + 2, String(sl["label"]), tc, 14, r * 2, c.x - r)
		_txt_center(c.y + 15, String(sl["sub"]), Color(0.8, 0.8, 0.9), 10, r * 2, c.x - r)
	# 切換目標 / 自動
	var tcn: Vector2 = layout["target"]["c"]
	_circle_btn("target", Color(0.12, 0.12, 0.12, 0.8), Color(1, 1, 1, 0.7))
	_txt_center(tcn.y + 5, "換目標", Color.WHITE, 11, 44, tcn.x - 22)
	var ab: Vector2 = layout["auto"]["c"]
	_circle_btn("auto", Color(0.9, 0.18, 0.1, 0.75) if auto else Color(0.12, 0.12, 0.12, 0.8), Color(1, 0.85, 0.3) if auto else Color(1, 1, 1, 0.7))
	_txt_center(ab.y + 5, "自動", Color.WHITE, 13, 44, ab.x - 22)
	# 互動掣（行近先出）
	if not ctx.is_empty():
		var cr: Rect2 = layout["context"]["rect"]
		var pulse := 0.6 + 0.4 * sin(_t * 4.0)
		draw_rect(cr, Color(0.35, 0.25, 0.1, 0.95) if _is_down("context") else Color(0.18, 0.13, 0.07, 0.9))
		draw_rect(cr, Color(1, 0.85, 0.4, pulse), false, 2.5)
		_txt_center(cr.position.y + cr.size.y / 2 + 6, String(ctx["label"]), Color(1, 0.95, 0.75), 17, cr.size.x, cr.position.x)

func _draw_sector(c: Vector2, r: float, frac: float, col: Color) -> void:
	var pts := PackedVector2Array([c])
	var n := maxi(3, int(32 * frac))
	for k in n + 1:
		var a := -PI / 2 + TAU * frac * float(k) / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)

# 日誌（最後 3 行，角色框下面，唔撳得）
func _draw_log(sr: Rect2) -> void:
	var lines: Array = main.log_lines
	var n := lines.size()
	if n == 0:
		return
	var show: Array = lines.slice(maxi(0, n - 3))
	var r := HudLayout.log_rect(sr)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 14 * show.size() + 4)), Color(0, 0, 0, 0.35))
	for i in show.size():
		var t := str(show[i])
		if t.length() > 26:
			t = t.substr(0, 25) + "…"
		_txt(r.position + Vector2(4, 13 + 14 * i), t, Color(1, 1, 0.75), 11)

# ================= 小工具 (同 main.gd 一致) =================
func _bar(x: float, y: float, w: float, h: float, ratio: float, col: Color) -> void:
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(x, y, w * clampf(ratio, 0.0, 1.0), h), col)

func _txt(pos: Vector2, str_: String, col := Color.WHITE, sz := 12) -> void:
	draw_string(ThemeDB.fallback_font, pos, str_, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _txt_right(pos: Vector2, str_: String, col := Color.WHITE, sz := 12) -> void:
	var w := ThemeDB.fallback_font.get_string_size(str_, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(ThemeDB.fallback_font, pos - Vector2(w, 0), str_, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _txt_center(y: float, str_: String, col: Color, sz: int, w: float, x: float) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(x, y), str_, HORIZONTAL_ALIGNMENT_CENTER, w, sz, col)
