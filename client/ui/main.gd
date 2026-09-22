extends Node2D
# UI: 內嵌單機 sim (sim/sim.gd)，畫格仔地圖同單位、點擊行路、戰鬥 (右鍵切戰鬥游標 → 左鍵點怪)、HUD、背包。
# UI 只透過 sim.cmd_* 發意圖、event_emitted 收事件、view_ents()/player_ch() 讀狀態。
# 命令行: --autotest 端到端: 入場 → 行路 → 攻擊最近怪 → 怪死 → 經驗增加 → print PASS 退出 (加速跑 sim)

const TILE := 16
const TICK := 0.1                 # sim 10Hz
const AUTOTEST_STEPS := 20        # autotest 每幀跑幾多 tick
const FACE_DIR := "res://assets_placeholder/faces/"   # 原版頭像佔位: 私人測試，成品前換走
const FONT_SZ := 12

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
var t0 := 0.0
var start_pos := Vector2i(-1, -1)
var moved := false
var target_id := -1
var hud: MobileHud                # 手機操控層 (ui/touch/mobile_hud.gd)
var auto := false                 # 自動掛機
var sshot_file := ""             # --sshot: 開場幾秒後截圖存 user:// 退出
var ch := {}                      # 玩家角色狀態 (sim 內同一個 Dictionary)
var item_names := {}              # id -> 名 (items.json)
var floats := []                  # 傷害數字 {pos, text, color, age}
var log_lines := []
var show_bag := false
var exp_start := -1
var atk_sent := false
var kills := 0
var facilities := []              # 設施 {kind, name, x, y, color, fac}
var item_prices := {}             # id -> 價錢
var inn_cost := 0
var shop_stock := []              # 武器店貨單 (data/shops.json)
var clock_str := ""               # 時辰/日/季節 (sim.clock_view)
var night_on := false
var last_season := -1
var banner := {"text": "", "t": 0.0}   # 天災/季節橫幅
var last_save_tick := 0

func _ready() -> void:
	autotest = "--autotest" in OS.get_cmdline_user_args()
	for i in 12:
		var p := "%sface_%d.jpg" % [FACE_DIR, i]
		faces.append(load(p) if ResourceLoader.exists(p) else null)   # 冇圖就畫色塊
	data = GameData.load_all()
	item_names = data.names
	for id in data.prices:
		item_prices[id] = int(data.prices[id])
	shop_stock = data.shops[0]["stock"]
	inn_cost = int(data.inn["restCost"])
	facilities.append({"kind": "inn", "name": "客棧 [R]休息", "x": int(data.inn["x"]), "y": int(data.inn["y"]), "color": Color(0.3, 0.5, 0.9)})
	for sh in data.shops:
		facilities.append({"kind": "shop", "name": "%s [1-3]買 [X]賣" % sh["name"], "x": int(sh["x"]), "y": int(sh["y"]), "color": Color(0.9, 0.7, 0.2)})
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
	sim = Sim.new(data, 1 if autotest else randi())
	var fresh := true
	if not autotest and not ("--newgame" in OS.get_cmdline_user_args()) and SaveSys.has(SaveSys.AUTOSLOT):
		var loaded := SaveSys.read_autosave(data)
		if loaded != null:
			sim = loaded
			fresh = false
			my_id = int(sim.state["player_id"])     # 載入: 唔會再 spawn，直接攞玩家 id
			print("載入自動存檔 (日 %d)" % int(sim.clock_view()["day"]))
	if fresh:
		sim.init_mobs()
		sim.add_bots(10)
		my_id = sim.spawn_player("玩家")
	sim.event_emitted.connect(_on_event)
	_refresh()
	hud = MobileHud.new()
	add_child(hud)
	hud.setup(self)
	hud.attack_pressed.connect(_hud_attack)
	hud.auto_toggled.connect(_hud_auto)
	hud.bag_pressed.connect(func(): show_bag = not show_bag)
	hud.travel_pressed.connect(func():
		var tp := _near_travel()
		if not tp.is_empty(): _send({"t": "travel", "point": String(tp["point"])}))
	for a in OS.get_cmdline_user_args():
		if a == "--sshot":
			sshot_file = "user://sshot_ui.png"

