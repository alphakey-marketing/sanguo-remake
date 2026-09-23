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
var uitest := false                # --uitest: 觸控 UI 煙霧測試 (tests/ui_smoke.gd)
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
var exp_start := -1
var atk_sent := false
var kills := 0
var facilities := []              # 設施 {kind, name, x, y, color, fac}
var item_prices := {}             # id -> 價錢
var inn_cost := 0
var clock_str := ""               # 時辰/日/季節 (sim.clock_view)
var night_on := false
var last_season := -1
var banner := {"text": "", "t": 0.0}   # 天災/季節橫幅
var last_save_tick := 0
var quest_npcs := []               # 任務 NPC 視圖 (Step 8): sim.view_quest_npcs()
var quest_items := {}              # item id -> true (任務道具，賣唔到標記用)
var pending := {}                  # 點遠處 NPC/設施: 行到附近自動開 {kind, ref}
var marker := {"pos": Vector2.ZERO, "t": 0.0}   # 點地行路落點標記
var _ask_seen := ""                # 任務答題對話框已自動彈過 (唔好一直彈)

func _ready() -> void:
	autotest = "--autotest" in OS.get_cmdline_user_args()
	uitest = "--uitest" in OS.get_cmdline_user_args() or "--uishot" in OS.get_cmdline_user_args()
	for i in 12:
		var p := "%sface_%d.jpg" % [FACE_DIR, i]
		faces.append(load(p) if ResourceLoader.exists(p) else null)   # 冇圖就畫色塊
	data = GameData.load_all()
	item_names = data.names
	for id in data.prices:
		item_prices[id] = int(data.prices[id])
	inn_cost = int(data.inn["restCost"])
	facilities.append({"kind": "inn", "name": "客棧", "x": int(data.inn["x"]), "y": int(data.inn["y"]), "color": Color(0.3, 0.5, 0.9)})
	for sh in data.shops:
		facilities.append({"kind": "shop", "name": str(sh["name"]), "x": int(sh["x"]), "y": int(sh["y"]),
			"color": Color(0.9, 0.7, 0.2), "stock": sh["stock"], "shopName": str(sh["name"])})
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
	if not autotest and not uitest and not ("--newgame" in OS.get_cmdline_user_args()) and SaveSys.has(SaveSys.AUTOSLOT):
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
	hud.target_cycle.connect(_cycle_target)
	hud.skill_pressed.connect(_on_skill)
	hud.context_pressed.connect(func(act: Dictionary) -> void: ContextActions.run(self, act))
	hud.create_done.connect(_on_create_done)
	if fresh and not autotest and not uitest:
		hud.creation_mode = true
	for a in OS.get_cmdline_user_args():
		if a == "--sshot":
			sshot_file = "user://sshot_ui.png"
	if "--uitest" in OS.get_cmdline_user_args():
		add_child(load("res://tests/ui_smoke.gd").new())
	elif "--uishot" in OS.get_cmdline_user_args():
		add_child(load("res://tests/ui_shot.gd").new())

func _refresh() -> void:
	ents = sim.view_ents()
	ch = sim.player_ch()
	quest_npcs = sim.view_quest_npcs()
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
	if not autotest:
		_ui_tick(delta)
	t0 += delta
	if not autotest and not uitest and sim.tick > 0 and sim.tick % 720 == 0 and sim.tick != last_save_tick:
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
		"raise_attr": sim.cmd_raise_attr(my_id, str(d.attr))
		"auto_assign": sim.cmd_auto_assign(my_id)
		"set_title": sim.cmd_set_title(my_id, str(d.title))
		"set_birth": sim.cmd_set_birth(my_id, int(d.month), int(d.day))
		"set_face": sim.cmd_set_face(my_id, str(d.part), int(d.value))
		"submit_quiz": sim.cmd_submit_quiz(my_id, d.answers)
		"quest_talk": sim.cmd_quest_talk(my_id, str(d.npc))
		"select_class": sim.cmd_select_class(my_id, str(d.class_id))
		"equip_spellbook": sim.cmd_equip_spellbook(my_id, int(d.item), int(d.get("slot", 0)))
		"cast_spell": sim.cmd_cast_spell(my_id, int(d.slot), int(d.get("target", 0)))
		"equip_weapon": sim.cmd_equip_weapon(my_id, int(d.item))
		"equip_jewel": sim.cmd_equip_jewel(my_id, int(d.item), int(d.get("slot", 0)))
		"use_ultimate": sim.cmd_use_ultimate(my_id, str(d.ult))
		"fusion_start": sim.cmd_fusion_start(my_id)
		"fusion_hit": sim.cmd_fusion_hit(my_id)
		"quest_answer": sim.cmd_quest_answer(my_id, str(d.quest), int(d.answer))
		"debug_give": sim.cmd_debug_give(my_id, int(d.item), int(d.get("n", 1)))

