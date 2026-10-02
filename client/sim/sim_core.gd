extends RefCounted
# Sim 繼承鏈 第 1 層: 核心狀態 / 讀取 / 共用 helper / 生成單位
# 鏈: sim_core -> sim_quest -> sim_char -> sim_econ -> sim_battle -> sim_combat -> sim_skill -> sim_ai -> sim_recruit -> sim_office -> sim_comm -> sim_station -> sim_mount -> sim (class_name Sim)
# 規矩: 每層只可以叫自己或者下層嘅 func (上層 func 下層睇唔到)

signal event_emitted(ev: Dictionary)

const W := GameData.WORLD_W                            # 全域格仔 (多張地圖拼埋, spec 12 §2)
const H := GameData.WORLD_H
const NEAR := 3                                        # 設施互動距離(格)
const WITNESS_RANGE := 8                               # NPC 目擊範圍(格) (Step 5.2)
const GROUP_RANGE := 5                                 # 群居怪同類仇恨範圍(格) (Step 11, spec 04 §3)
const DEFAULT_ZONE := "field_1"
const PATH_CAP := 30000                                # cmd_move A* 節點上限 (spec 12 §3；原版大圖 251x188 對角要 ~2 萬)
const CHASE_CAP := 800                                 # 追擊 A* 節點上限
const FACE_COUNT := 12                                 # 頭像款數 (UI 佔位頭像 face_0..11)

var data: GameData
var rng: SimRng
var rng_fn: Callable
var state: Dictionary = {}
var inn_pos := Vector2i(10, 10)   # 復活點(客棧)
# ---- LLM 層 (S09d, spec 09 §5) ----
# pending 只喺 instance（唔入存檔；重載 = 未回覆嘅請求當冇，模板後備照玩）。key 永遠唔入 sim。
var _llm_pending: Dictionary = {}
var _llm_seq: int = 0


func _init(game_data: GameData, seed_value: int = 1) -> void:
	data = game_data
	rng = SimRng.new(seed_value)
	rng_fn = Callable(rng, "next")
	state = {"tick": 0, "next_id": 1, "ents": {}, "respawns": [], "player_id": -1, "bots": [],
		"clock": {"day": 0, "ke": 0, "lastShichen": -1, "is_night": false}, "market": {}, "disasters": [],
		"cityAttrs": {}, "quest_npcs": {}, "cityGov": {}, "cityPop": {},
		"rumors": [], "rumorSeq": 0,		# S09b 傳聞 (spec 09 §4)
		"llm": {"enabled": false, "model": "",
			"used": {"day": -1, "calls": 0, "reflect": 0}, "cd": {}, "lastError": ""},
		"marry": {"festive": {}}}          # S09e 結婚/婚慶氛圍 (spec 06 §9)
	inn_pos = Vector2i(int(data.inn["x"]), int(data.inn["y"]))
	_init_markets()
	_init_city_attrs()

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


# ---- 城池屬性 (S08b, spec 08 §3) ----
func _city_attr_cfg() -> Dictionary:
	return data.world.get("cityAttrs", {})

func _init_city_attrs() -> void:
	var out := {}
	for c in data.world["cities"]:
		out[String(c.id)] = RulesCity.init_attrs(c, _city_attr_cfg())
	state["cityAttrs"] = out

# 舊存檔冇 cityAttrs → 用 world 初值補返 (現有嘅保留)
func _ensure_city_attrs() -> void:
	var ca: Dictionary = state.get("cityAttrs", {})
	for c in data.world["cities"]:
		if not ca.has(String(c.id)):
			ca[String(c.id)] = RulesCity.init_attrs(c, _city_attr_cfg())
	state["cityAttrs"] = ca

# 某城現時屬性 (冇 = 初始化)
func city_attrs(city_id: String) -> Dictionary:
	_ensure_city_attrs()
	return (state["cityAttrs"] as Dictionary).get(city_id, {})

func city_attrs_set(city_id: String, attrs: Dictionary) -> void:
	_ensure_city_attrs()
	state["cityAttrs"][city_id] = attrs

# world city + 現時 attrs + 現時人口 (市場/天災規則用)
func _city_with_attrs(c: Dictionary) -> Dictionary:
	var o := c.duplicate()
	o["attrs"] = city_attrs(String(c.id))
	o["pop"] = city_pop(String(c.id))
	return o


# ---- 城池民心 + 法令 (S08g, spec 08 §9/§10) ----
# 民心/法令要有城池（城主）先啟動；單機未有佔城系統（S10）→ state["cityGov"] 預設空 =
# 未啟動，全部 helper 回兼容值。佔城入口留 S10c。
func _civic_cfg() -> Dictionary:
	return data.world.get("cityMorale", {})


func _law_cfg() -> Dictionary:
	return data.world.get("cityLaw", {})


func _city_gov_read(city_id: String) -> Dictionary:
	var g = (state.get("cityGov", {}) as Dictionary).get(city_id, {})
	return g if g is Dictionary else {}


# 城池係唔係已經被玩家佔領（民心/法令已啟動）
func city_gov_active(city_id: String) -> bool:
	return not _city_gov_read(city_id).is_empty()


# 建立城池治理狀態（佔城時叫；S08g 淨係測試/預留 S10c 用）
func city_gov_init(city_id: String, tax: String = "") -> Dictionary:
	if city_id == "":
		return {}
	var govs: Dictionary = state.get("cityGov", {})
	if not govs.has(city_id):
		govs[city_id] = {
			"morale": RulesCivic.initial(_civic_cfg()),
			"tax": tax if tax != "" else String(_civic_cfg().get("defaultTax", "low")),
			"laws": RulesCivic.default_laws(_law_cfg()),
			"lastLawDay": -1,
			"moraleGain": 0.0,
		}
		state["cityGov"] = govs
	return govs[city_id]


func city_gov(city_id: String) -> Dictionary:
	return _city_gov_read(city_id)


func city_morale(city_id: String) -> int:
	var g := _city_gov_read(city_id)
	if g.is_empty():
		return RulesCivic.initial(_civic_cfg())
	return int(round(clampf(float(g.get("morale", 100)), 0.0, float(RulesCivic.cap(_civic_cfg())))))


func city_morale_set(city_id: String, v: Variant) -> void:
	var g := city_gov_init(city_id)
	if not g.is_empty():
		g["morale"] = clampf(float(v), 0.0, float(RulesCivic.cap(_civic_cfg())))


# 救災/捐贈官令名聲 → 所屬（有城池）義勇軍民心【自訂】。回傳今次實際加幾多。
func civic_fame_gain(ch: Dictionary, fame: int) -> float:
	var m = ch.get("militia", {})
	if not (m is Dictionary) or not bool((m as Dictionary).get("hasCity", false)):
		return 0.0
	var city := String((m as Dictionary).get("city", ""))
	if city == "" or not city_gov_active(city):
		return 0.0
	var g := city_gov(city)
	var gain := RulesCivic.morale_gain(fame, float(g.get("moraleGain", 0.0)), _civic_cfg())
	if gain <= 0.0:
		return 0.0
	g["morale"] = clampf(float(g.get("morale", 100)) + gain, 0.0, float(RulesCivic.cap(_civic_cfg())))
	g["moraleGain"] = float(g.get("moraleGain", 0.0)) + gain
	return gain


