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

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)   # size 跟 viewport，唔係 0

func setup(m: Node2D) -> void:
	main = m
	joy = SangoJoystick.new()
	joy.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(joy)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_relayout)   # 版面只喺 viewport 變大細先重計
	_relayout()
	sim_refreshed()

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
	var pslots := HudLayout.potion_slots(s, sr)
	for k in pslots:
		layout[k] = pslots[k]
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
			"craft": p = CraftPanel.new(main)
			"recruit": p = RecruitPanel.new(main)
			"mount": p = MountPanel.new(main)
			"war_beast": p = WarBeastPanel.new(main)
			"office": p = OfficePanel.new(main)
			"militia": p = MilitiaPanel.new(main)
			"camp": p = CampPanel.new(main)
			"civic": p = CivicPanel.new(main)
			"llm": p = LlmPanel.new(main)
			"marriage": p = MarriagePanel.new(main)
			"drop": p = DropPanel.new(main)
			"create": p = CreatePanel.new(main)
			"title": p = TitlePanel.new(main)
			"auto_setup": p = AutoPanel.new(main)
			"potion_setup": p = PotionSetupPanel.new(main)
			"unlock": p = UnlockPanel.new(main)
			"stealth": p = StealthPanel.new(main)
			"rumor": p = RumorPanel.new(main)
			_: p = DialogPanel.new(main)
		add_child(p)
		panels[name_] = p
	return panels[name_]

func bag_panel() -> BagPanel:
	return _panel("bag") as BagPanel

func shop_panel() -> ShopPanel:
	close_panels()
	return _panel("shop") as ShopPanel

func craft_panel() -> CraftPanel:
	close_panels()
	return _panel("craft") as CraftPanel

func mount_panel() -> MountPanel:
	close_panels()
	return _panel("mount") as MountPanel

func war_beast_panel() -> WarBeastPanel:
	close_panels()
	return _panel("war_beast") as WarBeastPanel

func office_panel() -> OfficePanel:
	close_panels()
	return _panel("office") as OfficePanel

func militia_panel() -> MilitiaPanel:
	close_panels()
	return _panel("militia") as MilitiaPanel

func camp_panel() -> CampPanel:
	close_panels()
	return _panel("camp") as CampPanel

func civic_panel() -> CivicPanel:
	close_panels()
	return _panel("civic") as CivicPanel

func llm_panel() -> LlmPanel:
	close_panels()
	return _panel("llm") as LlmPanel

func marriage_panel() -> MarriagePanel:
	close_panels()
	return _panel("marriage") as MarriagePanel

func drop_panel() -> DropPanel:
	close_panels()
	return _panel("drop") as DropPanel

func open_panel(name_: String) -> void:
	close_panels()
	_panel(name_).open()

# 撳空快捷補品格：直接彈快捷欄設定面板，並揀定嗰一格等揀補品
func open_potion_setup(slot: int) -> void:
	close_panels()
	var p := _panel("potion_setup") as PotionSetupPanel
	p.editing_slot = slot
	p.open()

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
	_ctx_t += delta
	if _ctx_t >= 0.2 and main != null:
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
	for i in HudLayout.POTION_SLOTS:
		ids.append("potion%d" % i)
	ids.append_array(HudLayout.MENU)
	ids.append("minimap")
	ids.append("portrait")
	if main != null and not main.comp.is_empty():
		ids.append("companion")
	if not mount_btn().is_empty():
		ids.append("mount")
	return ids

# main._refresh 每 tick 叫: 技能扇形 / 騎馬掣狀態快取 (繪畫每幀讀，唔使每幀重計)
var _slots_cache: Array = []
var _mount_cache: Dictionary = {}

func sim_refreshed() -> void:
	_slots_cache = _calc_skill_slots()
	_mount_cache = _calc_mount_btn()


func mount_btn() -> Dictionary:
	return _mount_cache


# 騎馬掣狀態 (Step 17a): 身邊有座騎 (唔計放牧中) 先有；{} = 唔顯示
func _calc_mount_btn() -> Dictionary:
	if main == null or main.ch.is_empty():
		return {}
	for m in main.ch.get("mounts", []):
		if String(m["where"]) == "with":
			var riding := bool(main.ch.get("riding", false))
			return {"riding": riding, "ok": riding or RulesMount.ride_why(main.data.mounts, m) == ""}
	return {}