func _refresh() -> void:
	ents = sim.view_ents()
	ch = sim.player_ch()
	var me = _me()
	if me != null:
		cam = Vector2(me.x, me.y) * TILE - get_viewport_rect().size / 2
	if target_id >= 0 and _ent(target_id) == null: target_id = -1
	if exp_start < 0 and not ch.is_empty(): exp_start = _exp_total()
	var cv: Variant = sim.clock_view()
	clock_str = str(cv["text"])
	night_on = bool(cv["is_night"])
	if float(banner["t"]) > 0:
		banner["t"] = float(banner["t"]) - 0.016

func _process(delta: float) -> void:
	if autotest:
		for i in AUTOTEST_STEPS: sim.step()
	else:
		acc += delta
		while acc >= TICK:
			acc -= TICK
			sim.step()
			_steer_tick()
			_auto_tick()
	_refresh()
	t0 += delta
	if not autotest and sim.tick > 0 and sim.tick % 720 == 0 and sim.tick != last_save_tick:
		last_save_tick = sim.tick
		SaveSys.autosave(sim)
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

# 舊 ws 訊息格式 → sim 意圖
func _send(d: Dictionary) -> void:
	match d.t:
		"move": sim.cmd_move(my_id, int(d.x), int(d.y))
		"attack": sim.cmd_attack(my_id, int(d.target))
		"chat": sim.cmd_chat(my_id, str(d.text))
		"rest": sim.cmd_rest(my_id)
		"buy": sim.cmd_buy(my_id, int(d.item), int(d.get("n", 1)))
		"sell": sim.cmd_sell(my_id, int(d.item), int(d.get("n", 1)))
		"facility": sim.cmd_facility(my_id, str(d.key))
		"travel": sim.cmd_travel(my_id, str(d.point))
		"work": sim.cmd_work(my_id, str(d.skill))
		"equip_tool": sim.cmd_equip_tool(my_id, str(d.skill), int(d.item))
		"storage_sub": sim.cmd_storage_sub(my_id, bool(d.on))
		"storage_deposit": sim.cmd_storage_deposit(my_id, int(d.item), int(d.get("n", 1)))
		"storage_withdraw": sim.cmd_storage_withdraw(my_id, int(d.item), int(d.get("n", 1)))
		"storage_sell": sim.cmd_storage_sell(my_id, int(d.item), int(d.get("n", 1)))
		"use_item": sim.cmd_use_item(my_id, int(d.item))

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 6: log_lines.pop_front()

func _exp_total() -> int:
	var t := 0
	for l in range(1, int(ch.get("level", 1))): t += RulesStats.exp_to_next(l)
	return t + int(ch.get("exp", 0))

func _on_event(e: Dictionary) -> void:
	match e.k:
		"chat":
			_log("%s: %s" % [e.name, e.text])
		"npc_say":
			_log("%s: %s" % [e.name, e.text])
		"hit":
			var d = _ent(int(e.dst))
			if d != null:
				var dmg: int = int(e.dmg)
				floats.append({"pos": Vector2(d.x, d.y) * TILE, "text": "miss" if dmg == 0 else str(dmg),
					"color": Color.YELLOW if int(e.dst) == my_id else Color.WHITE, "age": 0.0})
		"kill":
			if int(e.src) == my_id:
				kills += 1
				var names := []
				for i in e.items: names.append(item_names.get(int(i), str(i)))
				_log("殺怪 +%d 經驗 +%d 金 %s%s" % [e.exp, e.gold, ",".join(names), "  升級! Lv%d" % e.lvUp if int(e.lvUp) > 0 else ""])
		"msg":
			if int(e.dst) == my_id: _log(str(e.text))
		"travel":
			if int(e.dst) == my_id:
				target_id = -1
				_log("傳送到 %s" % str(e.to))
		"die":
			if int(e.dst) == my_id:
				_log("你死咗，返客棧" + ("，跌咗 %s" % item_names.get(int(e.lost), str(e.lost)) if int(e.get("lost", 0)) > 0 else ""))
				target_id = -1
				SaveSys.autosave(sim)           # 死完即存
		"train":
			if int(e.src) == my_id:
				if e.has("partner"):
					_log("同 %s 對練，歷練 %d/100" % [e.partner, int(e.lilian)])
				else:
					_log("%s: %s +1 (而家 %d)" % ["私塾" if e.attr == "政治" else "寺廟", e.attr, int(e.val)])
		"day":
			var season := int(e.season)
			if last_season >= 0 and season != last_season:
				_set_banner("入咗%s季" % RulesClock.SEASON_NAMES[season], Color(0.8, 0.9, 0.5), 10.0)
			last_season = season
		"disaster":
			if str(e.city) == str(data.world["homeCity"]):
				_set_banner("天災：%s (%s)！物資價格波動" % [e.name, e.size], Color(1, 0.55, 0.3), 15.0)

