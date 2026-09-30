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
	return _tex("mon_" + act, mob_def)


# 人形 sprite (NPC/居民/武將/玩家): sheet 格式同怪物。sid = 原版 sprite id
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