func _input(ev: InputEvent) -> void:
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
			if auto:
				auto = false
				auto_toggled.emit(false)
			else:
				open_panel("auto_setup")     # 開自動之前，先揀邊種怪打 / 跨唔跨場景
		"potion0", "potion1", "potion2":
			var pslot := int(id.substr(6))
			if int(main.potion_slots[pslot]) == 0:
				open_potion_setup(pslot)          # 空格：直接彈揀補品，唔使行去背包
			else:
				main.use_potion(pslot)
		"context":
			if not ctx.is_empty():
				context_pressed.emit(ctx)
		"menu_bag":
			close_panels()
			bag_panel().open_filter("")
		"menu_char", "portrait": open_panel("char")
		"menu_quest": open_panel("quest")
		"menu_pk":
			main.pk_mode = not main.pk_mode
			main._log("打人模式 %s" % ("開" if main.pk_mode else "關"))
		"menu_more": open_panel("more")
		"minimap": open_panel("map")
		"companion": open_panel("recruit")
		"mount":
			var mb := mount_btn()
			if mb.is_empty():
				pass
			elif bool(mb["ok"]):
				main._send({"t": "mount_ride", "on": not bool(mb["riding"])})
			else:
				mount_panel().open_tab(0)           # 騎唔到 → 開座騎面板睇原因
		_:
			if id.begins_with("skill"):
				var slots := skill_slots()
				var i := int(id.trim_prefix("skill"))
				if i < slots.size():
					skill_pressed.emit(slots[i])
	queue_redraw()

func skill_slots() -> Array:
	return _slots_cache


# 技能扇形內容: 術書 3 格（職業用得術法先有）+ 絕招逐招一格（已學嘅全部）+ 職業特技 1 格（學咗先有）
func _calc_skill_slots() -> Array:
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
			for uidk in ults:                  # S02c: 已學絕招逐招一格（義士三招 = 絕招 3 格，唔只最後一招）
				var uid := str(uidk)
				var u: Dictionary = d.ult_by_id.get(uid, {})
				var left := int(ch.get("ultCd", {}).get(uid, 0)) - tick
				var ready := left <= 0 and int(ch["mp"]) >= int(u.get("mp", 0)) and int(ch["sp"]) >= int(u.get("sp", 0))
				out.append({"kind": "ult", "ult": uid, "label": str(u.get("name", "絕")).substr(0, 2), "sub": "絕招",
					"ready": ready, "cd": clampf(float(left) / maxf(1.0, float(u.get("cd", 1))), 0.0, 1.0), "casting": false})
	var sk := str(ch.get("classSkill", ""))
	if sk != "":                                # S02c: 職業特技掣（學咗先有；而家 = 開鎖）
		var sd: Dictionary = d.class_skills.get(sk, {})
		out.append({"kind": "skill", "skill": sk, "label": str(sd.get("name", "技")).substr(0, 2), "sub": "特技",
			"ready": bool(RulesClassSkill.can_use(d, ch, sk).get("ok", false)), "cd": 0.0, "casting": false})
	if bool(ch.get("riding", false)):            # U02: 馬戰特技掣（騎緊 + 已學）
		var wtype := ""
		var wid := str(ch.get("mountWeapon", ""))
		if wid != "":
			wtype = RulesMountBattle.weapon_type_of(d.mount_weapons, wid)
		var cd_map: Dictionary = ch.get("mountSkillCd", {})
		for skidk in ch.get("mountSkills", []):
			var skid := str(skidk)
			var s: Dictionary = RulesMountBattle.skill_def(d.mount_weapons, skid)
			if s.is_empty():
				continue
			var left := int(cd_map.get(skid, 0)) - tick
			var ready := left <= 0 and String(s["weapon"]) == wtype and int(ch["sp"]) >= int(s.get("sp", 0))
			out.append({"kind": "mount", "skill": skid, "label": str(s.get("name", "馬")).substr(0, 2), "sub": "馬戰",
				"ready": ready, "cd": clampf(float(left) / maxf(1.0, float(s.get("cd", 1))), 0.0, 1.0), "casting": false})
	return out.slice(0, HudLayout.skill_cap(int(ch["level"])))

# ================= 繪畫 =================
func _draw() -> void:
	if main == null:
		return
	var s := get_viewport_rect().size
	var sr := safe_rect()
	_draw_status()
	_draw_companion()
	_draw_log(sr)
	_draw_target(s)
	_draw_info()
	_draw_menu()
	_draw_combat()
	_draw_potions()
	if _t < 12.0:                       # 開場提示，12 秒後淡出
		_txt(Vector2(sr.position.x + 10, sr.end.y - 8), "拖左下移動 · 點怪攻擊 · 點地行路 · 按住普攻連打", Color(1, 1, 1, 0.6), 11)