# 城池法令係唔係開（未啟動 = 全部照舊 = true，舊行為零改變）
func law_allows(city_id: String, law_id: String) -> bool:
	var g := _city_gov_read(city_id)
	if g.is_empty():
		return true
	return bool((g.get("laws", {}) as Dictionary).get(law_id, true))


# 現時人口（動態，market/demand 用）；唔喺 state 就回 world 初值
func city_pop(city_id: String) -> int:
	var pn: Dictionary = state.get("cityPop", {})
	if pn.has(city_id):
		return int(pn[city_id])
	for c in data.world["cities"]:
		if String(c.id) == city_id:
			return int(c["pop"])
	return 0


func city_pop_set(city_id: String, v: int) -> void:
	var pn: Dictionary = state.get("cityPop", {})
	pn[city_id] = maxi(0, v)
	state["cityPop"] = pn


# 座標 → 城池 id（"" = 唔喺城池）；各層共用（法令 gate 用）
func city_id_at(x: int, y: int) -> String:
	return GameData.map_city_of(data.map_at(x, y))


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


# 野外工作區 (spec 05): 企喺呢格係唔係 &skill 可做嘅工作區 (a.work 含 skill)。
# 唔喺任何工作區 = 否 → cmd_work 唔俾做。
func work_ok_here(skill: String, x: int, y: int) -> bool:
	var md := data.map_at(x, y)
	if md.is_empty():
		return false
	for a in md.get("areas", []):
		if x >= int(a["x0"]) and x <= int(a["x1"]) and y >= int(a["y0"]) and y <= int(a["y1"]):
			if (a.get("work", []) as Array).has(skill):
				return true
	return false


# 將一格嘅 工作區技能名 砌好 (read-model，畀 UI 顯示「而家係X地，可以做農耕」)
func work_area_skills(x: int, y: int) -> Array:
	var md := data.map_at(x, y)
	if md.is_empty():
		return []
	for a in md.get("areas", []):
		if x >= int(a["x0"]) and x <= int(a["x1"]) and y >= int(a["y0"]) and y <= int(a["y1"]):
			return (a.get("work", []) as Array).duplicate()
	return []


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
	return data.zone_by_id.get(zone_id, {})


# 某格所在 zone (UI 用: 渲染顏色/顯示區名)。搵唔到 = {}
func zone_view(x: int, y: int) -> Dictionary:
	var i := data.map_index(x, y)
	if i < 0:
		return {}
	var z: Dictionary = data.zones[i]
	return {"id": str(z["id"]), "name": str(z.get("name", z["id"])), "area": area_name(x, y)}


# 邊界內第一個匹配嘅 zone；搵唔到當安全 (例如冇定義嘅角落)
func is_safe(x: int, y: int) -> bool:
	var i := data.map_index(x, y)
	return bool(data.zones[i]["safe"]) if i >= 0 else true


func travel_point_by_id(point_id: String) -> Dictionary:
	return data.tp_by_id.get(point_id, {})


func ent(id: int) -> Dictionary:
	return ents.get(id, {})


# 有角色 (ch) 嘅單位 id，按所在地圖分組，每 tick 砌一次 (怪物揀仇恨目標用；怪佔大多數，唔使逐隻行晒全部單位)
# 地圖之間隔 ≥20 格 > 最大 aggroRange，所以只睇同一張地圖夠晒。
# 次序 = ents 插入次序 (同行 ents.values() 一致 → 決定性)；用嗰陣要再 check 單位仲喺度
var _actors_tick := -1
var _actors_by_map: Dictionary = {}
const _NO_ACTORS: Array = []

func _actor_ids_on_map(map_i: int) -> Array:
	if _actors_tick != tick:
		_actors_tick = tick
		_actors_by_map.clear()
		for e in ents.values():
			if e.has("ch"):
				var k := data.map_index(int(e["x"]), int(e["y"]))
				if not _actors_by_map.has(k):
					_actors_by_map[k] = []
				_actors_by_map[k].append(int(e["id"]))
	return _actors_by_map.get(map_i, _NO_ACTORS)


# 刪單位 + 清走所有人對佢嘅 atk_target
func _remove_ent(id: int) -> void:
	_remove_ents([id])


func _remove_ents(ids: Array) -> void:
	if ids.is_empty():
		return
	var gone := {}
	for id in ids:
		ents.erase(int(id))
		gone[int(id)] = true
	for e in ents.values():
		if gone.has(int(e["atk_target"])):
			e["atk_target"] = 0


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
		"face": id % FACE_COUNT, "hp": 0, "max_hp": 0, "level": 1, "atk_target": 0, "next_atk": 0,
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


# ================= 裝備 (Step 11.6, spec 02 §9) =================
# equip = {weapon (現用), weapons[3], wslot, head/body/boots/ring/necklace (item id, 0 = 空),
#          dur {str(item): 耐久}, hits (受擊累計)}。裝備 = 背包參照 (件嘢留喺背包，唔可以賣/死亡唔會跌)
# 補齊欄位 + 舊存檔兼容 (舊版得 weapon/boots，而且開場武器/靴唔喺背包)
func _ensure_equip(ch: Dictionary) -> void:
	var eq: Dictionary = ch["equip"]
	if not eq.has("weapons"):
		eq["weapons"] = [int(eq.get("weapon", 0)), 0, 0]
		eq["wslot"] = 0
	eq["weapon"] = int(eq["weapons"][int(eq["wslot"])])
	for s in RulesEquip.SLOTS:
		if not eq.has(s):
			eq[s] = 0
	if not eq.has("dur"):
		eq["dur"] = {}
	if not eq.has("hits"):
		eq["hits"] = 0
	for it in _equipped_items(ch):
		if RulesShop.count_item(ch["bag"], it) < _equipped_n(ch, it):
			RulesShop.add_item(ch["bag"], it, _equipped_n(ch, it) - RulesShop.count_item(ch["bag"], it))
	if not eq.has("whits"):
		eq["whits"] = 0
	for it in _equipped_items(ch):
		if not eq["dur"].has(str(it)):
			eq["dur"][str(it)] = _max_dur(it)


# 裝備耐久上限: 防具/武器 (Step 12 武器都有耐久)；其他 = 0
func _max_dur(item: int) -> int:
	if data.armors.has(item):
		return int(data.armors[item]["max_dur"])
	return int(data.weapons.get(item, {}).get("max_dur", 0))


# 現用武器 {power, hit}；耐久 0 = 武器強度減半【自訂】(同防具一致, Step 12)
func _weapon_def(ch: Dictionary) -> Dictionary:
	var w := int(ch["equip"].get("weapon", 0))
	var wd: Dictionary = data.weapons.get(w, {"power": 0.0, "hit": 45.0})
	if w > 0 and int(ch["equip"].get("dur", {}).get(str(w), 1)) <= 0:
		return {"power": float(wd["power"]) * 0.5, "hit": wd["hit"]}
	return wd