func _set_banner(text: String, col: Color, secs: float) -> void:
	banner = {"text": text, "t": secs, "color": col}
	_log("【%s】" % text)

func _autotest_step(me: Dictionary) -> void:
	var p := Vector2i(int(me.x), int(me.y))
	if start_pos.x < 0:
		start_pos = p
		_send({"t": "chat", "text": "autotest"}); _send({"t": "rest"}); _send({"t": "buy", "item": 10001, "n": 1})
		_send({"t": "move", "x": p.x + 6, "y": p.y + 2})
	elif not moved:
		if p != start_pos: moved = true; print("moved %s -> %s, saw %d entities" % [start_pos, p, ents.size()])
	else:
		var near = _nearest_mob(me)
		if near != null and int(near.id) != target_id:
			target_id = int(near.id); atk_sent = true
			_send({"t": "attack", "target": target_id})
		elif near == null and target_id < 0:
			_send({"t": "move", "x": 35, "y": 35})     # 未見到怪: 行入野區
		if kills > 0 and not ch.is_empty() and _exp_total() > exp_start:
			print("PASS: moved, killed %d mob, exp %d -> %d, Lv%d" % [kills, exp_start, _exp_total(), int(ch.level)])
			get_tree().quit(0)

func _nearest_mob(me: Dictionary):
	var best = null; var bd := 1e9
	for e in ents:
		if not e.get("mob", false) or int(e.get("level", 1)) > 2: continue   # autotest 只打 1~2 級怪，免得 1 級死喺山賊
		var d: float = absf(e.x - me.x) + absf(e.y - me.y)
		if d < bd: bd = d; best = e
	return best

func _near_shop() -> bool:
	var me = _me()
	if me == null: return false
	for f in facilities:
		if f.kind != "shop": continue
		if maxi(absi(int(me.x) - f.x), absi(int(me.y) - f.y)) <= 3: return true
	return false

func _near_inn() -> bool:
	var me = _me()
	if me == null: return false
	for f in facilities:
		if f.kind == "inn" and maxi(absi(int(me.x) - f.x), absi(int(me.y) - f.y)) <= 3: return true
	return false

# 附近商家設施 (練兵場/私塾/寺廟)
func _near_fac() -> Dictionary:
	var me = _me()
	if me == null: return {}
	for f in facilities:
		if f.kind == "fac" and maxi(absi(int(me.x) - f.x), absi(int(me.y) - f.y)) <= 3:
			return f
	return {}

# 附近傳送點 (城門: 城內/城外之間即時傳送)
func _near_travel() -> Dictionary:
	var me = _me()
	if me == null: return {}
	for f in facilities:
		if f.kind == "travel" and maxi(absi(int(me.x) - f.x), absi(int(me.y) - f.y)) <= 3:
			return f
	return {}

func _inn_rect() -> Rect2:
	return Rect2(get_viewport_rect().size.x / 2 - 150, 70, 300, 110)