func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 6: log_lines.pop_front()

const STATUS_NAMES := {"sealed": "封咒", "hex": "中邪", "power1": "聚力", "power2": "強力", "power3": "神力",
	"armor1": "護甲", "armor2": "金甲", "armor3": "聖鎧", "mirror1": "護鏡", "mirror2": "光鏡", "mirror3": "仙鏡"}
const ELEM_TAG := {"earth": "地", "water": "水", "fire": "火", "wind": "風"}

func _ent_name(id: int) -> String:
	var d = _ent(id)
	return str(d.name) if d != null else "？"

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
				_log("裝備武器: %s" % item_names.get(int(e.item), str(e.item)))
		"ult":
			if int(e.src) == my_id:
				_log("「%s」！ (-%d MP -%d SP)" % [e.name, int(e.get("mp", 0)), int(e.get("sp", 0))])
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
				if not uitest:
					SaveSys.autosave(sim)       # 死完即存
				ch["status"] = {}              # 死亡清狀態 (sim 權威，UI 同步)
		"flee":
			if int(e.get("dst", -1)) == my_id:
				_log("%s 見你唔夠打，逃咗！" % str(e.get("name", "")))
		"train":
			if int(e.src) == my_id:
				if e.has("partner"):
					_log("同 %s 對練，歷練 %d/100" % [e.partner, int(e.lilian)])
				else:
					_log("%s: %s +1 (而家 %d)" % ["私塾" if e.attr == "政治" else "寺廟", e.attr, int(e.val)])
		"quest":
			if int(e.dst) == my_id:
				var qname := String(e.quest)
				if bool(e.get("started", false)):
					_log("接咗任務「%s」" % qname)
				elif bool(e.get("done", false)):
					var rw: Dictionary = e.get("reward", {})
					var parts: Array = []
					if int(rw.get("gold", 0)) > 0: parts.append("+%d 金" % int(rw["gold"]))
					if int(rw.get("exp", 0)) > 0: parts.append("+%d 經驗" % int(rw["exp"]))
					if int(rw.get("lilian", 0)) > 0: parts.append("+%d 歷練" % int(rw["lilian"]))
					if rw.has("ultimate"): parts.append("學識絕招「%s」！" % str(rw["ultimate"]))
					if rw.has("items"):
						for it in rw["items"]:
							parts.append("%s x%d" % [item_names.get(int(it.id), str(it.id)), int(it.n)])
					_log("任務完成「%s」 %s" % [qname, " ".join(parts) if not parts.is_empty() else ""])
				else:
					_log("「%s」有進展" % qname)
		"heal":
			if int(e.dst) == my_id:
				_log("密醫幫你醫治，回復 %d HP" % int(e.hp))
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

# 附近傳送點 (城門: 城內/城外之間即時傳送)
func _near_travel() -> Dictionary:
	var me = _me()
	if me == null: return {}
	for f in facilities:
		if f.kind == "travel" and maxi(absi(int(me.x) - f.x), absi(int(me.y) - f.y)) <= 3:
			return f
	return {}

# 市場價 = 基準價 × 價格因子；買入另計魅力折扣【原】，賣出 = 市場價 50%
func _buy_price(id: int) -> int:
	var base: float = item_prices.get(id, 0)
	var pf: float = sim.market_factor(id)
	var cha := int(ch.attrs.cha) if not ch.is_empty() else 0
	return RulesShop.buy_price(RulesMarket.price(base, pf), cha)

func _sell_price(id: int) -> int:
	return RulesMarket.sell_price(item_prices.get(id, 0), sim.market_factor(id))



func _me():
	return _ent(my_id)

func target_ent():
	if target_id < 0:
		return null
	return _ent(target_id)

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
	# 怪優先（戰鬥中最常撳）
	var e = _ent_at(g)
	if e == null or not e.get("mob", false):
		e = _mob_near_tap(pos)                    # 手指粗: 容許 tap 埋隔籬格都算中
	if e != null and e.get("mob", false):
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
	_send({"t": "move", "x": int(g.x), "y": int(g.y)})
	marker = {"pos": g, "t": 1.0}

# tap 格仔係咪 NPC/設施（設施佔 3x3，NPC 容許隔籬 1 格）→ ContextActions 格式
func _interactable_at(g: Vector2) -> Dictionary:
	for qn in quest_npcs:
		if absi(int(g.x) - int(qn.x)) <= 1 and absi(int(g.y) - int(qn.y)) <= 1:
			return {"kind": "quest_npc", "label": "對話", "ref": qn}
	for f in facilities:
		if absi(int(g.x) - int(f.x)) <= 1 and absi(int(g.y) - int(f.y)) <= 1:
			return {"kind": String(f.kind), "label": "", "ref": f}
	return {}

