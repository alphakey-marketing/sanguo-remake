extends Node2D
# UI: 內嵌單機 sim (sim/sim.gd)，畫格仔地圖同單位、點擊行路、戰鬥 (右鍵切戰鬥游標 → 左鍵點怪)、HUD、背包。
# UI 只透過 sim.cmd_* 發意圖、event_emitted 收事件、view_ents()/player_ch() 讀狀態。
# 命令行: --autotest 端到端: 入場 → 行路 → 攻擊最近怪 → 怪死 → 經驗增加 → print PASS 退出 (加速跑 sim)

const TILE := 16
const TICK := 0.1                 # sim 10Hz
const AUTOTEST_STEPS := 20        # autotest 每幀跑幾多 tick
const FACE_DIR := "res://assets_placeholder/faces/"   # 原版頭像佔位: 私人測試，成品前換走
const FONT_SZ := 12
const TARGET_RANGE := 16          # 換目標: 附近幾多格 (Manhattan) 內嘅怪
const FIELD_RETRY_TICKS := 60     # 自動掛機冇怪: 每幾多 tick 再行去野區
const DEBUG_FOOD := 29054         # debug「試食」: 燻魚 (回 HP)
const LONG_PRESS_MS := 650        # S03a: 長按 NPC 先出「攻擊」menu (二次確認)

var sim: Sim
var data: GameData
var acc := 0.0
var my_id := -1
var w := Sim.W
var h := Sim.H
var ents := []
var faces := []
var cam := Vector2.ZERO
var autotest := false
var uitest := false                # --uitest: 觸控 UI 煙霧測試 (tests/ui_smoke.gd)
var t0 := 0.0
var start_pos := Vector2i(-1, -1)
var moved := false
var target_id := -1
var _touch_at := 0                # S03a: 長按偵測 (down 嘅時間戳)
var _touch_pos := Vector2.ZERO
var hud: MobileHud                # 手機操控層 (ui/touch/mobile_hud.gd)
var auto := false                 # 自動掛機
var auto_whitelist := {}          # U-fix: 自動掛機淨打嘅怪名 (name -> true)；空 = 打晒
var auto_roam := false            # U-fix: 自動掛機冇怪時可唔可以自動跨場景去搵怪 (預設關，留喺同一場景)
var pk_mode := false              # 打人模式: 開 = 所有怪+NPC 都可以撳中/target 攻擊；關 = 淨係怪 + 敵對(紅名/鎖定緊我)嘅 NPC 先得
var move_mode := "stick"           # 移動模式 (UAT-feedback): "stick" = 搖桿 / "tap" = 撳地行；存 user://settings.cfg
const SETTINGS_FILE := "user://settings.cfg"

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_FILE) == OK:
		move_mode = String(cf.get_value("ui", "move_mode", move_mode))
		if move_mode != "tap" and move_mode != "stick":
			move_mode = "stick"
func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("ui", "move_mode", move_mode)
	cf.save(SETTINGS_FILE)
func _set_move_mode(mode: String) -> void:
	if mode != "stick" and mode != "tap":
		return
	move_mode = mode
	_save_settings()
var potion_slots: Array = [0, 0, 0]   # U-fix: 快捷補品欄 3 格，存 item id（0 = 空），純 UI 偏好唔入 sim 存檔
var sshot_file := ""             # --sshot: 開場幾秒後截圖存 user:// 退出
var ch := {}                      # 玩家角色狀態 (sim 內同一個 Dictionary)
var item_names := {}              # id -> 名 (items.json)
var floats := []                  # 傷害數字 {pos, text, color, age}
var log_lines := []
var exp_start := -1
var atk_sent := false
var kills := 0
var facilities := []              # 設施 {kind, name, x, y, color, fac}
var item_prices := {}             # id -> 價錢
var inn_cost := 0
var clock_str := ""               # 時辰/日/季節 (sim.clock_view)
var night_on := false
var beast_light := false          # 焰牙虎「火焰」友好技: 夜晚照明
var last_season := -1
var banner := {"text": "", "t": 0.0}   # 天災/季節橫幅
var last_save_tick := 0
var quest_npcs := []               # 任務 NPC 視圖 (Step 8): sim.view_quest_npcs()
var generals := []                 # 城內 Tier1 武將 (Step 13.5): sim.view_generals()
var comp := {}                     # 登用同伴 (Step 13.5): sim.companion_view()，{} = 冇
var quest_items := {}              # item id -> true (任務道具，賣唔到標記用)
var pending := {}                  # 點遠處 NPC/設施: 行到附近自動開 {kind, ref}
var marker := {"pos": Vector2.ZERO, "t": 0.0}   # 點地行路落點標記
var _ask_seen := ""                # 任務答題對話框已自動彈過 (唔好一直彈)
var cur_map := {}                  # 玩家而家身處嘅地圖 def (spec 12)
var _place_key := ""               # 地圖+區名: 變咗就彈區名橫幅
var ent_by_id := {}                # id -> ents 入面嗰個視圖 (_refresh 砌)
var llm_client: LlmClient          # key 只存本機 user://llm.cfg，唔入 sim 存檔 (S09d)
var llm_log := []                  # 最近 LLM 對話句 (面板顯示用，U11)
var ask_now := {}                  # 進行中答題 (_refresh 計，每 tick 一次)
var _unlock_chest := 0             # 開鎖小遊戲目標寶箱实體 id (unlock_panel 用, S02c)
var _dirty := false                # 發咗意圖/收咗事件: 下幀要 _refresh (唔使等下個 tick)
var cur_slot := 0                  # U-fix: 0 = 用返 AUTOSLOT（原有行為）；1~SLOT_COUNT = 揀咗嗰個角色位
var awaiting_slot_pick := false     # U-fix: 開場等緊玩家喺「選擇角色」揀 slot，未有真正角色（唔好自動存/唔理輸入）

func _ready() -> void:
	UiTheme.install_font()   # embed CJK 字形，HUD/panel 中文先顯示到（Web/iOS 唔使睇 browser fallback）
	autotest = "--autotest" in OS.get_cmdline_user_args()
	uitest = "--uitest" in OS.get_cmdline_user_args() or "--uishot" in OS.get_cmdline_user_args()
	# 內建 watchdog: --uitest/--autotest 無論 test script 有冇 load 到 / 有冇 crash / 有冇死迴圈，
	# 超過呢個時間都會強制 quit，唔會令 Godot 無限跑 → bash 永久等 → relay leg 掛死。
	# 要喺 load test script 之前裝好，先至唔會因 smoke parse error 而失效。
	if autotest or uitest:
		get_tree().create_timer(150.0).timeout.connect(func() -> void:
			print("FAIL: watchdog timeout (150s)")
			get_tree().quit(1))
	for i in Sim.FACE_COUNT:
		var p := "%sface_%d.jpg" % [FACE_DIR, i]
		faces.append(load(p) if ResourceLoader.exists(p) else null)   # 冇圖就畫色塊
	data = GameData.load_all()
	item_names = data.names
	for id in data.prices:
		item_prices[id] = int(data.prices[id])
	inn_cost = int(data.inn["restCost"])
	for inn in data.inns:
		facilities.append({"kind": "inn", "name": String(inn["name"]), "x": int(inn["x"]), "y": int(inn["y"]), "color": Color(0.3, 0.5, 0.9)})
	for sh in data.shops:
		facilities.append({"kind": "shop", "name": str(sh["name"]), "x": int(sh["x"]), "y": int(sh["y"]),
			"color": Color(0.9, 0.7, 0.2), "stock": sh["stock"], "shopName": str(sh["name"]),
			"map": String(sh.get("map", ""))})
	for key in data.facilities:
		var fv: Variant = data.facilities[key]
		if not fv is Dictionary:          # 跳過 _note
			continue
		var f: Dictionary = fv
		var col: Array = f["color"]
		facilities.append({"kind": "fac", "fac": key, "name": f["name"], "x": int(f["x"]), "y": int(f["y"]),
			"color": Color(float(col[0]), float(col[1]), float(col[2]))})
	for tp in data.travel_points:
		facilities.append({"kind": "travel", "point": String(tp["id"]), "name": String(tp["name"]),
			"x": int(tp["x"]), "y": int(tp["y"]), "color": Color(0.6, 0.9, 0.4)})
	var c: Dictionary = data.cats
	for k in c:
		if int(c[k]) == 44 or int(c[k]) == 52:
			quest_items[int(k)] = true
	sim = Sim.new(data, 1 if autotest or uitest else randi())
	var fresh := true
	var newgame := "--newgame" in OS.get_cmdline_user_args()
	if autotest or uitest or newgame:
		# 自動化測試 / dev 快速開新局: 照舊即刻 spawn，唔經「選擇角色」畫面
		sim.init_mobs()
		sim.add_residents()
		sim.add_guards()
		my_id = sim.spawn_player("玩家")
	else:
		# U-fix: 「選擇角色」而家係開場第一個畫面 —— 舊版單一 AUTOSLOT 存檔一次過搬去角色位 1，
		# 等玩家喺個 3 個角色位入面揀（揀有存檔嘅 = 繼續；揀空嘅 = 新建角色走建角面板）。
		if not SaveSys.slot_exists(1) and SaveSys.has(SaveSys.AUTOSLOT):
			var f := FileAccess.open(SaveSys.slot_path(1), FileAccess.WRITE)
			if f != null:
				f.store_string(FileAccess.get_file_as_string(SaveSys.AUTOSLOT))
				f.close()
		fresh = false                # 未 spawn 任何人，淨係等揀 slot（唔算「新開局」）
		awaiting_slot_pick = true
	sim.event_emitted.connect(_on_event)
	llm_client = LlmClient.new()
	llm_client.load_cfg()
	_load_settings()
	_refresh()
	hud = MobileHud.new()
	add_child(hud)
	hud.setup(self)
	hud.attack_pressed.connect(_hud_attack)
	hud.auto_toggled.connect(_hud_auto)
	hud.target_cycle.connect(_cycle_target)
	hud.skill_pressed.connect(_on_skill)
	hud.context_pressed.connect(func(act: Dictionary) -> void: ContextActions.run(self, act))
	hud.create_done.connect(_on_create_done)
	if awaiting_slot_pick:
		hud.open_panel("title")      # U-fix: 開場第一畫面 = 揀角色位（TitlePanel 標題「選擇角色」）
	elif fresh and not autotest and not uitest:
		hud.open_panel("create")
	for a in OS.get_cmdline_user_args():
		if a == "--sshot":
			sshot_file = "user://sshot_ui.png"
	if "--uitest" in OS.get_cmdline_user_args():
		var sm := load("res://tests/ui_smoke.gd")
		if sm != null:   # guard: smoke parse error 都唔會 crash main._ready (斷續 -> watchdog 接住 quit)
			add_child(sm.new())
	elif "--uishot" in OS.get_cmdline_user_args():
		var sh := load("res://tests/ui_shot.gd")
		if sh != null:
			add_child(sh.new())

# 怪物動畫狀態 (客戶端推算): 位置變 = 行走 + 面向；aggro 且未郁 = 攻擊；否則站立
var _mon_anim := {}

