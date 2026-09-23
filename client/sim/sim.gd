class_name Sim
extends RefCounted
# 單機世界模擬: 格子地圖 + 單位 + 即時戰鬥 + 怪物 AI + 設施。
# - state 全部係純資料 (Dictionary/Array/int/String)，可直接存檔；RNG 由種子驅動 → 可重現
# - UI 只透過 cmd_* 發意圖、透過 event_emitted 收事件、透過 view_ents()/player_ch() 讀狀態
# 由 server/src/world.ts 重寫 (去 AOI/ws)；規則喺 rules/*.gd

signal event_emitted(ev: Dictionary)

const W := 128
const H := 64
const NEAR := 3                                        # 設施互動距離(格)
const WITNESS_RANGE := 8                               # NPC 目擊範圍(格) (Step 5.2)
const GROUP_RANGE := 5                                 # 群居怪同類仇恨範圍(格) (Step 11, spec 04 §3)
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
		"clock": {"day": 0, "ke": 0, "lastShichen": -1, "is_night": false}, "market": {}, "disasters": [],
		"quest_npcs": {}}		# npc_id -> {"visible": bool} (Step 8)
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
	blocked.clear()
	for w2 in data.walls:                                  # data/zones.json walls (Step 11)
		var x0 := int(w2[0]); var y0 := int(w2[1]); var x1 := int(w2[2]); var y1 := int(w2[3])
		for x in range(x0, x1 + 1):
			for y in range(y0, y1 + 1):
				blocked[y * W + x] = true


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


# 某格所在 zone (UI 用: 渲染顏色/顯示區名)。搵唔到 = {}
func zone_view(x: int, y: int) -> Dictionary:
	for z in data.zones:
		if x >= int(z["x0"]) and x <= int(z["x1"]) and y >= int(z["y0"]) and y <= int(z["y1"]):
			return {"id": str(z["id"]), "name": str(z.get("name", z["id"]))}
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
	var e := _new_ent(ename, kind, _pick_free(5, 5, 24, 16))
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


func spawn_player(pname: String, class_id: String = "yishi") -> int:
	var e := _spawn_actor(pname, "player", class_id)
	state["player_id"] = e["id"]
	_sync_quest_npcs()
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


func _spawn_mob(def_id: int, zone_id: String = DEFAULT_ZONE) -> Variant:
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
	e["mob"] = {"def": def_id, "home_x": p.x, "home_y": p.y, "state": "wander", "target": 0, "next_atk": 0, "zone": zone_id}
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
		"school":
			var qid := _fac_ensure_quest(ch, "school")
			if _fac_attr(e, ch, f, "pol", qid != ""):
				if qid != "":
					_finish_fac_quest(e, ch, qid, "school")
		"temple":
			var qid2 := _fac_ensure_quest(ch, "temple")
			if _fac_attr(e, ch, f, "cha", qid2 != ""):
				if qid2 != "":
					_finish_fac_quest(e, ch, qid2, "temple")


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


# 私塾/寺廟【原】: 政治/魅力 +1, 扣 SP (+MP) + 金。free=true = 新手修練退款 (spec 06 §2，第一次唔使金)。
# 回傳成功與否 (新手任務只喺成功時推進)
func _fac_attr(e: Dictionary, ch: Dictionary, f: Dictionary, attr: String, free: bool = false) -> bool:
	var id := int(e["id"])
	var lv := int(ch["level"])
	var cost_gold := 0 if free else int(f.get("gold", 0))
	var cost_sp := MathX.js_round(RulesStats.max_sp(lv, ch["attrs"]) * float(f.get("costSp", 0.0)))
	var cost_mp := MathX.js_round(RulesStats.max_mp(lv, ch["attrs"]) * float(f.get("costMp", 0.0)))
	if int(ch["gold"]) < cost_gold:
		_msg(id, "要 %d 金" % cost_gold)
		return false
	if int(ch["sp"]) < cost_sp or int(ch["mp"]) < cost_mp:
		_msg(id, "精神不足 (要 SP%d/MP%d)" % [cost_sp, cost_mp])
		return false
	var v := int(ch["attrs"][attr])
	if v >= int(f["attrCap"]):
		_msg(id, "屬性已到上限 (%d)" % int(f["attrCap"]))
		return false
	ch["gold"] = int(ch["gold"]) - cost_gold
	ch["sp"] = int(ch["sp"]) - cost_sp
	ch["mp"] = int(ch["mp"]) - cost_mp
	ch["attrs"][attr] = v + 1
	_sync_stats(e)
	var an := "政治" if attr == "pol" else "魅力"
	_emit({"k": "train", "src": id, "type": "attr", "attr": an, "val": v + 1})
	return true


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


