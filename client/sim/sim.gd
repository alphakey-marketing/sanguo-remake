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
const WITNESS_RANGE := 8                               # NPC 目擊範圍(格) (Step 5.2)
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
	e["ch"]["tools"] = {}                     # skill -> {item, dur} (Step 7.1)
	e["ch"]["storage"] = []                   # 天地商行倉庫 [{id,n}] (Step 7.2)
	e["ch"]["storageSub"] = false             # 有冇訂閱天地商行 (200/日)
	_sync_stats(e)
	return e


func spawn_player(pname: String) -> int:
	var e := _spawn_actor(pname, "player")
	state["player_id"] = e["id"]
	return int(e["id"])


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


# ================= 升級點數 / 建角欄位 (Step 7.5, spec 01 §1/§2/§5) =================

# 升級自由點數: 扣 1 點，str/agi/int/spi +1；政治/魅力唔可以用升級點 (只能私塾/寺廟)
func cmd_raise_attr(id: int, attr: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var code := RulesStats.can_raise(ch, attr)
	match code:
		1: return _msg(id, "冇可分配點數 (升呢俾 %d 點)" % RulesStats.UPGRADE_POINTS)
		2: return _msg(id, "政治/魅力唔可以用升級點，去私塾/寺廟修練")
		3: return _msg(id, "屬性已到上限 99")
	RulesStats.raise_attr(ch, attr)
	_sync_stats(e)
	_emit({"k": "attr_rise", "src": id, "attr": attr, "val": int(ch["attrs"][attr]), "points": int(ch["attrPoints"])})


# 一鍵自動分配【自訂】: 按 classes.json.growth 建議比例派晒所有點
func cmd_auto_assign(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if int(ch.get("attrPoints", 0)) <= 0:
		return _msg(id, "冇可分配點數")
	RulesStats.auto_assign_points(ch, data.classes[ch["classId"]])
	_sync_stats(e)
	_emit({"k": "attr_auto", "src": id, "points": int(ch["attrPoints"])})
	_msg(id, "自動分配合成 (剩 %d 點)" % int(ch["attrPoints"]))


# 稱號【原】: ≤8 字，隨時可改
func cmd_set_title(id: int, title: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	title = title.strip_edges()
	if title.length() < 1 or title.length() > 8:
		return _msg(id, "稱號要 1~8 字")
	e["ch"]["title"] = title
	_msg(id, "稱號改做「%s」" % title)


# 生日: 影響福日 (生日嗰日練功 exp +10%) 同結婚年數
func cmd_set_birth(id: int, month: int, day: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var month_days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month < 1 or month > 12 or day < 1 or day > int(month_days[month - 1]):
		return _msg(id, "生日日期唔啱")
	e["ch"]["birthMonth"] = month
	e["ch"]["birthDay"] = day
	_msg(id, "生日設為 %d月%d日 (福日練功 +10%%)" % [month, day])


# 臉譜: 8 部位，款式 1..count (data/face.json)
func cmd_set_face(id: int, part: String, value: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var count: int = int(data.face_parts.get(part, 0))
	if count <= 0 or value < 1 or value > count:
		return _msg(id, "冇呢個部位/款式")
	e["ch"]["face"][part] = value
	_msg(id, "%s 款式設為 %d" % [part, value])


# 理念測驗: 一次過交答卷 (data/quiz.json 12 題，每題 0/1)，決定理念。決定了就唔可以改
func cmd_submit_quiz(id: int, answers: Array) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if not str(ch.get("ideology", "")).is_empty():
		return _msg(id, "理念已經決定咗，唔可以改")
	if not RulesQuiz.valid_answers(data, answers):
		return _msg(id, "答卷唔啱 (要 %d 題)" % (data.quiz as Array).size())
	var res := RulesQuiz.score(data, answers)
	ch["ideology"] = str(res["ideology"])
	ch["quizAnswers"] = []
	for a in answers:
		ch["quizAnswers"].append(int(a))
	_emit({"k": "quiz", "src": id, "ideology": str(res["ideology"])})
	_msg(id, "理念測驗完成：你嘅理念係「%s」" % str(res["ideology"]))
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
	if e.is_empty() or text == "":
		return
	_emit({"k": "chat", "id": id, "name": e["name"], "text": text, "x": e["x"], "y": e["y"]})
	_witness_nearby(e, id, "greet", BotSys.W_GREET)
	_npc_react(e, id)


# 居民對打招呼嘅反應 (Step 5.4): brain 淨係揀白名單動作 + 生成話語，數值(好感)已經由
# _witness_nearby 結算好，brain 唔改任何數值
func _npc_react(actor_e: Dictionary, actor_id: int) -> void:
	var actor_ch: Dictionary = ent(actor_id).get("ch", {})
	var karma_tier := RulesKarma.tier(int(actor_ch.get("karma", 0))) if not actor_ch.is_empty() else 3
	for w in ents.values():
		if int(w["id"]) == actor_id or not w.has("mem"):
			continue
		if not RulesCombat.in_range(actor_e["x"], actor_e["y"], w["x"], w["y"], WITNESS_RANGE):
			continue
		var ctx := {"actor_name": actor_e.get("name", ""), "affinity": NpcMemory.affinity(w["mem"], actor_id), "karma_tier": karma_tier}
		var res := NpcBrain.decide(ctx, rng.below(4))
		if res["action"] == "ignore":
			continue
		_emit({"k": "npc_say", "id": w["id"], "name": w["name"], "text": res["line"], "action": res["action"], "x": w["x"], "y": w["y"]})


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
	var cost := RulesShop.buy_price(data.prices.get(item, 0.0) * market_factor(item), ch["attrs"]["cha"], int(ch["karma"])) * n
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
	var gain := RulesShop.sell_price(data.prices.get(item, 0.0) * market_factor(item)) * n
	ch["gold"] = int(ch["gold"]) + gain
	_msg(id, "賣出 %d 件，得 %d 金" % [n, gain])


# debug 用: 直接派物品落背包 (未有商店/任務可以攞到嘅嘢，方便手機冇鍵盤都測到成條流程；成品前移除)
func cmd_debug_give(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	RulesShop.add_item(e["ch"]["bag"], item, n)


# 食用/飲用消耗品【原=食物藥水回 HP、藥丸散回 MP；自訂=冇食用次數限制，用完即扣背包一件】
func cmd_use_item(id: int, item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var heal: Dictionary = data.heals.get(item, {})
	if heal.is_empty():
		return _msg(id, "呢件唔可以食用")
	var ch: Dictionary = e["ch"]
	if not RulesShop.remove_item(ch["bag"], item, 1):
		return _msg(id, "背包冇呢件")
	var mhp := RulesStats.max_hp(int(ch["level"]), ch["attrs"])
	var mmp := RulesStats.max_mp(int(ch["level"]), ch["attrs"])
	var gained_hp := mini(int(heal.get("hp", 0)), mhp - int(ch["hp"]))
	var gained_mp := mini(int(heal.get("mp", 0)), mmp - int(ch["mp"]))
	ch["hp"] = int(ch["hp"]) + maxi(0, gained_hp)
	ch["mp"] = int(ch["mp"]) + maxi(0, gained_mp)
	_sync_stats(e)
	_msg(id, "用咗 %s，回 %d HP %d MP" % [data.names.get(item, str(item)), maxi(0, gained_hp), maxi(0, gained_mp)])


# ================= 天地商行 (Step 7.2)【原=功能：代買賣/存材料/買賣工具/休息；自訂=費用扣法已在 4.5 有嘅市場價/日費】=================
# 依家做「代買賣 + 存材料」；休息/買賣工具已有 cmd_rest/cmd_buy 頂替，唔使再重做一套

func cmd_storage_sub(id: int, on: bool) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	e["ch"]["storageSub"] = on
	_msg(id, "訂閱天地商行" if on else "退訂天地商行")


func cmd_storage_deposit(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	n = mini(99, n)
	if e.is_empty() or not e.has("ch") or n < 1:
		return
	var ch: Dictionary = e["ch"]
	if not bool(ch.get("storageSub", false)):
		return _msg(id, "要先訂閱天地商行")
	if not RulesShop.remove_item(ch["bag"], item, n):
		return _msg(id, "背包冇咁多")
	RulesShop.add_item(ch["storage"], item, n)
	_msg(id, "存咗 %d 件入天地商行" % n)


func cmd_storage_withdraw(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	n = mini(99, n)
	if e.is_empty() or not e.has("ch") or n < 1:
		return
	var ch: Dictionary = e["ch"]
	if not bool(ch.get("storageSub", false)):
		return _msg(id, "要先訂閱天地商行")
	if not RulesShop.remove_item(ch["storage"], item, n):
		return _msg(id, "倉庫冇咁多")
	RulesShop.add_item(ch["bag"], item, n)
	_msg(id, "由天地商行攞返 %d 件" % n)


# 代買賣: 隨時隨地都可以賣 (唔使喺商店附近)，用市場價
func cmd_storage_sell(id: int, item: int, n: int = 1) -> void:
	var e := ent(id)
	n = mini(99, n)
	if e.is_empty() or not e.has("ch") or n < 1:
		return
	var ch: Dictionary = e["ch"]
	if not bool(ch.get("storageSub", false)):
		return _msg(id, "要先訂閱天地商行")
	if not RulesShop.remove_item(ch["bag"], item, n):
		return _msg(id, "背包冇咁多")
	var gain := RulesShop.sell_price(data.prices.get(item, 0.0) * market_factor(item)) * n
	ch["gold"] = int(ch["gold"]) + gain
	_msg(id, "天地商行代賣 %d 件，得 %d 金" % [n, gain])


# ================= 工作技能 (Step 7.1) =================
const WORK_MIN_LEVEL := 10                                # 【原】10 級可做初階工作技能

# 裝備工具: 背包要有呢件工具，裝上即扣 1 件、開耐久 (starterTool 或 tool 都得)
func cmd_equip_tool(id: int, skill: String, item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var sk: Dictionary = data.work.get(skill, {})
	if sk.is_empty() or (int(sk["tool"]) != item and int(sk["starterTool"]) != item):
		return _msg(id, "呢件唔係%s工具" % sk.get("name", skill))
	var ch: Dictionary = e["ch"]
	if not RulesShop.remove_item(ch["bag"], item, 1):
		return _msg(id, "背包冇呢件工具")
	var dur: int = int(data.work_meta.get("toolDurability", {}).get("starter" if int(sk["starterTool"]) == item else "normal", 50))
	ch["tools"][skill] = {"item": item, "dur": dur}
	_msg(id, "裝備咗%s（耐久 %d）" % [data.names.get(item, str(item)), dur])


func cmd_work(id: int, skill: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var sk: Dictionary = data.work.get(skill, {})
	if sk.is_empty():
		return _msg(id, "冇呢種工作")
	var ch: Dictionary = e["ch"]
	if int(ch["level"]) < WORK_MIN_LEVEL:
		return _msg(id, "要 %d 級先做得工作技能" % WORK_MIN_LEVEL)
	if is_safe(int(e["x"]), int(e["y"])):
		return _msg(id, "城內冇得工作，要出城")
	var tool: Dictionary = ch["tools"].get(skill, {})
	if tool.is_empty() or int(tool["dur"]) <= 0:
		return _msg(id, "要裝備%s工具先" % sk["name"])
	var msp := RulesStats.max_sp(int(ch["level"]), ch["attrs"])
	var cost := RulesWork.sp_cost(msp)
	if int(ch["sp"]) < cost:
		return _msg(id, "體力不足 (要 %d SP)" % cost)
	ch["sp"] = int(ch["sp"]) - cost
	var materials: Array = sk["materials"]
	var unlocked := RulesWork.unlocked_tiers(int(ch["level"]), sk["unlockLv"])
	var tier := RulesWork.roll_tier(unlocked, rng_fn)
	var item := int(materials[tier])
	RulesShop.add_item(ch["bag"], item, 1)
	tool["dur"] = RulesWork.durability_after_use(int(tool["dur"]))
	var broke := int(tool["dur"]) <= 0
	if broke:
		ch["tools"].erase(skill)
	_emit({"k": "work", "id": id, "skill": skill, "item": item, "spCost": cost, "toolBroke": broke})
	_msg(id, "%s: 得到 %s%s" % [sk["name"], data.names.get(item, str(item)), "（工具用爛咗）" if broke else ""])


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
	if by.has("ch"):
		var w := BotSys.W_SEE_KILL if RulesKarma.tier(int(by["ch"]["karma"])) < 5 else -BotSys.W_SEE_KILL
		_witness_nearby(m, int(by["id"]), "see_kill", w)
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
	var exp_gain := int(d["exp"])
	if by.get("kind", "") == "player":          # 福日【自訂】：生日嗰日練功 exp +10% (spec 01 §1)
		var clk: Dictionary = data.world["clock"]
		exp_gain = MathX.js_round(float(exp_gain) * RulesStats.birthday_exp_mult(int(_clock()["day"]),
			int(clk.get("yearDays", 360)), int(clk.get("monthDays", 30)),
			int(ch.get("birthMonth", 1)), int(ch.get("birthDay", 1))))
	var ups := RulesStats.gain_exp(data, ch, exp_gain)
	if ups > 0 and by.get("kind", "") == "bot":   # 機械人冇人幫手派點: 直接按建議比例自動派
		RulesStats.auto_assign_points(ch, data.classes[ch["classId"]])
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
	_storage_daily()
	_emit({"k": "day", "day": day, "season": season})
	for d in changed:
		_emit({"k": "disaster", "name": d["name"], "city": d["city"], "size": d["size"]})


# 天地商行【原】: 子時扣 200/日；唔夠錢自動退訂
func _storage_daily() -> void:
	var cost := int(data.world.get("storageFee", 200))
	for e in ents.values():
		if not e.has("ch"):
			continue
		var ch: Dictionary = e["ch"]
		if not bool(ch.get("storageSub", false)):
			continue
		if int(ch["gold"]) < cost:
			ch["storageSub"] = false
			_msg(int(e["id"]), "天地商行費唔夠錢，自動退訂")
			continue
		ch["gold"] = int(ch["gold"]) - cost
		_msg(int(e["id"]), "天地商行扣 %d 金" % cost)


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