func _mon_track(e: Dictionary) -> void:
	var id := int(e.id)
	var a: Dictionary = _mon_anim.get(id, {"x": e.x, "y": e.y, "dir": 4, "move_until": 0.0})
	var dx := int(e.x) - int(a.x)
	var dy := int(e.y) - int(a.y)
	if dx != 0 or dy != 0:
		# 順時針 N,NE,E,SE,S,SW,W,NW = 0..7
		var tab := {Vector2i(0, -1): 0, Vector2i(1, -1): 1, Vector2i(1, 0): 2, Vector2i(1, 1): 3, Vector2i(0, 1): 4, Vector2i(-1, 1): 5, Vector2i(-1, 0): 6, Vector2i(-1, -1): 7}
		a["dir"] = tab.get(Vector2i(signi(dx), signi(dy)), a.dir)
		a["move_until"] = t0 + 0.35
	elif (int(e.get("aggro", 0)) > 0 or int(e.get("atkTarget", 0)) > 0) and ent_by_id.has(int(e.get("aggro", 0)) if int(e.get("aggro", 0)) > 0 else int(e.atkTarget)):
		var t: Dictionary = ent_by_id[int(e.get("aggro", 0)) if int(e.get("aggro", 0)) > 0 else int(e.atkTarget)]
		var tx := signi(int(t.x) - int(e.x))
		var ty := signi(int(t.y) - int(e.y))
		if tx != 0 or ty != 0:
			a["dir"] = {Vector2i(0, -1): 0, Vector2i(1, -1): 1, Vector2i(1, 0): 2, Vector2i(1, 1): 3, Vector2i(0, 1): 4, Vector2i(-1, 1): 5, Vector2i(-1, 0): 6, Vector2i(-1, -1): 7}.get(Vector2i(tx, ty), a.dir)
	a["x"] = e.x
	a["y"] = e.y
	_mon_anim[id] = a

# 人形 sprite id 快取 (ent id -> sid；0 = 冇圖走舊頭像)
var _actor_sid := {}

func _sid_for(e: Dictionary) -> int:
	var id := int(e.id)
	if not _actor_sid.has(id):
		var isme := id == my_id
		_actor_sid[id] = AssetLib.actor_sid(str(e.get("name", "")), str(e.get("role", "")), id, str(ch.get("classId", "")) if isme else "")
	return int(_actor_sid[id])

# 畫動畫幀 (怪物用 mdef，人形用 actor sid)；冇 sheet 返回 false (呼叫方畫舊圖/色塊)
func _draw_mon_sprite(e: Dictionary, p: Vector2) -> bool:
	var mob: bool = e.get("mob", false)
	var sid := int(e.get("mdef", 0)) if mob else _sid_for(e)
	if sid == 0:
		return false
	var a: Dictionary = _mon_anim.get(int(e.id), {})
	var act := "S"
	if t0 < float(a.get("move_until", 0.0)):
		act = "W"
	elif int(e.get("aggro", 0)) > 0 or int(e.get("atkTarget", 0)) > 0:
		act = "A"
	var tex := AssetLib.mon_sheet(sid, act) if mob else AssetLib.actor_sheet(sid, act)
	if tex == null:
		tex = AssetLib.mon_sheet(sid, "S") if mob else AssetLib.actor_sheet(sid, "S")
		if tex == null:
			return false
	var cw := tex.get_width() / 8
	var ch_ := tex.get_height() / 8
	var src := Rect2(int(t0 * 8.0) % 8 * cw, int(a.get("dir", 4)) * ch_, cw, ch_)
	var sz := Vector2(cw, ch_) * 0.42
	draw_texture_rect_region(tex, Rect2(p + Vector2(TILE * 0.5 - sz.x * 0.5, TILE - sz.y), sz), src)
	return true

# 靜止 NPC/武將: 面向鏡頭站立幀 (row 4)
func _draw_idle_actor(name_: String, key: int, p: Vector2) -> bool:
	if not _actor_sid.has(-key):
		_actor_sid[-key] = AssetLib.actor_sid(name_, "", key)
	var sid := int(_actor_sid[-key])
	var tex := AssetLib.actor_sheet(sid, "S") if sid != 0 else null
	if tex == null:
		return false
	var cw := tex.get_width() / 8
	var ch_ := tex.get_height() / 8
	var sz := Vector2(cw, ch_) * 0.42
	draw_texture_rect_region(tex, Rect2(p + Vector2(TILE * 0.5 - sz.x * 0.5, TILE - sz.y), sz), Rect2(int(t0 * 8.0) % 8 * cw, 4 * ch_, cw, ch_))
	return true

func _refresh() -> void:
	_dirty = false
	ents = sim.view_ents()
	ent_by_id.clear()
	for e in ents:
		ent_by_id[int(e.id)] = e
		_mon_track(e)
	ch = sim.player_ch()
	quest_npcs = sim.view_quest_npcs()
	generals = sim.view_generals()
	comp = sim.companion_view()
	var me = _me()
	if me != null:
		cur_map = sim.map_at(int(me.x), int(me.y))
		cam = _clamp_cam(Vector2(me.x, me.y) * TILE + Vector2(TILE, TILE) * 0.5 - get_viewport_rect().size / 2)
		_check_place(me)
	if target_id >= 0 and _ent(target_id) == null: target_id = -1
	if exp_start < 0 and not ch.is_empty(): exp_start = _exp_total()
	var cv: Variant = sim.clock_view()
	clock_str = str(cv["text"])
	night_on = bool(cv["is_night"])
	beast_light = bool(sim.beast_effects_view(my_id).get("light", false))
	ask_now = _calc_active_ask()
	if hud != null:
		hud.sim_refreshed()
		_down_watchdog()

# 鏡頭限喺當前地圖入面；地圖細過畫面就置中 (spec 12 §6)
func _clamp_cam(c: Vector2) -> Vector2:
	if cur_map.is_empty():
		return c
	var vs := get_viewport_rect().size
	var r := Rect2(Vector2(int(cur_map.ox), int(cur_map.oy)) * TILE, Vector2(int(cur_map.w), int(cur_map.h)) * TILE)
	var out := c
	for a in 2:
		if r.size[a] <= vs[a]:
			out[a] = r.position[a] + (r.size[a] - vs[a]) / 2.0
		else:
			out[a] = clampf(c[a], r.position[a], r.end[a] - vs[a])
	return out.floor()

# 入新地圖 / 新區域: 彈區名橫幅 (三國群英傳M 風)
func _check_place(me: Dictionary) -> void:
	var zv := sim.zone_view(int(me.x), int(me.y))
	var key := "%s|%s" % [zv.get("name", ""), zv.get("area", "")]
	if key == _place_key:
		return
	var first := _place_key == ""
	_place_key = key
	if first or autotest:
		return
	var nm := str(zv.get("area", "")) if str(zv.get("area", "")) != "" else str(zv.get("name", ""))
	if nm != "":
		banner = {"text": "— %s —" % nm, "t": 3.0, "color": Color(0.95, 0.85, 0.55)}

var debug_speed := 1    # debug: 時間加速倍率 (1/4/16/64)，唔入存檔

func _process(delta: float) -> void:
	if autotest:
		for i in AUTOTEST_STEPS: sim.step()
		_dirty = true
	else:
		acc += delta
		while acc >= TICK:
			acc -= TICK
			sim.step()
			for i in range(debug_speed - 1):    # debug 加速: 額外 sim tick
				sim.step()
			_steer_tick()
			_auto_tick()
			_refresh()                  # 視圖跟 sim tick (10Hz) 更新，唔使每幀砌
	if _dirty:
		_refresh()
	if float(banner["t"]) > 0:
		banner["t"] = float(banner["t"]) - delta
	if not autotest:
		_ui_tick(delta)
	t0 += delta
	if not autotest and not uitest and not awaiting_slot_pick and sim.tick > 0 and sim.tick % _ticks_per_day() == 0 and sim.tick != last_save_tick:
		last_save_tick = sim.tick
		_save_current()
	for f in floats: f.age += delta
	floats = floats.filter(func(f): return f.age < 1.0)
	var me = _me()
	if autotest and me != null: _autotest_step(me)
	if autotest and t0 > 60.0:
		print("FAIL: timeout (moved=%s atk=%s kills=%d)" % [moved, atk_sent, kills]); get_tree().quit(1)
	queue_redraw()
	if sshot_file != "" and t0 > 2.5:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(sshot_file)
			print("SSHOT saved: ", ProjectSettings.globalize_path(sshot_file))
		else:
			print("SSHOT failed (headless 冇 GPU?)")
		sshot_file = ""

# 自動存檔週期 = 1 遊戲日 (1440 遊戲分 / gameMinPerTick)
func _ticks_per_day() -> int:
	return maxi(1, int(1440.0 / float(int(data.world["clock"]["gameMinPerTick"]))))