func _is_down(id: String) -> bool:
	return pressed.values().has(id)

# 快捷補品欄 (U-fix): 搖桿上面 3 粒細圓，撳一下即用
func _draw_potions() -> void:
	if not layout.has("potion0"):
		return
	for i in HudLayout.POTION_SLOTS:
		var id := "potion%d" % i
		if not layout.has(id):
			continue
		var c: Vector2 = layout[id]["c"]
		var r := HudLayout.POTION_R
		var item_id := int(main.potion_slots[i]) if i < main.potion_slots.size() else 0
		var filled := item_id > 0
		_circle_btn(id, Color(0.12, 0.28, 0.14, 0.8) if filled else Color(0.12, 0.12, 0.12, 0.55),
			Color(0.55, 0.95, 0.55) if filled else Color(1, 1, 1, 0.4))
		var label: String = main.item_name_for_potion(item_id).substr(0, 3) if filled else "空"
		_txt_center(c.y + 4, label, Color.WHITE if filled else Color(0.7, 0.7, 0.7), 11, r * 2, c.x - r)

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
	_draw_status_icons(o, fr, main.sim.tick)

# 狀態 icon 列 (S02a, spec 02 §7): 角色框底部一行，短名 + 剩餘秒數
func _draw_status_icons(o: Vector2, fr: Rect2, tick: int) -> void:
	var me = main._ent(main.my_id)
	var status: Dictionary = {} if me == null else me.get("status", {})
	var y := fr.end.y - HudLayout.STATUS_ROW_H
	draw_line(Vector2(o.x + 2, y), Vector2(fr.end.x - 2, y), Color(1, 1, 1, 0.15), 1.0)
	var x := o.x + 6
	for sid in status.keys():
		var left := int(status[sid]) - tick
		if left <= 0:
			continue
		var label: String = main.STATUS_NAMES.get(str(sid), str(sid))
		var w := 8.0 * label.length() + 20.0
		draw_rect(Rect2(x, y + 2, w, 14), Color(0.5, 0.15, 0.55, 0.75))
		_txt(Vector2(x + 3, y + 13), "%s %ds" % [label, int(left / 10.0)], Color(1, 0.9, 1), 10)
		x += w + 4