# 出手磨損 (Step 12): 每打中 hitsPerWear 下 → 現用武器耐久 -1
func _wear_weapon_hit(e: Dictionary) -> void:
	var eq: Dictionary = e["ch"]["equip"]
	var w := int(eq.get("weapon", 0))
	if w == 0 or not eq.has("dur"):
		return
	eq["whits"] = int(eq.get("whits", 0)) + 1
	if not RulesEquip.hit_wears(int(eq["whits"]), int(data.equip_cfg["durability"]["hitsPerWear"])):
		return
	var k := str(w)
	if int(eq["dur"].get(k, 0)) > 0:
		eq["dur"][k] = int(eq["dur"][k]) - 1
		if int(eq["dur"][k]) == 0:
			_emit({"k": "armor_broken", "dst": int(e["id"]), "item": w})
			_msg(int(e["id"]), "「%s」耐久用盡，威力減半" % data.names.get(w, str(w)))


# 身上所有裝備 item id (武器 3 槽 + 5 部位，唔計 0)
func _equipped_items(ch: Dictionary) -> Array:
	var out: Array = []
	var eq: Dictionary = ch["equip"]
	for w in eq.get("weapons", [eq.get("weapon", 0)]):
		if int(w) > 0:
			out.append(int(w))
	for s in RulesEquip.SLOTS:
		if int(eq.get(s, 0)) > 0:
			out.append(int(eq[s]))
	return out


func _equipped_n(ch: Dictionary, item: int) -> int:
	return _equipped_items(ch).count(item)


# 身上防具加總 (耐久 0 減半)
func _armor_bonus(ch: Dictionary) -> Dictionary:
	var worn: Array = []
	var eq: Dictionary = ch["equip"]
	for s in RulesEquip.SLOTS:
		var a := int(eq.get(s, 0))
		var ad: Dictionary = data.armors.get(a, {})
		if a > 0 and not ad.is_empty():
			worn.append({"stats": ad["stats"], "dur": int(eq.get("dur", {}).get(str(a), 0))})
	return RulesEquip.sum_worn(worn)


# 戰鬥用有效屬性 = 基礎 + 防具加成 (只影響戰鬥，唔改 HP/MP/SP 上限【自訂】)
# ab: 已計好嘅 _armor_bonus (同一下出手重用)；{} = 即場計
func _eff_attr(ch: Dictionary, k: String, ab: Dictionary = {}) -> float:
	if ab.is_empty():
		ab = _armor_bonus(ch)
	return float(ch["attrs"].get(k, 0)) + float(ab.get(k, 0))


# 受擊磨損: 每 hitsPerWear 下有傷害 → 身上每件防具耐久 -1 (spec 02 §9)
func _wear_armor_hit(e: Dictionary) -> void:
	var ch: Dictionary = e["ch"]
	var eq: Dictionary = ch["equip"]
	if not eq.has("hits"):
		return
	eq["hits"] = int(eq["hits"]) + 1
	if not RulesEquip.hit_wears(int(eq["hits"]), int(data.equip_cfg["durability"]["hitsPerWear"])):
		return
	for s in RulesEquip.SLOTS:
		var a := int(eq[s])
		if a > 0 and int(eq["dur"].get(str(a), 0)) > 0:
			eq["dur"][str(a)] = int(eq["dur"][str(a)]) - 1
			if int(eq["dur"][str(a)]) == 0:
				_emit({"k": "armor_broken", "dst": int(e["id"]), "item": a})
				_msg(int(e["id"]), "「%s」耐久用盡，效果減半" % data.names.get(a, str(a)))


# 死亡: 身上每件裝備 (防具 + 武器) 扣上限 10% 耐久 (spec 03 §4.3)
func _wear_armor_death(ch: Dictionary) -> void:
	var eq: Dictionary = ch["equip"]
	if not eq.has("dur"):
		return
	var seen := {}
	for a in _equipped_items(ch):     # 防具 + 武器 3 槽 (同一件只扣一次)
		if seen.has(a):
			continue
		seen[a] = true
		eq["dur"][str(a)] = RulesEquip.dur_after_death(int(eq["dur"].get(str(a), 0)),
			_max_dur(a), float(data.equip_cfg["durability"]["deathLossPct"]))


# 背包已經冇嘅防具 → 清耐久記錄
func _cleanup_dur(ch: Dictionary) -> void:
	var d: Dictionary = ch["equip"].get("dur", {})
	for k in d.keys():
		if RulesShop.count_item(ch["bag"], int(k)) <= 0:
			d.erase(k)


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


func _spawn_actor(ename: String, kind: String, class_id: String = "yishi", spawn_range: Array = []) -> Dictionary:
	var sp: Array = spawn_range if not spawn_range.is_empty() else _home_map().get("spawn", [int(data.inn["x"]) - 2, int(data.inn["y"]) - 2, int(data.inn["x"]) + 2, int(data.inn["y"]) + 2])
	var e := _new_ent(ename, kind, _pick_free(int(sp[0]), int(sp[1]), int(sp[2]), int(sp[3])))
	e["ch"] = RulesStats.create_character(data, ename.substr(0, 8), class_id)
	e["ch"]["tools"] = {}                     # skill -> {item, dur} (Step 7.1)
	e["ch"]["workLv"] = {}                    # 生產技能等級 skill -> {lv, exp} (Step 12；未做過 = 冇 key)
	e["ch"]["storage"] = []                   # 天地商行倉庫 [{id,n}] (Step 7.2)
	e["ch"]["storageSub"] = false             # 有冇訂閱天地商行 (200/日)
	e["ch"]["tiandi"] = {"deposit": [], "buyTool": false, "sellTool": false}   # 天地商行自動化設定 (Step 13)
	e["ch"]["ap"] = int(data.world["ap"]["max"])   # 行動力 (Step 13)，子時回滿
	e["ch"]["chaExp"] = 0                       # 魅力經驗 (捐獻, Step 13)
	e["ch"]["titleRank"] = 0                    # 頭銜階 0 = 白身 (Step 14, data/titles.json)
	e["ch"]["thirst"] = int(data.world["thirst"]["max"])   # 飲水度 (Step 14, spec 01 §9)
	e["ch"]["office"] = {}                      # 官令 {orderDay, order:{id, from, to?, met:[]}} (Step 14)
	e["ch"]["contrib"] = 0                      # 官宅貢獻 (官令攞，換行動丹)
	e["ch"]["polExp"] = 0                       # 政治經驗 (官令)
	e["ch"]["equip"]["spellbooks"] = [0, 0, 0]   # 術法快捷列 3 格 (Step 9, spec 02 §3.1)
	e["ch"]["equip"]["jewels"] = [0, 0]         # 寶石欄 2 格 (Step 10, spec 02 §4)
	e["ch"]["ultimates"] = []                   # 已學絕招 (spec 02 §5)
	e["ch"]["ultCd"] = {}                       # ultId -> until tick
	e["ch"]["fusedJewels"] = {}                 # 武器嵌石: weapon item id -> {elem, pct} (融合, 只能 1 粒)
	e["ch"]["fusing"] = {}                      # 進行中融合 QTE {weapon, jewel, start} (Step 10)
	e["ch"]["expert"] = {}                      # 專長 skillId -> exp (S01c, spec 01 §8)
	e["ch"]["classSkill"] = ""                  # 職業特技 (S02c, spec 02 §6): 學咗 = skill id (未學 = "")
	e["ch"]["rumors"] = []                      # 辯士竊聽傳聞線索/情報冊 (S02c-辯士, spec 02 §6)
	_ensure_equip(e["ch"])                      # 武器 3 槽 + 5 部位防具 + 耐久 (Step 11.6)
	_sync_stats(e)
	return e