# 舊 ws 訊息格式 → sim 意圖
func _send(d: Dictionary) -> void:
	_dirty = true
	match d.t:
		"move": sim.cmd_move(my_id, int(d.x), int(d.y))
		"attack": sim.cmd_attack(my_id, int(d.target))
		"chat": sim.cmd_chat(my_id, str(d.text))
		"rest": sim.cmd_rest(my_id)
		"buy": sim.cmd_buy(my_id, int(d.item), int(d.get("n", 1)))
		"mall_buy": sim.cmd_mall_buy(my_id, int(d.item), int(d.get("n", 1)))
		"sell": sim.cmd_sell(my_id, int(d.item), int(d.get("n", 1)))
		"facility": sim.cmd_facility(my_id, str(d.key))
		"travel": sim.cmd_travel(my_id, str(d.point))
		"station": sim.cmd_station(my_id, str(d.to))
		"goto_map": sim.cmd_goto_map(my_id, str(d.map))
		"work": sim.cmd_work(my_id, str(d.skill))
		"equip_tool": sim.cmd_equip_tool(my_id, str(d.skill), int(d.item))
		"pick": sim.cmd_pick(my_id, int(d.drop))
		"storage_sub": sim.cmd_storage_sub(my_id, bool(d.on))
		"storage_deposit": sim.cmd_storage_deposit(my_id, int(d.item), int(d.get("n", 1)))
		"storage_withdraw": sim.cmd_storage_withdraw(my_id, int(d.item), int(d.get("n", 1)))
		"storage_sell": sim.cmd_storage_sell(my_id, int(d.item), int(d.get("n", 1)))
		"storage_rest": sim.cmd_storage_rest(my_id)
		"tiandi_set": sim.cmd_tiandi_set(my_id, str(d.key), bool(d.on))
		"claim_title": sim.cmd_claim_title(my_id, int(d.rank))
		"office_order": sim.cmd_office_order(my_id, str(d.order))
		"office_turnin": sim.cmd_office_turnin(my_id)
		"comm_accept": sim.cmd_comm_accept(my_id, str(d.giver))
		"comm_report": sim.cmd_comm_report(my_id, str(d.giver))
		"comm_abandon": sim.cmd_comm_abandon(my_id, str(d.giver))
		"book_exchange": sim.cmd_book_exchange(my_id)
		"book_put": sim.cmd_book_put(my_id)
		"book_take": sim.cmd_book_take(my_id, int(d.item))
		"office_abandon": sim.cmd_office_abandon(my_id)
		"merit_turnin": sim.cmd_merit_turnin(my_id, int(d.item))
		"domestic": sim.cmd_domestic(my_id, str(d.job))
		"office_relief": sim.cmd_office_relief(my_id)
		"relief_work": sim.cmd_relief_work(my_id)
		"city_tribute": sim.cmd_city_tribute(my_id, d.items as Array)
		"settle": sim.cmd_settle(my_id, str(d.city))
		"militia_invite": sim.cmd_militia_invite(my_id, int(d.npc))
		"militia_found": sim.cmd_militia_found(my_id, str(d.name), str(d.password))
		"camp_upgrade": sim.cmd_camp_upgrade(my_id, str(d.fac))
		"camp_supervise": sim.cmd_camp_supervise(my_id, str(d.fac))
		"camp_call_back": sim.cmd_camp_call_back(my_id, int(d.gid))
		"camp_mat": sim.cmd_camp_mat(my_id, int(d.item), int(d.n), str(d.dir))
		"militia_work": sim.cmd_militia_work(my_id, str(d.work))
		"eval_assign": sim.cmd_eval_assign(my_id, d.kinds as Array)
		"eval_meeting": sim.cmd_eval_meeting(my_id, d.kinds as Array)
		"city_tax": sim.cmd_city_tax(my_id, str(d.tax))
		"city_law": sim.cmd_city_law(my_id, str(d.law), bool(d.on))
		"drop_item": sim.cmd_drop_item(my_id, int(d.item), int(d.n))
		"office_pill": sim.cmd_office_pill(my_id)
		"office_redeem_tool": sim.cmd_office_redeem_tool(my_id, int(d.item))
		"master_gem": sim.cmd_master_gem(my_id, str(d.skill))
		"master_treasure": sim.cmd_master_treasure(my_id, str(d.skill), d.gems)
		"master_redeem_baizhu": sim.cmd_master_redeem_baizhu(my_id)
		"tea": sim.cmd_tea(my_id)
		"battle_enter": sim.cmd_battle_enter(my_id)
		"battle_leave": sim.cmd_battle_leave(my_id)
		"scene_enter": sim.cmd_scene_enter(my_id, str(d.sid))
		"scene_leave": sim.cmd_scene_leave(my_id)
		"donate_gold": sim.cmd_donate_gold(my_id, int(d.amount))
		"donate_items": sim.cmd_donate_items(my_id, d.items)
		"use_item": _use_item(my_id, int(d.item))
		"self_revive": sim.cmd_self_revive(my_id)
		"revive_pill": sim.cmd_revive_pill(my_id)
		"companion_revive": sim.cmd_companion_revive_owner(my_id)
		"raise_attr": sim.cmd_raise_attr(my_id, str(d.attr))
		"auto_assign": sim.cmd_auto_assign(my_id)
		"set_name": sim.cmd_set_name(my_id, str(d.name))
		"set_title": sim.cmd_set_title(my_id, str(d.title))
		"set_face": sim.cmd_set_face(my_id, str(d.part), int(d.value))
		"submit_quiz": sim.cmd_submit_quiz(my_id, d.answers)
		"quest_talk": sim.cmd_quest_talk(my_id, str(d.npc))
		"select_class": sim.cmd_select_class(my_id, str(d.class_id))
		"set_home": sim.cmd_set_home(my_id, str(d.home))
		"help_seen": sim.cmd_help_seen(my_id, str(d.key))
		"promote": sim.cmd_class_promote(my_id)
		"equip_spellbook": sim.cmd_equip_spellbook(my_id, int(d.item), int(d.get("slot", 0)))
		"cast_spell": sim.cmd_cast_spell(my_id, int(d.slot), int(d.get("target", 0)))
		"equip_weapon": sim.cmd_equip_weapon(my_id, int(d.item))
		"equip": sim.cmd_equip(my_id, int(d.item), int(d.get("wslot", -1)))
		"unequip": sim.cmd_unequip(my_id, str(d.part), int(d.get("wslot", -1)))
		"switch_weapon": sim.cmd_switch_weapon(my_id, int(d.wslot))
		"equip_jewel": sim.cmd_equip_jewel(my_id, int(d.item), int(d.get("slot", 0)))
		"use_ultimate": sim.cmd_use_ultimate(my_id, str(d.ult))
		"fusion_start": sim.cmd_fusion_start(my_id)
		"fusion_hit": sim.cmd_fusion_hit(my_id)
		"quest_answer": sim.cmd_quest_answer(my_id, str(d.quest), int(d.answer))
		"use_skill": sim.cmd_use_skill(my_id, str(d.skill))
		"skill_pick": sim.cmd_skill_pick(my_id, int(d.chest), int(d.key))
		"stealth_cross": sim.cmd_stealth_cross(my_id)
		"debug_learn": sim.cmd_debug_learn(my_id, str(d.kind), str(d.what))
		"debug_give": sim.cmd_debug_give(my_id, int(d.item), int(d.get("n", 1)))
		"craft": sim.cmd_craft(my_id, int(d.item))
		"repair": sim.cmd_repair(my_id, int(d.item))
		"repair_service": sim.cmd_repair_service(my_id, int(d.item))
		"debug_work_lv": sim.cmd_debug_work_lv(my_id, int(d.add))
		"debug_level": sim.cmd_debug_level(my_id, int(d.get("n", 1)))
		"general_talk": sim.cmd_general_talk(my_id, int(d.gid))
		"recruit_survey": sim.cmd_recruit_survey(my_id, str(d.kind))
		"recruit_pick": sim.cmd_recruit_pick(my_id, int(d.gid))
		"recruit_answer": sim.cmd_recruit_answer(my_id, int(d.answer))
		"recruit_cancel": sim.cmd_recruit_cancel(my_id)
		"companion_order": sim.cmd_companion_order(my_id, str(d.order))
		"companion_skill_mode": sim.cmd_companion_skill_mode(my_id, str(d.mode))
		"companion_gift": sim.cmd_companion_gift(my_id, int(d.item))
		"companion_treasure": sim.cmd_companion_treasure(my_id, int(d.item))
		"companion_dismiss": sim.cmd_companion_dismiss(my_id)
		"companion_skill": sim.cmd_companion_skill(my_id, str(d.kind))
		"mount_buy": sim.cmd_mount_buy(my_id, str(d.breed), bool(d.get("tamed", false)))
		"mount_stable": sim.cmd_mount_stable(my_id, int(d.uid))
		"mount_take": sim.cmd_mount_take(my_id, int(d.uid))
		"mount_act": sim.cmd_mount_act(my_id, int(d.uid), str(d.act), int(d.get("item", 0)))
		"mount_abandon": sim.cmd_mount_abandon(my_id, int(d.uid))
		"mount_point": sim.cmd_mount_point(my_id, int(d.uid), str(d.attr))
		"mount_rename": sim.cmd_mount_rename(my_id, int(d.uid), str(d.nick))
		"mount_ride": sim.cmd_mount_ride(my_id, bool(d.on))
		"mount_graze": sim.cmd_mount_graze(my_id)
		"mount_breed_start": sim.cmd_mount_breed_start(my_id, int(d.uid), str(d.sire))
		"mount_breed_bet": sim.cmd_mount_breed_bet(my_id, int(d.uid), int(d.choice))
		"mount_breed_lazy": sim.cmd_mount_breed_lazy(my_id, int(d.uid), bool(d.on))
		"mount_breed_claim": sim.cmd_mount_breed_claim(my_id, int(d.uid))
		"mount_take_foal": sim.cmd_mount_take_foal(my_id)
		"mount_spend_bpt": sim.cmd_mount_spend_bpt(my_id, int(d.uid), str(d.attr))
		"mount_weapon_buy": sim.cmd_mount_weapon_buy(my_id, str(d.wtype), str(d.wid))
		"mount_skill_learn": sim.cmd_mount_skill_learn(my_id, str(d.skill))
		"mount_skill_use": sim.cmd_mount_skill_use(my_id, str(d.skill), int(d.get("target", 0)))
		"beast_adopt": sim.cmd_beast_adopt(my_id, str(d.breed))
		"beast_deploy": sim.cmd_beast_deploy(my_id, int(d.uid), bool(d.on))
		"beast_point": sim.cmd_beast_point(my_id, int(d.uid), str(d.attr))
		"beast_train": sim.cmd_beast_train(my_id, int(d.uid), str(d.skill))
		"beast_friend_train": sim.cmd_beast_friend_train(my_id, int(d.uid), str(d.breed), str(d.skill))
		"beast_sell": sim.cmd_beast_sell(my_id, int(d.uid))
		"beast_teleport": sim.cmd_beast_teleport(my_id)
		"beast_act": sim.cmd_beast_act(my_id, str(d.effect))
		"auction_buy": sim.cmd_auction_buy(my_id, int(d.lot))
		"llm_config": sim.cmd_llm_config(bool(d.enabled), str(d.model))
		"marry_propose": sim.cmd_marry_propose(my_id)
		"marry_buy_cake": sim.cmd_marry_buy_cake(my_id, int(d.tier))
		"marry_open_cake": sim.cmd_marry_open_cake(my_id, int(d.item))
		"marry_share_cake": sim.cmd_marry_share_cake(my_id, int(d.item))
		"marry_book": sim.cmd_marry_book(my_id)
		"marry_hold": sim.cmd_marry_hold(my_id)
		"marry_summon": sim.cmd_marry_summon(my_id)
		"marry_message": sim.cmd_marry_message(my_id, str(d.text))
		"marry_divorce": sim.cmd_marry_divorce(my_id)

# 用道具：職業丹（30055~30059）→ cmd_use_class_pill (sim_skill)，其餘 → cmd_use_item。
const PILL_USE_IDS := [30055, 30056, 30057, 30058, 30059]
func _use_item(uid: int, item: int) -> void:
	if PILL_USE_IDS.has(item):
		sim.cmd_use_class_pill(uid, item)
	else:
		sim.cmd_use_item(uid, item)

# sim 發 llm_request（url/headers/body 已砌好，冇 key）；呢度加返 key、真正發 HTTP，
# 回應餵返 cmd_llm_reply/cmd_llm_summary。冇 key/傳送失敗 = 即刻用空字串回覆 → sim 模板後備。
func _on_llm_request(e: Dictionary) -> void:
	var req_id := int(e.reqId)
	var kind := String(e.kind)
	if llm_client == null or not llm_client.has_key():
		if kind == "talk":
			sim.cmd_llm_reply(req_id, "")
		return
	var headers: Dictionary = (e.get("headers", {}) as Dictionary).duplicate()
	headers["Authorization"] = "Bearer " + String(llm_client.cfg.get("key", ""))
	var hs: Array = []
	for k in headers: hs.append("%s: %s" % [k, headers[k]])
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 15.0
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		var text := body.get_string_from_utf8() if code >= 200 and code < 300 else ""
		if kind == "talk":
			sim.cmd_llm_reply(req_id, text)
		else:
			sim.cmd_llm_summary(req_id, text), CONNECT_ONE_SHOT)
	var err := http.request(String(e.get("url", "")), PackedStringArray(hs), HTTPClient.METHOD_POST, JSON.stringify(e.get("body", {})))
	if err != OK:
		http.queue_free()
		if kind == "talk":
			sim.cmd_llm_reply(req_id, "")


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 200: log_lines.pop_front()

const STATUS_NAMES := {"sealed": "封咒", "hex": "中邪", "power1": "聚力", "power2": "強力", "power3": "神力",
	"armor1": "護甲", "armor2": "金甲", "armor3": "聖鎧", "mirror1": "護鏡", "mirror2": "光鏡", "mirror3": "仙鏡",
	"stealth": "潛行", "insight": "洞悉"}
const ELEM_TAG := {"earth": "地", "water": "水", "fire": "火", "wind": "風"}

func _ent_name(id: int) -> String:
	var d = _ent(id)
	return str(d.name) if d != null else "？"

func _exp_total() -> int:
	var t := 0
	for l in range(1, int(ch.get("level", 1))): t += RulesStats.exp_to_next(l)
	return t + int(ch.get("exp", 0))