func _draw_inn() -> void:
	if not _near_inn() or ch.is_empty(): return
	var r := _inn_rect()
	var col := Color(0.4, 0.6, 1.0)
	draw_rect(r, Color(0, 0, 0, 0.8)); draw_rect(r, col, false, 2.0)
	_txt(r.position + Vector2(10, 22), "客棧   金 %d" % int(ch.gold), col, 14)
	_txt(r.position + Vector2(10, 46), "住宿 %d 金: 回滿 HP / MP / SP" % inn_cost)
	var b := Rect2(r.position + Vector2(10, 62), Vector2(280, 34))
	draw_rect(b, Color(0.2, 0.35, 0.7) if int(ch.gold) >= inn_cost else Color(0.3, 0.3, 0.3)); draw_rect(b, col, false, 1.0)
	_txt(b.position + Vector2(90, 22), "點擊 休息 [R]", Color.WHITE, 14)

# 市場價 = 基準價 × 價格因子；買入另計魅力折扣【原】，賣出 = 市場價 50%
# ===== 設施面板 (練兵場/私塾/寺廟) =====
func _fac_rect() -> Rect2:
	return Rect2(get_viewport_rect().size.x / 2 - 220, 70, 440, 150)

func _fac_btn_rect() -> Rect2:
	var r := _fac_rect()
	return Rect2(r.position + Vector2(10, 104), Vector2(420, 36))

func _facility_click(pos: Vector2) -> bool:
	var f = _near_fac()
	if f.is_empty() or ch.is_empty(): return false
	var r := _fac_rect()
	if not r.has_point(pos): return false
	if _fac_btn_rect().has_point(pos):
		_send({"t": "facility", "key": String(f["fac"])})
	return true

func _draw_facility() -> void:
	var f = _near_fac()
	if f.is_empty() or ch.is_empty(): return
	var def: Dictionary = data.facilities[f["fac"]]
	var r := _fac_rect()
	var col := Color(f.color)
	draw_rect(r, Color(0, 0, 0, 0.8))
	draw_rect(r, col, false, 2.0)
	_txt(r.position + Vector2(10, 22), "%s   (金 %d)" % [def.name, int(ch.gold)], col, 14)
	_txt(r.position + Vector2(10, 46), str(def.desc), Color.WHITE, 11)
	if String(f["fac"]) == "training":
		_txt(r.position + Vector2(10, 64), "歷練 %d/100  (升級時武/智/敏/靈提升)" % int(ch.get("lilian", 0)), Color(0.7, 1.0, 0.7), 11)
		_txt(r.position + Vector2(10, 84), "下次升級加成: 武/智/敏/靈 +%d" % (int(ch.get("lilian", 0)) / 10), Color(0.7, 1.0, 0.7), 11)
	else:
		var attr := str(def.attr)
		_txt(r.position + Vector2(10, 64), "%s: %s +1  (而家 %d)" % [def.name, "政治" if attr == "pol" else "魅力", int(ch.attrs[attr])], Color(0.7, 1.0, 0.7), 11)
	var b := _fac_btn_rect()
	draw_rect(b, col)
	draw_rect(b, Color.WHITE, false, 1.0)
	_txt(b.position + Vector2(30, 23), "點擊使用", Color.WHITE, 13)


# 市場價 = 基準價 × 價格因子；買入另計魅力折扣【原】，賣出 = 市場價 50%
func _buy_price(id: int) -> int:
	var base: float = item_prices.get(id, 0)
	var pf: float = sim.market_factor(id)
	var cha := int(ch.attrs.cha) if not ch.is_empty() else 0
	return RulesShop.buy_price(RulesMarket.price(base, pf), cha)

func _sell_price(id: int) -> int:
	return RulesMarket.sell_price(item_prices.get(id, 0), sim.market_factor(id))

func _panel_rect() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(vs.x / 2 - 220, 70, 440, 60 + 32 * maxi(shop_stock.size(), maxi(1, ch.bag.size() if not ch.is_empty() else 1)))

