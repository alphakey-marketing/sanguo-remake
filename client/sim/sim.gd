class_name Sim
extends RefCounted
# 單機世界模擬: 格子地圖 + 單位 + 即時戰鬥 + 怪物 AI + 設施。
# - state 全部係純資料 (Dictionary/Array/int/String)，可直接存檔；RNG 由種子驅動 → 可重現
# - UI 只透過 cmd_* 發意圖、透過 event_emitted 收事件、透過 view_ents()/player_ch() 讀狀態
# 由 server/src/world.ts 重寫 (去 AOI/ws)；規則喺 rules/*.gd

signal event_emitted(ev: Dictionary)

const W := 64
const H := 64
const NEAR := 3                                        # 設施互動距離(格)
const DEFAULT_ZONE := "field_1"

var data: GameData
var rng: SimRng
var rng_fn: Callable
var state: Dictionary = {}
var blocked: Dictionary = {}      # y*W+x -> true (地形常量，唔入存檔)
var inn_pos := Vector2i(10, 10)   # 復活點(客棧)


func _init(game_data: GameData, seed_value: int = 1) -> void:
	data = game_data
	rng = SimRng.new(seed_value)
	rng_fn = Callable(rng, "next")
	state = {"tick": 0, "next_id": 1, "ents": {}, "respawns": [], "player_id": -1, "bots": [],
		"clock": {"day": 0, "ke": 0, "lastShichen": -1, "is_night": false}, "market": {}, "disasters": []}
	inn_pos = Vector2i(int(data.inn["x"]), int(data.inn["y"]))
	_build_terrain()
	_init_markets()

# 每城每類物資: 庫存 = vol, 價格因子 = 1.0
func _init_markets() -> void:
	var cats: Dictionary = data.world["market"]["cats"]
	var mkt: Dictionary = state["market"]
	for c in data.world["cities"]:
		var cm := {}
		for k in cats:
			var g: Dictionary = cats[k]
			cm[k] = {"stock": float(g["vol"]), "pf": 1.0}
		mkt[c.id] = cm


func _build_terrain() -> void:
	for i in range(10, 30):
		blocked[20 * W + i] = true
	for i in range(30, 50):
		blocked[i * W + 40] = true


# ---- 讀取 ----
var tick: int:
	get: return int(state["tick"])
var ents: Dictionary:
	get: return state["ents"]

func _clock() -> Dictionary:
	return state["clock"]

func clock_view() -> Dictionary:
	var clk: Dictionary = _clock()
	var season := RulesClock.season_of_day(int(clk["day"]), int(data.world["clock"]["seasonDays"]))
	return {"ke": int(clk["ke"]), "day": int(clk["day"]), "season": season, "is_night": bool(clk["is_night"]),
		"text": RulesClock.format(int(clk["ke"]), int(clk["day"]), int(data.world["clock"]["seasonDays"]))}

func active_disasters() -> Array:
	var out: Array = []
	for d in state["disasters"]:
		if str(d["city"]) == str(data.world["homeCity"]):
			out.append({"name": d["name"], "size": d["size"], "endDay": d["endDay"]})
	return out

# 物品價格因子 (商店用): 每城每 cat 一個 market 狀態；唔喺市場 cat 內 = 1.0
func market_factor(item_id: int) -> float:
	var home := str(data.world["homeCity"])
	var m: Dictionary = state["market"].get(home, {})
	var g: Dictionary = m.get(str(int(data.cats.get(item_id, 0))), {})
	return float(g.get("pf", 1.0)) if not g.is_empty() else 1.0

func market_city(city: String, cat: String) -> Dictionary:
	var m: Dictionary = state["market"].get(city, {})
	return m.get(cat, {})