func _on_event(e: Dictionary) -> void:
	_dirty = true
	match e.k:
		"chat":
			_log("%s: %s" % [e.name, e.text])
		"npc_say":
			_log("%s: %s" % [e.name, e.text])
			if bool(e.get("llm", false)):
				llm_log.append("%s: %s" % [e.name, e.text])
				if llm_log.size() > 20: llm_log.pop_front()
		"llm_request":
			_on_llm_request(e)
		"hit":
			var d = _ent(int(e.dst))
			if d != null:
				var dmg: int = int(e.dmg)
				floats.append({"pos": Vector2(d.x, d.y) * TILE, "text": "miss" if dmg == 0 else str(dmg),
					"color": Color.YELLOW if int(e.dst) == my_id else Color.WHITE, "age": 0.0})
		"spell_hit":
			var d2 = _ent(int(e.dst))
			if d2 != null:
				var dmg2: int = int(e.dmg)
				floats.append({"pos": Vector2(d2.x, d2.y) * TILE,
					"text": ("miss" if dmg2 == 0 else str(dmg2)) + " " + String(ELEM_TAG.get(str(e.elem), "")),
					"color": Color(1, 0.45, 1.0) if int(e.dst) == my_id else Color(0.85, 0.45, 0.95), "age": 0.0})
		"cast_start":
			if int(e.src) == my_id:
				_log("開始吟唱 %s…" % item_names.get(int(e.book), str(e.book)))
			elif int(e.dst) == my_id:
				_log("%s 對你吟唱術法！" % _ent_name(int(e.src)))
		"cast_interrupted":
			var reason: String = str(e.get("reason", ""))
			var who := "你" if int(e.dst) == my_id else _ent_name(int(e.dst))
			_log("%s吟唱被打斷 (%s)" % [who, "移動" if reason == "move" else "受擊" if reason == "hit" else reason])
		"status":
			if int(e.dst) == my_id:
				var sid: String = str(e.id)
				_log("%s%s (剩 %d tick)" % ["解除" if not bool(e.get("applied", true)) else "狀態: ",
					STATUS_NAMES.get(sid, sid), maxi(0, int(e.get("until", 0)) - sim.tick)])
		"spellbook":
			if int(e.src) == my_id:
				_log("快捷列 %d: %s" % [int(e.slot) + 1, item_names.get(int(e.item), "(空)") if int(e.item) > 0 else "(空)"])
		"jewel":
			if int(e.src) == my_id:
				_log("寶石欄 %d: %s" % [int(e.slot) + 1, item_names.get(int(e.item), "(空)") if int(e.item) > 0 else "(空)"])
		"equip":
			if int(e.src) == my_id:
				var part: String = str(data.equip_cfg["slotNames"].get(str(e.slot), "武器"))
				_log("%s: %s" % [part, item_names.get(int(e.item), str(e.item)) if int(e.item) > 0 else "(卸下)"])
		"armor_broken":
			if int(e.dst) == my_id:
				_log("「%s」耐久用盡，效果減半" % item_names.get(int(e.item), str(e.item)))
		"ult":
			if int(e.src) == my_id:
				_log("「%s」！ (-%d MP -%d SP)" % [e.name, int(e.get("mp", 0)), int(e.get("sp", 0))])
		"comp_skill":
			if int(e.dst) == my_id:
				_log("%s：「%s」！" % [_ent_name(int(e.src)), e.name])
		"ult_hit":
			var d3 = _ent(int(e.dst))
			if d3 != null:
				floats.append({"pos": Vector2(d3.x, d3.y) * TILE, "text": str(int(e.dmg)),
					"color": Color(1, 0.35, 0.1), "age": 0.0})
		"fusion":
			if int(e.src) == my_id:
				match str(e.get("state", "")):
					"start": _log("融合 QTE 起動！喺 50%% 左右撳實！")
					"ok": _log("融合成功！武器嵌咗 %s+%d%%" % [e.get("elem", ""), int(e.get("pct", 0))])
					"fail": _log("融合失敗，再試下")
		"quest_battle":
			if int(e.dst) == my_id:
				_log("%s 出現咗！打贏攞証物！" % str(e.name))
		"reclass":
			my_id = int(e.id)
			_log("職業改做 %s" % str(e.class))
		"kill":
			if int(e.src) == my_id:
				kills += 1
				var names := []
				for i in e.items: names.append(item_names.get(int(i), str(i)))
				_log("殺怪 +%d 經驗 +%d 金 %s%s" % [e.exp, e.gold, ",".join(names), "  升級! Lv%d" % e.lvUp if int(e.lvUp) > 0 else ""])
		"kill_npc":                # S03a: 殺居民/紅名 NPC -> 善惡變化
			if int(e.dst) == my_id:
				var km := str(e.get("kind", ""))
				var diff_str := "善惡咗"
				kills += 1
				_log("殺%s%s！%s（善惡而家 %d）" % ["咗紅名·殺人魔" if bool(e.get("red", false)) else "居民", str(e.name), "（反擊+100）" if bool(e.get("counter", false)) else "（謀殺-1000）", int(e.get("karma", 0))])
		"guard_alert":            # S03a: 被襲居民走去叫衛兵
			if int(e.dst) == my_id:
				_log("%s走去叫衛兵！" % str(e.name))
		"tianqian":               # S03b: 殺善居民後天譴雷劈 -> 世界公告 (只扣 HP，唔傳送)
			if int(e.dst) == my_id:
				_set_banner(str(e.announce), Color(1, 0.3, 0.9), 6.0)
				_log("天譴雷劈！%s（現有 HP×50%%）" % str(e.announce))
				target_id = -1
		"guard_warn":             # S03b: 殺人魔喺城內 -> 城門衛兵警告
			if int(e.dst) == my_id:
				_log(str(e.get("text", "城門衛兵攔住你：唔准入城！")))
		"msg":
			if int(e.dst) == my_id: _log(str(e.text))
		"picked":                 # S04a 拾取地面掉落物
			if int(e.dst) == my_id:
				var pn := []
				for it in e.get("items", []):
					pn.append("%s×%d" % [item_names.get(int(it["id"]), str(it["id"])), int(it["n"])])
				if not pn.is_empty():
					_log("拾取 %s" % ", ".join(pn))
				if bool(e.get("full", false)):
					_log("背包滿，有啲裝唔落留落地")
		"travel":
			if int(e.dst) == my_id:
				target_id = -1
				_log("傳送到 %s" % str(e.to))
		"die":
			if int(e.dst) == my_id:
				var dr := _death_report(e)
				last_death_report = dr
				for _ln in dr.split("\n"):
					_log(_ln)                       # UAT: 死亡報告全部入信息欄（含跌咗咩/扣經驗）
				target_id = -1
				if not uitest:
					_save_current()             # 死完即存
				ch["status"] = {}              # 死亡清狀態 (sim 權威，UI 同步)
				if hud != null and not autotest and not uitest:
					if bool(e.get("down", false)):
						hud.open_dialog(_down_dialog)     # 倒地畫面: 倒數 + 回城/復活丹/同伴超渡掣【自訂新增】
					else:
						hud.open_dialog(func() -> Dictionary: return {
							"title": "你死咗", "text": dr, "options": [{"label": "繼續", "cb": func() -> void: hud.close_panels()}]})
		"revive_self":                          # 倒地 → 回城/復活丹/逾時兜底復活【自訂新增】
			if int(e.dst) == my_id:
				if hud != null:
					hud.close_panels()
				if bool(e.get("timeout", false)):
					_set_banner("倒地太耐，強制送返客棧", Color(1, 0.7, 0.4), 5.0)
				elif bool(e.get("onsite", false)):
					_set_banner("服咗復活丹，原地起返身！", Color(0.6, 1, 0.6), 4.0)
				else:
					_set_banner("返到客棧，精神返嚟（HP/MP/SP 回一半）", Color(0.6, 1, 0.6), 4.0)
		"flee":
			if int(e.get("dst", -1)) == my_id:
				_log("%s 見你唔夠打，逃咗！" % str(e.get("name", "")))
		"train":
			if int(e.src) == my_id:
				if e.has("partner"):
					_log("同 %s 對練，經驗 +%d" % [e.partner, int(e.exp)])
				else:
					_log("%s: %s +1 (而家 %d)" % ["私塾" if e.attr == "政治" else "寺廟", e.attr, int(e.val)])
		"quest":
			if int(e.dst) == my_id:
				var qname := String(e.quest)
				var dlg: Array = e.get("dialog", [])
				if not dlg.is_empty() and hud != null and not autotest and not uitest:
					_show_quest_dialog(str(e.get("speaker", "")), dlg)
				if bool(e.get("started", false)):
					_log("接咗任務「%s」" % qname)
				elif bool(e.get("done", false)):
					var rw: Dictionary = e.get("reward", {})
					var parts: Array = []
					if int(rw.get("gold", 0)) > 0: parts.append("+%d 金" % int(rw["gold"]))
					if int(rw.get("exp", 0)) > 0: parts.append("+%d 經驗" % int(rw["exp"]))
					if rw.has("title"): parts.append("解鎖稱號「%s」！" % str(rw["title"]))
					if rw.has("ultimate"): parts.append("學識絕招「%s」！" % str(rw["ultimate"]))
					if rw.has("skill"):
						var sd: Dictionary = data.class_skills.get(str(rw["skill"]), {})
						parts.append("學識特技「%s」！" % str(sd.get("name", rw["skill"])))
					if rw.has("items"):
						for it in rw["items"]:
							parts.append("%s x%d" % [item_names.get(int(it.id), str(it.id)), int(it.n)])
					_log("任務完成「%s」 %s" % [qname, " ".join(parts) if not parts.is_empty() else ""])
				else:
					_log("「%s」有進展" % qname)
		"heal":
			if int(e.dst) == my_id:
				_log("密醫幫你醫治，回復 %d HP" % int(e.hp))
		"unlock_open":                        # S02c 開鎖小遊戲: sim 搵到附近鎖寶箱 -> 開揀鑰匙面板
			if int(e.dst) == my_id and hud != null:
				_unlock_chest = int(e.get("chest", 0))
				hud.open_panel("unlock")
		"unlock_done":                        # 開鎖成功 -> 閂面板 (失敗留低再試)
			if int(e.dst) == my_id and hud != null and bool(e.get("ok", false)):
				hud.close_panels()
		"stealth_open":                        # S02c 潛行: 行車 QTE 開面板
			if int(e.dst) == my_id and hud != null:
				hud.open_panel("stealth")
				_set_banner("行車嚟緊——揀啱空隙穿過！", Color(0.9, 0.9, 0.6), 3.0)
		"stealth_done":						# 成功: 閂面板 + 顯示潛行
			if int(e.dst) == my_id and hud != null:
				hud.close_panels()
				_set_banner("潛行！主動怪唔會仇恨你（10 分鐘）", Color(0.6, 0.8, 1.0), 4.0)
		"stealth_fail":                        # 失敗: 閂面板，留個 msg
			if int(e.dst) == my_id and hud != null:
				hud.close_panels()
		"qieting":                              # S02c-辯士 竊聽: 耳邊「…」傳聞線索
			if int(e.dst) == my_id:
				_log("【%s 耳邊「…」】%s" % [str(e.get("who", "居民")), str(e.get("text", ""))])
				if hud != null:
					_set_banner("耳邊「…」%s" % str(e.get("text", "")), Color(0.85, 0.85, 0.95), 5.0)
		"toushi":                              # S02c-美女 透視: 顯示隱藏資訊 + 洞悉
			if int(e.dst) == my_id:
				var inf = e.get("info", {})
				if inf is Dictionary:
					var wk := str(inf.get("weakness", ""))
					_log("透視【%s】Lv%d HP %d/%d 弱點：%s" % [str(inf.get("name", "")), int(inf.get("level", 0)),
						int(inf.get("hp", 0)), int(inf.get("maxHp", 0)), wk if wk != "" else "無"])
					if hud != null:
						_set_banner("透視【%s】Lv%d HP %d/%d 弱點：%s（+20%% 攻擊）" % [str(inf.get("name", "")),
							int(inf.get("level", 0)), int(inf.get("hp", 0)), int(inf.get("maxHp", 0)),
							wk if wk != "" else "無"], Color(0.7, 0.9, 1.0), 4.5)

		# ---- 登用 (Step 13.5) ----
		"recruit_survey", "recruit_quiz":
			if int(e.dst) == my_id and hud != null and not autotest:
				var rp = hud.panels.get("recruit")
				if rp == null or not rp.visible:
					hud.open_panel("recruit")
		"arena_start":
			if int(e.dst) == my_id:
				target_id = int(e.mob)
				if hud != null:
					hud.close_panels()
				_set_banner("擂台 PK：%s" % str(e.name), Color(1, 0.8, 0.3), 4.0)
		"recruit_result":
			if int(e.dst) == my_id and bool(e.ok):
				_set_banner("登用成功：%s" % str(data.general_by_id.get(int(e.gid), {}).get("name", "")), Color(0.6, 1, 0.6), 5.0)
		"companion_leave":
			if int(e.dst) == my_id:
				_set_banner("%s離開咗（%s）" % [str(e.name), str(e.reason)], Color(1, 0.7, 0.4), 6.0)
		"companion_down":                       # S02c 超渡: 同伴倒下
			if int(e.dst) == my_id and hud != null:
				_set_banner("%s倒低咗！快啲超渡" % str(e.name), Color(1, 0.6, 0.6), 5.0)
		"revive":                               # S02c 超渡: 道士復活同伴/主公（sim 已 _msg, 呢度純通標）
			if int(e.dst) == my_id and hud != null:
				hud.close_panels()              # 若主公自己倒地畫面開緊 → 救返即閂 (自訂新增)
				_set_banner("超渡！%s 起返身" % str(e.name), Color(0.65, 1, 0.65), 4.0)
		"companion_ko":
			if int(e.dst) == my_id and hud != null:
				_set_banner("%s受傷退返客棧休養" % str(e.name), Color(1, 0.7, 0.4), 5.0)
		"day":
			var season := int(e.season)
			if last_season >= 0 and season != last_season:
				_set_banner("入咗%s季" % RulesClock.SEASON_NAMES[season], Color(0.8, 0.9, 0.5), 10.0)
			last_season = season
		"landmark":
			if int(e.dst) == my_id:
				_log("【%s】%s" % [e.name, e.text])
				if hud != null and not hud.any_panel_open() and not autotest and not uitest:
					var nm := str(e.name)
					var tx := str(e.text)
					hud.open_dialog(func() -> Dictionary:
						return {"title": nm, "text": tx, "options": [{"label": "繼續", "cb": func() -> void: hud.close_panels()}]})
		"disaster":
			if str(e.city) == str(data.world["homeCity"]):
				_set_banner("天災：%s (%s)！物資價格波動" % [e.name, e.size], Color(1, 0.55, 0.3), 15.0)
		"scene_open":                       # S04d: 特殊場景開門公告 (game 日曆)
			_set_banner("%s 開門（武等 ≥%d，每月%s）！入口喺荊州港口" % [str(e.name), int(e.minLevel), str(e.openDays)], Color(0.6, 0.95, 0.8), 12.0)
			_log("特殊場景「%s」開門咗！" % str(e.name))
		"scene_enter":
			if int(e.dst) == my_id:
				_log("入咗%s" % str(e.name))
		"scene_win":
			if int(e.dst) == my_id:
				_set_banner("%s通晒！" % str(e.name), Color(0.9, 0.9, 0.5), 6.0)
				_log("%s通晒！" % str(e.name))