# 新手城地圖 (world.homeCity / ch.homeCity；建角揀城 UAT-feedback)
func _city_map(city: String) -> Dictionary:
	for md in data.maps:
		if String(md.get("city", "")) == city:
			return md
	return {}


# 玩家已揀新手城 → 用玩家嗰個（ch.homeCity）；否則預設 world.homeCity（許昌）
func _home_map() -> Dictionary:
	var p := ent(int(state.get("player_id", -1)))
	var home := String(p.get("ch", {}).get("homeCity", data.world["homeCity"])) if not p.is_empty() and (p.get("ch") is Dictionary) else String(data.world["homeCity"])
	if String(home) != "":
		var c := _city_map(home)
		if not c.is_empty():
			return c
	return _city_map(String(data.world["homeCity"]))


func add_bots(n: int) -> void:
	for i in n:
		var nm: String = BotSys.NAMES[i % BotSys.NAMES.size()] + (str(i) if i >= BotSys.NAMES.size() else "")
		var e := _spawn_actor(nm, "bot")
		BotSys.init_identity(e, rng)
		# S08b：城治安屬性影響居民犯案率（治安 50 = 原本）
		var crime_mul := RulesCity.crime_mult(city_attrs(String(data.world["homeCity"])), _city_attr_cfg())
		if rng.next() < float(data.world["bots"]["criminalPct"]) * crime_mul:   # S03a: 部分居民係紅名(殺人魔)「殺人魔 NPC」
			e["ch"]["criminal"] = true
		state["bots"].append(int(e["id"]))


# S09a 居民化 (spec 09 §1): 每張 city 地圖生 12~20 名居民 (大城多)，代入 residents.json 性格/理念/role/日程/homeZone。
func add_residents() -> void:
	for md in data.maps:
		if String(md.get("kind", "")) != "city":
			continue
		var city_id := String(md.get("city", ""))
		if city_id == "":
			continue
		var cdef: Dictionary = data.cities.get(city_id, {})
		var n := RulesResident.city_count(cdef, data.residents)
		var zone_id := RulesResident.home_zone(data.residents, city_id)
		var z := zone_by_id(String(md["id"]))
		var r := [int(z.get("x0", 0)), int(z.get("y0", 0)), int(z.get("x1", 0)), int(z.get("y1", 0))]
		var used := {}
		for i in n:
			var nm := RulesResident.make_name(data.residents, rng.below(maxi(1, RulesResident.surname_pool(data.residents).size())), rng.below(maxi(1, RulesResident.given_pool(data.residents).size())))
			if used.has(nm):
				nm += str(i)
			used[nm] = true
			var e := _spawn_actor(nm, "bot", "yishi", r)
			BotSys.init_resident(e, rng, data.residents, city_id, zone_id)
			var crime_mul := RulesCity.crime_mult(city_attrs(city_id), _city_attr_cfg())
			if rng.next() < float(data.world["bots"]["criminalPct"]) * crime_mul:
				e["ch"]["criminal"] = true
			state["bots"].append(int(e["id"]))


# 捕快 NPC【自訂】: 每張 city 地圖生 guards.json cfg.perCity 隻，50~75 級，企喺客棧側 (唔係城門口)。
func add_guards() -> void:
	var g := RulesGuard.cfg(data.guards)
	if g.is_empty():
		return
	var per_city := int(g.get("perCity", 2))
	for md in data.maps:
		if String(md.get("kind", "")) != "city":
			continue
		var city_id := String(md.get("city", ""))
		if city_id == "":
			continue
		var inn_here := Vector2i(-1, -1)
		for x in data.inns:
			var m: Dictionary = data.map_by_id.get(String(x.get("map", "")), {})
			if String(m.get("city", "")) == city_id:
				inn_here = Vector2i(int(x["x"]), int(x["y"]))
				break
		if inn_here.x < 0:      # 冇客棧嘅城: 用城圖中心做企定位基準 (UAT-001~003)
			var z: Dictionary = zone_by_id(String(md.get("id", "")))
			if z.is_empty():
				continue
			inn_here = Vector2i((int(z["x0"]) + int(z["x1"])) / 2, (int(z["y0"]) + int(z["y1"])) / 2)
		var stand := RulesGuard.stand_pos(inn_here.x, inn_here.y, g)
		for i in per_city:
			var e := _spawn_actor("捕快" + str(i + 1), "bot", "yishi", [stand.x - 1, stand.y - 1, stand.x + 1, stand.y + 1])
			_bump_level(e, RulesGuard.level_of(g, i, per_city))
			BotSys.init_guard(e, city_id, stand, RulesResident.home_zone(data.residents, city_id))
			state["bots"].append(int(e["id"]))


# 提升已生成單位嘅等級 (捕快用): 照 class 成長公式重推屬性/HP/MP/SP，滿血滿藍
func _bump_level(e: Dictionary, lv: int) -> void:
	var ch: Dictionary = e["ch"]
	var cls: Dictionary = data.classes.get(String(ch["classId"]), {})
	if cls.is_empty():
		return
	var attrs := RulesStats.attrs_at(cls, lv)
	ch["level"] = lv
	ch["attrs"] = attrs
	ch["hp"] = RulesStats.max_hp(lv, attrs)
	ch["mp"] = RulesStats.max_mp(lv, attrs)
	ch["sp"] = RulesStats.max_sp(lv, attrs)
	_sync_stats(e)


# S09a 居民日程: 居民 homeCity → 對應城內地圖 id (kind:city 且 city==homeCity；如 runan → runan_city)。
# 居民喺 in-town 活動 (eat/home/sleep) 時要留喺呢張城內地圖行街，唔出野外。
func resident_city_map_id(city_id: String) -> String:
	if city_id == "":
		return ""
	for md in data.maps:
		if String(md.get("kind", "")) == "city" and String(md.get("city", "")) == city_id:
			return String(md.get("id", ""))
	return ""


# S09a: 居民休息客棧位置。居民 → 自己城嘅客棧 (冇 = Vector2i(-1,-1) 唔撤退)；legacy bot → 預設客棧。
func resident_inn_pos(e: Dictionary) -> Vector2i:
	var ch: Dictionary = e.get("ch", {})
	if not bool(ch.get("resident", false)):
		return inn_pos
	var city := String(ch.get("homeCity", ""))
	if city == "":
		return inn_pos
	for x in data.inns:
		var m: Dictionary = data.map_by_id.get(String(x.get("map", "")), {})
		if String(m.get("city", "")) == city:
			return Vector2i(int(x["x"]), int(x["y"]))
	return Vector2i(-1, -1)


