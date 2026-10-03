class_name AssetLib
extends RefCounted
# 原版素材查詢 (tools/import_orig_assets.py 生成 data/asset_index.json + assets_orig/)。
# 冇索引/冇檔一律回 null，呼叫方自己 fallback (色塊/placeholder)，所以素材唔齊都唔會壞。

const INDEX_PATH := "res://data/asset_index.json"
const ROOT := "res://assets_orig/"

static var _index: Dictionary = {}
static var _loaded := false
static var _cache: Dictionary = {}

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(INDEX_PATH):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if v is Dictionary:
		_index = v

static func has(set_name: String, key: Variant) -> bool:
	_ensure()
	var tab: Variant = _index.get(set_name, {})
	return tab is Dictionary and (tab as Dictionary).has(str(key)) and _tex(set_name, key) != null

static func _tex(set_name: String, key: Variant) -> Texture2D:
	_ensure()
	var ck := "%s/%s" % [set_name, str(key)]
	if _cache.has(ck):
		return _cache[ck]
	var tex: Texture2D = null
	var tab: Variant = _index.get(set_name, {})
	if tab is Dictionary and (tab as Dictionary).has(str(key)):
		var p: String = ROOT + str((tab as Dictionary)[str(key)])
		if ResourceLoader.exists(p):
			tex = load(p) as Texture2D
		elif FileAccess.file_exists(p):            # 未經編輯器 import 都讀得
			var img := Image.load_from_file(p)
			if img != null:
				tex = ImageTexture.create_from_image(img)
	_cache[ck] = tex
	return tex

static func item_icon(item_id: int, large := false) -> Texture2D:
	return _tex("items_l" if large else "items", item_id)

static func face(key: Variant) -> Texture2D:
	return _tex("faces", key)

# 名 → 頭像 (武將/NPC 有原版頭像先有；冇就 null，呼叫方 fallback)
static func face_by_name(npc_name: String) -> Texture2D:
	_ensure()
	var m: Variant = _index.get("faces_by_name", {})
	if m is Dictionary and (m as Dictionary).has(npc_name):
		return face(str((m as Dictionary)[npc_name]).get_file().get_basename())
	return null


# 怪物動畫 sheet: act = "A" 攻擊 / "S" 站立 / "W" 行走；8 列(方向 N,NE,E,SE,S,SW,W,NW 順時針) x 8 欄(幀)。冇圖 = null
static func mon_sheet(mob_def: int, act: String) -> Texture2D:
	var t := _tex("mon_" + act, mob_def)
	if t == null:
		var al: Dictionary = _alias(mob_def)
		if al.has("actor"):
			return _tex("actor_" + act, int(al["actor"]))
		if al.has("mon"):
			return _tex("mon_" + act, int(al["mon"]))
	return t


# 冇原版圖嘅任務怪借圖 (data/mon_alias.json)
static var _alias_tab: Dictionary = {}
static var _alias_loaded := false
static func _alias(mob_def: int) -> Dictionary:
	if not _alias_loaded:
		_alias_loaded = true
		var f := FileAccess.open("res://data/mon_alias.json", FileAccess.READ)
		if f != null:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_alias_tab = (v as Dictionary).get("alias", {})
	return _alias_tab.get(str(mob_def), {})


# 借圖怪染色 (importer BORROW 表)；原版圖或冇登記 = 白色 (唔染)
static func mon_tint(mob_def: int) -> Color:
	_ensure()
	var t: Variant = _index.get("_mon_tint", {})
	if t is Dictionary and (t as Dictionary).has(str(mob_def)):
		return Color.html(str((t as Dictionary)[str(mob_def)]))
	var al := _alias(mob_def)
	if al.has("tint"):
		return Color.html(str(al["tint"]))
	return Color.WHITE


# 人形 sprite (NPC/居民/武將/玩家): sheet 格式同怪物。sid = 原版 sprite id
# 座騎 sheet (8x8, row4 面向鏡頭); key = 馬種 id
static func mount_sheet(breed: String) -> Texture2D:
	return _tex("mount_S", breed)


