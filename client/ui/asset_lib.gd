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
