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
var quest_npcs := []               # 任務 NPC 視圖 (Step 8): sim.view_quest_npcs()
var show_quests := false           # 記事面板 (Step 8)
var quest_items := {}              # item id -> true (任務道具，賣唔到標記用)

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
		facilities.append({"kind": "shop", "name": "%s [1-3]買 [X]賣" % sh["name"], "x": int(sh["x"]), "y": int(sh["y"]),
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
	hud.debug_pressed.connect(_on_debug_pressed)
	hud.quest_pressed.connect(func(): show_quests = not show_quests)
	hud.create_done.connect(_on_create_done)
	if fresh and not autotest:
		hud.creation_mode = true
	for a in OS.get_cmdline_user_args():
		if a == "--sshot":
			sshot_file = "user://sshot_ui.png"

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
				SaveSys.autosave(sim)           # 死完即存
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

func _near_shop() -> bool:
	return not _nearest_shop().is_empty()


# 最近商店 (買賣同貨單要跟邊間店) (Step 11 洞窟商店)
func _nearest_shop() -> Dictionary:
	var me = _me()
	if me == null:
		return {}
	for f in facilities:
		if f.kind != "shop" or maxi(absi(int(me.x) - f.x), absi(int(me.y) - f.y)) > 3:
			continue
		return f
	return {}

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
	# 打鐵鋪: 撳面板 = 融合開始 / 敲實 (QTE)
	if String(f["fac"]) == "forge":
		if (ch.get("fusing", {}) as Dictionary).is_empty():
			_send({"t": "fusion_start"})
		else:
			_send({"t": "fusion_hit"})
		return true
	if _fac_btn_rect().has_point(pos):
		_send({"t": "facility", "key": String(f["fac"])})
	return true

func _draw_facility() -> void:
	var f = _near_fac()
	if f.is_empty() or ch.is_empty(): return
	if String(f["fac"]) == "forge":
		_draw_forge(f)
		return
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


# 打鐵鋪 (義士融合, Step 10 spec 02 §6): 集氣棒 QTE
func _draw_forge(f: Dictionary) -> void:
	var r := _fac_rect()
	var col := Color(f.color)
	draw_rect(r, Color(0, 0, 0, 0.8))
	draw_rect(r, col, false, 2.0)
	_txt(r.position + Vector2(10, 22), "打鐵鋪   (金 %d)" % int(ch["gold"]), col, 14)
	var fs: Dictionary = ch.get("fusing", {})
	if fs.is_empty():
		_txt(r.position + Vector2(10, 46), "融合【義士】: 將屬性石燒入裝緊嗰把武器 (只能 1 粒)", Color.WHITE, 11)
		_txt(r.position + Vector2(10, 64), "背包要有屬性石 + 武器未嵌石 + 10 級以上", Color(0.8, 0.9, 0.6), 11)
		if str(ch.get("classId", "")) == "yishi":
			_txt(r.position + Vector2(10, 84), "點擊面板攞料：融合開始 [N]", Color(1, 1, 0.8), 13)
	else:
		var pos := RulesJewel.fusion_pos(sim.tick - int(fs["start"]))
		var jd: Dictionary = data.jewel_by_item.get(int(fs["jewel"]), {})
		_txt(r.position + Vector2(10, 46), "嵌入緊: %s → %s   (撳實 = 敲定)" % [
			jd.get("name", "?"), item_names.get(int(fs["weapon"]), str(fs["weapon"]))], Color(1, 0.85, 0.5), 11)
		# 集氣棒: 0→100%，目標 50%±20% 係金色窗口
		var bar := Rect2(r.position + Vector2(10, 66), Vector2(420, 22))
		draw_rect(bar, Color(0.15, 0.15, 0.15))
		var win := Rect2(bar.position + Vector2(bar.size.x * (RulesJewel.FUSION_TARGET - RulesJewel.FUSION_WINDOW), 0),
			Vector2(bar.size.x * RulesJewel.FUSION_WINDOW * 2, bar.size.y))
		draw_rect(win, Color(0.6, 0.75, 0.2))
		draw_rect(Rect2(bar.position + Vector2(bar.size.x * pos - 2, -3), Vector2(4, bar.size.y + 6)), Color(1, 0.4, 0.2))
		_txt(r.position + Vector2(10, 98), "集氣 %.0f%% — 金色窗口內撳 [N]/點擊！" % (pos * 100.0), Color(1, 1, 0.7), 12)


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
	var ns := _nearest_shop()
	var stk: Array = ns.get("stock", shop_stock) if not ns.is_empty() else shop_stock
	var nrows := maxi(stk.size(), maxi(1, ch.bag.size() if not ch.is_empty() else 1))
	return Rect2(vs.x / 2 - 220, 70, 440, 60 + 32 * nrows)

# 點擊商店面板: 左邊買、右邊賣。回傳 true = 已處理
func _shop_click(pos: Vector2) -> bool:
	if not _near_shop() or ch.is_empty(): return false
	var r := _panel_rect()
	if not r.has_point(pos): return false
	var ns := _nearest_shop()
	var stk: Array = ns.get("stock", shop_stock) if not ns.is_empty() else shop_stock
	var row := int((pos.y - r.position.y - 50) / 32)
	if row < 0: return true
	if pos.x < r.position.x + 220:
		if row < stk.size(): _send({"t": "buy", "item": int(stk[row]), "n": 1})
	elif row < ch.bag.size():
		_send({"t": "sell", "item": int(ch.bag[row].id), "n": 1})
	return true

func _draw_shop() -> void:
	var ns := _nearest_shop()
	if ns.is_empty() or ch.is_empty(): return
	var stk: Array = ns.get("stock", []) as Array
	var r := _panel_rect()
	draw_rect(r, Color(0, 0, 0, 0.8)); draw_rect(r, Color(0.9, 0.7, 0.2), false, 2.0)
	_txt(r.position + Vector2(10, 22), "%s   金 %d   (點 買/賣)" % [str(ns["shopName"]), int(ch["gold"])], Color(0.9, 0.7, 0.2), 14)
	_txt(r.position + Vector2(10, 44), "買 (魅力折扣後)", Color.CYAN); _txt(r.position + Vector2(230, 44), "賣 (原價 50%)", Color.CYAN)
	for i in stk.size():
		var id := int(stk[i])
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
	if _ask_click(pos):
		return
	if _facility_click(pos):
		return
	if _shop_click(pos):
		return
	if not ch.is_empty() and _near_inn() and _inn_rect().has_point(pos):
		_send({"t": "rest"})
		return
	var g: Vector2 = ((pos + cam) / TILE).floor()
	# 點任務 NPC = 對話 (Step 8)
	for qn in quest_npcs:
		if int(g.x) == int(qn.x) and int(g.y) == int(qn.y):
			_send({"t": "quest_talk", "npc": String(qn.id)})
			return
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

# 手機冇鍵盤，呢個俾 mobile_hud debug 掣 + 桌面鍵盤共用 (Step 5~7 未有正式面板嘅功能)
func _on_debug_pressed(action: String) -> void:
	match action:
		"greet": _send({"t": "chat", "text": "大家好"})
		"use":
			if not ch.is_empty():
				var food := 29054                            # debug: 燻魚(回 HP)，唔理背包原本有咩，直接派一件試食
				_send({"t": "debug_give", "item": food, "n": 1})
				_send({"t": "use_item", "item": food})
		"storage_sub": _send({"t": "storage_sub", "on": not bool(ch.get("storageSub", false))})
		"deposit":
			if not ch.is_empty() and ch.bag.size() > 0:
				_send({"t": "storage_deposit", "item": int(ch.bag[0].id), "n": 1})
		"withdraw":
			if not ch.is_empty() and ch.storage.size() > 0:
				_send({"t": "storage_withdraw", "item": int(ch.storage[0].id), "n": 1})
		"work_mining":
			var sk: Dictionary = data.work.get("mining", {})
			if not sk.is_empty() and (ch.get("tools", {}) as Dictionary).get("mining", {}).is_empty():
				var tool := int(sk["starterTool"])          # debug: 冇工具就直接派新手工具落背包再裝備
				_send({"t": "debug_give", "item": tool, "n": 1})
				_send({"t": "equip_tool", "skill": "mining", "item": tool})
			_send({"t": "work", "skill": "mining"})


func _unhandled_input(ev: InputEvent) -> void:
	if Input.is_emulating_mouse_from_touch():
		# Android: 觸控事件直接做世界點擊（emulate 出嚟嘅 mouse 事件忽略，避免雙重處理）
		if ev is InputEventScreenTouch and ev.pressed:
			_hud_tap(ev.position)
		return
	if ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_B: show_bag = not show_bag
		elif ev.keycode == KEY_J: show_quests = not show_quests                                  # 記事
		elif ev.keycode == KEY_R: _send({"t": "rest"})                                   # 客棧休息
		elif ev.keycode == KEY_X and not ch.is_empty() and ch.bag.size() > 0:          # 賣背包第一格
			_send({"t": "sell", "item": int(ch.bag[0].id), "n": 1})
		elif ev.keycode == KEY_H: _on_debug_pressed("greet")
		elif ev.keycode == KEY_G:
			var tp = _near_travel()
			if not tp.is_empty(): _send({"t": "travel", "point": String(tp["point"])})
		elif ev.keycode == KEY_T: _send({"t": "facility", "key": "training"})
		elif ev.keycode == KEY_P: _send({"t": "facility", "key": "school"})
		elif ev.keycode == KEY_M: _send({"t": "facility", "key": "temple"})
		elif ev.keycode >= KEY_1 and ev.keycode <= KEY_9:
			var stk: Array = _nearest_shop().get("stock", []) as Array
			var idx: int = int(ev.keycode) - KEY_1
			if idx < stk.size(): _send({"t": "buy", "item": int(stk[idx]), "n": 1})
		elif ev.keycode == KEY_A and not ch.is_empty() and ch.has("bag"):   # 裝備背包第一把武器 (Step 10)
			for b in ch["bag"]:
				if int(data.cats.get(int(b["id"]), 0)) in [1, 2, 3]:
					_send({"t": "equip_weapon", "item": int(b["id"])})
					break
		elif ev.keycode == KEY_L and not ch.is_empty():            # 絕招 (最新學嗰招)
			var ults: Array = ch.get("ultimates", [])
			if ults.is_empty():
				_log("未學任何絕招")
			else:
				_send({"t": "use_ultimate", "ult": str(ults[ults.size() - 1])})
		elif ev.keycode == KEY_I and not ch.is_empty() and ch.has("equip"):   # 寶石欄 0: 裝第一粒背包寶石 / 卸
			var jews: Array = ch["equip"].get("jewels", [0, 0])
			if int(jews[0]) != 0:
				_send({"t": "equip_jewel", "item": 0, "slot": 0})
			else:
				for b in ch["bag"]:
					if data.jewel_by_item.has(int(b["id"])):
						_send({"t": "equip_jewel", "item": int(b["id"]), "slot": 0})
						break
		elif ev.keycode == KEY_O and not ch.is_empty() and ch.has("equip"):   # 寶石欄 1 卸
			_send({"t": "equip_jewel", "item": 0, "slot": 1})
		elif ev.keycode == KEY_N and not ch.is_empty():             # 融合: 開始 / 敲實 (打鐵鋪)
			if (ch.get("fusing", {}) as Dictionary).is_empty():
				_send({"t": "fusion_start"})
			else:
				_send({"t": "fusion_hit"})
		elif ev.keycode == KEY_W: _on_debug_pressed("work_mining")
		elif ev.keycode == KEY_Z and not ch.is_empty() and ch.has("equip"):   # 施法: 快捷列 1 (Step 9)
			var tgt := target_id if target_id >= 0 else 0
			_send({"t": "cast_spell", "slot": 0, "target": tgt})
		elif ev.keycode == KEY_K and not ch.is_empty() and ch.has("equip"):   # 快捷列 1 裝第一本背包術書
			for b in ch["bag"]:
				if data.spell_by_item.has(int(b["id"])):
					_send({"t": "equip_spellbook", "item": int(b["id"]), "slot": 0})
					break
		elif ev.keycode == KEY_Q: _send({"t": "auto_assign"})
		elif ev.keycode == KEY_E: _send({"t": "raise_attr", "attr": "str"})
		elif ev.keycode == KEY_F: _send({"t": "raise_attr", "attr": "agi"})
		elif ev.keycode == KEY_D: _send({"t": "raise_attr", "attr": "int"})
		elif ev.keycode == KEY_S: _send({"t": "raise_attr", "attr": "spi"})
		elif ev.keycode == KEY_Y: _on_debug_pressed("storage_sub")
		elif ev.keycode == KEY_C: _on_debug_pressed("deposit")
		elif ev.keycode == KEY_V: _on_debug_pressed("withdraw")
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
	_draw_bag(vs)
	_draw_shop()
	_draw_inn()
	_draw_facility()
	_draw_zone(vs)
	_draw_banner(vs)
	_draw_clock(vs)
	_draw_char_status(vs)
	_draw_quests(vs)
	_draw_ask(vs)

# 所在區名 (左上角) (Step 11 洞窟)
func _draw_zone(vs: Vector2) -> void:
	var me = _me()
	if me == null:
		return
	var zv := sim.zone_view(int(me.x), int(me.y))
	if zv.is_empty():
		return
	_txt(Vector2(10, 12), str(zv["name"]), Color(0.9, 0.85, 0.7), 14)


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


func _ask_rect() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(vs.x / 2 - 200, 130, 400, 54 + 30 * 3)


func _ask_click(pos: Vector2) -> bool:
	var ask := _active_ask()
	if ask.is_empty():
		return false
	var r := _ask_rect()
	if not r.has_point(pos):
		return false
	var i := int((pos.y - r.position.y - 46) / 30)
	if i >= 0 and i < (ask["options"] as Array).size():
		_send({"t": "quest_answer", "quest": str(ask["q"]), "answer": i})
	return true


func _draw_ask(vs: Vector2) -> void:
	var ask := _active_ask()
	if ask.is_empty():
		return
	var r := _ask_rect()
	draw_rect(r, Color(0, 0, 0, 0.85))
	draw_rect(r, Color(1, 0.8, 0.3), false, 2.0)
	var dl: Array = ask["dialog"]
	var qline := "答題！" if dl.is_empty() else str(dl[0])
	if qline.length() > 30:
		qline = qline.substr(0, 29) + "…"
	_txt(r.position + Vector2(10, 18), qline, Color(1, 0.9, 0.5), 11)
	var opts: Array = ask["options"]
	for i in opts.size():
		var orr := Rect2(r.position + Vector2(10, 46 + 30 * i), Vector2(380, 26))
		draw_rect(orr, Color(0.25, 0.3, 0.5))
		draw_rect(orr, Color(1, 1, 1), false, 1.0)
		var ot := str(opts[i])
		if ot.length() > 26:
			ot = ot.substr(0, 25) + "…"
		_txt(orr.position + Vector2(8, 18), ot, Color.WHITE, 12)


# 記事面板 (Step 8, spec 06 §1.2): 進行中任務 + 提示；完成記錄
func _draw_quests(vs: Vector2) -> void:
	if not show_quests:
		return
	var qs := sim.view_quests()
	var lines: Array = []
	for q in qs:
		if bool(q.get("active", false)):
			var h: String = str(q.get("hint", ""))
			if h.length() > 26:
				h = h.substr(0, 25) + "…"
			lines.append("● %s — %s" % [q.name, h])
		elif bool(q.get("done", false)):
			lines.append("✓ %s (完成)" % q.name)
	var r := Rect2(vs.x - 330, 96, 324, 22 + 15 * maxi(1, lines.size()))
	draw_rect(r, Color(0, 0, 0, 0.82))
	draw_rect(r, Color(1, 0.85, 0.4), false, 1.5)
	_txt(r.position + Vector2(10, 16), "記事", Color(1, 0.9, 0.5), 12)
	if lines.is_empty():
		_txt(r.position + Vector2(10, 38), "未有任務 — 去城門口搵神秘老人", Color.GRAY, 11)
	for i in lines.size():
		_txt(r.position + Vector2(10, 38 + 15 * i), str(lines[i]), Color.WHITE, 11)


# 建角面板完成（mobile_hud)_on_create_done 用
func _on_create_done() -> void:
	show_quests = false
	_log("建角完成，出發！")

# 升級點數 / 理念 / 生日 / 稱號 狀態列 (Step 7.5 debug UI)
func _draw_char_status(vs: Vector2) -> void:
	if ch.is_empty():
		return
	var y := vs.y - 78
	draw_rect(Rect2(10, y - 6, 330, 62), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(10, y - 6, 330, 62), Color(1, 0.85, 0.4), false, 1.5)
	_txt(Vector2(16, y + 12), "點數 %d    理念 %s" % [int(ch.get("attrPoints", 0)), str(ch.get("ideology", "未測"))], Color(1, 1, 0.7), 12)
	_txt(Vector2(16, y + 30), "生日 %d月%d日    稱號「%s」" % [int(ch.get("birthMonth", 1)), int(ch.get("birthDay", 1)), str(ch.get("title", ""))], Color(0.85, 1, 0.8), 12)
	_txt(Vector2(16, y + 48), "Q自動派  E力量 F敏捷 D智力 S靈力 (用升級點數)" if int(ch.get("attrPoints", 0)) > 0 else "任務：城門口神秘老人 / 練兵場小兵 · 記事[J]睇任務", Color(0.85, 0.9, 1), 10)

func _draw_bag(vs: Vector2) -> void:
	if show_bag and not ch.is_empty():
		var bag: Array = ch.bag
		draw_rect(Rect2(vs.x - 190, 52, 184, 30 + 16 * maxi(1, bag.size())), Color(0, 0, 0, 0.7))
		_txt(Vector2(vs.x - 182, 70), "背包")
		for i in bag.size():
			var bid := int(bag[i].id)
			var tag := ""
			if quest_items.has(bid):
				tag = " (任)"
			_txt(Vector2(vs.x - 182, 88 + 16 * i), "%s x%d%s" % [item_names.get(bid, str(bid)), int(bag[i].n), tag])
