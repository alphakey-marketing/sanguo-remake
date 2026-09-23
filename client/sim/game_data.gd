class_name GameData
extends RefCounted
# 載入 res://data/*.json。數值表喺 data/，規則喺 rules/

const NEWBIE_LEVEL := 5

var classes: Dictionary = {}     # id(String) -> def
var monsters: Dictionary = {}    # id(int) -> def
var spawns: Array = []
var starter: Dictionary = {}
var weapons: Dictionary = {}     # item id -> {power, hit}  武器強度(effect 99) / 命中率(effect 13)
var heals: Dictionary = {}       # item id -> {hp, mp}  回復生命力(effect 14) / 回復靈力(effect 16)，供 cmd_use_item
var prices: Dictionary = {}      # item id -> price
var item_ids: Dictionary = {}    # item id -> true
var names: Dictionary = {}       # item id -> 名
var cats: Dictionary = {}        # item id -> cat (物品分類, 市場用)
var inn: Dictionary = {}
var shops: Array = []
var world: Dictionary = {}        # clock/cities/market/disasters (data/world.json)
var facilities: Dictionary = {}   # 練兵場/私塾/寺廟 (data/facilities.json)
var cities: Dictionary = {}       # city id -> def (由 world.json)
var zones: Array = []             # 安全區/戰鬥區 (data/zones.json)
var walls: Array = []             # 地形阻擋格 rect [x0,y0,x1,y1] (data/zones.json, Step 11)
var travel_points: Array = []     # 傳送點 (data/zones.json)
var work: Dictionary = {}         # 工作技能 (data/work.json.skills, Step 7.1)
var work_meta: Dictionary = {}    # 工作技能雜項 (data/work.json.toolDurability)
var quiz: Array = []              # 理念測驗題庫 (data/quiz.json, Step 7.5)
var face_parts: Dictionary = {}   # 臉譜 8 部位款式數 (data/face.json, Step 7.5)
var quests: Array = []            # 任務定義 (data/quests.json, Step 8)
var quest_npcs: Dictionary = {}   # quest npc id -> def (data/quest_npcs.json, Step 8)
var quest_npc_list: Array = []    # 同上，array 版 (順序)
var spells: Array = []            # 術書定義 (data/spells.json, Step 9)
var spell_by_item: Dictionary = {}  # item id -> spell def
var spell_by_id: Dictionary = {}  # spell id -> def
var jewels: Dictionary = {}      # 寶石目錄 (data/jewels.json, Step 10): stones/special/support/fusable
var jewel_by_item: Dictionary = {}  # item id -> jewel def (全種類)
var ultimates: Array = []        # 絕招定義 (data/ultimates.json, Step 10, spec 02 §5)
var ult_by_id: Dictionary = {}   # ult id -> def

static var _cache: GameData


static func _read(path: String) -> Variant:
	var txt := FileAccess.get_file_as_string(path)
	var v: Variant = JSON.parse_string(txt)
	assert(v != null, "JSON 讀取失敗: " + path)
	return v


static func load_all() -> GameData:
	if _cache != null:
		return _cache
	var g := GameData.new()
	var c: Dictionary = _read("res://data/classes.json")
	var m: Dictionary = _read("res://data/monsters.json")
	var sh: Dictionary = _read("res://data/shops.json")
	var items: Array = _read("res://data/items.json")
	g.world = _read("res://data/world.json")
	g.facilities = _read("res://data/facilities.json")
	var zn: Dictionary = _read("res://data/zones.json")
	g.zones = zn["zones"]
	g.travel_points = zn["travel_points"]
	g.walls = zn.get("walls", [])
	var wk: Dictionary = _read("res://data/work.json")
	g.work = wk["skills"]
	g.work_meta = {"toolDurability": wk["toolDurability"]}
	var qz: Dictionary = _read("res://data/quiz.json")
	g.quiz = qz["questions"]
	var fc: Dictionary = _read("res://data/face.json")
	g.face_parts = fc["parts"]
	var qn: Dictionary = _read("res://data/quest_npcs.json")
	for x in qn["npcs"]:
		g.quest_npcs[String(x["id"])] = x
		g.quest_npc_list.append(x)
	var qu: Dictionary = _read("res://data/quests.json")
	g.quests = qu["quests"]
	var sp: Dictionary = _read("res://data/spells.json")
	g.spells = sp["spells"]
	for x in g.spells:
		g.spell_by_id[String(x["id"])] = x
		g.spell_by_item[int(x["item"])] = x
	var jw: Dictionary = _read("res://data/jewels.json")
	g.jewels = jw
	for cat in ["stones", "special", "support", "fusable"]:
		for j in jw.get(cat, []):
			j["kind"] = "stone" if cat == "stones" else "special" if cat == "special" else "support" if cat == "support" else "fusable"
			g.jewel_by_item[int(j["id"])] = j
	var ul: Dictionary = _read("res://data/ultimates.json")
	g.ultimates = ul["ultimates"]
	for u in g.ultimates:
		g.ult_by_id[String(u["id"])] = u
	for x in c["classes"]:
		g.classes[String(x["id"])] = x
	for x in m["monsters"]:
		g.monsters[int(x["id"])] = x
	g.spawns = m["spawns"]
	g.starter = c["starter"]
	g.inn = sh["inn"]
	g.shops = sh["shops"]
	for c_ in g.world["cities"]:
		g.cities[c_.id] = c_
	for it in items:
		var id := int(it["id"])
		g.item_ids[id] = true
		g.names[id] = str(it.get("name", id))
		g.prices[id] = float(it.get("price", 0))
		g.cats[id] = int(it.get("cat", 0))
		var p = null
		var h = null
		var heal_hp := 0
		var heal_mp := 0
		var heal_sp := 0
		for e in it.get("effects", []):
			var et := int(e["type"])
			if et == 99 and p == null:
				p = float(e["value"])
			elif et == 13 and h == null:
				h = float(e["value"])
			elif et == 14:
				heal_hp += int(e["value"])
			elif et == 16:
				heal_mp += int(e["value"])
			elif et in [73, 74, 75]:    # 【自訂】73/74/75 = 戰騎藥水系 (紅/藍/綠藥水): value × 100 固定回復 (I=300, II=200, III=100)
				var v := int(e["value"]) * 100
				if et == 73:
					heal_hp += v
				elif et == 74:
					heal_mp += v
				else:
					heal_sp += v
		if p != null:
			g.weapons[id] = {"power": p, "hit": h if h != null else 45.0}
		if heal_hp > 0 or heal_mp > 0 or heal_sp > 0:
			g.heals[id] = {"hp": heal_hp, "mp": heal_mp, "sp": heal_sp}
	_cache = g
	return g