func is_free(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and not blocked.has(y * W + x)


# ---- 安全區 / 戰鬥區 (data/zones.json) ----
func zone_by_id(zone_id: String) -> Dictionary:
	for z in data.zones:
		if String(z["id"]) == zone_id:
			return z
	return {}


# 邊界內第一個匹配嘅 zone；搵唔到當安全 (例如冇定義嘅角落)
func is_safe(x: int, y: int) -> bool:
	for z in data.zones:
		if x >= int(z["x0"]) and x <= int(z["x1"]) and y >= int(z["y0"]) and y <= int(z["y1"]):
			return bool(z["safe"])
	return true


func travel_point_by_id(point_id: String) -> Dictionary:
	for p in data.travel_points:
		if String(p["id"]) == point_id:
			return p
	return {}


func ent(id: int) -> Dictionary:
	return ents.get(id, {})


func player_ch() -> Dictionary:
	var e := ent(int(state["player_id"]))
	return e.get("ch", {})


func _emit(ev: Dictionary) -> void:
	event_emitted.emit(ev)


func _msg(id: int, text: String) -> void:
	if ent(id).get("kind", "") == "player":     # bot 唔使收訊息
		_emit({"k": "msg", "dst": id, "text": text})


func _pick_free(x0: int, y0: int, x1: int, y1: int) -> Vector2i:
	while true:
		var x := x0 + rng.below(x1 - x0 + 1)
		var y := y0 + rng.below(y1 - y0 + 1)
		if is_free(x, y):
			return Vector2i(x, y)
	return Vector2i.ZERO


func _new_ent(ename: String, kind: String, pos: Vector2i) -> Dictionary:
	var id := int(state["next_id"])
	state["next_id"] = id + 1
	var e := {
		"id": id, "name": ename, "kind": kind, "x": pos.x, "y": pos.y, "tx": pos.x, "ty": pos.y,
		"face": id % 12, "hp": 0, "max_hp": 0, "level": 1, "atk_target": 0, "next_atk": 0,
	}
	ents[id] = e
	return e


func _sync_stats(e: Dictionary) -> void:
	var ch: Dictionary = e.get("ch", {})
	if ch.is_empty():
		return
	e["hp"] = int(ch["hp"])
	e["max_hp"] = RulesStats.max_hp(int(ch["level"]), ch["attrs"])
	e["level"] = int(ch["level"])


func _spawn_actor(ename: String, kind: String) -> Dictionary:
	var e := _new_ent(ename, kind, _pick_free(5, 5, 24, 16))
	e["ch"] = RulesStats.create_character(data, ename.substr(0, 8), "yishi")
	_sync_stats(e)
	return e


func spawn_player(pname: String) -> int:
	var e := _spawn_actor(pname, "player")
	state["player_id"] = e["id"]
	return int(e["id"])


func add_bots(n: int) -> void:
	for i in n:
		var nm: String = BotSys.NAMES[i % BotSys.NAMES.size()] + (str(i) if i >= BotSys.NAMES.size() else "")
		state["bots"].append(int(_spawn_actor(nm, "bot")["id"]))


func init_mobs() -> void:
	for sp in data.spawns:
		if sp.get("night", false):
			continue                    # 夜怪由 _sync_night_spawns 處理
		for i in int(sp["count"]):
			_spawn_mob(int(sp["monster"]), String(sp.get("zone", DEFAULT_ZONE)))


func _spawn_mob(def_id: int, zone_id: String = DEFAULT_ZONE):
	var d: Dictionary = data.monsters[def_id]
	if d.get("night", false) and not _clock().is_night:
		return null                     # 夜怪白天唔生
	var z := zone_by_id(zone_id)
	var p := _pick_free(int(z["x0"]), int(z["y0"]), int(z["x1"]), int(z["y1"]))
	var e := _new_ent(String(d["name"]), "mob", p)
	e["face"] = 0
	e["hp"] = int(d["hp"])
	e["max_hp"] = int(d["hp"])
	e["level"] = int(d["level"])
	e["mob"] = {"def": def_id, "home_x": p.x, "home_y": p.y, "state": "wander", "target": 0, "next_atk": 0}
	return e


# 玩家/機械人 意圖

# 設施互動 (Step 3.2): training=練兵場 school=私塾 temple=寺廟
func cmd_facility(id: int, key: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var f: Dictionary = data.facilities.get(key, {})
	if f.is_empty():
		return
	if not _near(e, int(f["x"]), int(f["y"])):
		return _msg(id, "要行近%s先得" % f["name"])
	var ch: Dictionary = e["ch"]
	match key:
		"training": _fac_training(e, ch, f)
		"school": _fac_attr(e, ch, f, "pol")
		"temple": _fac_attr(e, ch, f, "cha")


# 練兵場【原】: 2 人對練, 扣 HP+SP, +歷練 (升級時武/智/敏/靈提升)
func _fac_training(e: Dictionary, ch: Dictionary, f: Dictionary) -> void:
	var lv := int(ch["level"])
	var mhp := RulesStats.max_hp(lv, ch["attrs"])
	var msp := RulesStats.max_sp(lv, ch["attrs"])
	var id := int(e["id"])
	if tick < int(e.get("train_cd", 0)):
		return _msg(id, "啱啱練完，抖陣先")
	if int(ch["hp"]) < mhp * 0.35:
		return _msg(id, "體力唔夠對練 (HP 要 > 35%)")
	var lilian := int(ch.get("lilian", 0))
	if lilian >= int(f["lilianCap"]):
		return _msg(id, "歷練已滿 (%d)" % int(f["lilianCap"]))
	# 附近要有拍檔 (玩家或 bot)
	var partner := {}
	for b in ents.values():
		if int(b["id"]) == id or not b.has("ch") or int(b["hp"]) <= 0:
			continue
		if _near(e, int(b["x"]), int(b["y"])):
			partner = b
			break
	if partner.is_empty():
		return _msg(id, "附近冇人可以對練")
	ch["hp"] = maxi(1, int(ch["hp"]) - MathX.js_round(mhp * float(f["costHp"])))
	ch["sp"] = maxi(1, int(ch["sp"]) - MathX.js_round(msp * float(f["costSp"])))
	var pch: Dictionary = partner["ch"]
	pch["hp"] = maxi(1, int(pch["hp"]) - MathX.js_round(RulesStats.max_hp(int(pch["level"]), pch["attrs"]) * float(f["costHp"])))
	partner["hp"] = int(pch["hp"])
	_sync_stats(e)
	ch["lilian"] = lilian + int(f["lilian"])
	e["train_cd"] = tick + int(f["cooldownTicks"])
	_emit({"k": "train", "src": id, "partner": partner["name"], "lilian": int(ch["lilian"])})


# 私塾/寺廟【原】: 政治/魅力 +1, 扣 SP (+MP) + 金
func _fac_attr(e: Dictionary, ch: Dictionary, f: Dictionary, attr: String) -> void:
	var id := int(e["id"])
	var lv := int(ch["level"])
	var cost_gold := int(f.get("gold", 0))
	var cost_sp := MathX.js_round(RulesStats.max_sp(lv, ch["attrs"]) * float(f.get("costSp", 0.0)))
	var cost_mp := MathX.js_round(RulesStats.max_mp(lv, ch["attrs"]) * float(f.get("costMp", 0.0)))
	if int(ch["gold"]) < cost_gold:
		return _msg(id, "要 %d 金" % cost_gold)
	if int(ch["sp"]) < cost_sp or int(ch["mp"]) < cost_mp:
		return _msg(id, "精神不足 (要 SP%d/MP%d)" % [cost_sp, cost_mp])
	var v := int(ch["attrs"][attr])
	if v >= int(f["attrCap"]):
		return _msg(id, "屬性已到上限 (%d)" % int(f["attrCap"]))
	ch["gold"] = int(ch["gold"]) - cost_gold
	ch["sp"] = int(ch["sp"]) - cost_sp
	ch["mp"] = int(ch["mp"]) - cost_mp
	ch["attrs"][attr] = v + 1
	_sync_stats(e)
	var an := "政治" if attr == "pol" else "魅力"
	_emit({"k": "train", "src": id, "type": "attr", "attr": an, "val": v + 1})
func cmd_move(id: int, x: int, y: int) -> void:
	var e := ent(id)
	if not e.is_empty() and is_free(x, y):
		e["tx"] = x
		e["ty"] = y
		e["atk_target"] = 0      # 手動行路取消攻擊


func cmd_attack(id: int, target: int) -> void:
	var e := ent(id)
	var t := ent(target)
	if e.has("ch") and int(e["hp"]) > 0 and t.get("kind", "") == "mob":
		e["atk_target"] = target      # 安全區入面都可以追過去，行出安全區先真正出手 (見 _think_player)


# 傳送點 (Step 3.2+): 城內/城外之間即時傳送，要行近出發點
func cmd_travel(id: int, point_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var from_p := travel_point_by_id(point_id)
	if from_p.is_empty():
		return
	if not _near(e, int(from_p["x"]), int(from_p["y"])):
		return _msg(id, "要行近%s先得" % String(from_p["name"]))
	var to_p := travel_point_by_id(String(from_p["to"]))
	if to_p.is_empty():
		return
	e["x"] = int(to_p["x"])
	e["y"] = int(to_p["y"])
	e["tx"] = e["x"]
	e["ty"] = e["y"]
	e["atk_target"] = 0
	_emit({"k": "travel", "dst": id, "to": String(to_p["name"]), "x": e["x"], "y": e["y"]})


func cmd_chat(id: int, text: String) -> void:
	var e := ent(id)
	text = text.strip_edges().substr(0, 60)
	if not e.is_empty() and text != "":
		_emit({"k": "chat", "id": id, "name": e["name"], "text": text, "x": e["x"], "y": e["y"]})


func _near(e: Dictionary, x: int, y: int) -> bool:
	return RulesCombat.in_range(e["x"], e["y"], x, y, NEAR)


func _full_heal(ch: Dictionary) -> void:
	var lv := int(ch["level"])
	ch["hp"] = RulesStats.max_hp(lv, ch["attrs"])
	ch["mp"] = RulesStats.max_mp(lv, ch["attrs"])
	ch["sp"] = RulesStats.max_sp(lv, ch["attrs"])


func cmd_rest(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var cost := int(data.inn["restCost"])
	if not _near(e, inn_pos.x, inn_pos.y):
		return _msg(id, "要喺客棧附近先可以休息")
	var ch: Dictionary = e["ch"]
	if int(ch["gold"]) < cost:
		return _msg(id, "住宿要 %d 金" % cost)
	ch["gold"] = int(ch["gold"]) - cost
	_full_heal(ch)
	_sync_stats(e)
	_msg(id, "休息完畢，花 %d 金" % cost)


func _shop_for(e: Dictionary) -> Dictionary:
	for s in data.shops:
		if _near(e, int(s["x"]), int(s["y"])):
			return s
	return {}


func cmd_buy(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	n = mini(99, n)
	if e.is_empty() or not e.has("ch") or n < 1:
		return
	var shop := _shop_for(e)
	if shop.is_empty():
		return _msg(id, "附近冇商店")
	var stock: Array = shop["stock"]
	if not stock.has(item) and not stock.has(float(item)):
		return _msg(id, "呢間店唔賣呢件")
	var ch: Dictionary = e["ch"]
	var cost := RulesShop.buy_price(data.prices.get(item, 0.0), ch["attrs"]["cha"]) * n
	if int(ch["gold"]) < cost:
		return _msg(id, "金錢不足，要 %d" % cost)
	ch["gold"] = int(ch["gold"]) - cost
	RulesShop.add_item(ch["bag"], item, n)
	_msg(id, "買咗 %d 件，花 %d 金" % [n, cost])


func cmd_sell(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	n = mini(99, n)
	if e.is_empty() or not e.has("ch") or n < 1:
		return
	if _shop_for(e).is_empty():
		return _msg(id, "附近冇商店")
	var ch: Dictionary = e["ch"]
	var have := 0
	for b in ch["bag"]:
		if int(b["id"]) == item:
			have = int(b["n"])
	if int(ch["equip"].get("weapon", 0)) == item and have <= n:
		return _msg(id, "裝備中，唔可以賣")
	if not RulesShop.remove_item(ch["bag"], item, n):
		return _msg(id, "背包冇咁多")
	var gain := RulesShop.sell_price(data.prices.get(item, 0.0)) * n
	ch["gold"] = int(ch["gold"]) + gain
	_msg(id, "賣出 %d 件，得 %d 金" % [n, gain])


# ================= 戰鬥 =================
func damage(t: Dictionary, dmg: int, by: Dictionary) -> void:
	t["hp"] = maxi(0, int(t["hp"]) - dmg)
	if t["kind"] == "mob" and by.has("ch"):
		t["mob"]["state"] = "chase"
		t["mob"]["target"] = by["id"]
	if t.has("ch"):
		t["ch"]["hp"] = t["hp"]
	if int(t["hp"]) > 0:
		return
	if t["kind"] == "mob":
		_kill_mob(t, by)
	elif t.has("ch"):
		_kill_player(t)


func _kill_mob(m: Dictionary, by: Dictionary) -> void:
	var d: Dictionary = data.monsters[int(m["mob"]["def"])]
	ents.erase(m["id"])
	var delay := 200
	var zone_id := DEFAULT_ZONE
	for sp in data.spawns:
		if int(sp["monster"]) == int(d["id"]):
			delay = int(sp["respawnTicks"])
			zone_id = String(sp.get("zone", DEFAULT_ZONE))
			break
	state["respawns"].append({"at": tick + delay, "def": int(d["id"]), "zone": zone_id})
	for e in ents.values():
		if int(e["atk_target"]) == int(m["id"]):
			e["atk_target"] = 0
	if not by.has("ch"):
		return
	var ch: Dictionary = by["ch"]
	var gold := RulesCombat.roll_gold(d["gold"], rng_fn)
	var items := RulesCombat.roll_drops(d["drops"], rng_fn)
	ch["gold"] = int(ch["gold"]) + gold
	for it in items:
		RulesShop.add_item(ch["bag"], int(it), 1)
	ch["karma"] = RulesCombat.karma_after_kill(int(ch["karma"]), d["alignment"])
	var ups := RulesStats.gain_exp(data, ch, int(d["exp"]))
	_sync_stats(by)
	_emit({"k": "kill", "src": by["id"], "dst": m["id"], "exp": int(d["exp"]), "gold": gold, "items": items,
		"lvUp": int(ch["level"]) if ups > 0 else 0})


func _kill_player(p: Dictionary) -> void:
	var ch: Dictionary = p["ch"]
	ch["exp"] = maxi(0, int(ch["exp"]) - RulesCombat.death_exp_loss(int(ch["karma"]), RulesStats.exp_to_next(int(ch["level"]))))
	var lost := RulesCombat.roll_death_drop(int(ch["karma"]), ch["bag"], rng_fn)
	if lost > 0:
		RulesShop.remove_item(ch["bag"], lost, 1)
	_full_heal(ch)
	p["x"] = inn_pos.x
	p["tx"] = inn_pos.x
	p["y"] = inn_pos.y
	p["ty"] = inn_pos.y
	p["atk_target"] = 0
	_sync_stats(p)
	_emit({"k": "die", "dst": p["id"], "lost": lost})


# 怪物 AI: 遊蕩 / 仇恨追擊 / 脫戰回歸
func _think_mob(m: Dictionary) -> void:
	var s: Dictionary = m["mob"]
	var d: Dictionary = data.monsters[int(s["def"])]
	var tgt := ent(int(s["target"]))
	if s["state"] == "chase":
		var lost := tgt.is_empty() or not tgt.has("ch") or int(tgt["hp"]) <= 0 \
			or maxi(absi(int(m["x"]) - int(s["home_x"])), absi(int(m["y"]) - int(s["home_y"]))) > int(d["leash"])
		if lost:
			s["state"] = "return"
			s["target"] = 0
			m["tx"] = s["home_x"]
			m["ty"] = s["home_y"]
			return
		if RulesCombat.in_range(m["x"], m["y"], tgt["x"], tgt["y"]):
			m["tx"] = m["x"]
			m["ty"] = m["y"]
			if tick >= int(s["next_atk"]):
				s["next_atk"] = tick + int(d["atkInterval"])
				var dmg := RulesCombat.calc_mob_damage(d["atk"], RulesCombat.player_def(int(tgt["ch"]["level"])), rng_fn)
				_emit({"k": "hit", "src": m["id"], "dst": tgt["id"], "dmg": dmg})
				damage(tgt, dmg, m)
		else:
			m["tx"] = tgt["x"]
			m["ty"] = tgt["y"]
		return
	if s["state"] == "return":
		m["hp"] = mini(int(m["max_hp"]), int(m["hp"]) + int(ceil(int(m["max_hp"]) / 20.0)))    # 脫戰回血
		if int(m["x"]) == int(s["home_x"]) and int(m["y"]) == int(s["home_y"]):
			s["state"] = "wander"
		return
	# wander: 搵仇恨目標，否則隨機遊蕩
	if int(d["aggroRange"]) > 0:
		var best := {}
		var best_d := 1 << 30
		for p in ents.values():
			if not p.has("ch") or int(p["hp"]) <= 0:
				continue
			var dist := maxi(absi(int(p["x"]) - int(m["x"])), absi(int(p["y"]) - int(m["y"])))
			if dist <= int(d["aggroRange"]) and dist < best_d:
				best = p
				best_d = dist
		if not best.is_empty():
			s["state"] = "chase"
			s["target"] = best["id"]
			return
	if int(m["x"]) == int(m["tx"]) and int(m["y"]) == int(m["ty"]) and rng.next() < 0.05:
		var nx := int(s["home_x"]) + rng.below(7) - 3
		var ny := int(s["home_y"]) + rng.below(7) - 3
		if is_free(nx, ny):
			m["tx"] = nx
			m["ty"] = ny


# 玩家/機械人自動追擊 + 出手
func _think_player(p: Dictionary) -> void:
	if int(p["atk_target"]) == 0 or not p.has("ch"):
		return
	var t := ent(int(p["atk_target"]))
	if t.is_empty() or int(t["hp"]) <= 0 or int(p["hp"]) <= 0:
		p["atk_target"] = 0
		return
	if not RulesCombat.in_range(p["x"], p["y"], t["x"], t["y"]):
		p["tx"] = t["x"]
		p["ty"] = t["y"]
		return
	p["tx"] = p["x"]
	p["ty"] = p["y"]
	if is_safe(int(p["x"]), int(p["y"])):
		return     # 安全區唔畀出手 (理論上怪唔會入城，呢度做多重保險)
	if tick < int(p["next_atk"]):
		return
	var ch: Dictionary = p["ch"]
	var w: Dictionary = data.weapons.get(int(ch["equip"].get("weapon", 0)), {"power": 0.0, "hit": 45.0})
	p["next_atk"] = tick + RulesCombat.attack_interval(ch["attrs"]["agi"])
	if rng.next() >= RulesCombat.hit_chance(w["hit"], int(ch["level"]), int(t["level"])):
		_emit({"k": "hit", "src": p["id"], "dst": t["id"], "dmg": 0})     # miss
		t["mob"]["state"] = "chase"
		t["mob"]["target"] = p["id"]
		return
	var mdef: Dictionary = data.monsters[int(t["mob"]["def"])]
	var dmg := RulesCombat.calc_damage(ch["attrs"]["str"], w["power"], mdef["def"], rng_fn)
	_emit({"k": "hit", "src": p["id"], "dst": t["id"], "dmg": dmg})
	damage(t, dmg, p)


# ---- 世界時鐘 / 天災 / 市場 (Step 4) ----
func _advance_clock() -> void:
	var clk: Dictionary = _clock()
	var min_per_tick := int(data.world["clock"]["gameMinPerTick"])
	var ke := RulesClock.ke_of_tick(tick, min_per_tick)
	var day := RulesClock.day_of_tick(tick, min_per_tick)
	var new_day := day != int(clk["day"])
	clk["day"] = day
	clk["ke"] = ke
	clk["is_night"] = RulesClock.is_night(ke, int(data.world["night"]["startKe"]), int(data.world["night"]["endKe"]))
	var shi := RulesClock.shichen_of_ke(ke)
	if new_day:
		_daily_hook(day)
	if shi != int(clk.get("lastShichen", -1)):
		clk["lastShichen"] = shi
		_sync_night_spawns()


# 每日子時: 天災擲骰 -> 市場日結 -> 通知 UI
func _daily_hook(day: int) -> void:
	var disas: Array = state["disasters"]
	RulesDisaster.expire(disas, day)
	var season := RulesClock.season_of_day(day, int(data.world["clock"]["seasonDays"]))
	var changed: Array = []
	for c in data.world["cities"]:
		var d := RulesDisaster.roll_day(rng_fn, day, season, String(c.id), data.world["disasters"])
		if not d.is_empty():
			disas.append(d)
			changed.append(d)
	_market_daily(season)
	_emit({"k": "day", "day": day, "season": season})
	for d in changed:
		_emit({"k": "disaster", "name": d["name"], "city": d["city"], "size": d["size"]})


func _market_daily(season: int) -> void:
	var cfg: Dictionary = data.world["market"]
	for c in data.world["cities"]:
		var city_dis := []
		for d in state["disasters"]:
			if str(d["city"]) == str(c.id):
				city_dis.append(d)
		var sm := RulesMarket.supply_mods(season, cfg["seasonSupply"], city_dis, c)
		var dm := RulesMarket.demand_mods(season, cfg["seasonDemand"])
		RulesMarket.daily(c, state["market"][c.id], cfg, sm, dm)


# 入夜: 補夜怪；天光: 夜怪消失
func _sync_night_spawns() -> void:
	var night := bool(_clock()["is_night"])
	for sp in data.spawns:
		if not sp.get("night", false):
			continue
		if night:
			var have := 0
			for e in ents.values():
				if e["kind"] == "mob" and int(e["mob"]["def"]) == int(sp["monster"]):
					have += 1
			for i in int(sp["count"]) - have:
				if _spawn_mob(int(sp["monster"]), String(sp.get("zone", DEFAULT_ZONE))) == null:
					break
		else:
			for id0 in ents.keys():
				var e: Dictionary = ents.get(id0, {})
				if not e.is_empty() and e["kind"] == "mob" and data.monsters[int(e["mob"]["def"])].get("night", false):
					ents.erase(id0)
					for e2 in ents.values():
						if int(e2["atk_target"]) == int(id0):
							e2["atk_target"] = 0


# 每 tick: 時鐘 -> 日結(天災/市場) -> 夜怪 -> 機械人思考 -> 戰鬥/AI -> 重生 -> 移動 (一格)
func step() -> void:
	state["tick"] = tick + 1
	_advance_clock()
	BotSys.think(self)
	for id in ents.keys():
		var e: Dictionary = ents.get(id, {})
		if e.is_empty():
			continue
		if e["kind"] == "mob":
			_think_mob(e)
		elif e.has("ch"):
			_think_player(e)
	var rs: Array = state["respawns"]
	for i in range(rs.size() - 1, -1, -1):
		if tick >= int(rs[i]["at"]):
			_spawn_mob(int(rs[i]["def"]), String(rs[i].get("zone", DEFAULT_ZONE)))     # 夜怪喺白天唔重生，天黑由 _sync_night_spawns 補
			rs.remove_at(i)
	for e in ents.values():
		var dx := signi(int(e["tx"]) - int(e["x"]))
		var dy := signi(int(e["ty"]) - int(e["y"]))
		if dx != 0 and is_free(int(e["x"]) + dx, int(e["y"])):
			e["x"] = int(e["x"]) + dx
		elif dy != 0 and is_free(int(e["x"]), int(e["y"]) + dy):
			e["y"] = int(e["y"]) + dy


# ================= UI 讀取 / 存檔 =================
# UI 用嘅單位視圖 (camelCase，同舊 server snapshot 一致)
func view_ents() -> Array:
	var out: Array = []
	for e in ents.values():
		out.append({"id": e["id"], "name": e["name"], "x": e["x"], "y": e["y"], "face": e["face"],
			"bot": e["kind"] == "bot", "hp": e["hp"], "maxHp": e["max_hp"], "level": e["level"], "mob": e["kind"] == "mob"})
	return out


func save_string() -> String:
	return JSON.stringify(_canonical({"state": state, "rng": rng.s}))


# 規範化: 整數 float → int、其他 float → 6 位小數。保證 save→load→save 字串一致
static func _canonical(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _canonical(v[k])
		return o
	if v is Array:
		var a := []
		for x in v:
			a.append(_canonical(x))
		return a
	if v is float:
		var f: float = v
		return int(f) if f == floor(f) else float(round(f * 1000000.0)) / 1000000.0
	return v


static func load_string(game_data: GameData, s: String) -> Sim:
	var d = JSON.parse_string(s)
	if not d is Dictionary:
		return null
	var sim := Sim.new(game_data, int(d["rng"]))
	var st: Dictionary = _intify(d["state"])
	var es := {}
	for k in st["ents"]:
		es[int(k)] = st["ents"][k]
	st["ents"] = es
	sim.state = st
	return sim


# JSON 讀返嚟數字全部係 float；整數值轉返 int
static func _intify(v: Variant) -> Variant:
	if v is float:
		return int(v) if v == floor(v) else v
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _intify(v[k])
		return o
	if v is Array:
		var a := []
		for x in v:
			a.append(_intify(x))
		return a
	return v