func init_mobs() -> void:
	for sp in data.spawns:
		if sp.get("night", false):
			continue                    # 夜怪由 _sync_night_spawns 處理
		for i in int(sp["count"]):
			_spawn_mob(int(sp["monster"]), String(sp.get("zone", DEFAULT_ZONE)))
	_spawn_random_chests()      # T-07 隨機寶箱: 開局即刻 spawn (spec 02 §6), 之後每日子時換位


# T-07 隨機寶箱【自訂】: 野外每張地圖 spawn 一個鎖住寶箱（開局 init_mobs + 每日子時換位）。
# 開鎖實體: {kind:"chest", locked, key(0..2), drop={items/gold}}；開岩鎖匙得賞、開錯留返再試。
const CHEST_KEYS := 3
const CHEST_RANGE := 2


func _spawn_random_chests() -> void:
	for z in data.zones as Array:
		if bool(z.get("safe", false)):
			continue     # 城/安全區唔生寶箱
		_spawn_chest_in_zone(z)


func _spawn_chest_in_zone(z: Dictionary) -> void:
	var p := _pick_free(int(z["x0"]), int(z["y0"]), int(z["x1"]), int(z["y1"]))
	var e := _new_ent("寶箱", "chest", p)
	e["face"] = 0
	e["hp"] = 1
	e["max_hp"] = 1
	e["locked"] = true
	e["key"] = int(floor(rng.next() * CHEST_KEYS))     # 0..2
	e["drop"] = _chest_drop()


# 隨機寶箱賞【自訂】: 低機率出武器/防具/寶石/消耗，多數少金。用 data 掉落表（items.json 隨機）
func _chest_drop() -> Dictionary:
	var gold := 10 + int(floor(rng.next() * 71))
	var items: Array = []
	if rng.next() < 0.3:
		var pool: Array = []
		for id in data.info.keys():
			var cat := int(data.info[id].get("cat", 0))
			if cat >= 1 and cat <= 18:
				pool.append(int(id))
			elif cat >= 20 and cat <= 60:
				if int(data.info[id].get("req_lv", 1)) <= 5:
					pool.append(int(id))
		if not pool.is_empty():
			items.append({"id": pool[int(floor(rng.next() * pool.size()))], "n": 1})
	return {"gold": gold, "items": items}


# S04a 地面掉落物 (spec 04 §6)【原=跌落地】: 物品堆跌落地，存在 capTicks tick 後消失；
# 戰騎「撿寶」友好技 (S07c) 自動執呢啲 (PLAN §4)。
func _drop_items(x: int, y: int, items: Array) -> Dictionary:
	if items.is_empty():
		return {}
	var e := _new_ent("掉落物", "dropped", Vector2i(x, y))
	e["face"] = 0
	e["hp"] = 1
	e["max_hp"] = 1
	e["drop"] = {"items": items, "until": tick + int(data.world.get("dropped", {}).get("capTicks", 300))}
	return e


# 每 tick: 過期地面掉落物消失
func _expire_drops() -> void:
	var gone: Array = []
	for e in ents.values():
		if e["kind"] == "dropped" and tick >= int(e["drop"]["until"]):
			gone.append(int(e["id"]))
	_remove_ents(gone)


func _spawn_mob(def_id: int, zone_id: String = DEFAULT_ZONE) -> Variant:
	var lv := 0                           # spawn 可選 lv = 呢個地圖嘅等級覆蓋
	for sp0 in data.spawns:
		if int(sp0["monster"]) == def_id and String(sp0.get("zone", DEFAULT_ZONE)) == zone_id:
			lv = int(sp0.get("lv", 0))
			break
	var d: Dictionary = data.mob_def(def_id, lv)
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
	e["mob"] = {"def": def_id, "home_x": p.x, "home_y": p.y, "state": "wander", "target": 0, "next_atk": 0, "zone": zone_id, "lv": lv}
	return e


# 目擊/傳聞入口 (Step 5.2 + S09b): actor_id 做咗一件事，附近有記憶表嘅 NPC (bot) 記低 + 調好感；
# 顯著事件 (spec 09 §4) 再種一條傳聞，之後每日擴散。
func _witness_nearby(actor_e: Dictionary, actor_id: int, kind: String, weight: int) -> void:
	var rk := RulesRumor.rumor_kind_of(kind, weight, data.residents)
	var origin := ""
	var wits: Array = []
	for w in ents.values():
		if int(w["id"]) == actor_id or not w.has("mem"):
			continue
		if RulesCombat.in_range(actor_e["x"], actor_e["y"], w["x"], w["y"], WITNESS_RANGE):
			NpcMemory.witness(w["mem"], actor_id, kind, tick, weight)
			wits.append(w)
			if rk != "" and origin == "":
				origin = city_id_at(int(actor_e["x"]), int(actor_e["y"]))
				if origin == "":
					origin = String(w.get("ch", {}).get("homeCity", ""))
	if wits.is_empty() or rk == "" or origin == "":
		return
	_seed_rumor(actor_id, rk, weight, origin, int(_clock()["day"]))
	var rumor := _rumor_by_key(RulesRumor.rumor_key(actor_id, rk))
	var memcap := RulesRumor.mem_cap(data.residents)
	for w in wits:                                  # 目擊者即刻入記憶表 (居民再由 _inject_rumor 按城覆蓋)
		NpcMemory.add_rumor(w["mem"], String(rumor["key"]), rumor, memcap)


func _rumor_by_key(key: String) -> Dictionary:
	_ensure_rumors()
	for r in state["rumors"]:
		if String(r.get("key", "")) == key:
			return r
	return {}


# ================= 傳聞擴散 (S09b, spec 09 §4) =================
# state["rumors"] = [{"key", "actor", "kind", "weight", "origin", "day", "cities": {city: day}, "deliver": {city: day}}]
# 目擊 → 種傳聞 (起源城即日) → 每日反思: 同城 + 跨城 (延遲 1~3 日) 注入居民記憶表。
func _ensure_rumors() -> void:
	if not (state.get("rumors") is Array):
		state["rumors"] = []
	if not state.has("rumorSeq"):
		state["rumorSeq"] = 0


# 全部 kind:city 城池 id (maps.json；排序決定性)
func _all_city_ids() -> Array:
	var out: Array = []
	for md in data.maps:
		if String(md.get("kind", "")) != "city":
			continue
		var cid := String(md.get("city", ""))
		if cid != "" and not out.has(cid):
			out.append(cid)
	out.sort()
	return out


func _city_name(city_id: String) -> String:
	return String((data.cities.get(city_id, {}) as Dictionary).get("name", city_id))