# 點擊商店面板: 左邊買、右邊賣。回傳 true = 已處理
func _shop_click(pos: Vector2) -> bool:
	if not _near_shop() or ch.is_empty(): return false
	var r := _panel_rect()
	if not r.has_point(pos): return false
	var row := int((pos.y - r.position.y - 50) / 32)
	if row < 0: return true
	if pos.x < r.position.x + 220:
		if row < shop_stock.size(): _send({"t": "buy", "item": int(shop_stock[row]), "n": 1})
	elif row < ch.bag.size():
		_send({"t": "sell", "item": int(ch.bag[row].id), "n": 1})
	return true

func _draw_shop() -> void:
	if not _near_shop() or ch.is_empty(): return
	var r := _panel_rect()
	draw_rect(r, Color(0, 0, 0, 0.8)); draw_rect(r, Color(0.9, 0.7, 0.2), false, 2.0)
	_txt(r.position + Vector2(10, 22), "武器店   金 %d   (點 買/賣)" % int(ch.gold), Color(0.9, 0.7, 0.2), 14)
	_txt(r.position + Vector2(10, 44), "買 (魅力折扣後)", Color.CYAN); _txt(r.position + Vector2(230, 44), "賣 (原價 50%)", Color.CYAN)
	for i in shop_stock.size():
		var id := int(shop_stock[i])
		_txt(r.position + Vector2(10, 70 + 32 * i), "%s  %d 金" % [item_names.get(id, str(id)), _buy_price(id)])
	if ch.bag.is_empty(): _txt(r.position + Vector2(230, 64), "(背包空)", Color.GRAY)
	for i in ch.bag.size():
		var id := int(ch.bag[i].id)
		_txt(r.position + Vector2(230, 70 + 32 * i), "%s x%d  %d 金" % [item_names.get(id, str(id)), int(ch.bag[i].n), _sell_price(id)])

func _me():
	return _ent(my_id)

func target_ent():
	if target_id < 0:
		return null
	return _ent(target_id)

# 點怪 = 攻擊，點地 = 行路，點自己 = 取消目標
func _hud_tap(pos: Vector2) -> void:
	if _facility_click(pos):
		return
	if _shop_click(pos):
		return
	if not ch.is_empty() and _near_inn() and _inn_rect().has_point(pos):
		_send({"t": "rest"})
		return
	var g: Vector2 = ((pos + cam) / TILE).floor()
	var tp := _near_travel()
	if not tp.is_empty() and int(g.x) == tp.x and int(g.y) == tp.y:
		_send({"t": "travel", "point": String(tp["point"])})
		return
	var me = _me()
	if me != null and int(g.x) == int(me.x) and int(g.y) == int(me.y):
		target_id = -1                            # 點自己 = 取消目標
		return
	var e = _ent_at(g)
	if e == null or not e.get("mob", false):
		e = _mob_near_tap(pos)                    # 手機格仔細(16px)，容許 tap 埋隔籬格都算中
	if e != null and e.get("mob", false):
		target_id = int(e.id)
		_send({"t": "attack", "target": target_id})
	else:
		_send({"t": "move", "x": int(g.x), "y": int(g.y)})

# 容錯: tap 座標喺呢個範圍內揀最近嘅怪 (半格仔), 唔使準確咁啱格先郁到手
const TAP_TOLERANCE := TILE * 0.9
func _mob_near_tap(pos: Vector2):
	var world_pos: Vector2 = pos + cam
	var best = null
	var best_d := TAP_TOLERANCE
	for e in ents:
		if not e.get("mob", false):
			continue
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
	if t != null and t.get("mob", false):
		_send({"t": "attack", "target": target_id})
		return
	var me = _me()
	if me == null:
		return
	var near = _nearest_mob_safe(me)
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
	if t != null and t.get("mob", false):
		return                                  # sim 自己追梗
	var near = _nearest_mob_safe(me)
	if near != null:
		target_id = int(near.id)
		_send({"t": "attack", "target": target_id})
		return
	if int(sim.tick) % 60 == 0:
		_send({"t": "move", "x": 30 + (int(sim.tick) / 60) % 9, "y": 35})

func _nearest_mob_safe(me: Dictionary):
	var best = null
	var bd := 1e9
	for e in ents:
		if not e.get("mob", false):
			continue
		if int(e.level) > int(ch.level) + 1:
			continue                            # 唔打高自己兩級以上嘅怪
		var dist: float = absf(e.x - me.x) + absf(e.y - me.y)
		if dist < bd:
			bd = dist
			best = e
	return best

