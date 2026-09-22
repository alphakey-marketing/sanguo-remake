class_name GameData
extends RefCounted
# 載入 res://data/*.json。數值表喺 data/，規則喺 rules/

const NEWBIE_LEVEL := 5

var classes: Dictionary = {}     # id(String) -> def
var monsters: Dictionary = {}    # id(int) -> def
var spawns: Array = []
var starter: Dictionary = {}
var weapons: Dictionary = {}     # item id -> {power, hit}  武器強度(effect 99) / 命中率(effect 13)
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
var travel_points: Array = []     # 傳送點 (data/zones.json)

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
		for e in it.get("effects", []):
			if int(e["type"]) == 99 and p == null:
				p = float(e["value"])
			elif int(e["type"]) == 13 and h == null:
				h = float(e["value"])
		if p != null:
			g.weapons[id] = {"power": p, "hit": h if h != null else 45.0}
	_cache = g
	return g