# 同伴框 (Step 13.5): 頭像 + 名 + HP 條 + 忠誠/剩日/指令
func _draw_companion() -> void:
	var c: Dictionary = main.comp
	if c.is_empty():
		return
	var r: Rect2 = layout["companion"]["rect"]
	draw_rect(r, Color(0, 0, 0, 0.7 if _is_down("companion") else 0.55))
	draw_rect(r, Color(0.5, 0.95, 0.6, 0.6), false, 1.0)
	var pr := Rect2(r.position + Vector2(3, 3), Vector2(r.size.y - 6, r.size.y - 6))
	var faces: Array = main.faces
	if faces.size() > 0 and faces[int(c.face) % faces.size()] != null:
		draw_texture_rect(faces[int(c.face) % faces.size()], pr, true)
	else:
		draw_rect(pr, Color(0.3, 0.6, 0.4))
	var x := pr.end.x + 4
	_txt(Vector2(x, r.position.y + 13), "%s Lv%d" % [c.name, int(c.lv)], Color(0.7, 1, 0.75), 11)
	_bar(x, r.position.y + 17, r.end.x - x - 4, 6, float(c.hp) / maxi(1, int(c.maxHp)), Color(0.3, 0.8, 0.3))
	_bar(x, r.position.y + 25, r.end.x - x - 4, 4, float(c.exp) / maxi(1, int(c.needExp)), Color(0.5, 0.6, 0.95))   # 經驗條 (S02b)
	_txt(Vector2(x, r.position.y + 42), "忠%d 剩%d日" % [int(c.loyalty), int(c.daysLeft)],
		Color(1, 0.5, 0.45) if int(c.loyalty) < 40 else Color(0.95, 0.9, 0.75), 10)
	_txt(Vector2(x, r.position.y + 52), str(RulesRecruit.ORDER_NAMES.get(str(c.order), "")), Color(0.8, 0.85, 1.0), 9)

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
func _draw_info() -> void:
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
		var fx: Dictionary = main.sim.beast_effects_view(main.my_id)   # U13 戰騎導航/天眼/嗅血 友好技
		var tianyan: bool = bool(fx.get("show_npc", false))
		var xiuxue: bool = bool(fx.get("show_low_hp", false))
		for e in main.ents:
			var p := org + (Vector2(float(e.x) - float(md.ox), float(e.y) - float(md.oy)) + Vector2(0.5, 0.5)) * K
			if not dst.has_point(p) or int(e.id) == main.my_id:
				continue
			var is_low := xiuxue and bool(e.get("mob", false)) and float(e.maxHp) > 0 and float(e.hp) / float(e.maxHp) < 0.3
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.85, 0.1) if is_low else (Color(0.95, 0.25, 0.2) if e.get("mob", false) else Color(0.9, 0.9, 0.9)))
			if tianyan and not e.get("mob", false) and (bool(e.get("bot", false)) or bool(e.get("gen", false))):
				_txt(p + Vector2(3, 3), str(e.name), Color(0.6, 0.95, 1.0), 9)
		for qn in main.quest_npcs:
			var q := org + (Vector2(float(qn.x) - float(md.ox), float(qn.y) - float(md.oy)) + Vector2(0.5, 0.5)) * K
			if dst.has_point(q):
				draw_rect(Rect2(q - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.4, 0.75, 1.0))
		for gn in main.generals:
			var gq := org + (Vector2(float(gn.x) - float(md.ox), float(gn.y) - float(md.oy)) + Vector2(0.5, 0.5)) * K
			if dst.has_point(gq):
				draw_rect(Rect2(gq - Vector2(1.5, 1.5), Vector2(3, 3)), Color(1.0, 0.8, 0.3))
		var geo: bool = main.sim.geo_unlocked()      # 地理專長 lv≥1: 全部設施顯示，唔止傳送點 (S01c, spec 01 §8)
		for f in main.facilities:
			if String(f.kind) == "travel" or geo:
				var tp := org + (Vector2(float(f.x) - float(md.ox), float(f.y) - float(md.oy)) + Vector2(0.5, 0.5)) * K
				if dst.has_point(tp):
					draw_circle(tp, 2.5, Color(0.5, 1.0, 0.4) if String(f.kind) == "travel" else Color(0.6, 0.8, 1.0))
		draw_circle(org + (Vector2(mx, my) + Vector2(0.5, 0.5)) * K, 2.5, Color(1, 0.9, 0.2))
		var zv: Dictionary = main.sim.zone_view(int(me.x), int(me.y))
		var nm := str(zv.get("area", "")) if str(zv.get("area", "")) != "" else str(zv.get("name", ""))
		if bool(fx.get("map_city", false)):     # U13 戰騎「導航」友好技: 加返最近城池名 + 方向指示
			var nc: Dictionary = main.sim.nearest_city_view(int(me.x), int(me.y))
			if not nc.is_empty():
				nm += "  →%s" % str(nc.get("name", ""))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 14)), Color(0, 0, 0, 0.55))
		_txt_right(Vector2(r.end.x - 4, r.position.y + 11), nm, Color(0.95, 0.88, 0.7), 11)
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - 13), Vector2(r.size.x, 13)), Color(0, 0, 0, 0.55))
	_txt_right(Vector2(r.end.x - 4, r.end.y - 3), ("夜 " if main.night_on else "") + str(main.clock_str), Color(1, 0.95, 0.65), 10)
	draw_rect(r, UiTheme.GOLD if _is_down("minimap") else Color(1, 1, 1, 0.35), false, 1.0)

func _draw_menu() -> void:
	for id in HudLayout.MENU:
		var r: Rect2 = layout[id]["rect"]
		var down := _is_down(id)
		var pk_on: bool = id == "menu_pk" and bool(main.pk_mode)
		draw_rect(r, Color(0.55, 0.12, 0.12, 0.95) if pk_on else (Color(0.3, 0.22, 0.12, 0.95) if down else Color(0.12, 0.1, 0.08, 0.85)))
		draw_rect(r, Color(1, 0.3, 0.25) if pk_on else UiTheme.GOLD, false, 1.5)
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
	# 騎馬掣 (Step 17a)
	var mb := mount_btn()
	if not mb.is_empty():
		var mc: Vector2 = layout["mount"]["c"]
		var ring := Color(1, 0.85, 0.3) if bool(mb["ok"]) else Color(0.5, 0.5, 0.5)
		_circle_btn("mount", Color(0.45, 0.28, 0.12, 0.85) if bool(mb["riding"]) else Color(0.12, 0.12, 0.12, 0.8), ring)
		_txt_center(mc.y + 5, "落馬" if bool(mb["riding"]) else "騎馬", Color.WHITE if bool(mb["ok"]) else Color(0.65, 0.65, 0.65), 13, 44, mc.x - 22)
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
