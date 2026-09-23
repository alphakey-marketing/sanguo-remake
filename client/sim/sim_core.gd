extends RefCounted
# Sim 繼承鏈 第 1 層: 核心狀態 / 讀取 / 共用 helper / 生成單位
# 鏈: sim_core -> sim_quest -> sim_char -> sim_econ -> sim_combat -> sim_skill -> sim_ai -> sim (class_name Sim)
# 規矩: 每層只可以叫自己或者下層嘅 func (上層 func 下層睇唔到)

signal event_emitted(ev: Dictionary)

const W := GameData.WORLD_W                            # 全域格仔 (多張地圖拼埋, spec 12 §2)
const H := GameData.WORLD_H
const NEAR := 3                                        # 設施互動距離(格)
const WITNESS_RANGE := 8                               # NPC 目擊範圍(格) (Step 5.2)
const GROUP_RANGE := 5                                 # 群居怪同類仇恨範圍(格) (Step 11, spec 04 §3)
const DEFAULT_ZONE := "field_1"
const PATH_CAP := 6000                                 # cmd_move A* 節點上限 (spec 12 §3)
const CHASE_CAP := 800                                 # 追擊 A* 節點上限

var data: GameData
var rng: SimRng
var rng_fn: Callable
var state: Dictionary = {}
var inn_pos := Vector2i(10, 10)   # 復活點(客棧)


func _init(game_data: GameData, seed_value: int = 1) -> void:
	data = game_data
	rng = SimRng.new(seed_value)
	rng_fn = Callable(rng, "next")
	state = {"tick": 0, "next_id": 1, "ents": {}, "respawns": [], "player_id": -1, "bots": [],
		"clock": {"day": 0, "ke": 0, "lastShichen": -1, "is_night": false}, "market": {}, "disasters": [],
		"quest_npcs": {}}		# npc_id -> {"visible": bool} (Step 8)
	inn_pos = Vector2i(int(data.inn["x"]), int(data.inn["y"]))
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
	return x >= 0 and y >= 0 and x < W and y < H and data.walk[y * W + x] == 1


# ---- 地圖 (spec 12) ----
func map_at(x: int, y: int) -> Dictionary:
	return data.map_at(x, y)


func map_id_at(x: int, y: int) -> String:
	return String(data.map_at(x, y).get("id", ""))


# 地圖內命名區 (許田圍場…)；冇 = ""
func area_name(x: int, y: int) -> String:
	for a in data.map_at(x, y).get("areas", []):
		if x >= int(a["x0"]) and x <= int(a["x1"]) and y >= int(a["y0"]) and y <= int(a["y1"]):
			return String(a["name"])
	return ""


# 直線行一步: 先行差距大嗰個軸 (同差距先 x)，被擋就試另一軸；行唔到 = 原位
# (唔好固定 x 先: 怪同人互追會左右跳舞永遠追唔到)
func _greedy_step(x: int, y: int, tx: int, ty: int) -> Vector2i:
	var dx := signi(tx - x)
	var dy := signi(ty - y)
	if absi(ty - y) > absi(tx - x):
		if dy != 0 and is_free(x, y + dy):
			return Vector2i(x, y + dy)
		if dx != 0 and is_free(x + dx, y):
			return Vector2i(x + dx, y)
	else:
		if dx != 0 and is_free(x + dx, y):
			return Vector2i(x + dx, y)
		if dy != 0 and is_free(x, y + dy):
			return Vector2i(x, y + dy)
	return Vector2i(x, y)


# 直線 (_greedy_step) 行唔行到 (x1,y1)；行到就唔使 A*
func _greedy_reaches(x0: int, y0: int, x1: int, y1: int) -> bool:
	var p := Vector2i(x0, y0)
	for _i in absi(x1 - x0) + absi(y1 - y0):
		var n := _greedy_step(p.x, p.y, x1, y1)
		if n == p:
			return false
		p = n
	return p.x == x1 and p.y == y1


# 設目的地: 直線行唔到就 A* (spec 12 §3)；路徑存 e.path (全域 cell)，唔會經 auto 傳送點 (終點除外)
func _set_dest(e: Dictionary, x: int, y: int, cap: int = PATH_CAP) -> void:
	var path: Array = e.get("path", [])
	if int(e["tx"]) == x and int(e["ty"]) == y and (not path.is_empty() or _greedy_reaches(int(e["x"]), int(e["y"]), x, y)):
		return
	e["tx"] = x
	e["ty"] = y
	e.erase("path")
	if _greedy_reaches(int(e["x"]), int(e["y"]), x, y):
		return
	var p := RulesPath.find(data.walk, W, int(e["y"]) * W + int(e["x"]), y * W + x, cap, data.portal_at)
	if not p.is_empty():
		e["path"] = p