# 種/更新一條傳聞；起源城即日揭示，其餘城用獨立 SimRng 抽 1~3 日延遲
func _seed_rumor(actor: int, rkind: String, weight: int, origin: String, day: int) -> void:
	_ensure_rumors()
	var key := RulesRumor.rumor_key(actor, rkind)
	var list: Array = state["rumors"]
	for r in list:
		if String(r.get("key", "")) == key:
			r["weight"] = weight
			r["day"] = mini(int(r.get("day", day)), day)
			_inject_rumor(r, origin)
			return
	var cap := RulesRumor.cap(data.residents)
	if list.size() >= cap:
		var oi := 0
		var od := 1 << 60
		for i in list.size():
			if int(list[i].get("day", 0)) < od:
				od = int(list[i].get("day", 0))
				oi = i
		list.remove_at(oi)
	var seq := int(state.get("rumorSeq", 0))
	state["rumorSeq"] = seq + 1
	var rr := SimRng.new(910000 + seq * 7919)     # 獨立 SimRng，唔佔主 rng 流 (同 S08d 慣例)
	var rumor := RulesRumor.make_rumor(actor, rkind, weight, origin, day)
	var lo := RulesRumor.delay_min(data.residents)
	var hi := RulesRumor.delay_max(data.residents)
	for cid in _all_city_ids():
		if cid == origin:
			continue
		rumor["deliver"][cid] = day + RulesRumor.delay(lo, hi, rr.below(hi - lo + 1))
	list.append(rumor)
	_inject_rumor(rumor, origin)


# 將傳聞記入某城所有居民嘅記憶表 (同一 key 覆蓋)
func _inject_rumor(rumor: Dictionary, city: String) -> void:
	var memcap := RulesRumor.mem_cap(data.residents)
	for id in state["bots"]:
		var e := ent(int(id))
		if e.is_empty() or not e.has("mem"):
			continue
		if String((e.get("ch", {}) as Dictionary).get("homeCity", "")) != city:
			continue
		NpcMemory.add_rumor(e["mem"], String(rumor["key"]), rumor, memcap)


# 每日子時反思批次: 已揭示城持續注入；到期未傳嘅城揭示 + 注入 + emit
func _rumor_daily(day: int) -> void:
	_ensure_rumors()
	var list: Array = state["rumors"]
	var spread: Array = []
	for r in list:
		for cid in (r["cities"] as Dictionary).keys():
			_inject_rumor(r, String(cid))
		var deliver: Dictionary = r["deliver"]
		var due: Array = []
		for cid in deliver:
			if day >= int(deliver[cid]):
				due.append(cid)
		for cid in due:
			r["cities"][String(cid)] = day
			deliver.erase(cid)
			_inject_rumor(r, String(cid))
			spread.append({"r": r, "city": String(cid)})
	for s in spread:
		var r: Dictionary = s["r"]
		var city := String(s["city"])
		_emit({"k": "rumor_spread", "key": String(r["key"]), "actor": int(r["actor"]),
			"kind": String(r["kind"]), "city": city, "day": day})
		if String(r["kind"]) == "killer" and int(r["actor"]) == int(state["player_id"]):
			_msg(int(state["player_id"]), "你嘅惡名傳到%s" % _city_name(city))


# read-model: 某城已知傳聞 (city = "" → 全部)
func rumor_view(city: String = "") -> Array:
	_ensure_rumors()
	var out: Array = []
	for r in state["rumors"]:
		if city != "" and not (r["cities"] as Dictionary).has(city):
			continue
		out.append({"key": String(r["key"]), "actor": int(r["actor"]), "kind": String(r["kind"]),
			"weight": int(r["weight"]), "origin": String(r["origin"]), "day": int(r["day"]),
			"cities": (r["cities"] as Dictionary).keys()})
	return out


# read-model: 某 NPC 記憶表入面嘅傳聞
func known_rumors(id: int) -> Array:
	var e := ent(id)
	if e.is_empty() or not e.has("mem"):
		return []
	var rs: Dictionary = (e["mem"] as Dictionary).get("rumors", {})
	var out: Array = []
	for k in rs:
		out.append(rs[k])
	return out


# 同 NPC 傾偈 hook (官令戶口普查, Step 14)：sim_office 覆寫。key = "q:<npc>" / "g:<gid>"
func _office_on_talk(_e: Dictionary, _key: String, _x: int, _y: int) -> void:
	pass


# 居民委託 / 收集冊 hook (Step 16)：sim_comm 覆寫
func _comm_on_talk(_e: Dictionary, _npc_id: String) -> bool:
	return false


func _comm_on_kill(_by: Dictionary, _def_id: int) -> void:
	pass


func cmd_book_exchange(_id: int) -> void:
	pass


# 座騎 hook (Step 17a)：sim_mount 覆寫。落馬 (why = "attack" 用一般武器出手 / "die" 死亡)
func _mount_drop(_e: Dictionary, _why: String) -> void:
	pass


# 馬戰 hook (Step 17b)：sim_mount 覆寫，畀 sim_ai (喺繼承鏈上游) 用得
func is_riding(_ch: Dictionary) -> bool:
	return false


func _mount_weapon_type(_ch: Dictionary) -> String:
	return ""


func _mount_weapon_wdef(_ch: Dictionary) -> Dictionary:
	return {"power": 0.0, "hit": 0.0}


# 戰騎 hook (S07b)：sim_war_beast 覆寫；畀 sim_combat (喺繼承鏈上游) 用得
func _kill_beast(_t: Dictionary, _by: Dictionary) -> void:
	pass


func _beast_on_mob_kill(_by: Dictionary, _base_exp: int) -> void:
	pass


# 友好特技 hook (S07c)：sim_war_beast 覆寫。出戰戰騎學咗邊啲效果 (effect id → true)
func _friend_effect_active(_e: Dictionary, _effect: String) -> bool:
	return false


# 忠誠「痛楚屏障」減傷比例 hook (U13)：sim_war_beast 覆寫
func _friend_pain_shield_pct(_e: Dictionary) -> float:
	return 0.0


# 神獸/王者「加成」練功經驗倍率 hook (U13)：sim_war_beast 覆寫
func _friend_exp_mult(_e: Dictionary) -> float:
	return 1.0


# 內政武將協助 hook (S08b 掛鈎；S09c 同伴政治/專長協助 override)。回傳完成度加成 (0.0 = 冇)
func _domestic_assist_bonus(_ch: Dictionary) -> float:
	return 0.0


# 同伴政治 hook (S09c)：sim_recruit override。回傳同伴政治值 (加落營地監督完成度)；0 = 冇
func _companion_pol_bonus(_ch: Dictionary) -> int:
	return 0


# 生產專精 hook (S09c)：sim_recruit override。工作技能經驗倍率 (1.0 = 冇)
func _work_exp_mult(_ch: Dictionary, _skill: String) -> float:
	return 1.0


# 生產專精 hook (S09c)：sim_recruit override。進階技能成功率加成 (0.0 = 冇)
func _craft_rate_add(_ch: Dictionary, _skill: String) -> float:
	return 0.0


# 商才 hook (S09c)：sim_recruit override。買賣價乘數 {buy, sell}
func _companion_trade_mul(_ch: Dictionary) -> Dictionary:
	return {}


# 職業特技 hook (S09c-b, 22)：sim_recruit override。同伴喺附近 → 主公職業特技冷卻/消耗乘數 {cd, cost}
func _companion_class_skill_mul(_e: Dictionary) -> Dictionary:
	return {"cd": 1.0, "cost": 1.0}