# S03c 死亡結算彈窗文案: 跌咗邊啲物品/扣幾多/道具消耗 (spec 03 §4)
func _death_report(e: Dictionary) -> String:
	var lines: Array = ["你死咗，精神返到客棧（HP/MP/SP 回一半）"] if not bool(e.get("down", false)) \
		else ["你死咗，倒喺地上…"]
	if int(e.get("exp_lost", 0)) > 0:
		lines.append("扣經驗 %d" % int(e["exp_lost"]))
	var dn: Array = []
	for it in e.get("dropped", []):
		dn.append(item_names.get(int(it.id), str(it.id)))
	if not dn.is_empty():
		lines.append("跌咗物品：%s" % "、".join(dn))
	if bool(e.get("lucky", false)):
		lines.append("幸運符擋住，冇跌物品（消耗 1）")
	if bool(e.get("huhushen", false)):
		lines.append("護身符令經驗損失減半（消耗 1）")
	if bool(e.get("revived", false)):
		lines.append("還魂丹令你復活返客棧（消耗 1）")
	lines.append("每件裝備耐久扣 10%%")
	return "\n".join(lines)


func _show_quest_dialog(speaker: String, dlg: Array) -> void:
	# UAT point 4: 任務對話要用 DialogBox 彈窗（唔淨止信息欄）；確定先行
	var title := "任務" if speaker == "" else speaker
	var parts: Array = []
	for line in dlg:
		parts.append(str(line))
	var text := "\n".join(parts)
	if hud != null:
		hud.open_dialog(func() -> Dictionary: return {"title": title, "text": text,
			"options": [{"label": "確定", "cb": func() -> void: hud.close_panels()}]})


# 倒地畫面【自訂新增】: 倒數 + 回城/復活丹/同伴超渡掣，source 每 0.2 秒重算 (DialogPanel 機制)
var last_death_report := ""     # 倒地畫面顯示嘅死亡報 (S03: 跌咗乜/扣經驗/耐久)


func _down_dialog() -> Dictionary:
	var dv := sim.player_down_view()
	if dv.is_empty():
		if hud != null:
			hud.close_panels()
		return {}
	var can_self := bool(dv.get("canSelf", false))
	var text := ""
	if last_death_report != "":
		text = last_death_report + "\n──────\n"
	text += "你倒喺地上，%d 秒後強制送返客棧。\n" % int(dv.get("secsLeft", 0))
	if can_self:
		text += "可以撳「回城復活」返客棧。"
	else:
		text += "%d 秒後先可以「回城復活」；呢段時間可以用復活丹，或者等同伴道士超渡。" % int(dv.get("selfInSecs", 0))
	var opts: Array = [
		{"label": "回城復活", "disabled": not can_self,
			"cb": func() -> void: _send({"t": "self_revive"})},
		{"label": "使用復活丹復活", "disabled": not bool(dv.get("hasPill", false)),
			"cb": func() -> void: _send({"t": "revive_pill"})},
	]
	if bool(dv.get("hasChaoduComp", false)):
		opts.append({"label": "叫同伴超渡", "disabled": false,
			"cb": func() -> void: _send({"t": "companion_revive"})})
	return {"title": "倒地（%d 秒）" % int(dv.get("secsLeft", 0)), "text": text, "options": opts}

# 倒地畫面睇門口【自訂新增】: 防止玩家撳遮罩/✕/返回鍵誤閂咗個倒地畫面之後冇得再開 (卡死)。
# 每 tick 檢查: 仲倒地緊、又冇開緊任何面板 → 自動彈返個倒地畫面。
func _down_watchdog() -> void:
	if hud == null or autotest or uitest:
		return
	if not bool(sim.player_down_view().get("down", false)):
		return
	if not hud.any_panel_open():
		hud.open_dialog(_down_dialog)

func _set_banner(text: String, col: Color, secs: float) -> void:
	banner = {"text": text, "t": secs, "color": col}
	_log("【%s】" % text)

