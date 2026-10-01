class_name OrigMap
extends RefCounted
# 原版地圖視覺層 (tools/import_orig_maps.py 生成 data/orig_maps/<key>.json + assets_orig/maps/<key>/)。
# 邏輯層仍係 16px 格 (maps/<id>.txt)；呢度只負責畫：48px 地形 + 物件 sprite (按底邊 y 排序，畀角色夾插遮擋)。
# 冇資料/冇圖 → load_map 回 null，main 用返 MapArt。

const ROOT := "res://assets_orig/maps/"
const DATA := "res://data/orig_maps/"
static var _maps: Dictionary = {}        # key -> OrigMap
static var _imgs: Dictionary = {}        # path -> Texture2D|null

var key := ""
var W := 0
var H := 0
var cols := 0
var rows := 0
var tiles := PackedInt32Array()
var atlas: Texture2D = null
var atlas_cols := 32
var walk := PackedByteArray()            # 16px 行走層 (1=擋)
var gw := 0
var gh := 0
var objs: Array = []                     # {n,x,y,bot,tex}，已按 bot 排序
var _draw_objs: Array = []               # 今幀畫得嘅物件 (bot 排序)
var _next := 0

static func load_map(k: String) -> OrigMap:
	if _maps.has(k):
		return _maps[k]
	var m: OrigMap = null
	var jp := DATA + k + ".json"
	if FileAccess.file_exists(jp):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(jp))
		if v is Dictionary:
			m = OrigMap.new()
			m._init_from(k, v)
			if m.atlas == null:
				m = null
	_maps[k] = m
	return m

static func _tex(path: String) -> Texture2D:
	if _imgs.has(path):
		return _imgs[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			t = ImageTexture.create_from_image(img)
	_imgs[path] = t
	return t

func _init_from(k: String, d: Dictionary) -> void:
	key = k
	W = int(d["W"])
	H = int(d["H"])
	cols = int(d["cols"])
	rows = int(d["rows"])
	atlas_cols = int(d.get("atlas_cols", 32))
	var tl: Array = d["tiles"]
	tiles.resize(tl.size())
	for i in tl.size():
		tiles[i] = int(tl[i])
	atlas = _tex(ROOT + k + "/atlas.png")
	var wd: Dictionary = d.get("walk", {})
	if not wd.is_empty():
		gw = int(wd["w"])
		gh = int(wd["h"])
		walk = Marshalls.base64_to_raw(String(wd["z"])).decompress(gw * gh, FileAccess.COMPRESSION_DEFLATE)
	for o in d["objects"]:
		var t := _tex(ROOT + k + "/obj/" + str(o["n"]) + ".png")
		if t == null:
			continue
		objs.append({"x": int(o["x"]), "y": int(o["y"]), "bot": int(o["y"]) + t.get_height(), "tex": t, "floor": bool(o.get("floor", false)) or str(o["n"]).begins_with("up6") or _is_floor(int(o["x"]), int(o["y"]), t)})   # up6xx = 96px 石帶/鋪面，永遠貼地
	objs.sort_custom(func(a, b): return int(a["bot"]) < int(b["bot"]))

# 貼地物件 (路面/地毯/影子等)：佔嘅格冇一格係擋 → 永遠畫喺角色下面，唔好遮人
func _is_floor(x: int, y: int, t: Texture2D) -> bool:
	if walk.size() != gw * gh or gw == 0:
		return false
	var c0 := maxi(0, x / 16)
	var c1 := mini(gw - 1, (x + t.get_width() - 1) / 16)
	var r0 := maxi(0, y / 16)
	var r1 := mini(gh - 1, (y + t.get_height() - 1) / 16)
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if walk[r * gw + c] != 0:
				return false
	return true

# 地形：只畫畫面內嗰啲格。origin = 地圖左上角嘅畫布座標 (= 地圖 ox/oy*TILE - cam)
func draw_terrain(ci: CanvasItem, origin: Vector2, vs: Vector2, mod: Color) -> void:
	var c0 := maxi(0, int(floor(-origin.x / 48.0)))
	var r0 := maxi(0, int(floor(-origin.y / 48.0)))
	var c1 := mini(cols - 1, int(floor((vs.x - origin.x) / 48.0)))
	var r1 := mini(rows - 1, int(floor((vs.y - origin.y) / 48.0)))
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var t := tiles[r * cols + c]
			var src := Rect2((t % atlas_cols) * 48, (t / atlas_cols) * 48, 48, 48)
			ci.draw_texture_rect_region(atlas, Rect2(origin + Vector2(c * 48, r * 48), Vector2(48, 48)), src, mod)

# 物件：先 begin() 篩出畫面內嘅，然後角色逐個 flush_upto(腳底 y) 再畫，最後 flush_all()
func begin(vs: Vector2, origin: Vector2, mod: Color = Color.WHITE, ci: CanvasItem = null) -> void:
	_draw_objs.clear()
	_next = 0
	for o in objs:
		var p: Vector2 = origin + Vector2(int(o["x"]), int(o["y"]))
		var t: Texture2D = o["tex"]
		if p.x > vs.x or p.y > vs.y or p.x + t.get_width() < 0 or p.y + t.get_height() < 0:
			continue
		if bool(o["floor"]):
			_draw_one(ci, origin, o, mod)          # 貼地物件：喺角色前面先畫
		else:
			_draw_objs.append(o)

func flush_upto(ci: CanvasItem, origin: Vector2, foot_y: float, mod: Color) -> void:
	while _next < _draw_objs.size() and float(_draw_objs[_next]["bot"]) <= foot_y:
		_draw_one(ci, origin, _draw_objs[_next], mod)
		_next += 1

func flush_all(ci: CanvasItem, origin: Vector2, mod: Color) -> void:
	while _next < _draw_objs.size():
		_draw_one(ci, origin, _draw_objs[_next], mod)
		_next += 1

func _draw_one(ci: CanvasItem, origin: Vector2, o: Dictionary, mod: Color) -> void:
	ci.draw_texture(o["tex"], origin + Vector2(int(o["x"]), int(o["y"])), mod)