# 每幀 UI 雜務: 行到 pending 目標就開、任務答題自動彈對話框、落點標記淡出
func _ui_tick(delta: float) -> void:
	marker["t"] = maxf(0.0, float(marker["t"]) - delta * 1.5)
	if hud == null or hud.creation_mode:
		return
	var me = _me()
	if not pending.is_empty() and me != null:
		if hud.joy_active():
			pending = {}
		elif ContextActions._near(me, int(pending.ref.x), int(pending.ref.y)):
			var it := pending
			pending = {}
			ContextActions.run(self, it)
	var ask := _active_ask()
	var key := JSON.stringify(ask)
	if not ask.is_empty() and key != _ask_seen and not hud.any_panel_open():
		_ask_seen = key
		ContextActions.run(self, {"kind": "ask"})

# 切換目標: 附近怪按距離排，揀下一隻（唔會即刻打，撳攻擊先打）
func _cycle_target() -> void:
	var me = _me()
	if me == null:
		return
	var mobs: Array = []
	for e in ents:
		if e.get("mob", false) and absf(e.x - me.x) + absf(e.y - me.y) <= 16:
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
	if String(sl["ult"]) == "":
		_log("未學絕招 (絕招任務: 練兵場門口禁衛大隊長)")
		return
	_send({"t": "use_ultimate", "ult": String(sl["ult"])})

func class_has_spells() -> bool:
	var cid := str(ch.get("classId", ""))
	for sp in data.spells:
		if (sp["classes"] as Array).has(cid):
			return true
	return false

func class_has_ults() -> bool:
	var cid := str(ch.get("classId", ""))
	for u in data.ultimates:
		if str(u["class"]) == cid:
			return true
	return false

# Android 返回鍵: 有面板就關面板（唔會一撳就退出遊戲）
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and hud != null and hud.any_panel_open():
		hud.close_panels()

# 容錯: tap 座標喺呢個範圍內揀最近嘅怪 (~1.8 格 ≈ 手指闊), 唔使準確咁啱格先郁到手
const TAP_TOLERANCE := TILE * 1.8
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
	var near = _nearest_mob_safe(me)
	if t != null and t.get("mob", false):
		# 貼身 / 打緊我 → 繼續打；否則有更近嘅就轉 (例如目標逃走咗)
		if _mob_dist(me, t) <= 1 or int(t.get("aggro", 0)) == int(me.id):
			return
		if near == null or int(near.id) == target_id or _mob_dist(me, near) >= _mob_dist(me, t):
			return                              # sim 自己追梗
	if near != null:
		target_id = int(near.id)
		_send({"t": "attack", "target": target_id})
		return
	if int(sim.tick) % 60 == 0:
		_send({"t": "move", "x": 30 + (int(sim.tick) / 60) % 9, "y": 35})

func _nearest_mob_safe(me: Dictionary):
	return _pick_mob(me, true)

# 揀怪: 只揀同自己同一 zone (洞窟各層座標同野外相鄰，唔可以隔層鎖)；
# 打緊我嘅怪優先 (唔理等級)；其次最近 (Chebyshev = 實際步數，同距離再比 Manhattan)
# safe_only: 跳過高自己兩級以上嘅怪 (掛機用)
func _pick_mob(me: Dictionary, safe_only: bool):
	var my_zone := str(sim.zone_view(int(me.x), int(me.y)).get("id", ""))
	var best = null
	var bd := 1e9
	for e in ents:
		if not e.get("mob", false) or int(e.hp) <= 0:
			continue
		if str(sim.zone_view(int(e.x), int(e.y)).get("id", "")) != my_zone:
			continue
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
	for e in ents:
		if int(e.id) == id: return e
	return null

func _ent_at(g: Vector2):
	for e in ents:
		if int(e.x) == int(g.x) and int(e.y) == int(g.y): return e
	return null

# 測試功能: 「更多」面板 + 桌面鍵盤共用（成品前換走；倉庫已搬去背包面板）
func _on_debug_pressed(action: String) -> void:
	match action:
		"greet": _send({"t": "chat", "text": "大家好"})
		"use":
			if not ch.is_empty():
				var food := 29054                            # debug: 燻魚(回 HP)，唔理背包原本有咩，直接派一件試食
				_send({"t": "debug_give", "item": food, "n": 1})
				_send({"t": "use_item", "item": food})
		"work_mining":
			var sk: Dictionary = data.work.get("mining", {})
			if not sk.is_empty() and (ch.get("tools", {}) as Dictionary).get("mining", {}).is_empty():
				var tool := int(sk["starterTool"])          # debug: 冇工具就直接派新手工具落背包再裝備
				_send({"t": "debug_give", "item": tool, "n": 1})
				_send({"t": "equip_tool", "skill": "mining", "item": tool})
			_send({"t": "work", "skill": "mining"})