# 友好特技「野性」: 玩家攻擊間隔縮放 hook (sim_war_beast 覆寫；預設原值)
func _atk_interval_scale(_e: Dictionary, base: int) -> int:
	return base


# 友好特技「聖體」: 每刻自動回復倍率 (sim_war_beast 覆寫；1.0 = 冇效果)
func _friend_regen_mult(_e: Dictionary) -> float:
	return 1.0


# 背包負重上限 (S04a)；bagCapBonus = 百寶袋/千歲袋等永久加成道具 (U16)；sim_war_beast 覆寫加上霸王熊「背負」加成
func _bag_cap(ch: Dictionary) -> int:
	return int(data.world.get("dropped", {}).get("capBagWeight", 1000)) + int(ch.get("bagCapBonus", 0))


func order_count(ch: Dictionary, item: int) -> int:
	return RulesShop.count_item(ch["bag"], item)


func _order_consume(ch: Dictionary, item: int) -> bool:
	return RulesShop.remove_item(ch["bag"], item, 1)


# (x,y) 附近搵一格空位 (一圈圈向外)
func _free_near(x: int, y: int) -> Vector2i:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and is_free(x + dx, y + dy):
					return Vector2i(x + dx, y + dy)
	return Vector2i(x, y)


func _near(e: Dictionary, x: int, y: int) -> bool:
	return RulesCombat.in_range(e["x"], e["y"], x, y, NEAR)


# 企喺邊個有 flag (stable/office/donation/repair…) 嘅設施隔籬 → facility key ("" = 唔喺)
func _fac_near(e: Dictionary, flag: String) -> String:
	for k in data.facilities:
		var f = data.facilities[k]
		if f is Dictionary and bool(f.get(flag, false)) and _near(e, int(f["x"]), int(f["y"])):
			return String(k)
	return ""


func _full_heal(ch: Dictionary) -> void:
	# 輔助石加成: 用有效上限 (Step 10, spec 02 §4)
	ch["hp"] = _eff_max_hp(ch)
	ch["mp"] = _eff_max_mp(ch)
	ch["sp"] = _eff_max_sp(ch)


# 死亡復活回一半【自訂】(spec 03 §4.3 第 3 步: 原版復活後唔滿，要訓覺/食)
func _half_heal(ch: Dictionary) -> void:
	ch["hp"] = maxi(1, MathX.js_round(_eff_max_hp(ch) / 2.0))
	ch["mp"] = maxi(0, MathX.js_round(_eff_max_mp(ch) / 2.0))
	ch["sp"] = maxi(0, MathX.js_round(_eff_max_sp(ch) / 2.0))


# ================= LLM 層 (S09d, spec 09 §5) =================
# 架構: sim 只發 `llm_request` 事件（含規則層砌好嘅 request body，冇 key），UI/客戶端傳送去
# OpenRouter 之後 call `cmd_llm_reply(req_id, text)` / `cmd_llm_summary(req_id, text)` 回填。
# 邏輯層測試用 mock 文字餵呢兩個 cmd，完全唔碰網絡。冇 enabled / 冇回覆 → 模板後備。
# key 只由 `LlmClient` 存本機（user://llm.cfg），sim 存檔只記 enabled/model（非機密）。

func _llm_cfg() -> Dictionary:
	return RulesLlm.cfg(data)


func _ensure_llm() -> void:
	if not state.has("llm") or not (state["llm"] is Dictionary):
		state["llm"] = {"enabled": false, "model": "", "used": {"day": -1, "calls": 0, "reflect": 0}, "lastError": ""}
	var l: Dictionary = state["llm"]
	if not l.has("enabled"):
		l["enabled"] = false
	if not l.has("model"):
		l["model"] = ""
	if not l.has("lastError"):
		l["lastError"] = ""
	if not l.has("cd") or not (l["cd"] is Dictionary):
		l["cd"] = {}
	var u = l.get("used", {})
	if not (u is Dictionary):
		u = {}
	if not (u as Dictionary).has("day"):
		(u as Dictionary)["day"] = -1
	if not (u as Dictionary).has("calls"):
		(u as Dictionary)["calls"] = 0
	if not (u as Dictionary).has("reflect"):
		(u as Dictionary)["reflect"] = 0
	l["used"] = u


func llm_enabled() -> bool:
	_ensure_llm()
	return bool(state["llm"]["enabled"])


func llm_model() -> String:
	_ensure_llm()
	var m := String(state["llm"].get("model", ""))
	return m if m != "" else String(_llm_cfg().get("model", ""))


# UI 設定: enabled / 模型名（key 唔經呢度）
func cmd_llm_config(enabled: bool, model: String) -> void:
	_ensure_llm()
	state["llm"]["enabled"] = enabled
	state["llm"]["model"] = model


func _llm_set_error(err: String) -> void:
	_ensure_llm()
	state["llm"]["lastError"] = err


# 砌一個 NPC talk 用嘅 ctx（mem 可空 = 未登用嘅 Tier1 武將）
func _llm_ctx(npc_name: String, ideo: String, mem: Dictionary, actor_e: Dictionary, actor_id: int) -> Dictionary:
	var actor_ch: Dictionary = actor_e.get("ch", {})
	var karma_tier := RulesKarma.tier(int(actor_ch.get("karma", 0))) if not actor_ch.is_empty() else 3
	var aff := NpcMemory.affinity(mem, actor_id) if not mem.is_empty() else 0
	var rk := ""
	var digest := ""
	if not mem.is_empty():
		var keys := NpcMemory.rumor_keys(mem)
		if not keys.is_empty():
			rk = String(NpcMemory.rumor_of(mem, String(keys[0])).get("kind", ""))
		digest = RulesLlm.template_summary(_llm_cfg(), mem)
	return {"actor_name": String(actor_e.get("name", "")), "npc_name": npc_name, "tier": 0,
		"ideology": ideo, "affinity": aff, "karma_tier": karma_tier, "rumor_kind": rk, "mem_digest": digest}


# 開一個 LLM 請求（kind = "talk"/"reflect"）；回傳 req id，0 = 唔開（未啟用/超預算）
# extra: {npcId, npcName, gid, x, y, actorId, pick, tier}
func _llm_offer(kind: String, ctx: Dictionary, extra: Dictionary) -> int:
	_ensure_llm()
	if not llm_enabled():
		return 0
	var c := _llm_cfg()
	state["llm"]["used"] = RulesLlm.roll_day(state["llm"]["used"], int(_clock()["day"]))   # 跨日重設預算
	var used: Dictionary = state["llm"]["used"]
	if not RulesLlm.budget_ok(c, used, kind):
		_llm_set_error("budget")
		return 0
	_llm_seq += 1
	var req_id := _llm_seq
	var key := ""                                   # key 由客戶端加，sim 唔碰
	var req := RulesLlm.build_request(c, llm_model(), ctx, key) if kind != "reflect" else RulesLlm.build_reflect_request(c, llm_model(), ctx, key)
	_llm_pending[req_id] = {"kind": kind, "ctx": ctx, "extra": extra}
	if kind == "reflect":
		used["reflect"] = int(used.get("reflect", 0)) + 1
	else:
		used["calls"] = int(used.get("calls", 0)) + 1
	_llm_set_error("")
	_emit({"k": "llm_request", "reqId": req_id, "kind": kind, "tier": int(extra.get("tier", 0)),
		"url": String(req.get("url", "")), "headers": req.get("headers", {}), "body": req.get("body", {}),
		"npcId": int(extra.get("npcId", 0)), "gid": int(extra.get("gid", 0)),
		"x": int(extra.get("x", 0)), "y": int(extra.get("y", 0))})
	return req_id