# 玩家分層 sheet: b=職業 1~6, c=動作 (1 走 2 攻), kind b/w/a/h
static func player_layer(b: int, c: int, kind: String, style: int) -> Texture2D:
	return _tex("player_layers", "%d/%d/%s/%d" % [b, c, kind, style])


# 臉譜 hair 款 1~3 → 分層 sprite 髮層款 (h 0~6 入面裸髮款 1/3/6，其餘係頭盔)
const HAIR_STYLE := [1, 3, 6]
# 臉譜「臉型組」1~11 → Pic_Face 組碼 (男 5 + 女 6)
const FACE_SETS := ["b02", "b03", "b04", "b05", "b06", "g01", "g02", "g03", "g04", "g05", "g06"]


static func hair_style(face: Dictionary) -> int:
	return int(HAIR_STYLE[clampi(int(face.get("hair", 1)), 1, HAIR_STYLE.size()) - 1])


# 臉譜疊層 (72x80，由底到頂: 背景/頸/臉型/眉眼/髮)；缺圖跳過
static func face_layers(face: Dictionary) -> Array:
	var grp: String = FACE_SETS[clampi(int(face.get("set", 1)), 1, FACE_SETS.size()) - 1]
	var keys := ["b01b%02d" % clampi(int(face.get("bg", 1)), 1, 12)]
	for pair in [["c", "neck"], ["f", "shape"], ["e", "brow"], ["h", "hair"]]:
		keys.append("%s%s%02d" % [grp, pair[0], clampi(int(face.get(pair[1], 1)), 1, 3)])
	var out: Array = []
	for k in keys:
		var t := _tex("face_layers", k)
		if t != null:
			out.append(t)
	return out


# 臉譜合成圖 (4x = 288x320): 疊層後喺眉眼下面程序畫鼻/口/鬚 (原版冇呢三層)；key 同 face 一樣就用 cache
const FACE_SS := 4
static var _face_cache: Dictionary = {}


static func face_image(face: Dictionary) -> Texture2D:
	var ck := JSON.stringify(face)
	if _face_cache.has(ck):
		return _face_cache[ck]
	var layers := face_layers(face)
	if layers.is_empty():
		return null
	var img := Image.create(72 * FACE_SS, 80 * FACE_SS, false, Image.FORMAT_RGBA8)
	for t in layers:
		var li: Image = (t as Texture2D).get_image().duplicate()
		li.convert(Image.FORMAT_RGBA8)
		li.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_BILINEAR)
		img.blend_rect(li, Rect2i(Vector2i.ZERO, li.get_size()), Vector2i.ZERO)
	_draw_face_features(face, img)
	var tex := ImageTexture.create_from_image(img)
	_face_cache[ck] = tex
	return tex