func _unhandled_input(ev: InputEvent) -> void:
	if hud != null and (hud.any_panel_open() or hud.creation_mode):
		return                                     # 面板開住: 唔做世界點擊/快捷鍵
	# 逐個事件判斷: 觸控 = ScreenTouch；由觸控模擬出嚟嘅 mouse 事件忽略（避免雙重處理）
	# （唔用 Input.is_emulating_mouse_from_touch(): 4.7 桌面都回 true）
	if ev is InputEventScreenTouch:
		if ev.pressed:
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
	var x0 := maxi(0, int(cam.x / TILE)); var x1 := mini(w, int((cam.x + vs.x) / TILE) + 1)
	var y0 := maxi(0, int(cam.y / TILE)); var y1 := mini(h, int((cam.y + vs.y) / TILE) + 1)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var pos := Vector2(x, y) * TILE - cam
			var safe := sim.is_safe(x, y)
			var zv := sim.zone_view(x, y)
			var c: Color
			if sim.blocked.has(y * w + x):
				c = Color(0.32, 0.22, 0.2)
			elif String(zv.get("id", "")).begins_with("runan_"):
				c = Color(0.2 + 0.01 * ((x + y) % 3), 0.19, 0.23)   # 洞窟: 石板岩色 (Step 11)
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
		if not (e.get("statuses", []) as Array).is_empty():
			var tags: Array = []
			for sid in e["statuses"]:
				tags.append(STATUS_NAMES.get(str(sid), str(sid)))
			nm += " [%s]" % str(",".join(tags))
		if bool(e.get("casting", false)):
			nm += "（吟唱中）"
		_txt(p + Vector2(-8, -18), nm, Color(1, 0.7, 0.6) if ismob else Color.WHITE, 11)
	for qn in quest_npcs:
		var qp := Vector2(int(qn.x), int(qn.y)) * TILE - cam
		var qcol := Color(0.45, 0.75, 1.0) if not bool(qn.service) else Color(0.5, 1.0, 0.5)
		draw_rect(Rect2(qp - Vector2(2, 2), Vector2(TILE + 4, TILE + 4)), qcol, false, 2.0)
		draw_circle(qp + Vector2(TILE, TILE) * 0.5, 6, Color(0.1, 0.25, 0.45, 0.9))
		_txt(qp + Vector2(-6, -20), "!" if not bool(qn.service) else "+", Color(1, 0.9, 0.3), 12)
		_txt(qp + Vector2(-8, -32), str(qn.name), qcol, 11)
	for f in floats:
		var fp: Vector2 = f.pos - cam + Vector2(2, -20 - 24 * f.age)
		_txt(fp, f.text, f.color, 14)
	if float(marker["t"]) > 0.0:                   # 點地落點標記（縮細 + 淡出）
		var mc: Vector2 = marker["pos"] * TILE + Vector2(TILE, TILE) * 0.5 - cam
		var k := float(marker["t"])
		draw_arc(mc, 4.0 + 10.0 * k, 0, TAU, 24, Color(1, 0.9, 0.4, k), 2.0)
	_draw_banner(vs)



# 時辰/日/季節 (右上) + 夜晚示意


# 天災/季節橫幅 (頂中，目標框下)
func _draw_banner(vs: Vector2) -> void:
	if float(banner["t"]) <= 0 or str(banner["text"]) == "":
		return
	var col: Color = banner.get("color", Color(1, 0.55, 0.3))
	var r := Rect2(vs.x / 2 - 210, 40, 420, 26)
	draw_rect(r, Color(0, 0, 0, 0.75))
	draw_rect(r, col, false, 2.0)
	_txt(r.position + Vector2(12, 18), str(banner["text"]), Color.WHITE, 13)


# ===== 任務答題 (ask stage, Step 10 絕招任務) =====
func _active_ask() -> Dictionary:
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
			return {"q": str(q["id"]), "dialog": stage.get("dialog", []), "options": stage.get("options", [])}
	return {}








# 記事面板 (Step 8, spec 06 §1.2): 進行中任務 + 提示；完成記錄


# 建角面板完成（mobile_hud)_on_create_done 用
func _on_create_done() -> void:
	_log("建角完成，出發！")

# 升級點數 / 理念 / 生日 / 稱號 狀態列 (Step 7.5 debug UI)
