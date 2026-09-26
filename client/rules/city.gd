class_name RulesCity
extends RefCounted
# 城池屬性 (S08b, spec 08 §3) 純函數。8 項 0~100：
#   開墾 kaiken / 商業 shangye / 畜牧 xumu / 礦產 kuangchan /
#   鑄造 duanzao / 防禦 fangyu / 防災 fangzai / 治安 zhian
# 連動：防災 → 天災減弱；開墾/商業/畜牧/礦產 → 市場 prod；鑄造 → 商店貨單；
#       防禦 → 城門衛兵反應；治安 → 居民犯案率。
# cfg = data.world["cityAttrs"]（default/names/order/per/prodCats/shopGoods/...）。
# 城池屬性會隨時間變（官宅內政、義勇軍工作），所以真值存喺 sim state["cityAttrs"]；
# 呢度純函數只負責初始化 / 讀 / 換算。

const KEYS := ["kaiken", "shangye", "xumu", "kuangchan", "duanzao", "fangyu", "fangzai", "zhian"]


static func clamp_attr(v: Variant) -> int:
	return clampi(int(v), 0, 100)


static func _default(cfg: Dictionary) -> int:
	return clamp_attr(cfg.get("default", 50))


# 全部屬性 = default
static func defaults(cfg: Dictionary) -> Dictionary:
	var d := _default(cfg)
	var o := {}
	for k in KEYS:
		o[k] = d
	return o


# 由 world.json city 初始化（city.attrs 優先，缺 = default）
static func init_attrs(city: Dictionary, cfg: Dictionary) -> Dictionary:
	var o := defaults(cfg)
	var src: Dictionary = city.get("attrs", {})
	for k in o:
		if src.has(k):
			o[k] = clamp_attr(src[k])
	return o


static func attr_of(attrs: Dictionary, key: String, cfg: Dictionary) -> int:
	return clamp_attr(attrs.get(key, _default(cfg)))


# 屬性顯示名
static func name_of(cfg: Dictionary, key: String) -> String:
	return String((cfg.get("names", {}) as Dictionary).get(key, key))


# 市場 prod 連動：cat -> attr，倍率 = 1 + (attr − default) × per（default = 1.0）
static func prod_mult(attrs: Dictionary, cat: Variant, cfg: Dictionary) -> float:
	var key := String((cfg.get("prodCats", {}) as Dictionary).get(str(int(cat)), ""))
	if key == "":
		return 1.0
	return 1.0 + float(attr_of(attrs, key, cfg) - _default(cfg)) * float(cfg.get("per", 0.006))


# 天災減弱：防災度 0.0~1.0（防災 attr；冇 attrs 就用 city.defense 兼容舊行為）
static func disaster_mitigation(attrs: Dictionary, cfg: Dictionary, legacy_defense: float = 50.0) -> float:
	return float(attr_of(attrs, "fangzai", cfg)) / 100.0 if not attrs.is_empty() else legacy_defense / 100.0


# 鑄造 → 商店額外貨單：attr ≥ min 就賣嗰批貨
static func shop_extra_items(attrs: Dictionary, cfg: Dictionary) -> Array:
	var out: Array = []
	for e in cfg.get("shopGoods", []):
		if attr_of(attrs, String(e["attr"]), cfg) >= int(e["min"]):
			for it in e["items"]:
				if not out.has(int(it)):
					out.append(int(it))
	return out


# 防禦 → 城門衛兵警告間隔倍率（防禦 0 → ×1.5、50 → ×1.0、100 → ×0.5，即係城牆越好衛兵越密）
static func guard_warn_ticks(attrs: Dictionary, base: int, cfg: Dictionary) -> int:
	var a := attr_of(attrs, String(cfg.get("guardAttr", "fangyu")), cfg)
	return maxi(1, int(round(float(base) * (1.5 - float(a) / 100.0))))


# 治安 → 居民犯案率倍率（治安 0 → ×1.5、50 → ×1.0、100 → ×0.5）
static func crime_mult(attrs: Dictionary, cfg: Dictionary) -> float:
	var a := attr_of(attrs, String(cfg.get("crimeAttr", "zhian")), cfg)
	return maxf(0.1, 1.5 - float(a) / 100.0)


# 內政一次嘅屬性增量：base × 完成度倍率（倍率由 RulesExpert.domestic_mult + 武將協助合成），最少 1
static func attr_gain(base: int, mult: float) -> int:
	return maxi(1, int(round(float(base) * mult)))