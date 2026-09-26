class_name RulesMarket
extends RefCounted
# 動態市場純函數 (Step 4)【自訂】:
#   每城每類物資 (cat) 有 {stock, pf}: pf = 價格因子 [min..max]。
#   每日: stock += 供給 - 需求 (下限 0, 上限 stockCap×vol)
#         pf' = pf × (1 - stockSens×庫存偏差 - flowSens×供需差/vol)，再慢速回歸 1 (drift)
#   店鋪價 = 基準價 × pf (魅力折扣另計)。
# 供給/需求 = 每 100 人口基準 × 人口/100 × 季節/天災修正。全部確定性 (無 rng)。


static func step(good: Dictionary, m: Dictionary, supply: float, demand: float, cfg: Dictionary) -> void:
	var vol := float(good["vol"])
	var stock := float(m["stock"]) + supply - demand
	stock = maxf(0.0, minf(stock, vol * float(cfg.get("stockCap", 20.0))))
	var bal := (stock - vol) / vol
	var flow := (supply - demand) / vol
	var pf := float(m["pf"]) * (1.0 - float(cfg.get("stockSens", 0.05)) * bal - float(cfg.get("flowSens", 0.02)) * flow)
	pf = pf + float(cfg.get("drift", 0.02)) * (1.0 - pf)      # 慢速回歸 1，防長期偏離
	pf = minf(float(cfg["maxFactor"]), maxf(float(cfg["minFactor"]), pf))
	m["stock"] = stock
	m["pf"] = pf


static func daily(city: Dictionary, markets: Dictionary, cfg: Dictionary, supply_mod: Dictionary = {}, demand_mod: Dictionary = {}, attr_cfg: Dictionary = {}) -> void:
	# markets: cat(String) -> {stock, pf}；city: {pop, defense, attrs?}；mod: cat -> 倍率
	# attr_cfg (S08b) = world.cityAttrs：城池屬性「開墾/商業/畜牧/礦產」影響供應 prod
	var pop_scale := float(city["pop"]) / 100.0
	var cats: Dictionary = cfg["cats"]
	var attrs: Dictionary = city.get("attrs", {})
	for key in cats:
		var g: Dictionary = cats[key]
		var m: Dictionary = markets.get(key, {})
		if m.is_empty():
			m = {"stock": float(g["vol"]), "pf": 1.0}
		var sup := float(g["prod"]) * pop_scale * float(supply_mod.get(key, 1.0))
		if not attr_cfg.is_empty():
			sup *= RulesCity.prod_mult(attrs, key, attr_cfg)
		var dem := float(g["demand"]) * pop_scale * float(demand_mod.get(key, 1.0))
		var el := elasticity(g, m, sup, dem, cfg)          # 價格反饋
		step(g, m, el.x, el.y, cfg)
		markets[key] = m


# 買入價 (魅力折扣另計，RulesShop)
static func price(base: float, pf: float) -> int:
	return maxi(1, MathX.js_round(base * pf))


# 賣出價 = 市場價 × 50%【原】
static func sell_price(base: float, pf: float) -> int:
	return int(floor(base * pf * 0.5))


# 供/需修正: 由季節 + 天災合成. 回傳 {cat(Str) -> float}
static func supply_mods(season: int, seasons: Dictionary, disasters: Array, city: Dictionary) -> Dictionary:
	var out := {}
	var sm: Dictionary = seasons.get(str(season), {})
	for k in sm:
		out[k] = float(sm[k])
	for d in disasters:
		for k in d["supply"]:
			var f := float(d["supply"][k])
			if f < 1.0:
				# 防災度減輕 (S08b): 城池 attrs.fangzai；冇 attrs → 舊 defense 欄
				f = 1.0 - (1.0 - f) * (1.0 - RulesCity.disaster_mitigation(city.get("attrs", {}), {}, float(city.get("defense", 50.0))))
			var cur := float(out.get(k, 1.0))
			out[k] = cur * f
	return out


static func demand_mods(season: int, seasons: Dictionary) -> Dictionary:
	return seasons.get(str(season), {})


# 價格彈性: 價高 → 生產增/消費減，價低反之 → 自穩定 (防暴走)
static func elasticity(good: Dictionary, m: Dictionary, supply: float, demand: float, cfg: Dictionary) -> Vector2:
	var pf := float(m["pf"])
	var es := float(cfg.get("supplyElast", 0.2))
	var ed := float(cfg.get("demandElast", 0.25))
	return Vector2(supply * pow(pf, es), demand * pow(1.0 / pf, ed))