# 建角期間轉職業 (Step 9): 未出發 (Lv1) 先可以；重新生成角色
func cmd_select_class(id: int, class_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch"):
		return
	var ch: Dictionary = e["ch"]
	if int(ch["level"]) != 1:
		return _msg(id, "出發咗就唔可以轉職業")
	var cls: Dictionary = data.classes.get(class_id, {})
	if cls.is_empty() or not bool(cls["enabled"]):
		return _msg(id, "職業未開放")
	var name := str(ch["name"])
	ents.erase(id)
	var ne := _spawn_actor(name, "player", class_id)
	state["player_id"] = int(ne["id"])
	_sync_quest_npcs()
	_emit({"k": "reclass", "id": int(ne["id"]), "class": class_id, "name": name})
	_msg(int(ne["id"]), "轉職做「%s」" % cls["name"])


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
	if e.is_empty() or not is_free(x, y):
		return
	var ch: Dictionary = e.get("ch", {})
	if not ch.is_empty() and RulesSpell.blocks_move(ch.get("status", {}), tick):  # 中邪定身【原】
		if e["kind"] == "player":
			_msg(id, "中邪緊，郁唔到")
		return
	if e.has("casting"):                     # 吟唱期間移動 = 取消【原】
		e.erase("casting")
		if e["kind"] == "player":
			_msg(id, "移動取消咗吟唱")
		_emit({"k": "cast_interrupted", "dst": id, "reason": "move"})
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
	if e.has("casting"):                     # 傳送 = 斷吟唱
		e.erase("casting")
		_emit({"k": "cast_interrupted", "dst": id, "reason": "travel"})
	_emit({"k": "travel", "dst": id, "to": String(to_p["name"]), "x": e["x"], "y": e["y"]})


# ================= 任務系統 (Step 8, spec 06 §1~2) =================

# 任務 NPC 可見性同步（時辰/等級/任務狀態變化時）; state["quest_npcs"] = {npc_id: {"visible": bool}}
func _sync_quest_npcs() -> void:
	var ch := player_ch()
	var ke := int(_clock()["ke"])
	var qn: Dictionary = state["quest_npcs"]
	var changed := false
	for n in data.quest_npc_list:
		var nid := String(n["id"])
		var vis := RulesQuest.npc_visible(n, ch, ke) or RulesQuest.quest_locks_npc(ch, nid, data.quests)
		var cur := bool(qn.get(nid, {}).get("visible", false))
		if vis != cur:
			qn[nid] = {"visible": vis}
			changed = true
	if changed:
		_emit({"k": "quest_npcs", "npcs": view_quest_npcs()})


func _quest_by_id(quest_id: String) -> Dictionary:
	for q in data.quests:
		if String(q["id"]) == quest_id:
			return q
	return {}


# quest 進度事件統一出口: 播對話 + emit + 獎勵訊息
func _quest_emit(e: Dictionary, q: Dictionary, res: Dictionary) -> void:
	var id := int(e["id"])
	for line in res.get("dialog", []):
		_msg(id, str(line))
	if bool(res.get("started", false)):
		_emit({"k": "quest", "dst": id, "quest": q["id"], "started": true, "stage": int(res.get("stage", 0))})
	elif bool(res.get("done", false)):
		_sync_stats(e)
		_emit({"k": "quest", "dst": id, "quest": q["id"], "done": true, "reward": res.get("reward", {})})
		_sync_quest_npcs()          # 完成: 解鎖 NPC 嘅強制常駐
	else:
		_emit({"k": "quest", "dst": id, "quest": q["id"], "stage": int(res.get("stage", 0))})
	if not str(res.get("msg", "")).is_empty():
		_msg(id, str(res["msg"]))


# 同任務 NPC 對話: 檢查 pre → 觸發/推進 stage。NPC 位置/可見性由 quest_npcs.json 控制
func cmd_quest_talk(id: int, npc_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var npc: Dictionary = data.quest_npcs.get(npc_id, {})
	if npc.is_empty():
		return
	if not _near(e, int(npc["x"]), int(npc["y"])):
		return _msg(id, "要行近%s先得" % npc["name"])
	if not bool(state["quest_npcs"].get(npc_id, {}).get("visible", false)):
		return _msg(id, "呢度搵唔到%s" % npc["name"])
	var ch: Dictionary = e["ch"]
	# 服務 NPC（密醫免費醫療）
	var sv: Dictionary = npc.get("service", {})
	if not sv.is_empty():
		_quest_service(e, ch, npc)
		return
	var day := int(_clock()["day"])
	var spoke := false
	for q in data.quests:
		var res := RulesQuest.on_npc_talk(data, ch, q, npc_id, day)
		if not bool(res.get("changed", false)):
			continue
		spoke = true
		_quest_emit(e, q, res)
	if not spoke:
		var pool: Array = npc.get("idle", [])
		if not pool.is_empty():
			_emit({"k": "npc_say", "id": 0, "name": str(npc["name"]), "text": str(pool[rng.below(pool.size())]),
				"action": "greet", "x": int(npc["x"]), "y": int(npc["y"])})


# 服務 NPC 功能（密醫【原】: 免費醫療 100 HP，一日 3 次）
func _quest_service(e: Dictionary, ch: Dictionary, npc: Dictionary) -> void:
	var id := int(e["id"])
	var sv: Dictionary = npc["service"]
	if String(sv.get("kind", "")) != "heal":
		return _msg(id, "%s：而家冇服務" % npc["name"])
	var qid := ""
	for q in data.quests:
		if String(q.get("type", "")) == "service" and String(q.get("giver", "")) == String(npc["id"]):
			qid = String(q["id"])
			break
	var st: Dictionary = ch.get("quests", {}).get(qid, {})
	var day := int(_clock()["day"])
	var used := 0
	if int(st.get("day", -1)) == day:
		used = int(st.get("used", 0))
	var per_day := int(sv.get("perDay", 3))
	if used >= per_day:
		return _msg(id, "密醫：今日嘅名額用晒喇，聽日再嚟")
	var mhp := _eff_max_hp(ch)
	var gain := mini(int(sv["hp"]), mhp - int(ch["hp"]))
	if gain <= 0:
		return _msg(id, "密醫：你精神飽滿，唔使醫")
	ch["hp"] = int(ch["hp"]) + gain
	e["hp"] = int(ch["hp"])
	ch["quests"][qid] = {"day": day, "used": used + 1}
	_emit({"k": "heal", "dst": id, "hp": gain, "used": used + 1})
	_msg(id, "密醫幫你醫治，回復 %d HP (今日 %d/%d 次)" % [gain, used + 1, per_day])


# 繳交收集道具 (collect stage)
func cmd_quest_turnin(id: int, quest_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var q := _quest_by_id(quest_id)
	if q.is_empty():
		return
	var gv := String(q.get("giver", ""))
	if gv != "":
		var npc: Dictionary = data.quest_npcs.get(gv, {})
		if npc.is_empty() or not _near(e, int(npc["x"]), int(npc["y"])):
			return _msg(id, "要行近交任務嘅 NPC 先得")
	var res := RulesQuest.on_turnin(data, e["ch"], q)
	if not bool(res.get("changed", false)):
		if not str(res.get("msg", "")).is_empty():
			_msg(id, str(res["msg"]))
		return
	_quest_emit(e, q, res)


# 答題 (ask stage: 登用問答 / 任務題目)
func cmd_quest_answer(id: int, quest_id: String, answer_idx: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var q := _quest_by_id(quest_id)
	if q.is_empty():
		return
	var res := RulesQuest.on_answer(data, e["ch"], q, answer_idx)
	if not bool(res.get("changed", false)):
		if not str(res.get("msg", "")).is_empty():
			_msg(id, str(res["msg"]))
		return
	_quest_emit(e, q, res)


# 新手修練退款 (spec 06 §2): facility quest 進行中 → 免費；未開始 + pre ok → 由第一次使用自動觸發
func _fac_ensure_quest(ch: Dictionary, key: String) -> String:
	var day := int(_clock()["day"])
	for q in data.quests:
		var qid := String(q["id"])
		var st: Dictionary = ch.get("quests", {}).get(qid, {})
		if not st.is_empty():
			var stage := RulesQuest.stage_of(ch, q)
			if not stage.is_empty() and String(stage.get("type", "")) == "facility" and String(stage.get("fac", "")) == key:
				return qid
			continue
		var stages: Array = q.get("stages", [])
		if stages.is_empty() or bool(ch.get("questDone", {}).get(qid, false)):
			continue
		var st0: Dictionary = stages[0]
		if String(st0.get("type", "")) != "facility" or String(st0.get("fac", "")) != key:
			continue
		if not RulesQuest.pre_ok(data, q, ch):
			continue
		if not ch.has("quests"):
			ch["quests"] = {}
		ch["quests"][qid] = {"stage": 0, "startDay": day, "flags": {}}
		return qid
	return ""


func _finish_fac_quest(e: Dictionary, ch: Dictionary, qid: String, key: String) -> void:
	var q := _quest_by_id(qid)
	if q.is_empty():
		return
	var res := RulesQuest.on_facility(data, ch, q, key, int(_clock()["day"]))
	if bool(res.get("changed", false)):
		_quest_emit(e, q, res)


# ================= 任務讀取 (UI 記事用) =================
func view_quest_npcs() -> Array:
	var out: Array = []
	for n in data.quest_npc_list:
		var qv: Dictionary = state["quest_npcs"].get(String(n["id"]), {})
		if bool(qv.get("visible", false)):
			out.append({"id": n["id"], "name": n["name"], "x": n["x"], "y": n["y"], "desc": n.get("desc", ""),
				"service": (n.get("service", {}) as Dictionary).size() > 0})
	return out


# 記事 UI: 進行中任務 + stage 提示 + 完成記錄 (hidden quest 唔顯示)
func view_quests() -> Array:
	var ch := player_ch()
	var out: Array = []
	for q in data.quests:
		if bool(q.get("hidden", false)):
			continue
		var qid := String(q["id"])
		var entry := {"id": qid, "name": q["name"], "type": q["type"]}
		if bool(ch.get("questDone", {}).get(qid, false)):
			entry["done"] = true
		elif not (ch.get("quests", {}) as Dictionary).is_empty() and (ch["quests"] as Dictionary).has(qid):
			entry["active"] = true
			entry["stage"] = int(ch["quests"][qid].get("stage", 0))
			entry["hint"] = RulesQuest.hint(q, ch)
		else:
			entry["hint"] = RulesQuest.hint(q, ch)   # 未開始: preHint
		out.append(entry)
	return out


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
	# 輔助石加成: 用有效上限 (Step 10, spec 02 §4)
	ch["hp"] = _eff_max_hp(ch)
	ch["mp"] = _eff_max_mp(ch)
	ch["sp"] = _eff_max_sp(ch)


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
	if RulesQuest.is_quest_item(data, item):
		return _msg(id, "任務道具唔可以賣 (會擋任務)")
	var ch: Dictionary = e["ch"]
	var have := 0
	for b in ch["bag"]:
		if int(b["id"]) == item:
			have = int(b["n"])
	if int(ch["equip"].get("weapon", 0)) == item and have <= n:
		return _msg(id, "裝備中，唔可以賣")
	var eq_books: Array = ch["equip"].get("spellbooks", [0, 0, 0])
	if (eq_books as Array).has(item) and have <= n:
		return _msg(id, "快捷列裝備中，唔可以賣")
	if not RulesShop.remove_item(ch["bag"], item, n):
		return _msg(id, "背包冇咁多")
	var gain := RulesShop.sell_price(data.prices.get(item, 0.0) * market_factor(item)) * n
	ch["gold"] = int(ch["gold"]) + gain
	_cleanup_fused(ch)                    # 賣晒融合武器 → 清嵌石記錄
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
	var mhp := _eff_max_hp(ch)
	var mmp := _eff_max_mp(ch)
	var msp := _eff_max_sp(ch)
	var gained_hp := mini(int(heal.get("hp", 0)), mhp - int(ch["hp"]))
	var gained_mp := mini(int(heal.get("mp", 0)), mmp - int(ch["mp"]))
	var gained_sp := mini(int(heal.get("sp", 0)), msp - int(ch["sp"]))
	ch["hp"] = int(ch["hp"]) + maxi(0, gained_hp)
	ch["mp"] = int(ch["mp"]) + maxi(0, gained_mp)
	ch["sp"] = int(ch["sp"]) + maxi(0, gained_sp)
	_sync_stats(e)
	_msg(id, "用咗 %s，回 %d HP %d MP %d SP" % [data.names.get(item, str(item)), maxi(0, gained_hp), maxi(0, gained_mp), maxi(0, gained_sp)])


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
	if RulesQuest.is_quest_item(data, item):
		return _msg(id, "任務道具唔可以賣 (會擋任務)")
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


# ================= 寶石欄 + 武器裝備 (Step 10, spec 02 §4) =================
# 裝備武器: 背包要有；唔限職業武器 (武器分類只影響絕招, ultimates.json weaponCat)
func cmd_equip_weapon(id: int, item: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var has := RulesShop.has_item(ch["bag"], item, 1)
	if not has:
		return _msg(id, "背包冇呢件武器")
	if int(data.cats.get(item, 0)) not in [1, 2, 3]:
		return _msg(id, "呢件唔係武器")
	ch["equip"]["weapon"] = item
	_emit({"k": "equip", "src": id, "slot": "weapon", "item": item})
	_msg(id, "裝備咗「%s」" % data.names.get(item, str(item)))


# 寶石欄裝卸 (2 格): 背包要有，裝備唔消耗。item=0 = 清空。slot 0 = 攻擊用屬性石
func cmd_equip_jewel(id: int, item: int, slot: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if slot < 0 or slot > 1:
		return _msg(id, "寶石欄得 2 格")
	var ch: Dictionary = e["ch"]
	if item == 0:
		var old := int(ch["equip"]["jewels"][slot])
		if old != 0:
			_unequip_jewel_sync(ch, old)
		ch["equip"]["jewels"][slot] = 0
		_emit({"k": "jewel", "src": id, "slot": slot, "item": 0})
		return _msg(id, "寶石欄 %d 已清空" % (slot + 1))
	var jd: Dictionary = data.jewel_by_item.get(item, {})
	if jd.is_empty():
		return _msg(id, "呢件唔係寶石")
	if not RulesShop.has_item(ch["bag"], item, 1):
		return _msg(id, "背包冇呢粒寶石")
	var dup := int(ch["equip"]["jewels"][0]) == item or int(ch["equip"]["jewels"][1]) == item
	if dup:
		return _msg(id, "已經裝緊呢粒寶石")
	var full := (int(ch["equip"]["jewels"][0]) != 0 and slot == 0) or (int(ch["equip"]["jewels"][1]) != 0 and slot == 1)
	if full:
		_unequip_jewel_sync(ch, int(ch["equip"]["jewels"][slot]))
	ch["equip"]["jewels"][slot] = item
	_emit({"k": "jewel", "src": id, "slot": slot, "item": item})
	_msg(id, "裝咗「%s」落寶石欄 %d" % [jd["name"], slot + 1])


# 裝/卸石後: clamp 血/氣到有效上限 (輔助石 HP/MP/SP 加成)
func _unequip_jewel_sync(ch: Dictionary, item: int) -> void:
	var lv := int(ch["level"])
	var bonus_before := RulesJewel.support_bonus(data.jewel_by_item.get(item, {}).get("effects", []))
	var extra_hp := MathX.js_round(RulesStats.max_hp(lv, ch["attrs"]) * float(bonus_before.get("hpPct", 0.0)))
	var extra_mp := MathX.js_round(RulesStats.max_mp(lv, ch["attrs"]) * float(bonus_before.get("mpPct", 0.0)))
	var extra_sp := int(bonus_before.get("spFlat", 0))
	ch["hp"] = maxi(1, int(ch["hp"]) - extra_hp)
	ch["mp"] = maxi(0, int(ch["mp"]) - extra_mp)
	ch["sp"] = maxi(0, int(ch["sp"]) - extra_sp)


# ================= 術法 (Step 9, spec 02 §3) =================

# 術書裝備去快捷列 (3 格切換【原】)；item=0 = 清空。要喺背包，裝備唔消耗本體
func cmd_equip_spellbook(id: int, item: int, slot: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if slot < 0 or slot > 2:
		return _msg(id, "快捷列得 3 格")
	var ch: Dictionary = e["ch"]
	if item == 0:
		ch["equip"]["spellbooks"][slot] = 0
		_emit({"k": "spellbook", "src": id, "slot": slot, "item": 0})
		return _msg(id, "快捷列 %d 已清空" % (slot + 1))
	var def: Dictionary = data.spell_by_item.get(item, {})
	if def.is_empty():
		return _msg(id, "呢件唔係術書")
	if not (def["classes"] as Array).has(str(ch["classId"])):
		return _msg(id, "你嘅職業用唔到呢本術書")
	var in_bag := false
	for b in ch["bag"]:
		if int(b["id"]) == item and int(b["n"]) > 0:
			in_bag = true
			break
	if not in_bag:
		return _msg(id, "背包冇呢本術書")
	ch["equip"]["spellbooks"][slot] = item
	_emit({"k": "spellbook", "src": id, "slot": slot, "item": item})
	_msg(id, "「%s」已裝備落快捷列 %d" % [def["name"], slot + 1])


# 施展快捷列 slot 嘅術法。attack/status 要 target；buff 自動施自己。開始吟唱，tick 到先生效。
# 吟唱期間移動取消【原】；受擊 30% 中斷【自訂】；封咒中唔可以施【原】
func cmd_cast_spell(id: int, slot: int, target: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var books: Array = ch["equip"].get("spellbooks", [0, 0, 0])
	if slot < 0 or slot >= books.size():
		return
	var item := int(books[slot])
	if item == 0:
		return _msg(id, "快捷列 %d 未裝備術書" % (slot + 1))
	var def: Dictionary = data.spell_by_item.get(item, {})
	if def.is_empty():
		return
	if not (def["classes"] as Array).has(str(ch["classId"])):
		return _msg(id, "你嘅職業用唔到呢本術書")
	if int(ch["level"]) < int(def["lv"]):
		return _msg(id, "要 Lv%d 先用得「%s」" % [int(def["lv"]), def["name"]])
	if RulesSpell.blocks_cast(ch.get("status", {}), tick):
		return _msg(id, "封咒緊，施唔到術法")
	if e.has("casting"):
		return _msg(id, "正在吟唱")
	var need_jewel := str(def.get("jewel", ""))
	if need_jewel != "" and not _has_special_jewel(ch, need_jewel):
		return _msg(id, "需要裝備「%s」先施得 (元素術大範圍施放【原】)" % _special_jewel_name(need_jewel))
	var mp_cost := _mp_cost(ch, int(def["mp"]))
	if int(ch["mp"]) < mp_cost:
		return _msg(id, "靈力不足 (要 %d MP)" % mp_cost)
	var tgt_id := 0
	if str(def["kind"]) != "buff":
		var t := ent(target)
		if t.is_empty() or int(t["hp"]) <= 0 or (t.get("kind", "") != "mob" and not t.has("ch")):
			return _msg(id, "目標唔啱")
		if not RulesCombat.in_range(e["x"], e["y"], t["x"], t["y"], float(def["range"])):
			return _msg(id, "太遠，施唔到")
		tgt_id = target
	e["casting"] = {"book": item, "target": tgt_id, "done_at": tick + int(def["castTicks"]), "slot": slot}
	_emit({"k": "cast_start", "src": id, "dst": tgt_id, "book": item, "ticks": int(def["castTicks"])})
	_msg(id, "吟唱「%s」…（移動取消）" % str(def["name"]))


# ================= 戰鬥 =================
func damage(t: Dictionary, dmg: int, by: Dictionary) -> void:
	# 吟唱中受擊: 30% 有機率中斷【自訂】(spec 02 §3.1)
	if t.has("casting") and MathX.roll(rng_fn) < 0.3:
		t.erase("casting")
		_emit({"k": "cast_interrupted", "dst": t["id"], "reason": "hit"})
	t["hp"] = maxi(0, int(t["hp"]) - dmg)
	if t["kind"] == "mob" and by.has("ch"):
		t["mob"]["state"] = "chase"
		t["mob"]["target"] = by["id"]
		var md: Dictionary = data.monsters[int(t["mob"]["def"])]
		# 群居怪【自訂】(spec 04 §3): 打 1 隻，附近 GROUP_RANGE 格內同類一齊仇恨
		if dmg > 0 and bool(md.get("groups", false)):
			for o in ents.values():
				if o["kind"] == "mob" and int(o["id"]) != int(t["id"]) \
						and int(o.get("mob", {}).get("def", -1)) == int(t["mob"]["def"]) \
						and RulesCombat.in_range(t["x"], t["y"], o["x"], o["y"], GROUP_RANGE):
					o["mob"]["state"] = "chase"
					o["mob"]["target"] = int(by["id"])
		# 逃跑【自訂】(spec 04 §3): HP<20% 有 15% 機會逃跑；boss/PK 怪 flee=false 唔逃
		if dmg > 0 and int(t["hp"]) > 0 and bool(md.get("flee", true)) \
				and not t["mob"].has("quest_boss") and String(t["mob"]["state"]) != "flee" \
				and int(t["hp"]) < int(t["max_hp"]) * 0.2 and MathX.roll(rng_fn) < 0.15:
			t["mob"]["state"] = "flee"
			t["mob"]["target"] = int(by["id"])
			_emit({"k": "flee", "src": int(t["id"]), "dst": int(by["id"]), "name": str(t["name"])})
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
	# 任務 boss (PK 戰, Step 10): 唔掉落/唔重生，轉交 quest 推進
	var quest_boss := str(m.get("mob", {}).get("quest_boss", ""))
	if quest_boss != "":
		_emit({"k": "mob_died", "dst": int(by.get("id", 0)), "name": str(m["name"])})
		var q := _quest_by_id(quest_boss)
		if not q.is_empty() and by.has("ch"):
			var res := RulesQuest.on_fight_win(data, by["ch"], q)
			if bool(res.get("changed", false)):
				_quest_emit(by, q, res)
		ents.erase(m["id"])
		for e in ents.values():
			if int(e["atk_target"]) == int(m["id"]):
				e["atk_target"] = 0
		return
	if by.has("ch"):
		var w := BotSys.W_SEE_KILL if RulesKarma.tier(int(by["ch"]["karma"])) < 5 else -BotSys.W_SEE_KILL
		_witness_nearby(m, int(by["id"]), "see_kill", w)
	ents.erase(m["id"])
	_schedule_respawn(m, d)
	for e in ents.values():
		if int(e["atk_target"]) == int(m["id"]):
			e["atk_target"] = 0
	if not by.has("ch"):
		return
	var ch: Dictionary = by["ch"]
	var gold := RulesCombat.roll_gold(d["gold"], rng_fn)
	var items := RulesCombat.roll_drops(d["drops"], rng_fn)
	items.append_array(RulesCombat.roll_drops(d.get("rareDrops", []), rng_fn))   # 稀有掉落 (Step 11, spec 11 §2)
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
	if ups > 0:
		_sync_quest_npcs()          # 升級可能改變任務 NPC 可見性 (神秘老人/流浪狗)
	if ups > 0 and by.get("kind", "") == "bot":   # 機械人冇人幫手派點: 直接按建議比例自動派
		RulesStats.auto_assign_points(ch, data.classes[ch["classId"]])
	_sync_stats(by)
	_emit({"k": "kill", "src": by["id"], "dst": m["id"], "exp": int(d["exp"]), "gold": gold, "items": items,
		"lvUp": int(ch["level"]) if ups > 0 else 0})


# 重生排期: 普通怪定時重生，boss 每日一次【自訂】(spec 04 §3)。zone 用 mob spawn 嗰層，免得同 def 多層混亂
func _schedule_respawn(m: Dictionary, d: Dictionary) -> void:
	var zone_id := String(m.get("mob", {}).get("zone", DEFAULT_ZONE))
	var delay := 200
	for sp in data.spawns:
		if int(sp["monster"]) == int(d["id"]) and String(sp.get("zone", DEFAULT_ZONE)) == zone_id:
			delay = int(sp["respawnTicks"])
			break
	if bool(d.get("boss", false)):
		var tpd := int(1440.0 / float(int(data.world["clock"]["gameMinPerTick"])))
		delay = tpd - (tick % tpd)                       # 下一個子時先重生 (每日一次)
	state["respawns"].append({"at": tick + delay, "def": int(d["id"]), "zone": zone_id})


func _kill_player(p: Dictionary) -> void:
	var ch: Dictionary = p["ch"]
	ch["exp"] = maxi(0, int(ch["exp"]) - RulesCombat.death_exp_loss(int(ch["karma"]), RulesStats.exp_to_next(int(ch["level"]))))
	var lost := RulesCombat.roll_death_drop(int(ch["karma"]), ch["bag"], rng_fn)
	if lost > 0:
		RulesShop.remove_item(ch["bag"], lost, 1)
	_cleanup_fused(ch)              # 跌走咗武器 → 清除融合記錄
	_full_heal(ch)
	ch["status"] = {}
	p.erase("casting")
	ch.erase("fusing")
	p["x"] = inn_pos.x
	p["tx"] = inn_pos.x
	p["y"] = inn_pos.y
	p["ty"] = inn_pos.y
	p["atk_target"] = 0
	_sync_stats(p)
	_emit({"k": "die", "dst": p["id"], "lost": lost})


# 逃跑怪消失: 排重生 + 清 atk_target (冇掉落/善惡/經驗)
func _erase_flee(m: Dictionary, d: Dictionary) -> void:
	_schedule_respawn(m, d)
	var id := int(m["id"])
	ents.erase(id)
	for e in ents.values():
		if int(e["atk_target"]) == id:
			e["atk_target"] = 0


# 怪物 AI: 遊蕩 / 仇恨追擊 / 脫戰回歸 / 術法吟唱 (Step 9) / 逃跑 (Step 11)
func _think_mob(m: Dictionary) -> void:
	var s: Dictionary = m["mob"]
	var d: Dictionary = data.monsters[int(s["def"])]
	var tgt := ent(int(s["target"]))
	# 術法怪吟唱中: 停低，tick 到生效；受擊中斷喺 damage() 處理
	if m.has("casting"):
		_resolve_mob_cast(m, s, d, tgt)
		return
	# 逃跑中 (spec 04 §3): 唔打唔追，只顧走；離開 home 超過 leash 就消失
	if s["state"] == "flee":
		var ftgt := ent(int(s["target"]))
		if ftgt.is_empty() or not ftgt.has("ch") or int(ftgt["hp"]) <= 0:
			_erase_flee(m, d)                       # 目標冇咗 = 成功逃咗
			return
		if maxi(absi(int(m["x"]) - int(s["home_x"])), absi(int(m["y"]) - int(s["home_y"]))) > int(d["leash"]):
			_erase_flee(m, d)                       # 走甩咗
			return
		if RulesSpell.blocks_move(m.get("status", {}), tick):
			return                                  # 中邪: 郁唔到
		var away := Vector2i(signi(int(m["x"]) - int(ftgt["x"])), signi(int(m["y"]) - int(ftgt["y"])))
		var spd := 2 if tick % 2 == 0 else 1       # 移速 ×1.5 (double-move 一半機率)
		var nx := int(m["x"]) + away.x
		var ny := int(m["y"]) + away.y
		if spd == 2 and is_free(nx + away.x, ny) and is_free(nx, ny + away.y):
			nx += away.x
			ny += away.y
		m["tx"] = nx if is_free(nx, ny) else int(m["x"])
		m["ty"] = ny if is_free(nx, ny) else int(m["y"])
		return
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
			# 術法怪: 喺術法距離內就吟唱 (有冷卻)
			var spell_id := str(d.get("spell", ""))
			if spell_id != "" and tick >= int(s.get("next_spell", 0)):
				var sdef: Dictionary = data.spell_by_id.get(spell_id, {})
				if not sdef.is_empty() and RulesCombat.in_range(m["x"], m["y"], tgt["x"], tgt["y"], float(sdef["range"])):
					m["casting"] = {"spell": spell_id, "target": int(tgt["id"]), "done_at": tick + int(sdef["castTicks"])}
					_emit({"k": "cast_start", "src": m["id"], "dst": int(tgt["id"]),
						"book": int(sdef.get("item", 0)), "ticks": int(sdef["castTicks"])})
					return
			if tick >= int(s["next_atk"]):
				s["next_atk"] = tick + int(d["atkInterval"])
				var pch: Dictionary = tgt["ch"]
				# 輔助石: 玩家物防 %/flat + 物迴避 % (Step 10, spec 02 §4)
				var jb := _jewel_bonus(pch)
				var pdef := RulesCombat.player_def(int(pch["level"])) + int(jb.get("defFlat", 0))
				var pd := pdef * RulesSpell.def_mult(pch.get("status", {}), tick) * (1.0 + float(jb.get("defPct", 0.0)))
				if rng.next() < float(jb.get("evadePct", 0.0)):
					_emit({"k": "hit", "src": m["id"], "dst": tgt["id"], "dmg": 0})     # 迴避咗
				else:
					var dmg := RulesCombat.calc_mob_damage(d["atk"], pd, rng_fn)
					_emit({"k": "hit", "src": m["id"], "dst": tgt["id"], "dmg": dmg})
					damage(tgt, dmg, m)
		else:
			if not RulesSpell.blocks_move(m.get("status", {}), tick):   # 中邪定身: 唔可以追
				m["tx"] = tgt["x"]
				m["ty"] = tgt["y"]
		return
	if s["state"] == "return":
		m["hp"] = mini(int(m["max_hp"]), int(m["hp"]) + int(ceil(int(m["max_hp"]) / 20.0)))    # 脫戰回血
		if int(m["x"]) == int(s["home_x"]) and int(m["y"]) == int(s["home_y"]):
			s["state"] = "wander"
		return
	if RulesSpell.blocks_move(m.get("status", {}), tick):   # 中邪: 遊蕩都要停
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


# 玩家/機械人自動追擊 + 出手；吟唱中一律停低等生效
func _think_player(p: Dictionary) -> void:
	if p.has("casting"):
		_resolve_cast(p)
		return
	if int(p["atk_target"]) == 0 or not p.has("ch"):
		return
	var t := ent(int(p["atk_target"]))
	var ch: Dictionary = p["ch"]
	if t.is_empty() or int(t["hp"]) <= 0 or int(p["hp"]) <= 0:
		p["atk_target"] = 0
		return
	if not RulesCombat.in_range(p["x"], p["y"], t["x"], t["y"]):
		if not RulesSpell.blocks_move(ch.get("status", {}), tick):   # 中邪定身: 唔可以追
			p["tx"] = t["x"]
			p["ty"] = t["y"]
		return
	p["tx"] = p["x"]
	p["ty"] = p["y"]
	if is_safe(int(p["x"]), int(p["y"])):
		return     # 安全區唔畀出手 (理論上怪唔會入城，呢度做多重保險)
	if tick < int(p["next_atk"]):
		return
	var w: Dictionary = data.weapons.get(int(ch["equip"].get("weapon", 0)), {"power": 0.0, "hit": 45.0})
	p["next_atk"] = tick + RulesCombat.attack_interval(ch["attrs"]["agi"])
	# 輔助石命中率 % (effect 13) (Step 10, spec 02 §4)
	var base_hit := RulesCombat.hit_chance(w["hit"], int(ch["level"]), int(t["level"]))
	var hit := base_hit + float(_jewel_bonus(ch).get("hitPct", 0.0))
	if rng.next() >= hit:
		_emit({"k": "hit", "src": p["id"], "dst": t["id"], "dmg": 0})     # miss
		t["mob"]["state"] = "chase"
		t["mob"]["target"] = p["id"]
		return
	var mdef: Dictionary = data.monsters[int(t["mob"]["def"])]
	# 聚力/強力/神力 buff: 物攻 ×1.15/1.3/1.5 (spec 02 §7) + 輔助石物攻 % (effect 7)
	var atk_mult := RulesSpell.atk_mult(ch.get("status", {}), tick)
	atk_mult = atk_mult * (1.0 + float(_jewel_bonus(ch).get("atkPct", 0.0)))
	var eff_str := float(ch["attrs"]["str"]) + float(_jewel_bonus(ch).get("strFlat", 0))
	var elem_mult := _phys_elem_mult(ch, str(mdef.get("element", "none")))
	var dmg0 := RulesCombat.calc_damage(eff_str, w["power"], mdef["def"], rng_fn, atk_mult, 1.0)
	var dmg := MathX.js_round(dmg0 * elem_mult)
	_emit({"k": "hit", "src": p["id"], "dst": t["id"], "dmg": dmg})
	damage(t, dmg, p)


# ---- 術法生效 (Step 9, spec 02 §3): 吟唱完結先扣 MP + 出效果 ----
func _resolve_cast(p: Dictionary) -> void:
	var cs: Dictionary = p["casting"]
	if tick < int(cs["done_at"]):
		return
	p.erase("casting")
	var ch: Dictionary = p["ch"]
	var def: Dictionary = data.spell_by_item.get(int(cs["book"]), {})
	if def.is_empty():
		return
	if RulesSpell.blocks_cast(ch.get("status", {}), tick):
		return _msg(int(p["id"]), "封咒緊，術法失效")
	var mp_cost := _mp_cost(ch, int(def["mp"]))
	if int(ch["mp"]) < mp_cost:
		return _msg(int(p["id"]), "靈力唔夠，術法取消")
	ch["mp"] = int(ch["mp"]) - mp_cost
	_emit({"k": "cast", "src": p["id"], "book": int(cs["book"]), "kind": str(def["kind"])})
	match str(def["kind"]):
		"attack":
			var t := ent(int(cs["target"]))
			if t.is_empty() or int(t["hp"]) <= 0:
				return _msg(int(p["id"]), "目標死咗，術法落空")
			if not RulesCombat.in_range(p["x"], p["y"], t["x"], t["y"], float(def["range"])):
				return _msg(int(p["id"]), "目標行遠咗，術法落空")
			_spell_hit(p, def, t)
		"status", "cure":
			var t2 := ent(int(cs["target"]))
			if t2.is_empty() or int(t2["hp"]) <= 0:
				return _msg(int(p["id"]), "目標死咗，術法落空")
			if not RulesCombat.in_range(p["x"], p["y"], t2["x"], t2["y"], float(def["range"])):
				return _msg(int(p["id"]), "目標行遠咗，術法落空")
			_spell_status(p, def, t2)
		"buff":
			_spell_buff(p, def)


# 特殊石: 施法時裝備咗對應元素 (spells.json jewel 欄 = 元素名) 嘅 special 石先得 (Step 10)
func _has_special_jewel(ch: Dictionary, elem: String) -> bool:
	for it in ch["equip"].get("jewels", [0, 0]) as Array:
		var jd: Dictionary = data.jewel_by_item.get(int(it), {})
		if not jd.is_empty() and str(jd.get("kind", "")) == "special" and str(jd.get("elem", "")) == elem:
			return true
	return false


func _special_jewel_name(elem: String) -> String:
	for jd in data.jewels.get("special", []):
		if str(jd["elem"]) == elem:
			return str(jd["name"])
	return elem + "之石"


# 消耗類成本: 輔助石 MP/SP 耗損減免 (effects 63/65) 乘落去
func _mp_cost(ch: Dictionary, base: int) -> int:
	return maxi(1, MathX.js_round(float(base) * float(_jewel_bonus(ch).get("mpCostMul", 1.0))))


func _sp_cost(ch: Dictionary, base: int) -> int:
	return maxi(1, MathX.js_round(float(base) * float(_jewel_bonus(ch).get("spCostMul", 1.0))))


# 傷害術: 大範圍 (aoe>0) = 以目標格為圓心打晒所有怪物；隊友唔受【原】
func _spell_hit(p: Dictionary, def: Dictionary, t: Dictionary) -> void:
	var ch: Dictionary = p["ch"]
	var attr := float(ch["attrs"].get(str(def["stat"]), 0))
	# 寶石加成 (Step 10, spec 02 §3.2): 裝備 slot 0 屬性石同術法元素相同 → 石 pct 加成；另加輔助術攻 %
	var stone := _equip_stone(ch)
	var jewel_pct := RulesJewel.spell_jewel_bonus(str(stone.get("elem", "")), str(def.get("elem", "")),
		float(stone.get("pct", 0.0))) - 1.0
	var spell_atk_mult := 1.0 + float(_jewel_bonus(ch).get("spellAtkPct", 0.0))
	var aoe := int(def.get("aoe", 0))
	var targets: Array = []
	if aoe > 0:
		for o in ents.values():
			if o["kind"] == "mob" and int(o["hp"]) > 0 \
					and RulesCombat.in_range(t["x"], t["y"], o["x"], o["y"], aoe):
				targets.append(o)
	else:
		targets.append(t)
	for o in targets:
		var mdef: Dictionary = data.monsters[int(o["mob"]["def"])]
		var dmg := RulesSpell.calc_spell_damage(float(def["power"]) * spell_atk_mult, attr,
			float(mdef.get("spellDef", 0)), str(def["elem"]), str(mdef.get("element", "none")), jewel_pct, rng_fn)
		_emit({"k": "spell_hit", "src": p["id"], "dst": o["id"], "dmg": dmg, "elem": str(def["elem"])})
		damage(o, dmg, p)


# ================= 絕招 (Step 10, spec 02 §5) =================
# 大範圍即時傷害 (冇吟唱): 耗 MP+SP、冷卻、需要對應武器 (ultimates.json weaponCat)
func cmd_use_ultimate(id: int, ult_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	if not (ch.get("ultimates", []) as Array).has(ult_id):
		return _msg(id, "未學呢招絕招")
	var ult: Dictionary = data.ult_by_id.get(ult_id, {})
	if ult.is_empty():
		return
	if str(ult["class"]) != str(ch["classId"]):
		return _msg(id, "你嘅職業用唔到呢招")
	var w := int(ch["equip"].get("weapon", 0))
	if w == 0 or int(data.cats.get(w, 0)) != int(ult["weaponCat"]):
		return _msg(id, "要用矛類武器先用得「%s」" % ult["name"])
	var cd: Dictionary = ch.get("ultCd", {})
	if tick < int(cd.get(ult_id, 0)):
		return _msg(id, "「%s」冷卻中 (%d tick)" % [ult["name"], int(cd.get(ult_id, 0)) - tick])
	var mp_cost := _mp_cost(ch, int(ult["mp"]))
	var sp_cost := _sp_cost(ch, int(ult["sp"]))
	if int(ch["mp"]) < mp_cost:
		return _msg(id, "靈力不足 (要 %d MP)" % mp_cost)
	if int(ch["sp"]) < sp_cost:
		return _msg(id, "體力不足 (要 %d SP)" % sp_cost)
	if is_safe(int(e["x"]), int(e["y"])):
		return _msg(id, "要出城先用得絕招")
	var rng_cells := int(ult["range"])
	var targets: Array = []
	for o in ents.values():
		if o["kind"] == "mob" and int(o["hp"]) > 0 \
				and RulesCombat.in_range(e["x"], e["y"], o["x"], o["y"], rng_cells):
			targets.append(o)
	if targets.is_empty():
		return _msg(id, "附近冇怪")
	ch["mp"] = int(ch["mp"]) - mp_cost
	ch["sp"] = int(ch["sp"]) - sp_cost
	cd[ult_id] = tick + int(ult["cd"])
	ch["ultCd"] = cd
	var wdef: Dictionary = data.weapons.get(w, {"power": 0.0, "hit": 45.0})
	var atk_mult := RulesSpell.atk_mult(ch.get("status", {}), tick) * (1.0 + float(_jewel_bonus(ch).get("atkPct", 0.0)))
	var eff_str := float(ch["attrs"]["str"]) + float(_jewel_bonus(ch).get("strFlat", 0))
	_emit({"k": "ult", "src": id, "ult": ult_id, "name": str(ult["name"]), "mp": mp_cost, "sp": sp_cost})
	_msg(id, "「%s」！" % ult["name"])
	for o in targets:
		var mdef: Dictionary = data.monsters[int(o["mob"]["def"])]
		var elem_mult := _phys_elem_mult(ch, str(mdef.get("element", "none")))
		var dmg0 := RulesCombat.calc_damage(eff_str, wdef["power"], mdef["def"], rng_fn, atk_mult, 1.0)
		var dmg := MathX.js_round(dmg0 * float(ult["mult"]) * elem_mult)
		_emit({"k": "ult_hit", "src": id, "dst": o["id"], "dmg": dmg, "ult": ult_id})
		damage(o, dmg, e)


# ================= 任務 PK 戰 (fight stage, Step 10, spec 06 §5) =================
# 同指定 NPC 對話後召喚 boss (stage.monster)；打贏 → quest 自動推進 (getItem 派條目)
func cmd_quest_battle(id: int, quest_id: String) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var q := _quest_by_id(quest_id)
	if q.is_empty():
		return
	var stage := RulesQuest.stage_of(e["ch"], q)
	if stage.is_empty() or String(stage.get("type", "")) != "fight":
		return _msg(id, "而家唔係 PK 戰階段")
	var npc: Dictionary = data.quest_npcs.get(String(stage.get("npc", "")), {})
	if npc.is_empty() or not _near(e, int(npc["x"]), int(npc["y"])):
		return _msg(id, "要行近%s先得" % npc.get("name", ""))
	var boss_id := int(stage.get("monster", 0))
	if boss_id <= 0 or not data.monsters.has(boss_id):
		return
	var qid := String(q["id"])
	for o in ents.values():
		if o["kind"] == "mob" and str(o.get("mob", {}).get("quest_boss", "")) == qid:
			return _msg(id, "boss 仲喺度！")
	var b: Variant = _spawn_mob(boss_id, DEFAULT_ZONE)
	if b == null:
		return
	b["mob"]["quest_boss"] = qid
	b["x"] = int(npc["x"]) + 1      # 放喺 NPC 隔籬 (野區)
	b["y"] = int(npc["y"]) + 1
	b["tx"] = b["x"]
	b["ty"] = b["y"]
	b["mob"]["home_x"] = b["x"]
	b["mob"]["home_y"] = b["y"]
	for line in stage.get("dialog", []):
		_msg(id, str(line))
	_emit({"k": "quest_battle", "dst": id, "quest": quest_id, "name": str(b["name"]), "id": int(b["id"])})
	_msg(id, "%s出現咗！打定輸贏！" % b["name"])


# ================= 融合 (義士特技, Step 10, spec 02 §6) =================
func _near_forge(e: Dictionary) -> bool:
	var f: Dictionary = data.facilities.get("forge", {})
	return not f.is_empty() and _near(e, int(f["x"]), int(f["y"]))


# 融合開始: 打鐵鋪度撳，義士 Lv10+，揀裝緊嗰件武器 + 背包第一粒屬性石
func cmd_fusion_start(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	if not _near_forge(e):
		return _msg(id, "要喺打鐵鋪附近先融合得")
	var ch: Dictionary = e["ch"]
	if str(ch.get("classId", "")) != "yishi":
		return _msg(id, "融合係義士特技")
	if int(ch["level"]) < 10:
		return _msg(id, "要 10 級先學得融合")
	if not (ch.get("fusing", {}) as Dictionary).is_empty():
		return _msg(id, "正在融合緊")
	var w := int(ch["equip"].get("weapon", 0))
	if w == 0:
		return _msg(id, "未裝備武器")
	if (ch.get("fusedJewels", {}) as Dictionary).has(w):
		return _msg(id, "呢把武器已經嵌咗寶石 (只能 1 粒)")
	var jewel := 0
	for b in ch["bag"]:
		var jd: Dictionary = data.jewel_by_item.get(int(b["id"]), {})
		if not jd.is_empty() and str(jd.get("kind", "")) == "stone":
			jewel = int(b["id"])
			break
	if jewel == 0:
		return _msg(id, "背包要有一粒屬性石先融合得")
	ch["fusing"] = {"weapon": w, "jewel": jewel, "start": tick}
	_emit({"k": "fusion", "src": id, "state": "start", "weapon": w, "jewel": jewel,
		"target": RulesJewel.FUSION_TARGET, "window": RulesJewel.FUSION_WINDOW})
	_msg(id, "集氣棒起動 — 喺 50%%±20%% 嗰時撳實！（%d 秒）" % int(RulesJewel.FUSION_SECONDS))


# 融合敲實: 集氣棒位置 = f(tick - start)；hit 判定成功 → 扣屬性石 + 武器嵌石
func cmd_fusion_hit(id: int) -> void:
	var e := ent(id)
	if e.is_empty() or not e.has("ch") or int(e["hp"]) <= 0:
		return
	var ch: Dictionary = e["ch"]
	var fs: Dictionary = ch.get("fusing", {})
	if fs.is_empty():
		return _msg(id, "未開始融合 — 去打鐵鋪撳融合")
	ch.erase("fusing")
	var elapsed := tick - int(fs["start"])
	if RulesJewel.fusion_hit(elapsed):
		var jewel := int(fs["jewel"])
		var jd: Dictionary = data.jewel_by_item.get(jewel, {})
		RulesShop.remove_item(ch["bag"], jewel, 1)
		var wp := int(fs["weapon"])
		ch["fusedJewels"][wp] = {"elem": str(jd.get("elem", "none")), "pct": float(int(jd["pct"])) / 100.0}
		_emit({"k": "fusion", "src": id, "state": "ok", "weapon": wp, "elem": str(jd.get("elem", "")), "pct": int(jd["pct"])})
		_msg(id, "融合成功！%s 燒入咗武器（%s+%d%%）" % [jd["name"], jd.get("elem", ""), int(jd["pct"])])
	else:
		_emit({"k": "fusion", "src": id, "state": "fail"})
		_msg(id, "撳早/撳遲咗，再試下")


# 狀態術: status = 加狀態；cure = 解除對方狀態【原】
func _spell_status(p: Dictionary, def: Dictionary, t: Dictionary) -> void:
	var cure := str(def.get("cure", ""))
	var id := str(def.get("status", ""))
	if cure != "":
		var st: Dictionary
		if t["kind"] == "mob":
			if not t.has("status"):
				t["status"] = {}
			st = t["status"]
		else:
			if not (t["ch"] as Dictionary).has("status"):
				t["ch"]["status"] = {}
			st = t["ch"]["status"]
		if not RulesSpell.has(st, cure, tick):
			p["ch"]["mp"] = int(p["ch"]["mp"]) + _mp_cost(p["ch"], int(def["mp"]))    # 白費: 退款
			return _msg(int(p["id"]), "目標冇%s狀態，術法白費" % cure)
		RulesSpell.clear_status(st, cure)
		_emit({"k": "status", "dst": t["id"], "id": cure, "until": 0, "applied": false})
		_msg(int(p["id"]), "解咗%s狀態" % cure)
		return
	if id == "":
		return
	var ticks := RulesSpell.status_ticks(id)
	if t["kind"] == "mob":
		if not t.has("status"):
			t["status"] = {}
		RulesSpell.add_status(t["status"], id, ticks, tick)
	else:
		var ch2: Dictionary = t["ch"]
		if not ch2.has("status"):
			ch2["status"] = {}
		RulesSpell.add_status(ch2["status"], id, ticks, tick)
	_emit({"k": "status", "dst": t["id"], "id": id, "until": tick + ticks, "applied": true})
	_msg(int(p["id"]), "「%s」生效" % str(def["name"]))


# 增益術: 施自己 (聚力/強力/神力/護甲/護鏡系, spec 02 §7)
func _spell_buff(p: Dictionary, def: Dictionary) -> void:
	var ch: Dictionary = p["ch"]
	var id := str(def.get("status", ""))
	if id == "":
		return
	var ticks := RulesSpell.status_ticks(id)
	if not ch.has("status"):
		ch["status"] = {}
	RulesSpell.add_status(ch["status"], id, ticks, tick)
	_emit({"k": "status", "dst": p["id"], "id": id, "until": tick + ticks, "applied": true})
	_msg(int(p["id"]), "施咗「%s」（%d tick）" % [str(def["name"]), ticks])


# 術法怪吟唱生效: 傷害 (aoe = 打晒附近 ch) / 狀態 (打目標)
func _resolve_mob_cast(m: Dictionary, s: Dictionary, d: Dictionary, tgt: Dictionary) -> void:
	var cs: Dictionary = m["casting"]
	if tick < int(cs["done_at"]):
		m["tx"] = m["x"]
		m["ty"] = m["y"]
		return
	m.erase("casting")
	var sdef: Dictionary = data.spell_by_id.get(str(cs["spell"]), {})
	if sdef.is_empty():
		return
	if tgt.is_empty() or int(tgt["hp"]) <= 0 \
			or not RulesCombat.in_range(m["x"], m["y"], tgt["x"], tgt["y"], float(sdef["range"])):
		s["next_spell"] = tick + int(d.get("spellCd", 600))
		return
	match str(sdef["kind"]):
		"attack":
			var aoe := int(sdef.get("aoe", 0))
			var targets: Array = []
			if aoe > 0:
				for o in ents.values():
					if o.has("ch") and int(o["hp"]) > 0 \
							and RulesCombat.in_range(tgt["x"], tgt["y"], o["x"], o["y"], aoe):
						targets.append(o)
			else:
				targets.append(tgt)
			for o in targets:
				var pch: Dictionary = o["ch"]
				var pd := RulesStats.player_spell_def(int(pch["level"]), int(pch["attrs"]["spi"])) \
					* RulesSpell.spell_def_mult(pch.get("status", {}), tick)
				var dmg := RulesSpell.calc_spell_damage(float(sdef["power"]), float(d["level"]), pd,
					str(sdef["elem"]), "none", 0.0, rng_fn)
				_emit({"k": "spell_hit", "src": m["id"], "dst": o["id"], "dmg": dmg, "elem": str(sdef["elem"])})
				damage(o, dmg, m)
		"status":
			var sid := str(sdef.get("status", ""))
			if sid != "" and not tgt.is_empty() and tgt.has("ch"):
				var pch2: Dictionary = tgt["ch"]
				if not pch2.has("status"):
					pch2["status"] = {}
				RulesSpell.add_status(pch2["status"], sid, RulesSpell.status_ticks(sid), tick)
				_emit({"k": "status", "dst": tgt["id"], "id": sid, "until": tick + RulesSpell.status_ticks(sid), "applied": true})
	s["next_spell"] = tick + int(d.get("spellCd", 600))


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
	if ke != int(clk.get("lastKe", -1)):
		clk["lastKe"] = ke
		_sync_quest_npcs()          # 時辰窗口 NPC (Step 8): 每刻 check 一次


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
		# 逃跑怪 sprint: tick%2=0 嗰陣郁兩格 → 平均 1.5× 移速 (spec 04 §3)
		var mv := 2 if (e["kind"] == "mob" and (e.get("mob", {}) as Dictionary).get("state", "") == "flee" and tick % 2 == 0) else 1
		for _k in mv:
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
		var st_vis: Array = []
		var st_all: Dictionary = e.get("status", {}) if e["kind"] == "mob" else e.get("ch", {}).get("status", {})
		for k in st_all:
			if int(st_all[k]) > tick:
				st_vis.append(str(k))
		out.append({"id": e["id"], "name": e["name"], "x": e["x"], "y": e["y"], "face": e["face"],
			"bot": e["kind"] == "bot", "hp": e["hp"], "maxHp": e["max_hp"], "level": e["level"], "mob": e["kind"] == "mob",
			"statuses": st_vis, "casting": e.has("casting")})
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