static func _draw_face_features(face: Dictionary, img: Image) -> void:
	var grp: String = FACE_SETS[clampi(int(face.get("set", 1)), 1, FACE_SETS.size()) - 1]
	var et := _tex("face_layers", "%se%02d" % [grp, clampi(int(face.get("brow", 1)), 1, 3)])
	var ft := _tex("face_layers", "%sf%02d" % [grp, clampi(int(face.get("shape", 1)), 1, 3)])
	if et == null or ft == null:
		return
	var eb: Rect2i = (et as Texture2D).get_image().get_used_rect()
	var ss := FACE_SS
	var cx := (eb.position.x + eb.end.x) * 0.5 * ss
	var ey := eb.end.y * ss
	var fi: Image = (ft as Texture2D).get_image()
	var skin := fi.get_pixel(clampi(int(cx / ss), 0, 71), clampi(int(ey / ss) + 6, 0, 79))
	if skin.a < 0.5:
		skin = Color(0.93, 0.72, 0.6)
	skin.a = 1.0
	var dark := skin.darkened(0.3)
	var lip := Color(0.7, 0.28, 0.25).lerp(skin, 0.25)
	var nw: float = [2.2, 3.0, 3.8][clampi(int(face.get("nose", 1)), 1, 3) - 1]
	var ny := ey + 9.0 * ss
	_fdot_line(img, Vector2(cx, ny - 5.0 * ss), Vector2(cx - 0.4 * ss, ny), dark, 0.6 * ss, 0.3)   # 鼻樑影
	_fdot_line(img, Vector2(cx - nw * ss, ny + 0.5 * ss), Vector2(cx + nw * ss, ny + 0.5 * ss), dark, 0.8 * ss, 0.45)
	_fdot_line(img, Vector2(cx - nw * ss * 0.6, ny + 1.6 * ss), Vector2(cx - nw * ss * 0.4, ny + 1.6 * ss), dark.darkened(0.3), 0.5 * ss, 0.5)
	_fdot_line(img, Vector2(cx + nw * ss * 0.4, ny + 1.6 * ss), Vector2(cx + nw * ss * 0.6, ny + 1.6 * ss), dark.darkened(0.3), 0.5 * ss, 0.5)
	var mw: float = [4.5, 3.5, 5.5][clampi(int(face.get("mouth", 1)), 1, 3) - 1]
	var my := ey + 19.0 * ss
	var curve: float = [1.2, 0.0, -0.8][clampi(int(face.get("mouth", 1)), 1, 3) - 1] * ss
	var prev := Vector2(cx - mw * ss, my - curve)
	for i in range(1, 9):
		var t := i / 8.0
		var cur := Vector2(cx + (t * 2.0 - 1.0) * mw * ss, my - curve + curve * 1.0 * (1.0 - pow(2.0 * t - 1.0, 2.0)) * 1.0)
		_fdot_line(img, prev, cur, lip, 0.9 * ss, 0.7)
		prev = cur
	_fdot_line(img, Vector2(cx - mw * ss * 0.5, my + 1.2 * ss), Vector2(cx + mw * ss * 0.5, my + 1.2 * ss), dark, 0.7 * ss, 0.3)
	var bd := int(face.get("beard", 1))
	if bd >= 2 and grp.begins_with("b"):
		var hc := Color(0.12, 0.08, 0.06)
		if bd == 2:   # 八字鬚
			_fdot_line(img, Vector2(cx - 5.0 * ss, my - 2.5 * ss), Vector2(cx - 0.5 * ss, my - 3.2 * ss), hc, 0.9 * ss, 0.7)
			_fdot_line(img, Vector2(cx + 0.5 * ss, my - 3.2 * ss), Vector2(cx + 5.0 * ss, my - 2.5 * ss), hc, 0.9 * ss, 0.7)
		else:         # 山羊鬚
			_fdot_line(img, Vector2(cx, my + 3.0 * ss), Vector2(cx, my + 9.0 * ss), hc, 1.2 * ss, 0.7)


static func _fdot_line(img: Image, a: Vector2, b: Vector2, col: Color, r: float, alpha: float) -> void:
	var n := maxi(1, int(a.distance_to(b)))
	var ri := int(ceil(r))
	for i in n + 1:
		var c := a.lerp(b, float(i) / n)
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var d := sqrt(dx * dx + dy * dy)
				if d > r:
					continue
				var x := int(c.x) + dx
				var y := int(c.y) + dy
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				var base := img.get_pixel(x, y)
				if base.a < 0.5:
					continue
				var k := alpha * (1.0 - d / (r + 0.5))
				img.set_pixel(x, y, base.lerp(col, clampf(k, 0.0, 1.0)))


# 職業預覽: 面向鏡頭站立第一幀，Lv1 起手造型 (武 1 / 甲 1 / 臉譜髮)；疊序同遊戲內 (身 → 甲 → 髮 → 武)
static func player_preview(b: int, face: Dictionary) -> Array:
	var body := player_layer(b, 1, "b", 0)
	if body == null:
		return []
	var cw := body.get_width() / 8
	var chh := body.get_height() / 8
	var out: Array = []
	for t in [body, player_layer(b, 1, "a", 1), player_layer(b, 1, "h", hair_style(face)), player_layer(b, 1, "w", 1)]:
		if t != null:
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = Rect2(0, 4 * chh, cw, chh)
			out.append(at)
	return out