# sim 側打開一個 NPC 對話 LLM 請求（sim_recruit / sim_char 用）。true = 已排隊（唔好再出模板句）
func _llm_talk(npc_e: Dictionary, npc_name: String, ideo: String, gid: int, x: int, y: int, actor_id: int) -> bool:
	if not llm_enabled():
		return false
	var actor_e := ent(actor_id)
	if actor_e.is_empty():
		return false
	var mem: Dictionary = npc_e.get("mem", {}) if not npc_e.is_empty() else {}
	var npc_id := int(npc_e.get("id", 0))
	var cd_key := ("g:%d" % gid) if gid > 0 else ("e:%d" % npc_id)
	var last := int((state["llm"].get("cd", {}) as Dictionary).get(cd_key, -99999))
	if not RulesLlm.cooldown_ok(_llm_cfg(), last, tick):
		return false
	var tier := 1 if (gid > 0 and npc_e.is_empty()) else (1 if String(npc_e.get("kind", "")) == "gen" else 2)
	var roll := rng.below(1000)
	if not RulesLlm.tier_uses_llm(_llm_cfg(), tier, roll):
		return false
	var ctx := _llm_ctx(npc_name, ideo, mem, actor_e, actor_id)
	ctx["tier"] = tier
	ctx["npc_id"] = npc_id
	var extra := {"npcId": npc_id, "npcName": npc_name, "gid": gid, "x": x, "y": y,
		"actorId": actor_id, "pick": rng.below(4), "tier": tier}
	var rid := _llm_offer("talk", ctx, extra)
	if rid == 0:
		return false
	_llm_mark_cd(cd_key)
	return true


func _llm_mark_cd(cd_key: String) -> void:
	var l: Dictionary = state["llm"]
	if not l.has("cd") or not (l["cd"] is Dictionary):
		l["cd"] = {}
	l["cd"][cd_key] = tick


# 回填 LLM 對話回應。parsed 唔到 → 用模板後備；任何數值改動只由 RulesLlm.effect_of 決定。
func cmd_llm_reply(req_id: int, text: String) -> bool:
	var p: Dictionary = _llm_pending.get(req_id, {})
	if p.is_empty() or String(p.get("kind", "")) != "talk":
		return false
	_llm_pending.erase(req_id)
	var c := _llm_cfg()
	var extra: Dictionary = p.get("extra", {})
	var ctx: Dictionary = p.get("ctx", {})
	var parsed := RulesLlm.parse_response(c, text)
	if parsed.is_empty():
		parsed = NpcBrainLlm.decide(ctx, int(extra.get("pick", 0)))     # 解析唔到 → 模板後備
	var action := String(parsed["action"])
	var line := String(parsed["line"])
	var eff := RulesLlm.effect_of(action)                               # 唯一數值來源
	var npc_id := int(extra.get("npcId", 0))
	var actor_id := int(extra.get("actorId", 0))
	var npc_e := ent(npc_id)
	if not npc_e.is_empty() and npc_e.has("mem") and int(eff["affinity"]) != 0:
		NpcMemory.witness(npc_e["mem"], actor_id, "llm_" + action, tick, int(eff["affinity"]))
	_emit({"k": "npc_say", "id": npc_id, "name": String(extra.get("npcName", "")), "text": line,
		"action": action, "x": int(extra.get("x", 0)), "y": int(extra.get("y", 0)),
		"general": int(extra.get("gid", 0)), "llm": true})
	_emit({"k": "llm_action", "reqId": req_id, "action": action, "accept": bool(eff["accept"]),
		"hint": bool(eff["hint"]), "rumor": bool(eff["rumor"]), "refuse": bool(eff["refuse"]),
		"warn": bool(eff["warn"]), "ignore": bool(eff["ignore"])})
	return true


# 回填 LLM 反思摘要 → mem.summary / mem.goal
func cmd_llm_summary(req_id: int, text: String) -> bool:
	var p: Dictionary = _llm_pending.get(req_id, {})
	if p.is_empty() or String(p.get("kind", "")) != "reflect":
		return false
	_llm_pending.erase(req_id)
	var extra: Dictionary = p.get("extra", {})
	var npc_e := ent(int(extra.get("npcId", 0)))
	if npc_e.is_empty() or not npc_e.has("mem"):
		return false
	var s := RulesLlm.parse_summary(_llm_cfg(), text)
	if s == "":
		return false
	NpcMemory.set_summary(npc_e["mem"], s, RulesLlm.goal_of(npc_e["mem"]), int(_clock()["day"]))
	return true


# read-model
func llm_view() -> Dictionary:
	_ensure_llm()
	var c := _llm_cfg()
	var used: Dictionary = state["llm"]["used"]
	return {"enabled": llm_enabled(), "model": llm_model(),
		"actions": RulesLlm.actions(c), "used": used,
		"budgetPerDay": RulesLlm.per_day(c), "reflectPerDay": RulesLlm.reflect_per_day(c),
		"pending": _llm_pending.size(), "lastError": String(state["llm"].get("lastError", ""))}


# 每日反思批次 (子時): 先寫規則模板摘要（決定性、離線一定有），LLM 有回應再覆蓋。
# 摘要/目標純屬 read-model 資料，唔改任何遊戲數值。
func _llm_reflect_daily(day: int) -> void:
	_ensure_llm()
	var c := _llm_cfg()
	var actor_e := ent(int(state["player_id"]))
	var ids: Array = ents.keys()
	ids.sort()
	for id in ids:
		var e := ent(int(id))
		if e.is_empty() or not e.has("mem"):
			continue
		var mem: Dictionary = e["mem"]
		if not RulesLlm.reflect_due(c, mem, day):
			continue
		NpcMemory.set_summary(mem, RulesLlm.template_summary(c, mem), RulesLlm.goal_of(mem), day)
		if not llm_enabled() or actor_e.is_empty():
			continue
		var tier := 1 if String(e.get("kind", "")) == "gen" else 2
		if not RulesLlm.tier_uses_llm(c, tier, rng.below(1000)):
			continue
		var ch: Dictionary = e.get("ch", {})
		var ctx := _llm_ctx(String(e.get("name", "")), String(ch.get("ideology", "")), mem, actor_e, int(state["player_id"]))
		ctx["tier"] = tier
		ctx["npc_id"] = int(id)
		_llm_offer("reflect", ctx, {"npcId": int(id), "day": day, "tier": tier})