# ---- 安全區 / 戰鬥區 (data/zones.json) ----
func zone_by_id(zone_id: String) -> Dictionary:
	for z in data.zones:
		if String(z["id"]) == zone_id:
			return z
	return {}


# 某格所在 zone (UI 用: 渲染顏色/顯示區名)。搵唔到 = {}
func zone_view(x: int, y: int) -> Dictionary:
	for z in data.zones:
		if x >= int(z["x0"]) and x <= int(z["x1"]) and y >= int(z["y0"]) and y <= int(z["y1"]):
			return {"id": str(z["id"]), "name": str(z.get("name", z["id"])), "area": area_name(x, y)}
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
	e["max_hp"] = _eff_max_hp(ch)
	e["level"] = int(ch["level"])


# 輔助石加成 (Step 10, spec 02 §4): 裝備 2 格寶石欄" 嘅效果加總
func _jewel_bonus(ch: Dictionary) -> Dictionary:
	var jw: Array = ch["equip"].get("jewels", [0, 0]) as Array
	var list: Array = []
	for it in jw:
		var jd: Dictionary = data.jewel_by_item.get(int(it), {})
		if not jd.is_empty() and str(jd.get("kind", "")) == "support" and not jd.get("effects", []).is_empty():
			list.append(RulesJewel.jewel_bonus(jd))
	return RulesJewel.sum_bonus(list)


func _eff_max_hp(ch: Dictionary) -> int:
	return MathX.js_round(RulesStats.max_hp(int(ch["level"]), ch["attrs"]) * (1.0 + float(_jewel_bonus(ch).get("hpPct", 0.0))))


func _eff_max_mp(ch: Dictionary) -> int:
	return MathX.js_round(RulesStats.max_mp(int(ch["level"]), ch["attrs"]) * (1.0 + float(_jewel_bonus(ch).get("mpPct", 0.0))))


func _eff_max_sp(ch: Dictionary) -> int:
	return RulesStats.max_sp(int(ch["level"]), ch["attrs"]) + int(_jewel_bonus(ch).get("spFlat", 0))


# 裝備緊嘅屬性石 (slot 0, 攻擊用) → {elem, pct} / {}
func _equip_stone(ch: Dictionary) -> Dictionary:
	var it := int(ch["equip"].get("jewels", [0, 0])[0])
	var jd: Dictionary = data.jewel_by_item.get(it, {})
	if jd.is_empty() or str(jd.get("kind", "")) != "stone":
		return {}
	return {"elem": str(jd["elem"]), "pct": float(int(jd["pct"])) / 100.0}


# 裝備武器嘅融合屬性 (義士融合 → 武器嵌石, spec 02 §6) → {elem, pct} / {}
func _fused_stone(ch: Dictionary) -> Dictionary:
	var w := int(ch["equip"].get("weapon", 0))
	if w == 0:
		return {}
	var f: Dictionary = ch.get("fusedJewels", {})
	# 存檔 roundtrip 後 dict key 會變 String
	var out: Dictionary = f.get(str(w), {})
	if out.is_empty():
		out = f.get(w, {})
	return out


# 物理攻擊屬性倍率: 融合石優先，否則裝備 slot 0 屬性石；冇石 = 1.0
func _phys_elem_mult(ch: Dictionary, def_elem: String) -> float:
	var f := _fused_stone(ch)
	var stone := f if not f.is_empty() else _equip_stone(ch)
	if stone.is_empty():
		return 1.0
	return RulesJewel.element_mult(str(stone["elem"]), float(stone["pct"]), def_elem)


# fusedJewels 清理: 背包已經冇嗰件武器就刪
func _cleanup_fused(ch: Dictionary) -> void:
	var f: Dictionary = ch.get("fusedJewels", {})
	for k in f.keys():
		if RulesShop.count_item(ch["bag"], int(k)) <= 0:
			f.erase(k)