# 服裝預覽: 身 → 服裝甲 → 服裝髮 (冇就臉譜髮) → 武 1；面向鏡頭站立第一幀
static func costume_preview(b: int, face: Dictionary, cs: int) -> Array:
	var body := player_layer(b, 1, "b", 0)
	if body == null:
		return []
	var cw := body.get_width() / 8
	var chh := body.get_height() / 8
	var hair := player_layer(b, 1, "th", cs)
	if hair == null:
		hair = player_layer(b, 1, "h", hair_style(face))
	var out: Array = []
	for t in [body, player_layer(b, 1, "t", cs), hair, player_layer(b, 1, "w", 1)]:
		if t != null:
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = Rect2(0, 4 * chh, cw, chh)
			out.append(at)
	return out


# 音效檔路徑；冇索引回 ""
static func audio_path(name: String) -> String:
	_ensure()
	var t: Variant = _index.get("audio", {})
	if t is Dictionary and (t as Dictionary).has(name):
		return ROOT + str((t as Dictionary)[name])
	return ""


# 特效 strip: {tex, n, cw, ch, ax, ay}；冇圖回 {}
static func fx(name: String) -> Dictionary:
	_ensure()
	var t := _tex("fx", name)
	var m: Variant = (_index.get("_fx_meta", {}) as Dictionary).get(name)
	if t == null or not (m is Dictionary):
		return {}
	var r: Dictionary = (m as Dictionary).duplicate()
	r["tex"] = t
	return r


static func actor_sheet(sid: int, act: String) -> Texture2D:
	return _tex("actor_" + act, sid)


# 揀人形 sprite id: 名字有原版 sprite → 用；否則 role 對通用池 (按 seed 決定性揀)；0 = 冇圖
static func actor_sid(npc_name: String, role := "", seed := 0, class_id := "") -> int:
	_ensure()
	var bn: Variant = _index.get("_actor_by_name", {})
	if npc_name != "" and bn is Dictionary and (bn as Dictionary).has(npc_name):
		return int((bn as Dictionary)[npc_name])
	var pool: Variant = _index.get("_actor_pool", {})
	if not (pool is Dictionary):
		return 0
	if class_id != "":
		return int(((pool as Dictionary).get("player", {}) as Dictionary).get(class_id, 0))
	var key := "civ_m"
	match role:
		"guard": key = "soldier"
		"official": key = "elder"
		"merchant", "stableman", "villager": key = "civ_f" if seed % 3 == 0 else "civ_m"
	var arr: Array = (pool as Dictionary).get(key, [])
	if arr.is_empty():
		return 0
	return int(arr[seed % arr.size()])


# 原版 NPC (okm sprite 編號)：有圖就用；冇 (52xxx 圖包未搵到) → 通用人形，同編號永遠同一款
static func npc_sid(sprite: int, npc_name: String) -> int:
	_ensure()
	var s: Variant = _index.get("actor_S", {})
	if s is Dictionary and (s as Dictionary).has(str(sprite)):
		return sprite
	var pool: Variant = _index.get("_actor_pool", {})
	if not (pool is Dictionary):
		return 0
	var key := "civ_m"
	for w in ["老", "師", "公", "夫子", "長"]:
		if npc_name.contains(w):
			key = "elder"
	for w in ["婦", "嫂", "妹", "女"]:
		if npc_name.contains(w):
			key = "civ_f"
	var arr: Array = (pool as Dictionary).get(key, [])
	return 0 if arr.is_empty() else int(arr[sprite % arr.size()])


# UI 皮件: panel / card / btn_n / btn_p / btn_d
static func ui(key: String) -> Texture2D:
	return _tex("ui", key)


static func coverage() -> Dictionary:
	_ensure()
	var r := {}
	for k in _index:
		if not String(k).begins_with("_"):
			r[k] = (_index[k] as Dictionary).size()
	return r
