class_name MapArt
extends RefCounted
# 地圖貼圖 (spec 12 §6): 每張地圖預渲染一張 Image (每格 TILE px)，程序化像素細節 (種子 = 座標 → 每次一樣)。
# 佔位美術，成品前換正式 tileset。main._draw 每幀只畫一張貼圖，唔再逐格 draw_rect。
# 小地圖: 每格 1px 顏色。兩樣都按 map id 快取。

static var _tex: Dictionary = {}      # map id -> ImageTexture
static var _mini: Dictionary = {}     # map id -> ImageTexture

const GRASS := Color(0.30, 0.50, 0.24)
const GRASS2 := Color(0.26, 0.45, 0.21)
const ROAD := Color(0.63, 0.52, 0.35)
const PAVE := Color(0.60, 0.57, 0.50)
const YARD := Color(0.56, 0.46, 0.32)
const CAVE_FLOOR := Color(0.30, 0.27, 0.25)
const FARM := Color(0.47, 0.36, 0.22)
const CROP := Color(0.46, 0.60, 0.22)
const PLANK := Color(0.52, 0.35, 0.18)
const WALL := Color(0.46, 0.44, 0.41)
const ROOF := Color(0.27, 0.29, 0.35)
const PLASTER := Color(0.84, 0.79, 0.68)
const PILLAR := Color(0.55, 0.16, 0.12)
const LEAF := Color(0.13, 0.33, 0.14)
const LEAF_HI := Color(0.22, 0.46, 0.20)
const ROCK := Color(0.47, 0.42, 0.36)
const CAVE_ROCK := Color(0.16, 0.14, 0.15)
const WATER := Color(0.19, 0.39, 0.62)
const WATER_HI := Color(0.45, 0.65, 0.85)


static func texture(data: GameData, md: Dictionary, tile: int) -> ImageTexture:
	var id := String(md["id"])
	if not _tex.has(id):
		_tex[id] = ImageTexture.create_from_image(_render(data, md, tile))
	return _tex[id]


static func minimap(data: GameData, md: Dictionary) -> ImageTexture:
	var id := String(md["id"])
	if not _mini.has(id):
		var w := int(md["w"])
		var h := int(md["h"])
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		var cave := String(md.get("kind", "")) == "cave"
		for y in h:
			for x in w:
				img.set_pixel(x, y, _mini_color(_tile(data, md, x, y), cave))
		_mini[id] = ImageTexture.create_from_image(img)
	return _mini[id]


static func _mini_color(c: String, cave: bool) -> Color:
	match c:
		".", ",": return GRASS
		"=": return ROAD
		":", "+": return PAVE
		"_": return CAVE_FLOOR.lightened(0.15) if cave else YARD
		"%": return CROP
		"b": return PLANK
		"#": return WALL.darkened(0.2)
		"H": return ROOF.lightened(0.1)
		"T": return LEAF
		"^": return CAVE_ROCK if cave else ROCK.darkened(0.2)
		"~": return WATER
	return Color.BLACK