func _autotest_step(me: Dictionary) -> void:
	var p := Vector2i(int(me.x), int(me.y))
	if start_pos.x < 0:
		start_pos = p
		_send({"t": "chat", "text": "autotest"}); _send({"t": "rest"}); _send({"t": "buy", "item": 10001, "n": 1})
		for d in [Vector2i(6, 2), Vector2i(-6, 2), Vector2i(6, -2), Vector2i(-6, -2), Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
			if sim.is_free(p.x + d.x, p.y + d.y):     # 出生位由 RNG 定，揀一格行得嘅
				_send({"t": "move", "x": p.x + d.x, "y": p.y + d.y})
				break
	elif not moved:
		if p != start_pos: moved = true; print("moved %s -> %s, saw %d entities" % [start_pos, p, ents.size()])
	else:
		var near = _nearest_mob(me)
		if near != null and int(near.id) != target_id:
			target_id = int(near.id); atk_sent = true
			_send({"t": "attack", "target": target_id})
		elif near == null and target_id < 0:
			_go_field()                                 # 未見到怪: 行入野區
		if kills > 0 and not ch.is_empty() and _exp_total() > exp_start:
			print("PASS: moved, killed %d mob, exp %d -> %d, Lv%d" % [kills, exp_start, _exp_total(), int(ch.level)])
			get_tree().quit(0)

# 行去野區: 喺城入面就行去出城門口 (踩上去自動過圖)；已經喺野區就行去圍場
func _go_field() -> void:
	var me = _me()
	if me == null:
		return
	var here := str(cur_map.get("id", ""))
	if here != Sim.DEFAULT_ZONE:
		var p := sim.next_portal(here, Sim.DEFAULT_ZONE)
		if not p.is_empty():
			_send({"t": "move", "x": int(p.x), "y": int(p.y)})
		return
	var md: Dictionary = data.map_by_id[Sim.DEFAULT_ZONE]
	_send({"t": "move", "x": int(md.ox) + 30 + (int(sim.tick) / 60) % 9, "y": int(md.oy) + 35})

func _nearest_mob(me: Dictionary):
	var best = null; var bd := 1e9
	var here := str(cur_map.get("id", ""))
	for e in ents:
		if not e.get("mob", false) or int(e.get("level", 1)) > 2: continue   # autotest 只打 1~2 級怪，免得 1 級死喺山賊
		if sim.map_id_at(int(e.x), int(e.y)) != here: continue
		var d: float = absf(e.x - me.x) + absf(e.y - me.y)
		if d < bd: bd = d; best = e
	return best

# 附近傳送點 (城門: 城內/城外之間即時傳送)
func _near_travel() -> Dictionary:
	var me = _me()
	if me == null: return {}
	for f in facilities:
		if f.kind == "travel" and maxi(absi(int(me.x) - f.x), absi(int(me.y) - f.y)) <= 3:
			return f
	return {}

# 市場價 = 基準價 × 價格因子；買入另計魅力折扣【原】，賣出 = 市場價 50%
# 城際貿易 (spec 05 §6): city = 商店所在城 (UI 用) → 用嗰城市場 pf；"" = 故鄉城市場代價
func _pf_for(city: String, id: int) -> float:
	var g: Dictionary = {}
	if city != "":
		g = sim.market_city(city, str(int(data.cats.get(id, 0))))
	return float(g.get("pf", 1.0)) if not g.is_empty() else sim.market_factor(id)

func _buy_price(id: int, city := "") -> int:
	var base: float = item_prices.get(id, 0)
	var pf: float = _pf_for(city, id)
	var cha := int(ch.attrs.cha) if not ch.is_empty() else 0
	var trade_lv := sim.expert_lv(ch, "jiaoyi") if not ch.is_empty() and sim != null else 0
	return RulesShop.buy_price(RulesMarket.price(base, pf), cha, 0, trade_lv)

func _sell_price(id: int, city := "") -> int:
	var trade_lv := sim.expert_lv(ch, "jiaoyi") if not ch.is_empty() and sim != null else 0
	return RulesShop.sell_price(item_prices.get(id, 0) * _pf_for(city, id), trade_lv)

func _me():
	return _ent(my_id)

func target_ent():
	if target_id < 0:
		return null
	return _ent(target_id)

# 呢個 entity 可唔可以俾玩家 target/攻擊：怪一律得；NPC(bot) 要打人模式開，或者本身敵對
# (紅名殺人魔 / 鎖定緊自己嘅居民) 先得——保持平時淨見到敵對 NPC 可以反擊，其餘要開返打人模式先亂咁打
func _is_targetable(e) -> bool:
	if e == null:
		return false
	if e.get("mob", false):
		return true
	if not e.get("bot", false):
		return false
	if pk_mode:
		return true
	return bool(e.get("criminal", false)) or int(e.get("atkTarget", 0)) == my_id

# 點怪 = 攻擊；點 NPC/設施 = 行過去自動互動；點地 = 行路（有落點標記）；點自己 = 取消目標
func _hud_tap(pos: Vector2) -> void:
	if hud != null and hud.any_panel_open():
		return
	var g: Vector2 = ((pos + cam) / TILE).floor()
	pending = {}
	var me = _me()
	if me != null and int(g.x) == int(me.x) and int(g.y) == int(me.y):
		target_id = -1                            # 點自己 = 取消目標
		return
	# 怪/可攻擊 NPC 優先（戰鬥中最常撳）
	var e = _ent_at(g)
	if e == null or not _is_targetable(e):
		e = _targetable_near_tap(pos)              # 手指粗: 容許 tap 埋隔籬格都算中
	if e != null and _is_targetable(e):
		target_id = int(e.id)
		_send({"t": "attack", "target": target_id})
		return
	# 任務 NPC / 設施: 近就即刻互動，遠就行過去再開 (三國群英傳M 點 NPC 自動尋路)
	var it := _interactable_at(g)
	if not it.is_empty():
		if me != null and ContextActions._near(me, int(it.ref.x), int(it.ref.y)):
			ContextActions.run(self, it)
		else:
			pending = it
			_send({"t": "move", "x": int(it.ref.x), "y": int(it.ref.y)})
			marker = {"pos": Vector2(int(it.ref.x), int(it.ref.y)), "t": 1.0}
		return
	# S04a 地面掉落物: 撳落地物件 → 近就即拾取；遠就（點擊模式）行埋邊執
	var dd = _drop_at_tap(pos, g)
	if dd != null:
		if me != null and ContextActions._near(me, int(dd.x), int(dd.y)):
			_send({"t": "pick", "drop": int(dd.id)})
		elif move_mode == "tap":
			_send({"t": "move", "x": int(dd.x), "y": int(dd.y)})
			marker = {"pos": Vector2(int(dd.x), int(dd.y)), "t": 1.0}
		return
	# 撳地行路 (點擊模式先得; 搖桿模式 = 撳地唔郁，避免同搖桿互夹扰)
	if move_mode != "tap":
		return
	if not sim.is_free(int(g.x), int(g.y)):           # 撳中屋/樹/河: 行去最近行得嘅格
		var f := _free_near(Vector2i(g), 2)
		if f.x < 0:
			return
		g = Vector2(f)
	_send({"t": "move", "x": int(g.x), "y": int(g.y)})
	marker = {"pos": g, "t": 1.0}

func _free_near(c: Vector2i, rmax: int) -> Vector2i:
	for r in range(1, rmax + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and sim.is_free(c.x + dx, c.y + dy):
					return Vector2i(c.x + dx, c.y + dy)
	return Vector2i(-1, -1)

# tap 格仔係咪 NPC/設施（設施佔 3x3，NPC 容許隔籬 1 格）→ ContextActions 格式
func _interactable_at(g: Vector2) -> Dictionary:
	for qn in quest_npcs:
		if absi(int(g.x) - int(qn.x)) <= 1 and absi(int(g.y) - int(qn.y)) <= 1:
			return {"kind": "quest_npc", "label": "對話", "ref": qn}
	for gn in generals:
		if absi(int(g.x) - int(gn.x)) <= 1 and absi(int(g.y) - int(gn.y)) <= 1:
			return {"kind": "general", "label": "人才", "ref": gn}
	for f in facilities:
		if absi(int(g.x) - int(f.x)) <= 1 and absi(int(g.y) - int(f.y)) <= 1:
			return {"kind": String(f.kind), "label": "", "ref": f}
	return {}

# 每幀 UI 雜務: 行到 pending 目標就開、任務答題自動彈對話框、落點標記淡出
func _ui_tick(delta: float) -> void:
	marker["t"] = maxf(0.0, float(marker["t"]) - delta * 1.5)
	if hud == null or hud.any_panel_open():
		return
	var me = _me()
	if not pending.is_empty() and me != null:
		if hud.joy_active():
			pending = {}
		elif ContextActions._near(me, int(pending.ref.x), int(pending.ref.y)):
			var it := pending
			pending = {}
			ContextActions.run(self, it)
	var ask := ask_now
	var key := "%s:%d" % [ask.get("q", ""), int(ask.get("stage", 0))]
	if not ask.is_empty() and key != _ask_seen and not hud.any_panel_open():
		_ask_seen = key
		ContextActions.run(self, {"kind": "ask"})

# 切換目標: 附近怪(+打人模式下嘅 NPC)按距離排，揀下一隻（唔會即刻打，撳攻擊先打）
func _cycle_target() -> void:
	var me = _me()
	if me == null:
		return
	var mobs: Array = []
	for e in ents:
		if _is_targetable(e) and absf(e.x - me.x) + absf(e.y - me.y) <= TARGET_RANGE:
			mobs.append(e)
	if mobs.is_empty():
		_log("附近冇怪")
		return
	mobs.sort_custom(func(a, b): return absf(a.x - me.x) + absf(a.y - me.y) < absf(b.x - me.x) + absf(b.y - me.y))
	var i := 0
	for k in mobs.size():
		if int(mobs[k].id) == target_id:
			i = (k + 1) % mobs.size()
	target_id = int(mobs[i].id)

# 技能扇形: 術書空格 = 開背包揀術書（唔會自動裝）；有書 = 施法；絕招 = 用
func _on_skill(sl: Dictionary) -> void:
	if String(sl["kind"]) == "spell":
		if int(sl["item"]) == 0:
			hud.close_panels()
			hud.bag_panel().open_filter("spell", int(sl["slot"]))
			return
		var t = target_ent()
		var tgt := int(t.id) if t != null and bool(t.get("mob", false)) else 0
		_send({"t": "cast_spell", "slot": int(sl["slot"]), "target": tgt})
		return
	if String(sl["kind"]) == "skill":           # S02c 職業特技掣: 而家得開鎖（sim 會檢查附近有冇鎖寶箱）
		_send({"t": "use_skill", "skill": String(sl["skill"])})
		return
	if String(sl["kind"]) == "mount":           # U02 馬戰特技掣
		var t = target_ent()
		var tgt := int(t.id) if t != null and bool(t.get("mob", false)) else 0
		_send({"t": "mount_skill_use", "skill": String(sl["skill"]), "target": tgt})
		return
	if String(sl["ult"]) == "":
		_log("未學絕招 (絕招任務: 練兵場門口禁衛大隊長)")
		return
	_send({"t": "use_ultimate", "ult": String(sl["ult"])})

var _class_caps := {}               # classId -> {spells, ults} (HUD 每幀問，按職業快取)

func _class_cap(k: String) -> bool:
	var cid := str(ch.get("classId", ""))
	if not _class_caps.has(cid):
		var sp_ok := false
		for sp in data.spells:
			if (sp["classes"] as Array).has(cid):
				sp_ok = true
				break
		var ult_ok := false
		for u in data.ultimates:
			if str(u["class"]) == cid:
				ult_ok = true
				break
		_class_caps[cid] = {"spells": sp_ok, "ults": ult_ok}
	return bool(_class_caps[cid][k])

func class_has_spells() -> bool:
	return _class_cap("spells")

func class_has_ults() -> bool:
	return _class_cap("ults")

# Android 返回鍵: 有面板就關面板（唔會一撳就退出遊戲）
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and hud != null and hud.any_panel_open():
		hud.close_panels()

# 容錯: tap 座標喺呢個範圍內揀最近嘅怪 (~1.8 格 ≈ 手指闊), 唔使準確咁啱格先郁到手
const TAP_TOLERANCE := TILE * 1.8
func _targetable_near_tap(pos: Vector2):
	var world_pos: Vector2 = pos + cam
	var best = null
	var best_d := TAP_TOLERANCE
	for e in ents:
		if not _is_targetable(e):
			continue
		var center: Vector2 = Vector2(e.x, e.y) * TILE + Vector2(TILE, TILE) * 0.5
		var d: float = world_pos.distance_to(center)
		if d < best_d:
			best_d = d
			best = e
	return best

# S04a: 撳嗰格係咪地面掉落物 (隔籬格都算中，同 _targetable_near_tap 一樣容差)
func _drop_at_tap(pos: Vector2, g: Vector2):
	var world_pos: Vector2 = pos + cam
	var best = null
	var best_d := TAP_TOLERANCE
	for e in ents:
		if not e.get("dropped", false):
			continue
		# 玩家撳正嗰格 = 直接命中；隔籬格用距離容差 (手指粗)
		if int(e.x) == int(g.x) and int(e.y) == int(g.y):
			return e
		var center: Vector2 = Vector2(e.x, e.y) * TILE + Vector2(TILE, TILE) * 0.5
		var d: float = world_pos.distance_to(center)
		if d < best_d:
			best_d = d
			best = e
	return best

func _hud_attack() -> void:
	if auto:
		auto = false
		hud.set_auto(false)
	var t = target_ent()
	if t != null and _is_targetable(t):
		_send({"t": "attack", "target": target_id})
		return
	var me = _me()
	if me == null:
		return
	var near = _pick_mob(me, false)            # 手動: 就咁打最近
	if near != null:
		target_id = int(near.id)
		_send({"t": "attack", "target": target_id})
	else:
		_log("附近冇怪")

func _hud_auto(v: bool) -> void:
	auto = v
	_log("自動掛機 %s" % ("開" if v else "關"))

func _toggle_auto() -> void:
	if hud != null:
		hud.set_auto(not hud.auto)
		_hud_auto(hud.auto)

# 搖桿持續移動: 每 tick 將目標點推前 2~4 格（揀第一個空格），放手自然停
func _steer_tick() -> void:
	if hud == null or not hud.joy_active():
		return
	var d := hud.joy_dir()
	var me = _me()
	if me == null or d == Vector2.ZERO:
		return
	if auto:
		auto = false
		hud.set_auto(false)
		_log("自動已關（手動移動）")
	var p := Vector2i(int(me.x), int(me.y))
	for k in [4, 3, 2]:
		var t := Vector2i(p.x + int(round(d.x * k)), p.y + int(round(d.y * k)))
		t.x = clampi(t.x, 0, w - 1)
		t.y = clampi(t.y, 0, h - 1)
		if sim.is_free(t.x, t.y):
			_send({"t": "move", "x": t.x, "y": t.y})
			return

# 自動掛機: 打最近唔高太多級嘅怪；冇怪就間中行去野區
func _auto_tick() -> void:
	if not auto:
		return
	var me = _me()
	if me == null:
		return
	var t = target_ent()
	var near = _pick_mob(me, true)
	if t != null and _is_targetable(t):
		# 貼身 / 打緊我 → 繼續打；否則有更近嘅就轉 (例如目標逃走咗)
		if _mob_dist(me, t) <= 1 or int(t.get("aggro", 0)) == int(me.id):
			return
		if near == null or int(near.id) == target_id or _mob_dist(me, near) >= _mob_dist(me, t):
			return                              # sim 自己追梗
	if near != null:
		target_id = int(near.id)
		_send({"t": "attack", "target": target_id})
		return
	if auto_roam and int(sim.tick) % FIELD_RETRY_TICKS == 0:
		_go_field()

# 揀怪: 只揀同自己同一 zone (洞窟各層座標同野外相鄰，唔可以隔層鎖)；
# 打緊我嘅怪優先 (唔理等級)；其次最近 (Chebyshev = 實際步數，同距離再比 Manhattan)
# safe_only: 跳過高自己兩級以上嘅怪 (掛機用)
func _pick_mob(me: Dictionary, safe_only: bool):
	var my_zone := str(sim.zone_view(int(me.x), int(me.y)).get("id", ""))
	var best = null
	var bd := 1e9
	for e in ents:
		if not _is_targetable(e) or int(e.hp) <= 0:
			continue
		if str(sim.zone_view(int(e.x), int(e.y)).get("id", "")) != my_zone:
			continue
		if safe_only and e.get("mob", false) and not auto_whitelist.is_empty() and not auto_whitelist.has(str(e.name)):
			continue                            # 自動掛機白名單: 冇揀嘅怪唔自動打 (打人模式 NPC 唔受白名單限制)
		var attacking := int(e.get("aggro", 0)) == int(me.id)
		if safe_only and not attacking and int(e.level) > int(ch.level) + 1:
			continue                            # 唔主動打高自己兩級以上嘅怪
		var dist: float = _mob_dist(me, e) * 1000.0 + absf(e.x - me.x) + absf(e.y - me.y)
		if attacking:
			dist -= 1e6                         # 反擊優先
		if dist < bd:
			bd = dist
			best = e
	return best

func _mob_dist(a: Dictionary, b: Dictionary) -> int:
	return maxi(absi(int(a.x) - int(b.x)), absi(int(a.y) - int(b.y)))

func _ent(id: int):
	return ent_by_id.get(id)

func _ent_at(g: Vector2):
	for e in ents:
		if int(e.x) == int(g.x) and int(e.y) == int(g.y): return e
	return null


# S03a: 長按位置附近格嘅居民 (bot) → 出「攻擊」menu (二次確認)。
# 短按照正常 tap (行路/打怪)；長按唔係撳中居民就照做 normal tap。
func _handle_long_press(pos: Vector2) -> void:
	var g := (pos + cam) / TILE
	var gx := int(floor(g.x))
	var gy := int(floor(g.y))
	var hit: Dictionary = {}
	for e in ents:
		if not bool(e.get("bot", false)):
			continue
		if absi(int(e.x) - gx) <= 1 and absi(int(e.y) - gy) <= 1:
			hit = e
			break
	if hit.is_empty():
		_hud_tap(pos)                 # 唔係居民: 當普通 tap
		return
	_open_npc_attack(hit)


# S03a: 長按居民 → 攻擊 menu + 二次確認。安全區照禁 (sim 出手前都擋, 呢度 UI 都灰)。
func _open_npc_attack(ev: Dictionary) -> void:
	var me = _me()
	var safe: bool = me != null and sim.is_safe(int(me.x), int(me.y))
	var red := bool(ev.get("criminal", false))
	var tid := int(ev.id)
	var name := str(ev.get("name", "居民")) + ("　［紅名·殺人魔］" if red else "")
	var effect := ("除害善惡 +300" if red else "做衰嘢，善惡一次過 -1000")
	var warn := "城內（安全區）唔可以攻擊居民。" if safe else "攻擊佢？殺害居民會被視為罪案（%s）。" % effect
	var opts: Array = [
		{"label": "攻擊…", "disabled": safe, "cb": func() -> void:
			hud.open_dialog(func() -> Dictionary: return {
				"title": "確定攻擊？", "text": "殺害居民會損善惡，附近居民都會記得你。\n%s" % name, "options": [
					{"label": "確定攻擊", "cb": func() -> void:
						target_id = tid
						_send({"t": "attack", "target": tid})
						hud.close_panels()},
					{"label": "取消", "cb": func() -> void: hud.close_panels()}]})}]
	if not red:
		opts.append({"label": "遊說（義勇軍）", "cb": func() -> void:
			_send({"t": "militia_invite", "npc": tid})
			hud.close_panels()})
	opts.append({"label": "離開", "cb": func() -> void: hud.close_panels()})
	hud.open_dialog(func() -> Dictionary: return {"title": name, "text": warn, "options": opts})

# 測試功能: 「更多」面板 + 桌面鍵盤共用（成品前換走；倉庫已搬去背包面板）
func _on_debug_pressed(action: String) -> void:
	match action:
		"greet": _send({"t": "chat", "text": "大家好"})
		"use":
			if not ch.is_empty():
				var food := DEBUG_FOOD                       # debug: 唔理背包原本有咩，直接派一件試食
				_send({"t": "debug_give", "item": food, "n": 1})
				_send({"t": "use_item", "item": food})
		"work_mining":
			var sk: Dictionary = data.work.get("mining", {})
			if not sk.is_empty() and (ch.get("tools", {}) as Dictionary).get("mining", {}).is_empty():
				var tool := int(sk["starterTool"])          # debug: 冇工具就直接派新手工具落背包再裝備
				_send({"t": "debug_give", "item": tool, "n": 1})
				_send({"t": "equip_tool", "skill": "mining", "item": tool})
			_send({"t": "work", "skill": "mining"})
		"work_lv": _send({"t": "debug_work_lv", "add": 10})    # debug: 生產技能 +10 級 (Step 12)
		"level_up": _send({"t": "debug_level", "n": 1})        # debug: 一鍵升 1 級
		"level_up10": _send({"t": "debug_level", "n": 10})     # debug: 一鍵升 10 級
		"speed":                                               # debug: 時間加速 1→4→16→64→1
			debug_speed = {1: 4, 4: 16, 16: 64}.get(debug_speed, 1)
		"learn_ults":
			# debug (S02c): 依家職業學晒初階三招絕招（任務鏈喺 S06d）
			if not ch.is_empty():
				var cid := str(ch.get("classId", ""))
				var n := 0
				for u in data.ultimates:
					if String(u["class"]) == cid and int(u.get("tier", 9)) <= 3:
						_send({"t": "debug_learn", "kind": "ult", "what": String(u["id"])})
						n += 1
				if n == 0:
					_log("你嘅職業暫時冇初階絕招")
		"learn_skill":
			# debug (S02c): 學職業特技（導師任務同屆）
			if not ch.is_empty():
				var cid := str(ch.get("classId", ""))
				var sid := ""
				for sk in data.class_skills:
					if String(data.class_skills[sk].get("class", "")) == cid:
						sid = String(sk)
						break
				if sid == "":
					_log("你嘅職業暫時冇特技")
				else:
					_send({"t": "debug_learn", "kind": "skill", "what": sid})


func _unhandled_input(ev: InputEvent) -> void:
	if hud != null and hud.any_panel_open():
		return                                     # 面板開住: 唔做世界點擊/快捷鍵
	# 逐個事件判斷: 觸控 = ScreenTouch；由觸控模擬出嚟嘅 mouse 事件忽略（避免雙重處理）
	# （唔用 Input.is_emulating_mouse_from_touch(): 4.7 桌面都回 true）
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touch_at = Time.get_ticks_msec()      # S03a: 記低 down 時刻做長按偵測
			_touch_pos = ev.position
		else:
			var held := Time.get_ticks_msec() - _touch_at
			if held >= LONG_PRESS_MS:              # 長按: 對 NPC 出「攻擊」menu
				_handle_long_press(ev.position)
			else:                                  # 短按: 正常 tap
				_hud_tap(ev.position)
		return
	if ev is InputEventMouse and ev.device == InputEvent.DEVICE_ID_EMULATION:
		return
	# 桌面快捷鍵（debug）: 背包/角色/記事/互動 開正式面板；唔再有「自動揀第一件」嘅鍵
	if ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_B: hud.bag_panel().open_filter("")
		elif ev.keycode == KEY_C: hud.open_panel("char")
		elif ev.keycode == KEY_J: hud.open_panel("quest")
		elif ev.keycode == KEY_SPACE:
			var act := ContextActions.find(self)
			if not act.is_empty(): ContextActions.run(self, act)
		elif ev.keycode == KEY_TAB: _cycle_target()
		elif ev.keycode == KEY_R: _send({"t": "rest"})                                   # 客棧休息
		elif ev.keycode == KEY_H: _on_debug_pressed("greet")
		elif ev.keycode == KEY_G:
			var tp = _near_travel()
			if not tp.is_empty(): _send({"t": "travel", "point": String(tp["point"])})
		elif ev.keycode == KEY_T: _send({"t": "facility", "key": "training"})
		elif ev.keycode == KEY_P: _send({"t": "facility", "key": "school"})
		elif ev.keycode == KEY_M: _send({"t": "facility", "key": "temple"})
		elif ev.keycode == KEY_L and not ch.is_empty():            # 絕招 (最新學嗰招)
			var ults: Array = ch.get("ultimates", [])
			if ults.is_empty():
				_log("未學任何絕招")
			else:
				_send({"t": "use_ultimate", "ult": str(ults[ults.size() - 1])})
		elif ev.keycode == KEY_N and not ch.is_empty():             # 融合: 開始 / 敲實 (打鐵鋪)
			if (ch.get("fusing", {}) as Dictionary).is_empty():
				_send({"t": "fusion_start"})
			else:
				_send({"t": "fusion_hit"})
		elif ev.keycode == KEY_W: _on_debug_pressed("work_mining")
		elif ev.keycode == KEY_Z and not ch.is_empty() and ch.has("equip"):   # 施法: 快捷列 1 (Step 9)
			var tgt := target_id if target_id >= 0 else 0
			_send({"t": "cast_spell", "slot": 0, "target": tgt})
		elif ev.keycode == KEY_Q: _send({"t": "auto_assign"})
		elif ev.keycode == KEY_E: _send({"t": "raise_attr", "attr": "str"})
		elif ev.keycode == KEY_F: _send({"t": "raise_attr", "attr": "agi"})
		elif ev.keycode == KEY_D: _send({"t": "raise_attr", "attr": "int"})
		elif ev.keycode == KEY_S: _send({"t": "raise_attr", "attr": "spi"})
		elif ev.keycode == KEY_U: _on_debug_pressed("use")
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			_hud_tap(ev.position)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			_toggle_auto()

func _bar(pos: Vector2, size: Vector2, ratio: float, col: Color) -> void:
	draw_rect(Rect2(pos, size), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(pos, Vector2(size.x * clampf(ratio, 0.0, 1.0), size.y)), col)

func _txt(pos: Vector2, s: String, col := Color.WHITE, sz := FONT_SZ) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.04, 0.05))
	if not cur_map.is_empty():
		var tex := MapArt.texture(data, cur_map, TILE)
		var mod := (Color(0.8, 0.8, 0.86) if beast_light else Color(0.5, 0.5, 0.62)) if night_on else Color.WHITE      # 夜景
		draw_texture(tex, Vector2(int(cur_map.ox), int(cur_map.oy)) * TILE - cam, mod)
	for f in facilities:
		_draw_sign(f)
	var mr := Rect2i(int(cur_map.get("ox", 0)), int(cur_map.get("oy", 0)), int(cur_map.get("w", Sim.W)), int(cur_map.get("h", Sim.H)))
	for e in ents:
		if not mr.has_point(Vector2i(int(e.x), int(e.y))):
			continue                                  # 其他地圖嘅單位唔畫
		var p := Vector2(e.x, e.y) * TILE - cam
		var isme: bool = int(e.id) == my_id
		var ismob: bool = e.get("mob", false)
		# S04b 吟唱線索: 術法怪 / boss 吟唱緊 → 落點紅圈 + 怪身框，玩家睇到走位拍
		if ismob and bool(e.get("casting", false)):
			var lx := int(e.get("castX", int(e.x)))
			var ly := int(e.get("castY", int(e.y)))
			if mr.has_point(Vector2i(lx, ly)):
				var cc := Vector2(lx, ly) * TILE - cam + Vector2(TILE, TILE) * 0.5
				var cr := float(TILE) * 1.35
				draw_circle(cc, cr, Color(1.0, 0.38, 0.28, 0.18))
				draw_circle(cc, cr * clampf(float(e.get("castProg", 0.0)), 0.05, 1.0), Color(1.0, 0.25, 0.15, 0.35))   # 漸滿: 由內向外填
				draw_arc(cc, cr, 0.0, TAU, 32, Color(1.0, 0.3, 0.2, 0.8), 2.0)
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(TILE + 4, TILE + 4)), Color(1.0, 0.5, 0.4), false, 2.0)
		if e.get("dropped", false):                     # S04a 地面掉落物: 小袋圖示 + 件數
			draw_rect(Rect2(p + Vector2(4, 12), Vector2(16, 10)), Color(0.85, 0.7, 0.35))
			draw_rect(Rect2(p + Vector2(7, 6), Vector2(10, 7)), Color(0.6, 0.5, 0.22))
			draw_rect(Rect2(p + Vector2(4, 12), Vector2(16, 10)), Color(0.2, 0.15, 0.05), false, 1.0)
			var n := 0
			for it in e.get("dropItems", []):
				n += int(it.get("n", 1))
			_txt(p + Vector2(-2, 4), "×%d" % n, Color(1, 0.95, 0.6), 11)
			continue
		if ismob:
			if not _draw_mon_sprite(e, p):
				draw_rect(Rect2(p, Vector2(TILE, TILE)), Color(0.8, 0.25, 0.2))    # 怪物色塊 (冇原版動畫圖)
		else:
			if isme:
				_draw_my_mount(p)                     # 座騎 (Step 17a): 騎緊 = 墊喺腳底，跟身 = 企隔籬
			var f = faces[int(e.face) % faces.size()] if faces.size() > 0 else null
			if _draw_mon_sprite(e, p): pass
			elif f != null: draw_texture_rect(f, Rect2(p - Vector2(4, 8), Vector2(24, 26)), false)
			else: draw_rect(Rect2(p, Vector2(TILE, TILE)), Color.RED if isme else Color.ORANGE)
			if isme: draw_rect(Rect2(p - Vector2(4, 8), Vector2(24, 26)), Color.YELLOW, false, 2.0)
		var isgen: bool = e.get("gen", false)
		if e.has("hp") and e.has("maxHp") and (ismob or isme or isgen):
			_bar(p + Vector2(-2, -14), Vector2(20, 3), float(e.hp) / float(e.maxHp), Color(0.9, 0.2, 0.2) if ismob else Color(0.3, 0.8, 0.3))
		if int(e.id) == target_id:
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(TILE + 4, TILE + 4)), Color.CYAN, false, 2.0)
		var nm := str(e.name) + (" Lv%d" % int(e.level) if ismob else "")
		if not (e.get("statuses", []) as Array).is_empty():
			var tags: Array = []
			for sid in e["statuses"]:
				tags.append(STATUS_NAMES.get(str(sid), str(sid)))
			nm += " [%s]" % str(",".join(tags))
		if bool(e.get("casting", false)):
			nm += "（吟唱中）"
		if isgen:
			nm = "【同伴】" + nm
		# S03a: 紅名(殺人魔)居民 = 紅字表示（居民警告話你知佢係殺人魔）
		var nc := Color(1, 0.32, 0.32) if bool(e.get("criminal", false)) else Color(1, 0.7, 0.6) if ismob else Color(0.6, 1, 0.65) if isgen else Color.WHITE
		_txt(p + Vector2(-8, -18), nm, nc, 11)
	for qn in quest_npcs:
		if not mr.has_point(Vector2i(int(qn.x), int(qn.y))):
			continue
		var qp := Vector2(int(qn.x), int(qn.y)) * TILE - cam
		var qcol := Color(0.45, 0.75, 1.0) if not bool(qn.service) else Color(0.5, 1.0, 0.5)
		var qnpc_art := _draw_idle_actor(str(qn.name), str(qn.name).hash() & 0xffff, qp)
		if not qnpc_art:
			draw_rect(Rect2(qp - Vector2(2, 2), Vector2(TILE + 4, TILE + 4)), qcol, false, 2.0)
			draw_circle(qp + Vector2(TILE, TILE) * 0.5, 6, Color(0.1, 0.25, 0.45, 0.9))
		_txt(qp + Vector2(-6, -20), "!" if not bool(qn.service) else "+", Color(1, 0.9, 0.3), 12)
		_txt(qp + Vector2(-8, -32), str(qn.name), qcol, 11)
	for gn in generals:                             # Tier1 武將 (Step 13.5): 框色 = 武將橙紅 / 文官金 (名唔加字，隔 3 格會撞)
		if not mr.has_point(Vector2i(int(gn.x), int(gn.y))):
			continue
		var gp := Vector2(int(gn.x), int(gn.y)) * TILE - cam
		var gcol := Color(1.0, 0.55, 0.35) if str(gn.type) == "wu" else Color(1.0, 0.82, 0.3)
		var gf = faces[int(gn.id) % faces.size()] if faces.size() > 0 else null
		if _draw_idle_actor(str(gn.name), int(gn.id), gp):
			pass
		elif gf != null:
			draw_texture_rect(gf, Rect2(gp - Vector2(4, 8), Vector2(24, 26)), false)
		else:
			draw_rect(Rect2(gp, Vector2(TILE, TILE)), Color(0.6, 0.45, 0.15))
		draw_rect(Rect2(gp - Vector2(5, 9), Vector2(26, 28)), gcol, false, 2.0)
		_txt(gp + Vector2(-4, -12), str(gn.name), gcol, 11)
	for f in floats:
		var fp: Vector2 = f.pos - cam + Vector2(2, -20 - 24 * f.age)
		_txt(fp, f.text, f.color, 14)
	if float(marker["t"]) > 0.0:                   # 點地落點標記（縮細 + 淡出）
		var mc: Vector2 = marker["pos"] * TILE + Vector2(TILE, TILE) * 0.5 - cam
		var k := float(marker["t"])
		draw_arc(mc, 4.0 + 10.0 * k, 0, TAU, 24, Color(1, 0.9, 0.4, k), 2.0)
	_draw_banner(vs)