func _ent(id: int):
	for e in ents:
		if int(e.id) == id: return e
	return null

func _ent_at(g: Vector2):
	for e in ents:
		if int(e.x) == int(g.x) and int(e.y) == int(g.y): return e
	return null

func _unhandled_input(ev: InputEvent) -> void:
	if Input.is_emulating_mouse_from_touch():
		# Android: 觸控事件直接做世界點擊（emulate 出嚟嘅 mouse 事件忽略，避免雙重處理）
		if ev is InputEventScreenTouch and ev.pressed:
			_hud_tap(ev.position)
		return
	if ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_B: show_bag = not show_bag
		elif ev.keycode == KEY_R: _send({"t": "rest"})                                   # 客棧休息
		elif ev.keycode == KEY_X and not ch.is_empty() and ch.bag.size() > 0:          # 賣背包第一格
			_send({"t": "sell", "item": int(ch.bag[0].id), "n": 1})
		elif ev.keycode == KEY_H: _send({"t": "chat", "text": "大家好"})
		elif ev.keycode == KEY_G:
			var tp = _near_travel()
			if not tp.is_empty(): _send({"t": "travel", "point": String(tp["point"])})
		elif ev.keycode == KEY_T: _send({"t": "facility", "key": "training"})
		elif ev.keycode == KEY_P: _send({"t": "facility", "key": "school"})
		elif ev.keycode == KEY_M: _send({"t": "facility", "key": "temple"})
		elif ev.keycode >= KEY_1 and ev.keycode <= KEY_9 and ev.keycode - KEY_1 < shop_stock.size():
			_send({"t": "buy", "item": int(shop_stock[ev.keycode - KEY_1]), "n": 1})
		elif ev.keycode == KEY_W: _send({"t": "work", "skill": "mining"})                # debug: 淨試採礦，未有技能揀選 UI
		elif ev.keycode == KEY_Y:
			_send({"t": "storage_sub", "on": not bool(ch.get("storageSub", false))})
		elif ev.keycode == KEY_C and not ch.is_empty() and ch.bag.size() > 0:            # 存背包第一格入天地商行
			_send({"t": "storage_deposit", "item": int(ch.bag[0].id), "n": 1})
		elif ev.keycode == KEY_V and not ch.is_empty() and ch.storage.size() > 0:        # 由天地商行攞返第一格
			_send({"t": "storage_withdraw", "item": int(ch.storage[0].id), "n": 1})
		elif ev.keycode == KEY_U and not ch.is_empty() and ch.bag.size() > 0:            # 食用背包第一格 (如果食得)
			_send({"t": "use_item", "item": int(ch.bag[0].id)})
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
	var x0 := maxi(0, int(cam.x / TILE)); var x1 := mini(w, int((cam.x + vs.x) / TILE) + 1)
	var y0 := maxi(0, int(cam.y / TILE)); var y1 := mini(h, int((cam.y + vs.y) / TILE) + 1)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var pos := Vector2(x, y) * TILE - cam
			var safe := sim.is_safe(x, y)
			var c: Color
			if sim.blocked.has(y * w + x):
				c = Color(0.32, 0.22, 0.2)
			elif safe:
				c = Color(0.5 + 0.02 * ((x + y) % 2), 0.46, 0.36)   # 城內: 石板/泥路色，同野外分明
			else:
				c = Color(0.16 + 0.02 * ((x + y) % 2), 0.28, 0.16)  # 城外: 草地色
			if night_on:
				c = Color(c.r * 0.5, c.g * 0.5, c.b * 0.6)   # 夜景
			draw_rect(Rect2(pos, Vector2(TILE, TILE)), c)
			if safe != sim.is_safe(x + 1, y):
				draw_rect(Rect2(pos + Vector2(TILE - 2, 0), Vector2(2, TILE)), Color(0.9, 0.8, 0.3, 0.8))   # 城牆邊界(直)
			if safe != sim.is_safe(x, y + 1):
				draw_rect(Rect2(pos + Vector2(0, TILE - 2), Vector2(TILE, 2)), Color(0.9, 0.8, 0.3, 0.8))   # 城牆邊界(橫)
	for f in facilities:
		var fp := Vector2(f.x, f.y) * TILE - cam
		draw_rect(Rect2(fp - Vector2(TILE, TILE), Vector2(TILE * 3, TILE * 3)), Color(f.color, 0.35))
		draw_rect(Rect2(fp - Vector2(TILE, TILE), Vector2(TILE * 3, TILE * 3)), f.color, false, 2.0)
		_txt(fp + Vector2(-TILE, -TILE - 4), f.name, f.color, 12)
	for e in ents:
		var p := Vector2(e.x, e.y) * TILE - cam
		var isme: bool = int(e.id) == my_id
		var ismob: bool = e.get("mob", false)
		if ismob:
			draw_rect(Rect2(p, Vector2(TILE, TILE)), Color(0.8, 0.25, 0.2))    # 怪物色塊
		else:
			var f = faces[int(e.face) % faces.size()] if faces.size() > 0 else null
			if f != null: draw_texture_rect(f, Rect2(p - Vector2(4, 8), Vector2(24, 26)), false)
			else: draw_rect(Rect2(p, Vector2(TILE, TILE)), Color.RED if isme else Color.ORANGE)
			if isme: draw_rect(Rect2(p - Vector2(4, 8), Vector2(24, 26)), Color.YELLOW, false, 2.0)
		if e.has("hp") and e.has("maxHp") and (ismob or isme):
			_bar(p + Vector2(-2, -14), Vector2(20, 3), float(e.hp) / float(e.maxHp), Color(0.9, 0.2, 0.2) if ismob else Color(0.3, 0.8, 0.3))
		if int(e.id) == target_id:
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(TILE + 4, TILE + 4)), Color.CYAN, false, 2.0)
		var nm := str(e.name) + (" Lv%d" % int(e.level) if ismob else "")
		_txt(p + Vector2(-8, -18), nm, Color(1, 0.7, 0.6) if ismob else Color.WHITE, 11)
	for f in floats:
		var fp: Vector2 = f.pos - cam + Vector2(2, -20 - 24 * f.age)
		_txt(fp, f.text, f.color, 14)
	_draw_bag(vs)
	_draw_shop()
	_draw_inn()
	_draw_facility()
	_draw_banner(vs)
	_draw_clock(vs)