static func _tile(data: GameData, md: Dictionary, x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= int(md["w"]) or y >= int(md["h"]):
		return " "
	var c := data.tiles[(int(md["oy"]) + y) * GameData.WORLD_W + int(md["ox"]) + x]
	return String.chr(c) if c > 0 else " "


static func _hash(x: int, y: int, k: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ (k * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


static func _render(data: GameData, md: Dictionary, t: int) -> Image:
	var w := int(md["w"])
	var h := int(md["h"])
	var img := Image.create(w * t, h * t, false, Image.FORMAT_RGBA8)
	var cave := String(md.get("kind", "")) == "cave"
	var palace := Rect2i()
	for a in md.get("areas", []):
		if String(a["name"]).contains("皇城"):
			palace = Rect2i(int(a["x0"]) - int(md["ox"]), int(a["y0"]) - int(md["oy"]), int(a["x1"]) - int(a["x0"]) + 1, int(a["y1"]) - int(a["y0"]) + 1)
	for y in h:
		for x in w:
			var c := _tile(data, md, x, y)
			var px := x * t
			var py := y * t
			var r := _hash(x, y, 1)
			match c:
				".":
					_grass(img, px, py, t, r)
				",":
					_grass(img, px, py, t, r)
					_blob(img, px + 2 + r % 6, py + 5 + (r >> 4) % 5, 5, LEAF_HI)
					_blob(img, px + 7 + (r >> 8) % 5, py + 3 + (r >> 12) % 6, 4, LEAF_HI.darkened(0.15))
					if r % 3 == 0:
						img.set_pixel(px + 4 + (r >> 5) % 8, py + 3 + (r >> 9) % 9, Color(0.95, 0.85, 0.3) if r % 2 == 0 else Color(0.95, 0.95, 0.95))
				"=":
					img.fill_rect(Rect2i(px, py, t, t), ROAD)
					_speckle(img, px, py, t, r, ROAD.darkened(0.12), 6)
					_edge(img, data, md, x, y, px, py, t, "=b+", GRASS.darkened(0.1))
				":":
					img.fill_rect(Rect2i(px, py, t, t), PAVE)
					var off := (y % 2) * (t / 2)
					img.fill_rect(Rect2i(px, py + t - 1, t, 1), PAVE.darkened(0.18))
					img.fill_rect(Rect2i(px + (off + t / 2) % t, py, 1, t), PAVE.darkened(0.18))
					_speckle(img, px, py, t, r, PAVE.lightened(0.08), 3)
				"+":
					img.fill_rect(Rect2i(px, py, t, t), PAVE.darkened(0.12))
					img.fill_rect(Rect2i(px, py + t / 2, t, 1), PAVE.darkened(0.3))
				"_":
					img.fill_rect(Rect2i(px, py, t, t), CAVE_FLOOR if cave else YARD)
					_speckle(img, px, py, t, r, (CAVE_FLOOR if cave else YARD).darkened(0.18), 5)
				"%":
					img.fill_rect(Rect2i(px, py, t, t), FARM)
					for k in range(2, t, 4):
						img.fill_rect(Rect2i(px, py + k, t, 2), CROP if (y + x / 6) % 3 != 0 else CROP.darkened(0.15))
				"b":
					img.fill_rect(Rect2i(px, py, t, t), PLANK)
					var vertical := _tile(data, md, x, y - 1) in ["b", "="] or _tile(data, md, x, y + 1) in ["b", "="]
					for k in range(0, t, 4):
						if vertical:
							img.fill_rect(Rect2i(px, py + k, t, 1), PLANK.darkened(0.3))
						else:
							img.fill_rect(Rect2i(px + k, py, 1, t), PLANK.darkened(0.3))
				"#":
					img.fill_rect(Rect2i(px, py, t, t), WALL)
					for row in range(0, t, 4):
						img.fill_rect(Rect2i(px, py + row, t, 1), WALL.darkened(0.25))
						var o := 0 if (row / 4 + y) % 2 == 0 else t / 2
						img.fill_rect(Rect2i(px + o, py + row, 1, 4), WALL.darkened(0.25))
					if _tile(data, md, x, y - 1) != "#":
						img.fill_rect(Rect2i(px, py, t, 2), WALL.lightened(0.25))
				"H":
					var in_palace := palace.has_point(Vector2i(x, y))
					var front := _tile(data, md, x, y + 1) != "H"
					var top := _tile(data, md, x, y - 1) != "H"
					var roof := Color(0.62, 0.45, 0.14) if in_palace else ROOF
					if front:
						img.fill_rect(Rect2i(px, py, t, t), PILLAR if in_palace else PLASTER)
						img.fill_rect(Rect2i(px, py, t, 4), roof.darkened(0.3))
						if (x + y) % 3 == 0:
							img.fill_rect(Rect2i(px + 4, py + 7, t - 8, 6), Color(0.25, 0.18, 0.12))
						img.fill_rect(Rect2i(px, py + t - 2, t, 2), Color(0.35, 0.3, 0.25))
					else:
						img.fill_rect(Rect2i(px, py, t, t), roof)
						for k in range(1, t, 3):
							img.fill_rect(Rect2i(px, py + k, t, 1), roof.darkened(0.2))
						if top:
							img.fill_rect(Rect2i(px, py, t, 2), roof.lightened(0.3))
				"T":
					_grass(img, px, py, t, r)
					img.fill_rect(Rect2i(px + t / 2 - 1, py + t - 5, 3, 5), Color(0.35, 0.22, 0.12))
					_blob(img, px + t / 2, py + t / 2 - 1, t / 2 + 1, LEAF)
					_blob(img, px + t / 2 - 2, py + t / 2 - 3, t / 4, LEAF_HI)
				"^":
					if cave:
						img.fill_rect(Rect2i(px, py, t, t), CAVE_ROCK)
						_speckle(img, px, py, t, r, CAVE_ROCK.lightened(0.12), 6)
						if _tile(data, md, x, y + 1) == "_":
							img.fill_rect(Rect2i(px, py + t - 3, t, 3), CAVE_ROCK.lightened(0.25))
					else:
						_grass(img, px, py, t, r)
						for k in t:
							var half := int((t - k) / 2.0 * 0.9)
							img.fill_rect(Rect2i(px + t / 2 - half, py + k, half, 1), ROCK)
							img.fill_rect(Rect2i(px + t / 2, py + k, half, 1), ROCK.darkened(0.25))
				"~":
					img.fill_rect(Rect2i(px, py, t, t), WATER)
					if r % 3 != 0:
						img.fill_rect(Rect2i(px + r % (t - 5), py + 3 + (r >> 6) % (t - 6), 4, 1), WATER_HI)
					_edge(img, data, md, x, y, px, py, t, "~b", Color(0.72, 0.66, 0.46))
				_:
					img.fill_rect(Rect2i(px, py, t, t), Color.BLACK)
	return img


static func _grass(img: Image, px: int, py: int, t: int, r: int) -> void:
	img.fill_rect(Rect2i(px, py, t, t), GRASS if r % 5 != 0 else GRASS2)
	for k in 4:
		var hh := _hash(px, py, k + 7)
		img.set_pixel(px + hh % t, py + (hh >> 8) % t, GRASS.lightened(0.18) if k % 2 == 0 else GRASS.darkened(0.15))


static func _speckle(img: Image, px: int, py: int, t: int, r: int, col: Color, n: int) -> void:
	for k in n:
		var hh := _hash(px + k, py, r & 0xff)
		img.set_pixel(px + hh % t, py + (hh >> 8) % t, col)


static func _blob(img: Image, cx: int, cy: int, rad: int, col: Color) -> void:
	for yy in range(-rad, rad + 1):
		for xx in range(-rad, rad + 1):
			if xx * xx + yy * yy <= rad * rad:
				var x := cx + xx
				var y := cy + yy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, col)


# 同隔籬唔同類嘅邊畫一條細邊 (路邊/河岸)
static func _edge(img: Image, data: GameData, md: Dictionary, x: int, y: int, px: int, py: int, t: int, same: String, col: Color) -> void:
	if not same.contains(_tile(data, md, x, y - 1)):
		img.fill_rect(Rect2i(px, py, t, 1), col)
	if not same.contains(_tile(data, md, x, y + 1)):
		img.fill_rect(Rect2i(px, py + t - 1, t, 1), col)
	if not same.contains(_tile(data, md, x - 1, y)):
		img.fill_rect(Rect2i(px, py, 1, t), col)
	if not same.contains(_tile(data, md, x + 1, y)):
		img.fill_rect(Rect2i(px + t - 1, py, 1, t), col)