# 座騎佔位圖 (色塊 = 品種顏色；成品前換 sprite)
func _draw_my_mount(p: Vector2) -> void:
	for m in ch.get("mounts", []):
		if String(m["where"]) != "with":
			continue
		var col: Array = RulesMount.breed_def(data.mounts, String(m["breed"])).get("color", [0.5, 0.35, 0.2])
		var c := Color(float(col[0]), float(col[1]), float(col[2]))
		if bool(ch.get("riding", false)):
			draw_rect(Rect2(p + Vector2(-8, 8), Vector2(32, 11)), c)                 # 馬身
			draw_rect(Rect2(p + Vector2(20, 2), Vector2(8, 9)), c)                   # 馬頭
			for lx in [-6, 0, 14, 20]:
				draw_rect(Rect2(p + Vector2(lx, 19), Vector2(3, 6)), c.darkened(0.3))  # 馬腳
			draw_rect(Rect2(p + Vector2(-8, 8), Vector2(32, 11)), Color(0, 0, 0, 0.6), false, 1.0)
		else:
			var q := p + Vector2(18, 6)
			draw_rect(Rect2(q, Vector2(16, 8)), c)
			draw_rect(Rect2(q + Vector2(13, -5), Vector2(5, 6)), c)
			for lx in [1, 11]:
				draw_rect(Rect2(q + Vector2(lx, 8), Vector2(2, 5)), c.darkened(0.3))
			draw_rect(Rect2(q, Vector2(16, 8)), Color(0, 0, 0, 0.6), false, 1.0)
		return