# 時辰/日/季節 (右上) + 夜晚示意
func _draw_clock(vs: Vector2) -> void:
	_txt(Vector2(vs.x - 252, 44), clock_str, Color(1, 0.95, 0.65), 13)
	if night_on:
		draw_circle(Vector2(vs.x - 24, 50), 6, Color(0.9, 0.9, 0.75))
		_txt(Vector2(vs.x - 44, 52), "夜", Color(0.8, 0.8, 0.9), 9)


# 天災/季節橫幅 (頂中，目標框下)
func _draw_banner(vs: Vector2) -> void:
	if float(banner["t"]) <= 0 or str(banner["text"]) == "":
		return
	var col: Color = banner.get("color", Color(1, 0.55, 0.3))
	var r := Rect2(vs.x / 2 - 210, 40, 420, 26)
	draw_rect(r, Color(0, 0, 0, 0.75))
	draw_rect(r, col, false, 2.0)
	_txt(r.position + Vector2(12, 18), str(banner["text"]), Color.WHITE, 13)

func _draw_bag(vs: Vector2) -> void:
	if show_bag and not ch.is_empty():
		var bag: Array = ch.bag
		draw_rect(Rect2(vs.x - 190, 52, 184, 30 + 16 * maxi(1, bag.size())), Color(0, 0, 0, 0.7))
		_txt(Vector2(vs.x - 182, 70), "背包")
		for i in bag.size():
			_txt(Vector2(vs.x - 182, 88 + 16 * i), "%s x%d" % [item_names.get(int(bag[i].id), str(bag[i].id)), int(bag[i].n)])