func _spawn_actor(ename: String, kind: String, class_id: String = "yishi") -> Dictionary:
	var sp: Array = _home_map().get("spawn", [int(data.inn["x"]) - 2, int(data.inn["y"]) - 2, int(data.inn["x"]) + 2, int(data.inn["y"]) + 2])
	var e := _new_ent(ename, kind, _pick_free(int(sp[0]), int(sp[1]), int(sp[2]), int(sp[3])))
	e["ch"] = RulesStats.create_character(data, ename.substr(0, 8), class_id)
	e["ch"]["tools"] = {}                     # skill -> {item, dur} (Step 7.1)
	e["ch"]["storage"] = []                   # 天地商行倉庫 [{id,n}] (Step 7.2)
	e["ch"]["storageSub"] = false             # 有冇訂閱天地商行 (200/日)
	e["ch"]["equip"]["spellbooks"] = [0, 0, 0]   # 術法快捷列 3 格 (Step 9, spec 02 §3.1)
	e["ch"]["equip"]["jewels"] = [0, 0]         # 寶石欄 2 格 (Step 10, spec 02 §4)
	e["ch"]["ultimates"] = []                   # 已學絕招 (spec 02 §5)
	e["ch"]["ultCd"] = {}                       # ultId -> until tick
	e["ch"]["fusedJewels"] = {}                 # 武器嵌石: weapon item id -> {elem, pct} (融合, 只能 1 粒)
	e["ch"]["fusing"] = {}                      # 進行中融合 QTE {weapon, jewel, start} (Step 10)
	_sync_stats(e)
	return e




# 新手城地圖 (world.homeCity)
func _home_map() -> Dictionary:
	for md in data.maps:
		if String(md.get("city", "")) == String(data.world["homeCity"]):
			return md
	return {}


func add_bots(n: int) -> void:
	for i in n:
		var nm: String = BotSys.NAMES[i % BotSys.NAMES.size()] + (str(i) if i >= BotSys.NAMES.size() else "")
		var e := _spawn_actor(nm, "bot")
		BotSys.init_identity(e, rng)
		state["bots"].append(int(e["id"]))


func init_mobs() -> void:
	for sp in data.spawns:
		if sp.get("night", false):
			continue                    # 夜怪由 _sync_night_spawns 處理
		for i in int(sp["count"]):
			_spawn_mob(int(sp["monster"]), String(sp.get("zone", DEFAULT_ZONE)))


func _spawn_mob(def_id: int, zone_id: String = DEFAULT_ZONE) -> Variant:
	var d: Dictionary = data.monsters[def_id]
	if d.get("night", false) and not _clock().is_night:
		return null                     # 夜怪白天唔生
	var z := zone_by_id(zone_id)
	var r := [int(z["x0"]), int(z["y0"]), int(z["x1"]), int(z["y1"])]
	# spawn 可選 area [x0,y0,x1,y1]: 限喺 zone 入面一塊 (例如北門附近只出低等怪)
	for sp in data.spawns:
		if int(sp["monster"]) == def_id and String(sp.get("zone", DEFAULT_ZONE)) == zone_id and sp.has("area"):
			var a: Array = sp["area"]
			r = [int(a[0]), int(a[1]), int(a[2]), int(a[3])]
			break
	var p := _pick_free(r[0], r[1], r[2], r[3])
	var e := _new_ent(String(d["name"]), "mob", p)
	e["face"] = 0
	e["hp"] = int(d["hp"])
	e["max_hp"] = int(d["hp"])
	e["level"] = int(d["level"])
	e["mob"] = {"def": def_id, "home_x": p.x, "home_y": p.y, "state": "wander", "target": 0, "next_atk": 0, "zone": zone_id}
	return e



# 目擊/傳聞入口 (Step 5.2): actor_id 做咗一件事，附近有記憶表嘅 NPC (bot) 記低 + 調好感
func _witness_nearby(actor_e: Dictionary, actor_id: int, kind: String, weight: int) -> void:
	for w in ents.values():
		if int(w["id"]) == actor_id or not w.has("mem"):
			continue
		if RulesCombat.in_range(actor_e["x"], actor_e["y"], w["x"], w["y"], WITNESS_RANGE):
			NpcMemory.witness(w["mem"], actor_id, kind, tick, weight)


func _near(e: Dictionary, x: int, y: int) -> bool:
	return RulesCombat.in_range(e["x"], e["y"], x, y, NEAR)


func _full_heal(ch: Dictionary) -> void:
	# 輔助石加成: 用有效上限 (Step 10, spec 02 §4)
	ch["hp"] = _eff_max_hp(ch)
	ch["mp"] = _eff_max_mp(ch)
	ch["sp"] = _eff_max_sp(ch)