# 設施招牌: 門口一格框 + 上面招牌 (屋已經畫喺地圖貼圖)
func _draw_sign(f: Dictionary) -> void:
	var fp := Vector2(f.x, f.y) * TILE - cam
	var vs := get_viewport_rect().size
	if fp.x < -80 or fp.y < -40 or fp.x > vs.x + 80 or fp.y > vs.y + 40:
		return
	var col: Color = f.color
	draw_rect(Rect2(fp, Vector2(TILE, TILE)), Color(col, 0.35))
	draw_rect(Rect2(fp, Vector2(TILE, TILE)), col, false, 1.5)
	var nm := str(f.name)
	var tw := ThemeDB.fallback_font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var r := Rect2(fp + Vector2(TILE / 2.0 - tw / 2.0 - 4, -18), Vector2(tw + 8, 15))
	draw_rect(r, Color(0.12, 0.08, 0.05, 0.85))
	draw_rect(r, col, false, 1.0)
	_txt(r.position + Vector2(4, 12), nm, Color(1, 0.93, 0.75), 11)

# 天災/季節橫幅 (頂中，目標框下)
func _draw_banner(vs: Vector2) -> void:
	if float(banner["t"]) <= 0 or str(banner["text"]) == "":
		return
	var col: Color = banner.get("color", Color(1, 0.55, 0.3))
	# 位置: 日誌右邊 ~ 自動掣左邊之間 (唔好壓住頭像框/選單/小地圖)
	var sr: Rect2 = hud.safe_rect() if hud != null else Rect2(Vector2.ZERO, vs)
	var lr := HudLayout.log_rect(sr)
	var right := sr.end.x - 60.0
	if hud != null and hud.layout.has("auto"):
		right = float(hud.layout["auto"]["c"].x) - float(hud.layout["auto"]["r"]) - 6.0
	var left := lr.end.x + 6.0
	if hud != null and not comp.is_empty() and hud.layout.has("companion"):
		left = (hud.layout["companion"]["rect"] as Rect2).end.x + 6.0
	var text := str(banner["text"])
	var sz := 13
	var tw := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	if tw + 20 > right - left:
		sz = 11
		tw = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var bw := minf(tw + 20, right - left)
	var r := Rect2((left + right - bw) / 2.0, lr.position.y, bw, 24)
	var a := clampf(float(banner["t"]), 0.0, 1.0)          # 最後 1 秒淡出
	draw_rect(r, Color(0, 0, 0, 0.75 * a))
	draw_rect(r, Color(col, a), false, 1.5)
	_txt(r.position + Vector2(10, 17), text, Color(1, 1, 1, a), sz)


# ===== 任務答題 (ask stage, Step 10 絕招任務) =====
func _active_ask() -> Dictionary:
	return ask_now


func _calc_active_ask() -> Dictionary:
	if ch.is_empty():
		return {}
	for q in data.quests:
		if not (ch.get("quests", {}) as Dictionary).has(String(q["id"])):
			continue
		var st: Dictionary = ch["quests"][String(q["id"])]
		if bool(st.get("done", false)):
			continue
		var stage := RulesQuest.stage_of(ch, q)
		if not stage.is_empty() and String(stage.get("type", "")) == "ask":
			return {"q": str(q["id"]), "stage": int(st.get("stage", 0)), "dialog": stage.get("dialog", []), "options": stage.get("options", [])}
	return {}


# 快捷補品欄 (U-fix): 撳格即用嗰件補品，冇貨就出返 log 提示
func use_potion(slot: int) -> void:
	if slot < 0 or slot >= potion_slots.size():
		return
	var id := int(potion_slots[slot])
	if id == 0:
		_log("呢格快捷欄未裝補品，去背包長按補品揀「裝入快捷欄」。")
		return
	var have := false
	for b in ch.get("bag", []):
		if int(b["id"]) == id and int(b["n"]) > 0:
			have = true
			break
	if not have:
		_log("背包冇%s喇" % item_name_for_potion(id))
		return
	_send({"t": "use_item", "item": id})


func item_name_for_potion(id: int) -> String:
	return str(item_names.get(id, "補品"))


# 建角面板完成（mobile_hud)_on_create_done 用
func _on_create_done() -> void:
	_log("建角完成，出發！")


# 存返而家用緊嗰個角色位（cur_slot==0 = AUTOSLOT，向下兼容；否則存去嗰個 slot）
func _save_current() -> void:
	if cur_slot == 0:
		SaveSys.autosave(sim)
	else:
		SaveSys.save_slot(sim, cur_slot)


# ---- 切換/開新角色位 (U-fix: 「更多」面板嘅「切換角色」入口) ----
# n=0 keep 用返 AUTOSLOT；n>=1 = 用 SaveSys slot_path(n)。is_new=true 就唔 load，直接開新角。
func switch_to_slot(n: int, is_new: bool) -> void:
	if not awaiting_slot_pick:
		_save_current()   # 現有進度先存返落佢自己嗰個 slot（開場首次揀 slot 冇「現有進度」，唔使存）
	awaiting_slot_pick = false
	cur_slot = n
	sim = Sim.new(data, 1 if autotest or uitest else randi())
	var fresh := true
	if not is_new and n >= 1 and SaveSys.slot_exists(n):
		var loaded := SaveSys.read_slot(data, n)
		if loaded != null:
			sim = loaded
			fresh = false
			my_id = int(sim.state["player_id"])
	if fresh:
		sim.init_mobs()
		sim.add_residents()
		sim.add_guards()
		my_id = sim.spawn_player("玩家")
	sim.event_emitted.connect(_on_event)
	target_id = -1
	exp_start = -1
	_place_key = ""
	_refresh()
	hud.close_panels()
	if fresh:
		hud.open_panel("create")
	if n >= 1:
		SaveSys.save_slot(sim, n)
