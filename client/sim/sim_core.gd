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
const PATH_CAP := 6000                                 # cmd_move A* 節點上限 (spec 12 §3)
const CHASE_CAP := 800                                 # 追擊 A* 節點上限
const FACE_COUNT := 12                                 # 頭像款數 (UI 佔位頭像 face_0..11)

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


func _spawn_actor(ename: String, kind: String, class_id: String = "yishi") -> Dictionary:
	var sp: Array = _home_map().get("spawn", [int(data.inn["x"]) - 2, int(data.inn["y"]) - 2, int(data.inn["x"]) + 2, int(data.inn["y"]) + 2])
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
		if rng.next() < float(data.world["bots"]["criminalPct"]):   # S03a: 部分居民係紅名(殺人魔)「殺人魔 NPC」
			e["ch"]["criminal"] = true
		state["bots"].append(int(e["id"]))


func init_mobs() -> void:
	for sp in data.spawns:
		if sp.get("night", false):
			continue                    # 夜怪由 _sync_night_spawns 處理
		for i in int(sp["count"]):
			_spawn_mob(int(sp["monster"]), String(sp.get("zone", DEFAULT_ZONE)))


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
	var d: Dictionary = data.mob_def(def_id)
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
